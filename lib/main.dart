import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'state/store.dart';
import 'ui/unsupported_platform.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled typeface's license, listed with the packages' in Settings.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/fonts/Inter-LICENSE.txt'));
  });

  final desktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  if (!desktop) {
    // Rendering needs a local FFmpeg process, which phones and browsers
    // can't run.
    runApp(const UnsupportedPlatformApp());
    return;
  }

  var playerAvailable = true;
  try {
    MediaKit.ensureInitialized();
  } catch (_) {
    playerAvailable = false;
  }

  final store = await Store.open();
  // Files passed on the command line ("Open with…") are loaded at start.
  final initialFiles = args.where((a) => !a.startsWith('-') && File(a).existsSync()).toList();
  runApp(StudioApp(store: store, playerAvailable: playerAvailable, initialFiles: initialFiles));
}
