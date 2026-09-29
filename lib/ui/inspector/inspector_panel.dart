import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/effects/effect.dart';
import '../../state/compilation_controller.dart';
import '../../state/editor_controller.dart';
import '../../state/library_controller.dart';
import '../../state/preview_controller.dart';
import '../../state/project_controller.dart';
import '../actions.dart';
import '../browser/effect_thumb.dart';
import '../dialogs/custom_effect_dialog.dart';
import '../dialogs/preset_dialog.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'output_section.dart';
import 'param_editor.dart';

/// Right panel: the selected effect (or compilation item), its parameters,
/// presets and output settings.
class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final comp = context.watch<CompilationController>();
    final library = context.watch<LibraryController>();
    final target = resolveTarget(editor, comp, library);

    return Container(
      color: AppColors.panel,
      child: Column(
        children: [
          PanelHeader(
            title: target?.compIndex != null ? 'Compilation item' : 'Inspector',
            icon: Icons.tune,
            subtitle: target?.compIndex != null ? '#${target!.compIndex! + 1} of ${comp.length}' : null,
            trailing: [
              if (target?.compIndex != null)
                ToolButton(icon: Icons.close, tooltip: 'Back to browser selection', onPressed: () => comp.select(null)),
            ],
          ),
          Expanded(
            child: target == null
                ? const EmptyState(
                    icon: Icons.touch_app_outlined,
                    title: 'Pick an effect',
                    message: 'Choose something from the effect list to see its settings and a live preview.',
                  )
                : _EffectDetails(target: target),
          ),
          const Divider(),
          const OutputSection(),
        ],
      ),
    );
  }
}

class _EffectDetails extends StatelessWidget {
  const _EffectDetails({required this.target});
  final FxTarget target;

  @override
  Widget build(BuildContext context) {
    final effect = target.effect;
    final library = context.watch<LibraryController>();
    final editor = context.read<EditorController>();
    final comp = context.read<CompilationController>();
    final clip = context.select<ProjectController, SourceClip?>((p) => p.active);
    final color = AppColors.category(effect.category);
    final fav = library.isFavorite(effect.id);
    final params = target.params;

    void setParam(String id, Object? v) {
      if (target.compIndex != null) {
        comp.setItemParam(target.compIndex!, id, v);
      } else {
        editor.setParam(effect, id, v);
      }
    }

    void setAll(Map<String, Object?> values) {
      if (target.compIndex != null) {
        comp.setItemParams(target.compIndex!, values);
      } else {
        editor.setParams(effect, values);
      }
    }

    final inSeconds = clip?.info == null ? null : clip!.trimmedLength;
    final outSeconds = inSeconds == null ? null : effect.outputSecondsFor(params, inSeconds);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EffectThumb(effect: effect, params: params, width: 96, height: 56, radius: 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(effect.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 17)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(
                        effect.category.label,
                        color: color,
                        icon: AppColors.categoryIcon(effect.category),
                        filled: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ToolButton(
              icon: fav ? Icons.star : Icons.star_border,
              tooltip: fav ? 'Remove from favorites' : 'Add to favorites',
              color: fav ? AppColors.warn : null,
              onPressed: () => library.toggleFavorite(effect.id),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(effect.description, style: const TextStyle(fontSize: 13, color: AppColors.text, height: 1.45)),
        if (effect.credit != null) ...[
          const SizedBox(height: 6),
          Text(effect.credit!, style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (effect.loud)
              const Pill(
                'Loud',
                color: AppColors.warn,
                icon: Icons.volume_up,
                tooltip: 'Authentic volume, no limiter — turn your speakers down',
              ),
            if (effect.heavy)
              const Pill(
                'Buffers clip',
                icon: Icons.hourglass_bottom,
                tooltip: 'Reverses or buffers the whole clip in memory — best on short clips',
              ),
            if (effect.video == null) const Pill('Audio only', icon: Icons.graphic_eq),
            if (effect.audio == null && effect.video != null) const Pill('Video only', icon: Icons.movie_outlined),
            if (outSeconds != null && (outSeconds - inSeconds!).abs() > 0.05)
              Pill(
                '${formatDuration(inSeconds, precise: true)} → ${formatDuration(outSeconds, precise: true)}',
                icon: Icons.timelapse,
                color: AppColors.compilation,
              ),
            if (effect.custom) const Pill('Custom', icon: Icons.code),
          ],
        ),
        if (effect.params.isNotEmpty) ...[
          SectionLabel(
            'Parameters',
            trailing: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
              onPressed: () => setAll(effect.defaults()),
              child: const Text('Reset all', style: TextStyle(fontSize: 12)),
            ),
          ),
          for (final p in effect.params)
            ParamEditor(
              key: ValueKey('${effect.id}/${target.compIndex}/${p.id}'),
              param: p,
              value: params[p.id],
              onChanged: (v) => setParam(p.id, v),
            ),
          _PresetRow(effect: effect, params: params, onApply: setAll),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => StudioActions(context).previewNow(),
                icon: const Icon(Icons.play_circle_outline, size: 17),
                label: const Text('Preview'),
              ),
            ),
            const SizedBox(width: 8),
            if (target.compIndex == null)
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.compilation),
                  onPressed: () => StudioActions(context).addToCompilation(effect),
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('Add to comp'),
                ),
              )
            else
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => comp.removeAt(target.compIndex!),
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: const Text('Remove'),
                ),
              ),
          ],
        ),
        if (effect.custom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => showCustomEffectDialog(context, existing: library.customById(effect.id)),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit custom effect'),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () async {
                  final ok = await confirmDelete(
                    context,
                    'Delete "${effect.name}"?',
                    'It will also be removed from favorites and the compilation.',
                  );
                  if (ok && context.mounted) {
                    library.deleteCustom(effect.id);
                    context.read<CompilationController>().prune(library.registry);
                  }
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.effect, required this.params, required this.onApply});
  final Effect effect;
  final Map<String, Object?> params;
  final ValueChanged<Map<String, Object?>> onApply;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryController>();
    final presets = library.presetsFor(effect.id);
    return Row(
      children: [
        Expanded(
          child: PopupMenuButton<String>(
            tooltip: 'Load a preset',
            enabled: presets.isNotEmpty,
            onSelected: (name) => onApply({...effect.defaults(), ...presets.firstWhere((p) => p.name == name).values}),
            itemBuilder: (_) => [
              for (final p in presets)
                PopupMenuItem(
                  value: p.name,
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark_outline, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.name)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        tooltip: 'Delete preset',
                        onPressed: () {
                          library.deletePreset(effect.id, p.name);
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bookmarks_outlined, size: 15, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      presets.isEmpty ? 'No presets yet' : '${presets.length} preset${presets.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                    ),
                  ),
                  if (presets.isNotEmpty) const Icon(Icons.expand_more, size: 16),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        ToolButton(
          icon: Icons.bookmark_add_outlined,
          tooltip: 'Save these settings as a preset',
          onPressed: () async {
            final name = await askPresetName(context);
            if (name != null && context.mounted) {
              library.savePreset(effect.id, name, params);
              showMessage(context, 'Saved preset "$name".');
            }
          },
        ),
      ],
    );
  }
}
