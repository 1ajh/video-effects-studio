import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/audio/dsp.dart';
import 'package:video_effects_studio/core/audio/psola.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sample_finder.dart';
import 'package:video_effects_studio/core/sparta/sample_processing.dart';

void main() {
  late List<SourceAnalysis> sources;
  late List<AudioBuffer> raw48;

  setUpAll(() {
    final paths = ['test/fixtures/speech_a.wav', 'test/fixtures/speech_b.wav'];
    sources = [
      for (var i = 0; i < paths.length; i++)
        SourceAnalysis.fromAudio(i, paths[i], AudioBuffer.fromWav(File(paths[i]).readAsBytesSync())),
    ];
    raw48 = [
      for (final s in sources) AudioBuffer(resample(s.audio.data, s.audio.sampleRate / 48000), sampleRate: 48000),
    ];
  });

  test('finds candidates for every role across sources', () {
    final picks = SampleFinder(sources).find();
    for (final role in SampleRole.values) {
      expect(picks.of(role), isNotEmpty, reason: role.name);
      final best = picks.best(role)!;
      expect(best.score, inInclusiveRange(0, 1));
      expect(best.end, greaterThan(best.start));
      // ignore: avoid_print
      print(
        '${role.name.padRight(6)} src${best.sourceIndex} ${best.start.toStringAsFixed(2)}–${best.end.toStringAsFixed(2)}s '
        'score ${best.score.toStringAsFixed(2)} f0 ${best.f0.toStringAsFixed(0)} ${best.details.map((k, v) => MapEntry(k, v.toStringAsFixed(2)))}',
      );
    }
    expect(picks.best(SampleRole.pitch)!.f0, inInclusiveRange(70, 400));
    expect(picks.best(SampleRole.quote)!.duration, greaterThan(0.5));
  });

  test('distinct assignment gives roles different material', () {
    final chosen = SampleFinder(sources).find().assignDistinct();
    expect(chosen.keys.toSet(), SampleRole.values.toSet());
    final nonQuote = chosen.entries.where((e) => e.key != SampleRole.quote).map((e) => e.value).toList();
    var clashes = 0;
    for (var i = 0; i < nonQuote.length; i++) {
      for (var j = i + 1; j < nonQuote.length; j++) {
        final a = nonQuote[i], b = nonQuote[j];
        if (a.sourceIndex == b.sourceIndex && a.start < b.end - 0.01 && b.start < a.end - 0.01) clashes++;
      }
    }
    expect(clashes, 0);
  });

  test('candidates never overlap within a role on the same source', () {
    final picks = SampleFinder(sources).find();
    for (final role in SampleRole.values) {
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

  test('enhanced pitch sample is tuned to D and sustains', () {
    final picks = SampleFinder(sources).find();
    final c = picks.best(SampleRole.pitch)!;
    final src = raw48[c.sourceIndex].slice(c.start, c.end);
    final p = SampleEnhancer().process(c, src, sources[c.sourceIndex].path);
    expect(p.audio.length, greaterThanOrEqualTo(4 * 48000));
    const ds = [73.42, 146.83, 293.66, 587.33];
    expect(ds.any((d) => (p.rootHz - d).abs() < 0.5), isTrue, reason: '${p.rootHz}');
    final track = trackPitch(p.audio.sublist(0, 48000), 48000)!;
    expect(12 * (math.log(track.medianHz / p.rootHz) / math.ln2).abs(), lessThan(0.4));
  });

  test('every role processes into a normalized, non-silent sample', () {
    final picks = SampleFinder(sources).find();
    for (final role in SampleRole.values) {
      final c = picks.best(role)!;
      final src = raw48[c.sourceIndex].slice(c.start, c.end);
      final p = SampleEnhancer().process(c, src, sources[c.sourceIndex].path);
      final peak = p.audio.fold<double>(0, (m, v) => math.max(m, v.abs()));
      expect(peak, inInclusiveRange(0.3, 1.0), reason: role.name);
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
