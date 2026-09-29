import 'package:flutter/foundation.dart';

import 'store.dart';

class HistoryEntry {
  const HistoryEntry({
    required this.title,
    required this.source,
    required this.success,
    required this.timestamp,
    this.outputPath,
    this.message,
    this.seconds,
  });

  final String title;
  final String source;
  final bool success;
  final DateTime timestamp;
  final String? outputPath;
  final String? message;

  /// Wall-clock render time.
  final double? seconds;

  Map<String, Object?> toJson() => {
    'title': title,
    'source': source,
    'success': success,
    'timestamp': timestamp.toIso8601String(),
    'outputPath': outputPath,
    'message': message,
    'seconds': seconds,
  };

  factory HistoryEntry.fromJson(Map<String, Object?> j) => HistoryEntry(
    title: j['title'] as String? ?? '',
    source: j['source'] as String? ?? '',
    success: j['success'] as bool? ?? false,
    timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
    outputPath: j['outputPath'] as String?,
    message: j['message'] as String?,
    seconds: (j['seconds'] as num?)?.toDouble(),
  );
}

class HistoryController extends ChangeNotifier {
  HistoryController(this._store) {
    _entries = [
      for (final e in (_store.readJson<List>('history') ?? const []).cast<Map>())
        HistoryEntry.fromJson(e.cast<String, Object?>()),
    ];
  }

  final Store _store;
  late List<HistoryEntry> _entries;

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  void add(HistoryEntry e) {
    _entries.insert(0, e);
    if (_entries.length > 300) _entries = _entries.sublist(0, 300);
    _persist();
  }

  void remove(HistoryEntry e) {
    _entries.remove(e);
    _persist();
  }

  void clear() {
    _entries.clear();
    _persist();
  }

  void _persist() {
    _store.writeJson('history', [for (final e in _entries) e.toJson()]);
    notifyListeners();
  }
}
