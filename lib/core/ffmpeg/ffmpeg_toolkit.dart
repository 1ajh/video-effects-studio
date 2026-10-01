import 'dart:io';

import 'package:path/path.dart' as p;

/// A located, working FFmpeg installation and what it can do.
class FfmpegToolkit {
  FfmpegToolkit({
    required this.ffmpegPath,
    required this.ffprobePath,
    required this.versionLine,
    required this.filters,
    required this.encoders,
    required this.source,
  });

  final String ffmpegPath;
  final String? ffprobePath;
  final String versionLine;
  final Set<String> filters;
  final Set<String> encoders;

  /// Where it was found: "custom", "bundled" or "system".
  final String source;

  bool get hasDrawtext => filters.contains('drawtext');
  bool hasFilter(String name) => filters.contains(name);
  bool hasEncoder(String name) => encoders.contains(name);

  /// Filters the built-in effects rely on that are missing from this build.
  List<String> missingFilters(Iterable<String> required) => required.where((f) => !filters.contains(f)).toList();

  static String get _exe => Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
  static String get _probeExe => Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';

  /// Finds FFmpeg: explicit override → bundled next to the app → PATH →
  /// well-known install locations. Returns `null` if none works.
  static Future<FfmpegToolkit?> locate({String? overridePath}) async {
    final candidates = <(String, String)>[];

    void add(String path, String source) {
      if (path.isNotEmpty) candidates.add((path, source));
    }

    if (overridePath != null && overridePath.trim().isNotEmpty) {
      final o = overridePath.trim();
      add(FileSystemEntity.isDirectorySync(o) ? p.join(o, _exe) : o, 'custom');
    }
    final envOverride = Platform.environment['VFX_FFMPEG'];
    if (envOverride != null) add(envOverride, 'custom');

    for (final path in bundledCandidates()) {
      add(path, 'bundled');
    }

    final pathVar = Platform.environment['PATH'] ?? '';
    for (final dir in pathVar.split(Platform.isWindows ? ';' : ':')) {
      if (dir.trim().isNotEmpty) add(p.join(dir.trim(), _exe), 'system');
    }
    for (final dir in _wellKnownDirs()) {
      add(p.join(dir, _exe), 'system');
    }

    final seen = <String>{};
    for (final (path, source) in candidates) {
      final normalized = p.normalize(path);
      if (!seen.add(normalized)) continue;
      if (!File(normalized).existsSync()) continue;
      final kit = await probe(normalized, source: source);
      if (kit != null) return kit;
    }
    return null;
  }

  /// Paths where release builds ship FFmpeg next to the executable.
  static List<String> bundledCandidates() {
    final dir = p.dirname(Platform.resolvedExecutable);
    return [
      p.join(dir, _exe),
      p.join(dir, 'bin', _exe),
      p.join(dir, 'ffmpeg', _exe),
      if (Platform.isLinux) p.join(dir, 'lib', _exe),
      if (Platform.isMacOS) ...[p.join(dir, '..', 'Resources', _exe), p.join(dir, '..', 'Frameworks', _exe)],
    ];
  }

  static List<String> _wellKnownDirs() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return [
        r'C:\ffmpeg\bin',
        r'C:\Program Files\ffmpeg\bin',
        r'C:\ProgramData\chocolatey\bin',
        if (env['LOCALAPPDATA'] != null) p.join(env['LOCALAPPDATA']!, 'Microsoft', 'WinGet', 'Links'),
        if (env['USERPROFILE'] != null) p.join(env['USERPROFILE']!, 'scoop', 'shims'),
      ];
    }
    return [
      // GUI apps on macOS don't inherit the shell PATH, so check Homebrew.
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/snap/bin',
      '/opt/local/bin',
    ];
  }

  /// Validates an ffmpeg binary and collects its capabilities.
  static Future<FfmpegToolkit?> probe(String ffmpegPath, {String source = 'custom'}) async {
    try {
      final version = await Process.run(ffmpegPath, const [
        '-hide_banner',
        '-version',
      ]).timeout(const Duration(seconds: 15));
      if (version.exitCode != 0) return null;
      final versionLine = '${version.stdout}'.split('\n').first.trim();

      final filtersOut = await Process.run(ffmpegPath, const [
        '-hide_banner',
        '-filters',
      ]).timeout(const Duration(seconds: 15));
      final encodersOut = await Process.run(ffmpegPath, const [
        '-hide_banner',
        '-encoders',
      ]).timeout(const Duration(seconds: 15));

      final probePath = p.join(p.dirname(ffmpegPath), _probeExe);
      return FfmpegToolkit(
        ffmpegPath: ffmpegPath,
        ffprobePath: File(probePath).existsSync() ? probePath : null,
        versionLine: versionLine,
        filters: _parseList('${filtersOut.stdout}'),
        encoders: _parseList('${encodersOut.stdout}'),
        source: source,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parses the name column of `-filters` / `-encoders` listings.
  static Set<String> _parseList(String out) {
    final names = <String>{};
    for (final line in out.split('\n')) {
      final m = RegExp(r'^\s*[A-Z.|]{2,7}\s+(\S+)\s').firstMatch(line);
      if (m != null && m.group(1) != '=') names.add(m.group(1)!);
    }
    return names;
  }
}
