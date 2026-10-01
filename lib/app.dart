import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'state/compilation_controller.dart';
import 'state/editor_controller.dart';
import 'state/engine_controller.dart';
import 'state/history_controller.dart';
import 'state/library_controller.dart';
import 'state/playback_controller.dart';
import 'state/preview_controller.dart';
import 'state/project_controller.dart';
import 'state/render_queue.dart';
import 'state/settings_controller.dart';
import 'state/sparta_controller.dart';
import 'state/sparta_playback.dart';
import 'state/store.dart';
import 'state/thumbnail_service.dart';
import 'state/update_controller.dart';
import 'ui/shell/editor_shell.dart';
import 'ui/theme.dart';

class StudioApp extends StatefulWidget {
  const StudioApp({
    super.key,
    required this.store,
    required this.playerAvailable,
    this.autoInit = true,
    this.initialFiles = const [],
  });

  final Store store;

  /// Whether media_kit / libmpv initialized (in-app playback).
  final bool playerAvailable;

  /// Look for FFmpeg and check for updates on start (off in widget tests).
  final bool autoInit;

  /// Clips to open right away.
  final List<String> initialFiles;

  @override
  State<StudioApp> createState() => _StudioAppState();
}

class _StudioAppState extends State<StudioApp> {
  late final settings = SettingsController(widget.store);
  late final library = LibraryController(widget.store);
  late final history = HistoryController(widget.store);
  late final engine = EngineController();
  late final project = ProjectController(engine);
  late final editor = EditorController(library);
  late final compilation = CompilationController();
  late final queue = RenderQueue(history);
  late final thumbnails = ThumbnailService();
  late final updates = UpdateController();
  late final preview = PreviewController(
    project: project,
    editor: editor,
    compilation: compilation,
    library: library,
    engine: engine,
    settings: settings,
  );
  late final playback = PlaybackController(available: widget.playerAvailable, project: project, preview: preview);
  late final sparta = SpartaController(
    engine,
    store: widget.store,
    // Decoded here: loadString hands big assets to an isolate.
    loadBundledCatalog: () async => utf8.decode((await rootBundle.load('bases/catalog.json')).buffer.asUint8List()),
  );
  late final spartaPlayback = SpartaPlayback(available: widget.playerAvailable);

  @override
  void initState() {
    super.initState();
    // New clip or trim: stop generating thumbnails for the old frame.
    project.addListener(thumbnails.cancelPending);
    library.addListener(() => compilation.prune(library.registry));
    if (widget.autoInit) {
      engine.init(ffmpegOverride: settings.ffmpegOverride).then((_) {
        project.reprobeFailed();
        project.addFiles(widget.initialFiles);
      });
      updates.loadVersion();
      if (settings.autoCheckUpdates) updates.check();
    }
  }

  @override
  void dispose() {
    playback.dispose();
    spartaPlayback.dispose();
    sparta.dispose();
    preview.dispose();
    queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: engine),
        ChangeNotifierProvider.value(value: project),
        ChangeNotifierProvider.value(value: editor),
        ChangeNotifierProvider.value(value: compilation),
        ChangeNotifierProvider.value(value: queue),
        ChangeNotifierProvider.value(value: thumbnails),
        ChangeNotifierProvider.value(value: updates),
        ChangeNotifierProvider.value(value: preview),
        ChangeNotifierProvider.value(value: playback),
        ChangeNotifierProvider.value(value: sparta),
        ChangeNotifierProvider.value(value: spartaPlayback),
      ],
      child: MaterialApp(
        title: 'Video Effects Studio',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(),
        themeMode: ThemeMode.dark,
        home: const EditorShell(),
      ),
    );
  }
}
