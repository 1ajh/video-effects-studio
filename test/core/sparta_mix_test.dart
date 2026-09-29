import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/audio/dsp.dart';
import 'package:video_effects_studio/core/audio/psola.dart';
import 'package:video_effects_studio/core/sparta/arranger.dart';
import 'package:video_effects_studio/core/sparta/base_renderer.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sample_finder.dart';
import 'package:video_effects_studio/core/sparta/sample_processing.dart';

void main() {
  late Map<SampleRole, List<ProcessedSample>> samples;
  late Composition comp;
  late AudioBuffer baseAudio;

  setUpAll(() {
    final paths = ['test/fixtures/speech_a.wav', 'test/fixtures/speech_b.wav'];
    final sources = [
      for (var i = 0; i < paths.length; i++)
        SourceAnalysis.fromAudio(i, paths[i], AudioBuffer.fromWav(File(paths[i]).readAsBytesSync())),
    ];
    final raw = [
      for (final s in sources) AudioBuffer(resample(s.audio.data, s.audio.sampleRate / 48000), sampleRate: 48000),
    ];
    final chosen = SampleFinder(sources).find().assignDistinct();
    final enhancer = SampleEnhancer();
    samples = {
      for (final e in chosen.entries)
        e.key: [
          enhancer.process(
            e.value,
            raw[e.value.sourceIndex].slice(e.value.start, e.value.end),
            paths[e.value.sourceIndex],
          ),
        ],
    };
    comp = Composer(seed: 1).compose(
      defaultPlan(length: RemixLength.short, enabled: {SectionKind.intro, SectionKind.chorus, SectionKind.madness}),
    );
    baseAudio = BaseRenderer().render(comp);
  });

  test('schedules every chart note with sampler transposition and choke', () {
    final arranger = Arranger(base: comp.base, samples: samples, baseAudio: baseAudio);
    final events = arranger.schedule();
    expect(events, isNotEmpty);
    for (final role in SampleRole.values) {
      expect(events.where((e) => e.role == role), isNotEmpty, reason: role.name);
    }
    for (final e in events) {
      expect(e.rate, closeTo(math.pow(2, e.semitone / 12), 1e-9));
      expect(e.duration, greaterThan(0));
    }
    // Pitch hits never overlap the next pitch hit on a later beat.
    final pitch = events.where((e) => e.role == SampleRole.pitch).toList();
    for (var i = 0; i + 1 < pitch.length; i++) {
      if (pitch[i + 1].beat > pitch[i].beat) expect(pitch[i].end, lessThanOrEqualTo(pitch[i + 1].start + 1e-9));
    }
  });

  test('clean master hits loudness and ceiling; hot is louder', () {
    final sw = Stopwatch()..start();
    final clean = Arranger(base: comp.base, samples: samples, baseAudio: baseAudio).mix();
    // ignore: avoid_print
    print(
      'mixed ${clean.duration.toStringAsFixed(1)}s in ${sw.elapsedMilliseconds} ms; '
      'clean ${clean.lufs.toStringAsFixed(1)} LUFS peak ${clean.peakDb.toStringAsFixed(2)} dB',
    );
    expect(clean.duration, greaterThanOrEqualTo(comp.base.durationSeconds - 0.01));
    expect(clean.peakDb, lessThanOrEqualTo(-0.99));
    expect(clean.lufs, inInclusiveRange(-12.0, -8.0));
    final hot = Arranger(
      base: comp.base,
      samples: samples,
      baseAudio: baseAudio,
      settings: const MixSettings(master: MasterMode.hot),
    ).mix(stems: false);
    // ignore: avoid_print
    print('hot ${hot.lufs.toStringAsFixed(1)} LUFS peak ${hot.peakDb.toStringAsFixed(2)} dB');
    expect(hot.lufs, greaterThan(clean.lufs + 1));
    expect(hot.peakDb, lessThanOrEqualTo(-0.09));
    expect(hot.stems, isEmpty);
    expect(clean.stems.keys.toSet(), Stem.values.toSet());
  });

  test('pitch stem plays the charted notes in tune', () {
    final mix = Arranger(base: comp.base, samples: samples, baseAudio: baseAudio).mix();
    final stem = mix.stems[Stem.pitch]!.mono();
    final root = samples[SampleRole.pitch]!.first.rootHz;
    var checked = 0, inTune = 0;
    for (final e in mix.events.where((e) => e.role == SampleRole.pitch && e.duration >= 0.2)) {
      // Skip chords: another pitch hit at the same beat.
      if (mix.events.where((o) => o.role == SampleRole.pitch && o.beat == e.beat).length > 1) continue;
      final a = ((e.start + 0.04) * 48000).round();
      final b = math.min(stem.frames, a + (0.14 * 48000).round());
      final track = trackPitch(stem.data.sublist(a, b), 48000);
      if (track == null) continue;
      checked++;
      final expected = root * e.rate;
      final cents = 1200 * (math.log(track.medianHz / expected) / math.ln2);
      // Octave errors in the tracker are not tuning errors.
      final folded = ((cents % 1200) + 1200) % 1200;
      if (math.min(folded, 1200 - folded) < 40) inTune++;
    }
    expect(checked, greaterThan(5));
    expect(inTune / checked, greaterThan(0.8), reason: '$inTune / $checked');
  });

  test('base dips under the quote', () {
    final mix = Arranger(base: comp.base, samples: samples, baseAudio: baseAudio).mix();
    final q = mix.events.firstWhere((e) => e.role == SampleRole.quote);
    final raw = baseAudio.slice(q.start + 0.1, q.start + math.min(q.duration, 1.0)).rms();
    final ducked = mix.stems[Stem.base]!.slice(q.start + 0.1, q.start + math.min(q.duration, 1.0)).rms() / 0.8;
    expect(gainToDb(ducked) - gainToDb(raw), lessThan(-1.5));
  });
}
