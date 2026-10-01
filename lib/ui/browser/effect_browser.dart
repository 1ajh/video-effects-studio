import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/effects/effect.dart';
import '../../state/editor_controller.dart';
import '../../state/library_controller.dart';
import '../actions.dart';
import '../dialogs/custom_effect_dialog.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'effect_thumb.dart';

/// Left panel: search, filters and the effect list.
class EffectBrowser extends StatefulWidget {
  const EffectBrowser({super.key, required this.searchFocus});
  final FocusNode searchFocus;

  @override
  State<EffectBrowser> createState() => _EffectBrowserState();
}

class _EffectBrowserState extends State<EffectBrowser> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorController>();
    final library = context.watch<LibraryController>();
    final effects = editor.visibleEffects();

    return Container(
      color: AppColors.panel,
      child: Column(
        children: [
          PanelHeader(
            title: 'Effects',
            icon: Icons.auto_awesome_outlined,
            subtitle: '${library.registry.all.length}',
            trailing: [
              ToolButton(
                icon: Icons.add_box_outlined,
                tooltip: 'New custom effect',
                onPressed: () => showCustomEffectDialog(context),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _search,
              focusNode: widget.searchFocus,
              onChanged: editor.setSearch,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search effects  (Ctrl+F)',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: editor.search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _search.clear();
                          editor.setSearch('');
                        },
                      ),
              ),
              onSubmitted: (_) {
                if (effects.isNotEmpty) editor.select(effects.first);
              },
            ),
          ),
          _FilterBar(editor: editor, library: library),
          const Divider(),
          Expanded(
            child: effects.isEmpty
                ? EmptyState(
                    icon: editor.filter == BrowserFilter.favorites ? Icons.star_border : Icons.search_off,
                    title: switch (editor.filter.kind) {
                      'fav' => 'No favorites yet',
                      'recent' => 'Nothing used yet',
                      _ => 'No effects found',
                    },
                    message: switch (editor.filter.kind) {
                      'fav' => 'Star effects in the list or inspector to pin them here.',
                      'recent' => 'Effects you select, preview or render show up here.',
                      _ when editor.filter.category == EffectCategory.custom =>
                        'Write your own FFmpeg filter chains and reuse them anywhere.',
                      _ => 'Try another search.',
                    },
                    actions: [
                      if (editor.filter.category == EffectCategory.custom)
                        FilledButton.icon(
                          onPressed: () => showCustomEffectDialog(context),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('New custom effect'),
                        ),
                    ],
                  )
                : Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
                      itemExtent: 64,
                      itemCount: effects.length,
                      itemBuilder: (context, i) =>
                          EffectTile(effect: effects[i], selected: editor.selected?.id == effects[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.editor, required this.library});
  final EditorController editor;
  final LibraryController library;

  @override
  Widget build(BuildContext context) {
    final reg = library.registry;
    Widget chip(BrowserFilter f, String label, {IconData? icon, Color? color, int? count}) {
      final selected = editor.filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => editor.setFilter(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? (color ?? AppColors.accent).withValues(alpha: 0.2) : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? (color ?? AppColors.accent).withValues(alpha: 0.7) : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 12, color: color ?? AppColors.muted), const SizedBox(width: 4)],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.text : AppColors.muted,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 4),
                  Text('$count', style: const TextStyle(fontSize: 10.5, color: AppColors.faint)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Wrap(
        children: [
          chip(BrowserFilter.all, 'All', count: reg.all.length),
          chip(
            BrowserFilter.favorites,
            'Favorites',
            icon: Icons.star,
            color: AppColors.warn,
            count: library.favorites.length,
          ),
          chip(BrowserFilter.recent, 'Recent', icon: Icons.history),
          for (final c in EffectCategory.values)
            chip(
              BrowserFilter.category(c),
              c.label,
              icon: AppColors.categoryIcon(c),
              color: AppColors.category(c),
              count: reg.inCategory(c).length,
            ),
        ],
      ),
    );
  }
}

/// One row in the effect list.
class EffectTile extends StatelessWidget {
  const EffectTile({super.key, required this.effect, required this.selected});
  final Effect effect;
  final bool selected;

  static String? _lastTapId;
  static DateTime _lastTapAt = DateTime(0);

  @override
  Widget build(BuildContext context) {
    final editor = context.read<EditorController>();
    final library = context.watch<LibraryController>();
    final compMode = context.select<EditorController, bool>((e) => e.mode == EditorMode.compilation);
    final fav = library.isFavorite(effect.id);
    final color = AppColors.category(effect.category);
    final params = context.select<EditorController, Map<String, Object?>>((e) => e.paramsFor(effect));

    return Hover(
      cursor: SystemMouseCursors.click,
      builder: (context, hover) => KeyedSubtree(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            // Double-click is detected by hand so a single click selects
            // instantly (a double-tap recognizer would delay it ~300 ms).
            final now = DateTime.now();
            final isDouble = _lastTapId == effect.id && now.difference(_lastTapAt) < const Duration(milliseconds: 350);
            _lastTapId = isDouble ? null : effect.id;
            _lastTapAt = now;
            editor.select(effect);
            library.markUsed(effect.id);
            if (isDouble) {
              if (compMode) {
                StudioActions(context).addToCompilation(effect);
              } else {
                StudioActions(context).previewNow();
              }
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.16)
                  : hover
                  ? AppColors.surfaceHi
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.6) : Colors.transparent),
            ),
            child: Row(
              children: [
                EffectThumb(effect: effect, params: params, width: 72, height: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              effect.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (effect.loud) ...[
                            const SizedBox(width: 5),
                            const Tooltip(
                              message: 'Loud — authentic volume, no limiter',
                              child: Icon(Icons.volume_up, size: 13, color: AppColors.warn),
                            ),
                          ],
                          if (effect.heavy) ...[
                            const SizedBox(width: 4),
                            const Tooltip(
                              message: 'Buffers the whole clip — best on short clips',
                              child: Icon(Icons.hourglass_bottom, size: 12, color: AppColors.faint),
                            ),
                          ],
                          if (effect.params.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.tune, size: 12, color: AppColors.faint),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        effect.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (hover || fav || compMode)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hover || fav)
                        ToolButton(
                          icon: fav ? Icons.star : Icons.star_border,
                          tooltip: fav ? 'Unfavorite' : 'Favorite',
                          color: fav ? AppColors.warn : null,
                          size: 16,
                          onPressed: () => library.toggleFavorite(effect.id),
                        ),
                      if (hover || compMode)
                        ToolButton(
                          icon: Icons.playlist_add,
                          tooltip: 'Add to compilation',
                          color: compMode ? AppColors.compilation : null,
                          size: 17,
                          onPressed: () => StudioActions(context).addToCompilation(effect),
                        ),
                    ],
                  )
                else
                  Container(
                    width: 3,
                    height: 22,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Arrow-key navigation helper for the browser list.
KeyEventResult handleBrowserArrows(BuildContext context, KeyEvent e) {
  if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
  final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
  final up = e.logicalKey == LogicalKeyboardKey.arrowUp;
  if (!down && !up) return KeyEventResult.ignored;
  final editor = context.read<EditorController>();
  final list = editor.visibleEffects();
  if (list.isEmpty) return KeyEventResult.ignored;
  final i = list.indexWhere((x) => x.id == editor.selected?.id);
  final next = (i < 0 ? 0 : i + (down ? 1 : -1)).clamp(0, list.length - 1);
  editor.select(list[next]);
  return KeyEventResult.handled;
}
