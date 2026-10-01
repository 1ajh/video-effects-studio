import 'dart:math' as math;

import '../effects/effect.dart';
import '../models/output_settings.dart';
import 'blocks.dart';
import 'filter_graph.dart';
import 'media_info.dart';

/// How a text label is burned into a compilation segment.
class SegmentLabel {
  const SegmentLabel({required this.textFile, required this.text, required this.fontFile});

  /// File name (relative to the working directory) holding the label text.
  final String textFile;

  /// The text itself (used to size the font).
  final String text;

  /// Font file name relative to the working directory.
  final String fontFile;
}

/// Fixed format for compilation segments so they can be concatenated.
class SegmentFormat {
  const SegmentFormat({required this.width, required this.height, required this.fps, this.label});

  final int width;
  final int height;
  final double fps;
  final SegmentLabel? label;
}

enum EncodeTarget {
  /// Final user-facing file using [OutputSettings].
  output,

  /// Fast low-res preview for the in-app player.
  preview,

  /// Near-lossless intermediate for compilation segments (MKV).
  segment,
}

class RenderRequest {
  const RenderRequest({
    required this.media,
    required this.effect,
    required this.params,
    required this.outputPath,
    this.start = 0,
    this.end,
    this.output = const OutputSettings(),
    this.target = EncodeTarget.output,
    this.segment,
    this.previewMaxHeight = 480,
    this.gainDb,
  });

  final MediaInfo media;
  final Effect effect;
  final ParamValues params;
  final String outputPath;

  /// Trim range in seconds of the source.
  final double start;
  final double? end;

  final OutputSettings output;
  final EncodeTarget target;
  final SegmentFormat? segment;
  final int previewMaxHeight;

  /// Level matching: gain applied after the effect, then a −1 dB peak
  /// limiter (null: the audio is left as the effect makes it).
  final double? gainDb;

  RenderRequest withGain(double? db) => RenderRequest(
    media: media,
    effect: effect,
    params: params,
    outputPath: outputPath,
    start: start,
    end: end,
    output: output,
    target: target,
    segment: segment,
    previewMaxHeight: previewMaxHeight,
    gainDb: db,
  );

  double get inputSeconds {
    final limit = media.duration > 0 ? media.duration : double.infinity;
    final stop = (end ?? media.duration).clamp(0.0, limit).toDouble();
    return math.max(0.04, stop - start);
  }
}

class BuiltCommand {
  const BuiltCommand(this.args, this.expectedSeconds, {this.graph = ''});
  final List<String> args;
  final double expectedSeconds;
  final String graph;

  @override
  String toString() => args.map((a) => a.contains(' ') ? '"$a"' : a).join(' ');
}

/// Turns a [RenderRequest] into FFmpeg arguments.
class CommandBuilder {
  static const int sampleRate = 48000;
  static const List<String> _common = [
    '-hide_banner',
    '-nostdin',
    '-y',
    '-loglevel',
    'error',
    '-progress',
    'pipe:1',
    '-nostats',
  ];

  /// Even frame size for the source after the resolution cap.
  static (int, int) scaledSize(MediaInfo m, int? maxHeight) {
    var w = m.width > 0 ? m.width : 1280;
    var h = m.height > 0 ? m.height : 720;
    if (maxHeight != null && h > maxHeight) {
      w = (w * maxHeight / h).round();
      h = maxHeight;
    }
    w = math.max(2, w - w % 2);
    h = math.max(2, h - h % 2);
    return (w, h);
  }

  /// Peak ceiling of level-matched audio.
  static const ceilingDb = -1.0;

  /// The effect's audio alone (with [RenderRequest.gainDb] and the limiter
  /// when set), measured by `ebur128` instead of encoded. See
  /// [parseLoudness].
  static BuiltCommand measure(RenderRequest r) {
    final media = r.media;
    final inputSeconds = r.inputSeconds;
    final outSeconds = r.effect.outputSecondsFor(r.params, inputSeconds);
    final env = FxEnv(width: 320, height: 240, fps: 25, duration: inputSeconds, sampleRate: sampleRate);
    final g = FilterGraph();
    var a = g.a('0:a:0', 'aresample=$sampleRate,aformat=sample_fmts=fltp:channel_layouts=stereo');
    if (r.effect.audio != null) a = r.effect.audio!(g, a, r.effect.reader(r.params), env);
    if (r.gainDb != null) a = g.a(a, _gainStage(r.gainDb!));
    a = g.a(
      a,
      'aresample=$sampleRate,aformat=sample_fmts=fltp:sample_rates=$sampleRate:channel_layouts=stereo,'
      'atrim=duration=${fmt(outSeconds)},ebur128=framelog=quiet',
    );
    return BuiltCommand([
      '-hide_banner', '-nostdin', '-y', '-loglevel', 'info', '-nostats', //
      if (r.start > 0) ...['-ss', fmt(r.start)],
      '-t', fmt(inputSeconds), '-i', media.path,
      '-filter_complex', g.build(), '-map', '[$a]', '-f', 'null', '-',
    ], outSeconds);
  }

  /// Integrated loudness (LUFS) from a [measure] run's log; null when the
  /// log has none or the audio is silent.
  static double? parseLoudness(String log) {
    final m = RegExp(r'^\s*I:\s*(-?[\d.]+|-inf)\s*LUFS', multiLine: true).allMatches(log).lastOrNull;
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    return v == null || v < -70 ? null : v;
  }

  /// Gain, a gentle tanh soft clip (what lets speech get loud without
  /// pumping) and a lookahead limiter holding peaks under [ceilingDb].
  static String _gainStage(double db) =>
      'volume=${fmt(db)}dB,asoftclip=type=tanh:threshold=0.8,'
      'alimiter=limit=${fmt(math.pow(10, (ceilingDb - 0.5) / 20))}:attack=2:release=60:level=false:latency=true';

  /// Gain that brings audio measured at [lufs] to [target] (null: leave it
  /// alone). Effects that are loud on purpose are only ever turned up, and
  /// keep their own sound (no limiter) when they're loud enough already.
  static double? gainFor(double? lufs, double? target, {bool loud = false}) {
    if (lufs == null || target == null) return null;
    final g = (target - lufs).clamp(-24.0, 30.0);
    if (loud && g <= 0.5) return null;
    return g;
  }

  static BuiltCommand build(RenderRequest r) {
    final media = r.media;
    final inputSeconds = r.inputSeconds;
    final outSeconds = r.effect.outputSecondsFor(r.params, inputSeconds);
    final reader = r.effect.reader(r.params);

    final format = switch (r.target) {
      EncodeTarget.output => r.output.format,
      _ => OutputFormat.mp4,
    };
    final needVideo = format.hasVideo;
    final needAudio = format.hasAudio;

    final segment = r.segment;
    final int? cap = switch (r.target) {
      EncodeTarget.preview => math.min(r.previewMaxHeight, r.output.resolution.maxHeight ?? 1 << 20),
      _ => r.output.resolution.maxHeight,
    };
    final (w, h) = segment != null ? (segment.width, segment.height) : scaledSize(media, cap);
    final fps = segment?.fps ?? (media.fps > 0 && media.fps <= 120 ? media.fps : 30);

    final env = FxEnv(width: w, height: h, fps: fps, duration: inputSeconds, sampleRate: sampleRate);

    // ---- inputs ----------------------------------------------------------
    final args = <String>[..._common];
    if (r.start > 0) args.addAll(['-ss', fmt(r.start)]);
    args.addAll(['-t', fmt(inputSeconds), '-i', media.path]);
    var nextInput = 1;
    String videoIn = '0:v:0';
    String audioIn = '0:a:0';
    if (needVideo && !media.hasVideo) {
      args.addAll(['-f', 'lavfi', '-t', fmt(inputSeconds), '-i', 'color=c=black:s=${w}x$h:r=${fmt(fps)}']);
      videoIn = '$nextInput:v';
      nextInput++;
    }
    if (needAudio && !media.hasAudio) {
      // Silent source sized to the effect's output. Audio effects are skipped
      // for it below: they can't create sound from silence, and some FFmpeg
      // releases (6.1) deadlock on generated silence in multi-branch graphs.
      args.addAll([
        '-f', 'lavfi', '-t', fmt(outSeconds), //
        '-i', 'anullsrc=channel_layout=stereo:sample_rate=$sampleRate',
      ]);
      audioIn = '$nextInput:a';
      nextInput++;
    }

    // ---- graph -----------------------------------------------------------
    final g = FilterGraph();
    String? vOut;
    String? aOut;

    if (needVideo) {
      final pre = segment != null
          ? 'scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black,'
                'setsar=1,fps=${fmt(fps)},format=yuv420p'
          : 'scale=$w:$h,setsar=1,format=yuv420p';
      var v = g.v(videoIn, pre);
      if (r.effect.video != null) v = r.effect.video!(g, v, reader, env);
      if (segment != null) {
        v = g.v(
          v,
          'scale=$w:$h:force_original_aspect_ratio=decrease,pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black,'
          'setsar=1,fps=${fmt(fps)},format=yuv420p,'
          'tpad=stop_mode=clone:stop_duration=${fmt(outSeconds + 1)},'
          'trim=duration=${fmt(outSeconds)},setpts=PTS-STARTPTS',
        );
        if (segment.label != null) v = g.v(v, overlayLabel(segment.label!, w, h));
      } else {
        v = g.v(v, 'scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=1,format=yuv420p');
      }
      if (format == OutputFormat.gif) {
        final gifFps = math.min(r.output.gifFps.toDouble(), fps);
        final pre = g.v(v, "fps=${fmt(gifFps)},scale='min(iw,640)':-2:flags=lanczos");
        final s = g.split(pre, 2);
        final pal = g.v(s[0], 'palettegen=stats_mode=diff');
        v = g.join([s[1], pal], 'paletteuse=dither=bayer:bayer_scale=4');
      }
      vOut = v;
    }

    if (needAudio) {
      var a = g.a(audioIn, 'aresample=$sampleRate,aformat=sample_fmts=fltp:channel_layouts=stereo');
      if (r.effect.audio != null && media.hasAudio) a = r.effect.audio!(g, a, reader, env);
      final gain = r.gainDb;
      if (gain != null && media.hasAudio) a = g.a(a, _gainStage(gain));
      final norm = 'aresample=$sampleRate,aformat=sample_fmts=fltp:sample_rates=$sampleRate:channel_layouts=stereo';
      // Always land exactly on the effect's length: echo/reverb tails would
      // otherwise outlast the picture, and short audio would end early.
      a = g.a(a, '$norm,apad=whole_dur=${fmt(outSeconds)},atrim=duration=${fmt(outSeconds)},asetpts=PTS-STARTPTS');
      aOut = a;
    }

    final graph = g.build();
    args.addAll(['-filter_complex', graph]);
    if (vOut != null) args.addAll(['-map', '[$vOut]']);
    if (aOut != null) args.addAll(['-map', '[$aOut]']);
    args.addAll(['-max_muxing_queue_size', '4096']);
    args.addAll(_encodeArgs(r.target, format, r.output, fps: fps));
    args.add(r.outputPath);

    return BuiltCommand(args, outSeconds, graph: graph);
  }

  static List<String> _encodeArgs(EncodeTarget target, OutputFormat format, OutputSettings o, {required double fps}) {
    switch (target) {
      case EncodeTarget.segment:
        return [
          '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '14', '-pix_fmt', 'yuv420p', //
          '-g', '${math.max(1, (fps * 2).round())}',
          '-c:a', 'pcm_s16le', '-ar', '$sampleRate', '-ac', '2',
          '-f', 'matroska',
        ];
      case EncodeTarget.preview:
        return [
          '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '26', '-pix_fmt', 'yuv420p', //
          '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart',
        ];
      case EncodeTarget.output:
        return finalEncodeArgs(format, o);
    }
  }

  /// Encoder settings for user-facing files.
  static List<String> finalEncodeArgs(OutputFormat format, OutputSettings o) {
    switch (format) {
      case OutputFormat.mp4:
        return [
          '-c:v', 'libx264', '-preset', o.quality.preset, '-crf', '${o.quality.crf}', //
          '-pix_fmt', 'yuv420p',
          '-c:a', 'aac', '-b:a', '${o.quality.audioKbps}k',
          '-movflags', '+faststart',
        ];
      case OutputFormat.webm:
        return [
          '-c:v', 'libvpx-vp9', '-crf', '${o.quality.crf + 12}', '-b:v', '0', //
          '-deadline', 'good', '-cpu-used', '4', '-row-mt', '1', '-pix_fmt', 'yuv420p',
          '-c:a', 'libopus', '-b:a', '${math.min(o.quality.audioKbps, 192)}k',
        ];
      case OutputFormat.gif:
        return ['-an', '-loop', '0'];
      case OutputFormat.mp3:
        return ['-vn', '-c:a', 'libmp3lame', '-b:a', '${math.max(o.quality.audioKbps, 192)}k'];
      case OutputFormat.wav:
        return ['-vn', '-c:a', 'pcm_s16le'];
    }
  }

  /// drawtext overlay in the top-left corner.
  static String overlayLabel(SegmentLabel label, int w, int h) {
    final len = math.max(4, label.text.runes.length);
    final size = math.max(10, math.min(h * 0.058, w * 0.88 / (len * 0.62))).round();
    final pad = math.max(4, (size * 0.45).round());
    return 'drawtext=fontfile=${label.fontFile}:textfile=${label.textFile}:expansion=none:'
        'fontsize=$size:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=$pad:'
        'x=${(w * 0.03).round() + pad}:y=${(h * 0.04).round() + pad}';
  }

  /// A standalone title card segment ("EFFECT 3 OF 40" / "G-Major 4").
  static BuiltCommand titleCard({
    required String outputPath,
    required int width,
    required int height,
    required double fps,
    required double seconds,
    required SegmentLabel kicker,
    required SegmentLabel title,
  }) {
    final titleLen = math.max(4, title.text.runes.length);
    final big = math.max(12, math.min(height * 0.12, width * 0.86 / (titleLen * 0.62))).round();
    final small = math.max(10, (height * 0.042).round());
    final gap = (height * 0.03).round();
    final barW = (width * 0.14).round();
    final barH = math.max(2, (height * 0.008).round());
    final graph =
        '[0:v]'
        'drawtext=fontfile=${kicker.fontFile}:textfile=${kicker.textFile}:expansion=none:'
        'fontsize=$small:fontcolor=0xA99BFF:x=(w-tw)/2:y=h/2-$big/2-$gap-$small,'
        'drawtext=fontfile=${title.fontFile}:textfile=${title.textFile}:expansion=none:'
        'fontsize=$big:fontcolor=white:x=(w-tw)/2:y=(h-$big)/2,'
        'drawbox=x=(iw-$barW)/2:y=ih/2+$big/2+$gap:w=$barW:h=$barH:color=0x7C5CFF:t=fill,'
        'format=yuv420p[v];'
        '[1:a]aformat=sample_fmts=fltp:sample_rates=$sampleRate:channel_layouts=stereo[a]';
    final args = <String>[
      ..._common,
      '-f', 'lavfi', '-i', 'color=c=0x0E0E12:s=${width}x$height:r=${fmt(fps)}:d=${fmt(seconds)}', //
      '-f', 'lavfi', '-t', fmt(seconds), '-i', 'anullsrc=channel_layout=stereo:sample_rate=$sampleRate',
      '-filter_complex', graph,
      '-map', '[v]', '-map', '[a]',
      ..._encodeArgs(EncodeTarget.segment, OutputFormat.mp4, const OutputSettings(), fps: fps),
      outputPath,
    ];
    return BuiltCommand(args, seconds, graph: graph);
  }

  /// Joins compilation segments listed in [listFile] into the final output.
  static BuiltCommand concat({
    required String listFile,
    required String outputPath,
    required OutputSettings output,
    required double totalSeconds,
    required double fps,
  }) {
    final format = output.format;
    final args = <String>[..._common, '-f', 'concat', '-safe', '0', '-i', listFile];
    if (format == OutputFormat.gif) {
      final gifFps = math.min(output.gifFps.toDouble(), fps);
      args.addAll([
        '-filter_complex',
        "[0:v]fps=${fmt(gifFps)},scale='min(iw,640)':-2:flags=lanczos,split[a][b];"
            '[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4[v]',
        '-map',
        '[v]',
      ]);
    } else {
      if (format.hasVideo) args.addAll(['-map', '0:v:0']);
      if (format.hasAudio) args.addAll(['-map', '0:a:0']);
    }
    args.addAll(['-max_muxing_queue_size', '4096', ...finalEncodeArgs(format, output), outputPath]);
    return BuiltCommand(args, totalSeconds);
  }

  /// Single JPEG frame of [effect] applied at [atSeconds] (effect browser
  /// thumbnails and the preview poster).
  static BuiltCommand thumbnail({
    required MediaInfo media,
    required Effect? effect,
    required ParamValues params,
    required double atSeconds,
    required String outputPath,
    int width = 320,
  }) {
    final window = math.min(1.0, math.max(0.1, media.duration - atSeconds));
    final (sw, sh) = scaledSize(media, null);
    final h = math.max(2, ((width * sh / sw) / 2).round() * 2);
    final env = FxEnv(width: width, height: h, fps: media.fps, duration: window, sampleRate: sampleRate);
    final g = FilterGraph();
    var v = g.v('0:v:0', 'scale=$width:$h,setsar=1,format=yuv420p');
    if (effect?.video != null) v = effect!.video!(g, v, effect.reader(params), env);
    v = g.v(v, 'scale=$width:$h:force_original_aspect_ratio=decrease,pad=$width:$h:(ow-iw)/2:(oh-ih)/2,format=yuv420p');
    final args = <String>[
      '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
      if (atSeconds > 0) ...['-ss', fmt(atSeconds)],
      '-t', fmt(window), '-i', media.path,
      '-filter_complex', g.build(),
      '-map', '[$v]',
      '-ss', fmt(math.min(0.5, window / 2)),
      '-frames:v', '1', '-q:v', '4', outputPath,
    ];
    return BuiltCommand(args, 0, graph: g.build());
  }
}
