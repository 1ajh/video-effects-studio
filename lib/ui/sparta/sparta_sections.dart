import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/sparta/base.dart';
import '../../core/sparta/model.dart';
import '../../state/sparta_controller.dart';
import '../theme.dart';
import 'sparta_style.dart';

/// Kinds offered when relabelling a section, in song order.
const editableKinds = [
  SectionKind.intro,
  SectionKind.chorus,
  SectionKind.dundundenden,
  SectionKind.epicness,
  SectionKind.awesomeness,
  SectionKind.madness,
  SectionKind.outro,
];

/// The base's sections as chips: click one to relabel, rename, split,
/// merge or re-roll it. Boundaries can also be dragged on the timeline.
class SectionChips extends StatelessWidget {
  const SectionChips({super.key, required this.base});
  final SpartaBase base;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final sections = base.sections;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < sections.length; i++) _SectionChip(index: i, section: sections[i], base: base),
        if (c.savedLayouts.isNotEmpty)
          TextButton.icon(
            onPressed: c.busy ? null : () => _copyFrom(context),
            icon: const Icon(Icons.content_copy, size: 14),
            label: const Text('Copy sections from…'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              textStyle: const TextStyle(fontSize: 11.5, fontFamily: 'Inter'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
          ),
        if (c.sectionsEdited)
          TextButton.icon(
            onPressed: c.busy ? null : c.resetSections,
            icon: const Icon(Icons.restart_alt, size: 15),
            label: const Text('Reset sections'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.muted,
              textStyle: const TextStyle(fontSize: 11.5, fontFamily: 'Inter'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
          ),
      ],
    );
  }
}

enum _Action { rename, split, merge, reroll }

class _SectionChip extends StatelessWidget {
  const _SectionChip({required this.index, required this.section, required this.base});
  final int index;
  final Section section;
  final SpartaBase base;

  @override
  Widget build(BuildContext context) {
    final c = context.read<SpartaController>();
    final color = sectionColor(section.kind);
    final bars = (section.lengthBeats / base.beatsPerBar).round();
    final builtIn = c.baseMode == BaseMode.builtIn;
    final canReroll = c.canRewriteSections;
    final last = index == base.sections.length - 1;

    void reroll() => c.rerollSectionAt(index);

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<Object>(
            tooltip: 'Edit this section',
            position: PopupMenuPosition.under,
            onSelected: (v) async {
              if (v is SectionKind) {
                await relabelWithPrompt(context, index, v);
              } else if (v == _Action.rename) {
                await _rename(context, index, section);
              } else if (v == _Action.split) {
                await _split(context, index, section, base.beatsPerBar);
              } else if (v == _Action.merge) {
                c.mergeSectionWithNext(index);
              } else if (v == _Action.reroll) {
                reroll();
              }
            },
            itemBuilder: (_) => [
              for (final k in editableKinds)
                PopupMenuItem<Object>(
                  value: k,
                  height: 34,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: sectionColor(k), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(k.label, style: const TextStyle(fontSize: 13))),
                      if (k == section.kind) const Icon(Icons.check, size: 16),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              _item(_Action.rename, Icons.edit_outlined, 'Rename…'),
              _item(_Action.split, Icons.content_cut, 'Split…', enabled: bars >= 2),
              _item(_Action.merge, Icons.merge_type, 'Merge with next', enabled: !last),
              if (canReroll)
                _item(_Action.reroll, Icons.casino_outlined, builtIn ? 'Re-roll this section' : 'New sample notes'),
            ],
            child: Padding(
              padding: EdgeInsets.fromLTRB(9, 4, canReroll ? 2 : 9, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${section.title} · $bars bar${bars == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                  Icon(Icons.arrow_drop_down, size: 16, color: color),
                ],
              ),
            ),
          ),
          if (canReroll)
            InkWell(
              onTap: reroll,
              customBorder: const CircleBorder(),
              child: Tooltip(
                message: builtIn ? 'Re-roll this section' : 'New sample notes for this section',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 3, 6, 3),
                  child: Icon(Icons.casino_outlined, size: 14, color: color),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static PopupMenuItem<Object> _item(_Action a, IconData icon, String label, {bool enabled = true}) =>
      PopupMenuItem<Object>(
        value: a,
        enabled: enabled,
        height: 34,
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.muted),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

/// Relabels section [i]; when its notes can be recomposed, asks whether to
/// rewrite them in the new style or keep them.
Future<void> relabelWithPrompt(BuildContext context, int i, SectionKind kind) async {
  final c = context.read<SpartaController>();
  if (i >= c.currentSections.length || c.currentSections[i].kind == kind) return;
  if (!c.canRewriteSections) {
    c.relabelSection(i, kind);
    return;
  }
  final rewrite = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Make this section ${kind.label}?'),
      content: SizedBox(
        width: 420,
        child: Text(
          c.baseMode == BaseMode.builtIn
              ? 'Rewrite its music and sample notes as ${kind.label}, or keep what it has and only change the '
                    'label? Visuals and sample variation follow the label either way.'
              : 'Rewrite its sample notes in the ${kind.label} style, or keep the notes it has and only change '
                    'the label? Visuals and sample variation follow the label either way.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(c.baseMode == BaseMode.builtIn ? 'Keep as is' : 'Keep notes'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.sparta, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(c.baseMode == BaseMode.builtIn ? 'Rewrite section' : 'Rewrite notes'),
        ),
      ],
    ),
  );
  if (rewrite == null || !context.mounted) return;
  c.relabelSection(i, kind, rewrite: rewrite);
}

Future<void> _rename(BuildContext context, int i, Section s) async {
  final c = context.read<SpartaController>();
  final text = TextEditingController(text: s.name);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename section'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(hintText: s.kind.label, helperText: 'Leave empty to use "${s.kind.label}"'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, text.text), child: const Text('Rename')),
      ],
    ),
  );
  text.dispose();
  if (name != null && context.mounted) c.renameSection(i, name);
}

Future<void> _split(BuildContext context, int i, Section s, int beatsPerBar) async {
  final c = context.read<SpartaController>();
  final bars = (s.lengthBeats / beatsPerBar).round();
  if (bars < 2) return;
  var at = bars ~/ 2;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Split ${s.title}'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('First part $at bar${at == 1 ? '' : 's'}, second part ${bars - at}.'),
              Slider(
                value: at.toDouble(),
                min: 1,
                max: (bars - 1).toDouble(),
                divisions: bars > 2 ? bars - 2 : null,
                label: 'after bar $at',
                onChanged: bars > 2 ? (v) => setState(() => at = v.round()) : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Split')),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) c.splitSection(i, s.startBeat + at * beatsPerBar);
}

/// "Intro 16 · Epicness 12 · Madness 16 …"
String layoutSummary(List<Section> layout, {int beatsPerBar = 4, int max = 6}) {
  final parts = [
    for (final s in layout.take(max)) '${s.title} ${(s.lengthBeats / beatsPerBar).round()}',
    if (layout.length > max) '…',
  ];
  return parts.join(' · ');
}

Future<void> _copyFrom(BuildContext context) async {
  final c = context.read<SpartaController>();
  final sources = c.savedLayouts;
  if (sources.isEmpty) return;
  var pick = 0;
  var rewrite = c.canRewriteSections;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Copy sections from another base'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Uses its section layout here bar for bar; the last section is cut or stretched to fit.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: RadioGroup<int>(
                    groupValue: pick,
                    onChanged: (v) => setState(() => pick = v ?? pick),
                    child: Column(
                      children: [
                        for (var i = 0; i < sources.length; i++)
                          RadioListTile<int>(
                            value: i,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.basename(sources[i].path), overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              layoutSummary(sources[i].layout),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (c.canRewriteSections)
                CheckboxListTile(
                  value: rewrite,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => setState(() => rewrite = v ?? rewrite),
                  title: Text(
                    c.baseMode == BaseMode.builtIn
                        ? 'Rewrite the music and sample notes to match'
                        : 'Rewrite the sample notes to match',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Copy sections')),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) c.copySections(sources[pick].layout, rewrite: rewrite);
}
