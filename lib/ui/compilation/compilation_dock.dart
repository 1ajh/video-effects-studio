import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/effects/effect.dart';
import '../../core/render/render_engine.dart';
import '../../state/compilation_controller.dart';
import '../../state/editor_controller.dart';
import '../../state/library_controller.dart';
import '../../state/project_controller.dart';
import '../../state/settings_controller.dart';
import '../actions.dart';
import '../browser/effect_thumb.dart';
import '../dialogs/preset_dialog.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Bottom dock: the ordered list of effects that play one after another.
class CompilationDock extends StatelessWidget {
  const CompilationDock({super.key});

  @override
  Widget build(BuildContext context) {
    final comp = context.watch<CompilationController>();
    final library = context.watch<LibraryController>();
    final settings = context.watch<SettingsController>();
    final clip = context.select<ProjectController, SourceClip?>((p) => p.active);
    final reg = library.registry;
    final inSecs = clip?.info == null ? null : clip!.trimmedLength;
    final estimate = inSecs == null
        ? null
        : comp.estimateSeconds(reg, inSecs, originalFirst: settings.originalFirst, labelMode: settings.labelMode);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: LayoutBuilder(
              builder: (context, c) {
                // Narrow windows get icon-only action buttons.
                final compact = c.maxWidth < 1320;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.view_timeline_outlined, size: 17, color: AppColors.compilation),
                      const SizedBox(width: 8),
                      const Text(
                        'COMPILATION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          color: AppColors.compilation,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          '${comp.length} effect${comp.length == 1 ? '' : 's'}'
                          '${estimate == null ? '' : ' · ${formatDuration(estimate)}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _OptionSwitch(
                        label: 'Original first',
                        value: settings.originalFirst,
                        onChanged: settings.setOriginalFirst,
                      ),
                      const SizedBox(width: 8),
                      _LabelModeMenu(value: settings.labelMode, onChanged: settings.setLabelMode),
                      const Spacer(),
                      _DockButton(
                        icon: Icons.select_all,
                        label: 'All effects',
                        compact: compact,
                        tooltip: 'Replace the list with every effect (${reg.all.length})',
                        onPressed: () async {
                          if (comp.length > 0 &&
                              !await confirmDelete(
                                context,
                                'Use every effect?',
                                'This replaces the current ${comp.length} items with all ${reg.all.length} effects.',
                                action: 'Replace',
                              )) {
                            return;
                          }
                          comp.selectAll(reg);
                        },
                      ),
                      _CategoryMenu(compact: compact, onSelected: (c) => comp.addCategory(reg, c)),
                      _DockButton(
                        icon: Icons.casino_outlined,
                        label: 'Random',
                        compact: compact,
                        tooltip: 'Pick N random effects',
                        onPressed: () => _randomDialog(context),
                      ),
                      _DockButton(
                        icon: Icons.shuffle,
                        label: 'Shuffle',
                        compact: compact,
                        tooltip: 'Shuffle the order',
                        onPressed: comp.length < 2 ? null : comp.shuffle,
                      ),
                      _DockButton(
                        icon: Icons.delete_sweep_outlined,
                        label: 'Clear',
                        compact: compact,
                        tooltip: 'Remove everything',
                        onPressed: comp.isEmpty ? null : comp.clear,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: comp.isEmpty
                ? _EmptyDock(onAll: () => comp.selectAll(reg))
                : _Timeline(comp: comp, library: library, originalFirst: settings.originalFirst),
          ),
        ],
      ),
    );
  }

  Future<void> _randomDialog(BuildContext context) async {
    final reg = context.read<LibraryController>().registry;
    final comp = context.read<CompilationController>();
    var count = 10.0;
    EffectCategory? category;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final pool = category == null ? reg.all.length : reg.inCategory(category!).length;
          final n = count.clamp(1, pool.toDouble()).round();
          return AlertDialog(
            title: const Text('Random compilation'),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<EffectCategory?>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Pick from'),
                    dropdownColor: AppColors.surface,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All effects')),
                      for (final c in reg.categories) DropdownMenuItem(value: c, child: Text(c.label)),
                    ],
                    onChanged: (v) => setState(() => category = v),
                  ),
                  const SizedBox(height: 14),
                  Text('$n effect${n == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Slider(
                    value: n.toDouble(),
                    min: 1,
                    max: pool.toDouble().clamp(1, 500),
                    divisions: pool > 1 ? pool - 1 : null,
                    onChanged: (v) => setState(() => count = v),
                  ),
                  const Text(
                    'Replaces the current list. No effect is picked twice.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Roll')),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      final pool = category == null ? reg.all.length : reg.inCategory(category!).length;
      comp.randomize(reg, count.clamp(1, pool.toDouble()).round(), category: category);
    }
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.comp, required this.library, required this.originalFirst});
  final CompilationController comp;
  final LibraryController library;
  final bool originalFirst;

  @override
  Widget build(BuildContext context) {
    final items = comp.items;
    return Row(
      children: [
        if (originalFirst) const Padding(padding: EdgeInsets.fromLTRB(12, 8, 0, 12), child: _OriginalCard()),
        Expanded(
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
            itemCount: items.length,
            onReorderItem: comp.move,
            proxyDecorator: (child, index, animation) => Material(color: Colors.transparent, child: child),
            itemBuilder: (context, i) {
              final item = items[i];
              final effect = library.registry.byId(item.effectId);
              return ReorderableDragStartListener(
                key: ValueKey(item.uid),
                index: i,
                child: _CompCard(
                  index: i,
                  effect: effect,
                  item: item,
                  selected: comp.selectedIndex == i,
                  onTap: () {
                    comp.select(comp.selectedIndex == i ? null : i);
                    context.read<EditorController>().setMode(EditorMode.compilation);
                  },
                  onRemove: () => comp.removeAt(i),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompCard extends StatelessWidget {
  const _CompCard({
    required this.index,
    required this.effect,
    required this.item,
    required this.selected,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final Effect? effect;
  final CompItem item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final e = effect;
    final color = e == null ? AppColors.faint : AppColors.category(e.category);
    return Hover(
      cursor: SystemMouseCursors.grab,
      builder: (context, hover) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 132,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.compilation.withValues(alpha: 0.12)
                : (hover ? AppColors.surfaceHi : AppColors.surface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? AppColors.compilation : AppColors.border, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: e == null
                          ? const SizedBox()
                          : LayoutBuilder(
                              builder: (context, c) =>
                                  EffectThumb(effect: e, params: item.params, width: c.maxWidth, height: c.maxHeight),
                            ),
                    ),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                    if (hover)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: InkWell(
                          onTap: onRemove,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 13, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      e?.name ?? 'Missing effect',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OriginalCard extends StatelessWidget {
  const _OriginalCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_outlined, size: 22, color: AppColors.faint),
          SizedBox(height: 6),
          Text(
            'Original',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
          Text('plays first', style: TextStyle(fontSize: 10.5, color: AppColors.faint)),
        ],
      ),
    );
  }
}

class _EmptyDock extends StatelessWidget {
  const _EmptyDock({required this.onAll});
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            const Text(
              'Add effects with the + button or by double-clicking — they play in order, one after another.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.compilation),
              onPressed: onAll,
              icon: const Icon(Icons.select_all, size: 16),
              label: const Text('Use every effect'),
            ),
            OutlinedButton.icon(
              onPressed: () => StudioActions(context).addTargetToCompilation(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add selected'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onPressed,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) => compact
      ? ToolButton(icon: icon, tooltip: '$label — $tooltip', onPressed: onPressed)
      : Tooltip(
          message: tooltip,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontSize: 12.5)),
          ),
        );
}

class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({required this.onSelected, this.compact = false});
  final ValueChanged<EffectCategory> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final reg = context.watch<LibraryController>().registry;
    return PopupMenuButton<EffectCategory>(
      tooltip: 'Append every effect in a category',
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final c in reg.categories)
          PopupMenuItem(
            value: c,
            child: Row(
              children: [
                Icon(AppColors.categoryIcon(c), size: 16, color: AppColors.category(c)),
                const SizedBox(width: 10),
                Expanded(child: Text(c.label)),
                Text('${reg.inCategory(c).length}', style: const TextStyle(color: AppColors.faint, fontSize: 12)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.library_add_outlined, size: 16, color: AppColors.muted),
            if (!compact) ...[
              const SizedBox(width: 6),
              const Text(
                'Add category',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
            ],
            const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _LabelModeMenu extends StatelessWidget {
  const _LabelModeMenu({required this.value, required this.onChanged});
  final LabelMode value;
  final ValueChanged<LabelMode> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<LabelMode>(
    tooltip: 'How each effect is labeled in the video',
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final m in LabelMode.values) CheckedPopupMenuItem(value: m, checked: m == value, child: Text(m.label)),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.label_outline, size: 15, color: AppColors.muted),
          const SizedBox(width: 6),
          Text(value.label, style: const TextStyle(fontSize: 12.5)),
          const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.muted),
        ],
      ),
    ),
  );
}

class _OptionSwitch extends StatelessWidget {
  const _OptionSwitch({required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: () => onChanged(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.75,
          child: Switch(value: value, onChanged: onChanged),
        ),
        Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
      ],
    ),
  );
}
