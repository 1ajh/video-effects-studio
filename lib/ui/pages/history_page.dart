import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/history_controller.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryController>();
    final entries = history.entries
        .where(
          (e) => switch (_filter) {
            'ok' => e.success,
            'failed' => !e.success,
            _ => true,
          },
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        surfaceTintColor: Colors.transparent,
        title: const Text('Render history', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'ok', label: Text('Succeeded')),
              ButtonSegment(value: 'failed', label: Text('Failed')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: history.entries.isEmpty ? null : history.clear, child: const Text('Clear all')),
          const SizedBox(width: 12),
        ],
      ),
      body: entries.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'No renders yet',
              message: 'Finished and failed renders are listed here.',
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final exists = e.outputPath != null && File(e.outputPath!).existsSync();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            e.success ? Icons.check_circle : Icons.error,
                            color: e.success ? AppColors.success : AppColors.danger,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                const SizedBox(height: 3),
                                Text(
                                  '${e.source} · ${_when(e.timestamp)}'
                                  '${e.seconds == null ? '' : ' · took ${formatDuration(e.seconds!)}'}',
                                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                ),
                                if (e.message != null) ...[
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    e.message!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: e.success ? AppColors.warn : AppColors.danger,
                                    ),
                                  ),
                                ],
                                if (e.outputPath != null && !exists)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      'File was moved or deleted',
                                      style: TextStyle(fontSize: 11.5, color: AppColors.faint),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (exists) ...[
                            ToolButton(
                              icon: Icons.play_arrow,
                              tooltip: 'Play',
                              onPressed: () => openFile(e.outputPath!),
                            ),
                            ToolButton(
                              icon: Icons.folder_open,
                              tooltip: 'Show in folder',
                              onPressed: () => showInFolder(e.outputPath!),
                            ),
                          ],
                          ToolButton(icon: Icons.close, tooltip: 'Remove entry', onPressed: () => history.remove(e)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
    );
  }

  static String _when(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
