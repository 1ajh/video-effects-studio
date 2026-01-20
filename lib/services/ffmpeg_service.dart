import 'dart:io';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_min/statistics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/effect_mode.dart';

/// Service for processing videos with FFmpeg
class FFmpegService {
  /// Process a single video with the given effect
  static Future<ProcessResult> processVideo({
    required String inputPath,
    required EffectMode effect,
    required Map<String, dynamic> parameters,
    required Function(double progress) onProgress,
  }) async {
    try {
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
      
      // Remove the 'ffmpeg' prefix since FFmpegKit adds it
      if (command.startsWith('ffmpeg ')) {
        command = command.substring(7);
      }

      // Get video duration for progress calculation
      final duration = await _getVideoDuration(inputPath);

      // Execute FFmpeg command
      final session = await FFmpegKit.executeAsync(
        command,
        (session) async {
          final returnCode = await session.getReturnCode();
          if (ReturnCode.isSuccess(returnCode)) {
            onProgress(1.0);
          }
        },
        (log) {
          // Log callback - can be used for debugging
          print('FFmpeg Log: ${log.getMessage()}');
        },
        (Statistics statistics) {
          // Progress callback
          if (duration > 0) {
            final time = statistics.getTime();
            final progress = (time / 1000) / duration;
            onProgress(progress.clamp(0.0, 1.0));
          }
        },
      );

      // Wait for completion
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return ProcessResult(
          success: true,
          outputPath: outputPath,
          message: 'Processing complete',
        );
      } else if (ReturnCode.isCancel(returnCode)) {
        return ProcessResult(
          success: false,
          message: 'Processing cancelled',
        );
      } else {
        final logs = await session.getAllLogsAsString();
        return ProcessResult(
          success: false,
          message: 'Processing failed: $logs',
        );
      }
    } catch (e) {
      return ProcessResult(
        success: false,
        message: 'Error: $e',
      );
    }
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

  /// Get video duration in seconds
  static Future<double> _getVideoDuration(String inputPath) async {
    try {
      final session = await FFmpegKit.execute(
        '-i "$inputPath" -f null -',
      );
      final output = await session.getAllLogsAsString();
      
      // Parse duration from FFmpeg output
      final durationMatch = RegExp(r'Duration: (\d{2}):(\d{2}):(\d{2})\.(\d{2})')
          .firstMatch(output ?? '');
      
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
    // Check if output format is specified in parameters
    if (parameters.containsKey('output_format')) {
      return parameters['output_format'] as String;
    }
    
    // Default to mp4
    return 'mp4';
  }

  /// Cancel all running FFmpeg sessions
  static Future<void> cancelAll() async {
    await FFmpegKit.cancel();
  }

  /// Get FFmpeg version info
  static Future<String> getVersion() async {
    final session = await FFmpegKit.execute('-version');
    return await session.getOutput() ?? 'Unknown';
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
