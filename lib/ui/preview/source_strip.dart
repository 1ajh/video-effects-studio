import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/engine_controller.dart';
import '../../state/project_controller.dart';
import '../../state/thumbnail_service.dart';
import '../actions.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Horizontal strip of loaded clips.
class SourceStrip extends StatelessWidget {
  const SourceStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectController>();
    final sources = project.sources;
    return Container(
      height: 76,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              itemCount: sources.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == sources.length) return const _AddCard();
                return _ClipCard(clip: sources[i], active: i == project.activeIndex, onTap: () => project.select(i));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ClipCard extends StatelessWidget {
  const _ClipCard({required this.clip, required this.active, required this.onTap});
  final SourceClip clip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final info = clip.info;
    return Hover(
      cursor: SystemMouseCursors.click,
      builder: (context, hover) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 220,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.14)
                : (hover ? AppColors.surfaceHi : AppColors.surface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.7) : AppColors.border),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(width: 80, height: 45, child: _ClipPoster(clip: clip)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      clip.probing
                          ? 'Reading…'
                          : clip.error != null
                          ? clip.error!
                          : '${formatDuration(info!.duration)} · ${info.resolutionLabel}'
                                '${info.hasAudio ? '' : ' · no audio'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: clip.error != null ? AppColors.danger : AppColors.faint),
                    ),
                  ],
                ),
              ),
              if (hover)
                ToolButton(
                  icon: Icons.close,
                  tooltip: 'Remove clip',
                  size: 15,
                  onPressed: () => context.read<ProjectController>().remove(clip),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipPoster extends StatelessWidget {
  const _ClipPoster({required this.clip});
  final SourceClip clip;

  @override
  Widget build(BuildContext context) {
    final info = clip.info;
    final engine = context.read<EngineController>();
    if (info == null || !info.hasVideo || engine.engine == null) {
      return Container(
        color: AppColors.surfaceHi,
        child: Icon(info?.hasAudio == true ? Icons.audiotrack : Icons.movie_outlined, size: 18, color: AppColors.faint),
      );
    }
    final at = (info.duration * 0.3).clamp(0, 2).toDouble();
    final key = 'poster|${info.path}|$at';
    final thumbs = context.watch<ThumbnailService>();
    thumbs.request(
      key,
      () => engine.engine!.thumbnail(
        media: info,
        effect: null,
        params: const {},
        atSeconds: at,
        cacheDir: engine.cacheDir,
        width: 160,
      ),
    );
    final path = thumbs.pathFor(key);
    return path == null
        ? Container(color: AppColors.surfaceHi)
        : Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true);
  }
}

class _AddCard extends StatelessWidget {
  const _AddCard();

  @override
  Widget build(BuildContext context) {
    return Hover(
      cursor: SystemMouseCursors.click,
      builder: (context, hover) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => StudioActions(context).importFiles(),
        child: Container(
          width: 150,
          decoration: BoxDecoration(
            color: hover ? AppColors.surfaceHi : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderHi, style: BorderStyle.solid),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: AppColors.muted),
              SizedBox(width: 6),
              Text(
                'Add clips',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
