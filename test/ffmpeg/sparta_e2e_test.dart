@Tags(['ffmpeg'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:video_effects_studio/core/ffmpeg/ffmpeg_toolkit.dart';
import 'package:video_effects_studio/core/models/output_settings.dart';
import 'package:video_effects_studio/core/render/render_engine.dart';
import 'package:video_effects_studio/core/sparta/arranger.dart';
import 'package:video_effects_studio/core/sparta/base_library.dart';
import 'package:video_effects_studio/core/sparta/charter.dart';
import 'package:video_effects_studio/core/sparta/midi.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sample_processing.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';
import 'package:video_effects_studio/core/sparta/visual_renderer.dart';

/// A 12-bar D base at 140 BPM: intro, chorus, epicness.
BaseTranscription _transcription() => BaseTranscription(
  bpm: 140,
  rootKey: 62,
  lengthBeats: 48,
  sections: const [
    Section(SectionKind.intro, 0, 8),
    Section(SectionKind.chorus, 8, 24),
    Section(SectionKind.epicness, 24, 48),
  ],
  hits: [
    for (var b = 0.0; b < 48; b += 1) GuideNote(b, 0.75, const [0, 0, 1, 1, -2, -2, 1, 1][b.toInt() % 8]),
  ],
  kick: [for (var b = 8.0; b < 48; b += 1) b],
  snare: [for (var b = 9.0; b < 48; b += 2) b],
  hat: [for (var b = 8.5; b < 48; b += 1) b],
);

/// Full Sparta pipeline against a real FFmpeg: sources → line, words and
/// samples → base → mix → video, for every visual style and every kind of
/// base.
void main() {
  FfmpegToolkit? kit;
  late SpartaEngine engine;
  late RenderEngine probe;
  late Directory tmp;
  late String videoSource;
  late String midiPath;
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
    midiPath = p.join(tmp.path, 'base.mid');
    await File(midiPath).writeAsBytes(MidiFile.fromTranscription(_transcription()).encode());

    final sources = [await engine.analyzeSource(0, videoSource), await engine.analyzeSource(1, audioSource)];
    final paths = [videoSource, audioSource];
    final found = await engine.findSamples(sources);
    final line = found.lines.first;
    Future<ProcessedSample> cut(SampleCandidate c) => engine.prepareSample(c, paths[c.sourceIndex], rootPc: 2);
    samples = {
      for (final e in found.assignDistinct(line: line).entries) e.key: [await cut(e.value)],
      SampleRole.word: [for (final c in line.wordCandidates) await cut(c)],
      SampleRole.quote: [await cut(line.quote)],
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

  test('project base → remix video in every style and option', () async {
    if (kit == null) return markTestSkipped('ffmpeg not found');
    final prepared = await engine.prepareBase(ProjectBaseSource(projectPath: midiPath));
    expect(prepared.transcription.bpm, closeTo(140, 0.01));
    final base = prepared.withChart(Charter().write(prepared.transcription));
    final mix = await engine.mix(base, samples, const MixSettings());
    for (final role in SampleRole.values) {
      expect(mix.events.where((e) => e.role == role), isNotEmpty, reason: role.name);
    }
    final looks = [
      const VisualOptions(),
      const VisualOptions(grid: GridSize.two, flip: FlipMode.both, idle: IdleBox.dimmed, intro: IntroVisual.box),
      const VisualOptions(style: VisualStyle.modern, idle: IdleBox.hold, intro: IntroVisual.titleCard),
      const VisualOptions(style: VisualStyle.chaos, grid: GridSize.four, flip: FlipMode.pitchOnly),
      const VisualOptions(style: VisualStyle.minimal, flip: FlipMode.none),
    ];
    for (var i = 0; i < looks.length; i++) {
      final look = looks[i];
      final sw = Stopwatch()..start();
      final out = await engine.export(
        base: base,
        mix: mix,
        samples: samples,
        sourceHasVideo: {videoSource: true, audioSource: false},
        outDir: p.join(tmp.path, 'out'),
        name: 'remix $i ${look.style.name}',
        visuals: look,
        title: 'Speaker\nSparta Remix',
        fontPath: 'assets/fonts/Inter-Bold.ttf',
        stems: i == 0,
        midi: i == 0,
        output: const OutputSettings(quality: OutputQuality.small, resolution: ResolutionCap.p480),
      );
      // ignore: avoid_print
      print('${look.toJson()}: ${mix.duration.toStringAsFixed(1)}s remix rendered in ${sw.elapsedMilliseconds} ms');
      await expectPlayable(out.output, mix.duration);
      if (i == 0) {
        expect(out.stems.keys.toSet(), Stem.values.toSet());
        expect(out.midi, hasLength(2));
        final chart = MidiFile.parse(File(out.midi.first).readAsBytesSync());
        expect(chart.tracks.map((t) => t.name), contains('Pitch sample'));
      }
    }
    // Scratch space is cleaned up after every export.
    final leftovers = Directory(p.join(tmp.path, 'cache', 'sparta')).listSync().whereType<Directory>();
    expect(leftovers.where((d) => p.basename(d.path).startsWith('render_')), isEmpty);
  });

  test('audio base is transcribed; a project lines up with its audio; a library base uses its checked notes', () async {
    if (kit == null) return markTestSkipped('ffmpeg not found');
    final fromMidi = await engine.prepareBase(ProjectBaseSource(projectPath: midiPath));
    final wav = p.join(tmp.path, 'base.wav');
    await fromMidi.audio.writeWav(wav);
    final padded = p.join(tmp.path, 'padded.wav');
    final r = await Process.run(kit!.ffmpegPath, [
      '-hide_banner', '-loglevel', 'error', '-y', '-i', wav, '-af', 'adelay=800:all=1', padded, //
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');

    final fromAudio = await engine.prepareBase(AudioBaseSource(audioPath: padded));
    expect(fromAudio.transcription.bpm, closeTo(140, 0.5));
    expect(fromAudio.transcription.audioOffset, closeTo(0.8, 0.03));
    expect(fromAudio.transcription.source, TranscriptionSource.audio);
    expect(fromAudio.transcription.kick, isNotEmpty);

    final aligned = await engine.prepareBase(ProjectBaseSource(projectPath: midiPath, audioPath: padded));
    expect(aligned.transcription.audioOffset, closeTo(0.8, 0.03));

    // A catalog base with a checked transcription: downloaded, and its notes used as they are.
    final checked = _transcription().copyWith(audioOffset: 0.8, source: TranscriptionSource.curated, credit: 'Tester');
    final audioBytes = File(padded).readAsBytesSync();
    final client = MockClient.streaming((request, _) async {
      final url = request.url.toString();
      if (url.endsWith('base.wav')) return http.StreamedResponse(Stream.value(audioBytes), 200);
      if (url.endsWith('t.json')) return http.StreamedResponse(Stream.value(checked.encode().codeUnits), 200);
      return http.StreamedResponse(const Stream.empty(), 404);
    });
    final online = SpartaEngine(
      ffmpegPath: kit!.ffmpegPath,
      cacheDir: p.join(tmp.path, 'cache2'),
      library: BaseLibrary(cacheDir: p.join(tmp.path, 'cache2'), client: client),
    );
    const entry = CatalogBase(
      id: 'test/base',
      name: 'Test Base',
      maker: 'Someone',
      audioUrl: 'https://example.org/base.wav',
      transcriptionPath: 'transcriptions/t.json',
    );
    final progress = <double>[];
    final lib = await online.prepareBase(
      const LibraryBaseSource(entry),
      onStatus: (_, f) => f == null ? null : progress.add(f),
    );
    expect(progress, isNotEmpty);
    expect(lib.transcription.credit, 'Tester');
    expect(lib.transcription.hits, checked.hits);
    expect(lib.transcription.catalogId, 'test/base');
    expect(lib.base.author, 'Someone');
    expect(lib.transcription.audioSha1, await BaseLibrary.sha1Of(padded));
  });
}
