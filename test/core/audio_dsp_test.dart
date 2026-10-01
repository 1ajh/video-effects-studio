import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/analysis.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/audio/dsp.dart';
import 'package:video_effects_studio/core/audio/fft.dart';
import 'package:video_effects_studio/core/audio/psola.dart';

const sr = 48000;

Float32List sine(double hz, double seconds, {double amp = 0.5, int rate = sr}) {
  final n = (seconds * rate).round();
  return Float32List.fromList(List.generate(n, (i) => amp * math.sin(2 * math.pi * hz * i / rate)));
}

/// Vowel-like buzz: band-limited pulse train through two formants, with a
/// gliding, wobbling pitch.
Float32List fakeVowel(double seconds, double Function(double t) f0) {
  final n = (seconds * sr).round();
  final out = Float32List(n);
  var phase = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    phase += f0(t) / sr;
    var v = 0.0;
    for (var h = 1; h <= 20; h++) {
      v += math.sin(2 * math.pi * h * phase) / h;
    }
    out[i] = v * 0.2;
  }
  Biquad.peak(sr.toDouble(), 700, 12, q: 3).process(out);
  Biquad.peak(sr.toDouble(), 1200, 9, q: 3).process(out);
  out.fillRange(0, 0, 0);
  final peak = out.fold<double>(0, (p, v) => math.max(p, v.abs()));
  for (var i = 0; i < n; i++) {
    out[i] *= 0.8 / peak;
  }
  return out;
}

double medianF0(Float32List x) {
  final t = trackPitch(x, sr)!;
  return t.medianHz;
}

void main() {
  test('FFT round trip and a pure tone bin', () {
    final fft = Fft(1024);
    final re = Float64List(1024), im = Float64List(1024);
    for (var i = 0; i < 1024; i++) {
      re[i] = math.cos(2 * math.pi * 32 * i / 1024);
    }
    final orig = Float64List.fromList(re);
    fft.transform(re, im);
    var best = 0;
    for (var k = 1; k < 512; k++) {
      if (re[k].abs() + im[k].abs() > re[best].abs() + im[best].abs()) best = k;
    }
    expect(best, 32);
    fft.transform(re, im, inverse: true);
    for (var i = 0; i < 1024; i++) {
      expect(re[i], closeTo(orig[i], 1e-9));
    }
  });

  test('YIN finds the pitch of tones', () {
    for (final hz in [82.4, 146.8, 220.0, 440.0, 880.0]) {
      final yin = Yin(sampleRate: sr, window: 1024, fMin: 60);
      final (f, ap) = yin.estimate(sine(hz, 0.2), 1000);
      expect(f, closeTo(hz, hz * 0.01), reason: '$hz');
      expect(ap, lessThan(0.1));
    }
  });

  test('analysis marks tones voiced and silence quiet, onsets on clicks', () {
    final x = Float32List(sr);
    x.setAll(sr ~/ 4, sine(220, 0.25));
    x.setAll(sr * 3 ~/ 4, sine(330, 0.2));
    final f = analyze(x, sr, hop: 480, yinWindow: 1024);
    expect(f.voiced(f.frameAt(0.35)), isTrue);
    expect(f.f0[f.frameAt(0.35)], closeTo(220, 3));
    expect(f.rmsDb[f.frameAt(0.1)], lessThan(-100));
    final onsets = detectOnsets(f).map(f.timeOf).toList();
    expect(onsets.any((t) => (t - 0.25).abs() < 0.05), isTrue, reason: '$onsets');
    expect(onsets.any((t) => (t - 0.75).abs() < 0.05), isTrue, reason: '$onsets');
  });

  test('PSOLA flattens a gliding vowel to the nearest D', () {
    final vowel = fakeVowel(0.8, (t) => 170 + 40 * t + 6 * math.sin(2 * math.pi * 5.5 * t));
    final corrected = psolaCorrect(vowel, sr)!;
    expect(corrected.targetHz, closeTo(146.83, 0.01)); // D3 is nearest to ~185 Hz
    final track = trackPitch(corrected.audio, sr)!;
    final inner = track.hz.sublist(2, track.hz.length - 2);
    expect(median(inner), closeTo(146.83, 146.83 * 0.012));
    expect(centsSpread(inner), lessThan(25));
  });

  test('PSOLA sustains beyond the source length at the target pitch', () {
    final vowel = fakeVowel(0.4, (t) => 300);
    final long = psolaCorrect(vowel, sr, targetHz: 293.66, lengthSeconds: 2.0)!;
    expect(long.audio.length, 2 * sr);
    // Still voiced and on pitch near the end.
    final tail = Float32List.sublistView(long.audio, (1.5 * sr).round(), (1.9 * sr).round());
    expect(medianF0(tail), closeTo(293.66, 293.66 * 0.015));
    final rmsTail = math.sqrt(tail.fold<double>(0, (s, v) => s + v * v) / tail.length);
    expect(rmsTail, greaterThan(0.05));
  });

  test('resample transposes pitch and length together', () {
    final x = sine(220, 1.0);
    final up = resample(x, 2.0);
    expect(up.length, closeTo(sr / 2, 2));
    expect(medianF0(up), closeTo(440, 5));
  });

  test('limiter never exceeds the ceiling; loudness of a -20 dBFS tone', () {
    final x = sine(1000, 2, amp: 2.0);
    limit(x, sr, ceilingDb: -1);
    final peak = x.fold<double>(0, (p, v) => math.max(p, v.abs()));
    expect(peak, lessThanOrEqualTo(dbToGain(-1) + 1e-6));
    final quiet = sine(1000, 3, amp: 0.1);
    expect(loudness(quiet, sr), closeTo(-23, 1.2));
  });

  test('WAV round trip', () {
    final buf = AudioBuffer(sine(440, 0.1), sampleRate: sr);
    final back = AudioBuffer.fromWav(buf.toWav());
    expect(back.frames, buf.frames);
    expect(back.data[100], closeTo(buf.data[100], 1 / 16000));
    final f = AudioBuffer.fromWav(buf.stereo().toWav(float32: true));
    expect(f.channels, 2);
    expect(f.data[201], closeTo(buf.data[100], 1e-6));
  });
}
