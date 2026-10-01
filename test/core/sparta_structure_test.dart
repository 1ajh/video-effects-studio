import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/score.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sectioning.dart';

/// A part playing [perBar] evenly spaced notes in bars [from, to).
ChartTrack part(String name, int from, int to, {int perBar = 4, int key = 62, double length = 0.25}) => ChartTrack(
  id: name,
  name: name,
  notes: [
    for (var b = from; b < to; b++)
      for (var i = 0; i < perBar; i++) RawNote(b * 4 + i * 4 / perBar, length, key + (i % 3) * 2),
  ],
);

void main() {
  group('named sections', () {
    test('each bar follows the named parts playing in it; one-bar blips fold away', () {
      final marks = markersFromNamedParts([
        (beat: 0, length: 64, name: 'perc intro'),
        (beat: 64, length: 32, name: 'Epicness Pitch'),
        (beat: 96, length: 32, name: 'madness'),
        (beat: 96, length: 32, name: 'madbass'),
        (beat: 112, length: 4, name: 'epic fill'),
        (beat: 128, length: 16, name: 'outro pad'),
      ], 4);
      expect(
        [for (final m in marks) (m.beat, sectionKindFor(m.name))],
        [
          (0.0, SectionKind.intro),
          (64.0, SectionKind.epicness),
          (96.0, SectionKind.madness),
          (128.0, SectionKind.outro),
        ],
      );
      expect(marks[1].name, 'Epicness Pitch');
    });

    test('too few named parts are not trusted', () {
      expect(
        markersFromNamedParts([
          (beat: 0, length: 8, name: 'Prepicness'),
          (beat: 8, length: 4, name: 'madness hit'),
          (beat: 12, length: 120, name: 'Lead'),
        ], 4),
        isEmpty,
      );
    });
  });

  test('sections follow where the parts change, starting with the intro', () {
    // 16 bars of pad, then drums and bass, then fast arps join, then a pad
    // tail: the shape of a typical community base.
    final tracks = [
      part('Pad', 0, 16, perBar: 1, length: 4),
      part('Kick', 16, 60),
      part('Snare', 16, 60, perBar: 2),
      part('Bass', 16, 60, perBar: 8, key: 38),
      part('Lead', 16, 32, perBar: 6, key: 74),
      part('Arp', 32, 60, perBar: 16, key: 70),
      part('Outro pad', 60, 64, perBar: 1, length: 4),
    ];
    final sections = sectionsFromTracks(tracks, 64, 4);
    expect(sections.first.kind, SectionKind.intro);
    expect(sections.first.endBeat, 64);
    final starts = sections.map((s) => s.startBeat).toList();
    expect(starts, containsAll([64.0, 128.0]));
    expect(sections.last.endBeat, 256);
    expect(sections.skip(1).map((s) => s.kind), isNot(contains(SectionKind.intro)));
    // Contiguous, no gaps.
    for (var i = 1; i < sections.length; i++) {
      expect(sections[i].startBeat, sections[i - 1].endBeat);
    }
  });

  test('drum parts are recognised from real-world channel and sample names', () {
    const expected = {
      'Grv Kick 17': Instrument.kick,
      'DM-BD 0021': Instrument.kick,
      'FPC_SdSt_B_004': Instrument.snare,
      'Grv Snareclap 17': Instrument.clap,
      'VEC4 Open HH 031': Instrument.openHat,
      'Attack OHat 06': Instrument.openHat,
      'VFOB1 Hihat OP 25': Instrument.openHat,
      'Closed HH': Instrument.hat,
      '909 CH 2': Instrument.hat,
      'VEC4 Percussions 020': Instrument.tom,
      'Ride 2': Instrument.crash,
    };
    for (final e in expected.entries) {
      expect(drumForName(e.key), e.value, reason: e.key);
    }
    for (final name in ['Custom', 'Atom Lead', 'Pride', 'Phat Bass', 'Morphine', 'Grim']) {
      expect(drumForName(name), isNull, reason: name);
    }
  });

  test('a natural-minor project keeps its own notes (G minor reads as D Phrygian)', () {
    // G A Bb C D Eb F, with G strongest: G Phrygian would put Ab against A.
    final notes = [
      for (final (key, len) in [(55, 4.0), (57, 1.0), (58, 2.0), (60, 1.0), (62, 2.0), (63, 1.0), (65, 1.0), (43, 8.0)])
        RawNote(0, len, key),
    ];
    expect(tonicPitchClass(notes), 2);
    final pcs = {for (final d in phrygian) (2 + d) % 12};
    expect(notes.every((n) => pcs.contains(n.key % 12)), isTrue);
  });
}
