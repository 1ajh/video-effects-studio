import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ffmpeg/ffmpeg_runner.dart';
import '../core/render/render_engine.dart';
import 'history_controller.dart';

enum JobStatus { queued, running, done, failed, cancelled }

class RenderJob extends ChangeNotifier {
  RenderJob({required this.title, required this.subtitle, required this.isCompilation, required this.task})
    : id = '${DateTime.now().microsecondsSinceEpoch}';

  final String id;
  final String title;
  final String subtitle;
  final bool isCompilation;
  final Future<RenderOutcome> Function(RenderJob job, CancelToken cancel) task;

  final CancelToken cancelToken = CancelToken();
  JobStatus status = JobStatus.queued;
  double progress = 0;
  String statusText = 'Queued';
  String? outputPath;
  String? error;
  List<SegmentFailure> failures = const [];
  DateTime? startedAt;
  DateTime? finishedAt;

  bool get isFinished => status == JobStatus.done || status == JobStatus.failed || status == JobStatus.cancelled;

  Duration? get elapsed => startedAt == null ? null : (finishedAt ?? DateTime.now()).difference(startedAt!);

  /// Rough time remaining based on progress so far.
  Duration? get eta {
    final e = elapsed;
    if (status != JobStatus.running || e == null || progress < 0.03) return null;
    final total = e.inMilliseconds / progress;
    return Duration(milliseconds: (total - e.inMilliseconds).round());
  }

  void report(double fraction, String text) {
    progress = fraction.clamp(0.0, 1.0);
    statusText = text;
    notifyListeners();
  }
}

/// Runs render jobs one at a time and records them in history.
class RenderQueue extends ChangeNotifier {
  RenderQueue(this._history);

  final HistoryController _history;
  final List<RenderJob> _jobs = [];
  final _finished = StreamController<RenderJob>.broadcast();
  bool _pumping = false;

  List<RenderJob> get jobs => List.unmodifiable(_jobs);
  Stream<RenderJob> get finished => _finished.stream;

  RenderJob? get current {
    for (final j in _jobs) {
      if (j.status == JobStatus.running) return j;
    }
    return null;
  }

  int get activeCount => _jobs.where((j) => !j.isFinished).length;

  /// Overall progress of unfinished work (0..1), or null when idle.
  double? get overallProgress {
    final active = _jobs.where((j) => !j.isFinished).toList();
    if (active.isEmpty) return null;
    return active.fold<double>(0, (s, j) => s + j.progress) / active.length;
  }

  void enqueue(RenderJob job) {
    _jobs.insert(0, job);
    job.addListener(notifyListeners);
    notifyListeners();
    _pump();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (true) {
        final next = _jobs.lastWhere((j) => j.status == JobStatus.queued, orElse: () => _sentinel);
        if (identical(next, _sentinel)) break;
        await _run(next);
      }
    } finally {
      _pumping = false;
    }
  }

  static final _sentinel = RenderJob(
    title: '',
    subtitle: '',
    isCompilation: false,
    task: (_, _) async => throw StateError('sentinel'),
  );

  Future<void> _run(RenderJob job) async {
    job
      ..status = JobStatus.running
      ..startedAt = DateTime.now()
      ..report(0, 'Starting…');
    try {
      final outcome = await job.task(job, job.cancelToken);
      job
        ..status = JobStatus.done
        ..outputPath = outcome.outputPath
        ..failures = outcome.failures;
      job.report(1, outcome.failures.isEmpty ? 'Done' : 'Done · ${outcome.failures.length} skipped');
    } on CancelledException {
      job.status = JobStatus.cancelled;
      job.report(job.progress, 'Cancelled');
    } catch (e) {
      job
        ..status = JobStatus.failed
        ..error = '$e';
      job.report(job.progress, 'Failed');
    }
    job.finishedAt = DateTime.now();
    notifyListeners();
    if (job.status != JobStatus.cancelled) {
      _history.add(
        HistoryEntry(
          title: job.title,
          source: job.subtitle,
          success: job.status == JobStatus.done,
          timestamp: job.finishedAt!,
          outputPath: job.outputPath,
          message:
              job.error ??
              (job.failures.isEmpty ? null : 'Skipped: ${job.failures.map((f) => f.effectName).join(', ')}'),
          seconds: job.elapsed!.inMilliseconds / 1000,
        ),
      );
    }
    _finished.add(job);
  }

  void cancel(RenderJob job) {
    if (job.status == JobStatus.queued) {
      job.status = JobStatus.cancelled;
      job.report(0, 'Cancelled');
      job.finishedAt = DateTime.now();
    } else if (job.status == JobStatus.running) {
      job.cancelToken.cancel();
      job.report(job.progress, 'Cancelling…');
    }
  }

  void cancelAll() {
    for (final j in _jobs) {
      cancel(j);
    }
  }

  void remove(RenderJob job) {
    if (!job.isFinished) return;
    _jobs.remove(job);
    job.removeListener(notifyListeners);
    notifyListeners();
  }

  void clearFinished() {
    for (final j in _jobs.where((j) => j.isFinished).toList()) {
      _jobs.remove(j);
      j.removeListener(notifyListeners);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    cancelAll();
    _finished.close();
    super.dispose();
  }
}
