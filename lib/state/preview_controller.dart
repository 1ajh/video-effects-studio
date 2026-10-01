import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/effects/effect.dart';
import '../core/ffmpeg/ffmpeg_runner.dart';
import 'compilation_controller.dart';
import 'editor_controller.dart';
import 'engine_controller.dart';
import 'library_controller.dart';
import 'project_controller.dart';
import 'settings_controller.dart';

enum ViewMode { original, effect, split }

/// The effect the inspector is editing: the browser selection, or the
/// selected compilation item.
class FxTarget {
  const FxTarget(this.effect, this.params, {this.compIndex});
  final Effect effect;
  final Map<String, Object?> params;
  final int? compIndex;
}

FxTarget? resolveTarget(EditorController editor, CompilationController comp, LibraryController library) {
  if (editor.mode == EditorMode.compilation) {
    final item = comp.selectedItem;
    if (item != null) {
      final e = library.registry.byId(item.effectId);
      if (e != null) return FxTarget(e, item.params, compIndex: comp.selectedIndex);
    }
  }
  final e = editor.selected;
  return e == null ? null : FxTarget(e, editor.paramsFor(e));
}

/// Renders short previews of the current effect for the before/after player.
class PreviewController extends ChangeNotifier {
  PreviewController({
    required this.project,
    required this.editor,
    required this.compilation,
    required this.library,
    required this.engine,
    required this.settings,
  }) {
    for (final l in _sources) {
      l.addListener(_onInputsChanged);
    }
  }

  final ProjectController project;
  final EditorController editor;
  final CompilationController compilation;
  final LibraryController library;
  final EngineController engine;
  final SettingsController settings;

  List<Listenable> get _sources => [project, editor, compilation, library, engine, settings];

  ViewMode _viewMode = ViewMode.original;
  String? _path;
  String? _pathKey;
  String? _wantedKey;
  String? _effectName;
  bool _rendering = false;
  double _progress = 0;
  String? _error;
  CancelToken? _cancel;
  Timer? _debounce;

  ViewMode get viewMode => _viewMode;
  String? get path => _path;
  bool get rendering => _rendering;
  double get progress => _progress;
  String? get error => _error;
  String? get effectName => _effectName;

  /// Whether the rendered preview matches the current effect + settings.
  bool get isCurrent => _path != null && _pathKey == _wantedKey;

  void setViewMode(ViewMode m) {
    if (_viewMode == m) return;
    _viewMode = m;
    notifyListeners();
  }

  FxTarget? get target => resolveTarget(editor, compilation, library);

  String? _keyFor(FxTarget? t) {
    final clip = project.active;
    if (t == null || clip?.info == null) return null;
    return [
      clip!.path,
      clip.trimStart.toStringAsFixed(3),
      settings.previewSeconds.toStringAsFixed(1),
      t.effect.id,
      t.params.toString(),
      settings.output.loudness.name,
    ].join('|');
  }

  void _onInputsChanged() {
    final key = _keyFor(target);
    if (key == _wantedKey) return;
    _wantedKey = key;
    if (key == null) {
      _cancelRender();
      notifyListeners();
      return;
    }
    if (settings.autoPreview) {
      schedule();
    } else {
      notifyListeners();
    }
  }

  /// Renders the preview after a short debounce (or right away).
  void schedule({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      _start();
    } else {
      _debounce = Timer(const Duration(milliseconds: 350), _start);
    }
  }

  Future<void> _start() async {
    final t = target;
    final clip = project.active;
    final eng = engine.engine;
    final key = _keyFor(t);
    if (t == null || clip?.info == null || eng == null || key == null) return;
    if (key == _pathKey && _path != null) {
      if (_viewMode == ViewMode.original) _viewMode = ViewMode.effect;
      notifyListeners();
      return;
    }

    _cancelRender();
    final cancel = _cancel = CancelToken();
    _rendering = true;
    _progress = 0;
    _error = null;
    _effectName = t.effect.name;
    notifyListeners();

    try {
      final seconds = math.min(settings.previewSeconds, math.max(0.2, clip!.trimmedLength));
      final path = await eng.preview(
        media: clip.info!,
        effect: t.effect,
        params: t.params,
        start: clip.trimStart,
        seconds: seconds,
        cacheDir: engine.cacheDir,
        loudness: settings.output.loudness,
        cancel: cancel,
        onProgress: (f) {
          if (identical(cancel, _cancel)) {
            _progress = f;
            notifyListeners();
          }
        },
      );
      if (!identical(cancel, _cancel)) return;
      _path = path;
      _pathKey = key;
      _rendering = false;
      if (_viewMode == ViewMode.original) _viewMode = ViewMode.effect;
      notifyListeners();
    } on CancelledException {
      // Superseded by a newer request.
    } catch (e) {
      if (!identical(cancel, _cancel)) return;
      _rendering = false;
      _error = '$e';
      notifyListeners();
    }
  }

  void _cancelRender() {
    _cancel?.cancel();
    _cancel = null;
    if (_rendering) {
      _rendering = false;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelRender();
    for (final l in _sources) {
      l.removeListener(_onInputsChanged);
    }
    super.dispose();
  }
}
