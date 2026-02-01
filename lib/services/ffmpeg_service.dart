import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/effect_mode.dart';

/// Service for processing videos with FFmpeg
class FFmpegService {
  static bool? _useSystemFFmpeg;
  static Process? _currentProcess;

  /// Check if system FFmpeg is available
  static Future<bool> _checkSystemFFmpeg() async {
    if (_useSystemFFmpeg != null) return _useSystemFFmpeg!;
    
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['ffmpeg'],
        runInShell: true,
      );
      _useSystemFFmpeg = result.exitCode == 0;
    } catch (e) {
      _useSystemFFmpeg = false;
    }
    
    print('System FFmpeg available: $_useSystemFFmpeg');
    return _useSystemFFmpeg!;
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

      // Check if FFmpeg is available first
      final ffmpegAvailable = await _checkSystemFFmpeg();
      if (!ffmpegAvailable) {
        return ProcessResult(
          success: false,
          message: 'FFmpeg is not installed.\n\n'
              'Please install FFmpeg:\n'
              '• Windows: Download from https://ffmpeg.org/download.html and add to PATH\n'
              '• Mac: Run "brew install ffmpeg"\n'
              '• Linux: Run "sudo apt install ffmpeg"',
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

      return await _processWithSystemFFmpeg(
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

  /// Process video using system FFmpeg binary
  static Future<ProcessResult> _processWithSystemFFmpeg({
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
        'ffmpeg',
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

  /// Get video duration in seconds using system FFmpeg
  static Future<double> _getVideoDuration(String inputPath) async {
    try {
      final result = await Process.run(
        'ffmpeg',
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
      final result = await Process.run(
        'ffmpeg',
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
    return await _checkSystemFFmpeg();
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
