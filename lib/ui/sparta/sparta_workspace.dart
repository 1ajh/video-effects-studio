import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sparta/arranger.dart';
import '../../core/sparta/base.dart';
import '../../core/sparta/model.dart';
import '../../state/sparta_controller.dart';
import '../../state/sparta_playback.dart';
import '../actions.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sparta_sections.dart';
import 'sparta_setup.dart';
import 'sparta_style.dart';

/// The Sparta Remix mode: setup on the left, generate/review on the right.
class SpartaWorkspace extends StatefulWidget {
  const SpartaWorkspace({super.key});

  @override
  State<SpartaWorkspace> createState() => _SpartaWorkspaceState();
}

class _SpartaWorkspaceState extends State<SpartaWorkspace> {
  late final SpartaController _c = context.read<SpartaController>();
  int _loaded = -1;

  @override
  void initState() {
    super.initState();
    _c.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _c.removeListener(_sync);
    super.dispose();
  }

  /// Feed each new preview mix to the player (keeping the playhead).
  void _sync() {
    final path = _c.previewPath;
    if (path == null || _c.previewVersion == _loaded || !mounted) return;
    _loaded = _c.previewVersion;
    context.read<SpartaPlayback>().loadPreview(path, _c.previewVersion);
  }

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 372, child: SpartaSetupPanel()),
        VerticalDivider(width: 1),
        Expanded(child: _ReviewArea()),
      ],
    );
  }
}

class _ReviewArea extends StatelessWidget {
  const _ReviewArea();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Header(),
        if (c.busy)
          const LinearProgressIndicator(minHeight: 2, color: AppColors.sparta, backgroundColor: Colors.transparent),
        Expanded(
          child: c.mix == null
              ? const _Onboarding()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: const [
                    _PreviewCard(),
                    SizedBox(height: 18),
                    SectionLabel('SAMPLES — AUDITION, SWAP OR NUDGE'),
                    _SamplesGrid(),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final message = c.error ?? (c.busy ? c.status : null);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
        gradient: LinearGradient(
          colors: [Color(0x22FF5A36), Color(0x00FF5A36)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department, color: AppColors.sparta, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sparta Remix Generator', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  message ??
                      (c.mix == null
                          ? 'Finds the samples, tunes them to D, writes the chart, mixes, masters and makes the video.'
                          : 'Change anything on the left — the preview updates by itself.'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.error != null ? AppColors.danger : AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (c.busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.sparta),
              ),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.sparta,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
            onPressed: c.canGenerate ? c.generate : null,
            icon: Icon(c.mix == null ? Icons.auto_fix_high : Icons.refresh, size: 18),
            label: Text(c.mix == null ? 'Generate remix' : 'Re-pick samples'),
          ),
        ],
      ),
    );
  }
}

class _Onboarding extends StatelessWidget {
  const _Onboarding();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    Widget step(int n, String title, String text, bool done) => Container(
      width: 230,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: done ? AppColors.success.withValues(alpha: 0.6) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$n',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.spartaHi),
              ),
              const Spacer(),
              if (done) const Icon(Icons.check_circle, color: AppColors.success, size: 18),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35)),
        ],
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department, size: 54, color: AppColors.sparta),
            const SizedBox(height: 10),
            const Text('Make a real Sparta remix', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const SizedBox(
              width: 520,
              child: Text(
                'Everything is automatic: pitch, chop, drum and quote samples are found in your sources, '
                'pitch-corrected to D and sustained, placed on a base, mixed and mastered — then the video is cut to every hit.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                step(
                  1,
                  'Add sources',
                  'Videos or audio of someone talking or singing. More sources, more variety.',
                  c.readySources > 0,
                ),
                step(
                  2,
                  'Pick a base',
                  'A built-in base, your FL Studio / FL Mobile / MIDI project, or any base audio.',
                  c.baseReady,
                ),
                step(
                  3,
                  'Generate',
                  'One click. Then audition and swap any sample, re-roll sections, tweak the mix.',
                  c.mix != null,
                ),
                step(
                  4,
                  'Render',
                  'Choose a visual style and export the video — plus stems and MIDI if you like.',
                  false,
                ),
              ],
            ),
            if (!c.engineReady) ...[
              const SizedBox(height: 18),
              const Text('FFmpeg is needed — see the banner above.', style: TextStyle(color: AppColors.warn)),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Preview
// -----------------------------------------------------------------------------

class _PreviewCard extends StatelessWidget {
  const _PreviewCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final play = context.watch<SpartaPlayback>();
    final mix = c.mix!;
    final base = c.prepared!.base;
    final pos = play.auditioning == null ? play.position : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PlayButton(
                playing: play.playing && play.auditioning == null,
                enabled: play.available,
                onPressed: () async {
                  if (play.auditioning != null && c.previewPath != null) {
                    await play.loadPreview(c.previewPath!, c.previewVersion, play: true);
                  } else {
                    await play.toggle();
                  }
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.remixName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      play.available
                          ? '${formatDuration(pos)} / ${formatDuration(mix.duration)}'
                          : 'In-app playback is unavailable — open the preview in your player.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  Pill('${base.bpm.toStringAsFixed(base.bpm % 1 == 0 ? 0 : 1)} BPM', icon: Icons.speed),
                  Pill('${mix.events.length} hits', icon: Icons.graphic_eq),
                  Pill(
                    '${mix.lufs.toStringAsFixed(1)} LUFS',
                    icon: Icons.volume_up_outlined,
                    tooltip: 'Integrated loudness · peak ${mix.peakDb.toStringAsFixed(1)} dBFS',
                  ),
                ],
              ),
              if (!play.available && c.previewPath != null)
                ToolButton(icon: Icons.open_in_new, tooltip: 'Open preview', onPressed: () => openFile(c.previewPath!)),
            ],
          ),
          const SizedBox(height: 12),
          _Timeline(
            base: base,
            mix: mix,
            position: pos,
            onSeek: play.available ? play.seek : null,
            onMoveBoundary: c.busy ? null : c.moveSectionBoundary,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: SectionChips(base: base)),
              const SizedBox(width: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.sparta, foregroundColor: Colors.white),
                onPressed: c.busy ? null : () => StudioActions(context).renderSparta(),
                icon: const Icon(Icons.movie_creation_outlined, size: 17),
                label: const Text('Render remix'),
              ),
            ],
          ),
          if (base.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(base.notes, style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
          ],
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.enabled, required this.onPressed});
  final bool playing;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.sparta : AppColors.border,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}

/// Lanes of the mix over the base's sections. Click or drag to seek; drag a
/// section boundary (in the top strip) to move it, snapping to bars.
class _Timeline extends StatefulWidget {
  const _Timeline({required this.base, required this.mix, required this.position, this.onSeek, this.onMoveBoundary});
  final SpartaBase base;
  final RemixMix mix;
  final double position;
  final ValueChanged<double>? onSeek;
  final void Function(int boundary, double beat)? onMoveBoundary;

  @override
  State<_Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<_Timeline> {
  static const _strip = 22.0, _grab = 6.0;
  int? _dragging;
  double? _dragBeat;
  bool _hoverBoundary = false;

  double _beatAt(double x, double width) => (x / width).clamp(0.0, 1.0) * widget.mix.duration * widget.base.bpm / 60;

  /// The boundary (index of the section it ends) under [o], if any.
  int? _boundaryAt(Offset o, double width) {
    if (widget.onMoveBoundary == null || o.dy > _strip) return null;
    final dur = widget.mix.duration;
    if (dur <= 0) return null;
    final s = widget.base.sections;
    for (var i = 0; i + 1 < s.length; i++) {
      final x = widget.base.seconds(s[i].endBeat) / dur * width;
      if ((o.dx - x).abs() <= _grab) return i;
    }
    return null;
  }

  double _snap(double beat) {
    final bpb = widget.base.beatsPerBar;
    return (beat / bpb).round() * bpb.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        void seek(Offset o) => widget.onSeek?.call((o.dx / w).clamp(0.0, 1.0) * widget.mix.duration);
        final cursor = _dragging != null || _hoverBoundary
            ? SystemMouseCursors.resizeColumn
            : (widget.onSeek == null ? MouseCursor.defer : SystemMouseCursors.click);
        return MouseRegion(
          cursor: cursor,
          onHover: (e) {
            final over = _boundaryAt(e.localPosition, w) != null;
            if (over != _hoverBoundary) setState(() => _hoverBoundary = over);
          },
          onExit: (_) => _hoverBoundary ? setState(() => _hoverBoundary = false) : null,
          child: GestureDetector(
            // Grab where the pointer went down, not where the drag was
            // recognised (a few pixels later), so boundaries are easy to catch.
            dragStartBehavior: DragStartBehavior.down,
            onTapDown: (d) => seek(d.localPosition),
            onHorizontalDragStart: (d) {
              final b = _boundaryAt(d.localPosition, w);
              if (b != null) {
                setState(() {
                  _dragging = b;
                  _dragBeat = _snap(_beatAt(d.localPosition.dx, w));
                });
              } else {
                seek(d.localPosition);
              }
            },
            onHorizontalDragUpdate: (d) {
              if (_dragging == null) return seek(d.localPosition);
              setState(() => _dragBeat = _snap(_beatAt(d.localPosition.dx, w)));
            },
            onHorizontalDragEnd: (_) {
              final b = _dragging, beat = _dragBeat;
              setState(() {
                _dragging = null;
                _dragBeat = null;
              });
              if (b != null && beat != null) widget.onMoveBoundary?.call(b, beat);
            },
            child: CustomPaint(
              size: Size(w, 24 + SampleRole.values.length * 13 + 4),
              painter: _TimelinePainter(
                base: widget.base,
                mix: widget.mix,
                position: widget.position,
                dragBeat: _dragBeat,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.base, required this.mix, required this.position, this.dragBeat});
  final SpartaBase base;
  final RemixMix mix;
  final double position;

  /// Where a dragged section boundary would land.
  final double? dragBeat;

  static const _lanes = [
    SampleRole.quote,
    SampleRole.pitch,
    SampleRole.chop,
    SampleRole.kick,
    SampleRole.snare,
    SampleRole.hat,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final dur = math.max(0.1, mix.duration);
    double x(double t) => t / dur * size.width;
    final bg = Paint()..color = AppColors.bg;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)), bg);

    // Sections.
    for (final s in base.sections) {
      final a = x(base.seconds(s.startBeat)), b = x(base.seconds(s.endBeat));
      final color = sectionColor(s.kind);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(a + 1, 2, b - 1, 20), const Radius.circular(4)),
        Paint()..color = color.withValues(alpha: 0.35),
      );
      canvas.drawRect(Rect.fromLTRB(a, 22, a + 1, size.height), Paint()..color = color.withValues(alpha: 0.35));
      if (b - a > 40) {
        final tp = TextPainter(
          text: TextSpan(
            text: s.title,
            style: const TextStyle(fontSize: 10.5, color: AppColors.text, fontWeight: FontWeight.w600),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: b - a - 8);
        tp.paint(canvas, Offset(a + 5, 11 - tp.height / 2));
      }
    }

    // Lanes.
    for (var i = 0; i < _lanes.length; i++) {
      final y = 24.0 + i * 13;
      final paint = Paint()..color = laneColor(_lanes[i]).withValues(alpha: 0.9);
      canvas.drawRect(Rect.fromLTWH(0, y + 5, size.width, 1), Paint()..color = AppColors.border.withValues(alpha: 0.5));
      for (final e in mix.events) {
        if (e.role != _lanes[i]) continue;
        final a = x(e.start), w = math.max(1.5, x(e.end) - a);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(a, y + 1, w, 9), const Radius.circular(2)), paint);
      }
    }

    // Boundary being dragged.
    final drag = dragBeat;
    if (drag != null) {
      final dx = x(base.seconds(drag));
      canvas.drawRect(Rect.fromLTWH(dx - 1.5, 0, 3, size.height), Paint()..color = AppColors.sparta);
    }

    // Playhead.
    final px = x(position.clamp(0, dur).toDouble());
    canvas.drawRect(Rect.fromLTWH(px - 1, 0, 2, size.height), Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.position != position || old.mix != mix || old.base != base || old.dragBeat != dragBeat;
}

// -----------------------------------------------------------------------------
// Samples
// -----------------------------------------------------------------------------

class _SamplesGrid extends StatelessWidget {
  const _SamplesGrid();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final role in SampleRole.values)
          if (c.picks[role] != null) _SampleCard(pick: c.picks[role]!),
      ],
    );
  }
}

class _SampleCard extends StatelessWidget {
  const _SampleCard({required this.pick});
  final RolePick pick;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final play = context.watch<SpartaPlayback>();
    final role = pick.role;
    final color = laneColor(role);
    final cand = pick.current;
    final processed = c.processed[role];
    final tuned = processed != null && processed.isNotEmpty && processed.first.rootHz > 0
        ? processed.first.rootHz
        : null;

    Future<void> audition(int which) async {
      final path = await c.auditionPath(role, which: which);
      if (path != null) await play.audition(path, '${role.name}$which');
    }

    return Container(
      width: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(laneIcon(role), size: 16, color: color),
              const SizedBox(width: 6),
              Text(role.label, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              if (tuned != null)
                Pill(
                  '→ ${_noteOfHz(tuned)}',
                  color: color,
                  tooltip: 'Pitch-corrected to ${tuned.toStringAsFixed(1)} Hz',
                ),
              const Spacer(),
              Pill('${(cand.score * 100).round()}%', tooltip: 'How well it fits this lane'),
            ],
          ),
          const SizedBox(height: 4),
          Text(role.blurb, style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.subdirectory_arrow_right, size: 14, color: AppColors.faint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${c.sourceName(cand.sourceIndex)} · ${cand.start.toStringAsFixed(2)}–${cand.end.toStringAsFixed(2)} s',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MiniButton(
                icon: play.auditioning == '${role.name}0' && play.playing ? Icons.stop : Icons.play_arrow,
                label: 'Play',
                color: color,
                onPressed: !play.available || processed == null
                    ? null
                    : () => play.auditioning == '${role.name}0' && play.playing ? play.stop() : audition(0),
              ),
              const Spacer(),
              ToolButton(icon: Icons.chevron_left, tooltip: 'Previous candidate', onPressed: () => c.swap(role, -1)),
              Text(
                '${pick.index + 1} / ${pick.options.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              ToolButton(icon: Icons.chevron_right, tooltip: 'Next candidate', onPressed: () => c.swap(role, 1)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Start', style: TextStyle(fontSize: 11.5, color: AppColors.faint)),
              ToolButton(
                icon: Icons.remove,
                size: 14,
                tooltip: '20 ms earlier',
                onPressed: () => c.nudge(role, start: -0.02),
              ),
              ToolButton(
                icon: Icons.add,
                size: 14,
                tooltip: '20 ms later',
                onPressed: () => c.nudge(role, start: 0.02),
              ),
              const Spacer(),
              const Text('End', style: TextStyle(fontSize: 11.5, color: AppColors.faint)),
              ToolButton(
                icon: Icons.remove,
                size: 14,
                tooltip: '20 ms earlier',
                onPressed: () => c.nudge(role, end: -0.02),
              ),
              ToolButton(icon: Icons.add, size: 14, tooltip: '20 ms later', onPressed: () => c.nudge(role, end: 0.02)),
            ],
          ),
          if (pick.options.length > 1)
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: 'Alternate this lane between two samples (per section / per hit)',
                    child: Text(
                      pick.alternate == null
                          ? 'Second sample: off'
                          : 'Second: ${c.sourceName(pick.options[pick.alternate!].sourceIndex)} · '
                                '${pick.options[pick.alternate!].start.toStringAsFixed(2)} s',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ),
                ),
                if (pick.alternate != null && (processed?.length ?? 0) > 1)
                  ToolButton(
                    icon: Icons.play_arrow,
                    size: 15,
                    tooltip: 'Play the second sample',
                    onPressed: () => audition(1),
                  ),
                Transform.scale(
                  scale: 0.72,
                  child: Switch(value: pick.alternate != null, onChanged: (_) => c.toggleAlternate(role)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _noteOfHz(double hz) {
    final midi = (69 + 12 * math.log(hz / 440) / math.ln2).round();
    const names = ['C', 'C♯', 'D', 'E♭', 'E', 'F', 'F♯', 'G', 'A♭', 'A', 'B♭', 'B'];
    return '${names[midi % 12]}${midi ~/ 12 - 1}';
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.icon, required this.label, required this.color, required this.onPressed});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        foregroundColor: color,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
