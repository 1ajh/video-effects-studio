import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../ffmpeg/ffmpeg_runner.dart';
import '../models/output_settings.dart';
import 'arranger.dart';
import 'model.dart';

/// Overall look of the remix video. Every style is a grid of boxes, one per
/// sample, so every sample is always on screen.
enum VisualStyle {
  classic('Classic', 'The Sparta remix look everyone knows: a box per sample that flips on every hit'),
  modern('Modern', 'Spaced boxes with a punch-zoom and flash on hits'),
  chaos('Chaos / YTPMV', 'Pitch-coloured boxes, vertical flips and inverted snares'),
  minimal('Minimal', 'One full-frame picture that cuts to whatever just played');

  const VisualStyle(this.label, this.blurb);
  final String label;
  final String blurb;
}

enum GridSize {
  auto('Auto', 'By how many samples there are (2 × 2, 3 × 3 or 4 × 4)', 0),
  two('2 × 2', 'Four boxes', 2),
  three('3 × 3', 'Nine boxes', 3),
  four('4 × 4', 'Sixteen boxes', 4);

  const GridSize(this.label, this.blurb, this.n);
  final String label;
  final String blurb;

  /// Boxes per side (0: automatic).
  final int n;

  int sideFor(int boxes) {
    if (n > 0) return n;
    if (boxes <= 4) return 2;
    if (boxes <= 9) return 3;
    return 4;
  }
}

/// Which boxes flip on alternate hits, and how.
enum FlipMode {
  horizontal('Horizontal, every box'),
  pitchOnly('Horizontal, pitch only'),
  wordsOnly('Horizontal, chorus words only'),
  pitchAndWords('Horizontal, pitch and words'),
  vertical('Vertical, every box'),
  both('Horizontal + vertical, every box'),
  none('No flips');

  const FlipMode(this.label);
  final String label;

  bool appliesTo(SampleRole r) => switch (this) {
    FlipMode.pitchOnly => r == SampleRole.pitch,
    FlipMode.wordsOnly => r == SampleRole.word,
    FlipMode.pitchAndWords => r == SampleRole.pitch || r == SampleRole.word,
    FlipMode.none => false,
    _ => true,
  };
}

/// What a box shows between hits.
enum IdleBox {
  black('Black'),
  dimmed('Last frame, dimmed'),
  hold('Last frame');

  const IdleBox(this.label);
  final String label;
}

/// How the quote is shown.
enum IntroVisual {
  fullScreen('Full-screen quote', 'The quote fills the screen while it plays'),
  box('Its own box', 'The quote gets a box in the grid like every other sample'),
  titleCard('Title card', "The remix's title over black while the quote plays");

  const IntroVisual(this.label, this.blurb);
  final String label;
  final String blurb;
}

class VisualOptions {
  const VisualOptions({
    this.style = VisualStyle.classic,
    this.grid = GridSize.auto,
    this.flip = FlipMode.horizontal,
    this.idle = IdleBox.black,
    this.intro = IntroVisual.fullScreen,
  });

  final VisualStyle style;
  final GridSize grid;
  final FlipMode flip;
  final IdleBox idle;
  final IntroVisual intro;

  VisualOptions copyWith({VisualStyle? style, GridSize? grid, FlipMode? flip, IdleBox? idle, IntroVisual? intro}) =>
      VisualOptions(
        style: style ?? this.style,
        grid: grid ?? this.grid,
        flip: flip ?? this.flip,
        idle: idle ?? this.idle,
        intro: intro ?? this.intro,
      );

  Map<String, Object?> toJson() => {
    'style': style.name,
    'grid': grid.name,
    'flip': flip.name,
    'idle': idle.name,
    'intro': intro.name,
  };

  factory VisualOptions.fromJson(Map<String, Object?> j) => VisualOptions(
    style: VisualStyle.values.asNameMap()[j['style']] ?? VisualStyle.classic,
    grid: GridSize.values.asNameMap()[j['grid']] ?? GridSize.auto,
    flip: FlipMode.values.asNameMap()[j['flip']] ?? FlipMode.horizontal,
    idle: IdleBox.values.asNameMap()[j['idle']] ?? IdleBox.black,
    intro: IntroVisual.values.asNameMap()[j['intro']] ?? IntroVisual.fullScreen,
  );
}

/// Where the pictures for one sample come from.
class VisualSource {
  const VisualSource({required this.path, required this.hasVideo, required this.start, required this.duration});

  final String path;
  final bool hasVideo;

  /// Region of [path] the sample was cut from (seconds).
  final double start;
  final double duration;
}

/// One box of the grid: the samples it shows.
class VisualBox {
  const VisualBox(this.role, {this.word = 0});
  final SampleRole role;

  /// Word boxes: the word number (its syllables share the box).
  final int word;

  String get label => role == SampleRole.word ? 'Word $word' : role.label;

  bool shows(PlacedEvent e) {
    if (e.role != role) return false;
    if (role != SampleRole.word) return true;
    return wordNumber(e.slot) == word;
  }

  static int wordNumber(String slot) => int.tryParse(RegExp(r'^\d+').stringMatch(slot) ?? '') ?? 1;

  @override
  bool operator ==(Object other) => other is VisualBox && other.role == role && other.word == word;
  @override
  int get hashCode => Object.hash(role, word);
}

/// The boxes a remix needs: pitch, each chorus word, kick, snare, hat (and
/// the quote when it has its own box), in that order.
List<VisualBox> boxesFor(List<PlacedEvent> events, VisualOptions o) {
  final roles = events.map((e) => e.role).toSet();
  final words = {for (final e in events.where((e) => e.role == SampleRole.word)) VisualBox.wordNumber(e.slot)}.toList()
    ..sort();
  return [
    if (roles.contains(SampleRole.pitch)) const VisualBox(SampleRole.pitch),
    for (final w in words) VisualBox(SampleRole.word, word: w),
    for (final r in const [SampleRole.kick, SampleRole.snare, SampleRole.hat])
      if (roles.contains(r)) VisualBox(r),
    if (o.intro == IntroVisual.box && roles.contains(SampleRole.quote)) const VisualBox(SampleRole.quote),
  ];
}

/// One variant clip: a sample's pictures at a rate / flip / look and size.
class _VariantKey {
  _VariantKey(
    this.role,
    this.variant,
    this.semitone,
    this.hflip,
    this.vflip,
    this.hue,
    this.negate,
    this.punch,
    this.w,
    this.h, {
    this.dim = false,
  });
  final SampleRole role;
  final int variant;
  final int semitone;
  final bool hflip, vflip;
  final int hue;
  final bool negate, punch;
  final int w, h;
  final bool dim;

  _VariantKey dimmed() => _VariantKey(role, variant, semitone, hflip, vflip, hue, negate, false, w, h, dim: true);

  String get id =>
      '${role.name}_v${variant}_s${semitone}_${hflip ? 'h' : ''}${vflip ? 'v' : ''}_hue$hue'
      '${negate ? '_neg' : ''}${punch ? '_punch' : ''}${dim ? '_dim' : ''}_${w}x$h';

  @override
  bool operator ==(Object other) => other is _VariantKey && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A piece of a box's track: [content] frames of [file] from [inFrames],
/// held (the last frame repeats) for [frames] in total.
class _Segment {
  _Segment(this.file, this.frames, {this.inFrames = 0, int? content}) : content = content ?? frames;
  final String file;
  final int frames;
  final int inFrames;
  final int content;
}

/// Renders the remix video with FFmpeg: every hit cuts its box to (and
/// transposes) the pictures of its sample.
class VisualRenderer {
  VisualRenderer({
    required this.ffmpegPath,
    required this.workDir,
    this.width = 1280,
    this.height = 720,
    this.fps = 30,
    this.concurrency = 3,
    this.fontPath,
  }) : _runner = FfmpegRunner(ffmpegPath);

  final String ffmpegPath;
  final String workDir;
  final int width;
  final int height;
  final int fps;
  final int concurrency;

  /// Font for the title card (without one the quote is shown instead).
  final String? fontPath;
  final FfmpegRunner _runner;

  /// Renders the finished video (muxed with [masterAudioPath]) to [outputPath].
  Future<String> render({
    required List<PlacedEvent> events,
    required Map<(SampleRole, int), VisualSource> sources,
    required String masterAudioPath,
    required double duration,
    required String outputPath,
    VisualOptions options = const VisualOptions(),
    String title = '',
    OutputSettings output = const OutputSettings(),
    void Function(double fraction, String status)? onProgress,
    CancelToken? cancel,
  }) async {
    await Directory(workDir).create(recursive: true);
    final totalFrames = math.max(1, (duration * fps).round());
    final visible = events.where((e) => sources.containsKey((e.role, e.variant))).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // Layout -----------------------------------------------------------------
    final minimal = options.style == VisualStyle.minimal;
    final boxes = minimal ? const <VisualBox>[] : boxesFor(visible, options);
    final n = minimal ? 1 : options.grid.sideFor(boxes.length);
    final cells = n * n;
    final gap = options.style == VisualStyle.modern ? (8 * height / 720).round() : 0;
    final cellW = (((width / n) - 2 * gap).round() ~/ 2) * 2;
    final cellH = (((height / n) - 2 * gap).round() ~/ 2) * 2;
    var intro = options.intro;
    if (intro == IntroVisual.titleCard && (fontPath == null || title.trim().isEmpty)) intro = IntroVisual.fullScreen;
    bool onTop(PlacedEvent e) => e.role == SampleRole.quote && intro != IntroVisual.box && !minimal;

    // Which cell shows each event (extra boxes share the last cell).
    int cellOf(PlacedEvent e) {
      if (minimal) return 0;
      final i = boxes.indexWhere((b) => b.shows(e));
      return i < 0 ? -1 : math.min(i, cells - 1);
    }

    // Plan every cell's track, collecting the variant clips it needs.
    final variantFrames = <_VariantKey, int>{};
    final plans = <List<(Object, int, int, int)>>[]; // (variant | 'black', frames, inFrames, content)
    final hitCount = <int, int>{};
    for (var c = 0; c < cells; c++) {
      final evs = visible.where((e) => !onTop(e) && cellOf(e) == c).toList();
      final items = <(Object, int, int, int)>[];
      var cursor = 0;
      _VariantKey? last;
      var lastEnd = 0; // frame index (within the variant) where the last hit stopped
      void idle(int to) {
        if (to <= cursor) return;
        final frames = to - cursor;
        if (last == null || options.idle == IdleBox.black) {
          items.add(('black', frames, 0, 1));
        } else if (options.idle == IdleBox.hold && items.isNotEmpty && items.last.$1 == last) {
          // Stretch the last hit: its final frame holds.
          final prev = items.removeLast();
          items.add((prev.$1, prev.$2 + frames, prev.$3, prev.$4));
        } else {
          final key = options.idle == IdleBox.dimmed ? last.dimmed() : last;
          final at = math.max(0, lastEnd - 1);
          items.add((key, frames, at, 1));
          variantFrames[key] = math.max(variantFrames[key] ?? 0, at + 1);
        }
        cursor = to;
      }

      for (var k = 0; k < evs.length; k++) {
        final e = evs[k];
        final start = (e.start * fps).round();
        var end = (e.end * fps).round();
        if (k + 1 < evs.length) end = math.min(end, (evs[k + 1].start * fps).round());
        final s0 = math.max(start, cursor), s1 = math.min(end, totalFrames);
        if (s1 <= s0) continue;
        idle(s0);
        final index = hitCount[c] = (hitCount[c] ?? -1) + 1;
        final key = _variantFor(e, index, options, minimal ? width : cellW, minimal ? height : cellH);
        final inFrames = s0 - start;
        items.add((key, s1 - s0, inFrames, s1 - s0));
        variantFrames[key] = math.max(variantFrames[key] ?? 0, inFrames + s1 - s0);
        cursor = s1;
        last = key;
        lastEnd = inFrames + s1 - s0;
      }
      idle(totalFrames);
      plans.add(items);
    }

    // The quote over everything (full screen or as a title card).
    final topEvents = visible.where(onTop).toList();
    final topKeys = <_VariantKey>[];
    for (final e in topEvents) {
      final key = _VariantKey(e.role, e.variant, 0, false, false, 0, false, false, width, height);
      topKeys.add(key);
      final frames = math.max(1, (e.duration * fps).round());
      variantFrames[key] = math.max(variantFrames[key] ?? 0, frames);
    }

    final usedSources = {for (final k in variantFrames.keys) (k.role, k.variant)};
    final steps = usedSources.length + variantFrames.length + 3;
    var done = 0;
    void step(String status) {
      done++;
      onProgress?.call(math.min(0.99, done / steps), status);
    }

    // 1. Base clips per sample (normalised to the frame size, intra-coded).
    final baseClips = <(SampleRole, int), String>{};
    for (final key in usedSources) {
      final (role, variant) = key;
      final out = p.join(workDir, 'src_${role.name}_v$variant.mkv');
      await _sourceClip(sources[key]!, out, cancel);
      baseClips[key] = out;
      step('Cutting ${role.label.toLowerCase()} pictures');
    }

    // 2. Variants.
    final variantFiles = <_VariantKey, String>{};
    final jobs = <Future<void> Function()>[];
    for (final e in variantFrames.entries) {
      final key = e.key;
      final file = p.join(workDir, 'var_${key.id}.mkv');
      variantFiles[key] = file;
      jobs.add(() async {
        await _variantClip(baseClips[(key.role, key.variant)]!, key, e.value + 1, file, cancel);
        step('Building hit variants');
      });
    }
    await _pool(jobs, concurrency);
    final black = p.join(workDir, 'black_${cellW}x$cellH.mkv');
    await _blackClip(minimal ? width : cellW, minimal ? height : cellH, black, cancel);

    // 3. Compose the grid (and the quote on top).
    final tracks = <String>[];
    for (var c = 0; c < plans.length; c++) {
      final segs = [
        for (final (key, frames, inFrames, content) in plans[c])
          _Segment(
            key is _VariantKey ? variantFiles[key]! : black,
            frames,
            inFrames: key is _VariantKey ? inFrames : 0,
            content: content,
          ),
      ];
      final list = p.join(workDir, 'cell$c.ffconcat');
      await File(list).writeAsString(_concatList(segs));
      tracks.add(list);
    }
    final overlays = <(String, double, double)>[];
    for (var i = 0; i < topEvents.length; i++) {
      final e = topEvents[i];
      final file = intro == IntroVisual.titleCard
          ? await _titleCard(title, e.duration, p.join(workDir, 'title_$i.mkv'), cancel)
          : variantFiles[topKeys[i]]!;
      overlays.add((file, e.start, e.duration));
    }
    final composed = p.join(workDir, 'grid.mkv');
    await _compose(
      tracks,
      n: n,
      gap: gap,
      cellW: minimal ? width : cellW,
      cellH: minimal ? height : cellH,
      frames: totalFrames,
      background: switch (options.style) {
        VisualStyle.modern => '0x0d0f14',
        VisualStyle.chaos => '0x100014',
        _ => '0x000000',
      },
      overlays: overlays,
      out: composed,
      cancel: cancel,
    );
    step('Composing the boxes');

    // 4. Encode with the master.
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await _runner.run(
      [
        '-hide_banner', '-nostdin', '-y', '-progress', 'pipe:1', //
        '-i', composed, '-i', masterAudioPath,
        ..._encodeArgs(output, duration),
        outputPath,
      ],
      expectedSeconds: duration,
      onProgress: (f) => onProgress?.call(math.min(0.995, (done + f) / steps), 'Encoding video'),
      cancel: cancel,
    );
    onProgress?.call(1, 'Done');
    return outputPath;
  }

  _VariantKey _variantFor(PlacedEvent e, int hitIndex, VisualOptions o, int w, int h) {
    var hf = false, vf = false;
    if (o.flip.appliesTo(e.role)) {
      switch (o.flip) {
        case FlipMode.vertical:
          vf = hitIndex.isOdd;
        case FlipMode.both:
          // none, horizontal, both, vertical, …
          final k = hitIndex % 4;
          hf = k == 1 || k == 2;
          vf = k == 2 || k == 3;
        case FlipMode.none:
          break;
        default:
          hf = hitIndex.isOdd;
      }
    }
    var hue = 0;
    var negate = false;
    if (o.style == VisualStyle.chaos) {
      hue = e.role == SampleRole.pitch
          ? ((e.semitone % 12) + 12) % 12 * 30
          : const [0, 60, 120, 180, 240, 300][hitIndex % 6];
      negate = e.role == SampleRole.snare && hitIndex.isOdd;
    }
    // Pitched hits are transposed pictures too; words, drums and the quote
    // play at 1×.
    final semi = e.role == SampleRole.pitch ? e.semitone : 0;
    return _VariantKey(e.role, e.variant, semi, hf, vf, hue, negate, o.style == VisualStyle.modern, w, h);
  }

  // ---------------------------------------------------------------------------
  // FFmpeg steps
  // ---------------------------------------------------------------------------

  Future<void> _sourceClip(VisualSource s, String out, CancelToken? cancel) async {
    if (await File(out).exists()) return;
    final dur = math.max(0.1, math.min(s.duration, 12.0));
    final List<String> args;
    if (s.hasVideo) {
      args = [
        '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
        '-ss', s.start.toStringAsFixed(3), '-t', dur.toStringAsFixed(3), '-i', s.path,
        '-an', '-vf',
        'fps=$fps,scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height,setsar=1,format=yuvj420p',
        '-c:v', 'mjpeg', '-q:v', '3', out,
      ];
    } else {
      // Audio-only source: an animated waveform card.
      args = [
        '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
        '-ss', s.start.toStringAsFixed(3), '-t', dur.toStringAsFixed(3), '-i', s.path,
        '-filter_complex',
        '[0:a]aformat=channel_layouts=mono,showwaves=s=${width}x$height:mode=cline:rate=$fps:colors=0x9ab8ff,'
            'format=yuv420p[w];color=c=0x141824:s=${width}x$height:r=$fps[bg];'
            '[bg][w]overlay=shortest=1,format=yuvj420p[v]',
        '-map', '[v]', '-c:v', 'mjpeg', '-q:v', '3', out,
      ];
    }
    await _runner.run(args, cancel: cancel);
  }

  Future<void> _variantClip(String src, _VariantKey k, int frames, String out, CancelToken? cancel) async {
    final rate = math.pow(2, k.semitone / 12).toDouble();
    final seconds = frames / fps;
    final filters = <String>[
      'setpts=(PTS-STARTPTS)/${rate.toStringAsFixed(6)}',
      'fps=$fps',
      'tpad=stop_mode=clone:stop_duration=${(seconds + 1).toStringAsFixed(3)}',
      'trim=end_frame=$frames',
      'scale=${k.w}:${k.h}',
      if (k.hflip) 'hflip',
      if (k.vflip) 'vflip',
      if (k.hue != 0) 'hue=h=${k.hue}',
      if (k.negate) 'negate',
      if (k.dim) 'eq=brightness=-0.22:saturation=0.45',
      if (k.punch)
        "zoompan=z='if(lt(on,6),1.2-0.033*on,1)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${k.w}x${k.h}:fps=$fps",
      if (k.punch) "eq=brightness='0.22*exp(-n/1.5)':eval=frame",
      'setsar=1',
      'format=yuvj420p',
    ];
    await _runner.run([
      '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
      '-i', src, '-an', '-vf', filters.join(','), '-c:v', 'mjpeg', '-q:v', '3', out,
    ], cancel: cancel);
  }

  Future<void> _blackClip(int w, int h, String out, CancelToken? cancel) => _runner.run([
    '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
    '-f', 'lavfi', '-i', 'color=c=black:s=${w}x$h:r=$fps:d=${(2 / fps).toStringAsFixed(4)}',
    '-vf', 'format=yuvj420p', '-c:v', 'mjpeg', '-q:v', '3', out,
  ], cancel: cancel);

  Future<String> _titleCard(String title, double seconds, String out, CancelToken? cancel) async {
    // Relative names (run from the work folder) keep drawtext's escaping simple.
    final dir = p.dirname(out);
    final font = File(p.join(dir, 'title_font${p.extension(fontPath!)}'));
    if (!await font.exists()) await File(fontPath!).copy(font.path);
    final textName = '${p.basenameWithoutExtension(out)}.txt';
    await File(p.join(dir, textName)).writeAsString(title.trim());
    final len = math.max(4, title.trim().runes.length);
    final size = math.max(14, math.min(height * 0.11, width * 0.86 / (len * 0.62))).round();
    await _runner.run(
      [
        '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
        '-f', 'lavfi', '-i', 'color=c=black:s=${width}x$height:r=$fps:d=${math.max(0.1, seconds).toStringAsFixed(3)}',
        '-vf',
        'drawtext=fontfile=${p.basename(font.path)}:textfile=$textName:expansion=none:fontsize=$size:'
            'fontcolor=white:x=(w-tw)/2:y=(h-th)/2,format=yuvj420p',
        '-c:v', 'mjpeg', '-q:v', '3', p.basename(out),
      ],
      workingDirectory: dir,
      cancel: cancel,
    );
    return out;
  }

  String _concatList(List<_Segment> segs) {
    final b = StringBuffer('ffconcat version 1.0\n');
    for (final s in segs) {
      b.writeln("file '${_esc(s.file)}'");
      if (s.inFrames > 0) b.writeln('inpoint ${(s.inFrames / fps).toStringAsFixed(6)}');
      b.writeln('outpoint ${((s.inFrames + s.content - 0.5) / fps).toStringAsFixed(6)}');
      // A longer duration than the content leaves a gap the fps filter fills
      // with the last frame (how idle boxes hold their picture).
      b.writeln('duration ${(s.frames / fps).toStringAsFixed(6)}');
    }
    return b.toString();
  }

  Future<void> _compose(
    List<String> tracks, {
    required int n,
    required int gap,
    required int cellW,
    required int cellH,
    required int frames,
    required String background,
    required List<(String, double, double)> overlays,
    required String out,
    CancelToken? cancel,
  }) async {
    final seconds = (frames / fps + 0.5).toStringAsFixed(3);
    final args = <String>[
      '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
      '-f', 'lavfi', '-i', 'color=c=$background:s=${width}x$height:r=$fps:d=$seconds',
      for (final t in tracks) ...['-f', 'concat', '-safe', '0', '-i', t],
      for (final o in overlays) ...['-i', o.$1],
    ];
    final chains = <String>[];
    var last = '0:v';
    for (var i = 0; i < tracks.length; i++) {
      final col = i % n, row = i ~/ n;
      final x = (col * width / n + gap).round(), y = (row * height / n + gap).round();
      chains.add('[${i + 1}:v]fps=$fps,setpts=PTS-STARTPTS,scale=$cellW:$cellH,setsar=1,format=yuv420p[c$i]');
      chains.add('[$last][c$i]overlay=x=$x:y=$y:eof_action=pass:shortest=0[b$i]');
      last = 'b$i';
    }
    for (var i = 0; i < overlays.length; i++) {
      final (_, start, dur) = overlays[i];
      final input = tracks.length + 1 + i;
      final a = start.toStringAsFixed(4), z = (start + dur).toStringAsFixed(4);
      chains.add('[$input:v]fps=$fps,setpts=PTS-STARTPTS+$a/TB,scale=$width:$height,setsar=1,format=yuv420p[q$i]');
      chains.add("[$last][q$i]overlay=0:0:eof_action=pass:enable='between(t,$a,$z)'[o$i]");
      last = 'o$i';
    }
    chains.add('[$last]null[v]');
    args.addAll([
      '-filter_complex', chains.join(';'), //
      '-map', '[v]', '-frames:v', '$frames', '-r', '$fps',
      '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '15', '-pix_fmt', 'yuv420p', '-g', '$fps',
      out,
    ]);
    await _runner.run(args, cancel: cancel);
  }

  List<String> _encodeArgs(OutputSettings o, double duration) {
    final cap = o.resolution.maxHeight;
    final scale = cap != null && cap < height ? 'scale=-2:$cap' : null;
    switch (o.format) {
      case OutputFormat.webm:
        return [
          '-map', '0:v', '-map', '1:a', //
          if (scale != null) ...['-vf', scale],
          '-c:v', 'libvpx-vp9', '-crf', '${o.quality.crf + 12}', '-b:v', '0', '-row-mt', '1', '-deadline', 'good',
          '-cpu-used', '4', '-c:a', 'libopus', '-b:a', '${o.quality.audioKbps}k', '-t', duration.toStringAsFixed(3),
        ];
      case OutputFormat.gif:
        return [
          '-map', '0:v', //
          '-filter_complex',
          '[0:v]fps=${o.gifFps},scale=-2:${math.min(cap ?? 360, 480)}:flags=lanczos,split[a][b];'
              '[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4',
          '-t', duration.toStringAsFixed(3),
        ];
      case OutputFormat.mp3 || OutputFormat.wav:
        return [
          '-map', '1:a', '-vn', //
          if (o.format == OutputFormat.mp3) ...['-c:a', 'libmp3lame', '-b:a', '${o.quality.audioKbps}k'],
          if (o.format == OutputFormat.wav) ...['-c:a', 'pcm_s16le'],
        ];
      case OutputFormat.mp4:
        return [
          '-map', '0:v', '-map', '1:a', //
          if (scale != null) ...['-vf', scale],
          '-c:v', 'libx264', '-preset', o.quality.preset, '-crf', '${o.quality.crf}', '-pix_fmt', 'yuv420p',
          '-c:a', 'aac', '-b:a', '${o.quality.audioKbps}k', '-movflags', '+faststart',
          '-t', duration.toStringAsFixed(3),
        ];
    }
  }

  static String _esc(String path) => path.replaceAll(r'\', '/').replaceAll("'", r"'\''");

  static Future<void> _pool(List<Future<void> Function()> jobs, int n) async {
    var next = 0;
    Future<void> worker() async {
      while (next < jobs.length) {
        final job = jobs[next++];
        await job();
      }
    }

    await Future.wait([for (var i = 0; i < math.max(1, n); i++) worker()]);
  }
}
