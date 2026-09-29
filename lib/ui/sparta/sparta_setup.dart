import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sparta/arranger.dart';
import '../../core/sparta/composer.dart';
import '../../core/sparta/model.dart';
import '../../core/sparta/sample_processing.dart';
import '../../core/sparta/visual_renderer.dart';
import '../../state/project_controller.dart';
import '../../state/sparta_controller.dart';
import '../inspector/output_section.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sparta_style.dart';

/// Left column of the Sparta mode: sources, base, sound and look.
class SpartaSetupPanel extends StatelessWidget {
  const SpartaSetupPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panel,
      child: Column(
        children: [
          const PanelHeader(title: 'Remix setup', icon: Icons.tune),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
              children: const [_SourcesCard(), _BaseCard(), _SoundCard(), _LookCard()],
            ),
          ),
          const Divider(),
          const OutputSection(),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sources
// -----------------------------------------------------------------------------

class _SourcesCard extends StatelessWidget {
  const _SourcesCard();

  Future<void> _add(BuildContext context) async {
    final files = await FilePicker.pickFiles(
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

    return SpartaCard(
      step: 1,
      title: 'Sources',
      subtitle: 'Videos or audio with speech/singing. Several sources = more variety.',
      trailing: TextButton.icon(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('Add'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.sources.isEmpty)
            _DropHint(onTap: () => _add(context))
          else
            for (final s in c.sources) _SourceRow(source: s),
          if (importable.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => c.addSources(importable),
                  icon: const Icon(Icons.move_down, size: 15),
                  label: Text('Use ${importable.length} clip${importable.length == 1 ? '' : 's'} from the editor'),
                ),
              ),
            ),
        ],
      ),
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
// Base
// -----------------------------------------------------------------------------

class _BaseCard extends StatelessWidget {
  const _BaseCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return SpartaCard(
      step: 2,
      title: 'Base',
      subtitle: c.baseMode.blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<BaseMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: BaseMode.builtIn, label: Text('Built-in')),
              ButtonSegment(value: BaseMode.project, label: Text('Project')),
              ButtonSegment(value: BaseMode.audio, label: Text('Audio')),
            ],
            selected: {c.baseMode},
            onSelectionChanged: (s) => c.setBaseMode(s.first),
          ),
          const SizedBox(height: 12),
          switch (c.baseMode) {
            BaseMode.builtIn => const _BuiltInBase(),
            BaseMode.project => const _ProjectBase(),
            BaseMode.audio => const _AudioBase(),
          },
        ],
      ),
    );
  }
}

class _BuiltInBase extends StatelessWidget {
  const _BuiltInBase();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in BaseStyle.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ChoiceTile(
              selected: c.style == s,
              title: s.label,
              trailing: '${s.bpm.round()} BPM',
              subtitle: s.blurb,
              onTap: () => c.setStyle(s),
            ),
          ),
        const SizedBox(height: 6),
        const Text('Length', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 6),
        SegmentedButton<RemixLength>(
          showSelectedIcon: false,
          segments: [for (final l in RemixLength.values) ButtonSegment(value: l, label: Text(l.label))],
          selected: {c.length},
          onSelectionChanged: (s) => c.setLength(s.first),
        ),
        const SizedBox(height: 10),
        const Text('Sections', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in SectionKind.values.where((k) => k != SectionKind.other))
              FilterChip(
                label: Text(
                  k.label,
                  style: TextStyle(fontSize: 12, color: c.sections.contains(k) ? AppColors.text : AppColors.faint),
                ),
                backgroundColor: AppColors.surface,
                selected: c.sections.contains(k),
                showCheckmark: false,
                selectedColor: sectionColor(k).withValues(alpha: 0.28),
                side: BorderSide(color: c.sections.contains(k) ? sectionColor(k) : AppColors.border),
                onSelected: (_) => c.toggleSection(k),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Variation #${c.seed}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.faint),
              ),
            ),
            OutlinedButton.icon(
              onPressed: c.newVariation,
              icon: const Icon(Icons.casino_outlined, size: 16),
              label: const Text('New variation'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProjectBase extends StatelessWidget {
  const _ProjectBase();

  Future<void> _pickProject(BuildContext context) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Open a base project',
      type: FileType.custom,
      allowedExtensions: projectFileExtensions.toList(),
    );
    final path = files.map((f) => f.path).whereType<String>().firstOrNull;
    if (path != null && context.mounted) await context.read<SpartaController>().setProject(path);
  }

  Future<void> _pickAudio(BuildContext context) async {
    final files = await FilePicker.pickFiles(
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
    final chart = c.chart;
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
              ? "Base audio (optional — else it's re-synthesized)"
              : shortPath(c.projectAudioPath!),
          onTap: () => _pickAudio(context),
          onClear: c.projectAudioPath == null ? null : () => c.setProjectAudio(null),
        ),
        if (c.chartError != null) ...[
          const SizedBox(height: 8),
          Text(c.chartError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
        ],
        if (chart != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill('${chart.bpm.toStringAsFixed(chart.bpm % 1 == 0 ? 0 : 1)} BPM', icon: Icons.speed),
              Pill('${chart.bars} bars', icon: Icons.view_week_outlined),
              Pill('${chart.tracks.length} tracks', icon: Icons.list),
            ],
          ),
          for (final w in chart.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(w, style: const TextStyle(fontSize: 11.5, color: AppColors.warn)),
            ),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(
                child: Text('Tracks → sample lanes', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
              Tooltip(
                message:
                    'Leave everything on "Base part" and the sample chart is composed\nautomatically over the project\'s chords and drums.',
                child: Icon(Icons.help_outline, size: 15, color: AppColors.faint),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final t in chart.tracks) _TrackMapRow(trackId: t.id, name: t.name, detail: t.detail, drum: t.isDrums),
          const SizedBox(height: 8),
          _TransposeRow(value: c.transpose, onChanged: c.setTranspose),
          if (c.projectAudioPath != null) ...[
            const SizedBox(height: 8),
            _OffsetRow(value: c.manualOffset, detected: c.prepared?.base.audioOffset, onChanged: c.setManualOffset),
          ],
        ],
      ],
    );
  }
}

class _TrackMapRow extends StatelessWidget {
  const _TrackMapRow({required this.trackId, required this.name, required this.detail, required this.drum});
  final String trackId;
  final String name;
  final String detail;
  final bool drum;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final role = c.mapping[trackId];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(drum ? Icons.album_outlined : Icons.music_note_outlined, size: 15, color: AppColors.faint),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: detail.isEmpty ? name : '$name\n$detail',
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          DropdownButton<SampleRole?>(
            value: role,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 12, color: AppColors.text, fontFamily: 'Inter'),
            dropdownColor: AppColors.surface,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Base part', style: TextStyle(color: AppColors.faint)),
              ),
              for (final r in SampleRole.values)
                DropdownMenuItem(
                  value: r,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LaneDot(role: r),
                      const SizedBox(width: 6),
                      Text(r.label),
                    ],
                  ),
                ),
            ],
            onChanged: (r) => c.setMapping(trackId, r),
          ),
        ],
      ),
    );
  }
}

class _AudioBase extends StatelessWidget {
  const _AudioBase();

  Future<void> _pick(BuildContext context) async {
    final files = await FilePicker.pickFiles(
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
    final a = c.prepared?.analysis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FileRow(
          icon: Icons.audio_file_outlined,
          label: c.audioBasePath == null ? 'Choose a base audio file' : shortPath(c.audioBasePath!),
          onTap: () => _pick(context),
        ),
        if (a != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Pill('${a.bpm.toStringAsFixed(a.bpm % 1 == 0 ? 0 : 1)} BPM', icon: Icons.speed, color: AppColors.success),
              Pill('${a.bars} bars', icon: Icons.view_week_outlined),
              Pill('Key ${_noteName(a.tonicPc)}', icon: Icons.piano_outlined),
              Pill('Bar 1 at ${a.firstDownbeat.toStringAsFixed(2)}s', icon: Icons.flag_outlined),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
              child: Text('Tempo hint', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
            SizedBox(
              width: 110,
              child: TextFormField(
                initialValue: c.bpmHint?.toStringAsFixed(0) ?? '',
                decoration: const InputDecoration(hintText: 'auto', suffixText: 'BPM'),
                style: const TextStyle(fontSize: 12.5),
                keyboardType: TextInputType.number,
                onFieldSubmitted: (v) => c.setBpmHint(double.tryParse(v)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _TransposeRow(value: c.transpose, onChanged: c.setTranspose),
      ],
    );
  }

  static String _noteName(int pc) => const ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'][pc % 12];
}

class _TransposeRow extends StatelessWidget {
  const _TransposeRow({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Tooltip(
            message: 'Shift the sample melody if it clashes with the base',
            child: Text('Sample transpose', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
        ),
        ToolButton(icon: Icons.remove, size: 15, tooltip: 'Down a semitone', onPressed: () => onChanged(value - 1)),
        SizedBox(
          width: 44,
          child: Text(
            value == 0 ? '0' : (value > 0 ? '+$value' : '$value'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
        ToolButton(icon: Icons.add, size: 15, tooltip: 'Up a semitone', onPressed: () => onChanged(value + 1)),
      ],
    );
  }
}

class _OffsetRow extends StatelessWidget {
  const _OffsetRow({required this.value, required this.detected, required this.onChanged});
  final double? value;
  final double? detected;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = value ?? detected;
    return Row(
      children: [
        Expanded(
          child: Text(
            value == null
                ? 'Audio start: auto${detected == null ? '' : ' (${detected!.toStringAsFixed(3)}s)'}'
                : 'Audio start',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        ToolButton(
          icon: Icons.chevron_left,
          size: 15,
          tooltip: '10 ms earlier',
          onPressed: shown == null ? null : () => onChanged(shown - 0.01),
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
          onPressed: shown == null ? null : () => onChanged(shown + 0.01),
        ),
        if (value != null)
          ToolButton(icon: Icons.auto_fix_high, size: 15, tooltip: 'Detect again', onPressed: () => onChanged(null)),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Sound
// -----------------------------------------------------------------------------

class _SoundCard extends StatelessWidget {
  const _SoundCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final m = c.mixSettings;
    final e = c.enhance;
    return SpartaCard(
      step: 3,
      title: 'Sound',
      subtitle: m.master.blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Master', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ),
              SegmentedButton<MasterMode>(
                showSelectedIcon: false,
                segments: [for (final mm in MasterMode.values) ButtonSegment(value: mm, label: Text(mm.label))],
                selected: {m.master},
                onSelectionChanged: (s) => c.setMixSettings(m.copyWith(master: s.first)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SwitchRow(
            title: 'Chorus Crisp chops',
            subtitle: 'Doubled, tightened attack on chop samples',
            value: e.chorusCrisp,
            onChanged: (v) => c.setEnhance(
              EnhanceOptions(
                chorusCrisp: v,
                layerDrums: e.layerDrums,
                sustainSeconds: e.sustainSeconds,
                forceOctave: e.forceOctave,
              ),
            ),
          ),
          SwitchRow(
            title: 'Reinforce drum samples',
            subtitle: 'Layer a sub/body under kick, snare and hat samples',
            value: e.layerDrums,
            onChanged: (v) => c.setEnhance(
              EnhanceOptions(
                chorusCrisp: e.chorusCrisp,
                layerDrums: v,
                sustainSeconds: e.sustainSeconds,
                forceOctave: e.forceOctave,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Levels', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          _LevelSlider(
            label: 'Base',
            color: AppColors.muted,
            value: m.baseDb,
            onChanged: (v) => c.setMixSettings(m.copyWith(baseDb: v)),
          ),
          for (final r in SampleRole.values)
            _LevelSlider(
              label: r.label,
              color: laneColor(r),
              value: m.laneDb[r] ?? 0,
              onChanged: (v) => c.setLaneDb(r, v),
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
        ],
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
  });
  final String label;
  final Color color;
  final double value;
  final ValueChanged<double> onChanged;
  final double min, max;
  final String Function(double value)? format;

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
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 56, child: Text(widget.label, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(activeTrackColor: widget.color),
              child: Slider(
                value: v,
                min: widget.min,
                max: widget.max,
                onChanged: (x) => setState(() => _drag = x),
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

// -----------------------------------------------------------------------------
// Look
// -----------------------------------------------------------------------------

class _LookCard extends StatelessWidget {
  const _LookCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return SpartaCard(
      step: 4,
      title: 'Look & export',
      subtitle: c.preset.blurb,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.3,
            children: [
              for (final v in VisualPreset.values)
                _PresetTile(preset: v, selected: c.preset == v, onTap: () => c.setPreset(v)),
            ],
          ),
          const SizedBox(height: 8),
          SwitchRow(
            title: 'Export stems',
            subtitle: 'Base, pitch, chop, drums and quote as WAVs',
            value: c.exportStems,
            onChanged: (v) => c.setExport(stems: v),
          ),
          SwitchRow(
            title: 'Export MIDI',
            subtitle: 'The sample chart (and the base, when composed)',
            value: c.exportMidi,
            onChanged: (v) => c.setExport(midi: v),
          ),
        ],
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({required this.preset, required this.selected, required this.onTap});
  final VisualPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = switch (preset) {
      VisualPreset.classic => Icons.grid_view,
      VisualPreset.modern => Icons.dashboard_outlined,
      VisualPreset.chaos => Icons.blur_on,
      VisualPreset.minimal => Icons.crop_square,
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
                preset.label,
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
