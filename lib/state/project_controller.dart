import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/ffmpeg/media_info.dart';
import 'engine_controller.dart';

const videoExtensions = {
  'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi', 'wmv', 'flv', 'mpg', 'mpeg', 'ts', 'mts', '3gp', 'gif', //
  'mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac', 'opus',
};

bool isMediaFile(String path) => videoExtensions.contains(p.extension(path).replaceFirst('.', '').toLowerCase());

/// A clip loaded into the project.
class SourceClip {
  SourceClip(this.path);

  final String path;
  MediaInfo? info;
  String? error;
  bool probing = true;
  double trimStart = 0;
  double? trimEnd;

  String get name => p.basename(path);
  double get duration => info?.duration ?? 0;
  double get effectiveEnd => (trimEnd ?? duration).clamp(0, duration).toDouble();
  double get trimmedLength => (effectiveEnd - trimStart).clamp(0, duration).toDouble();
  bool get isTrimmed => trimStart > 0.001 || (trimEnd != null && trimEnd! < duration - 0.001);
}

/// The clips being worked on and their trim ranges.
class ProjectController extends ChangeNotifier {
  ProjectController(this._engine);

  final EngineController _engine;
  final List<SourceClip> _sources = [];
  int _active = -1;

  List<SourceClip> get sources => List.unmodifiable(_sources);
  SourceClip? get active => _active >= 0 && _active < _sources.length ? _sources[_active] : null;
  int get activeIndex => _active;
  bool get isEmpty => _sources.isEmpty;

  /// Adds media files, ignoring duplicates and non-media. Returns how many
  /// were added.
  int addFiles(Iterable<String> paths) {
    var added = 0;
    for (final path in paths) {
      if (!isMediaFile(path)) continue;
      if (_sources.any((s) => s.path == path)) continue;
      final clip = SourceClip(path);
      _sources.add(clip);
      added++;
      _probe(clip);
    }
    if (added > 0) {
      _active = _sources.length - added;
      notifyListeners();
    }
    return added;
  }

  Future<void> _probe(SourceClip clip) async {
    final engine = _engine.engine;
    if (engine == null) {
      clip
        ..probing = false
        ..error = 'FFmpeg not available';
      notifyListeners();
      return;
    }
    try {
      clip.info = await engine.probe(clip.path);
      if (clip.info!.duration <= 0) clip.error = 'Could not read the duration of this file';
    } catch (e) {
      clip.error = '$e';
    }
    clip.probing = false;
    notifyListeners();
  }

  /// Re-probes clips that failed because FFmpeg was missing.
  void reprobeFailed() {
    for (final c in _sources.where((c) => c.info == null)) {
      c
        ..probing = true
        ..error = null;
      _probe(c);
    }
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= _sources.length || index == _active) return;
    _active = index;
    notifyListeners();
  }

  void remove(SourceClip clip) {
    final i = _sources.indexOf(clip);
    if (i < 0) return;
    _sources.removeAt(i);
    if (_sources.isEmpty) {
      _active = -1;
    } else if (_active >= _sources.length || i < _active) {
      _active = (_active - 1).clamp(0, _sources.length - 1);
    }
    notifyListeners();
  }

  void clear() {
    _sources.clear();
    _active = -1;
    notifyListeners();
  }

  void setTrim(double start, double end) {
    final c = active;
    if (c == null || c.info == null) return;
    final d = c.duration;
    start = start.clamp(0, d);
    end = end.clamp(0, d);
    if (end - start < 0.1) return;
    c
      ..trimStart = start
      ..trimEnd = (d - end).abs() < 0.001 ? null : end;
    notifyListeners();
  }

  void resetTrim() {
    final c = active;
    if (c == null) return;
    c
      ..trimStart = 0
      ..trimEnd = null;
    notifyListeners();
  }
}
