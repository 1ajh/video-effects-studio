import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/sparta/audio_base.dart';
import 'package:video_effects_studio/core/sparta/audio_sections.dart';
import 'package:video_effects_studio/core/sparta/audio_transcriber.dart';
import 'package:video_effects_studio/core/sparta/base_renderer.dart';
import 'package:video_effects_studio/core/sparta/score.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

/// A Sparta-style base: kick on every beat, snare on 2 and 4, hats on the
/// off-beats, orchestra stabs playing the chorus pitch pattern
/// (0 0 +1 +1 -2 -2 +1 +1 from D5) and a bass following it, at 140 BPM.
Score sampleScore({int bars = 24, double bpm = 140}) {
  const pattern = [0, 0, 1, 1, -2, -2, 1, 1];
  final events = <ScoreEvent>[];
  for (var b = 0; b < bars; b++) {
    for (var k = 0; k < 4; k++) {
      final beat = b * 4.0 + k;
      // The kick leans on beat 1, as in real bases; a crash opens every 4 bars.
      events.add(ScoreEvent(Instrument.kick, beat, 0.25, velocity: k == 0 ? 1 : 0.75));
      if (k.isOdd) events.add(ScoreEvent(Instrument.snare, beat, 0.25, velocity: 0.7));
      if (k == 0 && b % 4 == 0) events.add(ScoreEvent(Instrument.crash, beat, 2));
      // A low boom marks every bar line (the "dun" of the base).
      if (k == 0) events.add(ScoreEvent(Instrument.tom, beat, 1, midi: const [38]));
      events.add(ScoreEvent(Instrument.hat, beat + 0.5, 0.25, velocity: 0.7));
      final semi = pattern[(b % 2) * 4 + k];
      // Octave hits (a fifth stacked on top would read equally well as the
      // pattern from the fifth: audio alone can't tell those apart).
      events.add(ScoreEvent(Instrument.stab, beat, 0.45, midi: [74.0 + semi, 86.0 + semi]));
      events.add(ScoreEvent(Instrument.bass, beat, 0.45, midi: [38.0 + semi]));
      events.add(ScoreEvent(Instrument.bass, beat + 0.5, 0.45, midi: [50.0 + semi]));
    }
  }
  return Score(events, bpm: bpm, lengthBeats: bars * 4.0 + 4);
}

AudioBuffer withLeadIn(AudioBuffer audio, double lead) {
  final pad = (lead * audio.sampleRate).round() * audio.channels;
  final data = Float32List(pad + audio.data.length)..setRange(pad, pad + audio.data.length, audio.data);
  return AudioBuffer(data, sampleRate: audio.sampleRate, channels: audio.channels);
}

double f1(List<double> truth, List<double> found, {double tol = 0.05}) {
  if (truth.isEmpty || found.isEmpty) return truth.isEmpty && found.isEmpty ? 1 : 0;
  var hit = 0;
  final used = <int>{};
  for (final t in truth) {
    for (var i = 0; i < found.length; i++) {
      if (!used.contains(i) && (found[i] - t).abs() <= tol) {
        used.add(i);
        hit++;
        break;
      }
    }
  }
  final p = hit / found.length, r = hit / truth.length;
  return p + r == 0 ? 0 : 2 * p * r / (p + r);
}

void main() {
  final rendered = BaseRenderer().render(sampleScore());

  for (final lead in [1.3, 0.45]) {
    test('recovers tempo, first bar and key of a base with a ${lead}s lead-in', () {
      final a = AudioBaseAnalyzer().analyze(withLeadIn(rendered, lead));
      expect(a.bpm, closeTo(140, 0.5));
      const bar = 240 / 140;
      final err = ((a.firstDownbeat - lead) / bar - ((a.firstDownbeat - lead) / bar).round()) * bar;
      expect(err.abs(), lessThan(0.03));
      expect(a.tonicPc, 2);
    });
  }

  test('lines a project up on the audio\'s beats when the audio makes sound before beat 1', () {
    // A click 0.15 s before the first beat: the first sound isn't the first
    // note, and the project's hats alone could line up a 16th off.
    const lead = 0.45;
    final audio = withLeadIn(rendered, lead);
    final click = ((lead - 0.15) * audio.sampleRate).round();
    for (var i = 0; i < audio.sampleRate ~/ 100; i++) {
      for (var c = 0; c < audio.channels; c++) {
        audio.data[(click + i) * audio.channels + c] = i.isEven ? 0.8 : -0.8;
      }
    }
    final hats = [
      for (final e in sampleScore().events)
        if (e.instrument == Instrument.hat) e.beat * 60 / 140,
    ];
    final off = AudioBaseAnalyzer().alignHits(audio, hats, firstNoteSeconds: 0, bpm: 140);
    expect(off, closeTo(lead, 0.012));
  });

  test('reads the chord progression from a held bass, down to D2', () {
    // D, D#, C, D# for half a bar each from D2 (73 Hz), under orchestra hits
    // and kicks whose 50 Hz body rings louder than the bass.
    const progression = [0, 1, -2, 1];
    final events = <ScoreEvent>[];
    for (var h = 0; h < 48; h++) {
      final beat = h * 2.0, semi = progression[h % 4];
      events.add(ScoreEvent(Instrument.bass, beat, 1.95, midi: [38.0 + semi]));
      for (var k = 0; k < 2; k++) {
        events.add(ScoreEvent(Instrument.kick, beat + k, 0.25));
        events.add(ScoreEvent(Instrument.stab, beat + k, 0.45, midi: [74.0 + semi, 86.0 + semi]));
        if ((h * 2 + k).isOdd) events.add(ScoreEvent(Instrument.snare, beat + k, 0.25, velocity: 0.7));
      }
    }
    final audio = BaseRenderer().render(Score(events, bpm: 140, lengthBeats: 100));
    final t = AudioTranscriber().transcribe(AudioBaseAnalyzer().analyze(withLeadIn(audio, 0.6)), name: 'synth');
    var right = 0, total = 0;
    for (var h = 2; h < t.lengthBeats / 2 - 2; h++) {
      total++;
      if (t.chordRootAt(h * 2 + 0.1) == progression[h % 4]) right++;
    }
    expect(right / total, greaterThan(0.85), reason: '$right of $total half bars');
  });

  test('finds where the chord loop starts when bar 1 is half a bar off', () {
    List<GuideNote> loop(int from, int key, {List<int> progression = const [0, 1, -2, 1]}) => [
      for (var h = 0; h < 32; h++)
        for (final iv in [0, 4, 7]) GuideNote(h * 2.0, 2, progression[(h - from) % 4] + key + iv),
    ];
    expect(AudioSectioner.cyclePhase(loop(0, 0)), 0);
    expect(AudioSectioner.cyclePhase(loop(1, 0)), 1);
    expect(AudioSectioner.cyclePhase(loop(3, 5)), 3, reason: 'in any key');
    expect(AudioSectioner.cyclePhase(loop(2, -2)), 2, reason: 'a bar off');
    expect(AudioSectioner.cyclePhase(loop(1, 0, progression: const [0, -4, 3, -2])), 0, reason: 'another progression');
  });

  test('transcribes the drums and the chorus pitch pattern from audio', () {
    const lead = 0.8;
    final a = AudioBaseAnalyzer().analyze(withLeadIn(rendered, lead));
    final t = AudioTranscriber().transcribe(a, name: 'synth');
    expect(t.rootPitchClass, 2);
    expect(t.source, TranscriptionSource.audio);
    const spb = 60 / 140;
    // Ground truth in seconds of the audio file.
    final truthKick = [for (var b = 0; b < 24 * 4; b++) lead + b * spb];
    final truthSnare = [for (var b = 1; b < 24 * 4; b += 2) lead + b * spb];
    List<double> sec(List<double> beats) => [for (final b in beats) t.audioOffset + b * spb];
    expect(f1(truthKick, sec(t.kick)), greaterThan(0.85));
    expect(f1(truthSnare, sec(t.snare)), greaterThan(0.6));
    // The pitch guide plays the chorus pattern: compare pitch classes on the beats.
    var agree = 0, total = 0;
    for (final h in t.hits) {
      final sTime = t.audioOffset + h.beat * spb - lead;
      final beatIndex = (sTime / spb).round();
      if ((sTime / spb - beatIndex).abs() > 0.1 || beatIndex < 0 || beatIndex >= 96) continue;
      total++;
      const pattern = [0, 0, 1, 1, -2, -2, 1, 1];
      if ((h.semitone - pattern[beatIndex % 8]) % 12 == 0) agree++;
    }
    expect(total, greaterThan(40));
    expect(agree / total, greaterThan(0.75), reason: '$agree / $total');
    expect(t.patterns, isNotEmpty);
  });

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
    const bar = 240 / 140;
    for (final tempo in [70.0, 280.0]) {
      final a = AudioBaseAnalyzer().analyze(rendered, tempo: tempo);
      expect(a.bpm, tempo);
      expect(a.tempoConfidence, 1);
      final err = (a.firstDownbeat / bar - (a.firstDownbeat / bar).round()) * bar;
      expect(err.abs(), lessThan(0.03), reason: 'at $tempo BPM, bar 1 at ${a.firstDownbeat}');
      expect(a.barSeconds, closeTo(240 / tempo, 1e-9));
    }
  });
}
