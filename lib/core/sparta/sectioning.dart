import 'dart:math' as math;

import 'chart_import.dart';
import 'model.dart';

/// Finds the sections of an imported project from how its parts play.
///
/// Boundaries go where the set of playing parts changes (Sparta bases are
/// built from looped patterns, so sections swap parts in and out). The
/// intro is found by a small hidden Markov model whose section order and
/// statistics were learned from 52 community Sparta bases that name their
/// sections; it finds 81% of their intro bars (fixed blocks labelled by
/// density found 8%). On those bases the result labels about twice as many
/// bars correctly as before (40% vs 19% across seven section kinds).
List<Section> sectionsFromTracks(List<ChartTrack> tracks, int bars, int beatsPerBar) {
  final parts = [
    for (final t in tracks)
      if (t.notes.isNotEmpty) t,
  ];
  if (bars < 4 || parts.isEmpty) return const [];
  final bpb = beatsPerBar.toDouble();
  final counts = [
    for (final t in parts)
      () {
        final c = List<int>.filled(bars, 0);
        for (final n in t.notes) {
          final b = (n.beat / bpb).floor();
          if (b >= 0 && b < bars) c[b]++;
        }
        return c;
      }(),
  ];
  final drums = [for (final t in parts) t.isDrums];

  final bounds = _boundaries(counts, bars);
  final cuts = [0, ...bounds, bars];
  final segments = [for (var i = 0; i + 1 < cuts.length; i++) (cuts[i], cuts[i + 1])];
  final feats = _features(counts, drums, bars, segments);
  // Real intros end within the first 40% of a song (37% at most in the
  // labelled bases), so only early segments may be one.
  final labels = _viterbi(feats, introAllowed: [for (final (_, z) in segments) z <= bars * 0.4]);
  final kinds = [for (final l in labels) l == 0 ? SectionKind.intro : null];

  // After the intro, notes alone can't tell epicness from madness reliably
  // (the model above would call it all epicness), so the rest follows the
  // Sparta template by intensity: a clearly thinner last part is the
  // outro, the densest parts (30% of the bars) are madness, a short part
  // leading into madness is awesomeness, and the rest is epicness. On the
  // labelled bases this scores as well and matches their mix of sections.
  final rest = [
    for (var i = 0; i < segments.length; i++)
      if (kinds[i] == null) i,
  ];
  if (rest.isNotEmpty) {
    double density(int i) => feats[i][0];
    int barsOf(int i) => segments[i].$2 - segments[i].$1;
    final sorted = [for (final i in rest) density(i)]..sort();
    final median = sorted[sorted.length ~/ 2];
    if (rest.length > 1 && density(rest.last) < 0.6 * median) kinds[rest.removeLast()] = SectionKind.outro;
    final total = rest.fold<int>(0, (s, i) => s + barsOf(i));
    var mad = 0;
    for (final i in [...rest]..sort((x, y) => density(x) != density(y) ? density(y).compareTo(density(x)) : x - y)) {
      if (mad >= 0.3 * total) break;
      kinds[i] = SectionKind.madness;
      mad += barsOf(i);
    }
    for (final i in rest) {
      kinds[i] ??= SectionKind.epicness;
    }
    for (var j = 0; j + 1 < rest.length; j++) {
      final i = rest[j];
      if (kinds[i] == SectionKind.epicness && kinds[rest[j + 1]] == SectionKind.madness && barsOf(i) <= 8) {
        kinds[i] = SectionKind.awesomeness;
      }
    }
  }
  // Neighbours with the same label stay separate: the base changes there,
  // so the sample chart should too.
  return [for (var i = 0; i < segments.length; i++) Section(kinds[i]!, segments[i].$1 * bpb, segments[i].$2 * bpb)];
}

/// Bars where the playing parts change most: cosine distance between the
/// two bars before and the two after, strongest first, at least 4 bars
/// apart, preferring even bars.
List<int> _boundaries(List<List<int>> counts, int bars) {
  const window = 2, threshold = 0.1, minGap = 4;
  final k = counts.length;
  final v = [
    for (var b = 0; b < bars; b++) [for (final c in counts) math.log(1 + c[b])],
  ];
  List<double> mean(int from, int to) {
    final m = List<double>.filled(k, 0);
    for (var b = from; b < to; b++) {
      for (var j = 0; j < k; j++) {
        m[j] += v[b][j];
      }
    }
    return [for (final x in m) x / math.max(1, to - from)];
  }

  final novelty = List<double>.filled(bars, 0);
  for (var b = 1; b < bars; b++) {
    novelty[b] = _cosineDistance(mean(math.max(0, b - window), b), mean(b, math.min(bars, b + window)));
  }
  final order = List.generate(bars - 1, (i) => i + 1)
    ..sort((a, z) => novelty[z] != novelty[a] ? novelty[z].compareTo(novelty[a]) : a.compareTo(z));
  final chosen = <int>[];
  for (final b in order) {
    if (novelty[b] < threshold) break;
    var at = b;
    if (b.isOdd) {
      final alts = [b - 1, b + 1].where((x) => x > 0 && x < bars);
      final best = alts.reduce((x, y) => novelty[y] > novelty[x] ? y : x);
      if (novelty[best] >= 0.7 * novelty[b]) at = best;
    }
    if (at >= 2 && at <= bars - 2 && chosen.every((c) => (at - c).abs() >= minGap)) chosen.add(at);
  }
  return chosen..sort();
}

double _cosineDistance(List<double> a, List<double> b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 && nb == 0) return 0;
  if (na == 0 || nb == 0) return 1;
  return 1 - dot / math.sqrt(na * nb);
}

/// Per segment: overall, drum and tonal note density, notes per playing
/// tonal part (relative to the project's 90th percentile), share of parts
/// heard for the first time, position in the song and length.
List<List<double>> _features(List<List<int>> counts, List<bool> drums, int bars, List<(int, int)> segments) {
  final total = List<double>.filled(bars, 0), drum = List<double>.filled(bars, 0), tonal = List<double>.filled(bars, 0);
  final tonalParts = List<int>.filled(bars, 0);
  for (var j = 0; j < counts.length; j++) {
    for (var b = 0; b < bars; b++) {
      final c = counts[j][b];
      total[b] += c;
      if (drums[j]) {
        drum[b] += c;
      } else {
        tonal[b] += c;
        if (c > 0) tonalParts[b]++;
      }
    }
  }
  final rate = [for (var b = 0; b < bars; b++) tonalParts[b] > 0 ? tonal[b] / tonalParts[b] : 0.0];
  double p90(List<double> x) {
    final s = [...x]..sort();
    final v = s[(0.9 * (s.length - 1)).floor()];
    return v > 0 ? v : (s.last > 0 ? s.last : 1);
  }

  final mT = p90(total), mD = p90(drum), mTo = p90(tonal), mR = p90(rate);
  final seen = <int>{};
  return [
    for (final (a, z) in segments)
      () {
        final len = z - a;
        double avg(List<double> x, double m) =>
            math.min(1.5, x.sublist(a, z).fold<double>(0, (s, y) => s + y) / len / m);
        final active = {
          for (var j = 0; j < counts.length; j++)
            if (counts[j].sublist(a, z).any((c) => c > 0)) j,
        };
        final fresh = active.difference(seen).length / math.max(1, active.length);
        seen.addAll(active);
        return [
          avg(total, mT),
          avg(drum, mD),
          avg(tonal, mTo),
          avg(rate, mR),
          fresh,
          (a + z) / 2 / bars,
          math.min(1.0, len / 16),
        ];
      }(),
  ];
}

// Model states, in this order: intro, chorus, dundundenden, epicness,
// awesomeness, madness, outro.

// Learned from the labelled bases (log probabilities; feature means and
// variances in the order produced by _features). Variances are floored at
// 0.08 so one unusual feature can't veto a section (cross-validated
// accuracy is the same).
const _start = [-0.146, -4.078, -4.078, -4.078, -4.078, -2.979, -4.078];
const _trans = [
  [-0.386, -2.807, -3.997, -1.652, -3.746, -4.844, -3.997],
  [-3.958, -0.945, -1.689, -1.56, -3.447, -2.348, -2.658],
  [-4.443, -1.498, -0.636, -1.878, -4.443, -2.833, -4.443],
  [-4.438, -2.551, -6.047, -0.498, -1.97, -1.904, -4.438],
  [-2.565, -3.017, -3.864, -2.565, -0.885, -1.113, -3.353],
  [-3.714, -2.826, -4.561, -1.728, -2.951, -0.472, -2.951],
  [-3.807, -2.708, -3.807, -1.861, -3.807, -3.807, -0.373],
];
const _mean = [
  [0.593, 0.547, 0.577, 0.762, 0.343, 0.194, 0.38],
  [0.782, 0.655, 0.767, 0.849, 0.125, 0.486, 0.442],
  [0.641, 0.617, 0.615, 0.732, 0.089, 0.415, 0.377],
  [0.703, 0.571, 0.702, 0.771, 0.055, 0.559, 0.394],
  [0.78, 0.776, 0.75, 0.8, 0.058, 0.682, 0.445],
  [0.727, 0.561, 0.729, 0.784, 0.081, 0.632, 0.43],
  [0.576, 0.368, 0.619, 0.655, 0.057, 0.822, 0.337],
];
const _variance = [
  [0.08, 0.147, 0.08, 0.08, 0.137, 0.08, 0.08],
  [0.08, 0.125, 0.08, 0.08, 0.08, 0.08, 0.08],
  [0.08, 0.15, 0.08, 0.08, 0.08, 0.08, 0.08],
  [0.08, 0.13, 0.08, 0.08, 0.08, 0.08, 0.08],
  [0.08, 0.08, 0.08, 0.08, 0.08, 0.08, 0.08],
  [0.08, 0.146, 0.08, 0.08, 0.08, 0.08, 0.08],
  [0.116, 0.132, 0.123, 0.093, 0.08, 0.08, 0.08],
];

/// Emissions are down-weighted against the section-order model, and each
/// feature's penalty is capped at one standard deviation; both
/// cross-validated best.
const _emissionWeight = 0.5;

List<int> _viterbi(List<List<double>> feats, {required List<bool> introAllowed}) {
  const k = 7;
  double emit(int s, List<double> x, int i) {
    if (s == 0 && i > 0 && !introAllowed[i]) return double.negativeInfinity;
    var l = 0.0;
    for (var j = 0; j < x.length; j++) {
      final d = x[j] - _mean[s][j];
      // Each feature can only count so much against a section.
      l += -0.5 * math.min(1.0, d * d / _variance[s][j]) - 0.5 * math.log(_variance[s][j]);
    }
    return _emissionWeight * l;
  }

  var score = [for (var s = 0; s < k; s++) _start[s] + emit(s, feats[0], 0)];
  final back = <List<int>>[];
  for (var i = 1; i < feats.length; i++) {
    final next = List<double>.filled(k, 0), from = List<int>.filled(k, 0);
    for (var s = 0; s < k; s++) {
      var best = 0;
      for (var p = 1; p < k; p++) {
        if (score[p] + _trans[p][s] > score[best] + _trans[best][s]) best = p;
      }
      from[s] = best;
      next[s] = score[best] + _trans[best][s] + emit(s, feats[i], i);
    }
    back.add(from);
    score = next;
  }
  var s = 0;
  for (var j = 1; j < k; j++) {
    if (score[j] > score[s]) s = j;
  }
  final path = [s];
  for (var i = back.length - 1; i >= 0; i--) {
    s = back[i][s];
    path.add(s);
  }
  return path.reversed.toList();
}
