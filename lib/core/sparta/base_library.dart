import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'transcription.dart';

/// A real Sparta base the app can download.
class CatalogBase {
  const CatalogBase({
    required this.id,
    required this.name,
    required this.audioUrl,
    this.maker = '',
    this.collection = '',
    this.page = '',
    this.size,
    this.sha1,
    this.flpUrl,
    this.transcriptionPath,
    this.featured = false,
  });

  final String id;
  final String name;
  final String maker;

  /// Where it was published (a collection on archive.org, Keaton's site…).
  final String collection;
  final String audioUrl;

  /// Page to credit and visit.
  final String page;
  final int? size;

  /// SHA-1 of the audio file, when the host lists it.
  final String? sha1;

  /// The base's FL Studio project, when it's available too (exact notes).
  final String? flpUrl;

  /// A checked transcription in the repository's bases/ folder.
  final String? transcriptionPath;
  final bool featured;

  /// Notes known exactly (project or checked transcription).
  bool get exact => flpUrl != null || transcriptionPath != null;

  String get credit => maker.isNotEmpty ? maker : collection;

  factory CatalogBase.fromJson(Map<String, Object?> j) => CatalogBase(
    id: j['id']! as String,
    name: j['name']! as String,
    audioUrl: j['audio']! as String,
    maker: j['maker'] as String? ?? '',
    collection: j['collection'] as String? ?? '',
    page: j['page'] as String? ?? '',
    size: (j['size'] as num?)?.toInt(),
    sha1: j['sha1'] as String?,
    flpUrl: j['flp'] as String?,
    transcriptionPath: j['transcription'] as String?,
    featured: j['featured'] as bool? ?? false,
  );

  /// File name for the local copy.
  String get fileStem => id.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  String get extension {
    final path = Uri.tryParse(audioUrl)?.path ?? audioUrl;
    final ext = p.extension(Uri.decodeComponent(path)).toLowerCase();
    return ext.isEmpty ? '.mp3' : ext;
  }
}

class BaseCatalog {
  BaseCatalog(this.bases, {this.version = 1});

  final List<CatalogBase> bases;
  final int version;

  factory BaseCatalog.parse(String text) {
    final j = (jsonDecode(text) as Map).cast<String, Object?>();
    return BaseCatalog([
      for (final b in (j['bases'] as List?) ?? const []) CatalogBase.fromJson((b as Map).cast<String, Object?>()),
    ], version: (j['version'] as num?)?.toInt() ?? 1);
  }

  CatalogBase? byId(String id) {
    for (final b in bases) {
      if (b.id == id) return b;
    }
    return null;
  }

  CatalogBase? bySha1(String sha1) {
    for (final b in bases) {
      if (b.sha1 != null && b.sha1!.toLowerCase() == sha1.toLowerCase()) return b;
    }
    return null;
  }

  /// Bases whose name, maker or collection contains every word of [query].
  List<CatalogBase> search(String query, {bool exactOnly = false}) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return [
      for (final b in bases)
        if ((!exactOnly || b.exact) &&
            words.every((w) => '${b.name} ${b.maker} ${b.collection}'.toLowerCase().contains(w)))
          b,
    ];
  }
}

/// A download given up because something newer was asked for.
class DownloadCancelled implements Exception {
  @override
  String toString() => 'Cancelled';
}

class LibraryException implements Exception {
  LibraryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Downloads bases from the catalog and keeps them in a local cache.
///
/// The catalog ships with the app and is refreshed from the repository, so
/// new bases and checked transcriptions arrive without an app update.
class BaseLibrary {
  BaseLibrary({required this.cacheDir, http.Client? client}) : _client = client ?? http.Client();

  final String cacheDir;
  final http.Client _client;

  static const repoRaw = 'https://raw.githubusercontent.com/1ajh/video-effects-studio/main/bases/';
  static const issueUrl = 'https://github.com/1ajh/video-effects-studio/issues/new';

  String get _dir => p.join(cacheDir, 'bases');
  File get _catalogCache => File(p.join(_dir, 'catalog.json'));

  /// The newest catalog available: the cached remote copy when it's newer
  /// than [bundled], refreshed from the repository when [refresh] is set.
  Future<BaseCatalog> catalog(String bundled, {bool refresh = true}) async {
    var best = BaseCatalog.parse(bundled);
    try {
      if (await _catalogCache.exists()) {
        final cached = BaseCatalog.parse(await _catalogCache.readAsString());
        if (cached.bases.length >= best.bases.length || cached.version > best.version) best = cached;
      }
    } catch (_) {
      // A corrupt cache is ignored and replaced below.
    }
    if (!refresh) return best;
    try {
      final r = await _client.get(Uri.parse('${repoRaw}catalog.json')).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final remote = BaseCatalog.parse(r.body);
        if (remote.bases.isNotEmpty) {
          await Directory(_dir).create(recursive: true);
          await _catalogCache.writeAsString(r.body);
          return remote;
        }
      }
    } catch (_) {
      // Offline: the bundled or cached catalog is fine.
    }
    return best;
  }

  /// Local copy of [b]'s audio, downloaded on first use.
  Future<String> audio(CatalogBase b, {void Function(double fraction)? onProgress, bool Function()? cancelled}) =>
      _fetch(
        b.audioUrl,
        p.join(_dir, '${b.fileStem}${b.extension}'),
        expectedSize: b.size,
        onProgress: onProgress,
        cancelled: cancelled,
      );

  /// Local copy of [b]'s FL Studio project, if it has one.
  Future<String?> project(CatalogBase b) async {
    final url = b.flpUrl;
    if (url == null) return null;
    return _fetch(url, p.join(_dir, '${b.fileStem}.flp'));
  }

  /// The checked transcription for [b], if the repository has one: the
  /// newest from the repository, else the last one fetched, else the copy
  /// shipped with the app ([bundled] reads it).
  Future<BaseTranscription?> checkedTranscription(
    CatalogBase b, {
    Future<String?> Function(String path)? bundled,
  }) async {
    final path = b.transcriptionPath;
    if (path == null) return null;
    final local = File(p.join(_dir, 'transcriptions', p.basename(path)));
    try {
      final r = await _client.get(Uri.parse('$repoRaw$path')).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        BaseTranscription.decode(r.body);
        await local.parent.create(recursive: true);
        await local.writeAsString(r.body);
      }
    } catch (_) {
      // Offline or not published yet: use a local copy below.
    }
    try {
      if (await local.exists()) return BaseTranscription.decode(await local.readAsString());
    } catch (_) {
      // A broken cache: fall back to the shipped copy.
    }
    final shipped = await bundled?.call(path);
    return shipped == null ? null : BaseTranscription.decode(shipped);
  }

  /// Whether [b] is already downloaded.
  Future<bool> isDownloaded(CatalogBase b) async {
    final f = File(p.join(_dir, '${b.fileStem}${b.extension}'));
    if (!await f.exists()) return false;
    return b.size == null || await f.length() == b.size;
  }

  Future<String> _fetch(
    String url,
    String path, {
    int? expectedSize,
    void Function(double fraction)? onProgress,
    bool Function()? cancelled,
  }) async {
    final file = File(path);
    if (await file.exists() && (expectedSize == null || await file.length() == expectedSize)) return path;
    await file.parent.create(recursive: true);
    // A unique partial file: an abandoned download can't collide with this one.
    final part = File('$path.${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}.part');
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw LibraryException('Download failed (${response.statusCode}): ${Uri.decodeFull(p.basename(url))}');
    }
    final total = response.contentLength ?? expectedSize;
    final sink = part.openWrite();
    var got = 0;
    var stopped = false;
    try {
      await for (final chunk in response.stream) {
        if (cancelled?.call() ?? false) {
          stopped = true;
          break;
        }
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) onProgress?.call(got / total);
      }
    } finally {
      await sink.close();
    }
    if (stopped || got == 0) {
      try {
        await part.delete();
      } catch (_) {}
      if (stopped) throw DownloadCancelled();
      throw LibraryException('The download was empty.');
    }
    // Another download may have finished it meanwhile.
    if (await file.exists() && (expectedSize == null || await file.length() == expectedSize)) {
      try {
        await part.delete();
      } catch (_) {}
      return path;
    }
    try {
      await part.rename(path);
    } on FileSystemException {
      // The file is in use (being read by an earlier load): copy over it later.
      if (!await file.exists()) rethrow;
      try {
        await part.delete();
      } catch (_) {}
    }
    onProgress?.call(1);
    return path;
  }

  /// SHA-1 of a file (how bases are recognised).
  static Future<String> sha1Of(String path) async => (await sha1.bind(File(path).openRead()).first).toString();

  /// Where "Submit transcription" saves the file to attach.
  static String submissionFileName(BaseTranscription t) {
    final name = (t.baseName.isEmpty ? 'base' : t.baseName).replaceAll(RegExp(r'[^A-Za-z0-9 ._-]+'), '').trim();
    return '$name.sparta.json';
  }

  /// The prefilled GitHub issue for sending in a fixed transcription.
  static Uri submissionUrl(BaseTranscription t, {String credit = '', String notes = ''}) {
    final title = 'Transcription: ${t.baseName.isEmpty ? 'unnamed base' : t.baseName}';
    return Uri.parse(issueUrl).replace(
      queryParameters: {
        'template': 'base-transcription.yml',
        'title': title,
        'labels': 'transcription',
        'base': t.baseName,
        'maker': t.maker,
        'catalog': t.catalogId,
        'sha1': t.audioSha1,
        'credit': credit,
        if (notes.isNotEmpty) 'notes': notes,
      },
    );
  }
}
