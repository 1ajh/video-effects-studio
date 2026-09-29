import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/sparta/audio_base.dart';
import 'package:video_effects_studio/core/sparta/base_renderer.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/model.dart';

void main() {
  for (final (style, lead) in [(BaseStyle.classic, 1.3), (BaseStyle.hyper, 0.45), (BaseStyle.venom, 2.0)]) {
    test('recovers tempo, first bar and harmony of a ${style.name} base with ${lead}s lead-in', () {
      final comp = Composer(
        style: style,
        seed: 5,
      ).compose(defaultPlan(enabled: {SectionKind.chorus, SectionKind.dundundenden, SectionKind.awesomeness}));
      final audio = BaseRenderer().render(comp);
      // Prepend silence so beat 0 is not at the file start.
      final pad = (lead * 48000).round() * 2;
      final data = Float32List(pad + audio.data.length)..setRange(pad, pad + audio.data.length, audio.data);
      final shifted = AudioBuffer(data, sampleRate: 48000, channels: 2);

      final sw = Stopwatch()..start();
      final a = AudioBaseAnalyzer().analyze(shifted);
      // ignore: avoid_print
      print(
        '${style.name}: ${a.bpm} BPM (conf ${a.tempoConfidence.toStringAsFixed(2)}), '
        'bar 1 at ${a.firstDownbeat.toStringAsFixed(3)}s, ${a.bars} bars, tonic ${a.tonicPc} '
        'in ${sw.elapsedMilliseconds} ms',
      );
      expect(a.bpm, closeTo(style.bpm, 0.5));
      final bar = 240 / style.bpm;
      // Downbeat within 30 ms of the true bar grid.
      final err = ((a.firstDownbeat - lead) / bar - ((a.firstDownbeat - lead) / bar).round()) * bar;
      expect(err.abs(), lessThan(0.03));
      expect(a.tonicPc, 2);
      // Roots of whole bars (skip bars that start before the music does).
      final skipBars = ((lead - a.firstDownbeat) / bar).round();
      var agree = 0, total = 0;
      for (var b = 0; b < comp.base.barRoots.length; b++) {
        final i = b + skipBars;
        if (i < 0 || i >= a.barRoots.length) continue;
        total++;
        if (a.barRoots[i] == comp.base.barRoots[b]) agree++;
      }
      expect(agree / total, greaterThan(0.7), reason: '$agree / $total');

      final base = AudioBaseAnalyzer().toBase(a, name: 'x', audioPath: 'x.wav');
      expect(base.lane(SampleRole.pitch), isNotEmpty);
      expect(base.audioOffset, a.firstDownbeat);
    });
  }
}
