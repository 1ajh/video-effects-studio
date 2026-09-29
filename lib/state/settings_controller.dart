import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/models/output_settings.dart';
import '../core/render/render_engine.dart';
import 'store.dart';

/// User preferences.
class SettingsController extends ChangeNotifier {
  SettingsController(this._store) {
    _load();
  }

  final Store _store;

  late String _outputDir;
  OutputSettings _output = const OutputSettings();
  String? _ffmpegOverride;
  int _concurrency = 2;
  double _previewSeconds = 5;
  bool _autoPreview = true;
  bool _effectThumbnails = true;
  LabelMode _labelMode = LabelMode.overlay;
  bool _originalFirst = true;
  bool _autoCheckUpdates = true;
  bool _showLoudWarning = true;

  String get outputDir => _outputDir;
  OutputSettings get output => _output;
  String? get ffmpegOverride => _ffmpegOverride;
  int get concurrency => _concurrency;
  double get previewSeconds => _previewSeconds;
  bool get autoPreview => _autoPreview;
  bool get effectThumbnails => _effectThumbnails;
  LabelMode get labelMode => _labelMode;
  bool get originalFirst => _originalFirst;
  bool get autoCheckUpdates => _autoCheckUpdates;
  bool get showLoudWarning => _showLoudWarning;

  static String defaultOutputDir() {
    final env = Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
    final videos = Platform.isMacOS ? 'Movies' : 'Videos';
    return p.join(home, videos, 'VideoEffectsStudio');
  }

  void _load() {
    _outputDir = _store.getString('outputDir') ?? defaultOutputDir();
    _output = OutputSettings.fromJson(_store.readJson<Map<String, Object?>>('output'));
    _ffmpegOverride = _store.getString('ffmpegOverride');
    _concurrency = (_store.getInt('concurrency') ?? 2).clamp(1, 4);
    _previewSeconds = (_store.getDouble('previewSeconds') ?? 5).clamp(2, 20);
    _autoPreview = _store.getBool('autoPreview') ?? true;
    _effectThumbnails = _store.getBool('effectThumbnails') ?? true;
    _labelMode = LabelMode.values.firstWhere(
      (m) => m.name == _store.getString('labelMode'),
      orElse: () => LabelMode.overlay,
    );
    _originalFirst = _store.getBool('originalFirst') ?? true;
    _autoCheckUpdates = _store.getBool('autoCheckUpdates') ?? true;
    _showLoudWarning = _store.getBool('showLoudWarning') ?? true;
  }

  void setOutputDir(String dir) {
    _outputDir = dir;
    _store.setString('outputDir', dir);
    notifyListeners();
  }

  void setOutput(OutputSettings o) {
    _output = o;
    _store.writeJson('output', o.toJson());
    notifyListeners();
  }

  void setFfmpegOverride(String? path) {
    _ffmpegOverride = (path == null || path.trim().isEmpty) ? null : path.trim();
    if (_ffmpegOverride == null) {
      _store.remove('ffmpegOverride');
    } else {
      _store.setString('ffmpegOverride', _ffmpegOverride!);
    }
    notifyListeners();
  }

  void setConcurrency(int v) {
    _concurrency = v.clamp(1, 4);
    _store.setInt('concurrency', _concurrency);
    notifyListeners();
  }

  void setPreviewSeconds(double v) {
    _previewSeconds = v.clamp(2, 20);
    _store.setDouble('previewSeconds', _previewSeconds);
    notifyListeners();
  }

  void setAutoPreview(bool v) {
    _autoPreview = v;
    _store.setBool('autoPreview', v);
    notifyListeners();
  }

  void setEffectThumbnails(bool v) {
    _effectThumbnails = v;
    _store.setBool('effectThumbnails', v);
    notifyListeners();
  }

  void setLabelMode(LabelMode m) {
    _labelMode = m;
    _store.setString('labelMode', m.name);
    notifyListeners();
  }

  void setOriginalFirst(bool v) {
    _originalFirst = v;
    _store.setBool('originalFirst', v);
    notifyListeners();
  }

  void setAutoCheckUpdates(bool v) {
    _autoCheckUpdates = v;
    _store.setBool('autoCheckUpdates', v);
    notifyListeners();
  }

  void setShowLoudWarning(bool v) {
    _showLoudWarning = v;
    _store.setBool('showLoudWarning', v);
    notifyListeners();
  }

  Future<void> resetAll() async {
    await _store.clearAll();
    _load();
    notifyListeners();
  }
}
