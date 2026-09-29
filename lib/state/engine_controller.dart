import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/ffmpeg/ffmpeg_toolkit.dart';
import '../core/render/render_engine.dart';

enum EngineStatus { detecting, ready, missing }

/// Owns FFmpeg discovery and the [RenderEngine].
class EngineController extends ChangeNotifier {
  EngineStatus _status = EngineStatus.detecting;
  FfmpegToolkit? _toolkit;
  RenderEngine? _engine;
  String? _fontPath;
  late String _cacheDir;

  EngineStatus get status => _status;
  FfmpegToolkit? get toolkit => _toolkit;
  RenderEngine? get engine => _engine;
  bool get ready => _status == EngineStatus.ready;

  /// Label font copied out of the asset bundle (FFmpeg needs a real file).
  String? get fontPath => _fontPath;

  /// Scratch space for previews and thumbnails.
  String get cacheDir => _cacheDir;

  /// Filters every built-in effect depends on.
  static const requiredFilters = [
    'afftfilt', 'amix', 'asetrate', 'atempo', 'asoftclip', 'acrusher', 'chorus', //
    'geq', 'hue', 'negate', 'colorchannelmixer', 'lutrgb', 'pseudocolor', 'gblur',
    'blend', 'hstack', 'vstack', 'xstack', 'rotate', 'lagfun', 'tmix', 'drawtext',
  ];

  List<String> get missingFilters => _toolkit?.missingFilters(requiredFilters) ?? const [];

  Future<void> init({String? ffmpegOverride}) async {
    _cacheDir = p.join(Directory.systemTemp.path, 'video_effects_studio_cache');
    await _prepareCache();
    await _extractFont();
    await detect(ffmpegOverride: ffmpegOverride);
  }

  Future<void> detect({String? ffmpegOverride}) async {
    _status = EngineStatus.detecting;
    notifyListeners();
    _toolkit = await FfmpegToolkit.locate(overridePath: ffmpegOverride);
    _engine = _toolkit == null ? null : RenderEngine(_toolkit!);
    _status = _toolkit == null ? EngineStatus.missing : EngineStatus.ready;
    notifyListeners();
  }

  Future<void> _prepareCache() async {
    final dir = Directory(_cacheDir);
    try {
      if (await dir.exists()) {
        // Drop previews/thumbnails older than a day.
        final cutoff = DateTime.now().subtract(const Duration(days: 1));
        await for (final f in dir.list()) {
          if (f is File && (await f.lastModified()).isBefore(cutoff)) await f.delete();
        }
      } else {
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> clearCache() async {
    try {
      await Directory(_cacheDir).delete(recursive: true);
    } catch (_) {}
    await Directory(_cacheDir).create(recursive: true);
  }

  Future<void> _extractFont() async {
    try {
      final support = await getApplicationSupportDirectory();
      final file = File(p.join(support.path, 'Inter-ExtraBold.ttf'));
      if (!await file.exists()) {
        final data = await rootBundle.load('assets/fonts/Inter-ExtraBold.ttf');
        await file.create(recursive: true);
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
      _fontPath = file.path;
    } catch (_) {
      _fontPath = null;
    }
  }
}
