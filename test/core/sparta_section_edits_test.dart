import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/sparta/base.dart';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/section_edits.dart';

void main() {
  final base = Composer(seed: 4)
      .compose(
        defaultPlan(
          length: RemixLength.short,
          enabled: {SectionKind.intro, SectionKind.chorus, SectionKind.epicness, SectionKind.madness},
        ),
      )
      .base;
  SpartaBase apply(SectionEdits e) => e.apply(base, style: BaseStyle.classic, seed: 4);
  List<ChartNote> inRange(SpartaBase b, Section s, {bool tonal = true}) => [
    for (final n in b.chart)
      if (s.contains(n.beat) && (!tonal || n.role.isTonal)) n,
  ];
  String sig(Iterable<ChartNote> notes) => notes.map((n) => '${n.role.name}${n.beat}/${n.semitone}').join(' ');

  test('relabel keeping the notes changes only the label', () {
    final e = const SectionEdits().relabel(base.sections, 1, SectionKind.madness);
    final b = apply(e);
    expect(b.sections[1].kind, SectionKind.madness);
    expect(b.sections[1].title, 'Madness');
    expect(sig(b.chart), sig(base.chart));
  });

  test('relabel with a rewrite recomposes that section only, in key and never the quote', () {
    final s = base.sections[1];
    final e = const SectionEdits().relabel(base.sections, 1, SectionKind.madness, rewrite: true);
    final b = apply(e);
    expect(sig(inRange(b, s)), isNot(sig(inRange(base, s))));
    expect(inRange(b, s), isNotEmpty);
    // Everything outside the section is untouched.
    String outside(SpartaBase x) => sig(x.chart.where((n) => !s.contains(n.beat)));
    expect(outside(b), outside(base));
    expect(b.lane(SampleRole.quote).length, base.lane(SampleRole.quote).length);
    // Deterministic, so saved edits come back the same.
    expect(sig(apply(e).chart), sig(b.chart));
    // Pitch notes stay in D Phrygian (the built-in key).
    final pcs = {for (final d in phrygian) d % 12};
    expect(inRange(b, s).where((n) => n.role == SampleRole.pitch).every((n) => pcs.contains(n.semitone % 12)), isTrue);
  });

  test('re-roll gives a new take each time', () {
    var e = const SectionEdits();
    final takes = <String>{sig(inRange(base, base.sections[2]))};
    for (var i = 0; i < 3; i++) {
      e = e.reroll(apply(e).sections, 2);
      takes.add(sig(inRange(apply(e), base.sections[2])));
    }
    expect(takes, hasLength(4));
    // Superseded rewrites are dropped, so edits stay small.
    expect(e.rewrites, hasLength(1));
  });

  test('split, merge and boundary moves snap to bars and keep sections contiguous', () {
    final first = base.sections[1];
    var e = const SectionEdits().split(base.sections, 1, first.startBeat + 8);
    var l = apply(e).sections;
    expect(l, hasLength(base.sections.length + 1));
    expect(l[1].endBeat, first.startBeat + 8);
    expect(l[2].startBeat, first.startBeat + 8);

    e = e.moveBoundary(l, 1, first.startBeat + 13.2, 4);
    l = apply(e).sections;
    expect(l[1].endBeat, first.startBeat + 12);
    // Never shorter than a bar.
    e = e.moveBoundary(l, 1, first.startBeat - 50, 4);
    l = apply(e).sections;
    expect(l[1].lengthBeats, 4);

    e = e.mergeWithNext(l, 1);
    l = apply(e).sections;
    expect(l, hasLength(base.sections.length));
    expect(l[1].startBeat, first.startBeat);
    expect(l[1].endBeat, first.endBeat);
    for (var i = 1; i < l.length; i++) {
      expect(l[i].startBeat, l[i - 1].endBeat);
    }
    // Notes never move with the labels.
    expect(sig(apply(e).chart), sig(base.chart));
  });

  test('rename, and survive a JSON round trip', () {
    var e = const SectionEdits().rename(base.sections, 0, 'Leonidas intro');
    e = e.relabel(apply(e).sections, 2, SectionKind.awesomeness, rewrite: true);
    final back = SectionEdits.fromJson(jsonDecode(jsonEncode(e.toJson())));
    expect(apply(back).sections[0].title, 'Leonidas intro');
    expect(sig(apply(back).chart), sig(apply(e).chart));
    expect(apply(back).sections.map((s) => s.kind), apply(e).sections.map((s) => s.kind));
  });

  test('a layout saved for a different base length is ignored', () {
    final e = SectionEdits(layout: [Section(SectionKind.madness, 0, base.sections.last.endBeat + 16)]);
    expect(e.fits(base), isFalse);
    expect(apply(e).sections.map((s) => s.kind), base.sections.map((s) => s.kind));
  });

  test("a project's own sample lanes are never rewritten", () {
    final src = ChartSource(
      name: 'x',
      path: '/x.mid',
      kind: BaseKind.midi,
      bpm: 140,
      tracks: [
        ChartTrack(id: 'p', name: 'Pitch', notes: [for (var b = 0; b < 32; b++) RawNote(b * 1.0, 0.5, 62 + (b % 3))]),
      ],
    );
    final own = src.toBase(src.guessMapping());
    expect(own.canRewriteChart, isFalse);
    final e = const SectionEdits().relabel(own.sections, 0, SectionKind.madness, rewrite: true);
    final b = e.apply(own, style: BaseStyle.classic, seed: 1);
    expect(sig(b.chart), sig(own.chart));
    expect(b.sections[0].kind, SectionKind.madness);
  });

  test("rewrites leave the sample drums locked to a project's own kick and snare", () {
    final src = ChartSource(
      name: 'x',
      path: '/x.mid',
      kind: BaseKind.midi,
      bpm: 140,
      tracks: [
        ChartTrack(id: 'k', name: 'Kick', notes: [for (var b = 0; b < 64; b++) RawNote(b * 1.0, 0.25, 36)]),
        ChartTrack(id: 's', name: 'Snare', notes: [for (var b = 0; b < 32; b++) RawNote(b * 2.0 + 1, 0.25, 38)]),
        ChartTrack(
          id: 'b',
          name: 'Bass',
          notes: [for (var b = 0; b < 16; b++) RawNote(b * 4.0, 3.5, b.isEven ? 38 : 39)],
        ),
      ],
    );
    final auto = src.toBase(src.guessMapping());
    expect(auto.canRewriteChart, isTrue);
    expect(auto.composedRoles, isNot(contains(SampleRole.kick)));
    final e = const SectionEdits().reroll(auto.sections, 0);
    final b = e.apply(auto, style: BaseStyle.classic, seed: 1);
    expect(sig(b.lane(SampleRole.kick)), sig(auto.lane(SampleRole.kick)));
    expect(sig(b.lane(SampleRole.snare)), sig(auto.lane(SampleRole.snare)));
    expect(sig(b.chart), isNot(sig(auto.chart)));
  });
}
