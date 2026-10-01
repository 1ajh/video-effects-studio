import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/render_queue.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Slide-out list of render jobs.
class QueueDrawer extends StatelessWidget {
  const QueueDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = context.watch<RenderQueue>();
    final jobs = queue.jobs;
    return Drawer(
      width: 420,
      child: SafeArea(
        child: Column(
          children: [
            PanelHeader(
              title: 'Render queue',
              icon: Icons.layers_outlined,
              subtitle: queue.activeCount > 0 ? '${queue.activeCount} active' : null,
              trailing: [
                if (jobs.any((j) => j.isFinished))
                  ConfirmTextButton(label: 'Clear finished', onConfirmed: queue.clearFinished),
                ToolButton(icon: Icons.close, tooltip: 'Close', onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            Expanded(
              child: jobs.isEmpty
                  ? const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'Nothing rendering',
                      message: 'Press Render (Ctrl+Enter) and your jobs show up here.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: jobs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _JobCard(job: jobs[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text button that needs a second click (within a few seconds) to act,
/// so finished jobs aren't cleared by a stray click.
class ConfirmTextButton extends StatefulWidget {
  const ConfirmTextButton({super.key, required this.label, required this.onConfirmed});
  final String label;
  final VoidCallback onConfirmed;

  @override
  State<ConfirmTextButton> createState() => _ConfirmTextButtonState();
}

class _ConfirmTextButtonState extends State<ConfirmTextButton> {
  Timer? _armed;

  @override
  void dispose() {
    _armed?.cancel();
    super.dispose();
  }

  void _press() {
    if (_armed != null) {
      _armed!.cancel();
      setState(() => _armed = null);
      widget.onConfirmed();
      return;
    }
    setState(() => _armed = Timer(const Duration(seconds: 3), () => mounted ? setState(() => _armed = null) : null));
  }

  @override
  Widget build(BuildContext context) {
    final armed = _armed != null;
    return Tooltip(
      message: armed ? 'Click again to confirm' : 'Click twice to clear',
      child: TextButton(
        onPressed: _press,
        style: armed ? TextButton.styleFrom(foregroundColor: AppColors.warn) : null,
        child: Text(armed ? 'Click again to clear' : widget.label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final RenderJob job;

  @override
  Widget build(BuildContext context) {
    final queue = context.read<RenderQueue>();
    final (color, icon) = switch (job.status) {
      JobStatus.queued => (AppColors.muted, Icons.schedule),
      JobStatus.running => (AppColors.accentHi, Icons.autorenew),
      JobStatus.done => (AppColors.success, Icons.check_circle),
      JobStatus.failed => (AppColors.danger, Icons.error),
      JobStatus.cancelled => (AppColors.faint, Icons.cancel_outlined),
    };
    final eta = job.eta;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: job.status == JobStatus.running ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                job.isCompilation ? Icons.view_timeline_outlined : Icons.auto_awesome_outlined,
                size: 16,
                color: job.isCompilation ? AppColors.compilation : AppColors.accentHi,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            job.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.faint),
          ),
          const SizedBox(height: 10),
          if (!job.isFinished)
            LinearProgressIndicator(
              value: job.status == JobStatus.running && job.progress > 0.005 ? job.progress : null,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  job.error ??
                      '${job.statusText}'
                          '${job.status == JobStatus.running ? ' · ${(job.progress * 100).round()}%' : ''}'
                          '${eta == null ? '' : ' · ${formatDuration(eta.inMilliseconds / 1000)} left'}'
                          '${job.isFinished && job.elapsed != null && job.status == JobStatus.done ? ' in ${formatDuration(job.elapsed!.inMilliseconds / 1000)}' : ''}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: job.error != null ? AppColors.danger : AppColors.muted),
                ),
              ),
            ],
          ),
          if (job.failures.isNotEmpty) ...[
            const SizedBox(height: 6),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                '${job.failures.length} effect${job.failures.length == 1 ? '' : 's'} skipped',
                style: const TextStyle(fontSize: 12, color: AppColors.warn),
              ),
              children: [
                for (final f in job.failures)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: SelectableText(
                        '${f.effectName}: ${f.message}',
                        style: const TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (!job.isFinished)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(0, 30)),
                  onPressed: () => queue.cancel(job),
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Cancel', style: TextStyle(fontSize: 12)),
                ),
              if (job.status == JobStatus.done && job.outputPath != null) ...[
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 30)),
                  onPressed: () => openFile(job.outputPath!),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Play', style: TextStyle(fontSize: 12)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 30)),
                  onPressed: () => showInFolder(job.outputPath!),
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Show in folder', style: TextStyle(fontSize: 12)),
                ),
              ],
              const Spacer(),
              if (job.isFinished)
                ToolButton(
                  icon: Icons.close,
                  tooltip: 'Remove from list',
                  size: 15,
                  onPressed: () => queue.remove(job),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
