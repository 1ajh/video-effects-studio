/// Shared data model for the Sparta Remix generator.
library;

import 'dart:math' as math;

/// What a sample does in the remix.
enum SampleRole {
  pitch('Pitch', 'A voiced syllable, tuned to the base\'s key, that plays the base\'s own hit notes'),
  word('Chorus words', 'The words of your line (1, 2, 3…), raw, in the wiki\'s section patterns'),
  kick('Kick', 'A thump from your source, on the base\'s kicks'),
  snare('Snare', 'A crack from your source, on the base\'s snares and claps'),
  hat('Hat', 'A hiss from your source, on the base\'s hi-hats'),
  quote('Quote', 'Your whole line, played in the intro');

  const SampleRole(this.label, this.blurb);
  final String label;
  final String blurb;

  bool get isPercussion => this == kick || this == snare || this == hat;

  /// Transposed per note (only the pitch sample: chorus words play raw).
  bool get isPitched => this == pitch;
}

/// A note on one of the remix's sample lanes.
class ChartNote {
  const ChartNote({
    required this.role,
    required this.beat,
    required this.length,
    this.semitone = 0,
    this.velocity = 1.0,
    this.slot = '',
  });

  final SampleRole role;

  /// Position in beats (quarter notes) from the start of the base.
  final double beat;

  /// Length in beats.
  final double length;

  /// Pitch lane: semitones from the base's root.
  final int semitone;

  /// 0..1
  final double velocity;

  /// Word lane: which word of the line plays ('1', '2', '3A'…).
  final String slot;

  double get end => beat + length;

  ChartNote copyWith({double? beat, double? length, int? semitone, double? velocity, String? slot}) => ChartNote(
    role: role,
    beat: beat ?? this.beat,
    length: length ?? this.length,
    semitone: semitone ?? this.semitone,
    velocity: velocity ?? this.velocity,
    slot: slot ?? this.slot,
  );

  @override
  String toString() => '${role.name}${slot.isEmpty ? '' : '[$slot]'}@$beat+$length/$semitone';
}

/// The parts of a Sparta base (see the Sparta Remix Wiki's components).
enum SectionKind {
  intro('Intro / quote', 'intro'),
  chorus('Chorus', 'chorus'),
  dundundenden('DunDunDenDen', 'dundundenden'),
  preEpicness('Pre-Epicness', 'preEpicness'),
  epicness('Epicness', 'epicness'),
  postEpicness('Post-Epicness', 'postEpicness'),
  awesomeness('Awesomeness', 'awesomeness'),
  madness('Madness', 'madness'),
  outro('Outro', 'outro'),
  other('Section', 'custom');

  const SectionKind(this.label, this.wiki);
  final String label;

  /// The section's name in the pattern library.
  final String wiki;

  static SectionKind? byWiki(String s) {
    for (final k in values) {
      if (k.wiki == s) return k;
    }
    return null;
  }
}

class Section {
  const Section(this.kind, this.startBeat, this.endBeat, {String? name}) : name = name ?? '';

  final SectionKind kind;
  final double startBeat;
  final double endBeat;
  final String name;

  String get title => name.isEmpty ? kind.label : name;
  double get lengthBeats => endBeat - startBeat;
  bool contains(double beat) => beat >= startBeat && beat < endBeat;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'start': startBeat,
    'end': endBeat,
    if (name.isNotEmpty) 'name': name,
  };

  factory Section.fromJson(Map<String, Object?> j) => Section(
    SectionKind.values.asNameMap()[j['kind']] ?? SectionKind.other,
    (j['start']! as num).toDouble(),
    (j['end']! as num).toDouble(),
    name: j['name'] as String?,
  );
}

/// A region of a source clip chosen for a role.
class SampleCandidate {
  const SampleCandidate({
    required this.role,
    required this.sourceIndex,
    required this.start,
    required this.end,
    required this.score,
    this.f0 = 0,
    this.details = const {},
    this.slot = '',
  });

  final SampleRole role;
  final int sourceIndex;

  /// Seconds within the source.
  final double start;
  final double end;

  /// 0..1, higher is better.
  final double score;

  /// Median fundamental (Hz) for voiced candidates.
  final double f0;

  /// Individual scoring terms, for the review UI.
  final Map<String, double> details;

  /// Word lane: which word of the line this is ('1', '2', '3A'…).
  final String slot;

  double get duration => end - start;

  SampleCandidate withRange(double s, double e) => SampleCandidate(
    role: role,
    sourceIndex: sourceIndex,
    start: s,
    end: e,
    score: score,
    f0: f0,
    details: details,
    slot: slot,
  );

  SampleCandidate withSlot(String s) => SampleCandidate(
    role: role,
    sourceIndex: sourceIndex,
    start: start,
    end: end,
    score: score,
    f0: f0,
    details: details,
    slot: s,
  );

  Map<String, Object?> toJson() => {
    'role': role.name,
    'source': sourceIndex,
    'start': start,
    'end': end,
    'score': score,
    'f0': f0,
    if (slot.isNotEmpty) 'slot': slot,
  };

  factory SampleCandidate.fromJson(Map<String, Object?> j) => SampleCandidate(
    role: SampleRole.values.asNameMap()[j['role']] ?? SampleRole.word,
    sourceIndex: (j['source']! as num).toInt(),
    start: (j['start']! as num).toDouble(),
    end: (j['end']! as num).toDouble(),
    score: (j['score'] as num?)?.toDouble() ?? 0,
    f0: (j['f0'] as num?)?.toDouble() ?? 0,
    slot: j['slot'] as String? ?? '',
  );
}

/// One word of the spoken line, with syllable cuts inside it.
class LineWord {
  const LineWord(this.start, this.end, {this.cuts = const []});

  /// Seconds within the source.
  final double start;
  final double end;

  /// Syllable boundaries strictly inside the word (seconds, ascending).
  final List<double> cuts;

  double get duration => end - start;

  /// The word's syllables as (start, end) ranges.
  List<(double, double)> get syllables {
    final edges = [start, ...cuts.where((c) => c > start + 0.01 && c < end - 0.01), end];
    return [for (var i = 0; i + 1 < edges.length; i++) (edges[i], edges[i + 1])];
  }

  LineWord copyWith({double? start, double? end, List<double>? cuts}) =>
      LineWord(start ?? this.start, end ?? this.end, cuts: cuts ?? this.cuts);

  Map<String, Object?> toJson() => {'start': start, 'end': end, if (cuts.isNotEmpty) 'cuts': cuts};

  factory LineWord.fromJson(Map<String, Object?> j) => LineWord(
    (j['start']! as num).toDouble(),
    (j['end']! as num).toDouble(),
    cuts: [for (final c in (j['cuts'] as List?) ?? const []) (c as num).toDouble()],
  );
}

/// A spoken line from a source: the quote, and the words the chorus plays
/// (word 1, 2, 3… in order; syllables of a word are 3A, 3B…).
class SpokenLine {
  const SpokenLine({
    required this.sourceIndex,
    required this.start,
    required this.end,
    required this.words,
    this.score = 0,
    this.details = const {},
  });

  final int sourceIndex;

  /// Seconds within the source (the whole line, used as the quote).
  final double start;
  final double end;
  final List<LineWord> words;

  /// 0..1, higher is better.
  final double score;
  final Map<String, double> details;

  double get duration => end - start;

  /// Every sample key the line offers: '1', '2', … and '3A', '3B' for the
  /// syllables of a word with more than one.
  Map<String, (double, double)> get slots {
    final out = <String, (double, double)>{};
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      out['${i + 1}'] = (w.start, w.end);
      final syl = w.syllables;
      if (syl.length > 1) {
        for (var j = 0; j < syl.length && j < 26; j++) {
          out['${i + 1}${String.fromCharCode(65 + j)}'] = syl[j];
        }
      }
    }
    return out;
  }

  /// The quote as a sample candidate.
  SampleCandidate get quote => SampleCandidate(
    role: SampleRole.quote,
    sourceIndex: sourceIndex,
    start: start,
    end: end,
    score: score,
    details: details,
  );

  /// Word samples, one per slot key.
  List<SampleCandidate> get wordCandidates => [
    for (final e in slots.entries)
      SampleCandidate(
        role: SampleRole.word,
        sourceIndex: sourceIndex,
        start: e.value.$1,
        end: e.value.$2,
        score: score,
        slot: e.key,
      ),
  ];

  SpokenLine withWords(List<LineWord> words) {
    final sorted = [...words]..sort((a, b) => a.start.compareTo(b.start));
    return SpokenLine(
      sourceIndex: sourceIndex,
      start: sorted.isEmpty ? start : math.min(start, sorted.first.start),
      end: sorted.isEmpty ? end : math.max(end, sorted.last.end),
      words: sorted,
      score: score,
      details: details,
    );
  }

  SpokenLine withRange(double s, double e) => SpokenLine(
    sourceIndex: sourceIndex,
    start: s,
    end: e,
    words: [
      for (final w in words)
        if (w.end > s + 0.02 && w.start < e - 0.02) w.copyWith(start: math.max(w.start, s), end: math.min(w.end, e)),
    ],
    score: score,
    details: details,
  );

  /// Splits word [i] in two at [at] seconds.
  SpokenLine splitWord(int i, double at) {
    final w = words[i];
    if (at <= w.start + 0.03 || at >= w.end - 0.03) return this;
    return withWords([
      ...words.take(i),
      LineWord(w.start, at, cuts: w.cuts.where((c) => c < at).toList()),
      LineWord(at, w.end, cuts: w.cuts.where((c) => c > at).toList()),
      ...words.skip(i + 1),
    ]);
  }

  /// Joins word [i] with the next one (the join becomes a syllable cut).
  SpokenLine mergeWithNext(int i) {
    if (i < 0 || i + 1 >= words.length) return this;
    final a = words[i], b = words[i + 1];
    return withWords([
      ...words.take(i),
      LineWord(a.start, b.end, cuts: [...a.cuts, a.end, ...b.cuts]),
      ...words.skip(i + 2),
    ]);
  }

  /// Removes word [i] (a breath or a word you don't want).
  SpokenLine removeWord(int i) => withWords([...words.take(i), ...words.skip(i + 1)]);

  /// Moves the boundary between word [i] and the next to [at].
  SpokenLine moveBoundary(int i, double at) {
    if (i < 0 || i + 1 >= words.length) return this;
    final a = words[i], b = words[i + 1];
    final t = at.clamp(a.start + 0.03, b.end - 0.03).toDouble();
    return withWords([
      ...words.take(i),
      a.copyWith(end: t, cuts: a.cuts.where((c) => c < t - 0.01).toList()),
      b.copyWith(start: t, cuts: b.cuts.where((c) => c > t + 0.01).toList()),
      ...words.skip(i + 2),
    ]);
  }

  /// Sets word [i]'s start / end.
  SpokenLine trimWord(int i, {double? start, double? end}) {
    final w = words[i];
    final s = (start ?? w.start).clamp(i > 0 ? words[i - 1].end : 0.0, w.end - 0.03).toDouble();
    final e = (end ?? w.end).clamp(s + 0.03, i + 1 < words.length ? words[i + 1].start : double.infinity).toDouble();
    return withWords([
      ...words.take(i),
      LineWord(s, e, cuts: w.cuts.where((c) => c > s + 0.01 && c < e - 0.01).toList()),
      ...words.skip(i + 1),
    ]);
  }

  /// Toggles a syllable cut in word [i] at [at] (or removes the nearest one
  /// within 40 ms).
  SpokenLine toggleCut(int i, double at) {
    final w = words[i];
    final near = w.cuts.where((c) => (c - at).abs() < 0.04).toList();
    final cuts = near.isNotEmpty ? w.cuts.where((c) => !near.contains(c)).toList() : ([...w.cuts, at]..sort());
    return withWords([...words.take(i), w.copyWith(cuts: cuts), ...words.skip(i + 1)]);
  }

  Map<String, Object?> toJson() => {
    'source': sourceIndex,
    'start': start,
    'end': end,
    'score': score,
    'words': [for (final w in words) w.toJson()],
  };

  factory SpokenLine.fromJson(Map<String, Object?> j) => SpokenLine(
    sourceIndex: (j['source']! as num).toInt(),
    start: (j['start']! as num).toDouble(),
    end: (j['end']! as num).toDouble(),
    score: (j['score'] as num?)?.toDouble() ?? 0,
    words: [for (final w in (j['words'] as List?) ?? const []) LineWord.fromJson((w as Map).cast<String, Object?>())],
  );
}

/// The sample key a chart's word slot plays, given the keys a line offers.
///
/// Words are numbered in the order they're spoken; a pattern asking for a
/// word the line doesn't have wraps around (word 4 of a 3-word line is word
/// 1), '0' is the last word, and a syllable ('3B') of a one-syllable word is
/// the whole word.
String? wordKeyFor(String slot, Iterable<String> keys) {
  final available = keys.toSet();
  final words = available.where((k) => RegExp(r'^\d+$').hasMatch(k)).length;
  if (words == 0) return null;
  final m = RegExp(r'^(\d+)([A-Z]?)$').firstMatch(slot);
  if (m == null) return '1';
  final n = int.parse(m.group(1)!);
  final idx = n == 0 ? words : (n - 1) % words + 1;
  final letter = m.group(2)!;
  if (letter.isEmpty) return '$idx';
  if (available.contains('$idx$letter')) return '$idx$letter';
  if (available.contains('${idx}A')) {
    // Fewer syllables than asked for: the last one.
    var last = 'A';
    for (var c = 66; c < 91; c++) {
      if (!available.contains('$idx${String.fromCharCode(c)}')) break;
      last = String.fromCharCode(c);
    }
    return '$idx$last';
  }
  return '$idx';
}
