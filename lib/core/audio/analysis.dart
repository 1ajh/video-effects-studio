import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

/// Frame-level description of a mono signal.
class FrameFeatures {
  FrameFeatures({
    required this.sampleRate,
    required this.hop,
    required this.rmsDb,
    required this.f0,
    required this.aperiodicity,
    required this.centroid,
    required this.flatness,
    required this.zcr,
    required this.flux,
    required this.bands,
  });

  final int sampleRate;
  final int hop;

  /// RMS in dBFS per frame.
  final Float64List rmsDb;

  /// Fundamental in Hz, 0 when unvoiced.
  final Float64List f0;

  /// YIN cumulative-mean-normalized difference at the chosen lag (0 = perfectly periodic).
  final Float64List aperiodicity;

  /// Spectral centroid (Hz).
  final Float64List centroid;

  /// Spectral flatness (0 tonal .. 1 noise).
  final Float64List flatness;

  /// Zero-crossing rate (crossings per sample).
  final Float64List zcr;

  /// Positive log-spectral flux (onset strength).
  final Float64List flux;

  /// Energy share per band: [<150, 150-500, 500-2k, 2k-6k, >6k] Hz.
  final List<Float64List> bands;

  int get length => rmsDb.length;
  double timeOf(int frame) => frame * hop / sampleRate;
  int frameAt(double seconds) => (seconds * sampleRate / hop).floor().clamp(0, math.max(0, length - 1));
  double get frameSeconds => hop / sampleRate;

  bool voiced(int i) => f0[i] > 0;
}

/// YIN pitch detector using an FFT cross-correlation for the difference
/// function (de Cheveigné & Kawahara 2002).
class Yin {
  Yin({required this.sampleRate, this.window = 512, this.fMin = 60, this.fMax = 1100, this.threshold = 0.15})
    : _fft = Fft(Fft.nextPow2(window * 3));

  final int sampleRate;
  final int window;
  final double fMin;
  final double fMax;
  final double threshold;
  final Fft _fft;

  int get frameLength => window * 2;

  /// Returns (f0 Hz or 0, aperiodicity) for `x[start .. start + 2*window)`.
  (double, double) estimate(Float32List x, int start) {
    final n = _fft.size;
    final w = window;
    final maxLag = math.min(w, (sampleRate / fMin).ceil());
    final minLag = math.max(2, (sampleRate / fMax).floor());
    if (start + 2 * w > x.length) return (0, 1);

    final ar = Float64List(n), ai = Float64List(n);
    final br = Float64List(n), bi = Float64List(n);
    for (var j = 0; j < w; j++) {
      ar[j] = x[start + j];
    }
    for (var j = 0; j < 2 * w; j++) {
      br[j] = x[start + j];
    }
    _fft.transform(ar, ai);
    _fft.transform(br, bi);
    // conj(A) * B
    for (var k = 0; k < n; k++) {
      final r = ar[k] * br[k] + ai[k] * bi[k];
      final i = ar[k] * bi[k] - ai[k] * br[k];
      ar[k] = r;
      ai[k] = i;
    }
    _fft.transform(ar, ai, inverse: true);

    // Energies: e0 = sum x[j]^2 (j<w), e(tau) = sum x[j+tau]^2 (j<w).
    final sq = Float64List(2 * w + 1);
    for (var j = 0; j < 2 * w; j++) {
      final v = x[start + j];
      sq[j + 1] = sq[j] + v * v;
    }
    final e0 = sq[w];
    if (e0 < 1e-10) return (0, 1);

    final d = Float64List(maxLag + 1);
    for (var tau = 1; tau <= maxLag; tau++) {
      final et = sq[tau + w] - sq[tau];
      d[tau] = e0 + et - 2 * ar[tau];
    }
    // Cumulative mean normalized difference.
    final cm = Float64List(maxLag + 1)..[0] = 1;
    var run = 0.0;
    for (var tau = 1; tau <= maxLag; tau++) {
      run += d[tau];
      cm[tau] = run <= 0 ? 1 : d[tau] * tau / run;
    }
    var tau = -1;
    for (var t = minLag; t < maxLag; t++) {
      if (cm[t] < threshold) {
        while (t + 1 < maxLag && cm[t + 1] < cm[t]) {
          t++;
        }
        tau = t;
        break;
      }
    }
    if (tau < 0) {
      // No dip under the threshold: report the global minimum's quality.
      var best = minLag;
      for (var t = minLag; t < maxLag; t++) {
        if (cm[t] < cm[best]) best = t;
      }
      return (0, cm[best]);
    }
    // Parabolic interpolation.
    var refined = tau.toDouble();
    if (tau > 1 && tau < maxLag) {
      final a = cm[tau - 1], b = cm[tau], c = cm[tau + 1];
      final den = a - 2 * b + c;
      if (den.abs() > 1e-12) refined = tau + 0.5 * (a - c) / den;
    }
    return (sampleRate / refined, cm[tau]);
  }
}

/// Computes [FrameFeatures] for a mono signal.
FrameFeatures analyze(Float32List x, int sampleRate, {int hop = 256, int yinWindow = 512}) {
  final yin = Yin(sampleRate: sampleRate, window: yinWindow);
  final specSize = Fft.nextPow2(yinWindow * 2);
  final fft = Fft(specSize);
  final win = hann(specSize);
  final frames = x.length <= yin.frameLength ? 1 : 1 + (x.length - yin.frameLength) ~/ hop;

  final rmsDb = Float64List(frames);
  final f0 = Float64List(frames);
  final aper = Float64List(frames);
  final centroid = Float64List(frames);
  final flatness = Float64List(frames);
  final zcr = Float64List(frames);
  final flux = Float64List(frames);
  final bands = List.generate(5, (_) => Float64List(frames));
  const edges = [0.0, 150.0, 500.0, 2000.0, 6000.0, double.infinity];

  final bins = specSize ~/ 2;
  var prevMag = Float64List(bins);
  final re = Float64List(specSize), im = Float64List(specSize);

  for (var f = 0; f < frames; f++) {
    final start = f * hop;
    // Time-domain features over the analysis window.
    var s = 0.0;
    var crossings = 0;
    final end = math.min(x.length, start + specSize);
    for (var i = start; i < end; i++) {
      s += x[i] * x[i];
      if (i > start && (x[i] >= 0) != (x[i - 1] >= 0)) crossings++;
    }
    final len = math.max(1, end - start);
    final rms = math.sqrt(s / len);
    rmsDb[f] = rms > 1e-9 ? 20 * math.log(rms) / math.ln10 : -180;
    zcr[f] = crossings / len;

    // Spectrum.
    for (var i = 0; i < specSize; i++) {
      final idx = start + i;
      re[i] = idx < x.length ? x[idx] * win[i] : 0;
      im[i] = 0;
    }
    fft.transform(re, im);
    final mag = Float64List(bins);
    var total = 0.0, weighted = 0.0, logSum = 0.0, lin = 0.0, fl = 0.0;
    final bandE = Float64List(5);
    for (var k = 1; k < bins; k++) {
      final m = math.sqrt(re[k] * re[k] + im[k] * im[k]);
      mag[k] = m;
      final p = m * m;
      final hz = k * sampleRate / specSize;
      total += p;
      weighted += p * hz;
      logSum += math.log(m + 1e-12);
      lin += m;
      final diff = math.log(1 + 100 * m) - math.log(1 + 100 * prevMag[k]);
      if (diff > 0) fl += diff;
      for (var b = 0; b < 5; b++) {
        if (hz >= edges[b] && hz < edges[b + 1]) {
          bandE[b] += p;
          break;
        }
      }
    }
    prevMag = mag;
    centroid[f] = total > 0 ? weighted / total : 0;
    final geo = math.exp(logSum / (bins - 1));
    final arith = lin / (bins - 1);
    flatness[f] = arith > 1e-12 ? (geo / arith).clamp(0, 1).toDouble() : 1;
    flux[f] = fl / bins;
    for (var b = 0; b < 5; b++) {
      bands[b][f] = total > 0 ? bandE[b] / total : 0;
    }

    // Pitch only where there is something to hear.
    if (rmsDb[f] > -50) {
      final (hz, ap) = yin.estimate(x, start);
      f0[f] = hz;
      aper[f] = ap;
    } else {
      aper[f] = 1;
    }
  }

  return FrameFeatures(
    sampleRate: sampleRate,
    hop: hop,
    rmsDb: rmsDb,
    f0: f0,
    aperiodicity: aper,
    centroid: centroid,
    flatness: flatness,
    zcr: zcr,
    flux: flux,
    bands: bands,
  );
}

/// Onset frames from spectral flux with an adaptive (median) threshold.
List<int> detectOnsets(FrameFeatures f, {double minGapSeconds = 0.06, double sensitivity = 1.0}) {
  final n = f.length;
  if (n < 3) return const [];
  final flux = f.flux;
  final maxFlux = flux.reduce(math.max);
  if (maxFlux <= 0) return const [];
  const half = 8;
  final onsets = <int>[];
  var last = -1 << 30;
  final minGap = (minGapSeconds / f.frameSeconds).ceil();
  for (var i = 1; i < n - 1; i++) {
    if (flux[i] < flux[i - 1] || flux[i] < flux[i + 1]) continue;
    final lo = math.max(0, i - half), hi = math.min(n, i + half + 1);
    final window = flux.sublist(lo, hi).toList()..sort();
    final median = window[window.length ~/ 2];
    final thresh = median * 1.5 / sensitivity + 0.08 * maxFlux / sensitivity;
    if (flux[i] > thresh && f.rmsDb[i] > -45 && i - last >= minGap) {
      onsets.add(i);
      last = i;
    }
  }
  return onsets;
}

/// Median of a list (0 for empty).
double median(Iterable<double> values) {
  final v = values.toList()..sort();
  if (v.isEmpty) return 0;
  return v.length.isOdd ? v[v.length ~/ 2] : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
}

/// Standard deviation in cents of a set of frequencies.
double centsSpread(Iterable<double> hz) {
  final list = hz.where((h) => h > 0).toList();
  if (list.length < 2) return 0;
  final logs = list.map((h) => 1200 * math.log(h) / math.ln2).toList();
  final mean = logs.reduce((a, b) => a + b) / logs.length;
  var v = 0.0;
  for (final l in logs) {
    v += (l - mean) * (l - mean);
  }
  return math.sqrt(v / logs.length);
}

double hzToMidi(double hz) => 69 + 12 * math.log(hz / 440) / math.ln2;
double midiToHz(double midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();
