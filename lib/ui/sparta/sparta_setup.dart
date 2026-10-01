import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sparta/arranger.dart';
import '../../core/sparta/base_library.dart';
import '../../core/sparta/model.dart';
import '../../core/sparta/project_transcriber.dart';
import '../../core/sparta/sample_processing.dart';
import '../../core/sparta/visual_renderer.dart';
import '../../state/project_controller.dart';
import '../../state/sparta_controller.dart';
import '../../state/sparta_playback.dart';
import '../file_dialogs.dart';
import '../inspector/output_section.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sparta_style.dart';

/// Left column of the Sparta mode: Base → Source → Line → Generate.
class SpartaSetupPanel extends StatelessWidget {
  const SpartaSetupPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return Container(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PanelHeader(title: 'Sparta Remix', icon: Icons.local_fire_department_outlined),
          const _Stepper(),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              key: PageStorageKey(c.step),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
              children: [
                Text(c.step.blurb, style: const TextStyle(fontSize: 12, color: AppColors.faint)),
                const SizedBox(height: 8),
                switch (c.step) {
                  SpartaStep.base => const _BaseStep(),
                  SpartaStep.source => const _SourceStep(),
                  SpartaStep.line => const _LineStep(),
                  SpartaStep.generate => const _GenerateStep(),
                },
              ],
            ),
          ),
          if (c.step == SpartaStep.generate) ...[const Divider(height: 1), const OutputSection()],
          const Divider(height: 1),
          const _StepButtons(),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          for (final s in SpartaStep.values) ...[
            if (s.index > 0)
              Expanded(
                child: Container(
                  height: 2,
                  color: c.stepDone(SpartaStep.values[s.index - 1]) ? AppColors.sparta : AppColors.border,
                ),
              ),
            _StepDot(step: s, current: c.step == s, done: c.stepDone(s), onTap: () => c.goTo(s)),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.step, required this.current, required this.done, required this.onTap});
  final SpartaStep step;
  final bool current;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = current ? AppColors.sparta : (done ? AppColors.success : AppColors.faint);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: current ? AppColors.sparta : color.withValues(alpha: 0.16),
                border: Border.all(color: color),
              ),
              child: done && !current
                  ? const Icon(Icons.check, size: 14, color: AppColors.success)
                  : Text(
                      '${step.index + 1}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: current ? Colors.white : color,
                      ),
                    ),
            ),
            const SizedBox(height: 3),
            Text(
              step.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                color: current ? AppColors.text : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButtons extends StatelessWidget {
  const _StepButtons();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final last = c.step == SpartaStep.generate;
    final next = last ? null : SpartaStep.values[c.step.index + 1];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          if (c.step.index > 0)
            TextButton.icon(
              onPressed: () => c.goTo(SpartaStep.values[c.step.index - 1]),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Back'),
            ),
          const Spacer(),
          if (last)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.sparta, foregroundColor: Colors.white),
              onPressed: c.canGenerate ? c.generate : null,
              icon: Icon(c.hasResult ? Icons.refresh : Icons.auto_fix_high, size: 18),
              label: Text(c.hasResult ? 'Generate again' : 'Generate remix'),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: c.stepDone(c.step) ? AppColors.sparta : AppColors.surfaceHi,
                foregroundColor: Colors.white,
              ),
              onPressed: () => c.goTo(next),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text('Next: ${next!.label}'),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 1. Base
// -----------------------------------------------------------------------------

class _BaseStep extends StatelessWidget {
  const _BaseStep();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<BaseTab>(
          showSelectedIcon: false,
          segments: [for (final t in BaseTab.values) ButtonSegment(value: t, label: Text(t.label))],
          selected: {c.tab},
          onSelectionChanged: (s) => c.setTab(s.first),
        ),
        const SizedBox(height: 6),
        Text(c.tab.blurb, style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
        const SizedBox(height: 10),
        const _BaseStatus(),
        switch (c.tab) {
          BaseTab.library => const _LibraryBrowser(),
          BaseTab.audio => const _AudioBase(),
          BaseTab.project => const _ProjectBase(),
        },
      ],
    );
  }
}

/// Loading / error / loaded state of the chosen base.
class _BaseStatus extends StatelessWidget {
  const _BaseStatus();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final t = c.transcription;
    if (c.baseLoading) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.baseStatus.isEmpty ? 'Loading the base…' : c.baseStatus,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: c.downloadProgress, color: AppColors.sparta, minHeight: 3),
          ],
        ),
      );
    }
    if (c.baseError != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(c.baseError!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
      );
    }
    if (t == null) return const SizedBox.shrink();
    final base = c.prepared!.base;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: AppColors.success),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  base.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
              ),
            ],
          ),
          if (base.author.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 22),
              child: Text('by ${base.author}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill('${_fmt(t.bpm)} BPM', icon: Icons.speed),
              Pill('Root ${t.rootName}', icon: Icons.piano_outlined),
              Pill('${t.bars} bars', icon: Icons.view_week_outlined),
              Pill(
                t.source.label,
                color: t.confidence >= 0.95 ? AppColors.success : AppColors.warn,
                tooltip: t.confidence >= 0.95
                    ? 'The notes are known exactly.'
                    : 'A draft from listening (${(t.confidence * 100).round()}% sure). Check it on the right: '
                          'sections, root and hits can all be fixed — and sent in so everyone gets the fix.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

class _LibraryBrowser extends StatefulWidget {
  const _LibraryBrowser();

  @override
  State<_LibraryBrowser> createState() => _LibraryBrowserState();
}

class _LibraryBrowserState extends State<_LibraryBrowser> {
  late final _search = TextEditingController(text: context.read<SpartaController>().query);
  int _shown = 40;

  @override
  void initState() {
    super.initState();
    final c = context.read<SpartaController>();
    if (c.catalog == null && !c.catalogLoading) WidgetsBinding.instance.addPostFrameCallback((_) => c.loadCatalog());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final results = c.results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18),
            hintText: 'Search bases, makers, collections',
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) {
            setState(() => _shown = 40);
            c.setQuery(v);
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            FilterChip(
              label: const Text('Exact notes only', style: TextStyle(fontSize: 11.5)),
              tooltip: 'Bases with their FL Studio project or a checked transcription',
              selected: c.exactOnly,
              showCheckmark: false,
              onSelected: c.setExactOnly,
            ),
            const Spacer(),
            Text(
              c.catalog == null ? '' : '${results.length} bases',
              style: const TextStyle(fontSize: 11.5, color: AppColors.faint),
            ),
            ToolButton(
              icon: Icons.refresh,
              size: 15,
              tooltip: 'Check for new bases',
              onPressed: c.catalogLoading ? null : () => c.loadCatalog(),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (c.catalog == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text('Loading the base library…', style: TextStyle(color: AppColors.muted)),
            ),
          )
        else if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No base matches that.', style: TextStyle(color: AppColors.faint)),
          )
        else ...[
          for (final b in results.take(_shown)) _CatalogTile(base: b),
          if (results.length > _shown)
            TextButton(
              onPressed: () => setState(() => _shown += 60),
              child: Text('Show more (${results.length - _shown} left)'),
            ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Bases are downloaded from where their makers published them, and credited. '
          'Know one that is missing? Add it with a fixed transcription via "Send your fixes".',
          style: TextStyle(fontSize: 11, color: AppColors.faint, height: 1.35),
        ),
      ],
    );
  }
}

class _CatalogTile extends StatelessWidget {
  const _CatalogTile({required this.base});
  final CatalogBase base;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final selected = c.selectedCatalogId == base.id;
    final loading = selected && c.baseLoading;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: () => c.selectCatalogBase(base),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.sparta.withValues(alpha: 0.12) : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? AppColors.sparta : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          base.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [if (base.maker.isNotEmpty) base.maker, base.collection].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.faint),
                        ),
                      ],
                    ),
                  ),
                  if (base.featured)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Pill('Official', color: AppColors.spartaHi),
                    ),
                  if (base.exact)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Pill(
                        'Exact',
                        color: AppColors.success,
                        tooltip: 'Its notes are known exactly (FL project or checked transcription)',
                      ),
                    ),
                  if (base.page.isNotEmpty)
                    ToolButton(
                      icon: Icons.open_in_new,
                      size: 14,
                      tooltip: 'Where it was published',
                      onPressed: () => openUrl(base.page),
                    ),
                ],
              ),
              if (loading) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: c.downloadProgress, minHeight: 2, color: AppColors.sparta),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioBase extends StatelessWidget {
  const _AudioBase();

  Future<void> _pick(BuildContext context) async {
    final files = await pickFilesSafely(
      context,
      dialogTitle: 'Choose a base (audio)',
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'flac', 'ogg', 'm4a', 'aac', 'opus', 'mp4', 'webm', 'mkv'],
    );
    final path = files.map((f) => f.path).whereType<String>().firstOrNull;
    if (path != null && context.mounted) context.read<SpartaController>().setAudioBase(path);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FileRow(
          icon: Icons.audio_file_outlined,
          label: c.audioBasePath == null ? 'Choose a base audio file' : shortPath(c.audioBasePath!),
          onTap: () => _pick(context),
        ),
        if (c.audioBasePath != null) ...[const SizedBox(height: 10), const _TempoRow()],
        const SizedBox(height: 8),
        const Text(
          'Tempo, bars, drums, the hit notes and the sections are worked out by listening. '
          'If the file is a base from the library, its checked transcription is used instead.',
          style: TextStyle(fontSize: 11, color: AppColors.faint, height: 1.35),
        ),
      ],
    );
  }
}

/// Detected (or set) tempo of an audio base, with half/double-time fixes
/// and an exact BPM.
class _TempoRow extends StatelessWidget {
  const _TempoRow();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final bpm = c.audioBpm;
    final set = c.bpmOverride != null;
    return Row(
      children: [
        Expanded(
          child: bpm == null
              ? const Text('Tempo', style: TextStyle(fontSize: 12, color: AppColors.muted))
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Pill(
                    '${_fmt(bpm)} BPM',
                    icon: set ? Icons.edit_outlined : Icons.check,
                    color: set ? AppColors.sparta : AppColors.success,
                    tooltip: set ? 'Tempo set by you' : 'Detected tempo',
                  ),
                ),
        ),
        _SmallButton(label: '½×', tooltip: 'Half time', onPressed: bpm == null || c.busy ? null : c.halveTempo),
        const SizedBox(width: 4),
        _SmallButton(label: '2×', tooltip: 'Double time', onPressed: bpm == null || c.busy ? null : c.doubleTempo),
        const SizedBox(width: 8),
        SizedBox(
          width: 86,
          child: TextFormField(
            key: ValueKey(c.bpmOverride),
            initialValue: c.bpmOverride == null ? '' : _fmt(c.bpmOverride!),
            decoration: const InputDecoration(hintText: 'auto', suffixText: 'BPM', isDense: true),
            style: const TextStyle(fontSize: 12.5),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onFieldSubmitted: (v) => c.setBpm(double.tryParse(v.trim())),
          ),
        ),
        if (set)
          ToolButton(icon: Icons.restart_alt, tooltip: 'Back to the detected tempo', onPressed: () => c.setBpm(null))
        else
          const SizedBox(width: 34),
      ],
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.tooltip, this.onPressed});
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(38, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, fontFamily: 'Inter'),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ProjectBase extends StatelessWidget {
  const _ProjectBase();

  Future<void> _pickProject(BuildContext context) async {
    final files = await pickFilesSafely(
      context,
      dialogTitle: 'Open a base project',
      type: FileType.custom,
      allowedExtensions: projectFileExtensions.toList(),
    );
    final path = files.map((f) => f.path).whereType<String>().firstOrNull;
    if (path != null && context.mounted) await context.read<SpartaController>().setProject(path);
  }

  Future<void> _pickAudio(BuildContext context) async {
    final files = await pickFilesSafely(
      context,
      dialogTitle: "The base's rendered audio",
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3', 'flac', 'ogg', 'm4a', 'aac', 'opus'],
    );
    final path = files.map((f) => f.path).whereType<String>().firstOrNull;
    if (path != null && context.mounted) context.read<SpartaController>().setProjectAudio(path);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final chart = c.projectChart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FileRow(
          icon: Icons.piano_outlined,
          label: c.projectPath == null ? 'Choose .flp / .flm / .mid' : shortPath(c.projectPath!),
          onTap: () => _pickProject(context),
        ),
        const SizedBox(height: 6),
        FileRow(
          icon: Icons.audio_file_outlined,
          label: c.projectAudioPath == null
              ? "The base's audio (optional — else it's re-synthesized)"
              : shortPath(c.projectAudioPath!),
          onTap: () => _pickAudio(context),
          onClear: c.projectAudioPath == null ? null : () => c.setProjectAudio(null),
        ),
        if (c.projectError != null) ...[
          const SizedBox(height: 8),
          Text(c.projectError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
        if (chart != null) ...[
          for (final w in chart.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(w, style: const TextStyle(fontSize: 11.5, color: AppColors.warn)),
            ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(
                child: Text('Which track is the hit / lead?', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
              Tooltip(
                message:
                    'The pitch sample plays the notes of the track the base\'s hits are on.\n'
                    '"Auto" finds it; pick "Pitch guide" if it chose the wrong one.',
                child: Icon(Icons.help_outline, size: 15, color: AppColors.faint),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final t in chart.tracks.where((t) => !t.isDrums && t.notes.isNotEmpty))
            _TrackUseRow(trackId: t.id, name: t.name, detail: t.detail),
          if (c.projectAudioPath != null) ...[const SizedBox(height: 8), const _OffsetRow()],
        ],
      ],
    );
  }
}

class _TrackUseRow extends StatelessWidget {
  const _TrackUseRow({required this.trackId, required this.name, required this.detail});
  final String trackId;
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.music_note_outlined, size: 15, color: AppColors.faint),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: detail.isEmpty ? name : '$name\n$detail',
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          DropdownButton<TrackUse>(
            value: c.uses[trackId] ?? TrackUse.auto,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 12, color: AppColors.text, fontFamily: 'Inter'),
            dropdownColor: AppColors.surface,
            items: [for (final u in TrackUse.values) DropdownMenuItem(value: u, child: Text(u.label))],
            onChanged: (u) => c.setTrackUse(trackId, u ?? TrackUse.auto),
          ),
        ],
      ),
    );
  }
}

class _OffsetRow extends StatelessWidget {
  const _OffsetRow();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final value = c.manualOffset;
    final shown = value ?? c.transcription?.audioOffset;
    return Row(
      children: [
        Expanded(
          child: Text(
            value == null ? 'Audio start: auto' : 'Audio start',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        ToolButton(
          icon: Icons.chevron_left,
          size: 15,
          tooltip: '10 ms earlier',
          onPressed: shown == null ? null : () => c.setManualOffset(shown - 0.01),
        ),
        SizedBox(
          width: 58,
          child: Text(
            shown == null ? '—' : '${shown.toStringAsFixed(2)}s',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
        ToolButton(
          icon: Icons.chevron_right,
          size: 15,
          tooltip: '10 ms later',
          onPressed: shown == null ? null : () => c.setManualOffset(shown + 0.01),
        ),
        if (value != null)
          ToolButton(
            icon: Icons.auto_fix_high,
            size: 15,
            tooltip: 'Detect again',
            onPressed: () => c.setManualOffset(null),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 2. Source
// -----------------------------------------------------------------------------

class _SourceStep extends StatelessWidget {
  const _SourceStep();

  Future<void> _add(BuildContext context) async {
    final files = await pickFilesSafely(
      context,
      dialogTitle: 'Add sources (videos or audio)',
      type: FileType.custom,
      allowedExtensions: videoExtensions.toList(),
    );
    final paths = files.map((f) => f.path).whereType<String>().toList();
    if (paths.isEmpty || !context.mounted) return;
    final added = context.read<SpartaController>().addSources(paths);
    if (added == 0) showMessage(context, 'Those are already added (or not media files).');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final editorClips = context.select<ProjectController, List<String>>((p) => p.sources.map((s) => s.path).toList());
    final importable = editorClips.where((path) => !c.sources.any((s) => s.path == path)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.sources.isEmpty)
          _DropHint(onTap: () => _add(context))
        else ...[
          for (final s in c.sources) _SourceRow(source: s),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add more'),
            ),
          ),
        ],
        if (importable.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => c.addSources(importable),
              icon: const Icon(Icons.move_down, size: 15),
              label: Text('Use ${importable.length} clip${importable.length == 1 ? '' : 's'} from the editor'),
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Everything in the remix is cut from these: the line, its words, the pitch sample and the percussion. '
          'Nothing is added from anywhere else.',
          style: TextStyle(fontSize: 11, color: AppColors.faint, height: 1.35),
        ),
      ],
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderHi),
          color: AppColors.bg.withValues(alpha: 0.4),
        ),
        child: const Column(
          children: [
            Icon(Icons.video_library_outlined, color: AppColors.muted),
            SizedBox(height: 6),
            Text('Drop videos or audio here', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 2),
            Text('or click to browse', style: TextStyle(fontSize: 12, color: AppColors.faint)),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source});
  final SpartaSource source;

  @override
  Widget build(BuildContext context) {
    final info = source.info;
    final detail =
        source.error ??
        (source.busy
            ? 'Listening…'
            : info == null
            ? ''
            : '${formatDuration(info.duration)} · ${info.hasVideo ? '${info.width}×${info.height}' : 'audio only'}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: source.error != null ? AppColors.danger.withValues(alpha: 0.5) : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              source.hasVideo || info == null ? Icons.movie_outlined : Icons.graphic_eq,
              size: 18,
              color: source.error != null ? AppColors.danger : AppColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: source.error != null ? AppColors.danger : AppColors.faint),
                  ),
                ],
              ),
            ),
            if (source.busy)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (source.analysis != null)
              const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.check_circle, size: 16, color: AppColors.success),
              ),
            ToolButton(
              icon: Icons.close,
              size: 15,
              tooltip: 'Remove',
              onPressed: () => context.read<SpartaController>().removeSource(source),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 3. Line
// -----------------------------------------------------------------------------

Future<void> _playClip(BuildContext context, int source, double start, double end, String id) async {
  final c = context.read<SpartaController>();
  final play = context.read<SpartaPlayback>();
  if (play.auditioning == id && play.playing) return play.stop();
  final path = await c.clipPath(source, start, end);
  if (path != null) await play.audition(path, id);
}

class _LineStep extends StatelessWidget {
  const _LineStep();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    if (c.readySources == 0) {
      return Text(
        c.sourcesBusy ? 'Listening to your sources…' : 'Add a source first.',
        style: const TextStyle(color: AppColors.muted),
      );
    }
    if (c.found == null) {
      return Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              c.status.isEmpty ? 'Finding spoken lines…' : c.status,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      );
    }
    if (c.lines.isEmpty) {
      return const Text(
        'No clear spoken line was found. Add a source where someone talks clearly.',
        style: TextStyle(color: AppColors.warn),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.line != null) ...[const _WordEditor(), const SizedBox(height: 14)],
        const SectionLabel('LINES FOUND'),
        const SizedBox(height: 6),
        for (var i = 0; i < c.lines.length; i++) _LineTile(index: i),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final play = context.watch<SpartaPlayback>();
    final l = c.lines[index];
    final selected = c.lineIndex == index && c.line != null;
    final id = 'line$index';
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: () => c.chooseLine(index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.sparta.withValues(alpha: 0.12) : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? AppColors.sparta : AppColors.border),
          ),
          child: Row(
            children: [
              ToolButton(
                icon: play.auditioning == id && play.playing ? Icons.stop : Icons.play_arrow,
                tooltip: 'Play this line',
                onPressed: play.available ? () => _playClip(context, l.sourceIndex, l.start, l.end, id) : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.sourceName(l.sourceIndex)} · ${l.start.toStringAsFixed(1)} s',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${l.duration.toStringAsFixed(1)} s · ${l.words.length} word${l.words.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 11, color: AppColors.faint),
                    ),
                  ],
                ),
              ),
              Pill('${(l.score * 100).round()}%', tooltip: 'How clear and quote-like it is'),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chosen line: its words in order (1, 2, 3…, syllables 3A, 3B), with
/// listening, splitting, merging and draggable boundaries.
class _WordEditor extends StatelessWidget {
  const _WordEditor();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final play = context.watch<SpartaPlayback>();
    final l = c.line!;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Your line', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: play.available ? () => _playClip(context, l.sourceIndex, l.start, l.end, 'quote') : null,
                icon: Icon(play.auditioning == 'quote' && play.playing ? Icons.stop : Icons.play_arrow, size: 16),
                label: const Text('Quote'),
              ),
            ],
          ),
          const Text(
            'The whole line is the quote; its words are the chorus samples, numbered in order. '
            'Drag the lines between words to fix them.',
            style: TextStyle(fontSize: 11, color: AppColors.faint, height: 1.35),
          ),
          const SizedBox(height: 8),
          _LineWave(line: l),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [for (var i = 0; i < l.words.length; i++) _WordChip(index: i)]),
        ],
      ),
    );
  }
}

class _LineWave extends StatefulWidget {
  const _LineWave({required this.line});
  final SpokenLine line;

  @override
  State<_LineWave> createState() => _LineWaveState();
}

class _LineWaveState extends State<_LineWave> {
  int? _drag; // boundary index (between word i and i + 1)
  double? _dragAt;

  @override
  Widget build(BuildContext context) {
    final c = context.read<SpartaController>();
    final l = widget.line;
    final pad = 0.15;
    final a = math.max(0.0, l.start - pad), z = l.end + pad;
    final env = c.envelope(l.sourceIndex, a, z);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        double x(double t) => (t - a) / (z - a) * w;
        double t(double px) => a + px / w * (z - a);
        int? near(double px) {
          for (var i = 0; i + 1 < l.words.length; i++) {
            final bx = x((l.words[i].end + l.words[i + 1].start) / 2);
            if ((px - bx).abs() < 8) return i;
          }
          return null;
        }

        return MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: (d) => setState(() {
              _drag = near(d.localPosition.dx);
              _dragAt = _drag == null ? null : t(d.localPosition.dx);
            }),
            onHorizontalDragUpdate: (d) {
              if (_drag != null) setState(() => _dragAt = t(d.localPosition.dx));
            },
            onHorizontalDragEnd: (_) {
              final i = _drag, at = _dragAt;
              setState(() {
                _drag = null;
                _dragAt = null;
              });
              if (i != null && at != null) c.editLine((l) => l.moveBoundary(i, at));
            },
            child: CustomPaint(
              size: Size(w, 64),
              painter: _WavePainter(line: l, env: env, a: a, z: z, drag: _drag, dragAt: _dragAt),
            ),
          ),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.line, required this.env, required this.a, required this.z, this.drag, this.dragAt});
  final SpokenLine line;
  final List<double> env;
  final double a, z;
  final int? drag;
  final double? dragAt;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double t) => (t - a) / (z - a) * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = AppColors.bg,
    );
    final color = laneColor(SampleRole.word);
    for (var i = 0; i < line.words.length; i++) {
      final w = line.words[i];
      final r = Rect.fromLTRB(x(w.start), 2, x(w.end), size.height - 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()..color = color.withValues(alpha: i.isEven ? 0.16 : 0.26),
      );
      for (final cut in w.cuts) {
        final cx = x(cut);
        canvas.drawLine(
          Offset(cx, 8),
          Offset(cx, size.height - 8),
          Paint()
            ..color = color.withValues(alpha: 0.6)
            ..strokeWidth = 1,
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.text),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(r.left + 4, 3));
    }
    // Loudness.
    if (env.isNotEmpty) {
      final path = Path();
      for (var i = 0; i < env.length; i++) {
        final px = i / math.max(1, env.length - 1) * size.width;
        final v = ((env[i] + 60) / 60).clamp(0.0, 1.0);
        final h = v * (size.height - 16);
        if (i == 0) {
          path.moveTo(px, size.height / 2 - h / 2);
        } else {
          path.lineTo(px, size.height / 2 - h / 2);
        }
      }
      for (var i = env.length - 1; i >= 0; i--) {
        final px = i / math.max(1, env.length - 1) * size.width;
        final v = ((env[i] + 60) / 60).clamp(0.0, 1.0);
        path.lineTo(px, size.height / 2 + v * (size.height - 16) / 2);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = AppColors.text.withValues(alpha: 0.55));
    }
    // Boundaries between words.
    for (var i = 0; i + 1 < line.words.length; i++) {
      final bx = x(drag == i && dragAt != null ? dragAt! : (line.words[i].end + line.words[i + 1].start) / 2);
      canvas.drawRect(
        Rect.fromLTWH(bx - 1, 0, 2, size.height),
        Paint()..color = drag == i ? AppColors.sparta : AppColors.spartaHi.withValues(alpha: 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.line != line || old.env != env || old.drag != drag || old.dragAt != dragAt;
}

enum _WordAction { split, merge, cut, uncut, remove, startEarlier, startLater, endEarlier, endLater }

class _WordChip extends StatelessWidget {
  const _WordChip({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final play = context.watch<SpartaPlayback>();
    final l = c.line!;
    final w = l.words[index];
    final syl = w.syllables;
    final color = laneColor(SampleRole.word);
    final id = 'word$index';
    final label = syl.length > 1
        ? '${index + 1} (${[for (var j = 0; j < syl.length; j++) '${index + 1}${String.fromCharCode(65 + j)}'].join(' ')})'
        : '${index + 1}';
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: play.available ? () => _playClip(context, l.sourceIndex, w.start, w.end, id) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 3, 2, 3),
              child: Icon(
                play.auditioning == id && play.playing ? Icons.stop : Icons.play_arrow,
                size: 15,
                color: color,
              ),
            ),
          ),
          PopupMenuButton<_WordAction>(
            tooltip: 'Edit word ${index + 1}',
            position: PopupMenuPosition.under,
            onSelected: (a) => c.editLine((l) {
              final w = l.words[index];
              return switch (a) {
                _WordAction.split => l.splitWord(index, w.cuts.isNotEmpty ? w.cuts.first : (w.start + w.end) / 2),
                _WordAction.merge => l.mergeWithNext(index),
                _WordAction.cut => l.toggleCut(index, (w.start + w.end) / 2),
                _WordAction.uncut => l.withWords([
                  ...l.words.take(index),
                  w.copyWith(cuts: const []),
                  ...l.words.skip(index + 1),
                ]),
                _WordAction.remove => l.removeWord(index),
                _WordAction.startEarlier => l.trimWord(index, start: w.start - 0.02),
                _WordAction.startLater => l.trimWord(index, start: w.start + 0.02),
                _WordAction.endEarlier => l.trimWord(index, end: w.end - 0.02),
                _WordAction.endLater => l.trimWord(index, end: w.end + 0.02),
              };
            }),
            itemBuilder: (_) => [
              _item(_WordAction.split, Icons.content_cut, w.cuts.isNotEmpty ? 'Split into two words' : 'Split in half'),
              _item(
                _WordAction.merge,
                Icons.merge_type,
                'Join with the next word',
                enabled: index + 1 < l.words.length,
              ),
              if (w.cuts.isEmpty)
                _item(_WordAction.cut, Icons.call_split, 'Two syllables (${index + 1}A / ${index + 1}B)')
              else
                _item(_WordAction.uncut, Icons.horizontal_rule, 'One syllable'),
              const PopupMenuDivider(),
              _item(_WordAction.startEarlier, Icons.first_page, 'Start 20 ms earlier'),
              _item(_WordAction.startLater, Icons.chevron_right, 'Start 20 ms later'),
              _item(_WordAction.endEarlier, Icons.chevron_left, 'End 20 ms earlier'),
              _item(_WordAction.endLater, Icons.last_page, 'End 20 ms later'),
              const PopupMenuDivider(),
              _item(_WordAction.remove, Icons.delete_outline, 'Remove (not a word)', enabled: l.words.length > 1),
            ],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 8, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  Icon(Icons.arrow_drop_down, size: 16, color: color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static PopupMenuItem<_WordAction> _item(_WordAction a, IconData icon, String label, {bool enabled = true}) =>
      PopupMenuItem(
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

// -----------------------------------------------------------------------------
// 4. Generate
// -----------------------------------------------------------------------------

class _GenerateStep extends StatelessWidget {
  const _GenerateStep();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final missing = c.missing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (missing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(missing, style: const TextStyle(fontSize: 12, color: AppColors.warn)),
          ),
        const _SoundCard(),
        const _RandomCard(),
        const _VideoCard(),
        const _MixCard(),
      ],
    );
  }
}

class _SoundCard extends StatelessWidget {
  const _SoundCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final e = c.enhance;
    return SpartaCard(
      step: 1,
      title: 'Samples',
      subtitle: 'Everything is cut from your sources. Defaults are the classic Sparta sound.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Labeled(
            label: 'Pitch tuning',
            tooltip: e.tuning.blurb,
            child: SegmentedButton<PitchTuning>(
              showSelectedIcon: false,
              segments: [for (final t in PitchTuning.values) ButtonSegment(value: t, label: Text(t.label))],
              selected: {e.tuning},
              onSelectionChanged: (s) => c.setEnhance(e.copyWith(tuning: s.first)),
            ),
          ),
          _Labeled(
            label: 'Pitch octave',
            tooltip: 'Which octave the pitch sample is tuned into (Auto: the nearest to the voice)',
            child: DropdownButton<int?>(
              value: e.forceOctave,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Auto')),
                for (final o in [2, 3, 4, 5]) DropdownMenuItem<int?>(value: o, child: Text('Octave $o')),
              ],
              onChanged: (o) => c.setEnhance(o == null ? e.copyWith(clearOctave: true) : e.copyWith(forceOctave: o)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Pitched notes', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                const SizedBox(height: 4),
                SegmentedButton<PitchRender>(
                  showSelectedIcon: false,
                  segments: [
                    for (final r in PitchRender.values) ButtonSegment(value: r, label: Text(r.label), tooltip: r.blurb),
                  ],
                  selected: {c.mixSettings.pitchRender},
                  onSelectionChanged: (s) => c.setMixSettings(c.mixSettings.copyWith(pitchRender: s.first)),
                ),
                const SizedBox(height: 2),
                Text(
                  c.mixSettings.pitchRender.blurb,
                  style: const TextStyle(fontSize: 11, color: AppColors.faint, height: 1.35),
                ),
              ],
            ),
          ),
          _Labeled(
            label: 'Bass octave',
            tooltip: 'Which octave the bass sample is tuned into (2: the classic deep bass)',
            child: DropdownButton<int>(
              value: e.bassOctave,
              isDense: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final o in [1, 2, 3]) DropdownMenuItem<int>(value: o, child: Text('Octave $o')),
              ],
              onChanged: (o) => o == null ? null : c.setEnhance(e.copyWith(bassOctave: o)),
            ),
          ),
          SwitchRow(
            title: 'Chorus Crisp',
            subtitle: 'Doubled, tighter attack on the chorus words (edits the word itself)',
            value: e.chorusCrisp,
            onChanged: (v) => c.setEnhance(e.copyWith(chorusCrisp: v)),
          ),
          SwitchRow(
            title: 'Pitch in the chorus',
            subtitle: 'Off: the chorus is the words only, as in a classic remix',
            value: c.pitchInChorus,
            onChanged: c.setPitchInChorus,
          ),
          SwitchRow(
            title: 'Synth drum body',
            subtitle: 'Layers a synthesized body under the percussion — not from your video (a "fake sample")',
            value: e.layerDrums,
            onChanged: (v) => c.setEnhance(e.copyWith(layerDrums: v)),
          ),
        ],
      ),
    );
  }
}

class _RandomCard extends StatelessWidget {
  const _RandomCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final r = c.random;
    return SpartaCard(
      step: 2,
      title: 'Random mode',
      subtitle: r.enabled
          ? 'Varies the remix while keeping the base. Take #${r.seed}.'
          : 'Off: the remix follows the base exactly.',
      trailing: Transform.scale(
        scale: 0.8,
        child: Switch(
          value: r.enabled,
          onChanged: (v) => c.setRandom(r.copyWith(enabled: v)),
        ),
      ),
      child: !r.enabled
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchRow(
                  title: 'Chorus freestyles',
                  subtitle: "The wiki's freestyle word patterns",
                  value: r.freestyles,
                  onChanged: (v) => c.setRandom(r.copyWith(freestyles: v)),
                ),
                SwitchRow(
                  title: 'Other pitch patterns',
                  subtitle: "Wiki pitch patterns instead of the base's hits in some sections",
                  value: r.pitchPatterns,
                  onChanged: (v) => c.setRandom(r.copyWith(pitchPatterns: v)),
                ),
                SwitchRow(
                  title: 'Samples per section',
                  subtitle: 'Which of your samples plays changes by section (turn on a second sample)',
                  value: r.samples,
                  onChanged: (v) => c.setRandom(r.copyWith(samples: v)),
                ),
                SwitchRow(
                  title: 'Section layout',
                  subtitle: "Sections can play another part's patterns",
                  value: r.layout,
                  onChanged: (v) => c.setRandom(r.copyWith(layout: v)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: c.rerollAll,
                    icon: const Icon(Icons.casino_outlined, size: 16),
                    label: const Text('Another take'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final v = c.visuals;
    return SpartaCard(
      step: 3,
      title: 'Video',
      subtitle: v.style.blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.6,
            children: [
              for (final s in VisualStyle.values)
                _StyleTile(
                  style: s,
                  selected: v.style == s,
                  onTap: () => c.setVisuals(v.copyWith(style: s)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (v.style != VisualStyle.minimal)
            _Labeled(
              label: 'Grid',
              tooltip: v.grid.blurb,
              child: _Dropdown<GridSize>(
                value: v.grid,
                values: GridSize.values,
                label: (g) => g.label,
                onChanged: (g) => c.setVisuals(v.copyWith(grid: g)),
              ),
            ),
          _Labeled(
            label: 'Flips',
            child: _Dropdown<FlipMode>(
              value: v.flip,
              values: FlipMode.values,
              label: (f) => f.label,
              onChanged: (f) => c.setVisuals(v.copyWith(flip: f)),
            ),
          ),
          _Labeled(
            label: 'Between hits',
            child: _Dropdown<IdleBox>(
              value: v.idle,
              values: IdleBox.values,
              label: (i) => i.label,
              onChanged: (i) => c.setVisuals(v.copyWith(idle: i)),
            ),
          ),
          _Labeled(
            label: 'Quote',
            tooltip: v.intro.blurb,
            child: _Dropdown<IntroVisual>(
              value: v.intro,
              values: IntroVisual.values,
              label: (i) => i.label,
              onChanged: (i) => c.setVisuals(v.copyWith(intro: i)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  const _MixCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final m = c.mixSettings;
    return SpartaCard(
      step: 4,
      title: 'Mix & export',
      subtitle: m.master.blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Labeled(
            label: 'Master',
            child: SegmentedButton<MasterMode>(
              showSelectedIcon: false,
              segments: [for (final mm in MasterMode.values) ButtonSegment(value: mm, label: Text(mm.label))],
              selected: {m.master},
              onSelectionChanged: (s) => c.setMixSettings(m.copyWith(master: s.first)),
            ),
          ),
          _LevelSlider(
            label: 'Base',
            color: AppColors.muted,
            value: m.baseDb,
            onChanged: (v) => c.setMixSettings(m.copyWith(baseDb: v)),
          ),
          for (final r in SampleRole.values)
            _LevelSlider(
              label: r == SampleRole.word ? 'Words' : r.label,
              color: laneColor(r),
              value: m.laneDb[r] ?? 0,
              onChanged: (v) => c.setLaneDb(r, v),
              on: !c.muted.contains(r),
              onToggle: (on) => c.setLaneOn(r, on),
            ),
          _LevelSlider(
            label: 'Reverb',
            color: AppColors.accentHi,
            value: m.reverb,
            min: 0,
            max: 0.3,
            format: (v) => '${(v / 0.3 * 100).round()}%',
            onChanged: (v) => c.setMixSettings(m.copyWith(reverb: v)),
          ),
          const SizedBox(height: 4),
          SwitchRow(
            title: 'Export stems',
            subtitle: 'Base, pitch, bass, pads, words, drums and quote as WAVs',
            value: c.exportStems,
            onChanged: (v) => c.setExport(stems: v),
          ),
          SwitchRow(
            title: 'Export MIDI',
            subtitle: "The sample chart and the base's notes",
            value: c.exportMidi,
            onChanged: (v) => c.setExport(midi: v),
          ),
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child, this.tooltip});
  final String label;
  final String? tooltip;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: tooltip == null ? text : Tooltip(message: tooltip!, child: text),
          ),
          child,
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.value, required this.values, required this.label, required this.onChanged});
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 12.5, color: AppColors.text, fontFamily: 'Inter'),
      dropdownColor: AppColors.surface,
      items: [for (final v in values) DropdownMenuItem(value: v, child: Text(label(v)))],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({required this.style, required this.selected, required this.onTap});
  final VisualStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (style) {
      VisualStyle.classic => Icons.grid_view,
      VisualStyle.modern => Icons.dashboard_outlined,
      VisualStyle.chaos => Icons.blur_on,
      VisualStyle.minimal => Icons.crop_square,
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selected ? AppColors.sparta.withValues(alpha: 0.16) : AppColors.surface,
          border: Border.all(color: selected ? AppColors.sparta : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.spartaHi : AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                style == VisualStyle.classic ? '${style.label} (default)' : style.label,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.text : AppColors.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelSlider extends StatefulWidget {
  const _LevelSlider({
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
    this.min = -12,
    this.max = 6,
    this.format,
    this.on = true,
    this.onToggle,
  });
  final String label;
  final Color color;
  final double value;
  final ValueChanged<double> onChanged;
  final double min, max;
  final String Function(double value)? format;

  /// Whether the lane plays (with [onToggle], a switch turns it off).
  final bool on;
  final ValueChanged<bool>? onToggle;

  @override
  State<_LevelSlider> createState() => _LevelSliderState();
}

class _LevelSliderState extends State<_LevelSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          if (widget.onToggle == null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
            )
          else
            Tooltip(
              message: widget.on ? 'Playing — click to switch it off' : 'Off — click to switch it on',
              child: InkWell(
                onTap: () => widget.onToggle!(!widget.on),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: widget.on ? widget.color : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.color, width: 1.5),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(widget.label, style: TextStyle(fontSize: 12, color: widget.on ? null : AppColors.faint)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(activeTrackColor: widget.color),
              child: Slider(
                value: v,
                min: widget.min,
                max: widget.max,
                onChanged: widget.on ? (x) => setState(() => _drag = x) : null,
                onChangeEnd: (x) {
                  setState(() => _drag = null);
                  widget.onChanged(x);
                },
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              widget.format?.call(v) ?? '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.faint,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
