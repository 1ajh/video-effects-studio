import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../state/engine_controller.dart';
import '../../state/playback_controller.dart';
import '../../state/preview_controller.dart';
import '../../state/project_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/thumbnail_service.dart';
import '../actions.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'trim_bar.dart';

/// Center stage: before/after player, transport and trim.
class PreviewPanel extends StatelessWidget {
  const PreviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectController>();
    final clip = project.active;
    if (clip == null) return const _DropHint();

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          const _PreviewHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: clip.info == null
                  ? Center(
                      child: clip.probing
                          ? const CircularProgressIndicator()
                          : EmptyState(icon: Icons.error_outline, title: 'Can\'t read this file', message: clip.error),
                    )
                  : const _Stage(),
            ),
          ),
          if (clip.info != null) ...[const _Transport(), const TrimBar()],
        ],
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader();

  @override
  Widget build(BuildContext context) {
    final preview = context.watch<PreviewController>();
    final settings = context.watch<SettingsController>();
    final target = preview.target;
    String status;
    if (preview.rendering) {
      status = 'Rendering preview of ${preview.effectName} · ${(preview.progress * 100).round()}%';
    } else if (preview.error != null) {
      status = 'Preview failed';
    } else if (target == null) {
      status = 'Pick an effect to preview it';
    } else if (preview.isCurrent) {
      status = 'Preview: ${target.effect.name} · first ${settings.previewSeconds.round()}s at 480p';
    } else {
      status = settings.autoPreview ? 'Preparing ${target.effect.name}…' : 'Preview is out of date';
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SegmentedButton<ViewMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ViewMode.original,
                label: Text('Original'),
                icon: Icon(Icons.movie_outlined, size: 15),
              ),
              ButtonSegment(value: ViewMode.effect, label: Text('Effect'), icon: Icon(Icons.auto_awesome, size: 15)),
              ButtonSegment(
                value: ViewMode.split,
                label: Text('Split'),
                icon: Icon(Icons.vertical_split_outlined, size: 15),
              ),
            ],
            selected: {preview.viewMode},
            onSelectionChanged: (s) => preview.setViewMode(s.first),
          ),
          const SizedBox(width: 14),
          if (preview.rendering)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: preview.progress > 0.02 ? preview.progress : null,
              ),
            )
          else if (preview.error != null)
            const Icon(Icons.error_outline, size: 16, color: AppColors.danger)
          else if (preview.isCurrent)
            const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: preview.error ?? '',
              child: Text(
                status,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: preview.error != null ? AppColors.danger : AppColors.muted),
              ),
            ),
          ),
          Tooltip(
            message: 'Render a preview whenever the effect or its settings change',
            child: Row(
              children: [
                const Text('Auto', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                Transform.scale(
                  scale: 0.7,
                  child: Switch(value: settings.autoPreview, onChanged: settings.setAutoPreview),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            onPressed: target == null ? null : () => StudioActions(context).previewNow(),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Preview  ⌃P'),
          ),
        ],
      ),
    );
  }
}

/// The video area (single or split).
class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) {
    final preview = context.watch<PreviewController>();
    final playback = context.watch<PlaybackController>();
    final mode = preview.viewMode;
    final hasEffect = preview.path != null;

    Widget pane(bool effect, {String? label}) {
      final Widget body;
      if (effect && !hasEffect) {
        body = _PreviewPlaceholder(rendering: preview.rendering, error: preview.error, progress: preview.progress);
      } else if (playback.available) {
        body = Video(
          controller: effect ? playback.effectVideo! : playback.originalVideo!,
          controls: null,
          fill: Colors.black,
        );
      } else {
        body = _StillFallback(effect: effect);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              body,
              if (label != null)
                Positioned(
                  left: 10,
                  top: 10,
                  child: Pill(label, color: effect ? AppColors.accentHi : AppColors.text, filled: true),
                ),
              if (effect && preview.rendering && hasEffect)
                const Positioned(right: 10, top: 10, child: Pill('Updating…', icon: Icons.autorenew, filled: true)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: switch (mode) {
            ViewMode.original => pane(false),
            ViewMode.effect => pane(true),
            ViewMode.split => Row(
              children: [
                Expanded(child: pane(false, label: 'Before')),
                const SizedBox(width: 10),
                Expanded(child: pane(true, label: 'After')),
              ],
            ),
          },
        ),
        if (!playback.available)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: AppColors.warn),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    Platform.isLinux
                        ? 'In-app playback needs libmpv (sudo apt install libmpv2). Showing stills — use "Open in player" to watch.'
                        : 'In-app playback is unavailable. Showing stills — use "Open in player" to watch.',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.rendering, required this.error, required this.progress});
  final bool rendering;
  final String? error;
  final double progress;

  @override
  Widget build(BuildContext context) {
    if (rendering) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                value: progress > 0.02 ? progress : null,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Rendering preview…', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
        ),
      );
    }
    if (error != null) {
      return EmptyState(icon: Icons.error_outline, title: 'Preview failed', message: error);
    }
    return const EmptyState(
      icon: Icons.auto_awesome_outlined,
      title: 'No preview yet',
      message: 'Select an effect — a short preview renders automatically (or press Ctrl+P).',
    );
  }
}

/// Still frames when libmpv isn't available.
class _StillFallback extends StatelessWidget {
  const _StillFallback({required this.effect});
  final bool effect;

  @override
  Widget build(BuildContext context) {
    final clip = context.watch<ProjectController>().active;
    final preview = context.watch<PreviewController>();
    final engine = context.read<EngineController>();
    final info = clip?.info;
    if (info == null || engine.engine == null) return const SizedBox();
    final target = effect ? preview.target : null;
    final at = clip!.trimStart + (clip.trimmedLength / 2).clamp(0, 1.0);
    final key = 'still|${info.path}|$at|${target?.effect.id}|${target?.params}';
    final thumbs = context.watch<ThumbnailService>();
    thumbs.request(
      key,
      () => engine.engine!.thumbnail(
        media: info,
        effect: target?.effect,
        params: target?.params ?? const {},
        atSeconds: at,
        cacheDir: engine.cacheDir,
        width: 960,
      ),
    );
    final path = thumbs.pathFor(key);
    final file = effect ? preview.path : clip.path;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (path != null) Image.file(File(path), fit: BoxFit.contain, gaplessPlayback: true),
        if (file != null)
          Positioned(
            right: 12,
            bottom: 12,
            child: FilledButton.icon(
              onPressed: () => openFile(file),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open in player'),
            ),
          ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport();

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    final preview = context.watch<PreviewController>();
    final clip = context.watch<ProjectController>().active!;
    final showingEffect = preview.viewMode != ViewMode.original && preview.path != null;
    final pos = showingEffect ? playback.positionSeconds : playback.positionSeconds - clip.trimStart;
    final total = showingEffect ? null : clip.trimmedLength;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ToolButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Back to start (Home)',
            onPressed: playback.available ? playback.restart : null,
            size: 20,
          ),
          const SizedBox(width: 2),
          Material(
            color: AppColors.accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: playback.available ? playback.togglePlay : null,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${formatDuration(pos.clamp(0, 1e9), precise: true)}${total == null ? '' : ' / ${formatDuration(total, precise: true)}'}',
            style: const TextStyle(
              fontSize: 12.5,
              fontFeatures: [FontFeature.tabularFigures()],
              color: AppColors.muted,
            ),
          ),
          const Spacer(),
          if (showingEffect)
            TextButton.icon(
              onPressed: () => openFile(preview.path!),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Open preview', style: TextStyle(fontSize: 12)),
            ),
          const SizedBox(width: 8),
          Icon(playback.volume == 0 ? Icons.volume_off : Icons.volume_up, size: 16, color: AppColors.muted),
          SizedBox(
            width: 110,
            child: Slider(
              value: playback.volume,
              min: 0,
              max: 100,
              onChanged: playback.available ? playback.setVolume : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => StudioActions(context).importFiles(),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 340),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderHi, width: 1.5),
              gradient: LinearGradient(
                colors: [AppColors.accent.withValues(alpha: 0.08), AppColors.compilation.withValues(alpha: 0.04)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: const Icon(Icons.video_library_outlined, size: 34, color: AppColors.accentHi),
                  ),
                  const SizedBox(height: 18),
                  Text('Drop a video to get started', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'or click to browse · MP4, MOV, MKV, WebM, AVI, GIF, MP3, WAV…',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => StudioActions(context).importFiles(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add clips   Ctrl+O'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
