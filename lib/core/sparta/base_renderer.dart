import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/audio_buffer.dart';
import '../audio/dsp.dart';
import '../audio/synth.dart';
import 'composer.dart';

/// Per-style sound design for the synthesized bases.
class _Voicing {
  const _Voicing({
    required this.kickDecay,
    required this.kickTone,
    required this.kickPunch,
    required this.snareTone,
    required this.snareDecay,
    required this.stabVoices,
    required this.stabDetune,
    required this.stabCutoff,
    required this.stabDecay,
    required this.stabSustain,
    required this.bassCutoff,
    required this.bassDrive,
    required this.duck,
    required this.room,
  });

  final double kickDecay, kickTone, kickPunch;
  final double snareTone, snareDecay;
  final int stabVoices;
  final double stabDetune, stabCutoff, stabDecay, stabSustain;
  final double bassCutoff, bassDrive;

  /// Sidechain depth (0..1) of the kick on the tonal buses.
  final double duck;
  final double room;

  static _Voicing of(BaseStyle s) => switch (s) {
    BaseStyle.classic => const _Voicing(
      kickDecay: 0.32,
      kickTone: 50,
      kickPunch: 1.0,
      snareTone: 190,
      snareDecay: 0.17,
      stabVoices: 5,
      stabDetune: 0.18,
      stabCutoff: 5000,
      stabDecay: 0.35,
      stabSustain: 0.25,
      bassCutoff: 900,
      bassDrive: 1.6,
      duck: 0.35,
      room: 0.78,
    ),
    BaseStyle.hyper => const _Voicing(
      kickDecay: 0.26,
      kickTone: 55,
      kickPunch: 1.2,
      snareTone: 210,
      snareDecay: 0.14,
      stabVoices: 5,
      stabDetune: 0.12,
      stabCutoff: 8000,
      stabDecay: 0.25,
      stabSustain: 0.3,
      bassCutoff: 1200,
      bassDrive: 1.8,
      duck: 0.45,
      room: 0.72,
    ),
    BaseStyle.venom => const _Voicing(
      kickDecay: 0.4,
      kickTone: 45,
      kickPunch: 1.1,
      snareTone: 170,
      snareDecay: 0.2,
      stabVoices: 7,
      stabDetune: 0.28,
      stabCutoff: 3200,
      stabDecay: 0.5,
      stabSustain: 0.35,
      bassCutoff: 700,
      bassDrive: 2.4,
      duck: 0.5,
      room: 0.84,
    ),
  };
}

/// Mix settings per instrument: gain, pan, reverb send, bus.
enum _Bus { drums, low, music, fx }

class _Channel {
  const _Channel(this.gain, this.bus, {this.pan = 0, this.send = 0, this.variants = 1, this.spread = 0});
  final double gain;
  final _Bus bus;
  final double pan;
  final double send;

  /// Round-robin variants (noise-based drums sound less robotic).
  final int variants;

  /// When > 0, two variants are played hard left/right by this amount.
  final double spread;
}

const _channels = {
  Instrument.kick: _Channel(0.9, _Bus.drums),
  Instrument.snare: _Channel(0.62, _Bus.drums, send: 0.25, variants: 3),
  Instrument.clap: _Channel(0.34, _Bus.drums, pan: -0.08, send: 0.3, variants: 3),
  Instrument.hat: _Channel(0.2, _Bus.drums, pan: 0.25, variants: 4),
  Instrument.openHat: _Channel(0.2, _Bus.drums, pan: 0.3, variants: 2),
  Instrument.crash: _Channel(0.24, _Bus.drums, pan: 0.15, send: 0.1),
  Instrument.tom: _Channel(0.5, _Bus.drums, pan: -0.2, send: 0.2),
  Instrument.riser: _Channel(0.22, _Bus.fx, send: 0.3, spread: 0.5),
  Instrument.bass: _Channel(0.44, _Bus.low),
  Instrument.stab: _Channel(0.36, _Bus.music, send: 0.18, spread: 0.4),
  Instrument.pad: _Channel(0.16, _Bus.music, send: 0.3, spread: 0.6),
};

/// Renders a composed built-in base to 48 kHz stereo audio.
///
/// Pure Dart and synchronous so it can run inside an isolate.
class BaseRenderer {
  BaseRenderer({this.sampleRate = 48000});

  final int sampleRate;

  AudioBuffer render(Composition c) {
    final v = _Voicing.of(c.style);
    final synth = Synth(seed: c.seed, sampleRate: sampleRate);
    final spb = 60 / c.base.bpm;
    final frames = (c.base.durationSeconds * sampleRate).ceil();
    final buses = {for (final b in _Bus.values) b: Float32List(frames * 2)};
    final send = Float32List(frames * 2);
    final cache = <String, Float32List>{};
    final roundRobin = <Instrument, int>{};
    final kicks = <int>[];

    Float32List voice(ScoreEvent e, int variant) {
      final key = '${e.instrument.name}|${e.midi.join(',')}|${e.length.toStringAsFixed(3)}|$variant';
      return cache.putIfAbsent(key, () {
        final seconds = e.length * spb;
        return switch (e.instrument) {
          Instrument.kick => synth.kick(punch: v.kickPunch, decay: v.kickDecay, tone: v.kickTone),
          Instrument.snare => synth.snare(tone: v.snareTone, decay: v.snareDecay),
          Instrument.clap => synth.clap(),
          Instrument.hat => synth.hat(),
          Instrument.openHat => synth.hat(open: true),
          Instrument.crash => synth.crash(seconds: math.max(1.2, math.min(3.0, seconds))),
          Instrument.tom => synth.tom(e.midi.isEmpty ? 38 : e.midi.first, decay: math.min(0.6, seconds * 0.6 + 0.15)),
          Instrument.riser => synth.riser(seconds),
          Instrument.bass => synth.bass(
            e.midi.isEmpty ? 38 : e.midi.first,
            seconds,
            cutoff: v.bassCutoff,
            drive: v.bassDrive,
          ),
          Instrument.stab => synth.stab(
            e.midi,
            seconds,
            voices: v.stabVoices,
            detune: v.stabDetune,
            cutoff: v.stabCutoff,
            decay: v.stabDecay,
            sustain: v.stabSustain,
          ),
          Instrument.pad => synth.pad(e.midi, seconds),
        };
      });
    }

    for (final e in c.score) {
      final ch = _channels[e.instrument]!;
      final at = (e.beat * spb * sampleRate).round();
      if (at >= frames) continue;
      if (e.instrument == Instrument.kick) kicks.add(at);
      final bus = buses[ch.bus]!;
      final gain = ch.gain * e.velocity;
      if (ch.spread > 0) {
        // Two independently generated takes, one per side: instant width.
        final l = voice(e, 0), r = voice(e, 1);
        mixInto(bus, l, at, gain: gain * 0.75, pan: -ch.spread);
        mixInto(bus, r, at, gain: gain * 0.75, pan: ch.spread);
        if (ch.send > 0) {
          mixInto(send, l, at, gain: gain * ch.send, pan: -ch.spread);
          mixInto(send, r, at, gain: gain * ch.send, pan: ch.spread);
        }
      } else {
        final n = roundRobin[e.instrument] = ((roundRobin[e.instrument] ?? -1) + 1) % ch.variants;
        final x = voice(e, n);
        mixInto(bus, x, at, gain: gain, pan: ch.pan);
        if (ch.send > 0) mixInto(send, x, at, gain: gain * ch.send, pan: ch.pan);
      }
    }

    // Kick sidechain on bass + music so the low end stays clean.
    if (v.duck > 0 && kicks.isNotEmpty) {
      final env = _duckEnvelope(kicks, frames, v.duck);
      for (final b in [_Bus.low, _Bus.music]) {
        final x = buses[b]!;
        for (var f = 0; f < frames; f++) {
          x[2 * f] *= env[f];
          x[2 * f + 1] *= env[f];
        }
      }
    }

    final wet = Reverb(sampleRate: sampleRate, room: v.room, damp: 0.4).process(send);
    final out = Float32List(frames * 2);
    for (final x in buses.values) {
      for (var i = 0; i < out.length; i++) {
        out[i] += x[i];
      }
    }
    for (var i = 0; i < out.length; i++) {
      out[i] += wet[i] * 3;
    }

    // Tidy the bottom, glue, and leave headroom for the samples.
    final hpL = Biquad.highPass(sampleRate.toDouble(), 28), hpR = Biquad.highPass(sampleRate.toDouble(), 28);
    Biquad.processStereo(out, hpL, hpR);
    compress(out, sampleRate, channels: 2, thresholdDb: -14, ratio: 2, attackMs: 12, releaseMs: 140);
    final buffer = AudioBuffer(out, sampleRate: sampleRate, channels: 2);
    buffer.normalize(dbToGain(-3));
    return buffer;
  }

  Float32List _duckEnvelope(List<int> kicks, int frames, double depth) {
    final env = Float32List(frames)..fillRange(0, frames, 1);
    final tau = 0.09 * sampleRate;
    final attack = (0.004 * sampleRate).round();
    kicks.sort();
    for (var k = 0; k < kicks.length; k++) {
      final start = kicks[k];
      final end = k + 1 < kicks.length ? kicks[k + 1] : frames;
      for (var f = math.max(0, start - attack); f < math.min(frames, end); f++) {
        final t = f - start;
        final g = t < 0 ? 1 - depth * (1 + t / attack) : 1 - depth * math.exp(-t / tau);
        if (g < env[f]) env[f] = g;
      }
    }
    return env;
  }
}
