import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/audio_buffer.dart';
import '../audio/dsp.dart';
import '../audio/psola.dart';
import '../audio/synth.dart';
import 'base.dart';
import 'model.dart';
import 'sample_processing.dart';

/// Master bus flavour.
enum MasterMode {
  clean('Clean', 'Glued and limited: loud but clean (about −10 LUFS, −1 dB peak)'),
  hot('Hot', 'Classic loud Sparta master: pushed into soft clipping');

  const MasterMode(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// How the pitched samples (pitch, bass, pads) are moved to each note.
enum PitchRender {
  stretch(
    'Stretch',
    "Re-pitched with its length kept, like FL Studio's stretch mode: no chipmunk voices, every note as long as written",
  ),
  resample(
    'Resample + crossfades',
    'Sped up or slowed down like a sampler (pitch and speed change together), with automatic crossfades between notes',
  );

  const PitchRender(this.label, this.blurb);
  final String label;
  final String blurb;
}

class MixSettings {
  const MixSettings({
    this.master = MasterMode.clean,
    this.baseDb = 0,
    this.laneDb = const {},
    this.reverb = 0.12,
    this.quoteDuckDb = 5,
    this.pitchRender = PitchRender.stretch,
  });

  final MasterMode master;
  final PitchRender pitchRender;
  final double baseDb;
  final Map<SampleRole, double> laneDb;

  /// Reverb send on the pitch / word buses (0..1).
  final double reverb;

  /// How far the base dips under the quote.
  final double quoteDuckDb;

  MixSettings copyWith({
    MasterMode? master,
    double? baseDb,
    Map<SampleRole, double>? laneDb,
    double? reverb,
    PitchRender? pitchRender,
  }) => MixSettings(
    master: master ?? this.master,
    baseDb: baseDb ?? this.baseDb,
    laneDb: laneDb ?? this.laneDb,
    reverb: reverb ?? this.reverb,
    quoteDuckDb: quoteDuckDb,
    pitchRender: pitchRender ?? this.pitchRender,
  );
}

/// A sample hit on the remix timeline (also what the visuals are cut from).
class PlacedEvent {
  const PlacedEvent({
    required this.role,
    required this.variant,
    required this.beat,
    required this.start,
    required this.duration,
    required this.rate,
    required this.semitone,
    required this.velocity,
    required this.sectionIndex,
    required this.laneIndex,
    this.slot = '',
  });

  final SampleRole role;

  /// Word hits: the word / syllable key that played ('1', '3A'…).
  final String slot;

  /// Which of the role's samples played (multiple sources alternate).
  final int variant;
  final double beat;

  /// Seconds on the remix timeline.
  final double start;
  final double duration;

  /// Playback-rate multiplier (sampler transposition: pitch and speed);
  /// 1 for stretched notes, which keep their speed.
  final double rate;
  final int semitone;
  final double velocity;
  final int sectionIndex;

  /// Running index of this hit within its lane (for alternating flips).
  final int laneIndex;

  double get end => start + duration;
}

/// Stems written next to the master.
enum Stem { base, pitch, bass, pads, words, drums, quote }

class RemixMix {
  RemixMix({required this.master, required this.stems, required this.events, required this.lufs, required this.peakDb});
  final AudioBuffer master;
  final Map<Stem, AudioBuffer> stems;
  final List<PlacedEvent> events;
  final double lufs;
  final double peakDb;
  double get duration => master.duration;
}

/// Places processed samples on a base's chart and mixes/masters the remix.
///
/// Pure Dart and synchronous (run it in an isolate from the UI).
class Arranger {
  Arranger({
    required this.base,
    required this.samples,
    this.baseAudio,
    this.settings = const MixSettings(),
    this.sampleRate = 48000,
    this.shuffleSamples = false,
    this.seed = 1,
  });

  final SpartaBase base;

  /// Stereo base instrumental at [sampleRate] (null: samples only).
  final AudioBuffer? baseAudio;

  /// Playable samples per role; several pitch / percussion samples
  /// alternate by section, word samples are picked by their slot.
  final Map<SampleRole, List<ProcessedSample>> samples;
  final MixSettings settings;
  final int sampleRate;

  /// Random mode: which of a role's samples plays changes per section.
  final bool shuffleSamples;
  final int seed;

  static const _laneGain = {
    SampleRole.pitch: 0.52,
    SampleRole.bass: 0.5,
    SampleRole.pad: 0.2,
    SampleRole.word: 0.5,
    SampleRole.kick: 0.5,
    SampleRole.snare: 0.42,
    SampleRole.hat: 0.22,
    SampleRole.quote: 0.75,
  };

  /// The remix ends with the base: its music plus a short ring-out (the
  /// base's own tail, when it has audio).
  double get _length {
    final end = base.durationSeconds;
    final chartEnd = base.chart.fold<double>(0, (m, n) => math.max(m, base.seconds(n.end)));
    var len = math.max(end, chartEnd) + 1.0;
    final a = baseAudio;
    if (a != null) len = math.max(len, math.min(a.duration - base.audioOffset, end + 3.0));
    return len;
  }

  bool _stretched(SampleRole role) => role.isPitched && settings.pitchRender == PitchRender.stretch;

  /// Schedules every chart note: which sample, when, how long, what rate.
  List<PlacedEvent> schedule() {
    final events = <PlacedEvent>[];
    for (final role in SampleRole.values) {
      final list = samples[role];
      if (list == null || list.isEmpty) continue;
      final lane = base.lane(role)..sort((a, b) => a.beat.compareTo(b.beat));
      for (var i = 0; i < lane.length; i++) {
        final n = lane[i];
        // Choke: a new hit on the lane (at a later beat) cuts this one.
        var next = double.infinity;
        for (var j = i + 1; j < lane.length; j++) {
          if (lane[j].beat > n.beat + 1e-6) {
            next = lane[j].beat;
            break;
          }
        }
        final sectionIndex = _sectionIndex(n.beat);
        final int variant;
        if (role == SampleRole.word) {
          final key = wordKeyFor(n.slot.isEmpty ? '1' : n.slot, [for (final s in list) s.slot]);
          final at = list.indexWhere((s) => s.slot == key);
          if (at < 0) continue;
          variant = at;
        } else if (shuffleSamples && list.length > 1) {
          variant = math.Random(seed * 7919 + sectionIndex * 104729 + role.index).nextInt(list.length);
        } else {
          variant = switch (role) {
            SampleRole.pitch || SampleRole.quote => sectionIndex % list.length,
            _ => (sectionIndex ~/ 2) % list.length,
          };
        }
        final sample = list[variant];
        final stretch = _stretched(role);
        final rate = stretch ? 1.0 : math.pow(2, n.semitone / 12).toDouble();
        final natural = sample.audio.length / sampleRate / rate;
        final lengthBeats = role.isPercussion ? math.min(next - n.beat, 4.0) : math.min(n.length, next - n.beat);
        final seconds = math.min(natural, base.seconds(lengthBeats));
        if (seconds <= 0.005) continue;
        events.add(
          PlacedEvent(
            role: role,
            variant: variant,
            beat: n.beat,
            start: base.seconds(n.beat),
            duration: seconds,
            rate: rate,
            semitone: n.semitone,
            velocity: n.velocity,
            sectionIndex: sectionIndex,
            laneIndex: i,
            slot: role == SampleRole.word ? sample.slot : '',
          ),
        );
      }
    }
    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  int _sectionIndex(double beat) {
    for (var i = 0; i < base.sections.length; i++) {
      if (base.sections[i].contains(beat)) return i;
    }
    return math.max(0, base.sections.length - 1);
  }

  RemixMix mix({bool stems = true}) {
    final frames = (_length * sampleRate).ceil();
    final events = schedule();
    final laneBus = {for (final r in SampleRole.values) r: Float32List(frames * 2)};
    final cache = <String, Float32List>{};
    final resampled = settings.pitchRender == PitchRender.resample;
    // Resample mode crossfades pitched notes into each other; otherwise a
    // short release just de-clicks the cut.
    int releaseOf(SampleRole r) => ((r.isPitched && resampled ? 0.025 : 0.012) * sampleRate).round();
    int attackOf(SampleRole r) => r.isPitched && resampled ? (0.006 * sampleRate).round() : 24;
    String keyOf(PlacedEvent e) => _stretched(e.role) && e.semitone != 0
        ? '${e.role.index}/${e.variant}/s${e.semitone}'
        : '${e.role.index}/${e.variant}/${e.rate.toStringAsFixed(5)}';

    // How much of each voice the notes need (stretched voices are rendered once).
    final needs = <String, int>{};
    for (final e in events) {
      final k = keyOf(e);
      needs[k] = math.max(needs[k] ?? 0, (e.duration * sampleRate).round() + releaseOf(e.role));
    }

    for (final e in events) {
      final sample = samples[e.role]![e.variant];
      final release = releaseOf(e.role);
      final key = keyOf(e);
      var voice = cache[key];
      if (voice == null) {
        final needed = needs[key]!;
        if (_stretched(e.role) && e.semitone != 0) {
          voice = _stretchVoice(sample, e.semitone, needed);
        } else if ((e.rate - 1).abs() < 1e-6) {
          voice = Float32List.fromList(sample.audio.sublist(0, math.min(sample.audio.length, needed)));
        } else {
          voice = resample(sample.audio, e.rate, sampleRate: sampleRate, maxFrames: needed);
        }
        cache[key] = voice;
      }
      final body = math.min(voice.length, (e.duration * sampleRate).round());
      final len = math.min(voice.length, body + release);
      final hit = Float32List.fromList(voice.sublist(0, len));
      // Attack de-click and a release fade where the note is cut (in resample
      // mode long enough to crossfade into the next note).
      final attack = attackOf(e.role);
      for (var i = 0; i < math.min(attack, hit.length); i++) {
        hit[i] *= i / attack;
      }
      for (var i = body; i < len; i++) {
        hit[i] *= 1 - (i - body) / math.max(1, len - body);
      }
      final gain = _laneGain[e.role]! * dbToGain(settings.laneDb[e.role] ?? 0) * (0.35 + 0.65 * e.velocity);
      final pan = switch (e.role) {
        SampleRole.hat => 0.3,
        SampleRole.pad => const [-0.35, 0.35, 0.0][e.semitone.abs() % 3],
        _ => 0.0,
      };
      mixInto(laneBus[e.role]!, hit, (e.start * sampleRate).round(), gain: gain, pan: pan);
    }

    // Bus processing ----------------------------------------------------------
    final sr = sampleRate.toDouble();
    final pitch = laneBus[SampleRole.pitch]!;
    _eq(pitch, [Biquad.highPass(sr, 90), Biquad.peak(sr, 3000, 2.5, q: 0.8)]);
    compress(pitch, sampleRate, channels: 2, thresholdDb: -20, ratio: 3, attackMs: 3, releaseMs: 90, makeupDb: 3);
    _haas(pitch, 0.012, -9);

    final bass = laneBus[SampleRole.bass]!;
    _eq(bass, [Biquad.highPass(sr, 32), Biquad.lowShelf(sr, 110, 2), Biquad.lowPass(sr, 3200)]);
    compress(bass, sampleRate, channels: 2, thresholdDb: -18, ratio: 4, attackMs: 5, releaseMs: 100, makeupDb: 3);

    final pads = laneBus[SampleRole.pad]!;
    _eq(pads, [Biquad.highPass(sr, 160), Biquad.lowPass(sr, 3500)]);
    compress(pads, sampleRate, channels: 2, thresholdDb: -22, ratio: 2, attackMs: 30, releaseMs: 250, makeupDb: 2);
    _haas(pads, 0.018, -6);

    final words = laneBus[SampleRole.word]!;
    _eq(words, [Biquad.highPass(sr, 100), Biquad.peak(sr, 4000, 2, q: 0.9)]);
    compress(words, sampleRate, channels: 2, thresholdDb: -18, ratio: 4, attackMs: 1, releaseMs: 60, makeupDb: 2);

    final drums = Float32List(frames * 2);
    for (final r in const [SampleRole.kick, SampleRole.snare, SampleRole.hat]) {
      final x = laneBus[r]!;
      for (var i = 0; i < drums.length; i++) {
        drums[i] += x[i];
      }
    }
    compress(drums, sampleRate, channels: 2, thresholdDb: -14, ratio: 3, attackMs: 8, releaseMs: 80, makeupDb: 2);

    final quote = laneBus[SampleRole.quote]!;
    _eq(quote, [Biquad.highPass(sr, 80)]);
    compress(quote, sampleRate, channels: 2, thresholdDb: -22, ratio: 3, attackMs: 5, releaseMs: 150, makeupDb: 4);

    // Shared reverb for the tonal samples.
    if (settings.reverb > 0) {
      final send = Float32List(frames * 2);
      for (var i = 0; i < send.length; i++) {
        send[i] = (pitch[i] + words[i] * 0.5 + pads[i] * 1.5) * settings.reverb;
      }
      final wet = Reverb(sampleRate: sampleRate, room: 0.7, damp: 0.45).process(send);
      for (var i = 0; i < wet.length; i++) {
        pitch[i] += wet[i] * 3;
      }
    }

    // Base, ducked under the quote.
    final baseBus = Float32List(frames * 2);
    final a = baseAudio;
    if (a != null) {
      final st = a.channels == 2 ? a : a.stereo();
      final offset = (base.audioOffset * sampleRate).round();
      final g = 0.8 * dbToGain(settings.baseDb);
      for (var f = 0; f < frames; f++) {
        final src = f + offset;
        if (src < 0 || src >= st.frames) continue;
        baseBus[2 * f] = st.data[2 * src] * g;
        baseBus[2 * f + 1] = st.data[2 * src + 1] * g;
      }
      if (settings.quoteDuckDb > 0) _duck(baseBus, quote, settings.quoteDuckDb);
    }

    // Master ------------------------------------------------------------------
    final master = Float32List(frames * 2);
    for (final x in [baseBus, pitch, bass, pads, words, drums, quote]) {
      for (var i = 0; i < master.length; i++) {
        master[i] += x[i];
      }
    }
    _master(master);
    final out = AudioBuffer(master, sampleRate: sampleRate, channels: 2);
    final lufs = loudness(master, sampleRate, channels: 2);
    return RemixMix(
      master: out,
      stems: stems
          ? {
              Stem.base: AudioBuffer(baseBus, sampleRate: sampleRate, channels: 2),
              Stem.pitch: AudioBuffer(pitch, sampleRate: sampleRate, channels: 2),
              Stem.bass: AudioBuffer(bass, sampleRate: sampleRate, channels: 2),
              Stem.pads: AudioBuffer(pads, sampleRate: sampleRate, channels: 2),
              Stem.words: AudioBuffer(words, sampleRate: sampleRate, channels: 2),
              Stem.drums: AudioBuffer(drums, sampleRate: sampleRate, channels: 2),
              Stem.quote: AudioBuffer(quote, sampleRate: sampleRate, channels: 2),
            }
          : const {},
      events: events,
      lufs: lufs,
      peakDb: gainToDb(out.peak()),
    );
  }

  /// [sample] moved [semitones] with its length kept (TD-PSOLA from its
  /// tuned root; formants stay put, so voices don't turn into chipmunks).
  Float32List _stretchVoice(ProcessedSample sample, int semitones, int frames) {
    final src = sample.audio;
    // The sample is sustained already: analyse only what the note needs.
    final take = math.min(src.length, frames + (0.1 * sampleRate).round());
    final piece = Float32List.sublistView(src, 0, take);
    final root = sample.rootHz > 0 ? sample.rootHz : null;
    final out = root == null
        ? null
        : psolaCorrect(
            Float32List.fromList(piece),
            sampleRate,
            targetHz: root * math.pow(2, semitones / 12).toDouble(),
            lengthSeconds: math.min(frames, take) / sampleRate,
          );
    if (out != null) {
      // Match the original's level (overlap-add can drift a little).
      final a = _rms(piece), b = _rms(out.audio);
      if (a > 1e-6 && b > 1e-6) {
        final g = (a / b).clamp(0.5, 2.0);
        for (var i = 0; i < out.audio.length; i++) {
          out.audio[i] *= g;
        }
      }
      return out.audio;
    }
    return resample(src, math.pow(2, semitones / 12).toDouble(), sampleRate: sampleRate, maxFrames: frames);
  }

  static double _rms(Float32List x) {
    if (x.isEmpty) return 0;
    var e = 0.0;
    for (final v in x) {
      e += v * v;
    }
    return math.sqrt(e / x.length);
  }

  void _master(Float32List x) {
    final sr = sampleRate.toDouble();
    Biquad.processStereo(x, Biquad.highPass(sr, 25), Biquad.highPass(sr, 25));
    switch (settings.master) {
      case MasterMode.clean:
        compress(x, sampleRate, channels: 2, thresholdDb: -12, ratio: 2, attackMs: 15, releaseMs: 150);
        // Two passes: limiting eats some loudness, so top up once.
        for (var pass = 0; pass < 2; pass++) {
          _toLoudness(x, -9.5);
          limit(x, sampleRate, channels: 2, ceilingDb: -1.0, releaseMs: 80);
        }
      case MasterMode.hot:
        compress(x, sampleRate, channels: 2, thresholdDb: -10, ratio: 3, attackMs: 5, releaseMs: 80);
        _toLoudness(x, -7.5);
        // Soft clip into the ceiling: the classic loud Sparta sound.
        for (var i = 0; i < x.length; i++) {
          final v = x[i] * 1.25;
          x[i] = v / (1 + v.abs() * 0.35);
        }
        limit(x, sampleRate, channels: 2, ceilingDb: -0.1, releaseMs: 40);
    }
  }

  void _toLoudness(Float32List x, double target) {
    final now = loudness(x, sampleRate, channels: 2);
    if (now <= -69) return;
    final g = dbToGain((target - now).clamp(-24.0, 24.0));
    for (var i = 0; i < x.length; i++) {
      x[i] *= g;
    }
  }

  static void _eq(Float32List stereo, List<Biquad> filters) {
    for (final f in filters) {
      Biquad.processStereo(stereo, f, f.copy());
    }
  }

  /// Short delayed copy on the right side for width.
  void _haas(Float32List stereo, double seconds, double db) {
    final d = (seconds * sampleRate).round();
    final g = dbToGain(db);
    final frames = stereo.length ~/ 2;
    for (var f = frames - 1; f >= d; f--) {
      stereo[2 * f + 1] += stereo[2 * (f - d)] * g;
    }
  }

  /// Ducks [target] by up to [db] following the level of [key].
  void _duck(Float32List target, Float32List key, double db) {
    final depth = 1 - dbToGain(-db);
    final atk = math.exp(-1 / (0.01 * sampleRate)), rel = math.exp(-1 / (0.25 * sampleRate));
    var env = 0.0;
    final frames = target.length ~/ 2;
    for (var f = 0; f < frames; f++) {
      final level = math.max(key[2 * f].abs(), key[2 * f + 1].abs());
      env = level > env ? atk * env + (1 - atk) * level : rel * env + (1 - rel) * level;
      final amount = (env * 8).clamp(0.0, 1.0);
      final g = 1 - depth * amount;
      target[2 * f] *= g;
      target[2 * f + 1] *= g;
    }
  }
}
