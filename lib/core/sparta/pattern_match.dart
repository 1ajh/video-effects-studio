import 'dart:math' as math;

import 'patterns.dart';

/// A note onset to match against the wiki's pitch patterns.
class Onset {
  const Onset(this.step, this.key, {this.length = 1, this.weight = 1});

  /// Position in 16th-note steps from the start of the song.
  final double step;

  /// MIDI key (or a pitch class 0..11 when matching by pitch class).
  final int key;

  /// Length in steps.
  final double length;
  final double weight;
}

/// How well a stretch of notes follows a pattern.
class PatternMatch {
  const PatternMatch({
    required this.pattern,
    required this.bar,
    required this.offset,
    required this.recall,
    required this.precision,
  });

  final Pattern pattern;

  /// First bar of the match.
  final int bar;

  /// The key the pattern's 0 lands on (MIDI key, or pitch class).
  final int offset;

  /// Share of the pattern's hits found, and of the onsets explained.
  final double recall;
  final double precision;

  double get score => recall + precision == 0 ? 0 : 2 * recall * precision / (recall + precision);
  int get bars => pattern.bars;

  @override
  String toString() => '${pattern.id} @bar$bar off$offset ${score.toStringAsFixed(2)}';
}

/// Finds which wiki pitch pattern a stretch of notes plays, in any key.
class PatternMatcher {
  PatternMatcher({Iterable<Pattern>? patterns, this.byPitchClass = false})
    : patterns = [
        for (final p in patterns ?? PatternLibrary.instance.of(PatternKind.pitch))
          if (!p.irregular && p.hits.length >= 3 && p.steps >= 16 && p.section != 'chords') p,
      ];

  final List<Pattern> patterns;

  /// Compare pitch classes only (audio, where octaves are unreliable).
  final bool byPitchClass;

  static const _tolerance = 0.3;

  /// The best pattern starting at [bar] among [onsets] (sorted by step).
  /// [preferPc] breaks offset ties toward a known root.
  PatternMatch? best(List<Onset> onsets, int bar, {int? preferPc, Set<String>? sections, int maxBars = 8}) {
    PatternMatch? top;
    for (final p in patterns) {
      if (p.bars > maxBars) continue;
      if (sections != null && !sections.contains(p.section)) continue;
      final m = match(p, onsets, bar, preferPc: preferPc);
      if (m != null && (top == null || m.score > top.score + 1e-9)) top = m;
    }
    return top;
  }

  /// How well [onsets] in [bar, bar + p.bars) follow [p].
  PatternMatch? match(Pattern p, List<Onset> onsets, int bar, {int? preferPc}) {
    final from = bar * 16.0, to = (bar + p.bars) * 16.0;
    final window = _slice(onsets, from - _tolerance, to - _tolerance);
    if (window.isEmpty) return null;
    final hits = p.looped(p.bars * 16.0);
    // Vote for the key the pattern's 0 sits on.
    final votes = <int, double>{};
    for (final h in hits) {
      for (final o in _at(window, from + h.step)) {
        final off = byPitchClass ? (o.key - h.semitone) % 12 : o.key - h.semitone;
        votes[off] = (votes[off] ?? 0) + 1 + (preferPc != null && off % 12 == preferPc ? 0.01 : 0);
      }
    }
    if (votes.isEmpty) return null;
    final offset = votes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    var matched = 0.0;
    for (final h in hits) {
      final want = offset + h.semitone;
      var got = 0.0;
      for (final o in _at(window, from + h.step)) {
        if (byPitchClass ? (o.key - want) % 12 == 0 : o.key == want) {
          got = 1;
          break;
        }
        // Right note in another octave: half credit.
        if (!byPitchClass && (o.key - want) % 12 == 0) got = math.max(got, 0.5);
      }
      matched += got;
    }
    final steps = <int>{for (final o in window) (o.step * 4).round()};
    final recall = matched / hits.length;
    final precision = math.min(1.0, matched / steps.length);
    return PatternMatch(pattern: p, bar: bar, offset: offset, recall: recall, precision: precision);
  }

  static List<Onset> _slice(List<Onset> sorted, double from, double to) {
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid].step < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final out = <Onset>[];
    for (var i = lo; i < sorted.length && sorted[i].step < to; i++) {
      out.add(sorted[i]);
    }
    return out;
  }

  static Iterable<Onset> _at(List<Onset> window, double step) sync* {
    for (final o in window) {
      if ((o.step - step).abs() <= _tolerance) yield o;
    }
  }
}
