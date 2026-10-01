import 'dart:math' as math;
import 'dart:typed_data';

/// In-place iterative radix-2 complex FFT (size must be a power of two).
class Fft {
  Fft(this.size) : assert(size > 1 && (size & (size - 1)) == 0, 'size must be a power of two') {
    var levels = 0;
    for (var s = size; s > 1; s >>= 1) {
      levels++;
    }
    _rev = Int32List(size);
    for (var i = 0; i < size; i++) {
      var r = 0;
      var x = i;
      for (var b = 0; b < levels; b++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
      }
      _rev[i] = r;
    }
    _cos = Float64List(size ~/ 2);
    _sin = Float64List(size ~/ 2);
    for (var i = 0; i < size ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / size);
      _sin[i] = -math.sin(2 * math.pi * i / size);
    }
  }

  final int size;
  late final Int32List _rev;
  late final Float64List _cos;
  late final Float64List _sin;

  /// Forward transform of (re, im) in place.
  void transform(Float64List re, Float64List im, {bool inverse = false}) {
    final n = size;
    for (var i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final half = len >> 1;
      final step = n ~/ len;
      for (var i = 0; i < n; i += len) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step];
          final wi = inverse ? -_sin[k * step] : _sin[k * step];
          final a = i + k, b = a + half;
          final xr = re[b] * wr - im[b] * wi;
          final xi = re[b] * wi + im[b] * wr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
        }
      }
    }
    if (inverse) {
      for (var i = 0; i < n; i++) {
        re[i] /= n;
        im[i] /= n;
      }
    }
  }

  static int nextPow2(int n) {
    var p = 1;
    while (p < n) {
      p <<= 1;
    }
    return p;
  }
}

/// Hann window of length [n].
Float64List hann(int n) {
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
  }
  return w;
}
