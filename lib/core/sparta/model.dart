/// Shared data model for the Sparta Remix generator.
library;

/// What a sample does in the remix.
enum SampleRole {
  pitch('Pitch', 'Voiced sample tuned to D and played as the melody'),
  chop('Chop', 'Short punchy syllable for the chorus hits'),
  kick('Kick', 'Low thump layered on the kick drum'),
  snare('Snare', 'Crack layered on the snare'),
  hat('Hat', 'Short hiss used as hi-hat'),
  quote('Quote', 'The spoken line that opens the remix');

  const SampleRole(this.label, this.blurb);
  final String label;
  final String blurb;

  bool get isPercussion => this == kick || this == snare || this == hat;
  bool get isTonal => this == pitch || this == chop;
}

/// A note on one of the base's sample lanes.
class ChartNote {
  const ChartNote({
    required this.role,
    required this.beat,
    required this.length,
    this.semitone = 0,
    this.velocity = 1.0,
  });

  final SampleRole role;

  /// Position in beats (quarter notes) from the start of the base.
  final double beat;

  /// Length in beats.
  final double length;

  /// Semitones relative to the sample's root D.
  final int semitone;

  /// 0..1
  final double velocity;

  double get end => beat + length;

  ChartNote copyWith({double? beat, double? length, int? semitone, double? velocity}) => ChartNote(
    role: role,
    beat: beat ?? this.beat,
    length: length ?? this.length,
    semitone: semitone ?? this.semitone,
    velocity: velocity ?? this.velocity,
  );

  @override
  String toString() => '${role.name}@$beat+$length/$semitone';
}

/// Kind of section (drives the generated patterns and visuals).
enum SectionKind {
  intro('Intro / quote'),
  chorus('Chorus'),
  dundundenden('Dundundenden'),
  epicness('Epicness'),
  madness('Madness'),
  awesomeness('Awesomeness'),
  outro('Outro'),
  other('Section');

  const SectionKind(this.label);
  final String label;

  /// 0 calm … 1 chaotic; drives grid sizes and chop density.
  double get intensity => switch (this) {
    SectionKind.intro => 0.15,
    SectionKind.chorus => 0.55,
    SectionKind.dundundenden => 0.45,
    SectionKind.epicness => 0.6,
    SectionKind.madness => 1.0,
    SectionKind.awesomeness => 0.8,
    SectionKind.outro => 0.3,
    SectionKind.other => 0.5,
  };
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
  });

  final SampleRole role;
  final int sourceIndex;

  /// Seconds within the source.
  final double start;
  final double end;

  /// 0..1, higher is better.
  final double score;

  /// Median fundamental (Hz) for tonal candidates.
  final double f0;

  /// Individual scoring terms, for the review UI.
  final Map<String, double> details;

  double get duration => end - start;

  SampleCandidate withRange(double s, double e) =>
      SampleCandidate(role: role, sourceIndex: sourceIndex, start: s, end: e, score: score, f0: f0, details: details);

  Map<String, Object?> toJson() => {
    'role': role.name,
    'source': sourceIndex,
    'start': start,
    'end': end,
    'score': score,
    'f0': f0,
  };

  factory SampleCandidate.fromJson(Map<String, Object?> j) => SampleCandidate(
    role: SampleRole.values.byName(j['role']! as String),
    sourceIndex: (j['source']! as num).toInt(),
    start: (j['start']! as num).toDouble(),
    end: (j['end']! as num).toDouble(),
    score: (j['score'] as num?)?.toDouble() ?? 0,
    f0: (j['f0'] as num?)?.toDouble() ?? 0,
  );
}
