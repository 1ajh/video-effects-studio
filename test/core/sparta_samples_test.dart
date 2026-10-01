import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/analysis.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/audio/dsp.dart';
import 'package:video_effects_studio/core/audio/psola.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sample_finder.dart';
import 'package:video_effects_studio/core/sparta/sample_processing.dart';

void main() {
  late List<SourceAnalysis> sources;
  late List<AudioBuffer> raw48;
  late SamplePicks picks;
  const roles = [SampleRole.pitch, SampleRole.kick, SampleRole.snare, SampleRole.hat];

  setUpAll(() {
    final paths = ['test/fixtures/speech_a.wav', 'test/fixtures/speech_b.wav'];
    sources = [
      for (var i = 0; i < paths.length; i++)
        SourceAnalysis.fromAudio(i, paths[i], AudioBuffer.fromWav(File(paths[i]).readAsBytesSync())),
    ];
    raw48 = [
      for (final s in sources) AudioBuffer(resample(s.audio.data, s.audio.sampleRate / 48000), sampleRate: 48000),
    ];
    picks = SampleFinder(sources).find();
  });

  ProcessedSample process(SampleCandidate c, {EnhanceOptions options = const EnhanceOptions(), int rootPc = 2}) =>
      SampleEnhancer(
        options: options,
        rootPc: rootPc,
      ).process(c, raw48[c.sourceIndex].slice(c.start, c.end), sources[c.sourceIndex].path);

  test('finds spoken lines split into words, and pitch / percussion candidates', () {
    expect(picks.lines, isNotEmpty);
    final line = picks.lines.first;
    expect(line.duration, greaterThan(0.4));
    expect(line.words, isNotEmpty);
    for (final w in line.words) {
      expect(w.start, greaterThanOrEqualTo(line.start - 1e-9));
      expect(w.end, lessThanOrEqualTo(line.end + 1e-9));
      expect(w.end, greaterThan(w.start));
    }
    for (var i = 0; i + 1 < line.words.length; i++) {
      expect(line.words[i].start, lessThan(line.words[i + 1].start));
    }
    // ignore: avoid_print
    print('line ${line.start.toStringAsFixed(2)}–${line.end.toStringAsFixed(2)} s, ${line.words.length} words');
    for (final role in roles) {
      expect(picks.of(role), isNotEmpty, reason: role.name);
      expect(picks.best(role)!.score, inInclusiveRange(0, 1));
    }
    expect(picks.best(SampleRole.pitch)!.f0, inInclusiveRange(70, 400));
  });

  test("the line's own vowels come first for the pitch sample", () {
    final line = picks.lines.first;
    final ranked = picks.pitchFor(line);
    final inside = ranked.where(
      (c) => c.sourceIndex == line.sourceIndex && c.start >= line.start - 0.05 && c.end <= line.end + 0.05,
    );
    if (inside.isNotEmpty) expect(ranked.indexOf(inside.first), lessThan(3));
  });

  test('distinct assignment gives roles different material', () {
    final chosen = picks.assignDistinct(line: picks.lines.first);
    expect(chosen.keys.toSet(), roles.toSet());
    final list = chosen.values.toList();
    var clashes = 0;
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i], b = list[j];
        if (a.sourceIndex == b.sourceIndex && a.start < b.end - 0.01 && b.start < a.end - 0.01) clashes++;
      }
    }
    expect(clashes, 0);
  });

  test('candidates never overlap within a role on the same source', () {
    for (final role in roles) {
      final list = picks.of(role);
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final a = list[i], b = list[j];
          if (a.sourceIndex != b.sourceIndex) continue;
          expect(a.start < b.end - 0.02 && b.start < a.end - 0.02, isFalse, reason: '$role $a $b');
        }
      }
    }
  });

  test("the pitch sample is hard-tuned flat to the base's root and sustains", () {
    final c = picks.best(SampleRole.pitch)!;
    for (final pc in [2, 3, 9]) {
      final p = process(c, rootPc: pc);
      expect(p.audio.length, greaterThanOrEqualTo(4 * 48000));
      final midi = 69 + 12 * math.log(p.rootHz / 440) / math.ln2;
      expect((midi - midi.round()).abs(), lessThan(0.01));
      expect(midi.round() % 12, pc);
      final track = trackPitch(p.audio.sublist(0, 48000), 48000)!;
      expect(12 * (math.log(track.medianHz / p.rootHz) / math.ln2).abs(), lessThan(0.4));
    }
  });

  test('natural tuning stays on the note but keeps more of the voice', () {
    final c = picks.best(SampleRole.pitch)!;
    final hard = process(c);
    final natural = process(c, options: const EnhanceOptions(tuning: PitchTuning.natural));
    expect(natural.rootHz, hard.rootHz);
    double spread(Float32List x) => centsSpread(trackPitch(x.sublist(0, 24000), 48000)!.hz.where((h) => h > 0));
    expect(spread(natural.audio), greaterThanOrEqualTo(spread(hard.audio) - 1));
  });

  test('a pitch candidate with no steady pitch is rejected, not used off-key', () {
    final rng = math.Random(1);
    final noise = AudioBuffer(
      Float32List.fromList([for (var i = 0; i < 24000; i++) rng.nextDouble() * 2 - 1]),
      sampleRate: 48000,
    );
    const c = SampleCandidate(role: SampleRole.pitch, sourceIndex: 0, start: 0, end: 0.5, score: 0.5);
    expect(() => SampleEnhancer().process(c, noise, 'noise'), throwsA(isA<UntunableSample>()));
  });

  test('every sample processes into a normalized, non-silent sample', () {
    final line = picks.lines.first;
    final all = [for (final role in roles) picks.best(role)!, line.quote, ...line.wordCandidates];
    for (final c in all) {
      final p = process(c);
      final peak = p.audio.fold<double>(0, (m, v) => math.max(m, v.abs()));
      expect(peak, inInclusiveRange(0.3, 1.0), reason: '${c.role.name} ${c.slot}');
      if (c.role == SampleRole.word) {
        expect(p.slot, c.slot);
        expect(p.rootHz, 0, reason: 'words play raw (not tuned)');
      }
    }
  });

  test('nothing is added to the percussion unless the synth drum body is on', () {
    expect(const EnhanceOptions().layerDrums, isFalse);
    final silence = AudioBuffer(Float32List(48000 ~/ 2), sampleRate: 48000);
    for (final role in const [SampleRole.kick, SampleRole.snare, SampleRole.hat]) {
      final c = SampleCandidate(role: role, sourceIndex: 0, start: 0, end: 0.5, score: 0.5);
      final plain = SampleEnhancer().process(c, silence, 'x');
      expect(plain.audio.fold<double>(0, (m, v) => math.max(m, v.abs())), 0, reason: role.name);
      final layered = SampleEnhancer(options: const EnhanceOptions(layerDrums: true)).process(c, silence, 'x');
      expect(layered.audio.fold<double>(0, (m, v) => math.max(m, v.abs())), greaterThan(0.1), reason: role.name);
    }
  });

  test('chorus crisp shortens and doubles the attack', () {
    final x = AudioBuffer(
      resample(sources[0].audio.data, sources[0].audio.sampleRate / 48000),
      sampleRate: 48000,
    ).slice(0.2, 0.5).data;
    final y = SampleEnhancer.chorusCrisp(x, 48000);
    expect(y.length, lessThan(x.length));
    expect(y.length, greaterThan(x.length - 48000 * 0.04));
  });
}
