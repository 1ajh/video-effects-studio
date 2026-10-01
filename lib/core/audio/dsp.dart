import 'dart:math' as math;
import 'dart:typed_data';

/// RBJ cookbook biquad (direct form I), mono.
class Biquad {
  Biquad._(this.b0, this.b1, this.b2, this.a1, this.a2);

  factory Biquad.lowPass(double sr, double hz, {double q = 0.7071}) {
    final w = 2 * math.pi * hz / sr, c = math.cos(w), a = math.sin(w) / (2 * q);
    return Biquad._norm((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + a, -2 * c, 1 - a);
  }

  factory Biquad.highPass(double sr, double hz, {double q = 0.7071}) {
    final w = 2 * math.pi * hz / sr, c = math.cos(w), a = math.sin(w) / (2 * q);
    return Biquad._norm((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + a, -2 * c, 1 - a);
  }

  factory Biquad.bandPass(double sr, double hz, {double q = 1}) {
    final w = 2 * math.pi * hz / sr, c = math.cos(w), a = math.sin(w) / (2 * q);
    return Biquad._norm(a, 0, -a, 1 + a, -2 * c, 1 - a);
  }

  factory Biquad.peak(double sr, double hz, double gainDb, {double q = 1}) {
    final A = math.pow(10, gainDb / 40).toDouble();
    final w = 2 * math.pi * hz / sr, c = math.cos(w), a = math.sin(w) / (2 * q);
    return Biquad._norm(1 + a * A, -2 * c, 1 - a * A, 1 + a / A, -2 * c, 1 - a / A);
  }

  factory Biquad.lowShelf(double sr, double hz, double gainDb) {
    final A = math.pow(10, gainDb / 40).toDouble();
    final w = 2 * math.pi * hz / sr, c = math.cos(w), s = math.sin(w);
    final a = s / 2 * math.sqrt(2), sq = 2 * math.sqrt(A) * a;
    return Biquad._norm(
      A * ((A + 1) - (A - 1) * c + sq),
      2 * A * ((A - 1) - (A + 1) * c),
      A * ((A + 1) - (A - 1) * c - sq),
      (A + 1) + (A - 1) * c + sq,
      -2 * ((A - 1) + (A + 1) * c),
      (A + 1) + (A - 1) * c - sq,
    );
  }

  factory Biquad.highShelf(double sr, double hz, double gainDb) {
    final A = math.pow(10, gainDb / 40).toDouble();
    final w = 2 * math.pi * hz / sr, c = math.cos(w), s = math.sin(w);
    final a = s / 2 * math.sqrt(2), sq = 2 * math.sqrt(A) * a;
    return Biquad._norm(
      A * ((A + 1) + (A - 1) * c + sq),
      -2 * A * ((A - 1) + (A + 1) * c),
      A * ((A + 1) + (A - 1) * c - sq),
      (A + 1) - (A - 1) * c + sq,
      2 * ((A - 1) - (A + 1) * c),
      (A + 1) - (A - 1) * c - sq,
    );
  }

  static Biquad _norm(double b0, double b1, double b2, double a0, double a1, double a2) =>
      Biquad._(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0);

  final double b0, b1, b2, a1, a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double tick(double x) {
    final y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  void reset() => _x1 = _x2 = _y1 = _y2 = 0;

  /// Same coefficients, fresh state (e.g. for the other stereo channel).
  Biquad copy() => Biquad._(b0, b1, b2, a1, a2);

  /// Continues from another filter's state (for time-varying coefficients).
  void copyStateFrom(Biquad o) {
    _x1 = o._x1;
    _x2 = o._x2;
    _y1 = o._y1;
    _y2 = o._y2;
  }

  /// Filters a mono buffer in place.
  void process(Float32List x) {
    for (var i = 0; i < x.length; i++) {
      x[i] = tick(x[i]);
    }
  }

  /// Filters interleaved stereo in place (separate state per channel).
  static void processStereo(Float32List x, Biquad left, Biquad right) {
    for (var i = 0; i + 1 < x.length; i += 2) {
      x[i] = left.tick(x[i]);
      x[i + 1] = right.tick(x[i + 1]);
    }
  }
}

double dbToGain(double db) => math.pow(10, db / 20).toDouble();
double gainToDb(double g) => g <= 1e-12 ? -240 : 20 * math.log(g) / math.ln10;

/// Linear fade in/out (in place, mono).
void fade(Float32List x, int sampleRate, {double inMs = 2, double outMs = 8}) {
  final fi = math.min(x.length, (inMs * sampleRate / 1000).round());
  final fo = math.min(x.length, (outMs * sampleRate / 1000).round());
  for (var i = 0; i < fi; i++) {
    x[i] *= i / fi;
  }
  for (var i = 0; i < fo; i++) {
    x[x.length - 1 - i] *= i / fo;
  }
}

/// Drops leading/trailing audio quieter than [thresholdDb] below the peak.
Float32List trimSilence(Float32List x, int sampleRate, {double thresholdDb = -40, double padMs = 5}) {
  var peak = 0.0;
  for (final v in x) {
    peak = math.max(peak, v.abs());
  }
  if (peak <= 1e-9) return Float32List(0);
  final t = peak * dbToGain(thresholdDb);
  var a = 0, b = x.length - 1;
  while (a < x.length && x[a].abs() < t) {
    a++;
  }
  while (b > a && x[b].abs() < t) {
    b--;
  }
  final pad = (padMs * sampleRate / 1000).round();
  a = math.max(0, a - pad);
  b = math.min(x.length - 1, b + pad);
  return Float32List.fromList(x.sublist(a, b + 1));
}

/// Resamples by [ratio] (output = input played [ratio]× faster) with
/// 4-point cubic interpolation and an anti-alias low-pass when speeding up.
/// This is the classic sampler transposition: pitch and speed together.
Float32List resample(Float32List x, double ratio, {int sampleRate = 48000, int? maxFrames}) {
  if (x.isEmpty || ratio <= 0) return Float32List(0);
  var src = x;
  if (ratio > 1.05) {
    src = Float32List.fromList(x);
    final cutoff = math.min(0.45 * sampleRate / ratio, 0.45 * sampleRate);
    Biquad.lowPass(sampleRate.toDouble(), cutoff).process(src);
    Biquad.lowPass(sampleRate.toDouble(), cutoff).process(src);
  }
  var n = (src.length / ratio).floor();
  if (maxFrames != null) n = math.min(n, maxFrames);
  final out = Float32List(math.max(0, n));
  final last = src.length - 1;
  double at(int i) => src[i < 0 ? 0 : (i > last ? last : i)];
  for (var i = 0; i < out.length; i++) {
    final pos = i * ratio;
    final k = pos.floor();
    final t = pos - k;
    final p0 = at(k - 1), p1 = at(k), p2 = at(k + 1), p3 = at(k + 2);
    out[i] = (p1 + 0.5 * t * (p2 - p0 + t * (2 * p0 - 5 * p1 + 4 * p2 - p3 + t * (3 * (p1 - p2) + p3 - p0))))
        .toDouble();
  }
  return out;
}

/// Feed-forward compressor with soft knee, mono or interleaved stereo
/// (linked detector), in place.
void compress(
  Float32List x,
  int sampleRate, {
  int channels = 1,
  double thresholdDb = -18,
  double ratio = 3,
  double attackMs = 5,
  double releaseMs = 120,
  double makeupDb = 0,
  double kneeDb = 6,
}) {
  final atk = math.exp(-1 / (attackMs * 0.001 * sampleRate));
  final rel = math.exp(-1 / (releaseMs * 0.001 * sampleRate));
  var env = 0.0;
  final makeup = dbToGain(makeupDb);
  for (var i = 0; i < x.length; i += channels) {
    var level = x[i].abs();
    if (channels == 2) level = math.max(level, x[i + 1].abs());
    env = level > env ? atk * env + (1 - atk) * level : rel * env + (1 - rel) * level;
    final db = gainToDb(env);
    final over = db - thresholdDb;
    double reduce;
    if (over <= -kneeDb / 2) {
      reduce = 0;
    } else if (over >= kneeDb / 2) {
      reduce = over * (1 - 1 / ratio);
    } else {
      final t = over + kneeDb / 2;
      reduce = (1 - 1 / ratio) * t * t / (2 * kneeDb);
    }
    final g = dbToGain(-reduce) * makeup;
    for (var c = 0; c < channels; c++) {
      x[i + c] *= g;
    }
  }
}

/// Look-ahead brick-wall limiter (in place). Never exceeds [ceilingDb].
void limit(Float32List x, int sampleRate, {int channels = 1, double ceilingDb = -0.3, double releaseMs = 60}) {
  final ceiling = dbToGain(ceilingDb);
  final look = math.max(1, (0.003 * sampleRate).round());
  final frames = x.length ~/ channels;
  // Required gain per frame.
  final need = Float32List(frames);
  for (var f = 0; f < frames; f++) {
    var p = 0.0;
    for (var c = 0; c < channels; c++) {
      p = math.max(p, x[f * channels + c].abs());
    }
    need[f] = p > ceiling ? ceiling / p : 1;
  }
  // Minimum over the look-ahead window, then smooth release.
  final gain = Float32List(frames);
  final rel = math.exp(-1 / (releaseMs * 0.001 * sampleRate));
  var g = 1.0;
  // Sliding minimum (simple deque).
  final dq = <int>[];
  var head = 0;
  for (var f = 0; f < frames + look; f++) {
    if (f < frames) {
      while (dq.length > head && need[dq.last] >= need[f]) {
        dq.removeLast();
      }
      dq.add(f);
    }
    final out = f - look;
    if (out < 0) continue;
    while (dq[head] < out) {
      head++;
    }
    final target = need[dq[head]];
    g = target < g ? target : rel * g + (1 - rel) * target;
    if (g > target) g = target;
    gain[out] = g;
  }
  for (var f = 0; f < frames; f++) {
    for (var c = 0; c < channels; c++) {
      final i = f * channels + c;
      x[i] = (x[i] * gain[f]).clamp(-ceiling, ceiling).toDouble();
    }
  }
}

/// Approximate integrated loudness (LUFS) with K-weighting and a -70 LUFS
/// absolute + -10 LU relative gate (ITU-R BS.1770, simplified).
double loudness(Float32List x, int sampleRate, {int channels = 1}) {
  final frames = x.length ~/ channels;
  if (frames == 0) return -70;
  final shelf = List.generate(channels, (_) => Biquad.highShelf(sampleRate.toDouble(), 1681, 4));
  final hp = List.generate(channels, (_) => Biquad.highPass(sampleRate.toDouble(), 38, q: 0.5));
  final block = (0.4 * sampleRate).round();
  final hopN = (0.1 * sampleRate).round();
  final weighted = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var s = 0.0;
    for (var c = 0; c < channels; c++) {
      final v = hp[c].tick(shelf[c].tick(x[f * channels + c]));
      s += v * v;
    }
    weighted[f] = s;
  }
  final prefix = Float64List(frames + 1);
  for (var f = 0; f < frames; f++) {
    prefix[f + 1] = prefix[f] + weighted[f];
  }
  final blocks = <double>[];
  for (var s = 0; s + block <= frames; s += hopN) {
    final ms = (prefix[s + block] - prefix[s]) / block;
    blocks.add(ms);
  }
  if (blocks.isEmpty) blocks.add(prefix[frames] / frames);
  double lufs(double ms) => -0.691 + 10 * math.log(ms + 1e-15) / math.ln10;
  final abs = blocks.where((m) => lufs(m) > -70).toList();
  if (abs.isEmpty) return -70;
  final mean = abs.reduce((a, b) => a + b) / abs.length;
  final rel = abs.where((m) => lufs(m) > lufs(mean) - 10).toList();
  final m2 = rel.isEmpty ? mean : rel.reduce((a, b) => a + b) / rel.length;
  return lufs(m2);
}

/// Soft saturation (tanh), in place.
void saturate(Float32List x, {double drive = 1.5}) {
  final norm = 1 / _tanh(drive);
  for (var i = 0; i < x.length; i++) {
    x[i] = _tanh(x[i] * drive) * norm;
  }
}

double _tanh(double v) {
  if (v > 20) return 1;
  if (v < -20) return -1;
  final e = math.exp(2 * v);
  return (e - 1) / (e + 1);
}

/// Mixes [src] (mono) into interleaved stereo [dst] at frame [offset] with
/// gain and equal-power pan (-1..1).
void mixInto(Float32List dst, Float32List src, int offset, {double gain = 1, double pan = 0}) {
  final a = (pan.clamp(-1.0, 1.0) + 1) * math.pi / 4;
  final gl = math.cos(a) * gain * math.sqrt2, gr = math.sin(a) * gain * math.sqrt2;
  final frames = dst.length ~/ 2;
  for (var i = 0; i < src.length; i++) {
    final f = offset + i;
    if (f < 0) continue;
    if (f >= frames) break;
    dst[2 * f] += src[i] * gl;
    dst[2 * f + 1] += src[i] * gr;
  }
}
