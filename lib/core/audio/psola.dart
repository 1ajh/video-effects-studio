import 'dart:math' as math;
import 'dart:typed_data';

import 'analysis.dart';
import 'dsp.dart';

/// Pitch track of a short voiced sample.
class PitchTrack {
  PitchTrack(this.hop, this.sampleRate, this.hz, this.quality);

  final int hop;
  final int sampleRate;

  /// Per-frame f0 with unvoiced gaps filled from neighbours (always > 0 when
  /// any voicing was found).
  final Float64List hz;

  /// Per-frame aperiodicity (0 = clean periodic).
  final Float64List quality;

  double periodAt(int sample) {
    final f = (sample / hop).clamp(0, hz.length - 1.0);
    final i = f.floor();
    final j = math.min(i + 1, hz.length - 1);
    final t = f - i;
    final h = hz[i] * (1 - t) + hz[j] * t;
    return sampleRate / h;
  }

  double get medianHz => median(hz.where((h) => h > 0));
}

/// Tracks f0 through a short sample and repairs octave jumps (as in
/// PitchCorrector297: every frame is snapped to the j/k multiple closest to
/// the local median).
PitchTrack? trackPitch(Float32List x, int sampleRate, {int hop = 240}) {
  final yin = Yin(sampleRate: sampleRate, window: 1024, fMin: 65, fMax: 1000, threshold: 0.2);
  final n = x.length <= yin.frameLength ? 0 : 1 + (x.length - yin.frameLength) ~/ hop;
  if (n < 2) return null;
  final raw = Float64List(n), q = Float64List(n);
  for (var i = 0; i < n; i++) {
    final (hz, ap) = yin.estimate(x, i * hop);
    raw[i] = hz;
    q[i] = ap;
  }
  final voiced = raw.where((h) => h > 0).length;
  if (voiced < 2) return null;

  // Octave-error repair against a 7-frame median.
  final fixed = Float64List(n);
  for (var i = 0; i < n; i++) {
    final neigh = <double>[
      for (var j = math.max(0, i - 3); j <= math.min(n - 1, i + 3); j++)
        if (raw[j] > 0) raw[j],
    ];
    if (raw[i] <= 0 || neigh.isEmpty) continue;
    final m = median(neigh);
    var best = raw[i];
    var bestDiff = double.infinity;
    for (var a = 1; a <= 4; a++) {
      for (var b = 1; b <= 4; b++) {
        final cand = raw[i] * a / b;
        final d = (math.log(cand / m)).abs();
        if (d < bestDiff) {
          bestDiff = d;
          best = cand;
        }
      }
    }
    fixed[i] = best;
  }
  // Fill unvoiced frames from the nearest voiced one.
  var last = 0.0;
  for (var i = 0; i < n; i++) {
    if (fixed[i] > 0) {
      last = fixed[i];
    } else if (last > 0) {
      fixed[i] = last;
    }
  }
  last = 0;
  for (var i = n - 1; i >= 0; i--) {
    if (fixed[i] > 0) {
      last = fixed[i];
    } else {
      fixed[i] = last;
    }
  }
  return PitchTrack(hop, sampleRate, fixed, q);
}

/// Places pitch marks on periodic peaks of a low-passed copy of the signal.
List<int> pitchMarks(Float32List x, PitchTrack track) {
  if (x.isEmpty) return const [];
  final sr = track.sampleRate.toDouble();
  final lp = Float32List.fromList(x);
  final cutoff = (track.medianHz * 1.8).clamp(120.0, 1500.0);
  Biquad.lowPass(sr, cutoff).process(lp);
  Biquad.lowPass(sr, cutoff).process(lp);

  // Start at the strongest peak inside the first two periods of the loudest region.
  var loudest = 0;
  var loud = 0.0;
  for (var i = 0; i < x.length; i++) {
    final a = x[i].abs();
    if (a > loud) {
      loud = a;
      loudest = i;
    }
  }
  int peakIn(int a, int b) {
    a = a.clamp(0, lp.length - 1);
    b = b.clamp(a + 1, lp.length);
    var bi = a;
    var bv = -double.infinity;
    for (var i = a; i < b; i++) {
      if (lp[i] > bv) {
        bv = lp[i];
        bi = i;
      }
    }
    return bi;
  }

  final p0 = track.periodAt(loudest);
  final anchor = peakIn(loudest - p0 ~/ 2, loudest + p0 ~/ 2 + 1);
  final marks = <int>[anchor];
  // Walk forward.
  var m = anchor;
  while (true) {
    final p = track.periodAt(m);
    if (p <= 2) break;
    final lo = (m + p * 0.8).round(), hi = (m + p * 1.2).round();
    if (lo >= x.length - 1) break;
    final next = peakIn(lo, hi + 1);
    if (next <= m) break;
    marks.add(next);
    m = next;
  }
  // Walk backward.
  m = anchor;
  final back = <int>[];
  while (true) {
    final p = track.periodAt(m);
    if (p <= 2) break;
    final lo = (m - p * 1.2).round(), hi = (m - p * 0.8).round();
    if (hi <= 0) break;
    final prev = peakIn(lo, hi + 1);
    if (prev >= m) break;
    back.add(prev);
    m = prev;
  }
  return [...back.reversed, ...marks];
}

/// Result of pitch correction.
class CorrectedSample {
  CorrectedSample(this.audio, this.targetHz, this.sourceHz);
  final Float32List audio;
  final double targetHz;
  final double sourceHz;
  double get shiftSemitones => 12 * math.log(targetHz / sourceHz) / math.ln2;
}

/// Picks the D closest to [hz] (D2 73.4 … D6 1174.7).
double nearestD(double hz) {
  const ds = [73.4162, 146.8324, 293.6648, 587.3295, 1174.659];
  var best = ds[2];
  for (final d in ds) {
    if ((math.log(hz / d)).abs() < (math.log(hz / best)).abs()) best = d;
  }
  return best;
}

/// The note of pitch class [pc] (0 = C … 11 = B) closest to [hz].
double nearestOfClass(double hz, int pc) {
  final midi = 69 + 12 * math.log(hz / 440) / math.ln2;
  var best = (midi / 12).floor() * 12 + pc;
  for (final m in [best - 12, best + 12]) {
    if ((m - midi).abs() < (best - midi).abs()) best = m;
  }
  return 440 * math.pow(2, (best - 69) / 12).toDouble();
}

/// TD-PSOLA: re-synthesizes [x] at [targetHz] (formants kept), producing
/// [lengthSeconds] of audio. With [follow] 0 the result is flat on the
/// note (hard-tuned); 1 keeps the voice's own inflection around it. When
/// the output is longer than the voiced material, the stable middle of the
/// sample is traversed back and forth so the vowel sustains.
///
/// Without [targetHz] the note is the [pitchClass] (default D) closest to
/// the sample's own pitch, moved up by octaves to at least [minHz].
CorrectedSample? psolaCorrect(
  Float32List x,
  int sampleRate, {
  double? targetHz,
  int pitchClass = 2,
  double? lengthSeconds,
  double formant = 1.0,
  double follow = 0,
  double minHz = 0,
}) {
  final track = trackPitch(x, sampleRate);
  if (track == null) return null;
  final marks = pitchMarks(x, track);
  if (marks.length < 4) return null;
  final src = track.medianHz;
  var target = targetHz ?? nearestOfClass(src, pitchClass);
  // Never under [minHz] (whole octaves up from the nearest note).
  while (targetHz == null && minHz > 0 && target < minHz * 0.999) {
    target *= 2;
  }
  final outLen = ((lengthSeconds ?? x.length / sampleRate) * sampleRate).round();
  final out = Float64List(outLen + 4096);
  final norm = Float64List(outLen + 4096);
  final period = sampleRate / target;

  // Analysis time map: forward through the sample, then ping-pong inside the
  // steady part [35% .. 90%] of the mark range for sustain.
  final first = marks.first, lastMark = marks[marks.length - 2];
  final span = (lastMark - first).toDouble();
  final loopA = first + span * 0.35, loopB = first + span * 0.9;
  double analysisTime(double t) {
    final pos = first + t;
    if (pos <= loopB) return pos;
    final loopLen = math.max(1.0, loopB - loopA);
    final over = (pos - loopB) % (2 * loopLen);
    return over < loopLen ? loopB - over : loopA + (over - loopLen);
  }

  int nearestMark(double pos) {
    var lo = 0, hi = marks.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (marks[mid] < pos) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (pos - marks[lo]).abs() < (marks[hi] - pos).abs() ? lo : hi;
  }

  double periodAt(double pos) {
    if (follow <= 0) return period;
    final i = (pos / track.hop).round().clamp(0, track.hz.length - 1);
    final hz = track.hz[i];
    if (hz <= 0) return period;
    return period / math.pow(hz / src, follow).toDouble();
  }

  for (var t = 0.0; t < outLen; t += periodAt(analysisTime(t))) {
    final k = nearestMark(analysisTime(t)).clamp(1, marks.length - 2);
    final c = marks[k];
    final left = ((c - marks[k - 1]) / formant).round();
    final right = ((marks[k + 1] - c) / formant).round();
    final dst = t.round();
    for (var i = -left; i <= right; i++) {
      final w = i < 0 ? 0.5 + 0.5 * math.cos(math.pi * i / left) : 0.5 + 0.5 * math.cos(math.pi * i / right);
      final srcIdx = c + (i * formant).round();
      if (srcIdx < 0 || srcIdx >= x.length) continue;
      final o = dst + i;
      if (o < 0 || o >= out.length) continue;
      out[o] += x[srcIdx] * w;
      norm[o] += w;
    }
  }
  final result = Float32List(outLen);
  for (var i = 0; i < outLen; i++) {
    // Soft normalization keeps overlap-add level constant without boosting gaps.
    result[i] = (out[i] / math.max(norm[i], 0.6)).toDouble();
  }
  return CorrectedSample(result, target, src);
}
