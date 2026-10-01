import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sparta/charter.dart';
import '../../core/sparta/model.dart';
import '../../core/sparta/patterns.dart';
import '../../core/sparta/transcription.dart';
import '../../state/settings_controller.dart';
import '../../state/sparta_controller.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sparta_style.dart';

/// Kinds offered when relabelling a section, in song order.
const editableKinds = [
  SectionKind.intro,
  SectionKind.chorus,
  SectionKind.dundundenden,
  SectionKind.preEpicness,
  SectionKind.epicness,
  SectionKind.postEpicness,
  SectionKind.awesomeness,
  SectionKind.madness,
  SectionKind.outro,
  SectionKind.other,
];

/// One row per section: what it is, which word / pitch patterns play, and
/// quick fixes to the base's transcription there.
class SectionEditor extends StatelessWidget {
  const SectionEditor({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final t = c.transcription;
    if (t == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel('SECTIONS — WHAT PLAYS WHERE')),
            if (c.savedLayouts.isNotEmpty)
              TextButton.icon(
                onPressed: () => _copyFrom(context),
                icon: const Icon(Icons.content_copy, size: 14),
                label: const Text('Copy sections from…'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < t.sections.length; i++) _SectionRow(index: i),
      ],
    );
  }
}

enum _Action { rename, split, merge }

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final t = c.transcription!;
    final s = t.sections[index];
    final color = sectionColor(s.kind);
    final bars = (s.lengthBeats / t.beatsPerBar).round();
    final choice = c.choiceAt(index);
    final charter = Charter();
    final defaultWords = charter.defaultWords(s.kind);
    final longIntro = s.kind == SectionKind.intro && s.lengthBeats >= 8 * t.beatsPerBar;
    final words = choice.words == null
        ? (defaultWords == null
              ? (longIntro ? 'Quote, then the chorus' : (s.kind == SectionKind.intro ? 'Quote' : 'No words'))
              : 'Words: ${defaultWords.name}')
        : choice.words!.isEmpty
        ? 'No words'
        : 'Words: ${charter.pattern(PatternKind.words, choice.words!)?.name ?? 'custom'}';
    final pitchOffDefault = s.kind == SectionKind.chorus && !c.pitchInChorus;
    final mode = choice.pitch ?? (pitchOffDefault ? PitchMode.off : PitchMode.base);
    final pitch = switch (mode) {
      PitchMode.base => 'Pitch: base hits',
      PitchMode.off => 'No pitch',
      PitchMode.pattern =>
        'Pitch: ${choice.pitchPattern == null ? 'wiki pattern' : charter.pattern(PatternKind.pitch, choice.pitchPattern!)?.name ?? 'custom'}',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          PopupMenuButton<Object>(
            tooltip: 'What this section is',
            position: PopupMenuPosition.under,
            onSelected: (v) async {
              if (v is SectionKind) {
                c.relabelSection(index, v);
              } else if (v == _Action.rename) {
                await _rename(context, index, s);
              } else if (v == _Action.split) {
                await _split(context, index, s, t.beatsPerBar);
              } else if (v == _Action.merge) {
                c.mergeSectionWithNext(index);
              }
            },
            itemBuilder: (_) => [
              for (final k in editableKinds)
                PopupMenuItem<Object>(
                  value: k,
                  height: 32,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: sectionColor(k), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(k.label, style: const TextStyle(fontSize: 13))),
                      if (k == s.kind) const Icon(Icons.check, size: 16),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              _menuItem(_Action.rename, Icons.edit_outlined, 'Rename…'),
              _menuItem(_Action.split, Icons.content_cut, 'Split…', enabled: bars >= 2),
              _menuItem(_Action.merge, Icons.merge_type, 'Merge with next', enabled: index + 1 < t.sections.length),
            ],
            child: Container(
              width: 150,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        Text(
                          'bar ${(s.startBeat / t.beatsPerBar).round() + 1} · $bars bar${bars == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 11, color: AppColors.faint),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18, color: color),
                ],
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _ChoiceChip(
                  icon: laneIcon(SampleRole.word),
                  color: laneColor(SampleRole.word),
                  label: words,
                  edited: choice.words != null,
                  onTap: () => _pickWords(context, index, s),
                ),
                _ChoiceChip(
                  icon: laneIcon(SampleRole.pitch),
                  color: laneColor(SampleRole.pitch),
                  label: pitch,
                  edited: choice.pitch != null,
                  onTap: () => _pickPitch(context, index, s),
                ),
                if (t.bass.isNotEmpty || t.chords.isNotEmpty)
                  _ToggleChip(
                    role: SampleRole.bass,
                    on: choice.bass ?? true,
                    edited: choice.bass != null,
                    onTap: () => c.setChoice(index, choice.copyWith(bass: !(choice.bass ?? true))),
                  ),
                if (t.chords.isNotEmpty)
                  _ToggleChip(
                    role: SampleRole.pad,
                    on: choice.pads ?? Charter.padsByDefault(s.kind),
                    edited: choice.pads != null,
                    onTap: () =>
                        c.setChoice(index, choice.copyWith(pads: !(choice.pads ?? Charter.padsByDefault(s.kind)))),
                  ),
              ],
            ),
          ),
          if (c.random.enabled)
            ToolButton(
              icon: Icons.casino_outlined,
              size: 16,
              tooltip: 'Another random take for this section',
              onPressed: () => c.rerollSection(index),
            ),
          if (!choice.isDefault)
            ToolButton(
              icon: Icons.restart_alt,
              size: 16,
              tooltip: 'Back to the defaults for this section',
              onPressed: () => c.resetChoice(index),
            ),
          _FixMenu(index: index),
        ],
      ),
    );
  }

  static PopupMenuItem<Object> _menuItem(_Action a, IconData icon, String label, {bool enabled = true}) =>
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

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.edited,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final bool edited;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: edited ? 0.22 : 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: edited ? 0.9 : 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 230),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
            ),
            Icon(Icons.arrow_drop_down, size: 15, color: color),
          ],
        ),
      ),
    );
  }
}

/// An instrument switched on or off in one section.
class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.role, required this.on, required this.edited, required this.onTap});
  final SampleRole role;
  final bool on;
  final bool edited;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = laneColor(role);
    return Tooltip(
      message: '${role.label} ${on ? 'play' : "don't play"} here — click to switch',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: edited ? 0.22 : 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: on ? (edited ? 0.9 : 0.4) : 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(on ? laneIcon(role) : Icons.block, size: 13, color: on ? color : AppColors.faint),
              const SizedBox(width: 5),
              Text(
                role.label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: on ? null : AppColors.faint,
                  decoration: on ? null : TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixes to the base's transcription in one section.
class _FixMenu extends StatelessWidget {
  const _FixMenu({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.read<SpartaController>();
    return PopupMenuButton<VoidCallback>(
      tooltip: "Fix the base's notes here",
      icon: const Icon(Icons.build_outlined, size: 16, color: AppColors.muted),
      position: PopupMenuPosition.under,
      onSelected: (f) => f(),
      itemBuilder: (_) {
        PopupMenuItem<VoidCallback> item(String label, VoidCallback f, {IconData? icon}) => PopupMenuItem(
          value: f,
          height: 32,
          child: Row(
            children: [
              Icon(icon ?? Icons.chevron_right, size: 15, color: AppColors.muted),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ),
        );
        PopupMenuItem<VoidCallback> header(String label) => PopupMenuItem(
          enabled: false,
          height: 26,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.faint, fontWeight: FontWeight.w700),
          ),
        );
        return [
          header("THE BASE'S HITS HERE"),
          item('Set to a wiki pitch pattern…', () => _replaceHits(context, index), icon: Icons.library_music_outlined),
          item('Up an octave', () => c.transposeSectionHits(index, 12), icon: Icons.keyboard_double_arrow_up),
          item('Down an octave', () => c.transposeSectionHits(index, -12), icon: Icons.keyboard_double_arrow_down),
          item('Up a semitone', () => c.transposeSectionHits(index, 1), icon: Icons.keyboard_arrow_up),
          item('Down a semitone', () => c.transposeSectionHits(index, -1), icon: Icons.keyboard_arrow_down),
          item('No hits here', () => c.setSectionHits(index, ''), icon: Icons.block),
          const PopupMenuDivider(),
          for (final role in const [SampleRole.kick, SampleRole.snare, SampleRole.hat]) ...[
            header('${role.label.toUpperCase()} HERE'),
            for (final f in DrumFill.values)
              item(f.label, () => c.setSectionDrums(index, role, f), icon: laneIcon(role)),
          ],
        ];
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Pattern pickers
// -----------------------------------------------------------------------------

Future<void> _pickWords(BuildContext context, int i, Section s) async {
  final c = context.read<SpartaController>();
  final charter = Charter();
  final result = await showDialog<String>(
    context: context,
    builder: (_) => PatternPicker(
      title: 'Chorus words in ${s.title}',
      kind: PatternKind.words,
      patterns: charter.wordChoices(s.kind),
      defaultLabel: charter.defaultWords(s.kind) == null
          ? (s.kind == SectionKind.intro
                ? 'Default: the quote (a long intro plays the chorus after it)'
                : 'Default: no words here')
          : 'Default: ${charter.defaultWords(s.kind)!.name}',
      noneLabel: 'No words here',
      current: c.choiceAt(i).words,
    ),
  );
  if (result == null) return;
  c.setWords(i, result == _defaultChoice ? null : result);
}

Future<void> _pickPitch(BuildContext context, int i, Section s) async {
  final c = context.read<SpartaController>();
  final charter = Charter();
  final choice = c.choiceAt(i);
  final result = await showDialog<String>(
    context: context,
    builder: (_) => PatternPicker(
      title: 'Pitch in ${s.title}',
      kind: PatternKind.pitch,
      patterns: charter.pitchChoices(s.kind),
      defaultLabel: "The base's own hits (default)",
      noneLabel: 'No pitch here',
      current: switch (choice.pitch) {
        null => null,
        PitchMode.base => _baseChoice,
        PitchMode.off => '',
        PitchMode.pattern => choice.pitchPattern,
      },
    ),
  );
  if (result == null) return;
  if (result == _defaultChoice) {
    c.setChoice(i, SectionChoice(words: choice.words, variant: choice.variant));
  } else if (result.isEmpty) {
    c.setPitch(i, PitchMode.off);
  } else {
    c.setPitch(i, PitchMode.pattern, pattern: result);
  }
}

Future<void> _replaceHits(BuildContext context, int i) async {
  final c = context.read<SpartaController>();
  final s = c.transcription!.sections[i];
  final result = await showDialog<String>(
    context: context,
    builder: (_) => PatternPicker(
      title: "The base's hits in ${s.title}",
      kind: PatternKind.pitch,
      patterns: Charter().pitchChoices(s.kind),
      subtitle: 'Fixes the transcription: pick the pattern the base really plays here (on its root).',
    ),
  );
  if (result == null || result == _defaultChoice) return;
  c.setSectionHits(i, result);
}

const _defaultChoice = '\u0000default';
const _baseChoice = '\u0000base';

/// Searchable list of wiki patterns (with the notation), plus a box to type
/// your own. Pops the chosen pattern id, '' for none, or the default.
class PatternPicker extends StatefulWidget {
  const PatternPicker({
    super.key,
    required this.title,
    required this.kind,
    required this.patterns,
    this.defaultLabel,
    this.noneLabel,
    this.current,
    this.subtitle,
  });

  final String title;
  final PatternKind kind;
  final List<Pattern> patterns;
  final String? defaultLabel;
  final String? noneLabel;
  final String? current;
  final String? subtitle;

  @override
  State<PatternPicker> createState() => _PatternPickerState();
}

class _PatternPickerState extends State<PatternPicker> {
  final _search = TextEditingController();
  late final _custom = TextEditingController(
    text: widget.current != null && widget.current!.startsWith('custom:')
        ? widget.current!.substring(7)
        : (widget.kind == PatternKind.pitch ? '0 0 +1 +1 -2 -2 +1 +1' : ''),
  );
  String? _error;
  bool _classicOnly = false;

  @override
  void dispose() {
    _search.dispose();
    _custom.dispose();
    super.dispose();
  }

  void _useCustom() {
    final text = _custom.text.replaceAll('+', '');
    try {
      PatternLibrary.custom(widget.kind, text);
      Navigator.pop(context, 'custom:$text');
    } on PatternFormatException catch (e) {
      setState(() => _error = 'Not readable: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase();
    final list = [
      for (final p in widget.patterns)
        if ((!_classicOnly || p.classic) &&
            (q.isEmpty || '${p.title} ${p.section} ${p.source.join(' ')}'.toLowerCase().contains(q)))
          p,
    ];
    Widget option(String label, String value, {IconData icon = Icons.radio_button_unchecked}) => ListTile(
      dense: true,
      leading: Icon(widget.current == value ? Icons.radio_button_checked : icon, size: 18),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      onTap: () => Navigator.pop(context, value),
    );
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 620,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(widget.subtitle!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ),
            if (widget.defaultLabel != null) option(widget.defaultLabel!, _defaultChoice),
            if (widget.noneLabel != null) option(widget.noneLabel!, '', icon: Icons.block),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search the Sparta Remix Wiki patterns',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Classics only'),
                  selected: _classicOnly,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => _classicOnly = v),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final p = list[i];
                  final selected = widget.current == p.id;
                  return ListTile(
                    dense: true,
                    selected: selected,
                    leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 18),
                    title: Row(
                      children: [
                        Flexible(child: Text(p.title, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 6),
                        Pill(SectionKind.byWiki(p.section)?.label ?? p.section),
                        if (p.classic) ...[const SizedBox(width: 4), const Pill('Classic', color: AppColors.spartaHi)],
                        if (p.irregular) ...[
                          const SizedBox(width: 4),
                          const Pill('Odd length', color: AppColors.warn, tooltip: 'Not a whole number of bars'),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      p.source.join('\n'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.faint),
                    ),
                    onTap: () => Navigator.pop(context, p.id),
                  );
                },
              ),
            ),
            const Divider(),
            Text(
              widget.kind == PatternKind.pitch
                  ? 'Your own pattern (wiki notation: semitones from the root, * longer, _ rest)'
                  : 'Your own pattern (wiki notation: word numbers 1 2 3 / 3A 3B, * longer, _ rest)',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _custom,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(isDense: true, errorText: _error),
                    onSubmitted: (_) => _useCustom(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _useCustom, child: const Text('Use')),
              ],
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

// -----------------------------------------------------------------------------
// Dialogs
// -----------------------------------------------------------------------------

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
                            title: Text(sources[i].name, overflow: TextOverflow.ellipsis),
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
  if (ok == true && context.mounted) c.copySections(sources[pick].layout);
}

/// Root note picker: the pitch sample is tuned to it and the base's hits
/// are read relative to it.
Future<void> pickRoot(BuildContext context) async {
  final c = context.read<SpartaController>();
  final t = c.transcription;
  if (t == null) return;
  var key = t.rootKey;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text("The base's root note"),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The note the base\'s hits are built on (most classic bases: D). The pitch sample is tuned to it.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var pc = 0; pc < 12; pc++)
                    ChoiceChip(
                      label: Text(noteNames[pc]),
                      selected: key % 12 == pc,
                      onSelected: (_) => setState(() => key = key - key % 12 + pc),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Octave'),
                  const Spacer(),
                  IconButton(onPressed: () => setState(() => key -= 12), icon: const Icon(Icons.remove)),
                  Text(keyName(key), style: const TextStyle(fontWeight: FontWeight.w700)),
                  IconButton(onPressed: () => setState(() => key += 12), icon: const Icon(Icons.add)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Use this root')),
        ],
      ),
    ),
  );
  if (ok == true && context.mounted) c.setRoot(key);
}

/// Sends a fixed transcription in: saves it as a file and opens a
/// prefilled GitHub issue to attach it to.
Future<void> submitTranscription(BuildContext context) async {
  final c = context.read<SpartaController>();
  final dir = context.read<SettingsController>().outputDir;
  final credit = TextEditingController();
  final notes = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Send your fixes'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Your fixed transcription is saved as a file and a GitHub issue opens, filled in. Attach the file '
              'to the issue and send it: once it is checked, the base gets your transcription for everyone, with '
              'your name on it.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: credit,
              decoration: const InputDecoration(labelText: 'Credit as (your name or channel)', isDense: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (what you fixed)', isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.send, size: 16),
          label: const Text('Save file & open GitHub'),
        ),
      ],
    ),
  );
  final who = credit.text, why = notes.text;
  credit.dispose();
  notes.dispose();
  if (ok != true || !context.mounted) return;
  try {
    final path = await c.saveTranscription(dir, credit: who);
    await openUrl(c.submissionUrl(credit: who, notes: why).toString());
    if (context.mounted) {
      showMessage(
        context,
        'Saved ${shortPath(path)} — attach it to the issue.',
        action: SnackBarAction(label: 'Show file', onPressed: () => showInFolder(path)),
      );
    }
  } catch (e) {
    if (context.mounted) showMessage(context, 'Could not save the transcription: $e', error: true);
  }
}
