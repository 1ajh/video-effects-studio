import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../effects/effect.dart';
import '../effects/registry.dart';
import '../ffmpeg/blocks.dart';
import '../ffmpeg/command_builder.dart';
import '../ffmpeg/ffmpeg_runner.dart';
import '../ffmpeg/ffmpeg_toolkit.dart';
import '../ffmpeg/media_info.dart';
import '../models/output_settings.dart';

enum LabelMode {
  none('No labels'),
  overlay('Name overlay'),
  titleCard('Title cards');

  const LabelMode(this.label);
  final String label;
}

/// One entry of a compilation: an effect with its own parameter values.
class CompilationEntry {
  const CompilationEntry(this.effect, this.params);
  final Effect effect;
  final ParamValues params;
}

class CompilationRequest {
  const CompilationRequest({
    required this.media,
    required this.entries,
    required this.outputPath,
    this.start = 0,
    this.end,
    this.output = const OutputSettings(),
    this.labelMode = LabelMode.overlay,
    this.originalFirst = true,
    this.titleCardSeconds = 1.2,
    this.fontPath,
    this.concurrency = 2,
  });

  final MediaInfo media;
  final List<CompilationEntry> entries;
  final String outputPath;
  final double start;
  final double? end;
  final OutputSettings output;
  final LabelMode labelMode;
  final bool originalFirst;
  final double titleCardSeconds;

  /// TTF used for labels (required unless [labelMode] is none).
  final String? fontPath;
  final int concurrency;
}

class SegmentFailure {
  const SegmentFailure(this.effectName, this.message);
  final String effectName;
  final String message;
}

class RenderOutcome {
  const RenderOutcome(this.outputPath, {this.failures = const []});
  final String outputPath;
  final List<SegmentFailure> failures;
}

typedef ProgressCallback = void Function(double fraction, String status);

/// Drives FFmpeg for everything the app renders.
class RenderEngine {
  RenderEngine(this.toolkit) : _runner = FfmpegRunner(toolkit.ffmpegPath);

  final FfmpegToolkit toolkit;
  final FfmpegRunner _runner;

  // ---------------------------------------------------------------------------
  // Probing
  // ---------------------------------------------------------------------------

  Future<MediaInfo> probe(String path) async {
    final size = await MediaInfo.fileSize(path);
    final ffprobe = toolkit.ffprobePath;
    if (ffprobe != null) {
      final r = await Process.run(ffprobe, [
        '-v', 'error', '-print_format', 'json', '-show_format', '-show_streams', path, //
      ]);
      if (r.exitCode == 0) return MediaInfo.fromProbeJson(path, '${r.stdout}', sizeBytes: size);
    }
    final r = await Process.run(toolkit.ffmpegPath, ['-hide_banner', '-nostdin', '-i', path]);
    final info = MediaInfo.fromFfmpegBanner(path, '${r.stderr}', sizeBytes: size);
    if (!info.hasVideo && !info.hasAudio) {
      throw FfmpegException('Not a readable video or audio file: ${p.basename(path)}');
    }
    return info;
  }

  // ---------------------------------------------------------------------------
  // Single effect
  // ---------------------------------------------------------------------------

  Future<RenderOutcome> render(RenderRequest request, {ProgressCallback? onProgress, CancelToken? cancel}) async {
    onProgress?.call(0, 'Measuring ${request.effect.name}');
    final cmd = CommandBuilder.build(await leveled(request, cancel: cancel));
    await Directory(p.dirname(request.outputPath)).create(recursive: true);
    try {
      await _runner.run(
        cmd.args,
        expectedSeconds: cmd.expectedSeconds,
        onProgress: (f) => onProgress?.call(f, 'Rendering ${request.effect.name}'),
        cancel: cancel,
      );
    } catch (_) {
      await _deleteQuietly(request.outputPath);
      rethrow;
    }
    return RenderOutcome(request.outputPath);
  }

  /// [r] with the gain that brings its audio to the output's loudness
  /// target: the effect's audio is measured first. Unchanged when level
  /// matching is off, there's no audio, or the measurement fails.
  Future<RenderRequest> leveled(RenderRequest r, {CancelToken? cancel}) async {
    final target = r.output.loudness.lufs;
    final format = r.target == EncodeTarget.output ? r.output.format : OutputFormat.mp4;
    if (target == null || !r.media.hasAudio || !format.hasAudio) return r;
    try {
      Future<double?> measure(RenderRequest x) async =>
          CommandBuilder.parseLoudness(await _runner.run(CommandBuilder.measure(x).args, cancel: cancel));
      final first = CommandBuilder.gainFor(await measure(r), target, loud: r.effect.loud);
      if (first == null) return r;
      if (first <= 0.5) return r.withGain(first);
      // Turning up: the limiter takes some of it back, so top up once.
      final after = await measure(r.withGain(first));
      if (after == null) return r.withGain(first);
      return r.withGain((first + (target - after)).clamp(math.max(0.0, first - 3), first + 12).toDouble());
    } on CancelledException {
      rethrow;
    } catch (_) {
      return r;
    }
  }

  /// Short, low-res render for the in-app before/after player.
  Future<String> preview({
    required MediaInfo media,
    required Effect effect,
    required ParamValues params,
    required double start,
    required double seconds,
    required String cacheDir,
    LoudnessTarget loudness = LoudnessTarget.loud,
    CancelToken? cancel,
    void Function(double)? onProgress,
  }) async {
    final end = math.min(media.duration, start + seconds);
    final key = _cacheKey([media.path, effect.id, params.toString(), fmt(start), fmt(end), loudness.name]);
    final out = p.join(cacheDir, 'preview_$key.mp4');
    if (await File(out).exists()) return out;
    await Directory(cacheDir).create(recursive: true);
    final tmp = p.join(cacheDir, 'preview_$key.part.mp4');
    final request = RenderRequest(
      media: media,
      effect: effect,
      params: params,
      outputPath: tmp,
      start: start,
      end: end,
      target: EncodeTarget.preview,
      output: OutputSettings(loudness: loudness),
    );
    final cmd = CommandBuilder.build(await leveled(request, cancel: cancel));
    try {
      await _runner.run(cmd.args, expectedSeconds: cmd.expectedSeconds, onProgress: onProgress, cancel: cancel);
      await File(tmp).rename(out);
    } catch (_) {
      await _deleteQuietly(tmp);
      rethrow;
    }
    return out;
  }

  /// Still frame of an effect for the browser/inspector.
  Future<String?> thumbnail({
    required MediaInfo media,
    required Effect? effect,
    required ParamValues params,
    required double atSeconds,
    required String cacheDir,
    int width = 320,
  }) async {
    if (!media.hasVideo) return null;
    final key = _cacheKey([media.path, effect?.id ?? '-', params.toString(), fmt(atSeconds), '$width']);
    final out = p.join(cacheDir, 'thumb_$key.jpg');
    if (await File(out).exists()) return out;
    await Directory(cacheDir).create(recursive: true);
    final cmd = CommandBuilder.thumbnail(
      media: media,
      effect: effect,
      params: params,
      atSeconds: atSeconds,
      outputPath: out,
      width: width,
    );
    try {
      await _runner.run(cmd.args);
      return await File(out).exists() ? out : null;
    } catch (_) {
      await _deleteQuietly(out);
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Compilation (effects one after another, in order)
  // ---------------------------------------------------------------------------

  Future<RenderOutcome> renderCompilation(
    CompilationRequest req, {
    ProgressCallback? onProgress,
    CancelToken? cancel,
  }) async {
    final entries = [if (req.originalFirst) const CompilationEntry(EffectRegistry.original, {}), ...req.entries];
    if (entries.isEmpty) throw FfmpegException('The compilation is empty.');

    final labels = req.labelMode != LabelMode.none && toolkit.hasDrawtext && req.fontPath != null;
    final work = await Directory.systemTemp.createTemp('vfx_comp_');
    try {
      const fontName = 'label_font.ttf';
      if (labels) await File(req.fontPath!).copy(p.join(work.path, fontName));

      final (w, h) = CommandBuilder.scaledSize(req.media, req.output.resolution.maxHeight);
      final fps = _segmentFps(req.media.fps);
      final inputSeconds = RenderRequest(
        media: req.media,
        effect: EffectRegistry.original,
        params: const {},
        outputPath: '',
        start: req.start,
        end: req.end,
      ).inputSeconds;

      // Plan every segment (title cards + effect clips) up front.
      final jobs = <_SegmentJob>[];
      var effectNumber = 0;
      final total = req.entries.length;
      for (final entry in entries) {
        final isOriginal = identical(entry.effect, EffectRegistry.original);
        if (!isOriginal) effectNumber++;
        final displayName = entry.effect.name;
        final index = jobs.length;

        if (labels && req.labelMode == LabelMode.titleCard) {
          final kickerText = isOriginal ? 'ORIGINAL' : 'EFFECT $effectNumber OF $total';
          final kickerFile = 'card_${index}_k.txt';
          final titleFile = 'card_${index}_t.txt';
          await File(p.join(work.path, kickerFile)).writeAsString(kickerText);
          await File(p.join(work.path, titleFile)).writeAsString(displayName);
          jobs.add(
            _SegmentJob.card(
              name: displayName,
              file: 'seg_${jobs.length.toString().padLeft(4, '0')}.mkv',
              seconds: req.titleCardSeconds,
              command: (out) async => CommandBuilder.titleCard(
                outputPath: out,
                width: w,
                height: h,
                fps: fps,
                seconds: req.titleCardSeconds,
                kicker: SegmentLabel(textFile: kickerFile, text: kickerText, fontFile: fontName),
                title: SegmentLabel(textFile: titleFile, text: displayName, fontFile: fontName),
              ),
            ),
          );
        }

        SegmentLabel? overlay;
        if (labels && req.labelMode == LabelMode.overlay) {
          final text = isOriginal ? 'Original' : '$effectNumber. $displayName';
          final file = 'label_$index.txt';
          await File(p.join(work.path, file)).writeAsString(text);
          overlay = SegmentLabel(textFile: file, text: text, fontFile: fontName);
        }

        final seconds = entry.effect.outputSecondsFor(entry.params, inputSeconds);
        final ownerIndex = jobs.length;
        jobs.add(
          _SegmentJob.effect(
            name: displayName,
            file: 'seg_${ownerIndex.toString().padLeft(4, '0')}.mkv',
            seconds: seconds,
            command: (out) async => CommandBuilder.build(
              await leveled(
                RenderRequest(
                  media: req.media,
                  effect: entry.effect,
                  params: entry.params,
                  outputPath: out,
                  start: req.start,
                  end: req.end,
                  output: req.output,
                  target: EncodeTarget.segment,
                  segment: SegmentFormat(width: w, height: h, fps: fps, label: overlay),
                ),
                cancel: cancel,
              ),
            ),
          ),
        );
      }

      // Title cards belong to the effect that follows them; if the effect
      // fails, its card is dropped too.
      for (var i = 0; i < jobs.length - 1; i++) {
        if (jobs[i].isCard) jobs[i].owner = jobs[i + 1];
      }

      final segmentWeight = 0.88;
      final totalSeconds = jobs.fold<double>(0, (s, j) => s + j.seconds);
      final done = <_SegmentJob, double>{};
      void report(String status) {
        final secs = done.entries.fold<double>(0, (s, e) => s + e.key.seconds * e.value);
        onProgress?.call(segmentWeight * (secs / math.max(totalSeconds, 0.001)), status);
      }

      var cursor = 0;
      final failures = <SegmentFailure>[];
      Future<void> worker() async {
        while (true) {
          if (cancel?.isCancelled ?? false) throw const CancelledException();
          if (cursor >= jobs.length) return;
          final job = jobs[cursor++];
          final out = p.join(work.path, job.file);
          final cmd = await job.command(out);
          final label = job.isCard ? 'Title card: ${job.name}' : 'Rendering ${job.name}';
          try {
            await _runner.run(
              cmd.args,
              workingDirectory: work.path,
              expectedSeconds: cmd.expectedSeconds,
              onProgress: (f) {
                done[job] = f;
                report(label);
              },
              cancel: cancel,
            );
            done[job] = 1;
            job.ok = true;
            report(label);
          } on CancelledException {
            rethrow;
          } catch (e) {
            done[job] = 1;
            job.ok = false;
            if (!job.isCard) failures.add(SegmentFailure(job.name, '$e'));
            report('Skipped ${job.name}');
          }
        }
      }

      await Future.wait([for (var i = 0; i < math.max(1, math.min(req.concurrency, 4)); i++) worker()]);

      final usable = jobs.where((j) => j.ok && (j.owner?.ok ?? true)).toList();
      if (usable.where((j) => !j.isCard).isEmpty) {
        throw FfmpegException(
          failures.isEmpty ? 'Nothing was rendered.' : 'Every effect failed. First error: ${failures.first.message}',
        );
      }
      final list = usable.map((j) => "file '${j.file}'").join('\n');
      await File(p.join(work.path, 'list.txt')).writeAsString('$list\n');

      final finalSeconds = usable.fold<double>(0, (s, j) => s + j.seconds);
      await Directory(p.dirname(req.outputPath)).create(recursive: true);
      final concatCmd = CommandBuilder.concat(
        listFile: 'list.txt',
        outputPath: req.outputPath,
        output: req.output,
        totalSeconds: finalSeconds,
        fps: fps,
      );
      try {
        await _runner.run(
          concatCmd.args,
          workingDirectory: work.path,
          expectedSeconds: finalSeconds,
          onProgress: (f) =>
              onProgress?.call(segmentWeight + (1 - segmentWeight) * f, 'Joining ${usable.length} segments'),
          cancel: cancel,
        );
      } catch (_) {
        await _deleteQuietly(req.outputPath);
        rethrow;
      }
      onProgress?.call(1, 'Done');
      return RenderOutcome(req.outputPath, failures: failures);
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  static double _segmentFps(double fps) {
    if (!fps.isFinite || fps < 10 || fps > 60) return 30;
    // Snap near-standard rates (29.97 -> 30000/1001 is fine as a decimal).
    return double.parse(fps.toStringAsFixed(3));
  }

  static String _cacheKey(List<String> parts) {
    var hash = 0xcbf29ce484222325;
    for (final unit in parts.join('\u0000').codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(36);
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Picks a free output path like `clip_g-major-4.mp4`, `clip_g-major-4 (2).mp4`.
  static Future<String> uniqueOutputPath(String dir, String baseName, String extension) async {
    final safe = baseName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    var candidate = p.join(dir, '$safe.$extension');
    var n = 2;
    while (await File(candidate).exists()) {
      candidate = p.join(dir, '$safe ($n).$extension');
      n++;
    }
    return candidate;
  }

  static String slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
}

class _SegmentJob {
  _SegmentJob.card({required this.name, required this.file, required this.seconds, required this.command})
    : isCard = true;
  _SegmentJob.effect({required this.name, required this.file, required this.seconds, required this.command})
    : isCard = false;

  final String name;
  final String file;
  final double seconds;
  final bool isCard;
  final Future<BuiltCommand> Function(String outputPath) command;
  _SegmentJob? owner;
  bool ok = false;
}
