import 'dart:convert';
import 'dart:math' as math;

import 'model.dart';

/// A note of the base's pitch guide: the hit / lead the pitch sample
/// doubles (in standard bases, the wiki's pitch patterns).
class GuideNote {
  const GuideNote(this.beat, this.length, this.semitone, {this.velocity = 1});

  final double beat;
  final double length;

  /// Semitones from the base's root key.
  final int semitone;
  final double velocity;

  double get end => beat + length;

  GuideNote copyWith({double? beat, double? length, int? semitone}) =>
      GuideNote(beat ?? this.beat, length ?? this.length, semitone ?? this.semitone, velocity: velocity);

  @override
  bool operator ==(Object other) =>
      other is GuideNote && other.beat == beat && other.length == length && other.semitone == semitone;

  @override
  int get hashCode => Object.hash(beat, length, semitone);

  @override
  String toString() => '$semitone@$beat+$length';
}

/// Where a transcription came from.
enum TranscriptionSource {
  /// Read from the base's own FL Studio / FL Studio Mobile / MIDI project.
  project('From the project'),

  /// Worked out by listening to the base's audio.
  audio('Transcribed from the audio'),

  /// Checked by a person and added to the app's base catalog.
  curated('Checked transcription'),

  /// Fixed by you in the app.
  user('Your edits');

  const TranscriptionSource(this.label);
  final String label;
}

const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// "D4" for MIDI key 62.
String keyName(int key) => '${noteNames[key % 12]}${key ~/ 12 - 1}';

/// MIDI key for "D4", "D#3", "Eb5"…; null when unreadable.
int? parseKeyName(String s) {
  final m = RegExp(r'^([A-Ga-g])([#b]?)(-?\d)$').firstMatch(s.trim());
  if (m == null) return null;
  var pc = const {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}[m.group(1)!.toUpperCase()]!;
  if (m.group(2) == '#') pc++;
  if (m.group(2) == 'b') pc--;
  return (int.parse(m.group(3)!) + 1) * 12 + pc;
}

/// What a remix follows in a base: its tempo and key, its sections, the
/// notes its hit/lead plays and where its kicks, snares and hats land.
///
/// Serialised as a small JSON document so fixed transcriptions can be sent
/// in and shared through the base catalog.
class BaseTranscription {
  BaseTranscription({
    required this.bpm,
    required this.rootKey,
    required this.lengthBeats,
    this.beatsPerBar = 4,
    this.sections = const [],
    this.hits = const [],
    this.bass = const [],
    this.chords = const [],
    this.kick = const [],
    this.snare = const [],
    this.hat = const [],
    this.audioOffset = 0,
    this.source = TranscriptionSource.project,
    this.credit = '',
    this.confidence = 1,
    this.patterns = const {},
    this.baseName = '',
    this.maker = '',
    this.audioSha1 = '',
    this.catalogId = '',
  });

  static const format = 'sparta-base-transcription';
  static const version = 1;

  final double bpm;
  final int beatsPerBar;

  /// MIDI key of the pitch guide's "0" (the base's root, e.g. 62 = D4).
  final int rootKey;
  final double lengthBeats;
  final List<Section> sections;
  final List<GuideNote> hits;

  /// The base's bass line (semitones from [rootKey], usually -24 … -12):
  /// what the bass sample plays.
  final List<GuideNote> bass;

  /// The base's chords, one note per voice (notes starting together form a
  /// chord; semitones from [rootKey]): what the pads play, and the
  /// progression wiki patterns are fitted to.
  final List<GuideNote> chords;

  /// Beats where the base's drums hit.
  final List<double> kick;
  final List<double> snare;
  final List<double> hat;

  /// Seconds into the base audio where beat 0 lands.
  final double audioOffset;
  final TranscriptionSource source;

  /// Who transcribed or fixed it.
  final String credit;

  /// 0..1: how sure the transcription is (1 for projects).
  final double confidence;

  /// Wiki pattern recognised at a bar (bar index → pattern id).
  final Map<int, String> patterns;

  final String baseName;
  final String maker;

  /// SHA-1 of the audio file it was made from (identifies the base).
  final String audioSha1;
  final String catalogId;

  int get rootPitchClass => rootKey % 12;
  String get rootName => noteNames[rootPitchClass];
  double get secondsPerBeat => 60 / bpm;
  int get bars => math.max(1, (lengthBeats / beatsPerBar - 1e-6).ceil());

  Section sectionAt(double beat) => sections.firstWhere(
    (s) => s.contains(beat),
    orElse: () => sections.isEmpty ? Section(SectionKind.other, 0, lengthBeats) : sections.last,
  );

  /// Root of the chord playing at [beat] (semitones from [rootKey], the
  /// chord's lowest voice), or null where no chord is known.
  int? chordRootAt(double beat) {
    int? best;
    for (final c in chords) {
      if (c.beat <= beat + 1e-6 && c.end > beat + 1e-6) best = best == null ? c.semitone : math.min(best, c.semitone);
    }
    return best;
  }

  List<double> drums(SampleRole role) => switch (role) {
    SampleRole.kick => kick,
    SampleRole.snare => snare,
    SampleRole.hat => hat,
    _ => const [],
  };

  BaseTranscription copyWith({
    double? bpm,
    int? rootKey,
    double? lengthBeats,
    List<Section>? sections,
    List<GuideNote>? hits,
    List<GuideNote>? bass,
    List<GuideNote>? chords,
    List<double>? kick,
    List<double>? snare,
    List<double>? hat,
    double? audioOffset,
    TranscriptionSource? source,
    String? credit,
    double? confidence,
    Map<int, String>? patterns,
    String? baseName,
    String? maker,
    String? audioSha1,
    String? catalogId,
  }) => BaseTranscription(
    bpm: bpm ?? this.bpm,
    beatsPerBar: beatsPerBar,
    rootKey: rootKey ?? this.rootKey,
    lengthBeats: lengthBeats ?? this.lengthBeats,
    sections: sections ?? this.sections,
    hits: hits ?? this.hits,
    bass: bass ?? this.bass,
    chords: chords ?? this.chords,
    kick: kick ?? this.kick,
    snare: snare ?? this.snare,
    hat: hat ?? this.hat,
    audioOffset: audioOffset ?? this.audioOffset,
    source: source ?? this.source,
    credit: credit ?? this.credit,
    confidence: confidence ?? this.confidence,
    patterns: patterns ?? this.patterns,
    baseName: baseName ?? this.baseName,
    maker: maker ?? this.maker,
    audioSha1: audioSha1 ?? this.audioSha1,
    catalogId: catalogId ?? this.catalogId,
  );

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'base': {
      if (baseName.isNotEmpty) 'name': baseName,
      if (maker.isNotEmpty) 'maker': maker,
      if (catalogId.isNotEmpty) 'catalogId': catalogId,
      if (audioSha1.isNotEmpty) 'audioSha1': audioSha1,
    },
    'bpm': _r(bpm),
    'beatsPerBar': beatsPerBar,
    'root': keyName(rootKey),
    'offset': _r(audioOffset),
    'lengthBeats': _r(lengthBeats),
    'sections': [for (final s in sections) s.toJson()],
    'hits': [
      for (final h in hits) [_r(h.beat), _r(h.length), h.semitone],
    ],
    if (bass.isNotEmpty)
      'bass': [
        for (final h in bass) [_r(h.beat), _r(h.length), h.semitone],
      ],
    if (chords.isNotEmpty)
      'chords': [
        for (final h in chords) [_r(h.beat), _r(h.length), h.semitone],
      ],
    'kick': [for (final b in kick) _r(b)],
    'snare': [for (final b in snare) _r(b)],
    'hat': [for (final b in hat) _r(b)],
    'source': source.name,
    if (credit.isNotEmpty) 'credit': credit,
    'confidence': _r(confidence),
  };

  String encode() => const JsonEncoder.withIndent(' ').convert(toJson());

  factory BaseTranscription.fromJson(Map<String, Object?> j) {
    if (j['format'] != format) throw const FormatException('Not a Sparta base transcription.');
    final base = (j['base'] as Map?)?.cast<String, Object?>() ?? const {};
    List<double> beats(Object? v) => [for (final x in (v as List?) ?? const []) (x as num).toDouble()];
    List<GuideNote> notes(Object? v) => [
      for (final h in (v as List?) ?? const [])
        GuideNote(((h as List)[0] as num).toDouble(), (h[1] as num).toDouble(), (h[2] as num).toInt()),
    ];
    final root = j['root'];
    return BaseTranscription(
      bpm: (j['bpm']! as num).toDouble(),
      beatsPerBar: (j['beatsPerBar'] as num?)?.toInt() ?? 4,
      rootKey: root is num ? root.toInt() : (parseKeyName('$root') ?? 62),
      lengthBeats: (j['lengthBeats']! as num).toDouble(),
      sections: [
        for (final s in (j['sections'] as List?) ?? const []) Section.fromJson((s as Map).cast<String, Object?>()),
      ],
      hits: notes(j['hits']),
      bass: notes(j['bass']),
      chords: notes(j['chords']),
      kick: beats(j['kick']),
      snare: beats(j['snare']),
      hat: beats(j['hat']),
      audioOffset: (j['offset'] as num?)?.toDouble() ?? 0,
      source: TranscriptionSource.values.asNameMap()[j['source']] ?? TranscriptionSource.curated,
      credit: j['credit'] as String? ?? '',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 1,
      baseName: base['name'] as String? ?? '',
      maker: base['maker'] as String? ?? '',
      audioSha1: base['audioSha1'] as String? ?? '',
      catalogId: base['catalogId'] as String? ?? '',
    );
  }

  static BaseTranscription decode(String text) =>
      BaseTranscription.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
}
