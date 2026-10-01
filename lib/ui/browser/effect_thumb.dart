import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/effects/effect.dart';
import '../../state/engine_controller.dart';
import '../../state/project_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/thumbnail_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// A still of [effect] applied to the active clip, or a category glyph when
/// there is nothing to show (no clip, thumbnails off, audio-only effect).
class EffectThumb extends StatelessWidget {
  const EffectThumb({
    super.key,
    required this.effect,
    required this.params,
    this.width = 72,
    this.height = 42,
    this.radius = 6,
  });

  final Effect effect;
  final Map<String, Object?> params;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.category(effect.category);
    final glyph = CategoryGlyph(color: color, icon: AppColors.categoryIcon(effect.category), size: height);
    final enabled = context.select<SettingsController, bool>((s) => s.effectThumbnails);
    final clip = context.select<ProjectController, SourceClip?>((p) => p.active);
    final media = clip?.info;
    final engine = context.read<EngineController>();
    if (!enabled || media == null || !media.hasVideo || engine.engine == null) {
      return SizedBox(
        width: width,
        height: height,
        child: Align(alignment: Alignment.centerLeft, child: glyph),
      );
    }

    final at = clip!.trimStart + math.min(1.0, clip.trimmedLength / 2);
    // Audio-only effects look like the original frame.
    final visual = effect.video == null ? null : effect;
    final key =
        '${media.path}|${at.toStringAsFixed(2)}|${visual?.id ?? '-'}|${visual == null ? '' : params}|${width.round()}';
    final thumbs = context.watch<ThumbnailService>();
    thumbs.request(key, () {
      return engine.engine!.thumbnail(
        media: media,
        effect: visual,
        params: params,
        atSeconds: at,
        cacheDir: engine.cacheDir,
        width: (width * 2).round(),
      );
    });
    final path = thumbs.pathFor(key);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: AppColors.surfaceHi),
            if (path != null)
              Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium)
            else if (thumbs.isDone(key))
              Center(child: Icon(AppColors.categoryIcon(effect.category), size: 16, color: color))
            else
              const Center(child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))),
            if (effect.video == null)
              Positioned(
                right: 3,
                bottom: 3,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.graphic_eq, size: 11, color: color),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
