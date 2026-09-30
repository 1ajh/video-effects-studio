import 'dart:math' as math;

import 'base.dart';
import 'composer.dart';
import 'model.dart';

/// Recompose the sample notes between two beats in the style of [kind];
/// [variant] > 0 asks for another take.
class ChartRewrite {
  const ChartRewrite(this.startBeat, this.endBeat, this.kind, {this.variant = 0});
  final double startBeat;
  final double endBeat;
  final SectionKind kind;
  final int variant;

  Map<String, Object> toJson() => {'s': startBeat, 'e': endBeat, 'k': kind.name, 'v': variant};

  static ChartRewrite? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = SectionKind.values.where((k) => k.name == j['k']).firstOrNull;
    final s = j['s'], e = j['e'], v = j['v'];
    if (kind == null || s is! num || e is! num || e <= s) return null;
    return ChartRewrite(s.toDouble(), e.toDouble(), kind, variant: v is int ? v : 0);
  }
}

/// A user's changes to a base's sections: their own layout (kinds, names,
/// boundaries) and sample-note rewrites. Kept apart from the base so they
/// can be saved per base file and re-applied over the automatic result
/// whenever the base is prepared again.
///
/// Sections are labels over the notes: relabelling, renaming, splitting,
/// merging or moving a boundary changes visuals and mix variation only;
/// notes change only through a rewrite.
class SectionEdits {
  const SectionEdits({this.layout, this.rewrites = const []});

  final List<Section>? layout;
  final List<ChartRewrite> rewrites;

  bool get isEmpty => layout == null && rewrites.isEmpty;

  /// The base with these edits applied. A layout that no longer fits the
  /// base (e.g. the project changed length) is ignored.
  SpartaBase apply(SpartaBase auto, {required BaseStyle style, required int seed}) {
    final sections = fits(auto) ? layout! : auto.sections;
    if (rewrites.isEmpty || !auto.canRewriteChart || auto.sections.isEmpty) {
      return identical(sections, auto.sections) ? auto : auto.copyWith(sections: sections);
    }
    final bpb = auto.beatsPerBar.toDouble();
    final limit = auto.sections.last.endBeat;
    var chart = [...auto.chart];
    for (final r in rewrites) {
      final bar0 = (r.startBeat / bpb).round();
      final bar1 = math.min((r.endBeat / bpb).round(), (limit / bpb).round());
      if (bar1 <= bar0) continue;
      final a = bar0 * bpb, z = bar1 * bpb;
      chart = [
        for (final n in chart)
          if (!(auto.composedRoles.contains(n.role) && n.beat >= a - 1e-9 && n.beat < z - 1e-9)) n,
        ...composeSectionChart(
          auto,
          kind: r.kind,
          bar0: bar0,
          bars: bar1 - bar0,
          style: style,
          seed: seed,
          variant: r.variant,
        ),
      ];
    }
    chart.sort((x, y) => x.beat != y.beat ? x.beat.compareTo(y.beat) : x.role.index.compareTo(y.role.index));
    return auto.copyWith(sections: sections, chart: chart);
  }

  /// Whether the saved layout covers exactly the base's sections.
  bool fits(SpartaBase auto) {
    final l = layout;
    if (l == null || l.isEmpty || auto.sections.isEmpty) return false;
    if ((l.first.startBeat - auto.sections.first.startBeat).abs() > 1e-6) return false;
    if ((l.last.endBeat - auto.sections.last.endBeat).abs() > 1e-6) return false;
    for (var i = 0; i < l.length; i++) {
      if (l[i].endBeat <= l[i].startBeat) return false;
      if (i > 0 && (l[i].startBeat - l[i - 1].endBeat).abs() > 1e-6) return false;
    }
    return true;
  }

  SectionEdits _withLayout(List<Section> l) => SectionEdits(layout: List.unmodifiable(l), rewrites: rewrites);

  /// Adds a rewrite, dropping earlier ones it covers completely.
  SectionEdits _withRewrite(ChartRewrite r) => SectionEdits(
    layout: layout,
    rewrites: [
      for (final o in rewrites)
        if (!(o.startBeat >= r.startBeat - 1e-9 && o.endBeat <= r.endBeat + 1e-9)) o,
      r,
    ],
  );

  /// Changes the kind of section [i]; with [rewrite], its notes are
  /// recomposed in that style too.
  SectionEdits relabel(List<Section> current, int i, SectionKind kind, {bool rewrite = false}) {
    final s = current[i];
    // The old name (e.g. "perc intro") no longer describes it.
    final l = [...current]..[i] = Section(kind, s.startBeat, s.endBeat);
    final e = _withLayout(l);
    return rewrite ? e._withRewrite(ChartRewrite(s.startBeat, s.endBeat, kind, variant: _nextVariant(s))) : e;
  }

  /// A custom name for section [i] (empty restores the kind's name).
  SectionEdits rename(List<Section> current, int i, String name) {
    final s = current[i];
    return _withLayout([...current]..[i] = Section(s.kind, s.startBeat, s.endBeat, name: name.trim()));
  }

  /// Splits section [i] at [beat] (a bar line strictly inside it); both
  /// halves keep its kind and name.
  SectionEdits split(List<Section> current, int i, double beat) {
    final s = current[i];
    if (beat <= s.startBeat + 1e-9 || beat >= s.endBeat - 1e-9) return this;
    return _withLayout([
      ...current.take(i),
      Section(s.kind, s.startBeat, beat, name: s.name),
      Section(s.kind, beat, s.endBeat, name: s.name),
      ...current.skip(i + 1),
    ]);
  }

  /// Joins section [i] with the next one; the result keeps section [i]'s
  /// kind and name.
  SectionEdits mergeWithNext(List<Section> current, int i) {
    if (i + 1 >= current.length) return this;
    final s = current[i];
    return _withLayout([
      ...current.take(i),
      Section(s.kind, s.startBeat, current[i + 1].endBeat, name: s.name),
      ...current.skip(i + 2),
    ]);
  }

  /// Moves the boundary between sections [i] and [i] + 1 to the bar line
  /// nearest [beat], keeping both at least one bar long.
  SectionEdits moveBoundary(List<Section> current, int i, double beat, int beatsPerBar) {
    if (i + 1 >= current.length) return this;
    final a = current[i], b = current[i + 1];
    final bpb = beatsPerBar.toDouble();
    final at = ((beat / bpb).round() * bpb).clamp(a.startBeat + bpb, b.endBeat - bpb).toDouble();
    if (at <= a.startBeat || at >= b.endBeat || (at - a.endBeat).abs() < 1e-9) return this;
    return _withLayout(
      [...current]
        ..[i] = Section(a.kind, a.startBeat, at, name: a.name)
        ..[i + 1] = Section(b.kind, at, b.endBeat, name: b.name),
    );
  }

  /// New notes for section [i], in the style of its kind.
  SectionEdits reroll(List<Section> current, int i) {
    final s = current[i];
    return _withRewrite(ChartRewrite(s.startBeat, s.endBeat, s.kind, variant: _nextVariant(s) + 1));
  }

  int _nextVariant(Section s) => rewrites
      .where((r) => r.startBeat < s.endBeat - 1e-9 && r.endBeat > s.startBeat + 1e-9)
      .fold(0, (m, r) => math.max(m, r.variant));

  Map<String, Object> toJson() => {
    if (layout != null)
      'layout': [
        for (final s in layout!)
          {'s': s.startBeat, 'e': s.endBeat, 'k': s.kind.name, if (s.name.isNotEmpty) 'n': s.name},
      ],
    'rewrites': [for (final r in rewrites) r.toJson()],
  };

  static SectionEdits fromJson(Object? j) {
    if (j is! Map) return const SectionEdits();
    List<Section>? layout;
    final l = j['layout'];
    if (l is List) {
      final parsed = <Section>[];
      for (final x in l) {
        if (x is! Map) continue;
        final kind = SectionKind.values.where((k) => k.name == x['k']).firstOrNull;
        final s = x['s'], e = x['e'], n = x['n'];
        if (kind == null || s is! num || e is! num) continue;
        parsed.add(Section(kind, s.toDouble(), e.toDouble(), name: n is String ? n : null));
      }
      if (parsed.isNotEmpty) layout = List.unmodifiable(parsed);
    }
    final r = j['rewrites'];
    return SectionEdits(
      layout: layout,
      rewrites: [
        if (r is List)
          for (final x in r) ?ChartRewrite.fromJson(x),
      ],
    );
  }
}

/// A built-in base with [rewrites] applied to its music as well as its
/// sample chart: each range is composed afresh as its kind (its own chords
/// and parts), so a section relabelled "madness" also sounds like one.
Composition rewriteComposition(Composition comp, List<ChartRewrite> rewrites) {
  final base = comp.base;
  if (rewrites.isEmpty || base.sections.isEmpty) return comp;
  final bpb = base.beatsPerBar.toDouble();
  final limit = base.sections.last.endBeat;
  var score = [...comp.score];
  var chart = [...base.chart];
  final roots = [...base.barRoots];
  bool inRange(double beat, double a, double z) => beat >= a - 1e-9 && beat < z - 1e-9;
  for (final r in rewrites) {
    final bar0 = (r.startBeat / bpb).round();
    final bar1 = math.min((r.endBeat / bpb).round(), (limit / bpb).round());
    if (bar1 <= bar0) continue;
    final a = bar0 * bpb, z = bar1 * bpb;
    final sub = Composer(
      style: comp.style,
      seed: sectionSeed(comp.seed, r.kind, bar0, r.variant),
    ).compose([SectionPlan(r.kind, bar1 - bar0)]);
    // Splice the new events in where the old ones were: the renderer draws
    // noise in score order, so everything before the section stays
    // sample-identical.
    final fresh = [
      for (final e in sub.score)
        if (e.beat < z - a - 1e-9) ScoreEvent(e.instrument, e.beat + a, e.length, midi: e.midi, velocity: e.velocity),
    ];
    final kept = <ScoreEvent>[];
    var placed = false;
    for (final e in score) {
      if (inRange(e.beat, a, z)) {
        if (!placed) kept.addAll(fresh);
        placed = true;
      } else {
        kept.add(e);
      }
    }
    if (!placed) kept.addAll(fresh);
    score = kept;
    chart = [
      for (final n in chart)
        if (!(base.composedRoles.contains(n.role) && inRange(n.beat, a, z))) n,
      for (final n in sub.base.chart)
        if (n.role != SampleRole.quote && base.composedRoles.contains(n.role) && n.beat < z - a - 1e-9)
          n.copyWith(beat: n.beat + a),
    ];
    for (var b = bar0; b < bar1 && b < roots.length && b - bar0 < sub.base.barRoots.length; b++) {
      roots[b] = sub.base.barRoots[b - bar0];
    }
  }
  chart.sort((x, y) => x.beat != y.beat ? x.beat.compareTo(y.beat) : x.role.index.compareTo(y.role.index));
  return Composition(
    base.copyWith(chart: chart, barRoots: roots),
    score,
    style: comp.style,
    seed: comp.seed,
  );
}

/// A short stable signature of [rewrites] (for render caches).
String rewritesKey(List<ChartRewrite> rewrites) {
  if (rewrites.isEmpty) return '';
  var h = 0x811c9dc5;
  for (final c in rewrites.map((r) => '${r.kind.index}:${r.startBeat}:${r.endBeat}:${r.variant}').join(';').codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return 'rw${h.toRadixString(16)}';
}
