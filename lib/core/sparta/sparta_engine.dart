import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../audio/audio_buffer.dart';
import '../ffmpeg/ffmpeg_runner.dart';
import '../models/output_settings.dart';
import 'arranger.dart';
import 'audio_base.dart';
import 'audio_transcriber.dart';
import 'base.dart';
import 'base_library.dart';
import 'base_renderer.dart';
import 'chart_import.dart';
import 'flm.dart';
import 'flp.dart';
import 'midi.dart';
import 'model.dart';
import 'project_transcriber.dart';
import 'sample_finder.dart';
import 'sample_processing.dart';
import 'transcription.dart';
import 'visual_renderer.dart';

/// Where the base comes from.
sealed class BaseSource {
  const BaseSource();

  /// Stable id (saved fixes and settings are kept under it).
  String get key;
  String get name;
}

/// A real base from the catalog, downloaded on first use.
class LibraryBaseSource extends BaseSource {
  const LibraryBaseSource(this.base);
  final CatalogBase base;

  @override
  String get key => 'catalog:${base.id}';
  @override
  String get name => base.name;
}

/// An FL Studio (.flp), FL Studio Mobile (.flm) or MIDI project, with its
/// rendered audio when there is one (else the project is re-synthesized).
class ProjectBaseSource extends BaseSource {
  const ProjectBaseSource({required this.projectPath, this.audioPath, this.uses = const {}, this.audioOffset});

  final String projectPath;
  final String? audioPath;

  /// Which tracks are the hit / lead (by track id).
  final Map<String, TrackUse> uses;

  /// Seconds into the audio where beat 0 lands (null: detect).
  final double? audioOffset;

  @override
  String get key => 'file:$projectPath';
  @override
  String get name => p.basenameWithoutExtension(projectPath);
}

/// A base you only have as audio: everything is transcribed from it.
class AudioBaseSource extends BaseSource {
  const AudioBaseSource({required this.audioPath, this.bpm});
  final String audioPath;

  /// Tempo to use instead of detecting it.
  final double? bpm;

  @override
  String get key => 'file:$audioPath';
  @override
  String get name => p.basenameWithoutExtension(audioPath);
}

/// A base ready to chart and mix: what it plays (the transcription) and its
/// stereo 48 kHz audio.
class PreparedBase {
  PreparedBase({required this.base, required this.audio, required this.auto, this.project, this.analysis});

  /// The base (its chart is written by the controller).
  final SpartaBase base;
  final AudioBuffer audio;

  /// The automatic transcription, before any fixes.
  final BaseTranscription auto;
  final ChartSource? project;
  final AudioBaseAnalysis? analysis;

  BaseTranscription get transcription => base.transcription;

  PreparedBase withTranscription(BaseTranscription t) => PreparedBase(
    base: base.copyWith(transcription: t),
    audio: audio,
    auto: auto,
    project: project,
    analysis: analysis,
  );

  PreparedBase withChart(List<ChartNote> chart) => PreparedBase(
    base: base.copyWith(chart: chart),
    audio: audio,
    auto: auto,
    project: project,
    analysis: analysis,
  );
}

/// Files written for a finished remix.
class RemixOutputs {
  RemixOutputs({required this.output, this.stems = const {}, this.midi = const []});

  /// The remix in the chosen format (video, or audio for MP3/WAV).
  final String output;
  final Map<Stem, String> stems;
  final List<String> midi;
}

/// Orchestrates the Sparta pipeline: bases, sources and samples, mixing and
/// export. Heavy DSP runs in background isolates.
class SpartaEngine {
  SpartaEngine({
    required this.ffmpegPath,
    required this.cacheDir,
    BaseLibrary? library,
    this.bundledCatalog = '{"version":1,"bases":[]}',
    this.bundledFile,
  }) : library = library ?? BaseLibrary(cacheDir: p.join(cacheDir, 'sparta'));

  final String ffmpegPath;
  final String cacheDir;
  final BaseLibrary library;

  /// The catalog shipped with the app (bases/catalog.json).
  final String bundledCatalog;

  /// Reads a file shipped with the app from bases/ (checked transcriptions),
  /// null when it isn't there.
  final Future<String?> Function(String path)? bundledFile;

  static const projectExtensions = {'.flp', '.flm', '.mid', '.midi'};

  // --- sources & samples ------------------------------------------------------

  Future<SourceAnalysis> analyzeSource(int index, String path) async {
    final audio = await AudioBuffer.decode(ffmpegPath, path, sampleRate: SourceAnalysis.analysisRate, duration: 360);
    if (audio.frames < SourceAnalysis.analysisRate ~/ 4) {
      throw FfmpegException('${p.basename(path)} has no usable audio.');
    }
    return Isolate.run(() => SourceAnalysis.fromAudio(index, path, audio));
  }

  Future<SamplePicks> findSamples(List<SourceAnalysis> sources) =>
      Isolate.run(() => SampleFinder(sources).find(keep: 10));

  /// Cuts [c] from its source at full quality and makes it Sparta-ready
  /// (pitch samples are tuned to [rootPc]).
  Future<ProcessedSample> prepareSample(
    SampleCandidate c,
    String path, {
    EnhanceOptions options = const EnhanceOptions(),
    int rootPc = 2,
  }) async {
    const pad = 0.01;
    final raw = await AudioBuffer.decode(
      ffmpegPath,
      path,
      sampleRate: ProcessedSample.sampleRate,
      start: math.max(0, c.start - pad),
      duration: c.duration + pad,
    );
    final trimmed = raw.slice(math.min(pad, c.start), raw.duration);
    return Isolate.run(() => SampleEnhancer(options: options, rootPc: rootPc).process(c, trimmed, path));
  }

  /// The source's audio between [start] and [end] seconds, for listening.
  Future<AudioBuffer> sourceClip(String path, double start, double end) => AudioBuffer.decode(
    ffmpegPath,
    path,
    sampleRate: ProcessedSample.sampleRate,
    start: math.max(0, start),
    duration: math.max(0.02, end - start),
  );

  // --- bases -------------------------------------------------------------------

  static ChartSource readProject(String path) {
    final bytes = File(path).readAsBytesSync();
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.flp' => FlpProject.parse(bytes).toChartSource(path),
      '.flm' => FlmProject.parse(bytes).toChartSource(path),
      _ => MidiFile.parse(bytes).toChartSource(p.basenameWithoutExtension(path), path),
    };
  }

  /// Loads a base and works out what it plays. A checked transcription from
  /// the catalog, or the project's own notes, is exact; audio alone is a
  /// draft the user can fix (pass the fixed one as [fixed]).
  Future<PreparedBase> prepareBase(
    BaseSource source, {
    BaseTranscription? fixed,
    void Function(String status, double? fraction)? onStatus,
    bool Function()? cancelled,
  }) async {
    // Stops early when another base was picked meanwhile.
    void check() {
      if (cancelled?.call() ?? false) throw DownloadCancelled();
    }

    switch (source) {
      case LibraryBaseSource(:final base):
        onStatus?.call('Downloading ${base.name}…', 0);
        final audioPath = await library.audio(
          base,
          onProgress: (f) => onStatus?.call('Downloading ${base.name}…', f),
          cancelled: cancelled,
        );
        check();
        final sha = await BaseLibrary.sha1Of(audioPath);
        onStatus?.call('Loading the base…', null);
        final audio = await AudioBuffer.decode(ffmpegPath, audioPath, channels: 2);
        check();
        BaseTranscription? auto = await library.checkedTranscription(base, bundled: bundledFile);
        ChartSource? project;
        AudioBaseAnalysis? analysis;
        if (auto == null && base.flpUrl != null) {
          onStatus?.call('Reading the base\'s FL Studio project…', null);
          final flp = await library.project(base);
          if (flp != null) {
            final read = await Isolate.run(() => readProject(flp));
            project = read;
            auto = await _fromProject(read, audio, const {}, null);
          }
        }
        check();
        if (auto == null) {
          onStatus?.call('Transcribing the base (tempo, drums, hits, sections)…', null);
          (auto, analysis) = await _fromAudio(audioPath, sha, name: base.name);
        }
        check();
        auto = auto.copyWith(baseName: base.name, maker: base.maker, catalogId: base.id, audioSha1: sha);
        return _prepared(source, auto, fixed, audio, audioPath, project: project, analysis: analysis);
      case final ProjectBaseSource s:
        onStatus?.call('Reading the project…', null);
        final project = await Isolate.run(() => readProject(s.projectPath));
        if (s.audioPath != null) {
          final audio = await AudioBuffer.decode(ffmpegPath, s.audioPath!, channels: 2);
          onStatus?.call('Lining the project up with its audio…', null);
          final found = await _fromProject(project, audio, s.uses, s.audioOffset);
          final sha = await BaseLibrary.sha1Of(s.audioPath!);
          final known = (await library.catalog(bundledCatalog, refresh: false)).bySha1(sha);
          final auto = found.copyWith(
            baseName: known?.name ?? project.name,
            maker: known?.maker,
            catalogId: known?.id,
            audioSha1: sha,
          );
          return _prepared(source, auto, fixed, audio, s.audioPath, project: project);
        }
        onStatus?.call('Re-synthesizing the project…', null);
        final auto = ProjectTranscriber().transcribe(project, uses: s.uses).copyWith(baseName: project.name);
        final audio = await _cachedRender(s, project);
        return _prepared(source, auto, fixed, audio, null, project: project);
      case final AudioBaseSource s:
        final sha = await BaseLibrary.sha1Of(s.audioPath);
        final catalog = await library.catalog(bundledCatalog, refresh: false);
        final known = catalog.bySha1(sha);
        BaseTranscription? auto = known == null
            ? null
            : await library.checkedTranscription(known, bundled: bundledFile);
        AudioBaseAnalysis? analysis;
        check();
        if (auto == null) {
          onStatus?.call('Transcribing the base (tempo, drums, hits, sections)…', null);
          (auto, analysis) = await _fromAudio(s.audioPath, sha, name: known?.name ?? s.name, bpm: s.bpm);
        }
        check();
        auto = auto.copyWith(
          baseName: known?.name ?? s.name,
          maker: known?.maker,
          catalogId: known?.id,
          audioSha1: sha,
        );
        final audio = await AudioBuffer.decode(ffmpegPath, s.audioPath, channels: 2);
        return _prepared(source, auto, fixed, audio, s.audioPath, analysis: analysis);
    }
  }

  PreparedBase _prepared(
    BaseSource source,
    BaseTranscription auto,
    BaseTranscription? fixed,
    AudioBuffer audio,
    String? audioPath, {
    ChartSource? project,
    AudioBaseAnalysis? analysis,
  }) {
    final t = fixed ?? auto;
    return PreparedBase(
      base: SpartaBase(
        id: source.key,
        name: t.baseName.isEmpty ? source.name : t.baseName,
        author: t.maker,
        kind: switch (source) {
          LibraryBaseSource() => BaseKind.library,
          ProjectBaseSource() => BaseKind.project,
          AudioBaseSource() => BaseKind.audio,
        },
        transcription: t,
        audioPath: audioPath,
        notes: [...?project?.warnings].join(' '),
      ),
      audio: audio,
      auto: auto,
      project: project,
      analysis: analysis,
    );
  }

  Future<BaseTranscription> _fromProject(
    ChartSource project,
    AudioBuffer audio,
    Map<String, TrackUse> uses,
    double? offset,
  ) async {
    final t = await Isolate.run(() => ProjectTranscriber().transcribe(project, uses: uses));
    if (offset != null) return endWithAudio(t.copyWith(audioOffset: offset), audio);
    // Line the base's own drums (else everything it plays) up with the audio.
    final drums = project.drumHits();
    final beats = [for (final l in drums.values) ...l];
    final hits = [
      for (final b in beats.isNotEmpty ? beats : [for (final tr in project.tracks) ...tr.notes.map((n) => n.beat)])
        b * 60 / t.bpm,
    ]..sort();
    final first = project.tracks
        .expand((tr) => tr.notes)
        .fold<double?>(null, (m, n) => m == null || n.beat < m ? n.beat : m);
    final firstSeconds = first == null ? null : first * 60 / t.bpm;
    final found = await Isolate.run(
      () => AudioBaseAnalyzer().alignHits(audio, hits, firstNoteSeconds: firstSeconds, bpm: t.bpm),
    );
    return endWithAudio(t.copyWith(audioOffset: found), audio);
  }

  /// A render can stop before its project does (a cut, an older version):
  /// the base ends with its audio's last bar, so nothing plays over silence.
  static BaseTranscription endWithAudio(BaseTranscription t, AudioBuffer audio) {
    final end = AudioBaseAnalyzer.lastSound(audio);
    if (end == null) return t;
    final bar = t.beatsPerBar.toDouble();
    // A ring-out under a quarter of a bar doesn't make another bar.
    final beats = (((end - t.audioOffset) * t.bpm / 60) / bar - 0.25).ceil() * bar;
    if (beats >= t.lengthBeats - 1e-6 || beats < bar) return t;
    return t.copyWith(
      lengthBeats: beats,
      sections: [
        for (final s in t.sections)
          if (s.startBeat < beats - 1e-6) s.endBeat > beats ? Section(s.kind, s.startBeat, beats, name: s.name) : s,
      ],
    );
  }

  Future<(BaseTranscription, AudioBaseAnalysis)> _fromAudio(
    String audioPath,
    String sha, {
    String name = '',
    double? bpm,
  }) async {
    final analysisAudio = await AudioBuffer.decode(ffmpegPath, audioPath, sampleRate: AudioBaseAnalyzer.sampleRate);
    return Isolate.run(() {
      final a = AudioBaseAnalyzer().analyze(analysisAudio, tempo: bpm);
      return (AudioTranscriber().transcribe(a, name: name), a);
    });
  }

  Future<AudioBuffer> _cachedRender(ProjectBaseSource s, ChartSource project) async {
    final stamp = File(s.projectPath).lastModifiedSync().millisecondsSinceEpoch;
    final key = 'proj_${s.projectPath.hashCode.toUnsigned(32).toRadixString(16)}_$stamp';
    final file = File(_cachePath('base_$key.wav'));
    if (await file.exists()) {
      try {
        return AudioBuffer.fromWav(await file.readAsBytes());
      } catch (_) {
        // Corrupt cache entry: render again.
      }
    }
    final audio = await Isolate.run(() => BaseRenderer().render(resynthesize(project)));
    await file.parent.create(recursive: true);
    await audio.writeWav(file.path);
    return audio;
  }

  String _cachePath(String name) => p.join(cacheDir, 'sparta', name.replaceAll(RegExp(r'[^\w.-]'), '_'));

  // --- mix & export ---------------------------------------------------------------

  Future<RemixMix> mix(
    PreparedBase base,
    Map<SampleRole, List<ProcessedSample>> samples,
    MixSettings settings, {
    bool shuffleSamples = false,
    int seed = 1,
  }) {
    final b = base.base, audio = base.audio;
    return Isolate.run(
      () => Arranger(
        base: b,
        samples: samples,
        baseAudio: audio,
        settings: settings,
        shuffleSamples: shuffleSamples,
        seed: seed,
      ).mix(),
    );
  }

  /// Writes the remix (video, or audio for MP3/WAV) into [outDir] named
  /// after [name], optionally with stems and MIDI.
  Future<RemixOutputs> export({
    required PreparedBase base,
    required RemixMix mix,
    required Map<SampleRole, List<ProcessedSample>> samples,
    required Map<String, bool> sourceHasVideo,
    required String outDir,
    required String name,
    bool stems = false,
    bool midi = false,
    VisualOptions visuals = const VisualOptions(),
    String title = '',
    String? fontPath,
    OutputSettings output = const OutputSettings(),
    void Function(double fraction, String status)? onProgress,
    CancelToken? cancel,
  }) async {
    await Directory(outDir).create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final work = Directory(p.join(cacheDir, 'sparta', 'render_$stamp'));
    await work.create(recursive: true);
    try {
      onProgress?.call(0.01, 'Writing audio');
      final masterWav = p.join(work.path, 'master.wav');
      await mix.master.writeWav(masterWav);

      final stemPaths = <Stem, String>{};
      if (stems) {
        final dir = p.join(outDir, '$name stems');
        await Directory(dir).create(recursive: true);
        for (final e in mix.stems.entries) {
          final path = p.join(dir, '$name - ${e.key.name}.wav');
          await e.value.writeWav(path);
          stemPaths[e.key] = path;
        }
      }
      final midiPaths = <String>[];
      if (midi) {
        final chartPath = p.join(outDir, '$name - sample chart.mid');
        await File(chartPath).writeAsBytes(MidiFile.fromChart(base.base).encode());
        midiPaths.add(chartPath);
        final basePath = p.join(outDir, '$name - base notes.mid');
        await File(basePath).writeAsBytes(MidiFile.fromTranscription(base.transcription).encode());
        midiPaths.add(basePath);
      }

      final target = await _unique(outDir, name, output.format.extension);
      if (output.format.hasVideo) {
        final sources = <(SampleRole, int), VisualSource>{};
        for (final e in samples.entries) {
          for (var i = 0; i < e.value.length; i++) {
            final s = e.value[i];
            sources[(e.key, i)] = VisualSource(
              path: s.sourcePath,
              hasVideo: sourceHasVideo[s.sourcePath] ?? false,
              start: s.candidate.start + s.lead,
              duration: math.max(s.naturalSeconds, s.candidate.duration - s.lead),
            );
          }
        }
        await VisualRenderer(ffmpegPath: ffmpegPath, workDir: p.join(work.path, 'video'), fontPath: fontPath).render(
          events: mix.events,
          sources: sources,
          options: visuals,
          title: title,
          masterAudioPath: masterWav,
          duration: mix.duration,
          outputPath: target,
          output: output,
          onProgress: (f, s) => onProgress?.call(0.02 + f * 0.97, s),
          cancel: cancel,
        );
      } else {
        await FfmpegRunner(ffmpegPath).run([
          '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', '-i', masterWav, //
          if (output.format == OutputFormat.mp3) ...[
            '-c:a',
            'libmp3lame',
            '-b:a',
            '${output.quality.audioKbps}k',
          ] else ...[
            '-c:a',
            'pcm_s16le',
          ],
          target,
        ], cancel: cancel);
      }
      onProgress?.call(1, 'Done');
      return RemixOutputs(output: target, stems: stemPaths, midi: midiPaths);
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<String> _unique(String dir, String name, String ext) async {
    var candidate = p.join(dir, '$name.$ext');
    var i = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(dir, '$name ($i).$ext');
      i++;
    }
    return candidate;
  }
}
