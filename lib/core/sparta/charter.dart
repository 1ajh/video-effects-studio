import 'dart:math' as math;

import 'model.dart';
import 'patterns.dart';
import 'transcription.dart';

/// What the pitch sample plays in a section.
enum PitchMode {
  /// The base's own hit / lead notes (the default: follow the base).
  base('Base hits'),

  /// A wiki pitch pattern, on the base's root.
  pattern('Wiki pattern'),

  /// Nothing.
  off('No pitch');

  const PitchMode(this.label);
  final String label;
}

/// Choices for one section, edited in the review. Null fields keep the
/// default for the section's kind.
class SectionChoice {
  const SectionChoice({this.words, this.pitch, this.pitchPattern, this.variant = 0, this.bass, this.pads});

  /// Word pattern id (`custom:<notation>` for a typed one), or '' for no
  /// chorus words here.
  final String? words;
  final PitchMode? pitch;

  /// Pitch pattern id (`custom:<notation>` for a typed one) when [pitch]
  /// is [PitchMode.pattern].
  final String? pitchPattern;

  /// Random-mode take for this section (re-roll).
  final int variant;

  /// Whether the bass sample plays here (null: when the base has a bass).
  final bool? bass;

  /// Whether the pads play here (null: in choruses and the epicness).
  final bool? pads;

  bool get isDefault =>
      words == null && pitch == null && pitchPattern == null && variant == 0 && bass == null && pads == null;

  SectionChoice copyWith({
    String? words,
    PitchMode? pitch,
    String? pitchPattern,
    int? variant,
    bool? bass,
    bool? pads,
    bool clearWords = false,
  }) => SectionChoice(
    words: clearWords ? null : (words ?? this.words),
    pitch: pitch ?? this.pitch,
    pitchPattern: pitchPattern ?? this.pitchPattern,
    variant: variant ?? this.variant,
    bass: bass ?? this.bass,
    pads: pads ?? this.pads,
  );

  Map<String, Object?> toJson() => {
    if (words != null) 'words': words,
    if (pitch != null) 'pitch': pitch!.name,
    if (pitchPattern != null) 'pitchPattern': pitchPattern,
    if (variant != 0) 'variant': variant,
    'bass': ?bass,
    'pads': ?pads,
  };

  factory SectionChoice.fromJson(Map<String, Object?> j) => SectionChoice(
    words: j['words'] as String?,
    pitch: PitchMode.values.asNameMap()[j['pitch']],
    pitchPattern: j['pitchPattern'] as String?,
    variant: (j['variant'] as num?)?.toInt() ?? 0,
    bass: j['bass'] as bool?,
    pads: j['pads'] as bool?,
  );
}

/// What random mode may change (it's off by default).
class RandomOptions {
  const RandomOptions({
    this.enabled = false,
    this.freestyles = true,
    this.pitchPatterns = true,
    this.samples = true,
    this.layout = true,
    this.seed = 1,
  });

  final bool enabled;

  /// Chorus (and other word) freestyles from the wiki instead of the
  /// original patterns.
  final bool freestyles;

  /// Other wiki pitch patterns for the section instead of the base's hits.
  final bool pitchPatterns;

  /// Different samples per section.
  final bool samples;

  /// Sections play another part's patterns (a chorus can become a madness…).
  final bool layout;
  final int seed;

  RandomOptions copyWith({
    bool? enabled,
    bool? freestyles,
    bool? pitchPatterns,
    bool? samples,
    bool? layout,
    int? seed,
  }) => RandomOptions(
    enabled: enabled ?? this.enabled,
    freestyles: freestyles ?? this.freestyles,
    pitchPatterns: pitchPatterns ?? this.pitchPatterns,
    samples: samples ?? this.samples,
    layout: layout ?? this.layout,
    seed: seed ?? this.seed,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'freestyles': freestyles,
    'pitchPatterns': pitchPatterns,
    'samples': samples,
    'layout': layout,
    'seed': seed,
  };

  factory RandomOptions.fromJson(Map<String, Object?> j) => RandomOptions(
    enabled: j['enabled'] as bool? ?? false,
    freestyles: j['freestyles'] as bool? ?? true,
    pitchPatterns: j['pitchPatterns'] as bool? ?? true,
    samples: j['samples'] as bool? ?? true,
    layout: j['layout'] as bool? ?? true,
    seed: (j['seed'] as num?)?.toInt() ?? 1,
  );
}

/// Writes the remix chart over a transcribed base, the way the Sparta
/// Remix Wiki describes a remix:
///
/// * the pitch sample plays the base's own hit notes (not in the chorus,
///   which is words only);
/// * the bass sample plays the base's bass line, the pads its chords;
/// * chorus words play the wiki's word pattern for each section (the
///   standard chorus, DunDunDenDen's 1-2-3A-3B, the epicness and madness
///   patterns) and nothing where the wiki has none;
/// * percussion samples land on the base's kicks, snares and hats;
/// * the whole line (the quote) opens the intro;
/// * nothing plays after the base ends.
class Charter {
  Charter({PatternLibrary? library}) : lib = library ?? PatternLibrary.instance;

  final PatternLibrary lib;

  /// A pattern by id; `custom:<notation>` parses a typed one.
  Pattern? pattern(PatternKind kind, String id) {
    if (id.startsWith('custom:')) {
      try {
        return PatternLibrary.custom(kind, id.substring(7));
      } on PatternFormatException {
        return null;
      }
    }
    return lib.byId(id);
  }

  /// The default word pattern for a section kind (null: no words there).
  Pattern? defaultWords(SectionKind kind) => switch (kind) {
    SectionKind.chorus ||
    SectionKind.dundundenden ||
    SectionKind.epicness ||
    SectionKind.madness => lib.classic(PatternKind.words, kind.wiki),
    // The awesomeness patterns are pitch patterns over a chorus.
    SectionKind.awesomeness => lib.classic(PatternKind.words, 'chorus'),
    _ => null,
  };

  /// Whether the pads play in a section by default.
  static bool padsByDefault(SectionKind kind) =>
      kind == SectionKind.chorus || kind == SectionKind.awesomeness || kind == SectionKind.epicness;

  /// Word patterns that fit a section (for the review's picker).
  List<Pattern> wordChoices(SectionKind kind) => [
    ...lib.of(PatternKind.words, section: kind.wiki),
    if (kind != SectionKind.chorus) ...lib.of(PatternKind.words, section: 'chorus'),
  ];

  /// Pitch patterns that fit a section (for the review's picker).
  List<Pattern> pitchChoices(SectionKind kind) {
    final own = lib.of(PatternKind.pitch, section: kind.wiki).toList();
    return [
      ...own,
      for (final p in lib.of(PatternKind.pitch))
        if (!own.contains(p)) p,
    ];
  }

  /// Writes the chart. [muted] lanes are left out (the instrument toggles).
  List<ChartNote> write(
    BaseTranscription t, {
    Map<int, SectionChoice> choices = const {},
    RandomOptions random = const RandomOptions(),
    bool pitchInChorus = false,
    Set<SampleRole> muted = const {},
  }) {
    final out = <ChartNote>[];
    final sections = t.sections.isEmpty ? [Section(SectionKind.other, 0, t.lengthBeats)] : t.sections;
    // Nothing plays after the base ends.
    final songEnd = t.lengthBeats;
    var quoted = false;
    for (var i = 0; i < sections.length; i++) {
      final choice = choices[i] ?? const SectionChoice();
      final rng = math.Random(random.seed * 7919 + i * 104729 + choice.variant * 31 + 17);
      final real = sections[i];
      if (real.startBeat >= songEnd - 1e-6) break;
      var s = real.endBeat > songEnd ? Section(real.kind, real.startBeat, songEnd, name: real.name) : real;
      // Random layout: the section plays another part's patterns.
      if (random.enabled && random.layout && _shuffled.contains(s.kind) && rng.nextDouble() < 0.5) {
        s = Section(_shuffled[rng.nextInt(_shuffled.length)], s.startBeat, s.endBeat, name: s.name);
      }
      void add(ChartNote n) {
        if (muted.contains(n.role)) return;
        if (n.beat < s.startBeat - 1e-6 || n.beat >= s.endBeat - 1e-6) return;
        final len = math.min(n.length, s.endBeat - n.beat);
        if (len <= 1e-6) return;
        out.add(len == n.length ? n : n.copyWith(length: len));
      }

      // Chorus words.
      final words = _wordsFor(s.kind, choice, random, rng);
      if (words != null) {
        for (final h in words.looped((s.lengthBeats * 4).roundToDouble())) {
          add(ChartNote(role: SampleRole.word, beat: s.startBeat + h.step / 4, length: h.length / 4, slot: h.slot));
        }
      }

      // Pitch.
      final pitchOff = s.kind == SectionKind.chorus && !pitchInChorus && choice.pitch == null;
      var mode = choice.pitch ?? (pitchOff ? PitchMode.off : PitchMode.base);
      Pattern? pitchPattern = choice.pitchPattern == null ? null : pattern(PatternKind.pitch, choice.pitchPattern!);
      if (choice.pitch == null && !pitchOff && random.enabled && random.pitchPatterns) {
        final options = lib.of(PatternKind.pitch, section: s.kind.wiki).where((p) => !p.irregular).toList();
        if (options.isNotEmpty && rng.nextDouble() < 0.6) {
          mode = PitchMode.pattern;
          pitchPattern = options[rng.nextInt(options.length)];
        }
      }
      // A section without hits of its own plays its wiki pattern instead.
      if (mode == PitchMode.base && !t.hits.any((h) => s.contains(h.beat)) && t.chords.isNotEmpty) {
        mode = PitchMode.pattern;
      }
      switch (mode) {
        case PitchMode.off:
          break;
        case PitchMode.base:
          for (final h in t.hits) {
            add(
              ChartNote(
                role: SampleRole.pitch,
                beat: h.beat,
                length: h.length,
                semitone: h.semitone,
                velocity: h.velocity,
              ),
            );
          }
        case PitchMode.pattern:
          final p = pitchPattern ?? lib.classic(PatternKind.pitch, s.kind.wiki);
          if (p != null) {
            for (final h in _pitchLoop(p, s)) {
              final beat = s.startBeat + h.step / 4;
              add(
                ChartNote(
                  role: SampleRole.pitch,
                  beat: beat,
                  length: h.length / 4,
                  semitone: fitToChords(t, h.semitone, beat, s.startBeat),
                ),
              );
            }
          }
      }

      // Bass: the base's bass line (or its chord roots).
      if (choice.bass ?? true) {
        for (final n in bassLine(t, s)) {
          add(ChartNote(role: SampleRole.bass, beat: n.beat, length: n.length, semitone: n.semitone));
        }
      }

      // Pads: the base's chords.
      if (choice.pads ?? padsByDefault(s.kind)) {
        for (final n in padChords(t, s)) {
          add(ChartNote(role: SampleRole.pad, beat: n.beat, length: n.length, semitone: n.semitone, velocity: 0.8));
        }
      }

      // Percussion on the base's own drums.
      for (final role in const [SampleRole.kick, SampleRole.snare, SampleRole.hat]) {
        for (final b in t.drums(role)) {
          add(ChartNote(role: role, beat: b, length: 0.5));
        }
      }

      // The quote opens the intro (or the song, when there's no intro).
      if (!quoted && (s.kind == SectionKind.intro || i == 0)) {
        quoted = true;
        final len = s.kind == SectionKind.intro ? s.lengthBeats : math.min(s.lengthBeats, 8.0);
        add(ChartNote(role: SampleRole.quote, beat: s.startBeat, length: math.max(1, len)));
      }
    }
    out.sort((a, b) => a.beat != b.beat ? a.beat.compareTo(b.beat) : a.role.index.compareTo(b.role.index));
    return out;
  }

  /// The classic Sparta progression wiki patterns are written over: D, D#,
  /// C, D# (0, 1, -2, 1), two beats each.
  static const classicProgression = [0, 1, -2, 1];

  /// Moves a wiki pattern's note onto the base's own chords (a progression
  /// twist): written over the classic progression, it keeps its distance to
  /// the chord's root. Unchanged where the base's chords aren't known.
  static int fitToChords(BaseTranscription t, int semitone, double beat, double sectionStart) {
    final root = t.chordRootAt(beat);
    if (root == null) return semitone;
    final classic = classicProgression[(((beat - sectionStart) / 2 + 1e-6).floor()) % 4];
    return semitone - classic + _wrap(root);
  }

  /// A root in -6 … 5 (closest to the key's root).
  static int _wrap(int semitone) => ((semitone + 6) % 12 + 12) % 12 - 6;

  /// What the bass plays in [s], in semitones from the bass sample's root
  /// (the key's root two octaves down, D2 for a D base): the base's own bass
  /// line, else its chord roots (eighths with octaves in a chorus, held
  /// elsewhere).
  static List<GuideNote> bassLine(BaseTranscription t, Section s) {
    final own = [
      for (final n in t.bass)
        if (s.contains(n.beat)) n,
    ];
    if (own.isNotEmpty) {
      // Bass notes are written from the key's root; the bass sample sits two
      // octaves under it.
      return [for (final n in own) n.copyWith(semitone: _bassRange(n.semitone + 24))];
    }
    final chords = _chordSpans(t, s);
    if (chords.isEmpty) return const [];
    final eighths = s.kind == SectionKind.chorus || s.kind == SectionKind.awesomeness;
    final out = <GuideNote>[];
    for (final (start, end, root) in chords) {
      final r = _wrap(root);
      if (!eighths) {
        out.add(GuideNote(start, end - start, r));
        continue;
      }
      var k = 0;
      for (var b = start; b < end - 1e-6; b += 0.5, k++) {
        out.add(GuideNote(b, math.min(0.5, end - b), k.isOdd ? r + 12 : r));
      }
    }
    return out;
  }

  static int _bassRange(int semitone) {
    var v = semitone;
    while (v < -7) {
      v += 12;
    }
    while (v > 19) {
      v -= 12;
    }
    return v;
  }

  /// The chord voices the pads play in [s] (semitones from the key's root,
  /// the chord's root kept within a fourth of it).
  static List<GuideNote> padChords(BaseTranscription t, Section s) {
    final out = <GuideNote>[];
    for (final (start, end, root) in _chordSpans(t, s)) {
      final shift = _wrap(root) - root;
      for (final c in t.chords) {
        if ((c.beat - start).abs() < 1e-6) {
          out.add(GuideNote(start, math.min(c.length, end - start), c.semitone + shift));
        }
      }
    }
    return out;
  }

  /// The chords starting in [s]: (start, end, root).
  static List<(double, double, int)> _chordSpans(BaseTranscription t, Section s) {
    final starts = <double, int>{};
    final ends = <double, double>{};
    for (final c in t.chords) {
      if (!s.contains(c.beat)) continue;
      starts[c.beat] = math.min(starts[c.beat] ?? c.semitone, c.semitone);
      ends[c.beat] = math.max(ends[c.beat] ?? c.end, c.end);
    }
    final keys = starts.keys.toList()..sort();
    return [for (final k in keys) (k, math.min(ends[k]!, s.endBeat), starts[k]!)];
  }

  static const _shuffled = [
    SectionKind.chorus,
    SectionKind.dundundenden,
    SectionKind.epicness,
    SectionKind.awesomeness,
    SectionKind.madness,
  ];

  Pattern? _wordsFor(SectionKind kind, SectionChoice choice, RandomOptions random, math.Random rng) {
    if (choice.words != null) return choice.words!.isEmpty ? null : pattern(PatternKind.words, choice.words!);
    final base = defaultWords(kind);
    if (base == null || !random.enabled || !random.freestyles) return base;
    final options = lib.of(PatternKind.words, section: kind.wiki).where((p) => !p.irregular).toList();
    if (options.length < 2 || rng.nextDouble() < 0.35) return base;
    return options[rng.nextInt(options.length)];
  }

  /// A pitch pattern over a section; the madness's two original patterns
  /// split it into its first and second half.
  List<PatternHit> _pitchLoop(Pattern p, Section s) {
    final steps = (s.lengthBeats * 4).roundToDouble();
    if (s.kind == SectionKind.madness && p.classic && p.section == 'madness') {
      final second = lib.of(PatternKind.pitch, section: 'madness').where((x) => x.name.contains('Trance Gate'));
      if (second.isNotEmpty && p.name == 'First Pattern' && steps >= 64) {
        final half = (steps / 2 / 16).round() * 16.0;
        return [...p.looped(half), for (final h in second.first.looped(steps - half)) h.shifted(half)];
      }
    }
    return p.looped(steps);
  }
}
