import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/sparta/arranger.dart';
import 'package:video_effects_studio/core/sparta/base_library.dart';
import 'package:video_effects_studio/core/sparta/charter.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';
import 'package:video_effects_studio/core/sparta/visual_renderer.dart';

/// 8 bars in D: intro, chorus, epicness, with chords and a bass line.
BaseTranscription _base({bool withBass = true}) => BaseTranscription(
  bpm: 140,
  rootKey: 62,
  lengthBeats: 32,
  sections: const [
    Section(SectionKind.intro, 0, 8),
    Section(SectionKind.chorus, 8, 24),
    Section(SectionKind.epicness, 24, 32),
    // Past the end of the music: nothing may play here.
    Section(SectionKind.madness, 32, 48),
  ],
  hits: const [GuideNote(0, 1, -2), GuideNote(2, 1, -2)],
  bass: withBass ? [for (var b = 8.0; b < 32; b += 0.5) GuideNote(b, 0.5, -24)] : const [],
  chords: [
    for (var b = 8.0; b < 32; b += 2)
      for (final i in const [0, 4, 7]) GuideNote(b, 2, const [0, 1, -2, 1][((b - 8) ~/ 2) % 4] + i),
  ],
  kick: [for (var b = 8.0; b < 48; b += 1) b],
);

PlacedEvent _event(SampleRole role, {String slot = ''}) => PlacedEvent(
  role: role,
  variant: 0,
  beat: 0,
  start: 0,
  duration: 1,
  rate: 1,
  semitone: 0,
  velocity: 1,
  sectionIndex: 0,
  laneIndex: 0,
  slot: slot,
);

void main() {
  group('charter instruments', () {
    test('the bass plays the base line two octaves under the key', () {
      final chart = Charter().write(_base());
      final bass = chart.where((n) => n.role == SampleRole.bass).toList();
      expect(bass, isNotEmpty);
      // -24 from D4 is D2: the bass sample's own root.
      expect(bass.every((n) => n.semitone == 0), isTrue);
      expect(bass.first.beat, 8);
    });

    test('without a bass line the bass follows the chord roots', () {
      final chart = Charter().write(_base(withBass: false));
      final chorus = chart.where((n) => n.role == SampleRole.bass && n.beat >= 8 && n.beat < 24).toList();
      // Eighths, root then octave, on D, D#, C, D#.
      expect(chorus.take(8).map((n) => n.semitone), [0, 12, 0, 12, 1, 13, 1, 13]);
      final epic = chart.where((n) => n.role == SampleRole.bass && n.beat >= 24).toList();
      expect(epic.first.length, 2, reason: 'held outside the chorus');
    });

    test('pads play the chords in choruses and the epicness by default', () {
      final chart = Charter().write(_base());
      final pads = chart.where((n) => n.role == SampleRole.pad).toList();
      expect(pads.where((n) => n.beat == 8).map((n) => n.semitone).toSet(), {0, 4, 7});
      expect(pads.where((n) => n.beat == 10).map((n) => n.semitone).toSet(), {1, 5, 8});
      final off = Charter().write(_base(), choices: {1: const SectionChoice(pads: false)});
      expect(off.where((n) => n.role == SampleRole.pad && n.beat < 24), isEmpty);
    });

    test('muted lanes are left out', () {
      final chart = Charter().write(_base(), muted: {SampleRole.bass, SampleRole.kick});
      expect(chart.where((n) => n.role == SampleRole.bass || n.role == SampleRole.kick), isEmpty);
      expect(chart.where((n) => n.role == SampleRole.pad), isNotEmpty);
    });

    test('nothing plays after the base ends', () {
      final chart = Charter().write(_base());
      expect(chart.where((n) => n.beat >= 32), isEmpty);
      expect(chart.every((n) => n.end <= 32 + 1e-9), isTrue);
    });

    test('wiki patterns are fitted to the base chords', () {
      final t = _base();
      // A base whose second chord is E instead of D#: the classic "1" moves up.
      final twisted = t.copyWith(
        chords: [
          for (final c in t.chords)
            if (((c.beat - 8) ~/ 2) % 4 == 1) GuideNote(c.beat, c.length, c.semitone + 1) else c,
        ],
      );
      expect(Charter.fitToChords(t, 1, 10, 8), 1);
      expect(Charter.fitToChords(twisted, 1, 10, 8), 2);
      expect(Charter.fitToChords(twisted, 13, 11, 8), 14);
      expect(Charter.fitToChords(twisted, 0, 8, 8), 0);
    });

    test('a long intro plays the chorus after the quote; a short one only the quote', () {
      BaseTranscription intro(double bars) => BaseTranscription(
        bpm: 140,
        rootKey: 62,
        lengthBeats: bars * 4 + 16,
        sections: [Section(SectionKind.intro, 0, bars * 4), Section(SectionKind.chorus, bars * 4, bars * 4 + 16)],
      );
      final long = Charter().write(intro(16), quoteBeats: 10);
      final words = long.where((n) => n.role == SampleRole.word && n.beat < 64).toList();
      expect(words, isNotEmpty);
      expect(words.first.beat, 12, reason: 'from the bar after the quote');
      final short = Charter().write(intro(4), quoteBeats: 10);
      expect(short.where((n) => n.role == SampleRole.word && n.beat < 16), isEmpty);
    });

    test('awesomeness sections keep the chorus words', () {
      final t = BaseTranscription(
        bpm: 140,
        rootKey: 62,
        lengthBeats: 16,
        sections: const [Section(SectionKind.awesomeness, 0, 16)],
        hits: const [GuideNote(0, 1, 0)],
      );
      final chart = Charter().write(t);
      expect(chart.where((n) => n.role == SampleRole.word), isNotEmpty);
      expect(chart.where((n) => n.role == SampleRole.pitch), isNotEmpty);
    });
  });

  group('grid layout', () {
    test('percussion takes the bottom row', () {
      final events = [
        _event(SampleRole.pitch),
        _event(SampleRole.bass),
        _event(SampleRole.pad),
        _event(SampleRole.word, slot: '1'),
        _event(SampleRole.word, slot: '2'),
        _event(SampleRole.word, slot: '3A'),
        _event(SampleRole.kick),
        _event(SampleRole.snare),
        _event(SampleRole.hat),
      ];
      final g = GridLayout.of(events, const VisualOptions());
      expect(g.n, 3);
      expect(g.cells.sublist(6).map((b) => b?.role), [SampleRole.kick, SampleRole.snare, SampleRole.hat]);
      expect(g.cells.first?.role, SampleRole.pitch);
      expect(g.cellOf(_event(SampleRole.hat)), 8);
      expect(g.cellOf(_event(SampleRole.word, slot: '3B')), g.cellOf(_event(SampleRole.word, slot: '3A')));
    });

    test('the grid grows so the top rows hold every other box', () {
      final events = [
        _event(SampleRole.pitch),
        _event(SampleRole.bass),
        _event(SampleRole.pad),
        for (final w in ['1', '2', '3', '4']) _event(SampleRole.word, slot: w),
        _event(SampleRole.kick),
      ];
      final g = GridLayout.of(events, const VisualOptions());
      expect(g.n, 4);
      expect(g.cells[12]?.role, SampleRole.kick);
      expect(g.cells.sublist(0, 12).whereType<VisualBox>().length, 7);
    });
  });

  group('Keaton Sparta Extended', () {
    late BaseTranscription t;
    setUpAll(() {
      t = BaseTranscription.decode(File('bases/transcriptions/keaton-sparta-extended.json').readAsStringSync());
    });

    test('is linked from the catalog', () {
      final catalog = BaseCatalog.parse(File('bases/catalog.json').readAsStringSync());
      final b = catalog.byId('keaton/sparta-extended')!;
      expect(b.transcriptionPath, 'transcriptions/keaton-sparta-extended.json');
      expect(b.exact, isTrue);
      expect(catalog.bySha1(t.audioSha1)?.id, b.id);
    });

    test('follows the base: 72 bars in D with the classic structure', () {
      expect(t.source, TranscriptionSource.curated);
      expect(t.bpm, 140);
      expect(t.rootName, 'D');
      expect(t.lengthBeats, 288);
      expect(t.sections.map((s) => s.kind.name), [
        'intro',
        'chorus',
        'dundundenden',
        'chorus',
        'epicness',
        'chorus',
        'awesomeness',
        'madness',
        'chorus',
        'epicness',
        'postEpicness',
        'awesomeness',
        'chorus',
      ]);
      // Sections tile the song.
      for (var i = 1; i < t.sections.length; i++) {
        expect(t.sections[i].startBeat, t.sections[i - 1].endBeat);
      }
      expect(t.sections.last.endBeat, t.lengthBeats);
    });

    test('every pitch, bass and pad note fits the D–D#–C–D# progression', () {
      for (final h in [...t.hits, ...t.bass, ...t.chords]) {
        if (h.beat < 8) continue;
        final root = const [0, 1, -2, 1][((h.beat - 8) ~/ 2) % 4];
        final major = {root % 12, (root + 4) % 12, (root + 7) % 12};
        // Chord tones, plus the wiki's passing notes in the awesomeness.
        final pc = (h.semitone % 12 + 12) % 12;
        final passing = {
          for (final s in t.sections.where((s) => s.kind == SectionKind.awesomeness)) s,
        }.any((s) => s.contains(h.beat));
        if (!passing) expect(major.contains(pc), isTrue, reason: '$h over ${(root % 12 + 12) % 12}');
      }
    });

    test('the chorus words land in the choruses', () {
      final chart = Charter().write(t);
      for (final s in t.sections.where((s) => s.kind == SectionKind.chorus)) {
        expect(chart.where((n) => n.role == SampleRole.word && s.contains(n.beat)), isNotEmpty, reason: '$s');
      }
      expect(chart.where((n) => n.beat >= t.lengthBeats), isEmpty);
      expect(chart.where((n) => n.role == SampleRole.bass), isNotEmpty);
      expect(chart.where((n) => n.role == SampleRole.pad), isNotEmpty);
    });
  });
}
