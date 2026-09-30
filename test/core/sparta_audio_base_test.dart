import 'dart:math' as math;
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

  test('finds beat 1 under loud off-beat open hats and reads G minor over a tuned kick', () {
    // What fooled the analyser on real Sparta bases: open hats between the
    // beats louder than anything on them, a tuned kick on every beat (a
    // constant "note"), snare on 2 and 4, and a natural-minor progression.
    const sr = 22050, bpm = 140.0, bars = 24, lead = 0.61;
    final beat = 60 / bpm;
    final x = Float32List(((lead + bars * 4 * beat + 1) * sr).round());
    final rng = math.Random(3);
    void add(double at, double seconds, double Function(double t) f) {
      final a = (at * sr).round();
      for (var i = 0; i < seconds * sr && a + i < x.length; i++) {
        x[a + i] += f(i / sr);
      }
    }

    // G minor, E-flat, F, D minor: all in G natural minor (= D Phrygian).
    const chords = [
      [55.0, 58.0, 62.0],
      [51.0, 55.0, 58.0],
      [53.0, 57.0, 60.0],
      [50.0, 53.0, 57.0],
    ];
    double hz(double midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();
    var hatPrev = 0.0;
    for (var b = 0; b < bars; b++) {
      final t0 = lead + b * 4 * beat;
      final chord = chords[b % 4];
      add(t0, 4 * beat, (t) {
        var v = 0.3 * math.sin(2 * math.pi * hz(chord[0] - 12) * t);
        for (final n in chord) {
          v += 0.06 * math.sin(2 * math.pi * hz(n) * t);
        }
        return v * math.min(1, t * 50);
      });
      for (var k = 0; k < 4; k++) {
        final tb = t0 + k * beat;
        // Kick tuned to E2 (not in the key), louder on beat 1.
        add(
          tb,
          0.3,
          (t) =>
              (k == 0 ? 0.9 : 0.7) *
              math.sin(2 * math.pi * (82 * t + 60 * (1 - math.exp(-t * 30)) / 30)) *
              math.exp(-t * 9),
        );
        if (k.isOdd) add(tb, 0.15, (t) => 0.5 * (rng.nextDouble() * 2 - 1) * math.exp(-t * 25));
        // Open hat on the off-beat: bright (differenced) noise, the loudest hit.
        add(tb + beat / 2, 0.2, (t) {
          final n = rng.nextDouble() * 2 - 1, v = n - hatPrev;
          hatPrev = n;
          return 0.9 * v * math.exp(-t * 14);
        });
      }
    }
    final a = AudioBaseAnalyzer().analyze(AudioBuffer(x, sampleRate: sr));
    expect(a.bpm, closeTo(bpm, 0.5));
    final bar = 4 * beat;
    final err = ((a.firstDownbeat - lead) / bar - ((a.firstDownbeat - lead) / bar).round()) * bar;
    expect(err.abs(), lessThan(0.03), reason: 'bar 1 at ${a.firstDownbeat}');
    expect(a.tonicPc, 2, reason: 'G minor shares D Phrygian\'s notes');
  });

  test('an exact tempo is used as given, and bar 1 stays on the real bar grid at half or double time', () {
    final comp = Composer(
      style: BaseStyle.venom,
      seed: 2,
    ).compose(defaultPlan(enabled: {SectionKind.chorus, SectionKind.epicness, SectionKind.madness}));
    final audio = BaseRenderer().render(comp);
    final bar = 240 / BaseStyle.venom.bpm;
    for (final tempo in [BaseStyle.venom.bpm / 2, BaseStyle.venom.bpm * 2]) {
      final a = AudioBaseAnalyzer().analyze(audio, tempo: tempo);
      expect(a.bpm, tempo);
      expect(a.tempoConfidence, 1);
      // Wherever bar 1 lands, it is on a bar line of the music.
      final err = (a.firstDownbeat / bar - (a.firstDownbeat / bar).round()) * bar;
      expect(err.abs(), lessThan(0.03), reason: 'at $tempo BPM, bar 1 at ${a.firstDownbeat}');
      expect(a.barSeconds, closeTo(240 / tempo, 1e-9));
    }
  });
}
