import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/engine_controller.dart';
import '../../state/project_controller.dart';
import '../../state/render_queue.dart';
import '../pages/settings_page.dart';
import '../platform_actions.dart';
import '../theme.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<EngineController>();
    final clip = context.select<ProjectController, SourceClip?>((p) => p.active);
    final queue = context.watch<RenderQueue>();
    final current = queue.current;
    final kit = engine.toolkit;

    final (Color dot, String ffmpeg) = switch (engine.status) {
      EngineStatus.detecting => (AppColors.warn, 'Looking for FFmpeg…'),
      EngineStatus.missing => (AppColors.danger, 'FFmpeg not found — click to set it up'),
      EngineStatus.ready => (
        engine.missingFilters.isEmpty ? AppColors.success : AppColors.warn,
        '${_shortVersion(kit!.versionLine)} · ${kit.source}'
            '${engine.missingFilters.isEmpty ? '' : ' · missing ${engine.missingFilters.length} filters'}',
      ),
    };

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 11.5, color: AppColors.faint, fontFamily: 'Inter'),
        child: Row(
          children: [
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(ffmpeg),
                ],
              ),
            ),
            if (clip?.info != null) ...[
              const _Sep(),
              Flexible(
                child: Text(
                  '${clip!.name} · ${clip.info!.resolutionLabel} · ${clip.info!.fps.toStringAsFixed(clip.info!.fps % 1 == 0 ? 0 : 2)} fps'
                  ' · ${formatDuration(clip.duration, precise: true)} · ${formatBytes(clip.info!.sizeBytes)}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const Spacer(),
            if (current != null)
              Text(
                '${current.title}: ${current.statusText} · ${(current.progress * 100).round()}%'
                '${current.eta == null ? '' : ' · ${formatDuration(current.eta!.inMilliseconds / 1000)} left'}',
              ),
          ],
        ),
      ),
    );
  }

  static String _shortVersion(String line) {
    final m = RegExp(r'ffmpeg version (\S+)').firstMatch(line);
    if (m == null) return 'FFmpeg';
    final v = m.group(1)!;
    return 'FFmpeg ${v.length > 18 ? '${v.substring(0, 18)}…' : v}';
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: Text('|', style: TextStyle(color: AppColors.border)),
  );
}
