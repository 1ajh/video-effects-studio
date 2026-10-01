import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/audio_buffer.dart';
import '../audio/dsp.dart';
import '../audio/psola.dart';
import 'model.dart';

/// A finished, playable sample plus where it came from (for the visuals).
class ProcessedSample {
  ProcessedSample({
    required this.role,
    required this.audio,
    required this.candidate,
    required this.sourcePath,
    this.rootHz = 0,
    this.naturalSeconds = 0,
  });

  final SampleRole role;

  /// Word samples: the line's word / syllable this is ('1', '3A'…).
  String get slot => candidate.slot;

  /// Mono, 48 kHz. Pitch samples are sustained (several seconds long).
  final Float32List audio;
  final SampleCandidate candidate;
  final String sourcePath;

  /// Frequency the pitch sample was tuned to (the base's root note).
  final double rootHz;

  /// Length of the original material before sustain.
  final double naturalSeconds;

  static const sampleRate = 48000;
}

/// How the pitch sample is tuned to the base's key.
enum PitchTuning {
  hard('Hard-tuned', 'Flat on the note: the classic Sparta pitch'),
  natural('Natural', "On the note, keeping the voice's own wobble");

  const PitchTuning(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// A pitch candidate the tuner can't follow (no steady pitch to tune):
/// it's skipped rather than used off-key.
class UntunableSample implements Exception {
  UntunableSample(this.candidate);
  final SampleCandidate candidate;
  @override
  String toString() => 'That pitch sample has no steady pitch to tune — pick another one.';
}

/// Options for sample enhancement.
class EnhanceOptions {
  const EnhanceOptions({
    this.chorusCrisp = true,
    this.layerDrums = false,
    this.sustainSeconds = 4.0,
    this.forceOctave,
    this.tuning = PitchTuning.hard,
    this.bassOctave = 2,
  });

  /// Doubled-attack splice on chorus words (the Chorus Crisp technique: it
  /// edits the word itself, nothing is added).
  final bool chorusCrisp;

  /// Layer a synthesized body under the percussion. Off by default: sound
  /// that isn't from the source is a "fake sample".
  final bool layerDrums;

  /// How long pitch samples can be held.
  final double sustainSeconds;

  /// Force the pitch sample's octave (2..5); null picks the nearest.
  final int? forceOctave;
  final PitchTuning tuning;

  /// Octave of the bass sample's root (2: D2 for a D base).
  final int bassOctave;

  EnhanceOptions copyWith({
    bool? chorusCrisp,
    bool? layerDrums,
    double? sustainSeconds,
    int? forceOctave,
    bool clearOctave = false,
    PitchTuning? tuning,
    int? bassOctave,
  }) => EnhanceOptions(
    chorusCrisp: chorusCrisp ?? this.chorusCrisp,
    layerDrums: layerDrums ?? this.layerDrums,
    sustainSeconds: sustainSeconds ?? this.sustainSeconds,
    forceOctave: clearOctave ? null : (forceOctave ?? this.forceOctave),
    tuning: tuning ?? this.tuning,
    bassOctave: bassOctave ?? this.bassOctave,
  );

  String get key => '$chorusCrisp|$layerDrums|$sustainSeconds|$forceOctave|${tuning.name}|$bassOctave';
}

/// Turns raw candidate audio into Sparta-ready instruments. Every sample is
/// edited from its own audio only (EQ, dynamics, tuning, Chorus Crisp);
/// nothing from elsewhere is mixed in unless [EnhanceOptions.layerDrums]
/// is switched on.
class SampleEnhancer {
  SampleEnhancer({this.options = const EnhanceOptions(), this.rootPc = 2, int seed = 7}) : _rng = math.Random(seed);

  final EnhanceOptions options;

  /// Pitch class of the base's root (0 = C … 11 = B): the pitch sample is
  /// tuned to it, so the base's notes play in key.
  final int rootPc;
  final math.Random _rng;
  static const sr = ProcessedSample.sampleRate;

  ProcessedSample process(SampleCandidate c, AudioBuffer raw, String sourcePath) {
    final mono = raw.mono().data;
    final x = Float32List.fromList(mono);
    switch (c.role) {
      case SampleRole.pitch:
        return _pitch(c, x, sourcePath);
      case SampleRole.bass:
        return _bass(c, x, sourcePath);
      case SampleRole.pad:
        return _pad(c, x, sourcePath);
      case SampleRole.word:
        return _word(c, x, sourcePath);
      case SampleRole.kick:
        return _kick(c, x, sourcePath);
      case SampleRole.snare:
        return _snare(c, x, sourcePath);
      case SampleRole.hat:
        return _hat(c, x, sourcePath);
      case SampleRole.quote:
        return _quote(c, x, sourcePath);
    }
  }

  ProcessedSample _pitch(SampleCandidate c, Float32List x, String src) {
    Biquad.highPass(sr.toDouble(), 90).process(x);
    var body = trimSilence(x, sr, thresholdDb: -38);
    if (body.isEmpty) body = x;
    final natural = body.length / sr;
    final o = options.forceOctave;
    final corrected = psolaCorrect(
      body,
      sr,
      targetHz: o == null ? null : 440 * math.pow(2, (12 * (o + 1) + rootPc - 69) / 12).toDouble(),
      pitchClass: rootPc,
      lengthSeconds: math.max(natural, options.sustainSeconds),
      follow: options.tuning == PitchTuning.natural ? 1 : 0,
    );
    if (corrected == null) throw UntunableSample(c);
    final out = corrected.audio;
    // Gentle presence and a little glue.
    Biquad.peak(sr.toDouble(), 3000, 2.5, q: 0.8).process(out);
    compress(out, sr, thresholdDb: -20, ratio: 3, attackMs: 3, releaseMs: 80);
    fade(out, sr, inMs: 1.5, outMs: 30);
    _normalize(out, 0.9);
    return ProcessedSample(
      role: c.role,
      audio: out,
      candidate: c,
      sourcePath: src,
      rootHz: corrected.targetHz,
      naturalSeconds: natural,
    );
  }

  /// The bass sample: the voice re-pitched down to the root in the bass
  /// register (D2 for a D base) with its formants lowered a little, so it
  /// sounds like a giant singing the bass line.
  ProcessedSample _bass(SampleCandidate c, Float32List x, String src) {
    Biquad.highPass(sr.toDouble(), 70).process(x);
    var body = trimSilence(x, sr, thresholdDb: -38);
    if (body.isEmpty) body = x;
    final natural = body.length / sr;
    final midi = 12 * (options.bassOctave + 1) + rootPc;
    final corrected = psolaCorrect(
      body,
      sr,
      targetHz: 440 * math.pow(2, (midi - 69) / 12).toDouble(),
      pitchClass: rootPc,
      lengthSeconds: math.max(natural, options.sustainSeconds),
      formant: 0.85,
    );
    if (corrected == null) throw UntunableSample(c);
    final out = corrected.audio;
    Biquad.lowPass(sr.toDouble(), 2600).process(out);
    Biquad.lowShelf(sr.toDouble(), 140, 4).process(out);
    saturate(out, drive: 1.3);
    compress(out, sr, thresholdDb: -18, ratio: 3, attackMs: 4, releaseMs: 90);
    fade(out, sr, inMs: 2, outMs: 30);
    _normalize(out, 0.9);
    return ProcessedSample(
      role: c.role,
      audio: out,
      candidate: c,
      sourcePath: src,
      rootHz: corrected.targetHz,
      naturalSeconds: natural,
    );
  }

  /// The pad: the vowel held and smoothed into a soft sustained tone on the
  /// root (chords stack it), darkened like a stretched pad sample.
  ProcessedSample _pad(SampleCandidate c, Float32List x, String src) {
    Biquad.highPass(sr.toDouble(), 120).process(x);
    var body = trimSilence(x, sr, thresholdDb: -38);
    if (body.isEmpty) body = x;
    final natural = body.length / sr;
    final o = options.forceOctave;
    final corrected = psolaCorrect(
      body,
      sr,
      targetHz: o == null ? null : 440 * math.pow(2, (12 * (o + 1) + rootPc - 69) / 12).toDouble(),
      pitchClass: rootPc,
      lengthSeconds: math.max(natural, options.sustainSeconds * 1.5),
    );
    if (corrected == null) throw UntunableSample(c);
    final out = corrected.audio;
    Biquad.lowPass(sr.toDouble(), 2900).process(out);
    Biquad.lowPass(sr.toDouble(), 2900).process(out);
    compress(out, sr, thresholdDb: -24, ratio: 2.5, attackMs: 20, releaseMs: 200);
    fade(out, sr, inMs: 60, outMs: 250);
    _normalize(out, 0.85);
    return ProcessedSample(
      role: c.role,
      audio: out,
      candidate: c,
      sourcePath: src,
      rootHz: corrected.targetHz,
      naturalSeconds: natural,
    );
  }

  /// A chorus word: raw (not tuned), cleaned up, optionally Chorus Crisp.
  ProcessedSample _word(SampleCandidate c, Float32List x, String src) {
    Biquad.highPass(sr.toDouble(), 70).process(x);
    var out = x;
    if (options.chorusCrisp) out = chorusCrisp(out, sr);
    Biquad.peak(sr.toDouble(), 3500, 2, q: 0.9).process(out);
    compress(out, sr, thresholdDb: -20, ratio: 3, attackMs: 2, releaseMs: 70);
    fade(out, sr, inMs: 1, outMs: 8);
    _normalize(out, 0.9);
    return ProcessedSample(role: c.role, audio: out, candidate: c, sourcePath: src, naturalSeconds: x.length / sr);
  }

  ProcessedSample _kick(SampleCandidate c, Float32List x, String src) {
    final hit = _cut(x, 0.35);
    Biquad.lowShelf(sr.toDouble(), 120, 6).process(hit);
    Biquad.highPass(sr.toDouble(), 30).process(hit);
    _shapeTransient(hit, attackGain: 1.6, sustainDb: -8);
    var out = hit;
    if (options.layerDrums) {
      final sub = _synthKick(0.35);
      out = _layer(hit, sub, 0.75);
    }
    saturate(out, drive: 1.6);
    fade(out, sr, inMs: 0.5, outMs: 30);
    _normalize(out, 0.95);
    return ProcessedSample(role: c.role, audio: out, candidate: c, sourcePath: src, naturalSeconds: hit.length / sr);
  }

  ProcessedSample _snare(SampleCandidate c, Float32List x, String src) {
    final hit = _cut(x, 0.28);
    Biquad.highPass(sr.toDouble(), 140).process(hit);
    Biquad.peak(sr.toDouble(), 220, 4, q: 1.2).process(hit);
    Biquad.peak(sr.toDouble(), 3500, 5, q: 0.7).process(hit);
    _shapeTransient(hit, attackGain: 1.8, sustainDb: -5);
    var out = hit;
    if (options.layerDrums) out = _layer(hit, _synthSnareTail(0.25), 0.45);
    saturate(out, drive: 1.4);
    fade(out, sr, inMs: 0.5, outMs: 25);
    _normalize(out, 0.9);
    return ProcessedSample(role: c.role, audio: out, candidate: c, sourcePath: src, naturalSeconds: hit.length / sr);
  }

  ProcessedSample _hat(SampleCandidate c, Float32List x, String src) {
    final hit = _cut(x, 0.12);
    Biquad.highPass(sr.toDouble(), 5000).process(hit);
    Biquad.highPass(sr.toDouble(), 5000).process(hit);
    var out = hit;
    // Speech is often dull up top: add a short noise tick so hats cut through.
    if (options.layerDrums) out = _layer(hit, _synthHat(0.06), 0.5);
    _decay(out, 0.07);
    fade(out, sr, inMs: 0.3, outMs: 10);
    _normalize(out, 0.7);
    return ProcessedSample(role: c.role, audio: out, candidate: c, sourcePath: src, naturalSeconds: hit.length / sr);
  }

  ProcessedSample _quote(SampleCandidate c, Float32List x, String src) {
    Biquad.highPass(sr.toDouble(), 80).process(x);
    compress(x, sr, thresholdDb: -24, ratio: 2.5, attackMs: 8, releaseMs: 150);
    fade(x, sr, inMs: 5, outMs: 40);
    _normalize(x, 0.85);
    return ProcessedSample(role: c.role, audio: x, candidate: c, sourcePath: src, naturalSeconds: x.length / sr);
  }

  // ---------------------------------------------------------------------------

  /// Splits a word 35 ms in, pulls the second part back so the attack
  /// doubles, crossfades and ducks it 3 dB ("Chorus Crisp", Standard preset).
  static Float32List chorusCrisp(
    Float32List x,
    int sampleRate, {
    double spliceMs = 35,
    double overlap = 0.9,
    double duckDb = -3,
  }) {
    final splice = (spliceMs * sampleRate / 1000).round();
    if (x.length < splice * 3) return x;
    final back = math.max(1, (splice * overlap).round());
    final start = splice - back; // where the second part now begins
    final out = Float32List(x.length - back);
    final duck = dbToGain(duckDb);
    // First part: the untouched attack, fading out across the overlap.
    for (var i = 0; i < splice; i++) {
      final g = i < start ? 1.0 : 1 - (i - start) / back;
      out[i] += x[i] * g;
    }
    // Second part: pulled back over the attack, ducked, fading in.
    for (var j = 0; splice + j < x.length; j++) {
      final o = start + j;
      if (o >= out.length) break;
      final g = j < back ? j / back : 1.0;
      out[o] += x[splice + j] * duck * g;
    }
    return out;
  }

  Float32List _cut(Float32List x, double maxSeconds) {
    final n = math.min(x.length, (maxSeconds * sr).round());
    return Float32List.fromList(x.sublist(0, n));
  }

  /// Boosts the first few ms and tightens the tail.
  void _shapeTransient(Float32List x, {required double attackGain, required double sustainDb}) {
    final atk = (0.006 * sr).round();
    final sus = dbToGain(sustainDb);
    for (var i = 0; i < x.length; i++) {
      final g = i < atk ? attackGain : sus + (1 - sus) * math.exp(-(i - atk) / (0.04 * sr));
      x[i] *= g;
    }
  }

  void _decay(Float32List x, double tau) {
    for (var i = 0; i < x.length; i++) {
      x[i] *= math.exp(-i / (tau * sr));
    }
  }

  Float32List _layer(Float32List a, Float32List b, double bGain) {
    final aPeak = _peak(a), bPeak = _peak(b);
    final out = Float32List(math.max(a.length, b.length));
    for (var i = 0; i < out.length; i++) {
      final va = i < a.length ? a[i] / (aPeak + 1e-9) : 0.0;
      final vb = i < b.length ? b[i] / (bPeak + 1e-9) : 0.0;
      out[i] = va + vb * bGain;
    }
    return out;
  }

  Float32List _synthKick(double seconds) {
    final n = (seconds * sr).round();
    final out = Float32List(n);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final f = 48 + 130 * math.exp(-t / 0.03);
      phase += 2 * math.pi * f / sr;
      out[i] = math.sin(phase) * math.exp(-t / 0.22);
    }
    return out;
  }

  Float32List _synthSnareTail(double seconds) {
    final n = (seconds * sr).round();
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = (_rng.nextDouble() * 2 - 1) * math.exp(-i / (0.09 * sr));
    }
    Biquad.bandPass(sr.toDouble(), 2500, q: 0.6).process(out);
    return out;
  }

  Float32List _synthHat(double seconds) {
    final n = (seconds * sr).round();
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = (_rng.nextDouble() * 2 - 1) * math.exp(-i / (0.018 * sr));
    }
    Biquad.highPass(sr.toDouble(), 7000).process(out);
    return out;
  }

  static double _peak(Float32List x) => x.fold<double>(0, (p, v) => math.max(p, v.abs()));

  static void _normalize(Float32List x, double target) {
    final p = _peak(x);
    if (p < 1e-9) return;
    final g = target / p;
    for (var i = 0; i < x.length; i++) {
      x[i] *= g;
    }
  }
}
