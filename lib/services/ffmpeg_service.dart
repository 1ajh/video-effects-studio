import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/effect_mode.dart';

/// Service for processing videos with FFmpeg
class FFmpegService {
  static String? _ffmpegPath;
  static Process? _currentProcess;

  /// Get the path to the FFmpeg executable
  /// Checks for bundled FFmpeg first, then falls back to system FFmpeg
  static Future<String?> _getFFmpegPath() async {
    if (_ffmpegPath != null) return _ffmpegPath;
    
    // Get the directory where the executable is located
    final executableDir = path.dirname(Platform.resolvedExecutable);
    
    // Possible locations for bundled FFmpeg
    final possiblePaths = <String>[];
    
    if (Platform.isWindows) {
      // Windows: ffmpeg.exe in same directory as app
      possiblePaths.addAll([
        path.join(executableDir, 'ffmpeg.exe'),
        path.join(executableDir, 'bin', 'ffmpeg.exe'),
      ]);
    } else if (Platform.isMacOS) {
      // macOS: in MacOS/bin directory or MacOS directory
      possiblePaths.addAll([
        path.join(executableDir, 'bin', 'ffmpeg'),
        path.join(executableDir, 'ffmpeg'),
        // Also check in Resources
        path.join(executableDir, '..', 'Resources', 'ffmpeg'),
      ]);
    } else if (Platform.isLinux) {
      // Linux: in same directory as app or lib subdirectory
      possiblePaths.addAll([
        path.join(executableDir, 'ffmpeg'),
        path.join(executableDir, 'bin', 'ffmpeg'),
        path.join(executableDir, 'lib', 'ffmpeg'),
      ]);
    }
    
    // Check bundled paths first
    for (final ffmpegPath in possiblePaths) {
      final file = File(ffmpegPath);
      if (await file.exists()) {
        print('Found bundled FFmpeg at: $ffmpegPath');
        _ffmpegPath = ffmpegPath;
        return _ffmpegPath;
      }
    }
    
    // Fall back to system FFmpeg
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['ffmpeg'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final systemPath = result.stdout.toString().trim().split('\n').first;
        print('Using system FFmpeg at: $systemPath');
        _ffmpegPath = 'ffmpeg'; // Use system path
        return _ffmpegPath;
      }
    } catch (e) {
      print('Could not find system FFmpeg: $e');
    }
    
    return null;
  }

  /// Process a single video with the given effect
  static Future<ProcessResult> processVideo({
    required String inputPath,
    required EffectMode effect,
    required Map<String, dynamic> parameters,
    required Function(double progress) onProgress,
  }) async {
    if (kIsWeb) {
      return ProcessResult(
        success: false,
        message: 'Video processing is not available on web. Please download the desktop app.',
      );
    }

    try {
      // Verify input file exists
      final inputFile = File(inputPath);
      if (!await inputFile.exists()) {
        return ProcessResult(
          success: false,
          message: 'Input file not found: $inputPath',
        );
      }

      // Check if FFmpeg is available
      final ffmpegPath = await _getFFmpegPath();
      if (ffmpegPath == null) {
        return ProcessResult(
          success: false,
          message: 'FFmpeg is not available.\n\n'
              'The bundled FFmpeg was not found. Please reinstall the application or '
              'install FFmpeg manually:\n'
              '• Windows: winget install FFmpeg\n'
              '• Mac: brew install ffmpeg\n'
              '• Linux: sudo apt install ffmpeg',
        );
      }

      // Get output directory
      final outputDir = await _getOutputDirectory();
      final inputFileName = path.basenameWithoutExtension(inputPath);
      final outputExtension = _getOutputExtension(effect, parameters);
      final outputPath = path.join(
        outputDir.path,
        '${inputFileName}_${effect.id}_${DateTime.now().millisecondsSinceEpoch}.$outputExtension',
      );

      // Build the FFmpeg command
      String command = effect.buildCommand(inputPath, outputPath, parameters);
      
      // Clean up the command (remove newlines and extra spaces)
      command = command.trim().replaceAll(RegExp(r'\s+'), ' ');
      
      // Remove the 'ffmpeg' prefix for argument parsing
      if (command.startsWith('ffmpeg ')) {
        command = command.substring(7);
      }

      return await _processWithFFmpeg(
        ffmpegPath: ffmpegPath,
        command: command,
        outputPath: outputPath,
        onProgress: onProgress,
      );
    } catch (e, stackTrace) {
      print('FFmpeg processing error: $e');
      print('Stack trace: $stackTrace');
      return ProcessResult(
        success: false,
        message: 'Processing error: ${e.toString()}',
      );
    }
  }

  /// Process video using FFmpeg binary (bundled or system)
  static Future<ProcessResult> _processWithFFmpeg({
    required String ffmpegPath,
    required String command,
    required String outputPath,
    required Function(double progress) onProgress,
  }) async {
    try {
      // Parse the command string into arguments
      final args = _parseFFmpegArgs(command);
      
      // Add overwrite flag at the beginning
      final fullArgs = ['-y', ...args];
      
      print('Running FFmpeg with args: ${fullArgs.join(' ')}');
      
      _currentProcess = await Process.start(
        ffmpegPath,
        fullArgs,
        runInShell: Platform.isWindows,
      );

      final process = _currentProcess!;
      
      // Track progress from stderr (FFmpeg outputs progress to stderr)
      double duration = 0;
      final stderrBuffer = StringBuffer();
      
      process.stderr.transform(utf8.decoder).listen((data) {
        stderrBuffer.write(data);
        
        // Parse duration if not yet found
        if (duration == 0) {
          final durationMatch = RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})')
              .firstMatch(data);
          if (durationMatch != null) {
            duration = int.parse(durationMatch.group(1)!) * 3600.0 +
                int.parse(durationMatch.group(2)!) * 60.0 +
                int.parse(durationMatch.group(3)!).toDouble() +
                int.parse(durationMatch.group(4)!) / 100.0;
            print('Video duration: $duration seconds');
          }
        }
        
        // Parse current time position for progress
        final timeMatch = RegExp(r'time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})')
            .firstMatch(data);
        if (timeMatch != null && duration > 0) {
          final currentTime = int.parse(timeMatch.group(1)!) * 3600.0 +
              int.parse(timeMatch.group(2)!) * 60.0 +
              int.parse(timeMatch.group(3)!).toDouble() +
              int.parse(timeMatch.group(4)!) / 100.0;
          final progress = (currentTime / duration).clamp(0.0, 0.99);
          onProgress(progress);
        }
      });

      // Also listen to stdout (for any output)
      process.stdout.transform(utf8.decoder).listen((data) {
        print('FFmpeg stdout: $data');
      });

      final exitCode = await process.exitCode;
      _currentProcess = null;
      onProgress(1.0);

      if (exitCode == 0) {
        // Verify output file exists
        final outputFile = File(outputPath);
        if (await outputFile.exists()) {
          final fileSize = await outputFile.length();
          if (fileSize > 0) {
            return ProcessResult(
              success: true,
              outputPath: outputPath,
              message: 'Processing complete',
            );
          } else {
            return ProcessResult(
              success: false,
              message: 'Output file is empty',
            );
          }
        } else {
          return ProcessResult(
            success: false,
            message: 'Output file was not created',
          );
        }
      } else {
        final errorOutput = stderrBuffer.toString();
        // Extract the most relevant error message
        final errorLines = errorOutput.split('\n');
        String errorMsg = 'FFmpeg exited with code $exitCode';
        
        for (final line in errorLines.reversed) {
          if (line.toLowerCase().contains('error') ||
              line.toLowerCase().contains('invalid') ||
              line.toLowerCase().contains('no such') ||
              line.toLowerCase().contains('permission denied') ||
              line.toLowerCase().contains('not found')) {
            errorMsg = line.trim();
            break;
          }
        }
        
        return ProcessResult(
          success: false,
          message: errorMsg,
        );
      }
    } catch (e) {
      _currentProcess = null;
      return ProcessResult(
        success: false,
        message: 'Failed to run FFmpeg: $e',
      );
    }
  }

  /// Parse FFmpeg command string into argument list
  static List<String> _parseFFmpegArgs(String command) {
    final args = <String>[];
    final regex = RegExp(r'"([^"]+)"|(\S+)');
    
    for (final match in regex.allMatches(command)) {
      final quoted = match.group(1);
      final unquoted = match.group(2);
      args.add(quoted ?? unquoted ?? '');
    }
    
    return args.where((arg) => arg.isNotEmpty).toList();
  }

  /// Process multiple videos in batch
  static Stream<BatchProgressUpdate> processBatch({
    required List<String> inputPaths,
    required EffectMode effect,
    required Map<String, dynamic> parameters,
  }) async* {
    final results = <ProcessResult>[];
    
    for (int i = 0; i < inputPaths.length; i++) {
      final inputPath = inputPaths[i];
      
      yield BatchProgressUpdate(
        currentIndex: i,
        totalCount: inputPaths.length,
        currentFileName: path.basename(inputPath),
        currentProgress: 0.0,
        results: List.from(results),
      );

      final result = await processVideo(
        inputPath: inputPath,
        effect: effect,
        parameters: parameters,
        onProgress: (progress) {
          // Individual file progress is handled via the stream
        },
      );

      results.add(result);

      yield BatchProgressUpdate(
        currentIndex: i,
        totalCount: inputPaths.length,
        currentFileName: path.basename(inputPath),
        currentProgress: 1.0,
        results: List.from(results),
      );
    }
  }

  /// Get the output directory for processed videos
  static Future<Directory> _getOutputDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final outputDir = Directory(path.join(appDir.path, 'VideoEffectsStudio', 'Output'));
    
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    
    return outputDir;
  }

  /// Get video duration in seconds using FFmpeg
  static Future<double> _getVideoDuration(String inputPath) async {
    try {
      final ffmpegPath = await _getFFmpegPath();
      if (ffmpegPath == null) return 0;
      
      final result = await Process.run(
        ffmpegPath,
        ['-i', inputPath],
        runInShell: Platform.isWindows,
      );
      
      final output = result.stderr.toString();
      final durationMatch = RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})')
          .firstMatch(output);
      
      if (durationMatch != null) {
        final hours = int.parse(durationMatch.group(1)!);
        final minutes = int.parse(durationMatch.group(2)!);
        final seconds = int.parse(durationMatch.group(3)!);
        final centiseconds = int.parse(durationMatch.group(4)!);
        
        return hours * 3600 + minutes * 60 + seconds + centiseconds / 100;
      }
    } catch (_) {}
    
    return 0;
  }

  /// Determine output file extension based on effect and parameters
  static String _getOutputExtension(EffectMode effect, Map<String, dynamic> parameters) {
    if (parameters.containsKey('output_format')) {
      return parameters['output_format'] as String;
    }
    return 'mp4';
  }

  /// Cancel all running FFmpeg processes
  static Future<void> cancelAll() async {
    if (_currentProcess != null) {
      _currentProcess!.kill();
      _currentProcess = null;
    }
  }

  /// Get FFmpeg version info
  static Future<String> getVersion() async {
    try {
      final ffmpegPath = await _getFFmpegPath();
      if (ffmpegPath == null) return 'FFmpeg not found';
      
      final result = await Process.run(
        ffmpegPath,
        ['-version'],
        runInShell: Platform.isWindows,
      );
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final versionLine = output.split('\n').first;
        return versionLine;
      }
    } catch (_) {}
    return 'FFmpeg not found';
  }

  /// Check if FFmpeg is available
  static Future<bool> isAvailable() async {
    return await _getFFmpegPath() != null;
  }
}

/// Result of a single video processing operation
class ProcessResult {
  final bool success;
  final String? outputPath;
  final String message;

  ProcessResult({
    required this.success,
    this.outputPath,
    required this.message,
  });
}

/// Progress update for batch processing
class BatchProgressUpdate {
  final int currentIndex;
  final int totalCount;
  final String currentFileName;
  final double currentProgress;
  final List<ProcessResult> results;

  BatchProgressUpdate({
    required this.currentIndex,
    required this.totalCount,
    required this.currentFileName,
    required this.currentProgress,
    required this.results,
  });

  double get overallProgress {
    if (totalCount == 0) return 0;
    return (currentIndex + currentProgress) / totalCount;
  }

  int get successCount => results.where((r) => r.success).length;
  int get failureCount => results.where((r) => !r.success).length;
}
