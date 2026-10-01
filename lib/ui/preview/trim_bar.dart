import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/playback_controller.dart';
import '../../state/project_controller.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// In/out range for everything that gets rendered from the active clip.
class TrimBar extends StatefulWidget {
  const TrimBar({super.key});

  @override
  State<TrimBar> createState() => _TrimBarState();
}

class _TrimBarState extends State<TrimBar> {
  RangeValues? _dragging;

  @override
  Widget build(BuildContext context) {
    final project = context.watch<ProjectController>();
    final playback = context.watch<PlaybackController>();
    final clip = project.active!;
    final d = clip.duration;
    if (d <= 0) return const SizedBox(height: 8);
    final values = _dragging ?? RangeValues(clip.trimStart, clip.effectiveEnd);
    final playhead = playback.sourcePosition.clamp(0, d).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              // Slider track spans the width minus the thumb overlay padding.
              const inset = 14.0;
              final x = inset + (c.maxWidth - inset * 2) * (playhead / d);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  RangeSlider(
                    values: values,
                    min: 0,
                    max: d,
                    onChanged: (v) => setState(() => _dragging = v),
                    onChangeEnd: (v) {
                      setState(() => _dragging = null);
                      project.setTrim(v.start, v.end);
                    },
                  ),
                  if (playback.available)
                    Positioned(
                      left: x - 1,
                      top: 6,
                      bottom: 6,
                      child: IgnorePointer(
                        child: Container(width: 2, color: AppColors.compilation.withValues(alpha: 0.9)),
                      ),
                    ),
                ],
              );
            },
          ),
          Row(
            children: [
              const Icon(Icons.content_cut, size: 14, color: AppColors.faint),
              const SizedBox(width: 6),
              Text(
                'In ${formatDuration(values.start, precise: true)}  ·  Out ${formatDuration(values.end, precise: true)}'
                '  ·  ${formatDuration(values.end - values.start, precise: true)} of ${formatDuration(d, precise: true)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              if (playback.available) ...[
                _TrimButton(
                  label: 'Set in  I',
                  onPressed: () => project.setTrim(playback.sourcePosition, clip.effectiveEnd),
                ),
                _TrimButton(
                  label: 'Set out  O',
                  onPressed: () => project.setTrim(clip.trimStart, playback.sourcePosition),
                ),
              ],
              if (clip.isTrimmed)
                ToolButton(icon: Icons.restart_alt, tooltip: 'Reset trim', size: 16, onPressed: project.resetTrim),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrimButton extends StatelessWidget {
  const _TrimButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.muted,
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    onPressed: onPressed,
    child: Text(label, style: const TextStyle(fontSize: 12)),
  );
}
