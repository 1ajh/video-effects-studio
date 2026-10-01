import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/sparta/charter.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/section_edits.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

/// "This is Spar-ta": three words, the last with two syllables.
SpokenLine _line() => const SpokenLine(
  sourceIndex: 0,
  start: 1.0,
  end: 2.2,
  words: [
    LineWord(1.0, 1.3),
    LineWord(1.3, 1.5),
    LineWord(1.6, 2.2, cuts: [1.85]),
  ],
);

void main() {
  group('spoken line', () {
    test('words are numbered in order; syllables of a word are A, B…', () {
      final slots = _line().slots;
      expect(slots.keys, ['1', '2', '3', '3A', '3B']);
      expect(slots['3A'], (1.6, 1.85));
      expect(slots['3B'], (1.85, 2.2));
      expect(_line().quote.start, 1.0);
      expect(_line().quote.end, 2.2);
      expect(_line().wordCandidates.map((c) => c.slot), ['1', '2', '3', '3A', '3B']);
    });

    test("a pattern's slot finds the word to play", () {
      final keys = _line().slots.keys;
      expect(wordKeyFor('1', keys), '1');
      expect(wordKeyFor('3A', keys), '3A');
      expect(wordKeyFor('3B', keys), '3B');
      // Syllables of a one-syllable word: the whole word.
      expect(wordKeyFor('2A', keys), '2');
      // More words than the line has wrap around; 0 is the last word.
      expect(wordKeyFor('4', keys), '1');
      expect(wordKeyFor('5', keys), '2');
      expect(wordKeyFor('0', keys), '3');
      // More syllables than the word has: its last one.
      expect(wordKeyFor('3C', keys), '3B');
      expect(wordKeyFor('1', const <String>[]), isNull);
    });

    test('words can be split, joined, moved, trimmed and removed', () {
      var l = _line();
      l = l.splitWord(2, 1.85);
      expect(l.words.length, 4);
      expect(l.slots.keys, ['1', '2', '3', '4']);
      l = l.mergeWithNext(2);
      expect(l.words.length, 3);
      expect(l.words[2].cuts, [1.85]);
      l = l.moveBoundary(0, 1.25);
      expect(l.words[0].end, 1.25);
      expect(l.words[1].start, 1.25);
      l = l.trimWord(1, end: 1.45);
      expect(l.words[1].end, 1.45);
      l = l.toggleCut(2, 1.86);
      expect(l.words[2].cuts, isEmpty);
      l = l.toggleCut(2, 1.9);
      expect(l.words[2].cuts, [1.9]);
      l = l.removeWord(1);
      expect(l.slots.keys, ['1', '2', '2A', '2B']);
      // JSON round trip.
      final back = SpokenLine.fromJson(l.toJson());
      expect(back.slots, l.slots);
    });
  });

  group('section edits', () {
    const sections = [
      Section(SectionKind.intro, 0, 16),
      Section(SectionKind.chorus, 16, 48),
      Section(SectionKind.epicness, 48, 64),
    ];

    test('relabel, rename, split, merge and move keep the sections contiguous', () {
      var s = SectionOps.relabel(sections, 1, SectionKind.dundundenden);
      expect(s[1].kind, SectionKind.dundundenden);
      s = SectionOps.rename(s, 1, 'Drop');
      expect(s[1].title, 'Drop');
      s = SectionOps.split(s, 1, 32);
      expect(s.map((x) => x.startBeat), [0, 16, 32, 48]);
      expect(s[2].title, 'Drop');
      s = SectionOps.mergeWithNext(s, 2);
      expect(s.map((x) => x.endBeat), [16, 32, 64]);
      s = SectionOps.moveBoundary(s, 0, 21, 4);
      expect(s[0].endBeat, 20);
      expect(s[1].startBeat, 20);
      expect(SectionOps.valid(s, 64), isTrue);
      // A boundary can't swallow a section.
      expect(SectionOps.moveBoundary(s, 0, 40, 4)[0].endBeat, 28);
    });

    test("another base's layout is fitted bar for bar", () {
      final fitted = SectionOps.fit(sections, 40, 4);
      expect(fitted.map((x) => x.kind), [SectionKind.intro, SectionKind.chorus]);
      expect(fitted.last.endBeat, 40);
      final stretched = SectionOps.fit(sections, 80, 4);
      expect(stretched.last.endBeat, 80);
      expect(SectionOps.valid(stretched, 80), isTrue);
    });
  });

  group('charter extras', () {
    final t = BaseTranscription(
      bpm: 140,
      rootKey: 62,
      lengthBeats: 64,
      sections: const [Section(SectionKind.chorus, 0, 32), Section(SectionKind.epicness, 32, 64)],
      hits: [for (var b = 0.0; b < 64; b++) GuideNote(b, 0.5, 0)],
    );

    test('a typed pattern plays as written', () {
      final chart = Charter().write(
        t,
        choices: {1: const SectionChoice(pitch: PitchMode.pattern, pitchPattern: 'custom:0 0 1 1 -2 -2 1 1')},
      );
      final pitch = chart.where((n) => n.role == SampleRole.pitch && n.beat >= 32).toList();
      expect(pitch.take(8).map((n) => n.semitone), [0, 0, 1, 1, -2, -2, 1, 1]);
      final words = Charter().write(t, choices: {0: const SectionChoice(words: 'custom:1_2_3A3B')});
      expect(words.where((n) => n.role == SampleRole.word && n.beat < 1).map((n) => n.slot), ['1', '2']);
    });

    test('random section layout only applies in random mode', () {
      final plain = Charter().write(t);
      final again = Charter().write(t, random: const RandomOptions(layout: true));
      expect(again.map((n) => '$n'), plain.map((n) => '$n'));
      var changed = false;
      for (var seed = 1; seed < 12 && !changed; seed++) {
        final r = Charter().write(
          t,
          random: RandomOptions(enabled: true, freestyles: false, pitchPatterns: false, samples: false, seed: seed),
        );
        changed = r.map((n) => '$n').join() != plain.map((n) => '$n').join();
      }
      expect(changed, isTrue);
    });
  });
}
