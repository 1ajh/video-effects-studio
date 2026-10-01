import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../core/effects/effect.dart';
import '../core/ffmpeg/command_builder.dart';
import '../core/render/render_engine.dart';
import '../state/compilation_controller.dart';
import '../state/editor_controller.dart';
import '../state/engine_controller.dart';
import '../state/library_controller.dart';
import '../state/preview_controller.dart';
import '../state/project_controller.dart';
import '../state/render_queue.dart';
import '../state/settings_controller.dart';
import '../state/sparta_controller.dart';
import 'file_dialogs.dart';
import 'widgets/common.dart';

/// User-level commands shared by buttons, menus and keyboard shortcuts.
class StudioActions {
  StudioActions(this.context);
  final BuildContext context;

  T _read<T>() => context.read<T>();

  Future<void> importFiles() async {
    final files = await pickFilesSafely(
      context,
      dialogTitle: 'Add videos',
      type: FileType.custom,
      allowedExtensions: videoExtensions.toList(),
    );
    final paths = files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty || !context.mounted) return;
    addPaths(paths);
  }

  void addPaths(List<String> paths) {
    final added = _read<ProjectController>().addFiles(paths);
    final skipped = paths.length - added;
    if (added == 0) {
      showMessage(context, 'Nothing new to add — drop video or audio files.', error: skipped > 0);
    } else if (skipped > 0) {
      showMessage(context, 'Added $added file${added == 1 ? '' : 's'} ($skipped skipped).');
    }
  }

  bool _checkEngine() {
    if (_read<EngineController>().ready) return true;
    showMessage(context, 'FFmpeg was not found. Set it up in Settings → FFmpeg.', error: true);
    return false;
  }

  /// Renders whatever the current mode is about.
  void render() {
    switch (_read<EditorController>().mode) {
      case EditorMode.compilation:
        renderCompilation();
      case EditorMode.sparta:
        renderSparta();
      case EditorMode.single:
        renderSingle();
    }
  }

  /// Renders the generated Sparta remix (video, stems and MIDI as chosen).
  void renderSparta() {
    if (!_checkEngine()) return;
    final sparta = _read<SpartaController>();
    if (!sparta.hasResult) {
      showMessage(context, sparta.busy ? 'Still generating — one moment.' : 'Generate a remix first.');
      return;
    }
    final settings = _read<SettingsController>();
    _read<RenderQueue>().enqueue(
      sparta.renderJob(
        outDir: settings.outputDir,
        output: settings.output,
        stems: sparta.exportStems,
        midi: sparta.exportMidi,
      ),
    );
    _openQueue();
  }

  /// Routes dropped/opened files: base projects and media for Sparta mode.
  void addSpartaPaths(List<String> paths) {
    final sparta = _read<SpartaController>();
    final projects = paths.where(isProjectFile).toList();
    if (projects.isNotEmpty) sparta.setProject(projects.first);
    final added = sparta.addSources(paths.where((p) => !isProjectFile(p)));
    if (projects.isEmpty && added == 0) {
      showMessage(context, 'Drop videos/audio for sources, or an .flp/.flm/.mid base.', error: true);
    }
  }

  /// Renders the selected effect for the active clip (or all clips).
  void renderSingle({bool allClips = false}) {
    if (!_checkEngine()) return;
    final editor = _read<EditorController>();
    final effect = editor.selected;
    if (effect == null) {
      showMessage(context, 'Pick an effect first.');
      return;
    }
    final project = _read<ProjectController>();
    final clips = (allClips ? project.sources : [?project.active]).where((c) => c.info != null).toList();
    if (clips.isEmpty) {
      showMessage(context, 'Add a video first.');
      return;
    }
    final params = editor.paramsFor(effect);
    for (final clip in clips) {
      _enqueueSingle(clip, effect, params);
    }
    _read<LibraryController>().markUsed(effect.id);
    _openQueue();
  }

  void _enqueueSingle(SourceClip clip, Effect effect, Map<String, Object?> params) {
    final settings = _read<SettingsController>();
    final engine = _read<EngineController>().engine!;
    final output = settings.output;
    final base = '${p.basenameWithoutExtension(clip.path)}_${RenderEngine.slug(effect.name)}';
    _read<RenderQueue>().enqueue(
      RenderJob(
        title: effect.name,
        subtitle: clip.name,
        isCompilation: false,
        task: (job, cancel) async {
          final out = await RenderEngine.uniqueOutputPath(settings.outputDir, base, output.format.extension);
          return engine.render(
            RenderRequest(
              media: clip.info!,
              effect: effect,
              params: params,
              outputPath: out,
              start: clip.trimStart,
              end: clip.trimEnd,
              output: output,
            ),
            onProgress: job.report,
            cancel: cancel,
          );
        },
      ),
    );
  }

  void renderCompilation() {
    if (!_checkEngine()) return;
    final clip = _read<ProjectController>().active;
    if (clip?.info == null) {
      showMessage(context, 'Add a video first.');
      return;
    }
    final comp = _read<CompilationController>();
    final library = _read<LibraryController>();
    final entries = comp.entries(library.registry);
    if (entries.isEmpty) {
      showMessage(context, 'The compilation is empty — add some effects.');
      return;
    }
    final settings = _read<SettingsController>();
    final engineCtl = _read<EngineController>();
    final engine = engineCtl.engine!;
    final output = settings.output;
    final base = '${p.basenameWithoutExtension(clip!.path)}_compilation_${entries.length}fx';
    CompilationRequest request(String out) => CompilationRequest(
      media: clip.info!,
      entries: entries,
      outputPath: out,
      start: clip.trimStart,
      end: clip.trimEnd,
      output: output,
      labelMode: settings.labelMode,
      originalFirst: settings.originalFirst,
      fontPath: engineCtl.fontPath,
      concurrency: settings.concurrency,
    );
    if (settings.labelMode != LabelMode.none && !(engineCtl.toolkit?.hasDrawtext ?? false)) {
      showMessage(context, 'This FFmpeg build has no drawtext filter, so labels will be skipped.');
    }
    _read<RenderQueue>().enqueue(
      RenderJob(
        title: 'Compilation · ${entries.length} effects',
        subtitle: clip.name,
        isCompilation: true,
        task: (job, cancel) async {
          final out = await RenderEngine.uniqueOutputPath(settings.outputDir, base, output.format.extension);
          return engine.renderCompilation(request(out), onProgress: job.report, cancel: cancel);
        },
      ),
    );
    _openQueue();
  }

  void addTargetToCompilation() {
    final editor = _read<EditorController>();
    final e = editor.selected;
    if (e == null) return;
    addToCompilation(e);
  }

  void addToCompilation(Effect e) {
    final editor = _read<EditorController>();
    _read<CompilationController>().add(e, editor.paramsFor(e));
    _read<LibraryController>().markUsed(e.id);
    if (editor.mode != EditorMode.compilation) {
      editor.setMode(EditorMode.compilation);
    }
  }

  void previewNow() {
    if (!_checkEngine()) return;
    final preview = _read<PreviewController>();
    if (preview.target == null) {
      showMessage(context, 'Pick an effect to preview.');
      return;
    }
    if (_read<ProjectController>().active?.info == null) {
      showMessage(context, 'Add a video first.');
      return;
    }
    preview.schedule(immediate: true);
  }

  void _openQueue() {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.hasEndDrawer && !scaffold.isEndDrawerOpen) scaffold.openEndDrawer();
  }
}
