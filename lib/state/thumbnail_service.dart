import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Generates effect thumbnails in the background with limited concurrency.
///
/// Widgets call [request] while building (idempotent) and read [pathFor];
/// listeners are notified as images arrive.
class ThumbnailService extends ChangeNotifier {
  ThumbnailService({this.maxConcurrent = 3});

  final int maxConcurrent;
  final Map<String, String?> _done = {};
  final Set<String> _pending = {};
  final Queue<(String, Future<String?> Function())> _queue = Queue();
  int _running = 0;
  int _generation = 0;
  bool _notifyScheduled = false;

  String? pathFor(String key) => _done[key];
  bool isDone(String key) => _done.containsKey(key);

  void request(String key, Future<String?> Function() producer) {
    if (_done.containsKey(key) || _pending.contains(key)) return;
    _pending.add(key);
    // Newest requests first: the user is looking at them right now.
    _queue.addFirst((key, producer));
    _pump();
  }

  /// Forget queued work (e.g. the source clip changed). Finished thumbnails
  /// stay cached.
  void cancelPending() {
    _generation++;
    for (final (key, _) in _queue) {
      _pending.remove(key);
    }
    _queue.clear();
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final (key, producer) = _queue.removeFirst();
      final gen = _generation;
      _running++;
      producer().then<String?>((v) => v, onError: (_) => null).then((path) {
        _running--;
        _pending.remove(key);
        if (gen == _generation || path != null) {
          _done[key] = path;
          _scheduleNotify();
        }
        _pump();
      });
    }
  }

  // Batch bursts of finished thumbnails into one rebuild per frame-ish.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    Future.delayed(const Duration(milliseconds: 60), () {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}
