import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/editor_controller.dart';
import '../../state/engine_controller.dart';
import '../../state/playback_controller.dart';
import '../../state/preview_controller.dart';
import '../../state/project_controller.dart';
import '../../state/render_queue.dart';
import '../actions.dart';
import '../browser/effect_browser.dart';
import '../compilation/compilation_dock.dart';
import '../dialogs/help_dialog.dart';
import '../inspector/inspector_panel.dart';
import '../pages/history_page.dart';
import '../pages/settings_page.dart';
import '../platform_actions.dart';
import '../preview/preview_panel.dart';
import '../preview/source_strip.dart';
import '../sparta/sparta_workspace.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'queue_drawer.dart';
import 'status_bar.dart';
import 'top_bar.dart';

class EditorShell extends StatefulWidget {
  const EditorShell({super.key});

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchFocus = FocusNode(debugLabel: 'effect search');
  final _rootFocus = FocusNode(debugLabel: 'shell');
  StreamSubscription<RenderJob>? _finishedSub;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _finishedSub = context.read<RenderQueue>().finished.listen(_onJobFinished);
  }

  @override
  void dispose() {
    _finishedSub?.cancel();
    _searchFocus.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  void _onJobFinished(RenderJob job) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    switch (job.status) {
      case JobStatus.done:
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${job.title} is ready'
                    '${job.failures.isEmpty ? '' : ' (${job.failures.length} skipped)'}',
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(label: 'Show in folder', onPressed: () => showInFolder(job.outputPath!)),
          ),
        );
      case JobStatus.failed:
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: AppColors.danger, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${job.title} failed: ${job.error}', maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(label: 'Details', onPressed: () => _scaffoldKey.currentState?.openEndDrawer()),
          ),
        );
      default:
        break;
    }
  }

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    final mod = kb.isControlPressed || kb.isMetaPressed;
    final key = event.logicalKey;
    final actions = StudioActions(context);
    final editor = context.read<EditorController>();

    if (mod) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      if (key == LogicalKeyboardKey.keyO) {
        actions.importFiles();
      } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        actions.render();
      } else if (key == LogicalKeyboardKey.keyP) {
        actions.previewNow();
      } else if (key == LogicalKeyboardKey.keyF) {
        _searchFocus.requestFocus();
      } else if (key == LogicalKeyboardKey.keyD) {
        actions.addTargetToCompilation();
      } else if (key == LogicalKeyboardKey.digit1) {
        editor.setMode(EditorMode.single);
      } else if (key == LogicalKeyboardKey.digit2) {
        editor.setMode(EditorMode.compilation);
      } else if (key == LogicalKeyboardKey.digit3) {
        editor.setMode(EditorMode.sparta);
      } else if (key == LogicalKeyboardKey.keyH) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage()));
      } else if (key == LogicalKeyboardKey.comma) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
      } else if (key == LogicalKeyboardKey.keyQ) {
        _scaffoldKey.currentState?.openEndDrawer();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.f1) {
      showHelpDialog(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _searchFocus.hasFocus) {
      _rootFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (_typing) return KeyEventResult.ignored;
    if (editor.mode == EditorMode.sparta) return KeyEventResult.ignored;

    final playback = context.read<PlaybackController>();
    final preview = context.read<PreviewController>();
    final project = context.read<ProjectController>();
    if (key == LogicalKeyboardKey.space) {
      playback.togglePlay();
    } else if (key == LogicalKeyboardKey.home) {
      playback.restart();
    } else if (key == LogicalKeyboardKey.keyI && project.active != null) {
      project.setTrim(playback.sourcePosition, project.active!.effectiveEnd);
    } else if (key == LogicalKeyboardKey.keyO && project.active != null) {
      project.setTrim(project.active!.trimStart, playback.sourcePosition);
    } else if (key == LogicalKeyboardKey.digit1) {
      preview.setViewMode(ViewMode.original);
    } else if (key == LogicalKeyboardKey.digit2) {
      preview.setViewMode(ViewMode.effect);
    } else if (key == LogicalKeyboardKey.digit3) {
      preview.setViewMode(ViewMode.split);
    } else {
      return handleBrowserArrows(context, event);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<EditorController, EditorMode>((e) => e.mode);
    final compMode = mode == EditorMode.compilation;
    final hasClips = context.select<ProjectController, bool>((p) => !p.isEmpty);
    final engineStatus = context.select<EngineController, EngineStatus>((e) => e.status);

    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        key: _scaffoldKey,
        endDrawer: const QueueDrawer(),
        body: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) {
            setState(() => _dragging = false);
            final paths = details.files.map((f) => f.path).toList();
            if (mode == EditorMode.sparta) {
              StudioActions(context).addSpartaPaths(paths);
            } else {
              StudioActions(context).addPaths(paths);
            }
          },
          child: Stack(
            children: [
              Column(
                children: [
                  const TopBar(),
                  if (engineStatus == EngineStatus.missing) const _FfmpegBanner(),
                  if (mode == EditorMode.sparta)
                    const Expanded(child: SpartaWorkspace())
                  else
                    Expanded(
                      child: Row(
                        children: [
                          SizedBox(width: 330, child: EffectBrowser(searchFocus: _searchFocus)),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: Column(
                              children: [
                                if (hasClips) const SourceStrip(),
                                const Expanded(child: PreviewPanel()),
                              ],
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          const SizedBox(width: 350, child: InspectorPanel()),
                        ],
                      ),
                    ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: compMode ? 196 : 0,
                    child: const ClipRect(
                      child: OverflowBox(alignment: Alignment.topCenter, maxHeight: 196, child: CompilationDock()),
                    ),
                  ),
                  const StatusBar(),
                ],
              ),
              if (_dragging) _DropOverlay(sparta: mode == EditorMode.sparta),
            ],
          ),
        ),
      ),
    );
  }
}

class _FfmpegBanner extends StatelessWidget {
  const _FfmpegBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.danger.withValues(alpha: 0.14),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'FFmpeg was not found, so nothing can be rendered yet. Release builds include it — if you built from source, '
              'install FFmpeg or point the app at your ffmpeg executable.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
            child: const Text('Set up FFmpeg'),
          ),
          TextButton(
            onPressed: () async {
              final engine = context.read<EngineController>();
              await engine.detect();
              if (context.mounted) {
                context.read<ProjectController>().reprobeFailed();
                if (!engine.ready) showMessage(context, 'Still not found.', error: true);
              }
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay({this.sparta = false});
  final bool sparta;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: AppColors.bg.withValues(alpha: 0.82),
          padding: const EdgeInsets.all(28),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sparta ? AppColors.sparta : AppColors.accent, width: 2),
              color: (sparta ? AppColors.sparta : AppColors.accent).withValues(alpha: 0.08),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_download_outlined, size: 48, color: sparta ? AppColors.spartaHi : AppColors.accentHi),
                  const SizedBox(height: 12),
                  Text(
                    sparta ? 'Drop sources, or an .flp / .flm / .mid base' : 'Drop to add clips',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
