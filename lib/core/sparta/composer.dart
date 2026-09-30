import 'dart:math' as math;

import 'base.dart';
import 'model.dart';

/// Instruments of the synthesized built-in bases.
enum Instrument { kick, snare, clap, hat, openHat, crash, tom, riser, bass, stab, pad }

/// One note for the base synthesizer.
class ScoreEvent {
  const ScoreEvent(this.instrument, this.beat, this.length, {this.midi = const [], this.velocity = 1});
  final Instrument instrument;
  final double beat;
  final double length;
  final List<double> midi;
  final double velocity;
}

/// Built-in base styles (all original compositions in the Sparta idiom:
/// 4/4, D Phrygian, the D–E♭–C–E♭ movement).
enum BaseStyle {
  classic('Sparta Classic', 140, 'Punchy orchestral stabs, four-on-the-floor, 140 BPM'),
  hyper('Sparta Hyper', 160, 'Faster, brighter and busier, 160 BPM'),
  venom('Sparta Venom', 150, 'Darker supersaws and heavier low end, 150 BPM');

  const BaseStyle(this.label, this.bpm, this.blurb);
  final String label;
  final double bpm;
  final String blurb;
}

class SectionPlan {
  const SectionPlan(this.kind, this.bars);
  final SectionKind kind;
  final int bars;

  Map<String, Object?> toJson() => {'kind': kind.name, 'bars': bars};
  factory SectionPlan.fromJson(Map<String, Object?> j) =>
      SectionPlan(SectionKind.values.byName(j['kind']! as String), (j['bars']! as num).toInt());
}

/// Structure presets for built-in / audio-only bases.
enum RemixLength {
  short('Short', 0.5),
  standard('Standard', 1.0),
  extended('Extended', 1.5);

  const RemixLength(this.label, this.factor);
  final String label;
  final double factor;
}

List<SectionPlan> defaultPlan({RemixLength length = RemixLength.standard, Set<SectionKind>? enabled}) {
  const base = [
    SectionPlan(SectionKind.intro, 4),
    SectionPlan(SectionKind.chorus, 8),
    SectionPlan(SectionKind.dundundenden, 8),
    SectionPlan(SectionKind.epicness, 8),
    SectionPlan(SectionKind.madness, 8),
    SectionPlan(SectionKind.awesomeness, 8),
    SectionPlan(SectionKind.outro, 4),
  ];
  return [
    for (final p in base)
      if (enabled == null || enabled.contains(p.kind))
        SectionPlan(
          p.kind,
          p.kind == SectionKind.intro || p.kind == SectionKind.outro
              ? p.bars
              : math.max(4, ((p.bars * length.factor) / 4).round() * 4),
        ),
  ];
}

/// D Phrygian (== G natural minor) in semitones above D.
const phrygian = [0, 1, 3, 5, 7, 8, 10];

/// The sample chart of one section, written as [kind] over bars
/// [bar0, bar0 + bars) of [base]: over the base's own chords and in its key,
/// on the lanes the composer owns (never the quote). [variant] gives
/// another take.
List<ChartNote> composeSectionChart(
  SpartaBase base, {
  required SectionKind kind,
  required int bar0,
  required int bars,
  required BaseStyle style,
  required int seed,
  int variant = 0,
}) {
  if (bars <= 0) return const [];
  final roots = base.barRoots.isEmpty ? null : [for (var b = 0; b < bars; b++) base.rootAtBar(bar0 + b)];
  final comp = Composer(
    style: style,
    seed: seed * 7919 + variant * 104729 + bar0 * 31 + kind.index,
  ).compose([SectionPlan(kind, bars)], barRoots: roots);
  final shift = base.chartShift ?? 0;
  final offset = bar0 * base.beatsPerBar.toDouble();
  final end = bars * base.beatsPerBar.toDouble();
  return [
    for (final n in comp.base.chart)
      if (n.role != SampleRole.quote && base.composedRoles.contains(n.role) && n.beat < end)
        n.copyWith(beat: n.beat + offset, semitone: n.role.isTonal ? n.semitone + shift : n.semitone),
  ];
}

/// Result of composing a built-in base.
class Composition {
  Composition(this.base, this.score, {required this.style, required this.seed});
  final SpartaBase base;
  final List<ScoreEvent> score;
  final BaseStyle style;
  final int seed;
}

/// Writes both the instrumental score and the sample chart, step by step on
/// a shared 16th-note grid.
class Composer {
  Composer({this.style = BaseStyle.classic, this.seed = 1});

  final BaseStyle style;
  final int seed;

  static const stepsPerBar = 16;
  static double beatOf(int bar, int step) => bar * 4 + step / 4;

  /// Composes [plan]. [barRoots] (semitones from D per bar) overrides the
  /// built-in progressions, used when charting over an existing base.
  Composition compose(List<SectionPlan> plan, {Map<SectionKind, int> sectionSeeds = const {}, List<int>? barRoots}) {
    final score = <ScoreEvent>[];
    final chart = <ChartNote>[];
    final sections = <Section>[];
    final roots = <int>[];
    var bar = 0;
    for (var i = 0; i < plan.length; i++) {
      final p = plan[i];
      final rng = math.Random(seed * 7919 + (sectionSeeds[p.kind] ?? 0) * 104729 + i * 31);
      final w = _SectionWriter(
        this,
        p.kind,
        bar,
        p.bars,
        rng,
        score,
        chart,
        isLast: i == plan.length - 1,
        rootOverride: barRoots,
      );
      w.write();
      roots.addAll(w.roots);
      sections.add(Section(p.kind, bar * 4.0, (bar + p.bars) * 4.0));
      bar += p.bars;
    }
    final base = SpartaBase(
      id: 'builtin_${style.name}',
      name: style.label,
      author: 'Video Effects Studio',
      bpm: style.bpm,
      kind: BaseKind.builtIn,
      sections: sections,
      chart: _dedupe(chart),
      lengthBeats: bar * 4.0 + 4, // one bar of tail
      barRoots: roots,
      chartShift: 0,
      composedRoles: const {SampleRole.pitch, SampleRole.chop, SampleRole.kick, SampleRole.snare, SampleRole.hat},
    );
    return Composition(base, score, style: style, seed: seed);
  }

  /// One hit per lane, beat and pitch (fills can land on groove hits);
  /// the longer, louder note wins.
  static List<ChartNote> _dedupe(List<ChartNote> chart) {
    final best = <String, ChartNote>{};
    for (final n in chart) {
      final key = '${n.role.index}|${n.beat}|${n.role.isTonal ? n.semitone : 0}';
      final prev = best[key];
      if (prev == null || n.length * n.velocity > prev.length * prev.velocity) best[key] = n;
    }
    return best.values.toList()
      ..sort((a, b) => a.beat != b.beat ? a.beat.compareTo(b.beat) : a.role.index.compareTo(b.role.index));
  }
}

class _SectionWriter {
  _SectionWriter(
    this.c,
    this.kind,
    this.bar0,
    this.bars,
    this.rng,
    this.score,
    this.chart, {
    required this.isLast,
    this.rootOverride,
  });

  final Composer c;
  final SectionKind kind;
  final int bar0;
  final int bars;
  final math.Random rng;
  final List<ScoreEvent> score;
  final List<ChartNote> chart;
  final bool isLast;
  final List<int>? rootOverride;
  final List<int> roots = [];

  bool get hyper => c.style == BaseStyle.hyper;
  bool get venom => c.style == BaseStyle.venom;

  // Progressions (root per bar, semitones from D).
  static const _prog = [0, 1, -2, 1];

  int rootAt(int b, [int step = 0]) {
    final o = rootOverride;
    if (o != null && o.isNotEmpty) return o[(bar0 + b).clamp(0, o.length - 1)];
    switch (kind) {
      case SectionKind.intro:
        return 0;
      case SectionKind.dundundenden:
        // Odd bars D→E♭, even bars C→E♭ (each half bar).
        final first = b.isEven ? 0 : -2;
        return step < 8 ? first : 1;
      case SectionKind.outro:
        return const [0, 1, -2, 0][b % 4];
      default:
        return _prog[b % 4];
    }
  }

  void hit(Instrument i, int b, int step, {double len = 0.25, List<double> midi = const [], double vel = 1}) =>
      score.add(ScoreEvent(i, Composer.beatOf(bar0 + b, step), len, midi: midi, velocity: vel));

  void note(SampleRole r, int b, int step, int steps, {int semi = 0, double vel = 1}) => chart.add(
    ChartNote(role: r, beat: Composer.beatOf(bar0 + b, step), length: steps / 4, semitone: semi, velocity: vel),
  );

  List<int> pattern(String p) => [
    for (var i = 0; i < p.length && i < 16; i++)
      if (p[i] == 'x' || p[i] == 'X') i,
  ];

  List<double> power(int root, {int octave = 3}) {
    final r = 26.0 + 12 * (octave - 1) + root; // D1 = 26
    return [r, r + 7, r + 12];
  }

  List<double> minorish(int root) {
    // Chord tones inside D Phrygian for each progression root.
    final r = 62.0 + root; // around D4
    return switch (root) {
      0 => [r, r + 3, r + 7], // D F A
      1 => [r, r + 4, r + 7], // Eb G Bb
      -2 => [r, r + 3, r + 7], // C Eb G
      _ => [r, r + 7, r + 12],
    };
  }

  void write() {
    for (var b = 0; b < bars; b++) {
      roots.add(rootAt(b));
    }
    switch (kind) {
      case SectionKind.intro:
        _intro();
      case SectionKind.chorus:
        _chorus();
      case SectionKind.dundundenden:
        _dundundenden();
      case SectionKind.epicness:
        _epicness();
      case SectionKind.madness:
        _madness();
      case SectionKind.awesomeness:
        _awesomeness();
      case SectionKind.outro:
        _outro();
      case SectionKind.other:
        _chorus();
    }
  }

  // --- drums -----------------------------------------------------------------

  void fourOnFloor(int b, {bool snare = true, bool hats = true, bool sixteenthHats = false}) {
    for (final s in pattern('x...x...x...x...')) {
      hit(Instrument.kick, b, s);
      note(SampleRole.kick, b, s, 2, vel: s == 0 ? 1 : 0.85);
    }
    if (snare) {
      for (final s in pattern('....x.......x...')) {
        hit(Instrument.snare, b, s);
        hit(Instrument.clap, b, s, vel: 0.7);
        note(SampleRole.snare, b, s, 2);
      }
    }
    if (hats) {
      final hp = sixteenthHats ? 'xxxxxxxxxxxxxxxx' : '..x...x...x...x.';
      for (final s in pattern(hp)) {
        hit(Instrument.hat, b, s, vel: s % 4 == 2 ? 0.9 : 0.55);
        if (sixteenthHats && s % 4 == 2) note(SampleRole.hat, b, s, 1, vel: 0.8);
      }
    }
  }

  void fill(int b) {
    for (final s in pattern('............xxxx')) {
      hit(Instrument.snare, b, s, vel: 0.6 + 0.1 * (s - 12));
      note(SampleRole.snare, b, s, 1, vel: 0.7 + 0.075 * (s - 12));
    }
    hit(Instrument.tom, b, 8, midi: [45], vel: 0.8);
    hit(Instrument.tom, b, 10, midi: [41], vel: 0.8);
  }

  void crashAt(int b) => hit(Instrument.crash, b, 0, len: 4);

  // --- tonal -----------------------------------------------------------------

  void bassLine(int b, String rhythm, {bool octaves = true, int stepsLen = 2}) {
    var alt = false;
    for (final s in pattern(rhythm)) {
      final r = rootAt(b, s);
      hit(Instrument.bass, b, s, len: stepsLen / 4 * 0.9, midi: [38.0 + r + (octaves && alt ? 12 : 0)]);
      alt = !alt;
    }
  }

  void stabs(int b, String rhythm, {double len = 0.4, double vel = 1}) {
    for (final s in pattern(rhythm)) {
      hit(Instrument.stab, b, s, len: len, midi: power(rootAt(b, s)), vel: vel);
    }
  }

  void padBar(int b) => hit(Instrument.pad, b, 0, len: 4, midi: minorish(rootAt(b)), vel: 0.8);

  /// Pitch-lane rhythm where each hit lasts until the next one.
  void pitchRhythm(int b, String rhythm, int Function(int step) semi, {int maxLen = 4}) {
    final hits = pattern(rhythm);
    for (var k = 0; k < hits.length; k++) {
      final s = hits[k];
      final next = k + 1 < hits.length ? hits[k + 1] : 16;
      note(SampleRole.pitch, b, s, math.min(maxLen, next - s), semi: semi(s), vel: s % 4 == 0 ? 1 : 0.88);
    }
  }

  // --- sections --------------------------------------------------------------

  void _intro() {
    for (var b = 0; b < bars; b++) {
      hit(Instrument.tom, b, 0, midi: [38], len: 1, vel: 0.9);
      hit(Instrument.bass, b, 0, len: 3.8, midi: [38], vel: 0.6);
      hit(Instrument.pad, b, 0, len: 4, midi: minorish(0), vel: 0.6);
      if (b < bars - 1) {
        hit(Instrument.kick, b, 0);
        stabs(b, 'x...............', len: 1.2);
        if (b > 0) note(SampleRole.pitch, b, 0, 6, semi: b.isOdd ? 12 : 0);
      }
    }
    crashAt(0);
    // The quote opens the remix.
    chart.add(ChartNote(role: SampleRole.quote, beat: bar0 * 4.0, length: (bars - 1) * 4.0));
    // Last bar: build-up into the chorus.
    final last = bars - 1;
    for (final s in pattern('x.x.x.x.xxxxxxxx')) {
      hit(Instrument.snare, last, s, vel: 0.45 + s / 32);
    }
    hit(Instrument.riser, last, 0, len: 4);
    pitchRhythm(last, 'x...x...x.x.xxxx', (s) => s >= 12 ? const [0, 3, 7, 12][s - 12] : 0, maxLen: 4);
  }

  void _chorus() {
    final rhythms = hyper
        ? const ['xx.xx.xxx.x.x.xx', 'x.xx.xx.x.xx.xxx']
        : const ['xx.xx.xxx.x.x.xx', 'xx.x.xx.x.xxx.x.', 'x.x.xx.xx.x.x.xx'];
    for (var b = 0; b < bars; b++) {
      fourOnFloor(b);
      if (b % 2 == 1) hit(Instrument.openHat, b, 14, vel: 0.7);
      bassLine(b, 'x.x.x.x.x.x.x.x.');
      stabs(b, 'x..x..x...x..x..', len: 0.3);
      final rhythm = rhythms[(b ~/ 2) % rhythms.length];
      final lift = b >= bars / 2 && rng.nextBool();
      pitchRhythm(b, rhythm, (s) => rootAt(b, s) + (lift && s >= 8 ? 12 : 0));
      if (b % 2 == 1) {
        for (final s in pattern('............xxxx')) {
          note(SampleRole.chop, b, s, 1, semi: rootAt(b, s) + 12, vel: 0.85);
        }
      }
    }
    crashAt(0);
    fill(bars - 1);
  }

  void _dundundenden() {
    for (var b = 0; b < bars; b++) {
      for (final s in pattern('x.....x...x.....')) {
        hit(Instrument.kick, b, s);
        note(SampleRole.kick, b, s, 2);
      }
      for (final s in pattern('........x.......')) {
        hit(Instrument.snare, b, s);
        note(SampleRole.snare, b, s, 2);
      }
      for (final s in pattern('x.x.x.x.x.x.x.x.')) {
        hit(Instrument.hat, b, s, vel: 0.5);
      }
      bassLine(b, 'x.x.x.x.x.x.x.x.', octaves: false);
      stabs(b, 'x...x...x...x...', len: 0.45);
      // "dun dun den den": two hits per chord, then a 16th pickup.
      pitchRhythm(
        b,
        b % 2 == 1 ? 'x...x...x...xxxx' : 'x...x...x...x...',
        (s) => rootAt(b, s) + (s >= 12 && b % 2 == 1 ? const [0, 0, 12, 12][s - 12] : 0),
      );
    }
    crashAt(0);
    fill(bars - 1);
  }

  void _epicness() {
    for (var b = 0; b < bars; b++) {
      hit(Instrument.kick, b, 0);
      hit(Instrument.kick, b, 10, vel: 0.8);
      note(SampleRole.kick, b, 0, 4);
      hit(Instrument.snare, b, 8);
      hit(Instrument.clap, b, 8, vel: 0.8);
      note(SampleRole.snare, b, 8, 4);
      for (final s in pattern('x...x...x...x...')) {
        hit(Instrument.hat, b, s, vel: 0.4);
      }
      if (b % 2 == 0) crashAt(b);
      padBar(b);
      hit(Instrument.bass, b, 0, len: 3.9, midi: [38.0 + rootAt(b)], vel: 0.9);
      stabs(b, 'x.......x.......', len: 1.5, vel: 0.9);
    }
    _melody(long: true);
    fill(bars - 1);
  }

  void _madness() {
    for (var b = 0; b < bars; b++) {
      fourOnFloor(b, sixteenthHats: true);
      if (b % 4 == 3) {
        for (final s in pattern('..........x.x.xx')) {
          hit(Instrument.kick, b, s, vel: 0.8);
        }
      }
      bassLine(b, 'xxxxxxxxxxxxxxxx', stepsLen: 1);
      stabs(b, 'x.x.x.x.x.x.x.x.', len: 0.2, vel: 0.85);
      if (b % 4 == 0) crashAt(b);
      // Interleaved pitch and chop 16ths.
      final cycle = [0, 12, 0, 7, 0, 12, 7, 12];
      for (var s = 0; s < 16; s++) {
        final r = rootAt(b, s);
        if (s.isEven) {
          note(SampleRole.pitch, b, s, 1, semi: r + cycle[(s ~/ 2 + b) % cycle.length], vel: s % 4 == 0 ? 1 : 0.85);
        } else if (rng.nextDouble() < 0.7) {
          note(SampleRole.chop, b, s, 1, semi: r + 12, vel: 0.8);
        }
      }
    }
    hit(Instrument.riser, bars - 1, 0, len: 4);
    fill(bars - 1);
  }

  void _awesomeness() {
    for (var b = 0; b < bars; b++) {
      fourOnFloor(b);
      if (b.isOdd) hit(Instrument.openHat, b, 14, vel: 0.7);
      bassLine(b, 'x.x.x.x.x.x.x.x.');
      padBar(b);
      stabs(b, 'x..x..x.........', len: 0.35, vel: 0.8);
      if (b % 4 == 0) crashAt(b);
    }
    _melody(long: false);
    fill(bars - 1);
  }

  void _outro() {
    for (var b = 0; b < bars; b++) {
      if (b < bars - 2) {
        fourOnFloor(b);
        bassLine(b, 'x.x.x.x.x.x.x.x.');
        stabs(b, 'x..x..x...x..x..', len: 0.3);
        pitchRhythm(b, b == bars - 3 ? 'x.x.x.x.xxxxxxxx' : 'xx.xx.xxx.x.x.xx', (s) => rootAt(b, s));
      }
    }
    final end = math.max(0, bars - 2);
    crashAt(end);
    hit(Instrument.kick, end, 0);
    hit(Instrument.tom, end, 0, midi: [38], len: 2);
    hit(Instrument.stab, end, 0, len: 3, midi: power(0));
    hit(Instrument.pad, end, 0, len: 6, midi: minorish(0), vel: 0.7);
    note(SampleRole.pitch, end, 0, 8, semi: 0);
    note(SampleRole.snare, end, 0, 2);
    note(SampleRole.kick, end, 0, 2);
    if (isLast) chart.add(ChartNote(role: SampleRole.quote, beat: Composer.beatOf(bar0 + end, 8), length: 6));
  }

  /// Seeded lead melody on the pitch lane: chord tones on beats, scale
  /// passing tones between, occasional octave leaps.
  void _melody({required bool long}) {
    const fast = [
      [4, 4, 4, 4],
      [2, 2, 4, 2, 2, 4],
      [3, 3, 2, 4, 4],
      [2, 2, 2, 2, 4, 4],
      [4, 2, 2, 4, 2, 2],
      [1, 1, 2, 4, 2, 2, 4],
      [3, 3, 3, 3, 4],
    ];
    const slow = [
      [8, 8],
      [12, 4],
      [6, 2, 8],
      [4, 4, 8],
      [16],
    ];
    var prev = 12;
    final scale = [for (var o = -1; o <= 2; o++) ...phrygian.map((d) => d + 12 * o)];
    for (var b = 0; b < bars; b++) {
      final pool = long ? slow : fast;
      // Repeat motifs in pairs of bars for memorability.
      final motif = (b ~/ 2) % 2 == 0 ? pool[rng.nextInt(pool.length)] : pool[(b ~/ 2 + seedBias) % pool.length];
      var step = 0;
      for (final dur in motif) {
        if (step >= 16) break;
        final root = rootAt(b, step);
        int target;
        if (step % 4 == 0) {
          final tones = [root, root + 7, root + 12, root + 19, root - 5];
          tones.sort((a, z) => (a - prev).abs().compareTo((z - prev).abs()));
          target = rng.nextDouble() < 0.2 ? tones[math.min(2, tones.length - 1)] : tones[0];
          if (!long && rng.nextDouble() < 0.12) target += (target < 12 ? 12 : -12);
        } else {
          final idx = scale.indexWhere((d) => d >= prev);
          final dir = rng.nextBool() ? 1 : -1;
          target = scale[(math.max(0, idx) + dir).clamp(0, scale.length - 1)];
        }
        target = target.clamp(-5, 24);
        note(SampleRole.pitch, b, step, math.min(dur, 16 - step), semi: target, vel: step % 4 == 0 ? 1 : 0.85);
        prev = target;
        step += dur;
      }
    }
  }

  int get seedBias => (c.seed + kind.index) % 5;
}
