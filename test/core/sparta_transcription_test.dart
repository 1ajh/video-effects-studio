import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/charter.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/patterns.dart';
import 'package:video_effects_studio/core/sparta/project_transcriber.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

/// A small Sparta base in D#: an intro, a chorus and an epicness, with an
/// orchestra hit playing the wiki's pitch patterns, a bass doubling the
/// progression in octaves, and drums.
ChartSource sampleBase() {
  const root = 75; // D#5
  final hit = <RawNote>[];
  final bass = <RawNote>[];
  final kick = <RawNote>[];
  final snare = <RawNote>[];
  // Intro, 4 bars: the intro hits (-2*** ×3) in bar 4.
  for (final b in [12.0, 13.0, 14.0]) {
    hit.add(RawNote(b, 0.5, root - 2));
  }
  // Chorus, 8 bars (beats 16..48): 0 0 +1 +1 -2 -2 +1 +1 on quarters.
  const chorus = [0, 0, 1, 1, -2, -2, 1, 1];
  for (var rep = 0; rep < 4; rep++) {
    for (var i = 0; i < 8; i++) {
      final beat = 16 + rep * 8 + i.toDouble();
      hit.add(RawNote(beat, 0.5, root + chorus[i]));
      // The bass plays it in 8th-note octaves ("0, 12"), two octaves down.
      bass.add(RawNote(beat, 0.5, root - 24 + chorus[i]));
      bass.add(RawNote(beat + 0.5, 0.5, root - 12 + chorus[i]));
    }
  }
  // Epicness, 8 bars (beats 48..80): the original epicness pitch pattern.
  final epic = PatternLibrary.instance.classic(PatternKind.pitch, 'epicness')!;
  for (var rep = 0; rep < 4; rep++) {
    for (final h in epic.hits) {
      hit.add(RawNote(48 + rep * 8 + h.step / 4, h.length / 4, root + h.semitone));
    }
  }
  for (var b = 16.0; b < 80; b++) {
    kick.add(RawNote(b, 0.25, 36));
    if (b % 2 == 1) snare.add(RawNote(b, 0.25, 38));
  }
  return ChartSource(
    name: 'Test base',
    path: 'test.flp',
    bpm: 140,
    tracks: [
      ChartTrack(id: 'bass', name: 'Fat Bass', notes: bass),
      ChartTrack(id: 'hit', name: 'HIT_4', notes: hit),
      ChartTrack(id: 'kick', name: 'FPC 5 Kick', notes: kick),
      ChartTrack(id: 'snare', name: 'FPC Snare 4', notes: snare),
    ],
    markers: const [ChartMarker(0, 'Intro'), ChartMarker(16, 'Chorus'), ChartMarker(48, 'Epicness')],
  );
}

void main() {
  test('the hit track is the pitch guide, not the bass that plays the same progression', () {
    final t = ProjectTranscriber().transcribe(sampleBase());
    expect(t.rootPitchClass, 3, reason: 'D#');
    // The chorus pitch exactly as the hit plays it.
    final chorus = t.hits.where((h) => h.beat >= 16 && h.beat < 24).toList();
    expect(chorus.map((h) => h.semitone), [0, 0, 1, 1, -2, -2, 1, 1]);
    expect(chorus.map((h) => h.beat), [16, 17, 18, 19, 20, 21, 22, 23]);
    // The intro hits and the epicness pattern come through too.
    expect(t.hits.where((h) => h.beat < 16).map((h) => h.semitone), [-2, -2, -2]);
    final epic = PatternLibrary.instance.classic(PatternKind.pitch, 'epicness')!;
    expect(t.hits.where((h) => h.beat >= 48 && h.beat < 56).map((h) => h.semitone), epic.hits.map((h) => h.semitone));
    expect(t.patterns.values, contains('pitch/epicness/Original'));
  });

  test('drums and marked sections come from the project', () {
    final t = ProjectTranscriber().transcribe(sampleBase());
    expect(t.kick, hasLength(64));
    expect(t.snare, hasLength(32));
    expect(t.sections.map((s) => s.kind), [SectionKind.intro, SectionKind.chorus, SectionKind.epicness]);
    expect(t.sections.map((s) => s.startBeat), [0, 16, 48]);
  });

  test('a track can be forced to be the guide', () {
    final t = ProjectTranscriber().transcribe(sampleBase(), uses: {'bass': TrackUse.guide});
    expect(t.hits.length, 64);
  });

  test('transcriptions round-trip through JSON', () {
    final t = ProjectTranscriber().transcribe(sampleBase()).copyWith(credit: 'Tester', audioSha1: 'abc');
    final back = BaseTranscription.decode(t.encode());
    expect(back.rootKey, t.rootKey);
    expect(back.hits, t.hits);
    expect(back.kick, t.kick);
    expect(
      back.sections.map((s) => '${s.kind}${s.startBeat}${s.endBeat}'),
      t.sections.map((s) => '${s.kind}${s.startBeat}${s.endBeat}'),
    );
    expect(back.credit, 'Tester');
    expect(back.audioSha1, 'abc');
    expect(() => BaseTranscription.decode('{"format":"other"}'), throwsFormatException);
  });

  group('charter', () {
    final t = ProjectTranscriber().transcribe(sampleBase());
    final chart = Charter().write(t);
    List<ChartNote> lane(SampleRole r, double from, double to) =>
        chart.where((n) => n.role == r && n.beat >= from && n.beat < to).toList();

    test('the chorus is words only, in the standard chorus rhythm', () {
      expect(lane(SampleRole.pitch, 16, 48), isEmpty);
      final words = lane(SampleRole.word, 16, 32);
      final std = PatternLibrary.instance.classic(PatternKind.words, 'chorus')!;
      expect(words.map((n) => n.slot), std.hits.map((h) => h.slot));
      expect(words.map((n) => n.beat), std.hits.map((h) => 16 + h.step / 4));
      expect(lane(SampleRole.word, 16, 48).length, std.hits.length * 2);
    });

    test('the pitch sample plays the base hits outside the chorus', () {
      final epic = lane(SampleRole.pitch, 48, 80);
      expect(epic.map((n) => n.semitone), t.hits.where((h) => h.beat >= 48).map((h) => h.semitone));
      expect(lane(SampleRole.pitch, 0, 16).map((n) => n.semitone), [-2, -2, -2]);
    });

    test('epicness gets its wiki word pattern, the intro its quote', () {
      final epic = PatternLibrary.instance.classic(PatternKind.words, 'epicness')!;
      expect(lane(SampleRole.word, 48, 64).length, epic.hits.length);
      expect(lane(SampleRole.word, 0, 16), isEmpty);
      final quote = lane(SampleRole.quote, 0, 80);
      expect(quote, hasLength(1));
      expect(quote.single.beat, 0);
      expect(quote.single.length, 16);
    });

    test('percussion follows the base drums', () {
      expect(lane(SampleRole.kick, 0, 80).map((n) => n.beat), t.kick);
      expect(lane(SampleRole.snare, 0, 80).map((n) => n.beat), t.snare);
    });

    test('section choices override words and pitch', () {
      final c = Charter().write(
        t,
        choices: {
          1: const SectionChoice(
            words: '',
            pitch: PitchMode.pattern,
            pitchPattern: 'pitch/chorus/Chorus Pattern/0*, 12* pattern',
          ),
          2: const SectionChoice(pitch: PitchMode.off),
        },
      );
      expect(c.where((n) => n.role == SampleRole.word && n.beat >= 16 && n.beat < 48), isEmpty);
      final pitch = c.where((n) => n.role == SampleRole.pitch && n.beat >= 16 && n.beat < 24).map((n) => n.semitone);
      expect(pitch.take(4), [0, 12, 0, 12]);
      expect(c.where((n) => n.role == SampleRole.pitch && n.beat >= 48), isEmpty);
    });

    test('random mode is repeatable and only changes what it may', () {
      const r = RandomOptions(enabled: true, seed: 5);
      final a = Charter().write(t, random: r), b = Charter().write(t, random: r);
      expect(a.map((n) => n.toString()), b.map((n) => n.toString()));
      // Percussion and the quote never change.
      for (final role in const [SampleRole.kick, SampleRole.snare, SampleRole.quote]) {
        expect(
          a.where((n) => n.role == role).map((n) => n.beat),
          chart.where((n) => n.role == role).map((n) => n.beat),
        );
      }
      final noFreestyles = Charter().write(t, random: r.copyWith(freestyles: false, pitchPatterns: false));
      expect(noFreestyles.map((n) => n.toString()), chart.map((n) => n.toString()));
    });
  });
}
