// Writes the checked transcription of Keaton's "300 This is Sparta EXTENDED"
// instrumental base (bases/transcriptions/keaton-sparta-extended.json).
//
//   dart run tool/curated/keaton_sparta_extended.dart
//
// How it was checked, against the catalog's MP3 (SHA-1 457bbe5f…):
// * tempo 140 BPM, beat 0 at 0.025 s (the silence-to-sound edges at beats 0,
//   8 and 160 all land within a millisecond of the grid), 72 bars of music
//   (it ends at 123.4 s; the rest of the file is the last hit ringing out);
// * sections from a bar-by-bar self-similarity map plus the spectrogram:
//   intro 2, chorus 4, DunDunDenDen 6, chorus 8, epicness 4, chorus 8,
//   madness 8, chorus 8, epicness 8, build 4, chorus 12 (the first 32 bars
//   are the classic short base);
// * harmony from the bass and a chroma per half bar: D, D#, C, D# (major
//   chords, two beats each) all the way through, the intro hits on C;
// * the bass line, octave by octave, from a constant-Q transform per eighth;
// * the drums per section from the percussive part of the audio.
//
// The pitch guide is the Sparta Remix Wiki's original patterns for each part
// (Keaton's own), which follow that progression note for note.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/patterns.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

const bar = 4.0;

/// Half-bar chord roots from bar 2 on: D, D#, C, D#.
const progression = [0, 1, -2, 1];

int rootAt(double beat) => progression[((beat - 8) / 2).floor() % 4];

final sections = <Section>[
  const Section(SectionKind.intro, 0, 2 * bar),
  const Section(SectionKind.chorus, 2 * bar, 6 * bar),
  const Section(SectionKind.dundundenden, 6 * bar, 12 * bar),
  const Section(SectionKind.chorus, 12 * bar, 20 * bar),
  const Section(SectionKind.epicness, 20 * bar, 24 * bar),
  const Section(SectionKind.chorus, 24 * bar, 28 * bar),
  const Section(SectionKind.awesomeness, 28 * bar, 32 * bar, name: 'Awesomeness 1'),
  const Section(SectionKind.madness, 32 * bar, 40 * bar),
  const Section(SectionKind.chorus, 40 * bar, 48 * bar),
  const Section(SectionKind.epicness, 48 * bar, 56 * bar),
  const Section(SectionKind.postEpicness, 56 * bar, 60 * bar, name: 'Build'),
  const Section(SectionKind.awesomeness, 60 * bar, 64 * bar, name: 'Awesomeness 2'),
  const Section(SectionKind.chorus, 64 * bar, 72 * bar),
];

/// A wiki pattern looped over [from]..[to] beats.
List<GuideNote> pattern(String notation, double from, double to) {
  final p = PatternLibrary.custom(PatternKind.pitch, notation);
  return [for (final h in p.looped((to - from) * 4)) GuideNote(from + h.step / 4, h.length / 4, h.semitone)];
}

const chorusPitch = '0*** 0*** 1*** 1*** -2*** -2*** 1*** 1***';
const dundunPitch = '0*__0*__1*__1*__-2*__-2*__1*__1*__';
const epicPitch = '0*__12*** 1*** 13*__10* 10_ 10*__13* 1* 13* 1*';
const madness1 = '00_00_0011_11_11-2-2_-2-2_-2-211_11_11';
const madness2 = "0'/0'/0*0'/0'/0*1'/1'/1*1'/1'/1*-2'/-2'/-2*-2'/-2'/-2*1'/1'/1*1'/1'/1*";
const awesome1 =
    '0_4_12* 24* 1* 5 1 13*** -2_-2_10* 14* 8* 1* 13***0* 7* 12* 16* 17* 5* 1_5 1 -2* 2_29* 10* 1_5 1 20***';
const awesome2 =
    '12* 0* 4* 7 4 13* 17* 20* 17* 10* -2* 2* 5* 13* 17* 13* 8* 0* 7* 0 7 12 19 1 8 13 20 13 8 1* -2* 10* 2* 5* 1* 17* 1 5 1 8';

List<GuideNote> hits() => [
  for (final b in [0.0, 2.0, 4.0]) GuideNote(b, 1.5, -2),
  ...pattern(chorusPitch, 8, 24),
  ...pattern(dundunPitch, 24, 48),
  ...pattern(chorusPitch, 48, 80),
  ...pattern(epicPitch, 80, 96),
  ...pattern(chorusPitch, 96, 112),
  ...pattern(awesome1, 112, 128),
  ...pattern(madness1, 128, 144),
  ...pattern(madness2, 144, 160),
  ...pattern(chorusPitch, 160, 192),
  ...pattern(epicPitch, 192, 224),
  ...pattern(dundunPitch, 224, 240),
  ...pattern(awesome2, 240, 256),
  ...pattern(chorusPitch, 256, 288),
];

/// Eighths alternating the root and its octave (the chorus bass).
List<GuideNote> octaves(double from, double to) => [
  for (var b = from; b < to; b += 0.5) GuideNote(b, 0.5, rootAt(b) - ((b * 2).round().isOdd ? 12 : 24)),
];

/// Eighths on the root.
List<GuideNote> roots(double from, double to, {int octave = -24}) => [
  for (var b = from; b < to; b += 0.5) GuideNote(b, 0.5, rootAt(b) + octave),
];

/// One note per chord, held.
List<GuideNote> held(double from, double to, {int octave = -24}) => [
  for (var b = from; b < to; b += 2) GuideNote(b, 2, rootAt(b) + octave),
];

List<GuideNote> bass() => [
  for (final b in [0.0, 2.0, 4.0]) GuideNote(b, 2, -26),
  ...octaves(8, 24),
  ...held(24, 40),
  ...roots(40, 48),
  ...octaves(48, 80),
  ...octaves(96, 128),
  ...held(128, 144, octave: -12),
  ...held(144, 160),
  ...octaves(160, 192),
  ...roots(192, 240),
  ...octaves(240, 288),
];

/// Major chords on every half bar from bar 2 to the end.
List<GuideNote> chords() => [
  for (var b = 8.0; b < 288; b += 2)
    for (final i in const [0, 4, 7]) GuideNote(b, 2, rootAt(b) + i),
];

List<double> every(double from, double to, double step, {double offset = 0}) => [
  for (var b = from + offset; b < to - 1e-9; b += step) b,
];

/// Beat [k] (0-based) of every bar in [from]..[to].
List<double> onBeats(double from, double to, List<int> beats) => [
  for (var b = from; b < to; b += bar)
    for (final k in beats) b + k,
];

void main() {
  final groove = [(8.0, 24.0), (48.0, 80.0), (96.0, 128.0), (160.0, 192.0), (240.0, 288.0)];
  final kick = <double>[
    for (final (a, z) in groove) ...every(a, z, 1),
    ...every(40, 48, 1),
    ...onBeats(128, 160, [0, 2]),
    ...onBeats(192, 240, [0, 2]),
  ]..sort();
  final snare = <double>[
    for (final (a, z) in groove) ...onBeats(a, z, [1, 3]),
    ...onBeats(192, 240, [1, 3]),
  ]..sort();
  final hat = <double>[
    for (final (a, z) in groove) ...every(a, z, 1, offset: 0.5),
    ...every(24, 40, 1),
    ...every(40, 48, 1, offset: 0.5),
    ...every(93.5, 96, 0.25),
    ...every(224, 240, 1, offset: 0.5),
  ]..sort();

  final t = BaseTranscription(
    bpm: 140,
    rootKey: 62,
    lengthBeats: 288,
    sections: sections,
    hits: hits(),
    bass: bass(),
    chords: chords(),
    kick: kick,
    snare: snare,
    hat: hat,
    audioOffset: 0.025,
    source: TranscriptionSource.curated,
    credit: 'Checked against the audio (spectrogram, chroma and bass) for SRLE Studio',
    baseName: 'Sparta Extended Remix (official instrumental base)',
    maker: 'Keaton (Funtastic Power!)',
    audioSha1: '457bbe5f433ec2c2e8be8b21cc20256afb6043cf',
    catalogId: 'keaton/sparta-extended',
  );
  const out = 'bases/transcriptions/keaton-sparta-extended.json';
  File(out).writeAsStringSync('${t.encode()}\n');
  print(
    'wrote $out: ${t.sections.length} sections, ${t.hits.length} hits, ${t.bass.length} bass notes, '
    '${t.chords.length ~/ 3} chords, ${kick.length}/${snare.length}/${hat.length} kick/snare/hat',
  );
}
