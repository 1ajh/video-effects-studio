@Tags(['ffmpeg'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_effects_studio/core/ffmpeg/ffmpeg_toolkit.dart';
import 'package:video_effects_studio/core/models/output_settings.dart';
import 'package:video_effects_studio/core/render/render_engine.dart';
import 'package:video_effects_studio/core/sparta/arranger.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/midi.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sample_processing.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';
import 'package:video_effects_studio/core/sparta/visual_renderer.dart';

/// Full Sparta pipeline against a real FFmpeg: sources → samples → base →
/// mix → video, for every visual preset and every kind of base.
void main() {
  FfmpegToolkit? kit;
  late SpartaEngine engine;
  late RenderEngine probe;
  late Directory tmp;
  late String videoSource;
  const audioSource = 'test/fixtures/speech_b.wav';
  late Map<SampleRole, List<ProcessedSample>> samples;

  setUpAll(() async {
    kit = await FfmpegToolkit.locate();
    if (kit == null) return;
    tmp = await Directory.systemTemp.createTemp('sparta_e2e_');
    engine = SpartaEngine(ffmpegPath: kit!.ffmpegPath, cacheDir: p.join(tmp.path, 'cache'));
    probe = RenderEngine(kit!);
    videoSource = p.join(tmp.path, 'speaker.mp4');
    final r = await Process.run(kit!.ffmpegPath, [
      '-hide_banner', '-loglevel', 'error', '-y', //
      '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30',
      '-i', 'test/fixtures/speech_a.wav',
      '-shortest', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', videoSource,
    ]);
    if (r.exitCode != 0) throw StateError('fixture failed: ${r.stderr}');

    final sources = [await engine.analyzeSource(0, videoSource), await engine.analyzeSource(1, audioSource)];
    final chosen = (await engine.findSamples(sources)).assignDistinct();
    samples = {
      for (final e in chosen.entries) e.key: [await engine.prepareSample(e.value, sources[e.value.sourceIndex].path)],
    };
  });

  tearDownAll(() async {
    if (kit != null) await tmp.delete(recursive: true);
  });

  Future<void> expectPlayable(String path, double seconds, {bool video = true}) async {
    final info = await probe.probe(path);
    expect(info.hasAudio, isTrue);
    expect(info.hasVideo, video);
    expect(info.duration, closeTo(seconds, 0.35));
  }

  test('built-in base → full remix video in every preset', () async {
    if (kit == null) return markTestSkipped('ffmpeg not found');
    final base = await engine.prepareBase(
      const BuiltInBaseSource(
        length: RemixLength.short,
        sections: {SectionKind.intro, SectionKind.chorus, SectionKind.dundundenden, SectionKind.madness},
      ),
    );
    final mix = await engine.mix(base, samples, const MixSettings());
    expect(mix.events, isNotEmpty);
    for (final preset in VisualPreset.values) {
      final sw = Stopwatch()..start();
      final out = await engine.export(
        base: base,
        mix: mix,
        samples: samples,
        sourceHasVideo: {videoSource: true, audioSource: false},
        outDir: p.join(tmp.path, 'out'),
        name: 'remix ${preset.name}',
        preset: preset,
        stems: preset == VisualPreset.classic,
        midi: preset == VisualPreset.classic,
        output: const OutputSettings(quality: OutputQuality.small, resolution: ResolutionCap.p480),
      );
      // ignore: avoid_print
      print('${preset.name}: ${mix.duration.toStringAsFixed(1)}s remix rendered in ${sw.elapsedMilliseconds} ms');
      await expectPlayable(out.output, mix.duration);
      if (preset == VisualPreset.classic) {
        expect(out.stems.keys.toSet(), Stem.values.toSet());
        for (final s in out.stems.values) {
          expect(File(s).existsSync(), isTrue);
        }
        expect(out.midi, hasLength(2));
        final chart = MidiFile.parse(File(out.midi.first).readAsBytesSync());
        expect(chart.tracks.map((t) => t.name), contains('Pitch sample'));
      }
    }
    // Scratch space is cleaned up after every export.
    final leftovers = Directory(p.join(tmp.path, 'cache', 'sparta')).listSync().whereType<Directory>();
    expect(leftovers, isEmpty);
  });

  test('MIDI project without audio is re-synthesized; audio-only base is analysed', () async {
    if (kit == null) return markTestSkipped('ffmpeg not found');
    final comp = Composer(
      style: BaseStyle.venom,
      seed: 3,
    ).compose(defaultPlan(length: RemixLength.short, enabled: {SectionKind.chorus, SectionKind.awesomeness}));
    final midiPath = p.join(tmp.path, 'venom.mid');
    await File(midiPath).writeAsBytes(MidiFile.fromScore(comp).encode());
    final fromMidi = await engine.prepareBase(ProjectBaseSource(projectPath: midiPath));
    expect(fromMidi.base.bpm, closeTo(150, 0.01));
    expect(fromMidi.audio.duration, closeTo(fromMidi.base.durationSeconds, 0.05));
    final mix = await engine.mix(fromMidi, samples, const MixSettings(master: MasterMode.hot));
    final out = await engine.export(
      base: fromMidi,
      mix: mix,
      samples: samples,
      sourceHasVideo: {videoSource: true, audioSource: false},
      outDir: p.join(tmp.path, 'out'),
      name: 'from midi',
      output: const OutputSettings(format: OutputFormat.mp3),
    );
    await expectPlayable(out.output, mix.duration, video: false);

    // The re-synthesized base as a plain audio file, with 0.8 s of lead-in.
    final wav = p.join(tmp.path, 'base.wav');
    await fromMidi.audio.writeWav(wav);
    final padded = p.join(tmp.path, 'padded.wav');
    final r = await Process.run(kit!.ffmpegPath, [
      '-hide_banner', '-loglevel', 'error', '-y', '-i', wav, '-af', 'adelay=800:all=1', padded, //
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final fromAudio = await engine.prepareBase(const AudioBaseSource(audioPath: 'PLACEHOLDER').copyWithPath(padded));
    expect(fromAudio.analysis!.bpm, closeTo(150, 0.5));
    expect(fromAudio.base.audioOffset, closeTo(0.8, 0.03));

    // And the MIDI chart aligned to that audio automatically.
    final aligned = await engine.prepareBase(ProjectBaseSource(projectPath: midiPath, audioPath: padded));
    expect(aligned.base.audioOffset, closeTo(0.8, 0.03));
  });
}

extension on AudioBaseSource {
  AudioBaseSource copyWithPath(String path) =>
      AudioBaseSource(audioPath: path, bpm: bpm, transpose: transpose, style: style, seed: seed);
}
