import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../ffmpeg/ffmpeg_runner.dart';
import '../models/output_settings.dart';
import 'arranger.dart';
import 'base.dart';
import 'model.dart';

/// Visual styles for the remix video.
enum VisualPreset {
  classic('Classic grid', 'The traditional Sparta layout: a grid of lanes that flip on every hit'),
  modern('Modern', 'Clean spaced cards with punch-zoom and flash on hits'),
  chaos('Chaos / YTPMV', 'Big grids, pitch-coloured copies, mirrors and inverts'),
  minimal('Minimal', 'One full-frame view that cuts to whatever just played');

  const VisualPreset(this.label, this.blurb);
  final String label;
  final String blurb;
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

enum _Flip { none, alternate, always, vertical }

class _Look {
  const _Look({
    this.hue = 0,
    this.negate = false,
    this.mono = false,
    this.hueBySemitone = false,
    this.hueRandom = false,
  });
  final double hue;
  final bool negate;
  final bool mono;
  final bool hueBySemitone;
  final bool hueRandom;
}

class _Cell {
  const _Cell(
    this.x,
    this.y,
    this.w,
    this.h,
    this.lanes, {
    this.flip = _Flip.none,
    this.look = const _Look(),
    this.punch = false,
  });

  /// Fractions of the frame.
  final double x, y, w, h;
  final List<SampleRole> lanes;
  final _Flip flip;
  final _Look look;
  final bool punch;
}

class _Layout {
  const _Layout(this.cells, {this.gap = 0, this.background = '0x000000'});
  final List<_Cell> cells;

  /// Inset of each cell in pixels (at 720p; scaled with the frame).
  final double gap;
  final String background;
}

/// One variant clip: a sample's pictures at a rate/flip/look.
class _VariantKey {
  _VariantKey(
    this.role,
    this.variant,
    this.semitone,
    this.hflip,
    this.vflip,
    this.hue,
    this.negate,
    this.mono,
    this.punch,
    this.small,
  );
  final SampleRole role;
  final int variant;
  final int semitone;
  final bool hflip, vflip;
  final int hue;
  final bool negate, mono, punch, small;

  String get id =>
      '${role.name}_v${variant}_s${semitone}_${hflip ? 'h' : ''}${vflip ? 'v' : ''}_hue$hue'
      '${negate ? '_neg' : ''}${mono ? '_mono' : ''}${punch ? '_punch' : ''}${small ? '_sm' : ''}';

  @override
  bool operator ==(Object other) => other is _VariantKey && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class _Segment {
  _Segment(this.file, this.frames, {this.inFrames = 0});
  final String file;
  final int frames;
  final int inFrames;
}

/// Renders the remix video with FFmpeg: every chart hit cuts to (and
/// transposes) the source pictures of its sample, laid out per section.
class VisualRenderer {
  VisualRenderer({
    required this.ffmpegPath,
    required this.workDir,
    this.width = 1280,
    this.height = 720,
    this.fps = 30,
    this.concurrency = 3,
  }) : _runner = FfmpegRunner(ffmpegPath);

  final String ffmpegPath;
  final String workDir;
  final int width;
  final int height;
  final int fps;
  final int concurrency;
  final FfmpegRunner _runner;

  int get _smallW => (width / 2).round() ~/ 2 * 2;
  int get _smallH => (height / 2).round() ~/ 2 * 2;

  /// Renders the finished video (muxed with [masterAudioPath]) to [outputPath].
  Future<String> render({
    required SpartaBase base,
    required List<PlacedEvent> events,
    required Map<(SampleRole, int), VisualSource> sources,
    required VisualPreset preset,
    required String masterAudioPath,
    required double duration,
    required String outputPath,
    OutputSettings output = const OutputSettings(),
    int seed = 1,
    void Function(double fraction, String status)? onProgress,
    CancelToken? cancel,
  }) async {
    final dir = Directory(workDir);
    await dir.create(recursive: true);
    final rng = math.Random(seed);
    final totalFrames = (duration * fps).round();

    // Section spans on the frame grid (the last one runs to the end).
    final spans = <(int, int, Section, int)>[];
    for (var i = 0; i < base.sections.length; i++) {
      final s = base.sections[i];
      final a = (base.seconds(s.startBeat) * fps).round();
      final b = i == base.sections.length - 1 ? totalFrames : (base.seconds(s.endBeat) * fps).round();
      if (b > a) spans.add((a, math.min(b, totalFrames), s, i));
    }
    if (spans.isEmpty) spans.add((0, totalFrames, Section(SectionKind.other, 0, base.lengthBeats), 0));
    if (spans.first.$1 > 0) {
      final f = spans.first;
      spans[0] = (0, f.$2, f.$3, f.$4);
    }

    // Plan every cell track first, collecting the variant clips it needs.
    final variantFrames = <_VariantKey, int>{};
    final idleFrames = <String, int>{};
    final plans = <List<(_Cell, List<(Object, int, int)>)>>[];
    for (final (a, b, section, index) in spans) {
      final layout = _layoutFor(preset, section.kind, index);
      final cellPlans = <(_Cell, List<(Object, int, int)>)>[];
      for (final cell in layout.cells) {
        final small = cell.w <= 0.5 && cell.h <= 0.5;
        final lane = events.where((e) => cell.lanes.contains(e.role) && sources.containsKey((e.role, e.variant)));
        final evs = lane.where((e) => (e.start * fps).round() < b && (e.end * fps).round() > a).toList()
          ..sort((x, y) => x.start.compareTo(y.start));
        final items = <(Object, int, int)>[]; // (variant key | idle id, frames, inFrames)
        var cursor = a;
        final idleRole = cell.lanes.firstWhere(
          (r) => sources.keys.any((k) => k.$1 == r),
          orElse: () => cell.lanes.first,
        );
        final idleVariant = sources.keys
            .where((k) => k.$1 == idleRole)
            .map((k) => k.$2)
            .fold<int?>(null, (m, v) => m ?? v);
        String? idleId(int variant) =>
            sources.containsKey((idleRole, variant)) ? 'idle_${idleRole.name}_v$variant${small ? '_sm' : ''}' : null;
        var lastIdle = idleVariant == null ? null : idleId(idleVariant);
        void idle(int from, int to) {
          if (to <= from) return;
          final id = lastIdle ?? 'black';
          items.add((id, to - from, 0));
          idleFrames[id] = math.max(idleFrames[id] ?? 0, to - from);
        }

        for (var k = 0; k < evs.length; k++) {
          final e = evs[k];
          final start = (e.start * fps).round();
          var end = (e.end * fps).round();
          if (k + 1 < evs.length) end = math.min(end, (evs[k + 1].start * fps).round());
          final s0 = math.max(start, a), s1 = math.min(end, b);
          if (s1 <= s0) continue;
          idle(cursor, s0);
          final key = _variantFor(e, cell, small, rng);
          final inFrames = s0 - start;
          items.add((key, s1 - s0, inFrames));
          variantFrames[key] = math.max(variantFrames[key] ?? 0, inFrames + s1 - s0);
          cursor = s1;
          if (e.role == idleRole) lastIdle = idleId(e.variant) ?? lastIdle;
        }
        idle(cursor, b);
        cellPlans.add((cell, items));
      }
      plans.add(cellPlans);
    }

    final steps = sources.length + variantFrames.length + idleFrames.length + spans.length + 1;
    var done = 0;
    void step(String status) {
      done++;
      onProgress?.call(math.min(0.99, done / steps), status);
    }

    // 1. Base clips per sample (normalised to the frame size, 30 fps, intra).
    final baseClips = <(SampleRole, int), String>{};
    for (final entry in sources.entries) {
      final (role, variant) = entry.key;
      final out = p.join(workDir, 'src_${role.name}_v$variant.mkv');
      await _sourceClip(entry.value, out, cancel);
      baseClips[entry.key] = out;
      step('Cutting ${role.label.toLowerCase()} pictures');
    }

    // 2. Variants and idle stills.
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
    final idleFiles = <String, String>{};
    for (final e in idleFrames.entries) {
      final file = p.join(workDir, '${e.key}.mkv');
      idleFiles[e.key] = file;
      jobs.add(() async {
        await _idleClip(e.key, baseClips, e.value + 1, file, cancel);
        step('Building idle frames');
      });
    }
    await _pool(jobs, concurrency);

    // 3. Compose each section.
    final sectionFiles = <String>[];
    for (var i = 0; i < spans.length; i++) {
      final (a, b, section, index) = spans[i];
      final layout = _layoutFor(preset, section.kind, index);
      final cellTracks = <String>[];
      for (var c = 0; c < plans[i].length; c++) {
        final (_, items) = plans[i][c];
        final segs = [
          for (final (key, frames, inFrames) in items)
            _Segment(key is _VariantKey ? variantFiles[key]! : idleFiles[key as String]!, frames, inFrames: inFrames),
        ];
        final list = p.join(workDir, 'sec${i}_cell$c.ffconcat');
        await File(list).writeAsString(_concatList(segs));
        cellTracks.add(list);
      }
      final out = p.join(workDir, 'sec$i.mkv');
      await _composeSection(layout, cellTracks, b - a, out, cancel);
      sectionFiles.add(out);
      step('Composing ${section.title}');
    }

    // 4. Join sections and mux the master.
    final joined = p.join(workDir, 'sections.ffconcat');
    await File(joined).writeAsString('ffconcat version 1.0\n${sectionFiles.map((f) => "file '${_esc(f)}'\n").join()}');
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await _runner.run(
      [
        '-hide_banner', '-nostdin', '-y', '-progress', 'pipe:1', //
        '-f', 'concat', '-safe', '0', '-i', joined,
        '-i', masterAudioPath,
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

  // ---------------------------------------------------------------------------
  // Layouts
  // ---------------------------------------------------------------------------

  _Layout _layoutFor(VisualPreset preset, SectionKind kind, int sectionIndex) {
    const pitch = SampleRole.pitch, chop = SampleRole.chop, kick = SampleRole.kick;
    const snare = SampleRole.snare, hat = SampleRole.hat, quote = SampleRole.quote;
    List<_Cell> grid(
      int n,
      List<List<SampleRole>> lanes, {
      List<_Flip>? flips,
      List<_Look>? looks,
      bool punch = false,
    }) {
      final out = <_Cell>[];
      for (var i = 0; i < n * n; i++) {
        out.add(
          _Cell(
            (i % n) / n,
            (i ~/ n) / n,
            1 / n,
            1 / n,
            lanes[i % lanes.length],
            flip: flips == null ? _Flip.none : flips[i % flips.length],
            look: looks == null ? const _Look() : looks[i % looks.length],
            punch: punch,
          ),
        );
      }
      return out;
    }

    switch (preset) {
      case VisualPreset.minimal:
        return const _Layout([
          _Cell(0, 0, 1, 1, [quote, pitch, chop, snare, kick, hat], flip: _Flip.alternate),
        ]);
      case VisualPreset.classic || VisualPreset.modern:
        final punch = preset == VisualPreset.modern;
        final layout = switch (kind) {
          SectionKind.intro => [
            const _Cell(0, 0, 1, 1, [quote]),
            _Cell(0.66, 0.66, 0.34, 0.34, const [pitch], flip: _Flip.alternate, punch: punch),
          ],
          SectionKind.dundundenden => [
            _Cell(0, 0, 2 / 3, 1, const [pitch], flip: _Flip.alternate, punch: punch),
            _Cell(2 / 3, 0, 1 / 3, 0.5, const [kick], punch: punch),
            _Cell(2 / 3, 0.5, 1 / 3, 0.5, const [snare, hat], punch: punch),
          ],
          SectionKind.epicness => [
            _Cell(0, 0, 1, 1, const [pitch], flip: _Flip.alternate, punch: punch),
            _Cell(0.7, 0.7, 0.3, 0.3, const [snare, kick], punch: punch),
          ],
          SectionKind.madness => grid(
            3,
            const [
              [pitch], [chop], [pitch], //
              [kick], [pitch], [snare],
              [pitch], [hat, chop], [pitch],
            ],
            flips: const [
              _Flip.always, _Flip.alternate, _Flip.none, //
              _Flip.none, _Flip.alternate, _Flip.none,
              _Flip.vertical, _Flip.none, _Flip.alternate,
            ],
            looks: const [
              _Look(hue: 60), _Look(), _Look(hue: 180), //
              _Look(), _Look(), _Look(),
              _Look(hue: 300), _Look(), _Look(mono: true),
            ],
            punch: punch,
          ),
          SectionKind.awesomeness => [
            ...grid(
              2,
              const [
                [pitch],
              ],
              flips: const [_Flip.none, _Flip.always, _Flip.vertical, _Flip.alternate],
              looks: const [_Look(), _Look(hue: 90), _Look(hue: 180), _Look(hue: 270)],
              punch: punch,
            ),
            _Cell(0.3, 0.3, 0.4, 0.4, const [chop], flip: _Flip.alternate, punch: punch),
          ],
          _ => [
            _Cell(0, 0, 0.5, 0.5, const [pitch], flip: _Flip.alternate, punch: punch),
            _Cell(0.5, 0, 0.5, 0.5, const [chop], flip: _Flip.alternate, punch: punch),
            _Cell(0, 0.5, 0.5, 0.5, const [kick], punch: punch),
            _Cell(0.5, 0.5, 0.5, 0.5, const [snare, hat], punch: punch),
          ],
        };
        return _Layout(layout, gap: punch ? 10 : 0, background: punch ? '0x0d0f14' : '0x000000');
      case VisualPreset.chaos:
        final n = switch (kind) {
          SectionKind.madness || SectionKind.awesomeness => 4,
          SectionKind.intro || SectionKind.outro => 2,
          _ => 3,
        };
        if (kind == SectionKind.intro) {
          return const _Layout([
            _Cell(0, 0, 1, 1, [quote]),
            _Cell(0, 0, 0.3, 0.3, [pitch], flip: _Flip.alternate, look: _Look(hueBySemitone: true), punch: true),
          ]);
        }
        return _Layout(
          grid(
            n,
            const [
              [pitch],
              [chop, pitch],
              [snare],
              [pitch],
              [kick, hat],
              [pitch, chop],
              [pitch],
              [snare, kick],
            ],
            flips: const [_Flip.alternate, _Flip.always, _Flip.vertical, _Flip.alternate],
            looks: const [
              _Look(hueBySemitone: true),
              _Look(hueRandom: true),
              _Look(negate: true),
              _Look(hueBySemitone: true),
              _Look(hue: 180),
              _Look(hueRandom: true),
            ],
            punch: true,
          ),
          background: '0x100014',
        );
    }
  }

  _VariantKey _variantFor(PlacedEvent e, _Cell cell, bool small, math.Random rng) {
    var h = false, v = false;
    switch (cell.flip) {
      case _Flip.none:
        break;
      case _Flip.alternate:
        h = e.laneIndex.isOdd;
      case _Flip.always:
        h = true;
      case _Flip.vertical:
        v = true;
        h = e.laneIndex.isOdd;
    }
    var hue = cell.look.hue.round();
    if (cell.look.hueBySemitone) hue = (hue + ((e.semitone % 12) + 12) % 12 * 30) % 360;
    if (cell.look.hueRandom) hue = [0, 60, 120, 180, 240, 300][e.laneIndex % 6];
    final negate = cell.look.negate && e.role == SampleRole.snare;
    // Tonal hits are transposed pictures too; drums/quote play at 1×.
    final semi = e.role.isTonal ? e.semitone : 0;
    return _VariantKey(e.role, e.variant, semi, h, v, hue, negate, cell.look.mono, cell.punch, small);
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
    final w = k.small ? _smallW : width, h = k.small ? _smallH : height;
    final seconds = frames / fps;
    final filters = <String>[
      'setpts=(PTS-STARTPTS)/${rate.toStringAsFixed(6)}',
      'fps=$fps',
      'tpad=stop_mode=clone:stop_duration=${(seconds + 1).toStringAsFixed(3)}',
      'trim=end_frame=$frames',
      'scale=$w:$h',
      if (k.hflip) 'hflip',
      if (k.vflip) 'vflip',
      if (k.hue != 0) 'hue=h=${k.hue}',
      if (k.mono) 'hue=s=0',
      if (k.negate) 'negate',
      if (k.punch)
        "zoompan=z='if(lt(on,6),1.2-0.033*on,1)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${w}x$h:fps=$fps",
      if (k.punch) "eq=brightness='0.22*exp(-n/1.5)':eval=frame",
      'setsar=1',
      'format=yuvj420p',
    ];
    await _runner.run([
      '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
      '-i', src, '-an', '-vf', filters.join(','), '-c:v', 'mjpeg', '-q:v', '3', out,
    ], cancel: cancel);
  }

  Future<void> _idleClip(
    String id,
    Map<(SampleRole, int), String> clips,
    int frames,
    String out,
    CancelToken? cancel,
  ) async {
    final small = id.endsWith('_sm');
    final w = small ? _smallW : width, h = small ? _smallH : height;
    final seconds = (frames / fps).toStringAsFixed(3);
    if (id == 'black') {
      await _runner.run([
        '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
        '-f', 'lavfi', '-i', 'color=c=black:s=${w}x$h:r=$fps:d=$seconds',
        '-vf', 'format=yuvj420p', '-c:v', 'mjpeg', '-q:v', '3', out,
      ], cancel: cancel);
      return;
    }
    final m = RegExp(r'^idle_(\w+?)_v(\d+)').firstMatch(id)!;
    final role = SampleRole.values.byName(m.group(1)!);
    final src = clips[(role, int.parse(m.group(2)!))]!;
    await _runner.run([
      '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
      '-i', src, '-an', '-vf',
      'trim=end_frame=1,setpts=PTS-STARTPTS,fps=$fps,tpad=stop_mode=clone:stop_duration=$seconds,'
          'trim=end_frame=$frames,scale=$w:$h,eq=brightness=-0.22:saturation=0.45,setsar=1,format=yuvj420p',
      '-c:v', 'mjpeg', '-q:v', '3', out,
    ], cancel: cancel);
  }

  String _concatList(List<_Segment> segs) {
    final b = StringBuffer('ffconcat version 1.0\n');
    for (final s in segs) {
      b.writeln("file '${_esc(s.file)}'");
      if (s.inFrames > 0) b.writeln('inpoint ${(s.inFrames / fps).toStringAsFixed(6)}');
      b.writeln('outpoint ${((s.inFrames + s.frames - 0.5) / fps).toStringAsFixed(6)}');
      b.writeln('duration ${(s.frames / fps).toStringAsFixed(6)}');
    }
    return b.toString();
  }

  Future<void> _composeSection(_Layout layout, List<String> tracks, int frames, String out, CancelToken? cancel) async {
    final seconds = (frames / fps + 0.5).toStringAsFixed(3);
    final args = <String>[
      '-hide_banner', '-nostdin', '-y', '-loglevel', 'error', //
      '-f', 'lavfi', '-i', 'color=c=${layout.background}:s=${width}x$height:r=$fps:d=$seconds',
      for (final t in tracks) ...['-f', 'concat', '-safe', '0', '-i', t],
    ];
    final g = layout.gap * height / 720;
    final chains = <String>[];
    var last = '0:v';
    for (var i = 0; i < layout.cells.length; i++) {
      final c = layout.cells[i];
      final x = (c.x * width + g).round(), y = (c.y * height + g).round();
      final w = ((c.w * width - 2 * g).round() ~/ 2) * 2, h = ((c.h * height - 2 * g).round() ~/ 2) * 2;
      chains.add(
        '[${i + 1}:v]fps=$fps,setpts=PTS-STARTPTS,scale=$w:$h:force_original_aspect_ratio=increase,'
        'crop=$w:$h,setsar=1,format=yuv420p[c$i]',
      );
      final outLabel = i == layout.cells.length - 1 ? 'v' : 'b$i';
      chains.add('[$last][c$i]overlay=x=$x:y=$y:eof_action=pass:shortest=0[$outLabel]');
      last = outLabel;
    }
    if (layout.cells.isEmpty) chains.add('[0:v]null[v]');
    args.addAll([
      '-filter_complex',
      chains.join(';'),
      '-map',
      '[v]',
      '-frames:v',
      '$frames',
      '-r',
      '$fps',
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '15',
      '-pix_fmt',
      'yuv420p',
      '-g',
      '$fps',
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
