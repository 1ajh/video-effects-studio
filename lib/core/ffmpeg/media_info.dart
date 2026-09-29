import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// What we know about an input file.
class MediaInfo {
  const MediaInfo({
    required this.path,
    required this.duration,
    required this.hasVideo,
    required this.hasAudio,
    this.width = 0,
    this.height = 0,
    this.fps = 30,
    this.videoCodec,
    this.audioCodec,
    this.sampleRate,
    this.sizeBytes = 0,
  });

  final String path;

  /// Seconds.
  final double duration;
  final bool hasVideo;
  final bool hasAudio;

  /// Display size (rotation already applied).
  final int width;
  final int height;
  final double fps;
  final String? videoCodec;
  final String? audioCodec;
  final int? sampleRate;
  final int sizeBytes;

  String get fileName => p.basename(path);

  String get resolutionLabel => hasVideo ? '$width×$height' : 'audio';

  /// Parses `ffprobe -print_format json -show_format -show_streams` output.
  factory MediaInfo.fromProbeJson(String path, String json, {int sizeBytes = 0}) {
    final data = jsonDecode(json) as Map<String, Object?>;
    final streams = (data['streams'] as List? ?? const []).cast<Map<String, Object?>>();
    final format = (data['format'] as Map?)?.cast<String, Object?>() ?? const {};

    Map<String, Object?>? firstOf(String type) {
      for (final s in streams) {
        if (s['codec_type'] == type) {
          // Skip cover art / attached pictures.
          final disposition = (s['disposition'] as Map?)?.cast<String, Object?>();
          if (type == 'video' && disposition?['attached_pic'] == 1) continue;
          return s;
        }
      }
      return null;
    }

    final video = firstOf('video');
    final audio = firstOf('audio');

    double? parseDouble(Object? v) => v == null ? null : double.tryParse('$v');

    var duration =
        parseDouble(format['duration']) ?? parseDouble(video?['duration']) ?? parseDouble(audio?['duration']) ?? 0;
    if (duration.isNaN || duration < 0) duration = 0;

    var width = (video?['width'] as num?)?.toInt() ?? 0;
    var height = (video?['height'] as num?)?.toInt() ?? 0;
    if (video != null && _rotation(video) % 180 != 0) {
      final t = width;
      width = height;
      height = t;
    }

    return MediaInfo(
      path: path,
      duration: duration,
      hasVideo: video != null,
      hasAudio: audio != null,
      width: width,
      height: height,
      fps: _parseRate(video?['avg_frame_rate']) ?? _parseRate(video?['r_frame_rate']) ?? 30,
      videoCodec: video?['codec_name'] as String?,
      audioCodec: audio?['codec_name'] as String?,
      sampleRate: int.tryParse('${audio?['sample_rate']}'),
      sizeBytes: sizeBytes,
    );
  }

  /// Fallback parser for `ffmpeg -i file` banner output (when ffprobe is
  /// missing).
  factory MediaInfo.fromFfmpegBanner(String path, String stderr, {int sizeBytes = 0}) {
    final dur = RegExp(r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)').firstMatch(stderr);
    final duration = dur == null
        ? 0.0
        : int.parse(dur.group(1)!) * 3600 + int.parse(dur.group(2)!) * 60 + double.parse(dur.group(3)!);

    final videoLine = RegExp(
      r'Stream #\S+.*?Video: (.*)',
    ).allMatches(stderr).where((m) => !m.group(0)!.contains('attached pic'));
    final audioLine = RegExp(r'Stream #\S+.*?Audio: (.*)').firstMatch(stderr);
    final vl = videoLine.isEmpty ? null : videoLine.first.group(1);

    var width = 0, height = 0;
    double fps = 30;
    String? vcodec;
    if (vl != null) {
      vcodec = vl.split(RegExp(r'[\s,(]')).first;
      final size = RegExp(r'(\d{2,5})x(\d{2,5})').firstMatch(vl);
      if (size != null) {
        width = int.parse(size.group(1)!);
        height = int.parse(size.group(2)!);
      }
      final f = RegExp(r'([\d.]+) fps').firstMatch(vl) ?? RegExp(r'([\d.]+) tbr').firstMatch(vl);
      if (f != null) fps = double.tryParse(f.group(1)!) ?? 30;
      final rot = RegExp(r'rotation of (-?[\d.]+) degrees').firstMatch(stderr);
      if (rot != null && (double.parse(rot.group(1)!).round().abs() % 180) == 90) {
        final t = width;
        width = height;
        height = t;
      }
    }
    final al = audioLine?.group(1);
    return MediaInfo(
      path: path,
      duration: duration,
      hasVideo: vl != null,
      hasAudio: al != null,
      width: width,
      height: height,
      fps: fps,
      videoCodec: vcodec,
      audioCodec: al?.split(RegExp(r'[\s,(]')).first,
      sampleRate: al == null ? null : int.tryParse(RegExp(r'(\d+) Hz').firstMatch(al)?.group(1) ?? ''),
      sizeBytes: sizeBytes,
    );
  }

  static int _rotation(Map<String, Object?> stream) {
    final tags = (stream['tags'] as Map?)?.cast<String, Object?>();
    final tagRotate = int.tryParse('${tags?['rotate']}');
    if (tagRotate != null) return tagRotate.abs();
    final sideData = (stream['side_data_list'] as List?)?.cast<Map>();
    for (final sd in sideData ?? const <Map>[]) {
      final r = sd['rotation'];
      if (r is num) return r.round().abs();
    }
    return 0;
  }

  static double? _parseRate(Object? v) {
    if (v is! String || v.isEmpty) return null;
    final parts = v.split('/');
    final num = double.tryParse(parts.first);
    final den = parts.length > 1 ? double.tryParse(parts[1]) : 1.0;
    if (num == null || den == null || den == 0 || num == 0) return null;
    final r = num / den;
    return r.isFinite && r > 0 && r < 1000 ? r : null;
  }

  static Future<int> fileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }
}
