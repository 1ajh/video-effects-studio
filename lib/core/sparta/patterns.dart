import 'dart:math' as math;

part 'pattern_data.dart';

/// What a pattern's numbers mean.
enum PatternKind {
  /// Semitones from the base's root, played by the pitch sample.
  pitch,

  /// Which chorus word plays (1, 2, 3, 3A, 3B…): the words of the remix's
  /// line, in order.
  words,

  /// Percussion: 1 kick, 2 snare/clap, 3 hi-hat.
  drums,
}

/// One hit of a pattern on the 16th-note grid.
class PatternHit {
  const PatternHit(this.step, this.length, {this.semitone = 0, this.slot = ''});

  /// Start, in 16th-note steps from the pattern's start.
  final double step;

  /// Length in 16th-note steps.
  final double length;

  /// Pitch patterns: semitones from the root.
  final int semitone;

  /// Word / drum patterns: which sample ('1', '2', '3A', …).
  final String slot;

  double get end => step + length;

  PatternHit shifted(double by) => PatternHit(step + by, length, semitone: semitone, slot: slot);

  @override
  String toString() => slot.isEmpty ? '$semitone@$step+$length' : '$slot@$step+$length';
}

/// A parsed pattern: its hits and its length on the 16th-note grid.
class Pattern {
  Pattern({
    required this.kind,
    required this.hits,
    required this.steps,
    this.id = '',
    this.name = '',
    this.section = '',
    this.group = '',
    this.page = '',
    this.source = const [],
    this.classic = false,
    this.irregular = false,
  });

  final PatternKind kind;

  /// Sorted by step.
  final List<PatternHit> hits;

  /// Length in 16th-note steps (rounded up to whole bars when looping).
  final double steps;

  /// Stable id: "kind/section/name".
  final String id;
  final String name;

  /// Section it belongs to on the wiki (chorus, dundundenden, epicness…),
  /// or 'custom' / 'execution' / 'chords' / 'twist' / 'craziness'.
  final String section;
  final String group;

  /// Wiki page the pattern comes from.
  final String page;

  /// The notation as written on the wiki (one line per layer).
  final List<String> source;

  /// One of the original patterns everyone knows.
  final bool classic;

  /// Its length as written on the wiki isn't a whole number of bars, so
  /// it's never picked on its own (random mode skips it).
  final bool irregular;

  int get bars => math.max(1, (steps / 16).ceil());

  /// Distinct samples a word/drum pattern uses, in order of first use.
  List<String> get slots {
    final out = <String>[];
    for (final h in hits) {
      if (h.slot.isNotEmpty && !out.contains(h.slot)) out.add(h.slot);
    }
    return out;
  }

  String get title => group.isEmpty || group == name ? name : '$group › $name';

  /// The hits repeated to fill [totalSteps] (the last repeat is cut).
  List<PatternHit> looped(double totalSteps) {
    final loop = bars * 16.0;
    final out = <PatternHit>[];
    for (var at = 0.0; at < totalSteps - 1e-9; at += loop) {
      for (final h in hits) {
        final s = at + h.step;
        if (s >= totalSteps - 1e-9) break;
        out.add(PatternHit(s, math.min(h.length, totalSteps - s), semitone: h.semitone, slot: h.slot));
      }
    }
    return out;
  }
}

class PatternFormatException implements FormatException {
  PatternFormatException(this.message, [this.source, this.offset]);
  @override
  final String message;
  @override
  final dynamic source;
  @override
  final int? offset;
  @override
  String toString() => 'Pattern: $message';
}

/// Reads the Sparta Remix Wiki's pattern notation.
///
/// Durations, in 16th-note steps: a bare number or digit is a 16th, `*` an
/// 8th, `**` a dotted 8th, `***` a quarter, `****` a half, `*****` a
/// dotted quarter (as used on the wiki), `******` a whole note; `'` or `#`
/// a 32nd and `''` or `"` a 64th. Rests: `_` a 16th, `/` a 32nd, `\` a 64th.
/// Pitch patterns are semitones from the root (`-2`, `12`, `+3`); word and
/// drum patterns are sample numbers, one digit per hit, optionally
/// followed by A/B (`3A`). Extra lines of a layered pattern play at the
/// same time as the first, aligned by column the way the wiki draws them.
class PatternNotation {
  const PatternNotation._();

  static const _starSteps = {0: 1.0, 1: 2.0, 2: 3.0, 3: 4.0, 4: 8.0, 5: 6.0, 6: 16.0, 7: 16.0};

  static double _duration(String marks) {
    if (marks.isEmpty) return 1;
    final stars = marks.split('').where((c) => c == '*').length;
    if (stars > 0) {
      final base = _starSteps[stars] ?? 16.0;
      return base;
    }
    var d = 1.0;
    for (final c in marks.split('')) {
      if (c == '\'' || c == '#') d /= 2;
      if (c == '"') d /= 4;
    }
    return d;
  }

  static bool _isMark(String c) => c == '*' || c == '\'' || c == '"' || c == '#';
  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  /// Parses [lines] of [kind]; extra lines are layered over the first.
  static Pattern parse(PatternKind kind, List<String> lines, {double? steps}) {
    if (lines.isEmpty || lines.first.trim().isEmpty) throw PatternFormatException('empty pattern');
    final first = kind == PatternKind.pitch ? _pitchLine(lines.first) : _slotLine(lines.first);
    final hits = [...first.hits];
    var length = first.length;
    for (final extra in lines.skip(1)) {
      final layer = kind == PatternKind.pitch && !_hasLeadingRests(extra)
          ? _pitchLine(extra)
          : (kind == PatternKind.pitch
                ? _pitchLine(extra, columns: first.columns)
                : _slotLine(extra, columns: first.columns));
      hits.addAll(layer.hits);
      length = math.max(length, layer.length);
    }
    hits.sort((a, b) => a.step != b.step ? a.step.compareTo(b.step) : a.slot.compareTo(b.slot));
    return Pattern(kind: kind, hits: hits, steps: steps ?? length, source: lines);
  }

  static bool _hasLeadingRests(String s) => s.trimLeft().startsWith('___');

  /// Word / drum line: one hit per digit.
  static _Line _slotLine(String text, {List<double>? columns}) {
    final hits = <PatternHit>[];
    final cols = <double>[];
    var t = 0.0;
    var i = 0;
    double at(int col) {
      if (columns == null) return t;
      if (col < columns.length) return columns[col];
      return columns.isEmpty ? col.toDouble() : columns.last + (col - columns.length + 1);
    }

    while (i < text.length) {
      final c = text[i];
      if (_isDigit(c)) {
        final start = columns == null ? t : at(i);
        var slot = c;
        var j = i + 1;
        if (j < text.length && (text[j] == 'A' || text[j] == 'B')) {
          slot += text[j];
          j++;
        }
        final m0 = j;
        while (j < text.length && _isMark(text[j])) {
          j++;
        }
        final d = _duration(text.substring(m0, j));
        hits.add(PatternHit(start, d, slot: slot));
        for (var k = i; k < j; k++) {
          cols.add(t);
        }
        t = start + d;
        i = j;
      } else if (c == '_' || c == '/' || c == '\\') {
        cols.add(t);
        final d = c == '_' ? 1.0 : (c == '/' ? 0.5 : 0.25);
        t = (columns == null ? t : at(i)) + d;
        i++;
      } else if (c == ' ' || c == '\t') {
        cols.add(t);
        i++;
      } else {
        throw PatternFormatException('unexpected "$c"', text, i);
      }
    }
    return _Line(hits, t, cols);
  }

  /// Pitch line: signed numbers with duration marks.
  static _Line _pitchLine(String text, {List<double>? columns}) {
    final s = text.replaceAll('|', ' ').replaceAll(',', ' ');
    final spaced = s.trim().contains(' ');
    final hasMarks = s.contains(RegExp('[*\'"]'));
    final hits = <PatternHit>[];
    final cols = <double>[];
    var t = 0.0;
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '-' || c == '+' || _isDigit(c)) {
        var sign = 1;
        var j = i;
        if (c == '-' || c == '+') {
          sign = c == '-' ? -1 : 1;
          j++;
          // "-2" only: a lone sign (typo) is skipped.
          if (j >= s.length || !_isDigit(s[j])) {
            cols.add(t);
            i = j;
            continue;
          }
        }
        final d0 = j;
        while (j < s.length && _isDigit(s[j])) {
          j++;
        }
        final digits = s.substring(d0, j);
        // Compact runs like "0011" are single digits; numbers only reach 32.
        final split = digits.length >= 3 || (!spaced && !hasMarks && digits.length > 1);
        final values = split ? digits.split('').map(int.parse).toList() : [int.parse(digits)];
        final m0 = j;
        while (j < s.length && _isMark(s[j])) {
          j++;
        }
        final marks = s.substring(m0, j);
        for (var k = 0; k < values.length; k++) {
          final last = k == values.length - 1;
          final d = last ? _duration(marks) : 1.0;
          final start = columns != null && k == 0 ? _col(columns, i) : t;
          hits.add(PatternHit(start, d, semitone: (k == 0 ? sign : 1) * values[k]));
          t = start + d;
        }
        for (var k = i; k < j; k++) {
          cols.add(t);
        }
        i = j;
      } else if (c == '_' || c == '/' || c == '\\') {
        cols.add(t);
        t += c == '_' ? 1.0 : (c == '/' ? 0.5 : 0.25);
        i++;
      } else if (c == ' ' || c == '\t') {
        cols.add(t);
        i++;
      } else {
        throw PatternFormatException('unexpected "$c"', text, i);
      }
    }
    return _Line(hits, t, cols);
  }

  static double _col(List<double> columns, int col) =>
      col < columns.length ? columns[col] : (columns.isEmpty ? 0 : columns.last + (col - columns.length + 1));

  /// Writes [hits] back in wiki notation (one line; rests as `_`).
  static String format(PatternKind kind, List<PatternHit> hits, {double? steps}) {
    final b = StringBuffer();
    var t = 0.0;
    final sorted = [...hits]..sort((a, c) => a.step.compareTo(c.step));
    for (final h in sorted) {
      while (h.step - t >= 1 - 1e-9) {
        b.write('_');
        t += 1;
      }
      while (h.step - t >= 0.5 - 1e-9) {
        b.write('/');
        t += 0.5;
      }
      if (kind == PatternKind.pitch && b.isNotEmpty) b.write(' ');
      b.write(kind == PatternKind.pitch ? '${h.semitone}' : h.slot);
      b.write(_marks(h.length));
      t = h.step + h.length;
    }
    final end = steps ?? t;
    while (end - t >= 1 - 1e-9) {
      b.write('_');
      t += 1;
    }
    return b.toString();
  }

  static String _marks(double len) {
    if ((len - 1).abs() < 1e-9) return '';
    if ((len - 0.5).abs() < 1e-9) return '\'';
    if ((len - 0.25).abs() < 1e-9) return '"';
    for (final e in _starSteps.entries) {
      if (e.key > 0 && (e.value - len).abs() < 1e-9) return '*' * e.key;
    }
    return '*';
  }
}

class _Line {
  _Line(this.hits, this.length, this.columns);
  final List<PatternHit> hits;
  final double length;

  /// Time at each character column (for aligning layered lines).
  final List<double> columns;
}

class _WikiPattern {
  const _WikiPattern(
    this.kind,
    this.section,
    this.name,
    this.page,
    this.lines, {
    this.group = '',
    this.layered = false,
    this.classic = false,
  });
  final PatternKind kind;
  final String section;
  final String name;
  final String page;
  final List<String> lines;
  final String group;
  final bool layered;
  final bool classic;
}

/// Where the wiki's text can't be read literally.
const _overrides = <(PatternKind, String, String), List<String>>{
  // The wiki writes the one-bar pattern out five and a half times.
  (PatternKind.words, 'dundundenden', 'DunDunDenDen'): ['1___2___3A___3B___'],
};

/// Every pattern documented on the Sparta Remix Wiki, parsed.
class PatternLibrary {
  PatternLibrary._(this.all);

  static final PatternLibrary instance = PatternLibrary._(_load());

  final List<Pattern> all;

  static List<Pattern> _load() {
    final out = <Pattern>[];
    final ids = <String>{};
    for (final w in _wikiPatterns) {
      // Progression twists describe chord roots, not a rhythm.
      if (w.section == 'twist') continue;
      final lines = _overrides[(w.kind, w.section, w.name)] ?? (w.layered ? w.lines : [w.lines.first]);
      Pattern p;
      try {
        p = PatternNotation.parse(w.kind, lines);
      } on PatternFormatException {
        continue;
      }
      if (p.hits.isEmpty) continue;
      // Hand-typed patterns are often a step or two off: snap to whole bars.
      var steps = p.steps;
      var hits = p.hits;
      final bar = (steps / 16).round() * 16.0;
      final irregular = !(bar > 0 && (steps - bar).abs() <= 3) && steps % 8 != 0;
      if (!irregular && bar > 0 && (steps - bar).abs() <= 3) {
        steps = bar;
        hits = [
          for (final h in hits)
            if (h.step < bar - 1e-9)
              PatternHit(h.step, math.min(h.length, bar - h.step), semitone: h.semitone, slot: h.slot),
        ];
      }
      var id = '${w.kind.name}/${w.section}/${w.group.isEmpty ? '' : '${w.group}/'}${w.name}';
      var n = 2;
      while (!ids.add(id)) {
        id = '${w.kind.name}/${w.section}/${w.name} ($n)';
        n++;
      }
      out.add(
        Pattern(
          kind: w.kind,
          hits: hits,
          steps: steps,
          id: id,
          name: w.name,
          section: w.section,
          group: w.group,
          page: w.page,
          source: w.lines,
          classic: w.classic,
          irregular: irregular,
        ),
      );
    }
    return out;
  }

  Pattern? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  Iterable<Pattern> of(PatternKind kind, {String? section, bool classicOnly = false}) =>
      all.where((p) => p.kind == kind && (section == null || p.section == section) && (!classicOnly || p.classic));

  /// The original pattern for [section], if the wiki has one.
  Pattern? classic(PatternKind kind, String section) {
    for (final p in all) {
      if (p.kind == kind && p.section == section && p.classic) return p;
    }
    return null;
  }

  /// Parses a pattern typed by the user (wiki notation).
  static Pattern custom(PatternKind kind, String text) {
    final lines = text.split('\n').map((l) => l.trimRight()).where((l) => l.trim().isNotEmpty).toList();
    final p = PatternNotation.parse(kind, lines);
    if (p.hits.isEmpty) throw PatternFormatException('no notes');
    return Pattern(
      kind: kind,
      hits: p.hits,
      steps: p.steps,
      id: 'custom',
      name: 'Custom',
      section: 'custom',
      source: lines,
    );
  }
}
