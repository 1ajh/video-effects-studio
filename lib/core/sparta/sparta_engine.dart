import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../audio/audio_buffer.dart';
import '../ffmpeg/ffmpeg_runner.dart';
import '../models/output_settings.dart';
import 'arranger.dart';
import 'audio_base.dart';
import 'base.dart';
import 'base_renderer.dart';
import 'chart_import.dart';
import 'composer.dart';
import 'flm.dart';
import 'flp.dart';
import 'midi.dart';
import 'model.dart';
import 'sample_finder.dart';
import 'sample_processing.dart';
import 'visual_renderer.dart';

/// Where the base comes from.
sealed class BaseSource {
  const BaseSource();
}

/// One of the procedurally composed built-in bases.
class BuiltInBaseSource extends BaseSource {
  const BuiltInBaseSource({
    this.style = BaseStyle.classic,
    this.length = RemixLength.standard,
    this.sections,
    this.seed = 1,
    this.sectionSeeds = const {},
  });

  final BaseStyle style;
  final RemixLength length;

  /// Enabled sections (null = all).
  final Set<SectionKind>? sections;
  final int seed;

  /// Per-section re-roll counters.
  final Map<SectionKind, int> sectionSeeds;
}

/// An FL Studio (.flp), FL Studio Mobile (.flm) or MIDI project, optionally
/// with its rendered audio. Without audio the project is re-synthesized.
class ProjectBaseSource extends BaseSource {
  const ProjectBaseSource({
    required this.projectPath,
    this.audioPath,
    this.mapping,
    this.transpose = 0,
    this.audioOffset,
    this.style = BaseStyle.classic,
    this.seed = 1,
  });

  final String projectPath;
  final String? audioPath;

  /// Track id → sample lane (null: guess from names).
  final Map<String, SampleRole?>? mapping;
  final int transpose;

  /// Seconds into the audio where beat 0 lands (null: detect).
  final double? audioOffset;
  final BaseStyle style;
  final int seed;
}

/// Just an audio file: tempo, bars, harmony and sections are detected.
class AudioBaseSource extends BaseSource {
  const AudioBaseSource({
    required this.audioPath,
    this.bpmHint,
    this.transpose = 0,
    this.style = BaseStyle.classic,
    this.seed = 1,
  });
  final String audioPath;
  final double? bpmHint;
  final int transpose;
  final BaseStyle style;
  final int seed;
}

/// A base ready to mix: chart + stereo 48 kHz audio.
class PreparedBase {
  PreparedBase({required this.base, required this.audio, this.score, this.chart, this.analysis});
  final SpartaBase base;
  final AudioBuffer audio;

  /// Instrument parts (built-in or re-synthesized), exported as MIDI.
  final Composition? score;
  final ChartSource? chart;
  final AudioBaseAnalysis? analysis;
}

/// Files written for a finished remix.
class RemixOutputs {
  RemixOutputs({required this.output, this.stems = const {}, this.midi = const []});

  /// The remix in the chosen format (video, or audio for MP3/WAV).
  final String output;
  final Map<Stem, String> stems;
  final List<String> midi;
}

/// Orchestrates the Sparta pipeline: analysis, samples, bases, mixing and
/// export. Heavy DSP runs in background isolates.
class SpartaEngine {
  SpartaEngine({required this.ffmpegPath, required this.cacheDir});

  final String ffmpegPath;
  final String cacheDir;

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
      Isolate.run(() => SampleFinder(sources).find(keep: 8));

  /// Cuts [c] from its source at full quality and makes it Sparta-ready.
  Future<ProcessedSample> prepareSample(
    SampleCandidate c,
    String path, {
    EnhanceOptions options = const EnhanceOptions(),
  }) async {
    final pad = 0.01;
    final raw = await AudioBuffer.decode(
      ffmpegPath,
      path,
      sampleRate: ProcessedSample.sampleRate,
      start: math.max(0, c.start - pad),
      duration: c.duration + pad,
    );
    final trimmed = raw.slice(math.min(pad, c.start), raw.duration);
    return Isolate.run(() => SampleEnhancer(options: options).process(c, trimmed, path));
  }

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

  Future<PreparedBase> prepareBase(BaseSource source) async {
    switch (source) {
      case final BuiltInBaseSource s:
        final plan = defaultPlan(length: s.length, enabled: s.sections);
        if (plan.isEmpty) throw ArgumentError('Enable at least one section.');
        final key = [
          s.style.name, s.length.name, s.seed, //
          plan.map((x) => '${x.kind.name}${x.bars}').join('-'),
          s.sectionSeeds.entries.map((e) => '${e.key.name}${e.value}').join('-'),
        ].join('_');
        final comp = Composer(style: s.style, seed: s.seed).compose(plan, sectionSeeds: s.sectionSeeds);
        final audio = await _cachedRender(key, comp);
        return PreparedBase(
          base: comp.base.copyWith(audioPath: _cachePath('base_$key.wav')),
          audio: audio,
          score: comp,
        );
      case final ProjectBaseSource s:
        final chart = await Isolate.run(() => readProject(s.projectPath));
        final mapping = s.mapping ?? chart.guessMapping();
        var base = chart.toBase(mapping, transpose: s.transpose, audioPath: s.audioPath, seed: s.seed, style: s.style);
        if (s.audioPath != null) {
          final audio = await AudioBuffer.decode(ffmpegPath, s.audioPath!, channels: 2);
          var offset = s.audioOffset;
          if (offset == null) {
            // Line up the base's own parts (its drums, else everything it
            // plays) with the audio; the sample chart isn't in the audio.
            final own = [
              for (final t in chart.tracks)
                if (mapping[t.id] == null) t,
            ];
            final drums = own.where((t) => t.isDrums).toList();
            final hits = [
              for (final t in drums.isNotEmpty ? drums : own)
                for (final n in t.notes) base.seconds(n.beat),
            ]..sort();
            final firstNote = chart.tracks
                .expand((t) => t.notes)
                .fold<double?>(null, (m, n) => m == null || n.beat < m ? n.beat : m);
            final firstSeconds = firstNote == null ? null : base.seconds(firstNote);
            offset = await Isolate.run(
              () => AudioBaseAnalyzer().alignHits(audio, hits, firstNoteSeconds: firstSeconds),
            );
          }
          base = base.copyWith(audioOffset: offset);
          return PreparedBase(base: base, audio: audio, chart: chart);
        }
        final comp = resynthesize(chart, base, mapping, style: s.style, seed: s.seed);
        final key =
            'proj_${s.projectPath.hashCode.toUnsigned(32).toRadixString(16)}_${s.style.name}_${s.seed}_'
            '${File(s.projectPath).lastModifiedSync().millisecondsSinceEpoch}_'
            '${mapping.entries.where((e) => e.value != null).map((e) => '${e.key}${e.value!.index}').join()}';
        final audio = await _cachedRender(key, comp);
        return PreparedBase(base: base, audio: audio, score: comp, chart: chart);
      case final AudioBaseSource s:
        final analysisAudio = await AudioBuffer.decode(
          ffmpegPath,
          s.audioPath,
          sampleRate: AudioBaseAnalyzer.sampleRate,
        );
        final analysis = await Isolate.run(() => AudioBaseAnalyzer().analyze(analysisAudio, bpmHint: s.bpmHint));
        final base = AudioBaseAnalyzer().toBase(
          analysis,
          name: p.basenameWithoutExtension(s.audioPath),
          audioPath: s.audioPath,
          style: s.style,
          seed: s.seed,
          transpose: s.transpose,
        );
        final audio = await AudioBuffer.decode(ffmpegPath, s.audioPath, channels: 2);
        return PreparedBase(base: base, audio: audio, analysis: analysis);
    }
  }

  Future<AudioBuffer> _cachedRender(String key, Composition comp) async {
    final file = File(_cachePath('base_$key.wav'));
    if (await file.exists()) {
      try {
        return AudioBuffer.fromWav(await file.readAsBytes());
      } catch (_) {
        // Corrupt cache entry: render again.
      }
    }
    final audio = await Isolate.run(() => BaseRenderer().render(comp));
    await file.parent.create(recursive: true);
    await audio.writeWav(file.path);
    return audio;
  }

  String _cachePath(String name) => p.join(cacheDir, 'sparta', name.replaceAll(RegExp(r'[^\w.-]'), '_'));

  // --- mix & export ---------------------------------------------------------------

  Future<RemixMix> mix(PreparedBase base, Map<SampleRole, List<ProcessedSample>> samples, MixSettings settings) {
    final b = base.base, audio = base.audio;
    return Isolate.run(() => Arranger(base: b, samples: samples, baseAudio: audio, settings: settings).mix());
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
    VisualPreset preset = VisualPreset.classic,
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
        final score = base.score;
        if (score != null) {
          final basePath = p.join(outDir, '$name - base.mid');
          await File(basePath).writeAsBytes(MidiFile.fromScore(score).encode());
          midiPaths.add(basePath);
        }
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
              start: s.candidate.start,
              duration: math.max(s.naturalSeconds, s.candidate.duration),
            );
          }
        }
        await VisualRenderer(ffmpegPath: ffmpegPath, workDir: p.join(work.path, 'video')).render(
          base: base.base,
          events: mix.events,
          sources: sources,
          preset: preset,
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
