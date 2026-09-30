import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/sparta/base.dart';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/section_edits.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';

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

  test('built-in rewrites recompose the music of that section too', () {
    final comp = Composer(seed: 4).compose(
      defaultPlan(length: RemixLength.short, enabled: {SectionKind.chorus, SectionKind.epicness, SectionKind.outro}),
    );
    final s = comp.base.sections[1];
    final rw = [ChartRewrite(s.startBeat, s.endBeat, SectionKind.madness)];
    final out = rewriteComposition(comp, rw);
    String score(Iterable<ScoreEvent> e) =>
        (e.map((x) => '${x.instrument.name}${x.beat}${x.midi}').toList()..sort()).join(' ');
    bool inside(double beat) => s.contains(beat);
    expect(score(out.score.where((e) => inside(e.beat))), isNot(score(comp.score.where((e) => inside(e.beat)))));
    expect(score(out.score.where((e) => !inside(e.beat))), score(comp.score.where((e) => !inside(e.beat))));
    expect(sig(out.base.chart.where((n) => !inside(n.beat))), sig(comp.base.chart.where((n) => !inside(n.beat))));
    expect(out.base.lane(SampleRole.quote).length, comp.base.lane(SampleRole.quote).length);
    // Same request, same music (so a render cache can be reused).
    expect(score(rewriteComposition(comp, rw).score), score(out.score));
    expect(rewritesKey(rw), rewritesKey([ChartRewrite(s.startBeat, s.endBeat, SectionKind.madness)]));
    expect(
      rewritesKey(rw),
      isNot(rewritesKey([ChartRewrite(s.startBeat, s.endBeat, SectionKind.madness, variant: 1)])),
    );
    expect(rewritesKey(const []), '');
  });

  test('a built-in base renders its rewritten sections, and caches the render', () async {
    final tmp = await Directory.systemTemp.createTemp('sparta_rw_');
    addTearDown(() => tmp.delete(recursive: true));
    final engine = SpartaEngine(ffmpegPath: 'ffmpeg', cacheDir: tmp.path);
    const sections = {SectionKind.chorus, SectionKind.epicness, SectionKind.outro};
    final plain = await engine.prepareBase(const BuiltInBaseSource(length: RemixLength.short, sections: sections));
    final s = plain.base.sections[1];
    final src = BuiltInBaseSource(
      length: RemixLength.short,
      sections: sections,
      rewrites: [ChartRewrite(s.startBeat, s.endBeat, SectionKind.madness)],
    );
    final edited = await engine.prepareBase(src);
    double rms(PreparedBase b, double from, double to) => b.audio.slice(b.base.seconds(from), b.base.seconds(to)).rms();
    // Relative difference once the overall gain is matched (the renderer
    // normalises the whole base's peak).
    double diff(double from, double to) {
      final a = plain.audio.slice(plain.base.seconds(from), plain.base.seconds(to)).mono().data;
      final b = edited.audio.slice(edited.base.seconds(from), edited.base.seconds(to)).mono().data;
      final n = a.length < b.length ? a.length : b.length;
      var ab = 0.0, aa = 0.0;
      for (var i = 0; i < n; i++) {
        ab += a[i] * b[i];
        aa += a[i] * a[i];
      }
      final k = aa > 0 ? ab / aa : 1.0;
      var d = 0.0, e = 0.0;
      for (var i = 0; i < n; i++) {
        d += (b[i] - k * a[i]) * (b[i] - k * a[i]);
        e += b[i] * b[i];
      }
      return e > 0 ? d / e : 0;
    }

    expect(rms(edited, s.startBeat, s.endBeat), greaterThan(0.01));
    expect(diff(s.startBeat + 0.5, s.endBeat - 0.5), greaterThan(0.2));
    // Before the section nothing changes.
    expect(diff(0, s.startBeat - 0.5), lessThan(1e-6));
    final files = Directory('${tmp.path}/sparta').listSync().whereType<File>().length;
    await engine.prepareBase(src);
    expect(Directory('${tmp.path}/sparta').listSync().whereType<File>().length, files);
  });
}
