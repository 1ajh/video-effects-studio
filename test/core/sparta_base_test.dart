import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/dsp.dart';
import 'package:video_effects_studio/core/sparta/base_renderer.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/model.dart';

void main() {
  group('composer', () {
    test('default plan honours toggles and length', () {
      final full = defaultPlan();
      expect(full.map((p) => p.kind), [
        SectionKind.intro,
        SectionKind.chorus,
        SectionKind.dundundenden,
        SectionKind.epicness,
        SectionKind.madness,
        SectionKind.awesomeness,
        SectionKind.outro,
      ]);
      final short = defaultPlan(length: RemixLength.short, enabled: {SectionKind.chorus, SectionKind.madness});
      expect(short.map((p) => p.kind), [SectionKind.chorus, SectionKind.madness]);
      expect(short.every((p) => p.bars == 4), isTrue);
      expect(defaultPlan(length: RemixLength.extended)[1].bars, 12);
    });

    for (final style in BaseStyle.values) {
      test('${style.name}: sections are contiguous and every lane is charted', () {
        final c = Composer(style: style, seed: 3).compose(defaultPlan());
        final base = c.base;
        expect(base.bpm, style.bpm);
        expect(base.sections.first.startBeat, 0);
        for (var i = 1; i < base.sections.length; i++) {
          expect(base.sections[i].startBeat, base.sections[i - 1].endBeat);
        }
        expect(base.lengthBeats, greaterThan(base.sections.last.endBeat));
        for (final role in SampleRole.values) {
          expect(base.lane(role), isNotEmpty, reason: role.name);
        }
        // Everything sits on the 16th grid, inside the base, in D Phrygian.
        const inScale = {0, 1, 3, 5, 7, 8, 10};
        for (final n in base.chart) {
          expect((n.beat * 4 - (n.beat * 4).round()).abs(), lessThan(1e-9));
          expect(n.length, greaterThan(0));
          expect(n.end, lessThanOrEqualTo(base.lengthBeats));
          if (n.role == SampleRole.pitch) expect(inScale.contains(n.semitone % 12), isTrue, reason: '$n');
        }
        expect(base.barRoots.length, base.sections.last.endBeat ~/ 4);
        expect(c.score, isNotEmpty);
      });
    }

    test('same seed is deterministic, different seeds differ', () {
      String sig(Composition c) => c.base.lane(SampleRole.pitch).map((n) => '${n.beat}/${n.semitone}').join(' ');
      final a = Composer(seed: 5).compose(defaultPlan());
      final b = Composer(seed: 5).compose(defaultPlan());
      final d = Composer(seed: 6).compose(defaultPlan());
      expect(sig(a), sig(b));
      expect(sig(a), isNot(sig(d)));
    });

    test('re-rolling one section leaves the others alone', () {
      final plan = defaultPlan();
      final a = Composer(seed: 2).compose(plan);
      final b = Composer(seed: 2).compose(plan, sectionSeeds: {SectionKind.epicness: 9});
      final epic = a.base.sections.firstWhere((s) => s.kind == SectionKind.epicness);
      String lane(Composition c, bool inside) => c.base
          .lane(SampleRole.pitch)
          .where((n) => epic.contains(n.beat) == inside)
          .map((n) => '${n.beat}/${n.semitone}')
          .join(' ');
      expect(lane(a, false), lane(b, false));
      expect(lane(a, true), isNot(lane(b, true)));
    });

    test('bar roots override drives the chart harmony', () {
      final roots = List.filled(64, 5);
      final c = Composer(seed: 1).compose(defaultPlan(), barRoots: roots);
      final chorus = c.base.sections.firstWhere((s) => s.kind == SectionKind.chorus);
      final first = c.base.lane(SampleRole.pitch).firstWhere((n) => chorus.contains(n.beat));
      expect(first.semitone % 12, 5);
    });
  });

  test('renders a base of the right length with sane levels', () {
    final c = Composer(style: BaseStyle.classic, seed: 1).compose(
      defaultPlan(length: RemixLength.short, enabled: {SectionKind.intro, SectionKind.chorus, SectionKind.madness}),
    );
    final sw = Stopwatch()..start();
    final audio = BaseRenderer().render(c);
    sw.stop();
    // ignore: avoid_print
    print('rendered ${c.base.durationSeconds.toStringAsFixed(1)}s of base in ${sw.elapsedMilliseconds} ms');
    expect(audio.channels, 2);
    expect(audio.sampleRate, 48000);
    expect(audio.duration, closeTo(c.base.durationSeconds, 0.01));
    expect(audio.peak(), closeTo(dbToGain(-3), 0.01));
    final lufs = loudness(audio.data, 48000, channels: 2);
    expect(lufs, inInclusiveRange(-24, -8));
    // The chorus is much denser than the intro.
    final intro = c.base.sections.first, chorus = c.base.sections[1];
    final a = audio.slice(c.base.seconds(intro.startBeat), c.base.seconds(intro.endBeat)).rms();
    final b = audio.slice(c.base.seconds(chorus.startBeat), c.base.seconds(chorus.endBeat)).rms();
    expect(b, greaterThan(a));
    // Stereo, not dual mono.
    var diff = 0.0;
    for (var i = 0; i + 1 < audio.data.length; i += 2) {
      diff = math.max(diff, (audio.data[i] - audio.data[i + 1]).abs());
    }
    expect(diff, greaterThan(0.01));
  });
}
