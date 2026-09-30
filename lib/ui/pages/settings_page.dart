import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/engine_controller.dart';
import '../../state/history_controller.dart';
import '../../state/library_controller.dart';
import '../../state/project_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/update_controller.dart';
import '../dialogs/preset_dialog.dart';
import '../file_dialogs.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final engine = context.watch<EngineController>();
    final updates = context.watch<UpdateController>();
    final kit = engine.toolkit;

    Future<void> redetect() async {
      await engine.detect(ffmpegOverride: settings.ffmpegOverride);
      if (context.mounted) {
        context.read<ProjectController>().reprobeFailed();
        showMessage(
          context,
          engine.ready ? 'Found ${kit?.versionLine ?? 'FFmpeg'}' : 'FFmpeg still not found.',
          error: !engine.ready,
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        surfaceTintColor: Colors.transparent,
        title: const Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _Card(
                title: 'FFmpeg',
                icon: Icons.memory,
                children: [
                  Row(
                    children: [
                      Icon(
                        engine.ready ? Icons.check_circle : Icons.error_outline,
                        color: engine.ready ? AppColors.success : AppColors.danger,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              engine.ready ? kit!.versionLine : 'FFmpeg not found',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            SelectableText(
                              engine.ready
                                  ? '${kit!.ffmpegPath}  (${kit.source})'
                                  : 'Release builds ship FFmpeg next to the app. For source builds install it '
                                        '(winget install ffmpeg · brew install ffmpeg · sudo apt install ffmpeg) or point to it below.',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (engine.ready && engine.missingFilters.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'This build is missing: ${engine.missingFilters.join(', ')}. Effects using them will fail — '
                      'a full build (e.g. BtbN or gyan.dev "full") is recommended.',
                      style: const TextStyle(fontSize: 12, color: AppColors.warn),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          settings.ffmpegOverride == null
                              ? 'Using automatic detection'
                              : 'Custom: ${settings.ffmpegOverride}',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (settings.ffmpegOverride != null)
                        TextButton(
                          onPressed: () {
                            settings.setFfmpegOverride(null);
                            redetect();
                          },
                          child: const Text('Use automatic'),
                        ),
                      OutlinedButton(
                        onPressed: () async {
                          final files = await pickFilesSafely(context, dialogTitle: 'Locate the ffmpeg executable');
                          final path = files.isEmpty ? null : files.first.path;
                          if (path != null) {
                            settings.setFfmpegOverride(path);
                            await redetect();
                          }
                        },
                        child: const Text('Choose ffmpeg…'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: redetect, child: const Text('Re-detect')),
                    ],
                  ),
                ],
              ),
              _Card(
                title: 'Output',
                icon: Icons.ios_share,
                children: [
                  _Row(
                    label: 'Output folder',
                    description: settings.outputDir,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(onPressed: () => openFolder(settings.outputDir), child: const Text('Open')),
                        OutlinedButton(
                          onPressed: () async {
                            final dir = await pickDirectorySafely(context, initialDirectory: settings.outputDir);
                            if (dir != null) settings.setOutputDir(dir);
                          },
                          child: const Text('Change…'),
                        ),
                      ],
                    ),
                  ),
                  _Row(
                    label: 'Reset to default folder',
                    description: SettingsController.defaultOutputDir(),
                    trailing: TextButton(
                      onPressed: () => settings.setOutputDir(SettingsController.defaultOutputDir()),
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
              _Card(
                title: 'Preview & performance',
                icon: Icons.speed,
                children: [
                  _Row(
                    label: 'Auto preview',
                    description: 'Render a short preview whenever the effect or its settings change.',
                    trailing: Switch(value: settings.autoPreview, onChanged: settings.setAutoPreview),
                  ),
                  _Row(
                    label: 'Preview length',
                    description: '${settings.previewSeconds.round()} seconds from the trim start, at 480p.',
                    trailing: SizedBox(
                      width: 220,
                      child: Slider(
                        value: settings.previewSeconds,
                        min: 2,
                        max: 20,
                        divisions: 18,
                        onChanged: settings.setPreviewSeconds,
                      ),
                    ),
                  ),
                  _Row(
                    label: 'Effect thumbnails',
                    description: 'Show every effect applied to your clip in the effect list.',
                    trailing: Switch(value: settings.effectThumbnails, onChanged: settings.setEffectThumbnails),
                  ),
                  _Row(
                    label: 'Parallel compilation renders',
                    description:
                        'How many compilation segments render at once (${settings.concurrency}). '
                        'Higher is faster on many-core CPUs but uses more memory.',
                    trailing: SizedBox(
                      width: 220,
                      child: Slider(
                        value: settings.concurrency.toDouble(),
                        min: 1,
                        max: 4,
                        divisions: 3,
                        onChanged: (v) => settings.setConcurrency(v.round()),
                      ),
                    ),
                  ),
                  _Row(
                    label: 'Clear preview cache',
                    description: 'Removes cached previews and thumbnails.',
                    trailing: TextButton(
                      onPressed: () async {
                        await engine.clearCache();
                        if (context.mounted) showMessage(context, 'Cache cleared.');
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
              _Card(
                title: 'Updates',
                icon: Icons.system_update_alt,
                children: [
                  _Row(
                    label: 'Check for updates on launch',
                    description: updates.version.isEmpty ? '' : 'You have version ${updates.version}.',
                    trailing: Switch(value: settings.autoCheckUpdates, onChanged: settings.setAutoCheckUpdates),
                  ),
                  _Row(
                    label: updates.available != null
                        ? 'Version ${updates.available!.latest} is available'
                        : 'Check now',
                    trailing: updates.available != null
                        ? FilledButton(onPressed: () => openUrl(updates.available!.url), child: const Text('Download'))
                        : OutlinedButton(
                            onPressed: updates.checking
                                ? null
                                : () async {
                                    final found = await updates.check();
                                    if (context.mounted && !found) showMessage(context, 'You are up to date.');
                                  },
                            child: Text(updates.checking ? 'Checking…' : 'Check'),
                          ),
                  ),
                ],
              ),
              _Card(
                title: 'Data',
                icon: Icons.storage_outlined,
                children: [
                  _Row(
                    label: 'Clear favorites, recents & presets',
                    trailing: TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () async {
                        if (await confirmDelete(
                          context,
                          'Clear library?',
                          'Favorites, recents and presets will be removed. Custom effects are kept.',
                        )) {
                          if (context.mounted) await context.read<LibraryController>().clear();
                        }
                      },
                      child: const Text('Clear'),
                    ),
                  ),
                  _Row(
                    label: 'Clear render history',
                    trailing: TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () => context.read<HistoryController>().clear(),
                      child: const Text('Clear'),
                    ),
                  ),
                ],
              ),
              _Card(
                title: 'About',
                icon: Icons.info_outline,
                children: [
                  const Text(
                    'Video Effects Studio — logo-editing style effects, G-Majors, vocoders and compilations, powered by FFmpeg. '
                    'Effect recipes are inspired by the Logo Editing Wiki and the original NotSoBot tags.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => openUrl('https://github.com/${UpdateController.repo}'),
                        icon: const Icon(Icons.code, size: 16),
                        label: const Text('Source'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => openUrl('https://github.com/${UpdateController.repo}/issues'),
                        icon: const Icon(Icons.bug_report_outlined, size: 16),
                        label: const Text('Report a bug'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => showLicensePage(
                          context: context,
                          applicationName: 'Video Effects Studio',
                          applicationVersion: updates.version,
                        ),
                        icon: const Icon(Icons.description_outlined, size: 16),
                        label: const Text('Licenses'),
                      ),
                    ],
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

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: AppColors.accentHi),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.description, required this.trailing});
  final String label;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (description != null && description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(description!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        trailing,
      ],
    ),
  );
}
