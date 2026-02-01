import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_state.dart';
import 'dart:io';

class ProcessingDialog extends StatelessWidget {
  const ProcessingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final isComplete = !appState.isProcessing && appState.results.isNotEmpty;

        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isComplete) ...[
                  // Processing State
                  const SizedBox(height: 20),
                  CircularPercentIndicator(
                    radius: 60,
                    lineWidth: 8,
                    percent: appState.processingProgress.clamp(0.0, 1.0),
                    center: Text(
                      '${(appState.processingProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    progressColor: Theme.of(context).colorScheme.primary,
                    backgroundColor: const Color(0xFF2A2A2A),
                    circularStrokeCap: CircularStrokeCap.round,
                    animation: true,
                    animateFromLastPercent: true,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    appState.processingStatus,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: () {
                      appState.cancelProcessing();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ] else ...[
                  // Complete State
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Processing Complete!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${appState.results.where((r) => r.success).length} of ${appState.results.length} files processed successfully',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[400],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // Results List
                  if (appState.results.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: appState.results.length,
                        itemBuilder: (context, index) {
                          final result = appState.results[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              result.success
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: result.success ? Colors.green : Colors.red,
                              size: 20,
                            ),
                            title: Text(
                              result.success 
                                  ? (result.outputPath?.split('/').last.split('\\').last ?? 'Output')
                                  : 'Processing failed',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: result.success 
                                ? null 
                                : Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      result.message,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.red[300],
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                            trailing: result.success && result.outputPath != null
                                ? IconButton(
                                    icon: const Icon(Icons.folder_open, size: 18),
                                    onPressed: () => _openFileLocation(result.outputPath!),
                                    tooltip: 'Open location',
                                  )
                                : null,
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (appState.results.any((r) => r.success && r.outputPath != null))
                        ElevatedButton.icon(
                          onPressed: () => _openOutputFolder(appState),
                          icon: const Icon(Icons.folder, size: 18),
                          label: const Text('Open Folder'),
                        ),
                      ElevatedButton.icon(
                        onPressed: () {
                          appState.clearResults();
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openFileLocation(String filePath) async {
    try {
      final file = File(filePath);
      final directory = file.parent.path;
      
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [directory]);
      }
    } catch (e) {
      print('Could not open file location: $e');
    }
  }

  void _openOutputFolder(AppState appState) async {
    final successResult = appState.results.firstWhere(
      (r) => r.success && r.outputPath != null,
      orElse: () => appState.results.first,
    );

    if (successResult.outputPath != null) {
      final file = File(successResult.outputPath!);
      final directory = file.parent.path;

      try {
        if (Platform.isWindows) {
          await Process.run('explorer', [directory]);
        } else if (Platform.isMacOS) {
          await Process.run('open', [directory]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [directory]);
        } else {
          // Mobile - use url_launcher
          final uri = Uri.directory(directory);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        }
      } catch (e) {
        print('Could not open folder: $e');
      }
    }
  }
}
