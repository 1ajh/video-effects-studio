import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Opens a file with the system's default app.
Future<void> openFile(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  } catch (_) {
    await launchUrl(Uri.file(path));
  }
}

/// Reveals a file in Explorer / Finder / the file manager.
Future<void> showInFolder(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else {
      // Ask the freedesktop file manager to highlight the file, falling back
      // to just opening the folder.
      final r = await Process.run('dbus-send', [
        '--session', '--print-reply', '--dest=org.freedesktop.FileManager1', //
        '/org/freedesktop/FileManager1', 'org.freedesktop.FileManager1.ShowItems',
        'array:string:${Uri.file(path)}', 'string:',
      ]);
      if (r.exitCode != 0) await Process.run('xdg-open', [p.dirname(path)]);
    }
  } catch (_) {
    await launchUrl(Uri.directory(p.dirname(path)));
  }
}

Future<void> openFolder(String dir) async {
  await Directory(dir).create(recursive: true);
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', [dir]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir]);
    } else {
      await Process.run('xdg-open', [dir]);
    }
  } catch (_) {
    await launchUrl(Uri.directory(dir));
  }
}

Future<void> openUrl(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

String formatDuration(double seconds, {bool precise = false}) {
  if (!seconds.isFinite || seconds < 0) seconds = 0;
  final m = seconds ~/ 60;
  final s = seconds - m * 60;
  if (precise) return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
  final h = m ~/ 60;
  if (h > 0) return '$h:${(m % 60).toString().padLeft(2, '0')}:${s.floor().toString().padLeft(2, '0')}';
  return '$m:${s.floor().toString().padLeft(2, '0')}';
}

/// Keeps the last [keep] segments of a long path: `…/Videos/SRLE Studio`.
String shortPath(String path, {int keep = 2}) {
  final parts = p.split(path).where((s) => s.isNotEmpty && s != p.separator).toList();
  if (parts.length <= keep + 1) return path;
  return '…${p.separator}${p.joinAll(parts.sublist(parts.length - keep))}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
}
