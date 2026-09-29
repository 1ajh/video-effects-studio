import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/output_settings.dart';
import '../../state/settings_controller.dart';
import '../platform_actions.dart';
import '../theme.dart';

/// Export format, quality, resolution and destination.
class OutputSection extends StatefulWidget {
  const OutputSection({super.key});

  @override
  State<OutputSection> createState() => _OutputSectionState();
}

class _OutputSectionState extends State<OutputSection> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final o = settings.output;

    return Container(
      color: AppColors.panel,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.ios_share, size: 15, color: AppColors.muted),
                  const SizedBox(width: 8),
                  const Text(
                    'OUTPUT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _open ? '' : '${o.format.label} · ${o.quality.label} · ${o.resolution.label}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.faint),
                    ),
                  ),
                  Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18, color: AppColors.faint),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<OutputFormat>(
                          showSelectedIcon: false,
                          segments: [
                            for (final f in OutputFormat.values)
                              ButtonSegment(value: f, label: Text(f.label), tooltip: f.blurb),
                          ],
                          selected: {o.format},
                          onSelectionChanged: (s) => settings.setOutput(o.copyWith(format: s.first)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Dropdown<OutputQuality>(
                              label: 'Quality',
                              value: o.quality,
                              items: {for (final q in OutputQuality.values) q: q.label},
                              onChanged: (q) => settings.setOutput(o.copyWith(quality: q)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Dropdown<ResolutionCap>(
                              label: 'Size',
                              value: o.resolution,
                              enabled: o.format.hasVideo,
                              items: {for (final r in ResolutionCap.values) r: r.label},
                              onChanged: (r) => settings.setOutput(o.copyWith(resolution: r)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
                          final dir = await FilePicker.getDirectoryPath(
                            dialogTitle: 'Choose output folder',
                            initialDirectory: settings.outputDir,
                          );
                          if (dir != null) settings.setOutputDir(dir);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 16, color: AppColors.muted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Tooltip(
                                  message: settings.outputDir,
                                  child: Text(
                                    shortPath(settings.outputDir),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => openFolder(settings.outputDir),
                                child: const Tooltip(
                                  message: 'Open folder',
                                  child: Padding(
                                    padding: EdgeInsets.all(2),
                                    child: Icon(Icons.open_in_new, size: 15, color: AppColors.muted),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      isDense: true,
      dropdownColor: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 12)),
      style: const TextStyle(fontSize: 12.5, color: AppColors.text, fontFamily: 'Inter'),
      items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
      onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
    );
  }
}
