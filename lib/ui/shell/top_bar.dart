import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/compilation_controller.dart';
import '../../state/editor_controller.dart';
import '../../state/project_controller.dart';
import '../../state/render_queue.dart';
import '../../state/update_controller.dart';
import '../actions.dart';
import '../dialogs/help_dialog.dart';
import '../pages/history_page.dart';
import '../pages/settings_page.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final comp = context.watch<CompilationController>();
    final queue = context.watch<RenderQueue>();
    final updates = context.watch<UpdateController>();
    final project = context.watch<ProjectController>();
    final compMode = editor.mode == EditorMode.compilation;
    final canRender = project.active?.info != null && (compMode ? !comp.isEmpty : editor.selected != null);

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [AppColors.accent, Color(0xFFE040FB), AppColors.compilation],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.auto_awesome, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text(
            'Video Effects Studio',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.1),
          ),
          const SizedBox(width: 24),
          SegmentedButton<EditorMode>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: EditorMode.single,
                icon: Icon(Icons.auto_awesome_outlined, size: 15),
                label: Text('Single effect'),
              ),
              ButtonSegment(
                value: EditorMode.compilation,
                icon: const Icon(Icons.view_timeline_outlined, size: 15),
                label: Text(comp.isEmpty ? 'Compilation' : 'Compilation (${comp.length})'),
              ),
            ],
            selected: {editor.mode},
            onSelectionChanged: (s) => editor.setMode(s.first),
          ),
          const Spacer(),
          if (updates.available != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.system_update_alt, size: 15, color: AppColors.success),
                label: Text('Update ${updates.available!.latest}', style: const TextStyle(fontSize: 12)),
                onPressed: () => openUrl(updates.available!.url),
              ),
            ),
          ToolButton(
            icon: Icons.history,
            tooltip: 'Render history (Ctrl+H)',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage())),
          ),
          ToolButton(
            icon: Icons.keyboard_outlined,
            tooltip: 'Shortcuts & help (F1)',
            onPressed: () => showHelpDialog(context),
          ),
          ToolButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings (Ctrl+,)',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          const SizedBox(width: 6),
          _QueueButton(queue: queue),
          const SizedBox(width: 10),
          _RenderButton(enabled: canRender, compMode: compMode, count: comp.length, clips: project.sources.length),
        ],
      ),
    );
  }
}

class _QueueButton extends StatelessWidget {
  const _QueueButton({required this.queue});
  final RenderQueue queue;

  @override
  Widget build(BuildContext context) {
    final progress = queue.overallProgress;
    final active = queue.activeCount;
    return Tooltip(
      message: 'Render queue',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Scaffold.of(context).openEndDrawer(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: active > 0 ? AppColors.accent.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active > 0 ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border),
          ),
          child: Row(
            children: [
              if (progress != null)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.2, value: progress > 0.01 ? progress : null),
                )
              else
                const Icon(Icons.layers_outlined, size: 17, color: AppColors.muted),
              const SizedBox(width: 8),
              Text(
                progress != null
                    ? '${(progress * 100).round()}% · $active'
                    : 'Queue${queue.jobs.isEmpty ? '' : ' · ${queue.jobs.length}'}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenderButton extends StatelessWidget {
  const _RenderButton({required this.enabled, required this.compMode, required this.count, required this.clips});
  final bool enabled;
  final bool compMode;
  final int count;
  final int clips;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: compMode ? AppColors.compilation : AppColors.accent,
        foregroundColor: compMode ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: enabled ? () => StudioActions(context).render() : null,
      icon: const Icon(Icons.rocket_launch_outlined, size: 17),
      label: Text(compMode ? 'Render compilation' : 'Render'),
    );
    if (compMode || clips < 2) {
      return Tooltip(message: 'Ctrl+Enter', child: button);
    }
    // Batch: offer "all clips" next to the main button.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(message: 'Render the active clip (Ctrl+Enter)', child: button),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'More render options',
          enabled: enabled,
          onSelected: (_) => StudioActions(context).renderSingle(allClips: true),
          itemBuilder: (_) => [PopupMenuItem(value: 'all', child: Text('Render all $clips clips with this effect'))],
          icon: const Icon(Icons.arrow_drop_down),
        ),
      ],
    );
  }
}
