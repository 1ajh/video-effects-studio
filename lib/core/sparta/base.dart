import 'model.dart';
import 'transcription.dart';

/// Where a base came from.
enum BaseKind {
  /// Downloaded from the base catalog.
  library,

  /// An FL Studio / FL Studio Mobile / MIDI project (optionally with audio).
  project,

  /// An audio file the user brought.
  audio,
}

/// A Sparta base: its audio, what it plays (the transcription) and the
/// remix chart written over it.
class SpartaBase {
  SpartaBase({
    required this.id,
    required this.name,
    required this.kind,
    required this.transcription,
    this.author = '',
    this.audioPath,
    this.chart = const [],
    this.notes = '',
  });

  final String id;
  final String name;
  final String author;
  final BaseKind kind;
  final BaseTranscription transcription;

  /// The base's audio (null for a project re-synthesized without it).
  final String? audioPath;

  /// Sample-lane notes of the remix.
  final List<ChartNote> chart;

  /// Import notes (warnings, how the base was read).
  final String notes;

  double get bpm => transcription.bpm;
  int get beatsPerBar => transcription.beatsPerBar;
  List<Section> get sections => transcription.sections;
  double get lengthBeats => transcription.lengthBeats;

  /// Seconds into the audio where beat 0 lands.
  double get audioOffset => transcription.audioOffset;
  int get rootKey => transcription.rootKey;

  double get secondsPerBeat => 60 / bpm;
  double seconds(double beat) => beat * 60 / bpm;
  double get durationSeconds => seconds(lengthBeats);
  double get barSeconds => seconds(beatsPerBar.toDouble());

  List<ChartNote> lane(SampleRole role) => chart.where((n) => n.role == role).toList();

  Section sectionAt(double beat) => transcription.sectionAt(beat);

  SpartaBase copyWith({
    List<ChartNote>? chart,
    BaseTranscription? transcription,
    String? audioPath,
    String? name,
    String? notes,
  }) => SpartaBase(
    id: id,
    name: name ?? this.name,
    author: author,
    kind: kind,
    transcription: transcription ?? this.transcription,
    audioPath: audioPath ?? this.audioPath,
    chart: chart ?? this.chart,
    notes: notes ?? this.notes,
  );
}
