import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lets the UI stop a running render.
class CancelToken {
  bool _cancelled = false;
  final Set<Process> _processes = {};

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    for (final proc in _processes.toList()) {
      proc.kill(ProcessSignal.sigkill);
    }
  }

  void _attach(Process proc) {
    _processes.add(proc);
    if (_cancelled) proc.kill(ProcessSignal.sigkill);
  }

  void _detach(Process proc) => _processes.remove(proc);
}

class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => 'Cancelled';
}

class FfmpegException implements Exception {
  FfmpegException(this.message, {this.exitCode, this.log = ''});
  final String message;
  final int? exitCode;
  final String log;

  @override
  String toString() => message;
}

/// Runs FFmpeg with `-progress pipe:1` and reports fractional progress.
class FfmpegRunner {
  const FfmpegRunner(this.ffmpegPath);

  final String ffmpegPath;

  Future<void> run(
    List<String> args, {
    String? workingDirectory,
    double? expectedSeconds,
    void Function(double fraction)? onProgress,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw const CancelledException();

    final process = await Process.start(ffmpegPath, args, workingDirectory: workingDirectory, runInShell: false);
    cancel?._attach(process);

    final stderrLines = <String>[];
    final stderrDone = process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      stderrLines.add(line);
      if (stderrLines.length > 200) stderrLines.removeAt(0);
    }).asFuture<void>();

    final stdoutDone = process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (onProgress == null || expectedSeconds == null || expectedSeconds <= 0) return;
      final m = RegExp(r'^out_time_(?:us|ms)=(\d+)').firstMatch(line);
      if (m != null) {
        final seconds = int.parse(m.group(1)!) / 1e6;
        onProgress((seconds / expectedSeconds).clamp(0.0, 0.999));
      }
    }).asFuture<void>();

    final exitCode = await process.exitCode;
    await Future.wait([stderrDone, stdoutDone]).catchError((_) => const <void>[]);
    cancel?._detach(process);

    if (cancel?.isCancelled ?? false) throw const CancelledException();
    if (exitCode != 0) {
      throw FfmpegException(summarizeError(stderrLines, exitCode), exitCode: exitCode, log: stderrLines.join('\n'));
    }
    onProgress?.call(1.0);
  }

  /// Picks the most useful line out of FFmpeg's error output.
  static String summarizeError(List<String> lines, int exitCode) {
    final meaningful = lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    const keys = [
      'No such filter',
      'Error initializing filter',
      'Invalid argument',
      'No such file',
      'Permission denied',
      'Unknown encoder',
      'not found',
      'Error',
      'error',
      'Invalid',
    ];
    for (final key in keys) {
      for (final line in meaningful) {
        if (line.contains(key)) return line.replaceFirst(RegExp(r'^\[[^\]]+\]\s*'), '');
      }
    }
    if (meaningful.isNotEmpty) return meaningful.last;
    return 'FFmpeg exited with code $exitCode';
  }
}
