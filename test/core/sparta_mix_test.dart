import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/audio/dsp.dart';
import 'package:video_effects_studio/core/audio/psola.dart';
import 'package:video_effects_studio/core/sparta/arranger.dart';
import 'package:video_effects_studio/core/sparta/base.dart';
import 'package:video_effects_studio/core/sparta/base_renderer.dart';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/charter.dart';
import 'package:video_effects_studio/core/sparta/midi.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sample_finder.dart';
import 'package:video_effects_studio/core/sparta/sample_processing.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

/// A 16-bar D# base: intro, chorus, epicness.
BaseTranscription _transcription() => BaseTranscription(
  bpm: 140,
  rootKey: 63,
  lengthBeats: 64,
  sections: const [
    Section(SectionKind.intro, 0, 16),
    Section(SectionKind.chorus, 16, 48),
    Section(SectionKind.epicness, 48, 64),
  ],
  hits: [
    for (var b = 0.0; b < 64; b += 1) GuideNote(b, 0.75, const [0, 0, 1, 1, -2, -2, 1, 1][b.toInt() % 8]),
  ],
  kick: [for (var b = 16.0; b < 64; b += 1) b],
  snare: [for (var b = 17.0; b < 64; b += 2) b],
  hat: [for (var b = 16.5; b < 64; b += 1) b],
);

void main() {
  late Map<SampleRole, List<ProcessedSample>> samples;
  late SpartaBase base;
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
    final found = SampleFinder(sources).find();
    final line = found.lines.first;
    final t = _transcription();
    final enhancer = SampleEnhancer(rootPc: t.rootPitchClass);
    ProcessedSample cut(SampleCandidate c) =>
        enhancer.process(c, raw[c.sourceIndex].slice(c.start, c.end), paths[c.sourceIndex]);
    samples = {
      for (final e in found.assignDistinct(line: line).entries) e.key: [cut(e.value)],
      SampleRole.word: [for (final c in line.wordCandidates) cut(c)],
      SampleRole.quote: [cut(line.quote)],
    };
    base = SpartaBase(id: 't', name: 'Test', kind: BaseKind.audio, transcription: t, chart: Charter().write(t));
    final src = MidiFile.parse(MidiFile.fromTranscription(t).encode()).toChartSource('t', 't.mid');
    baseAudio = BaseRenderer().render(resynthesize(src));
  });

  test('schedules every chart note with sampler transposition and choke', () {
    final events = Arranger(base: base, samples: samples, baseAudio: baseAudio).schedule();
    for (final role in SampleRole.values) {
      expect(events.where((e) => e.role == role), isNotEmpty, reason: role.name);
    }
    for (final e in events) {
      expect(e.rate, closeTo(math.pow(2, e.semitone / 12), 1e-9));
      expect(e.duration, greaterThan(0));
    }
    // A hit is cut by the next hit on its lane.
    for (final role in const [SampleRole.pitch, SampleRole.word]) {
      final lane = events.where((e) => e.role == role).toList();
      for (var i = 0; i + 1 < lane.length; i++) {
        if (lane[i + 1].beat > lane[i].beat) expect(lane[i].end, lessThanOrEqualTo(lane[i + 1].start + 1e-9));
      }
    }
    // The chorus is words only.
    final chorus = base.sections[1];
    expect(events.where((e) => e.role == SampleRole.pitch && chorus.contains(e.beat)), isEmpty);
    expect(events.where((e) => e.role == SampleRole.word && chorus.contains(e.beat)), isNotEmpty);
  });

  test("word hits play their slot's word", () {
    final events = Arranger(base: base, samples: samples, baseAudio: baseAudio).schedule();
    final keys = [for (final s in samples[SampleRole.word]!) s.slot];
    final notes = base.lane(SampleRole.word);
    final hits = events.where((e) => e.role == SampleRole.word).toList();
    expect(hits.length, notes.length);
    // Layered patterns (the epicness) play two words at once: compare per beat.
    String key(double beat, String slot) => '${beat.toStringAsFixed(4)}:$slot';
    expect(
      (hits.map((h) => key(h.beat, h.slot)).toList()..sort()),
      (notes.map((n) => key(n.beat, wordKeyFor(n.slot, keys)!)).toList()..sort()),
    );
    for (final h in hits) {
      expect(samples[SampleRole.word]![h.variant].slot, h.slot);
      expect(h.rate, 1, reason: 'words play raw');
    }
  });

  test('clean master is loud and consistent; hot is louder', () {
    final clean = Arranger(base: base, samples: samples, baseAudio: baseAudio).mix();
    // ignore: avoid_print
    print('clean ${clean.lufs.toStringAsFixed(1)} LUFS peak ${clean.peakDb.toStringAsFixed(2)} dB');
    expect(clean.duration, greaterThanOrEqualTo(base.durationSeconds - 0.01));
    expect(clean.peakDb, lessThanOrEqualTo(-0.99));
    expect(clean.lufs, inInclusiveRange(-12.0, -8.0));
    final hot = Arranger(
      base: base,
      samples: samples,
      baseAudio: baseAudio,
      settings: const MixSettings(master: MasterMode.hot),
    ).mix(stems: false);
    expect(hot.lufs, greaterThan(clean.lufs + 1));
    expect(hot.peakDb, lessThanOrEqualTo(-0.09));
    expect(hot.stems, isEmpty);
    expect(clean.stems.keys.toSet(), Stem.values.toSet());
  });

  test("the pitch stem plays the base's hits in its key", () {
    final mix = Arranger(base: base, samples: samples, baseAudio: baseAudio).mix();
    final stem = mix.stems[Stem.pitch]!.mono();
    final root = samples[SampleRole.pitch]!.first.rootHz;
    // Tuned to D#.
    expect((69 + 12 * math.log(root / 440) / math.ln2).round() % 12, 3);
    var checked = 0, inTune = 0;
    for (final e in mix.events.where((e) => e.role == SampleRole.pitch && e.duration >= 0.2)) {
      final a = ((e.start + 0.04) * 48000).round();
      final b = math.min(stem.frames, a + (0.14 * 48000).round());
      final track = trackPitch(stem.data.sublist(a, b), 48000);
      if (track == null) continue;
      checked++;
      final cents = 1200 * (math.log(track.medianHz / (root * e.rate)) / math.ln2);
      final folded = ((cents % 1200) + 1200) % 1200;
      if (math.min(folded, 1200 - folded) < 40) inTune++;
    }
    expect(checked, greaterThan(5));
    expect(inTune / checked, greaterThan(0.8), reason: '$inTune / $checked');
  });

  test('the base dips under the quote', () {
    final mix = Arranger(base: base, samples: samples, baseAudio: baseAudio).mix();
    final q = mix.events.firstWhere((e) => e.role == SampleRole.quote);
    final raw = baseAudio.slice(q.start + 0.1, q.start + math.min(q.duration, 1.0)).rms();
    final ducked = mix.stems[Stem.base]!.slice(q.start + 0.1, q.start + math.min(q.duration, 1.0)).rms() / 0.8;
    expect(gainToDb(ducked) - gainToDb(raw), lessThan(-1.5));
  });

  test('random mode can vary which sample plays per section', () {
    final two = {
      ...samples,
      SampleRole.kick: [samples[SampleRole.kick]!.first, samples[SampleRole.snare]!.first],
    };
    final fixed = Arranger(base: base, samples: two).schedule();
    final shuffled = Arranger(base: base, samples: two, shuffleSamples: true, seed: 3).schedule();
    expect(
      fixed.where((e) => e.role == SampleRole.kick).length,
      shuffled.where((e) => e.role == SampleRole.kick).length,
    );
  });
}
