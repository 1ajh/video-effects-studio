import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';

/// Small synthesis toolkit for the built-in bases (48 kHz mono voices).
class Synth {
  Synth({int seed = 1, this.sampleRate = 48000}) : _rng = math.Random(seed);

  final int sampleRate;
  final math.Random _rng;

  double get sr => sampleRate.toDouble();
  int frames(double seconds) => (seconds * sampleRate).round();
  double _noise() => _rng.nextDouble() * 2 - 1;

  static double hz(double midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

  // ---------------------------------------------------------------------------
  // Drums
  // ---------------------------------------------------------------------------

  Float32List kick({double punch = 1.0, double decay = 0.32, double tone = 50}) {
    final n = frames(decay * 1.8);
    final out = Float32List(n);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      final f = tone + 150 * punch * math.exp(-t / 0.028);
      phase += 2 * math.pi * f / sr;
      final body = math.sin(phase) * math.exp(-t / decay);
      final click = _noise() * math.exp(-t / 0.0025) * 0.35 * punch;
      out[i] = body + click;
    }
    saturate(out, drive: 1.8);
    return out;
  }

  Float32List snare({double tone = 190, double decay = 0.17, double snap = 1.0}) {
    final n = frames(decay * 2);
    final noise = Float32List(n), body = Float32List(n);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      noise[i] = _noise() * math.exp(-t / decay);
      phase += 2 * math.pi * (tone + 60 * math.exp(-t / 0.01)) / sr;
      body[i] = math.sin(phase) * math.exp(-t / 0.06);
    }
    Biquad.highPass(sr, 900).process(noise);
    Biquad.peak(sr, 3800, 6 * snap, q: 0.8).process(noise);
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = noise[i] * 0.8 + body[i] * 0.7;
    }
    saturate(out, drive: 1.4);
    return out;
  }

  Float32List clap() {
    final n = frames(0.3);
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      var env = 0.0;
      for (final off in const [0.0, 0.011, 0.022]) {
        if (t >= off) env = math.max(env, math.exp(-(t - off) / 0.007));
      }
      if (t >= 0.03) env = math.max(env, 0.6 * math.exp(-(t - 0.03) / 0.09));
      out[i] = _noise() * env;
    }
    Biquad.bandPass(sr, 1400, q: 0.9).process(out);
    return _norm(out, 0.9);
  }

  Float32List hat({bool open = false}) {
    final n = frames(open ? 0.35 : 0.07);
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      // Metallic: noise ring-modulated by inharmonic squares.
      var metal = 0.0;
      for (final f in const [3140.0, 4870.0, 6120.0, 8350.0]) {
        metal += (math.sin(2 * math.pi * f * t) >= 0 ? 1 : -1) * 0.25;
      }
      out[i] = (0.6 * _noise() + 0.4 * metal) * math.exp(-t / (open ? 0.12 : 0.018));
    }
    Biquad.highPass(sr, 7000).process(out);
    Biquad.highPass(sr, 7000).process(out);
    return _norm(out, 0.6);
  }

  Float32List crash({double seconds = 2.2}) {
    final n = frames(seconds);
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      var metal = 0.0;
      for (final f in const [2330.0, 3470.0, 5210.0, 7190.0, 9310.0]) {
        metal += math.sin(2 * math.pi * f * t + f);
      }
      out[i] = (0.7 * _noise() + 0.06 * metal) * math.exp(-t / (seconds * 0.35));
    }
    Biquad.highPass(sr, 3500).process(out);
    return _norm(out, 0.55);
  }

  /// Low tom / timpani-like hit at [midi].
  Float32List tom(double midi, {double decay = 0.4}) {
    final n = frames(decay * 1.6);
    final out = Float32List(n);
    var phase = 0.0;
    final f0 = hz(midi);
    for (var i = 0; i < n; i++) {
      final t = i / sr;
      phase += 2 * math.pi * f0 * (1 + 0.5 * math.exp(-t / 0.02)) / sr;
      out[i] = (math.sin(phase) + 0.15 * _noise() * math.exp(-t / 0.01)) * math.exp(-t / decay);
    }
    return _norm(out, 0.9);
  }

  /// Rising filtered-noise sweep (for build-ups).
  Float32List riser(double seconds) {
    final n = frames(seconds);
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _noise() * (i / n) * (i / n);
    }
    // Sweep a band-pass upward in blocks.
    const blocks = 32;
    final block = (n / blocks).ceil();
    for (var b = 0; b < blocks; b++) {
      final f = 300 * math.pow(40, b / blocks).toDouble();
      final bp = Biquad.bandPass(sr, math.min(f, 18000), q: 1.2);
      for (var i = b * block; i < math.min(n, (b + 1) * block); i++) {
        out[i] = bp.tick(out[i]);
      }
    }
    return _norm(out, 0.5);
  }

  // ---------------------------------------------------------------------------
  // Tonal
  // ---------------------------------------------------------------------------

  /// Detuned saw stack through a decaying low-pass: the "orchestra hit" /
  /// Sparta stab. [notes] are MIDI notes played together.
  Float32List stab(
    List<double> notes,
    double seconds, {
    int voices = 5,
    double detune = 0.18,
    double cutoff = 5000,
    double decay = 0.35,
    double sustain = 0.25,
  }) {
    final n = frames(seconds + 0.08);
    final out = Float32List(n);
    for (final note in notes) {
      for (var v = 0; v < voices; v++) {
        final cents = voices == 1 ? 0.0 : (v / (voices - 1) - 0.5) * 2 * detune * 100;
        final f = hz(note) * math.pow(2, cents / 1200).toDouble();
        var ph = _rng.nextDouble();
        for (var i = 0; i < n; i++) {
          ph += f / sr;
          ph -= ph.floorToDouble();
          out[i] += (2 * ph - 1) / voices;
        }
      }
    }
    _envFilter(out, cutoff: cutoff, decay: decay, sustain: sustain, gateSeconds: seconds);
    return _norm(out, 0.8);
  }

  /// Saw + sub bass note.
  Float32List bass(double midi, double seconds, {double cutoff = 900, double drive = 1.6}) {
    final n = frames(seconds + 0.02);
    final out = Float32List(n);
    final f = hz(midi);
    var ph = 0.0, sub = 0.0;
    for (var i = 0; i < n; i++) {
      ph += f / sr;
      ph -= ph.floorToDouble();
      sub += 2 * math.pi * f / sr;
      out[i] = 0.55 * (2 * ph - 1) + 0.7 * math.sin(sub);
    }
    _envFilter(out, cutoff: cutoff, decay: 0.12, sustain: 0.55, gateSeconds: seconds, attackMs: 3);
    saturate(out, drive: drive);
    return _norm(out, 0.85);
  }

  /// Slow supersaw pad.
  Float32List pad(List<double> notes, double seconds) {
    final out = stab(notes, seconds, voices: 7, detune: 0.25, cutoff: 2200, decay: 1.5, sustain: 0.9);
    final atk = frames(0.15);
    for (var i = 0; i < math.min(atk, out.length); i++) {
      out[i] *= i / atk;
    }
    return out;
  }

  /// Amplitude envelope + low-pass whose cutoff follows it (block updated).
  void _envFilter(
    Float32List x, {
    required double cutoff,
    required double decay,
    required double sustain,
    required double gateSeconds,
    double attackMs = 1,
  }) {
    final gate = frames(gateSeconds);
    final atk = math.max(1, frames(attackMs / 1000));
    final rel = frames(0.06);
    const block = 64;
    var bq = Biquad.lowPass(sr, cutoff);
    for (var i = 0; i < x.length; i++) {
      final t = i / sr;
      var env = i < atk ? i / atk : sustain + (1 - sustain) * math.exp(-(t - atk / sr) / decay);
      if (i > gate) env *= math.max(0, 1 - (i - gate) / rel);
      if (i % block == 0) {
        final c = (200 + (cutoff - 200) * env).clamp(80.0, sr * 0.45);
        final next = Biquad.lowPass(sr, c);
        // Carry state across coefficient updates.
        next.copyStateFrom(bq);
        bq = next;
      }
      x[i] = bq.tick(x[i]) * env;
    }
  }

  static Float32List _norm(Float32List x, double target) {
    final p = x.fold<double>(0, (m, v) => math.max(m, v.abs()));
    if (p > 1e-9) {
      for (var i = 0; i < x.length; i++) {
        x[i] *= target / p;
      }
    }
    return x;
  }
}

/// Stereo Freeverb-style reverb (4 combs + 2 all-passes per side).
class Reverb {
  Reverb({int sampleRate = 48000, this.room = 0.78, this.damp = 0.35}) {
    final scale = sampleRate / 44100;
    const combL = [1116, 1188, 1277, 1356];
    const apL = [556, 441];
    for (var side = 0; side < 2; side++) {
      final spread = side * 23;
      _combs.add([for (final c in combL) _Comb(((c + spread) * scale).round())]);
      _aps.add([for (final a in apL) _AllPass(((a + spread) * scale).round())]);
    }
  }

  final double room;
  final double damp;
  final List<List<_Comb>> _combs = [];
  final List<List<_AllPass>> _aps = [];

  /// Returns the wet signal for interleaved stereo input.
  Float32List process(Float32List stereo) {
    final out = Float32List(stereo.length);
    for (var i = 0; i + 1 < stereo.length; i += 2) {
      final input = (stereo[i] + stereo[i + 1]) * 0.015;
      for (var side = 0; side < 2; side++) {
        var s = 0.0;
        for (final c in _combs[side]) {
          s += c.tick(input, room, damp);
        }
        for (final a in _aps[side]) {
          s = a.tick(s);
        }
        out[i + side] = s;
      }
    }
    return out;
  }
}

class _Comb {
  _Comb(int size) : _buf = Float64List(size);
  final Float64List _buf;
  int _i = 0;
  double _store = 0;
  double tick(double x, double feedback, double damp) {
    final y = _buf[_i];
    _store = y * (1 - damp) + _store * damp;
    _buf[_i] = x + _store * feedback;
    _i = (_i + 1) % _buf.length;
    return y;
  }
}

class _AllPass {
  _AllPass(int size) : _buf = Float64List(size);
  final Float64List _buf;
  int _i = 0;
  double tick(double x) {
    final b = _buf[_i];
    final y = -x + b;
    _buf[_i] = x + b * 0.5;
    _i = (_i + 1) % _buf.length;
    return y;
  }
}
