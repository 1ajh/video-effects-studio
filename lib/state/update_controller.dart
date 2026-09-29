import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  const UpdateInfo({required this.current, required this.latest, required this.notes, required this.url});

  final String current;
  final String latest;
  final String notes;
  final String url;
}

/// Checks GitHub releases for a newer version.
class UpdateController extends ChangeNotifier {
  static const repo = '1ajh/video-effects-studio';
  static const releasesUrl = 'https://github.com/$repo/releases';

  UpdateInfo? _available;
  String _version = '';
  bool _dismissed = false;
  bool _checking = false;

  UpdateInfo? get available => _dismissed ? null : _available;
  String get version => _version;
  bool get checking => _checking;

  Future<void> loadVersion() async {
    try {
      _version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      _version = '';
    }
    notifyListeners();
  }

  /// Returns true when an update was found.
  Future<bool> check() async {
    _checking = true;
    notifyListeners();
    try {
      if (_version.isEmpty) await loadVersion();
      final res = await http
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, Object?>;
      final tag = (data['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
      if (isNewer(tag, _version)) {
        _available = UpdateInfo(
          current: _version,
          latest: tag,
          notes: data['body'] as String? ?? '',
          url: _assetFor(data) ?? (data['html_url'] as String? ?? releasesUrl),
        );
        _dismissed = false;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }

  String? _assetFor(Map<String, Object?> release) {
    if (kIsWeb) return null;
    final assets = (release['assets'] as List? ?? const []).cast<Map>();
    final hint = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
        ? 'macos'
        : Platform.isLinux
        ? 'linux'
        : null;
    if (hint == null) return null;
    for (final a in assets) {
      final name = '${a['name']}'.toLowerCase();
      if (name.contains(hint)) return a['browser_download_url'] as String?;
    }
    return null;
  }

  /// Semantic-ish version comparison ("2.1.0" > "2.0.9").
  static bool isNewer(String latest, String current) {
    List<int> parse(String v) {
      final parts = v.split(RegExp(r'[.+-]')).map((s) => int.tryParse(s) ?? 0).toList();
      while (parts.length < 3) {
        parts.add(0);
      }
      return parts.take(3).toList();
    }

    if (latest.isEmpty || current.isEmpty) return false;
    final a = parse(latest);
    final b = parse(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }
}
