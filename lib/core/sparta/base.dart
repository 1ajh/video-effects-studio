import 'model.dart';

enum BaseKind { builtIn, flp, midi, audioOnly }

/// A Sparta base: instrumental audio + the chart of sample-lane notes.
class SpartaBase {
  SpartaBase({
    required this.id,
    required this.name,
    required this.bpm,
    required this.kind,
    required this.sections,
    required this.chart,
    required this.lengthBeats,
    this.author = '',
    this.audioPath,
    this.audioOffset = 0,
    this.beatsPerBar = 4,
    this.barRoots = const [],
    this.notes = '',
    this.chartShift,
    this.composedRoles = const {},
  });

  final String id;
  final String name;
  final String author;
  final double bpm;
  final BaseKind kind;
  final int beatsPerBar;

  /// Ordered, non-overlapping sections.
  final List<Section> sections;

  /// Sample-lane notes.
  final List<ChartNote> chart;

  final double lengthBeats;

  /// Rendered instrumental (null until built-in audio is synthesized).
  String? audioPath;

  /// Seconds into [audioPath] where beat 0 lands.
  double audioOffset;

  /// Harmonic root per bar (semitones from D), when known.
  final List<int> barRoots;

  /// Free-form import notes (e.g. how lanes were mapped).
  final String notes;

  /// Semitones the composed chart's tonal notes were shifted by (the base's
  /// key relative to D, plus any transpose); null when the chart came from
  /// the project itself and can't be rewritten.
  final int? chartShift;

  /// Lanes written by the composer (the rest follow the base, e.g. drums
  /// locked to a project's own kick and snare).
  final Set<SampleRole> composedRoles;

  bool get canRewriteChart => chartShift != null && composedRoles.isNotEmpty;

  double get secondsPerBeat => 60 / bpm;
  double seconds(double beat) => beat * 60 / bpm;
  double get durationSeconds => seconds(lengthBeats);
  double get barSeconds => seconds(beatsPerBar.toDouble());

  List<ChartNote> lane(SampleRole role) => chart.where((n) => n.role == role).toList();

  Section sectionAt(double beat) => sections.firstWhere(
    (s) => s.contains(beat),
    orElse: () => sections.isEmpty ? Section(SectionKind.other, 0, lengthBeats) : sections.last,
  );

  int rootAtBar(int bar) => barRoots.isEmpty ? 0 : barRoots[bar.clamp(0, barRoots.length - 1)];

  SpartaBase copyWith({
    List<ChartNote>? chart,
    List<Section>? sections,
    String? audioPath,
    double? audioOffset,
    String? name,
  }) => SpartaBase(
    id: id,
    name: name ?? this.name,
    author: author,
    bpm: bpm,
    kind: kind,
    sections: sections ?? this.sections,
    chart: chart ?? this.chart,
    lengthBeats: lengthBeats,
    audioPath: audioPath ?? this.audioPath,
    audioOffset: audioOffset ?? this.audioOffset,
    beatsPerBar: beatsPerBar,
    barRoots: barRoots,
    notes: notes,
    chartShift: chartShift,
    composedRoles: composedRoles,
  );
}
