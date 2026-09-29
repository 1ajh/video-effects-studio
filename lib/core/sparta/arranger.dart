import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/audio_buffer.dart';
import '../audio/dsp.dart';
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

class MixSettings {
  const MixSettings({
    this.master = MasterMode.clean,
    this.baseDb = 0,
    this.laneDb = const {},
    this.reverb = 0.12,
    this.quoteDuckDb = 5,
  });

  final MasterMode master;
  final double baseDb;
  final Map<SampleRole, double> laneDb;

  /// Reverb send on the pitch/chop buses (0..1).
  final double reverb;

  /// How far the base dips under the quote.
  final double quoteDuckDb;

  MixSettings copyWith({MasterMode? master, double? baseDb, Map<SampleRole, double>? laneDb, double? reverb}) =>
      MixSettings(
        master: master ?? this.master,
        baseDb: baseDb ?? this.baseDb,
        laneDb: laneDb ?? this.laneDb,
        reverb: reverb ?? this.reverb,
        quoteDuckDb: quoteDuckDb,
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
  });

  final SampleRole role;

  /// Which of the role's samples played (multiple sources alternate).
  final int variant;
  final double beat;

  /// Seconds on the remix timeline.
  final double start;
  final double duration;

  /// Playback-rate multiplier (sampler transposition: pitch and speed).
  final double rate;
  final int semitone;
  final double velocity;
  final int sectionIndex;

  /// Running index of this hit within its lane (for alternating flips).
  final int laneIndex;

  double get end => start + duration;
}

/// Stems written next to the master.
enum Stem { base, pitch, chop, drums, quote }

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
  });

  final SpartaBase base;

  /// Stereo base instrumental at [sampleRate] (null: samples only).
  final AudioBuffer? baseAudio;

  /// Playable samples per role; several per role alternate.
  final Map<SampleRole, List<ProcessedSample>> samples;
  final MixSettings settings;
  final int sampleRate;

  static const _laneGain = {
    SampleRole.pitch: 0.52,
    SampleRole.chop: 0.42,
    SampleRole.kick: 0.5,
    SampleRole.snare: 0.42,
    SampleRole.hat: 0.22,
    SampleRole.quote: 0.75,
  };

  double get _length {
    final chartEnd = base.chart.fold<double>(0, (m, n) => math.max(m, base.seconds(n.end)));
    var len = math.max(base.durationSeconds, chartEnd + 1.5);
    final a = baseAudio;
    if (a != null) len = math.max(len, math.min(a.duration - base.audioOffset, base.durationSeconds + 16));
    return len;
  }

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
        final variant = switch (role) {
          SampleRole.pitch || SampleRole.quote => sectionIndex % list.length,
          SampleRole.chop => i % list.length,
          _ => (sectionIndex ~/ 2) % list.length,
        };
        final sample = list[variant];
        final rate = math.pow(2, n.semitone / 12).toDouble();
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
    final release = (0.012 * sampleRate).round();

    for (final e in events) {
      final sample = samples[e.role]![e.variant];
      final needed = (e.duration * sampleRate).round() + release;
      final key = '${e.role.index}/${e.variant}/${e.rate.toStringAsFixed(5)}';
      var voice = cache[key];
      if (voice == null || voice.length < needed) {
        voice = (e.rate - 1).abs() < 1e-6
            ? Float32List.fromList(sample.audio.sublist(0, math.min(sample.audio.length, needed)))
            : resample(sample.audio, e.rate, sampleRate: sampleRate, maxFrames: needed);
        cache[key] = voice;
      }
      final body = math.min(voice.length, (e.duration * sampleRate).round());
      final len = math.min(voice.length, body + release);
      final hit = Float32List.fromList(voice.sublist(0, len));
      // Tiny attack de-click and a release fade where the note is cut.
      for (var i = 0; i < math.min(24, hit.length); i++) {
        hit[i] *= i / 24;
      }
      for (var i = body; i < len; i++) {
        hit[i] *= 1 - (i - body) / math.max(1, len - body);
      }
      final gain = _laneGain[e.role]! * dbToGain(settings.laneDb[e.role] ?? 0) * (0.35 + 0.65 * e.velocity);
      final pan = switch (e.role) {
        SampleRole.chop => e.laneIndex.isEven ? -0.22 : 0.22,
        SampleRole.hat => 0.3,
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

    final chop = laneBus[SampleRole.chop]!;
    _eq(chop, [Biquad.highPass(sr, 120), Biquad.peak(sr, 4000, 2, q: 0.9)]);
    compress(chop, sampleRate, channels: 2, thresholdDb: -18, ratio: 4, attackMs: 1, releaseMs: 60, makeupDb: 2);

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
        send[i] = (pitch[i] + chop[i] * 0.7) * settings.reverb;
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
    for (final x in [baseBus, pitch, chop, drums, quote]) {
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
              Stem.chop: AudioBuffer(chop, sampleRate: sampleRate, channels: 2),
              Stem.drums: AudioBuffer(drums, sampleRate: sampleRate, channels: 2),
              Stem.quote: AudioBuffer(quote, sampleRate: sampleRate, channels: 2),
            }
          : const {},
      events: events,
      lufs: lufs,
      peakDb: gainToDb(out.peak()),
    );
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
