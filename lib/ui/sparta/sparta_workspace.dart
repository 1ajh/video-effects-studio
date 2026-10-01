import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/sparta/arranger.dart';
import '../../core/sparta/model.dart';
import '../../core/sparta/transcription.dart';
import '../../state/sparta_controller.dart';
import '../../state/sparta_playback.dart';
import '../actions.dart';
import '../platform_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sparta_sections.dart';
import 'sparta_setup.dart';
import 'sparta_style.dart';

/// The Sparta Remix mode: the steps on the left, the base and remix on the
/// right.
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
        SizedBox(width: 380, child: SpartaSetupPanel()),
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
        if (c.busy || c.baseLoading)
          LinearProgressIndicator(
            value: c.progress,
            minHeight: 2,
            color: AppColors.sparta,
            backgroundColor: Colors.transparent,
          ),
        Expanded(
          child: c.prepared == null
              ? const _Onboarding()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    const _BaseCard(),
                    const SizedBox(height: 12),
                    if (c.hasResult) ...[const _PreviewBar(), const SizedBox(height: 10)],
                    const _TimelineCard(),
                    const SizedBox(height: 16),
                    const SectionEditor(),
                    if (c.hasResult) ...[
                      const SizedBox(height: 18),
                      const SectionLabel('SAMPLES — AUDITION, SWAP OR NUDGE'),
                      const SizedBox(height: 8),
                      const _SamplesGrid(),
                    ],
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
    final message = c.error ?? ((c.busy || c.baseLoading) && c.status.isNotEmpty ? c.status : null);
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
                      (c.hasResult
                          ? 'Change anything — the preview updates by itself.'
                          : 'Follows a real base exactly: its hits, drums and sections, with your line as the samples.'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.error != null ? AppColors.danger : AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (c.hasResult)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sparta,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                onPressed: c.busy ? null : () => StudioActions(context).renderSparta(),
                icon: const Icon(Icons.movie_creation_outlined, size: 18),
                label: const Text('Render remix'),
              ),
            )
          else
            Tooltip(
              message: c.missing ?? '',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sparta,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                onPressed: c.canGenerate ? c.generate : null,
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: const Text('Generate remix'),
              ),
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
    Widget step(SpartaStep s, String text) {
      final done = c.stepDone(s);
      return InkWell(
        onTap: () => c.goTo(s),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: done
                  ? AppColors.success.withValues(alpha: 0.6)
                  : (c.step == s ? AppColors.sparta : AppColors.border),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${s.index + 1}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.spartaHi),
                  ),
                  const Spacer(),
                  if (done) const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                ],
              ),
              const SizedBox(height: 6),
              Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35)),
            ],
          ),
        ),
      );
    }

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
              width: 560,
              child: Text(
                'Pick a real base and the remix follows it exactly: the pitch sample plays the base\'s own hits '
                '(tuned to its key), the chorus plays your line\'s words in the Sparta Remix Wiki\'s patterns, the '
                'percussion lands on its drums. Every sample is cut from your sources.',
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
                step(SpartaStep.base, 'A real base from the library, your base audio, or your FL / MIDI project.'),
                step(SpartaStep.source, 'Videos or audio of the person or character talking.'),
                step(SpartaStep.line, 'The line they say: the quote, and the words the chorus plays.'),
                step(SpartaStep.generate, 'Sound and video options (classic by default), then generate.'),
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
// Base
// -----------------------------------------------------------------------------

class _BaseCard extends StatelessWidget {
  const _BaseCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final base = c.prepared!.base;
    final t = c.transcription!;
    final exact = t.confidence >= 0.95;
    final id = c.selectedCatalogId;
    final page = id == null ? null : c.catalog?.byId(id)?.page;
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(base.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    if (base.author.isNotEmpty)
                      Text('Base by ${base.author}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              if (page != null && page.isNotEmpty)
                ToolButton(
                  icon: Icons.open_in_new,
                  tooltip: 'Where the base was published',
                  onPressed: () => openUrl(page),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Pill('${t.bpm.toStringAsFixed(t.bpm % 1 == 0 ? 0 : 1)} BPM', icon: Icons.speed),
              InkWell(
                onTap: () => pickRoot(context),
                borderRadius: BorderRadius.circular(20),
                child: Pill(
                  'Root ${keyName(t.rootKey)}',
                  icon: Icons.piano_outlined,
                  color: AppColors.accentHi,
                  tooltip: 'Change the root note (the pitch sample is tuned to it)',
                ),
              ),
              Pill('${t.bars} bars · ${t.sections.length} sections', icon: Icons.view_week_outlined),
              Pill(
                exact ? t.source.label : '${t.source.label} · ${(t.confidence * 100).round()}% sure',
                icon: exact ? Icons.verified_outlined : Icons.hearing,
                color: exact ? AppColors.success : AppColors.warn,
              ),
              if (base.audioPath != null) _OffsetNudge(offset: t.audioOffset),
            ],
          ),
          if (!exact) ...[
            const SizedBox(height: 8),
            const Text(
              'This was transcribed by listening, so check it: play the preview, then fix sections (below), the '
              'root, the hits or the drums. Your fixes are kept for this base — send them in and everyone gets them.',
              style: TextStyle(fontSize: 11.5, color: AppColors.faint, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (c.transcriptionFixed || c.choices.isNotEmpty)
                TextButton.icon(
                  onPressed: c.resetFixes,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Undo all fixes'),
                ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => submitTranscription(context),
                icon: const Icon(Icons.outbox_outlined, size: 16),
                label: Text(c.transcriptionFixed ? 'Send your fixes' : 'Send this transcription'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OffsetNudge extends StatelessWidget {
  const _OffsetNudge({required this.offset});
  final double offset;

  @override
  Widget build(BuildContext context) {
    final c = context.read<SpartaController>();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.muted.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => c.setOffset(offset - 0.01),
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.chevron_left, size: 14, color: AppColors.muted),
            ),
          ),
          Tooltip(
            message: 'Where beat 1 is in the audio. Nudge it if the remix is early or late against the base.',
            child: Text(
              'Beat 1 at ${offset.toStringAsFixed(2)} s',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted),
            ),
          ),
          InkWell(
            onTap: () => c.setOffset(offset + 0.01),
            child: const Padding(
              padding: EdgeInsets.all(3),
              child: Icon(Icons.chevron_right, size: 14, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Preview
// -----------------------------------------------------------------------------

class _PreviewBar extends StatelessWidget {
  const _PreviewBar();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final play = context.watch<SpartaPlayback>();
    final mix = c.mix!;
    final pos = play.auditioning == null ? play.position : 0.0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.sparta.withValues(alpha: 0.5)),
      ),
      child: Row(
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

// -----------------------------------------------------------------------------
// Timeline: the base's notes and the remix chart over its sections
// -----------------------------------------------------------------------------

class _TimelineCard extends StatelessWidget {
  const _TimelineCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final play = context.watch<SpartaPlayback>();
    final t = c.transcription!;
    final mix = c.mix;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Expanded(child: SectionLabel('THE BASE AND YOUR REMIX')),
              Text(
                'Drag a section edge to move it · click to seek',
                style: TextStyle(fontSize: 11, color: AppColors.faint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Timeline(
            transcription: t,
            chart: mix == null ? c.chart : null,
            events: mix?.events,
            durationBeats: math.max(t.lengthBeats, mix == null ? 0 : mix.duration * t.bpm / 60),
            positionBeats: mix != null && play.auditioning == null ? play.position * t.bpm / 60 : null,
            onSeek: mix != null && play.available ? (beat) => play.seek(beat * 60 / t.bpm) : null,
            onMoveBoundary: c.busy ? null : c.moveSectionBoundary,
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatefulWidget {
  const _Timeline({
    required this.transcription,
    required this.durationBeats,
    this.chart,
    this.events,
    this.positionBeats,
    this.onSeek,
    this.onMoveBoundary,
  });
  final BaseTranscription transcription;
  final List<ChartNote>? chart;
  final List<PlacedEvent>? events;
  final double durationBeats;
  final double? positionBeats;
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

  double _beatAt(double x, double width) => (x / width).clamp(0.0, 1.0) * widget.durationBeats;

  int? _boundaryAt(Offset o, double width) {
    if (widget.onMoveBoundary == null || o.dy > _strip) return null;
    final s = widget.transcription.sections;
    for (var i = 0; i + 1 < s.length; i++) {
      final x = s[i].endBeat / widget.durationBeats * width;
      if ((o.dx - x).abs() <= _grab) return i;
    }
    return null;
  }

  double _snap(double beat) {
    final bpb = widget.transcription.beatsPerBar;
    return (beat / bpb).round() * bpb.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        void seek(Offset o) => widget.onSeek?.call(_beatAt(o.dx, w));
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
              size: Size(w, _TimelinePainter.height),
              painter: _TimelinePainter(
                t: widget.transcription,
                chart: widget.chart,
                events: widget.events,
                durationBeats: widget.durationBeats,
                position: widget.positionBeats,
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
  _TimelinePainter({
    required this.t,
    required this.durationBeats,
    this.chart,
    this.events,
    this.position,
    this.dragBeat,
  });
  final BaseTranscription t;
  final List<ChartNote>? chart;
  final List<PlacedEvent>? events;
  final double durationBeats;
  final double? position;
  final double? dragBeat;

  static const _hitsH = 44.0, _lane = 11.0;
  static const _baseLanes = [SampleRole.kick, SampleRole.snare, SampleRole.hat];
  static const _remixLanes = [
    SampleRole.quote,
    SampleRole.word,
    SampleRole.pitch,
    SampleRole.bass,
    SampleRole.pad,
    SampleRole.kick,
    SampleRole.snare,
    SampleRole.hat,
  ];
  static const height = 24 + 14 + _hitsH + 3 * _lane + 18 + 8 * _lane + 4;

  @override
  void paint(Canvas canvas, Size size) {
    final dur = math.max(1.0, durationBeats);
    double x(double beat) => beat / dur * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = AppColors.bg,
    );

    // Sections.
    for (final s in t.sections) {
      final a = x(s.startBeat), b = x(s.endBeat);
      final color = sectionColor(s.kind);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(a + 1, 2, b - 1, 20), const Radius.circular(4)),
        Paint()..color = color.withValues(alpha: 0.35),
      );
      canvas.drawRect(Rect.fromLTRB(a, 22, a + 1, size.height), Paint()..color = color.withValues(alpha: 0.3));
      if (b - a > 40) _text(canvas, s.title, Offset(a + 5, 5), b - a - 8, bold: true);
    }

    // The base: its hits as a mini piano roll, and its drums.
    var y = 24.0;
    _text(canvas, 'BASE', Offset(4, y), 80, color: AppColors.faint);
    y += 14;
    if (t.hits.isNotEmpty) {
      final lo = t.hits.map((h) => h.semitone).reduce(math.min), hi = t.hits.map((h) => h.semitone).reduce(math.max);
      final span = math.max(1, hi - lo);
      final paint = Paint()..color = laneColor(SampleRole.pitch).withValues(alpha: 0.85);
      for (final h in t.hits) {
        final yy = y + (_hitsH - 4) * (1 - (h.semitone - lo) / span);
        canvas.drawRect(Rect.fromLTWH(x(h.beat), yy, math.max(1.2, x(h.end) - x(h.beat)), 3), paint);
      }
    }
    y += _hitsH;
    for (final role in _baseLanes) {
      final paint = Paint()..color = laneColor(role).withValues(alpha: 0.75);
      for (final b in t.drums(role)) {
        canvas.drawRect(Rect.fromLTWH(x(b), y + 2, 1.5, _lane - 4), paint);
      }
      y += _lane;
    }

    // The remix chart (or, once mixed, what plays).
    y += 4;
    _text(canvas, events == null ? 'REMIX CHART' : 'REMIX', Offset(4, y), 120, color: AppColors.faint);
    y += 14;
    for (final role in _remixLanes) {
      canvas.drawRect(
        Rect.fromLTWH(0, y + _lane / 2, size.width, 1),
        Paint()..color = AppColors.border.withValues(alpha: 0.4),
      );
      final paint = Paint()..color = laneColor(role).withValues(alpha: 0.9);
      final ev = events;
      if (ev != null) {
        for (final e in ev) {
          if (e.role != role) continue;
          final a = x(e.beat), w = math.max(1.5, x(e.beat + e.duration * t.bpm / 60) - a);
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(a, y + 1, w, _lane - 2), const Radius.circular(2)),
            paint,
          );
        }
      } else {
        for (final n in chart ?? const <ChartNote>[]) {
          if (n.role != role) continue;
          final a = x(n.beat), w = math.max(1.5, x(n.end) - a);
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(a, y + 1, w, _lane - 2), const Radius.circular(2)),
            paint,
          );
        }
      }
      y += _lane;
    }

    final drag = dragBeat;
    if (drag != null) {
      canvas.drawRect(Rect.fromLTWH(x(drag) - 1.5, 0, 3, size.height), Paint()..color = AppColors.sparta);
    }
    final pos = position;
    if (pos != null) {
      canvas.drawRect(
        Rect.fromLTWH(x(pos.clamp(0, dur).toDouble()) - 1, 0, 2, size.height),
        Paint()..color = Colors.white,
      );
    }
  }

  void _text(Canvas canvas, String s, Offset at, double maxWidth, {bool bold = false, Color color = AppColors.text}) {
    if (maxWidth <= 4) return;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: 10.5, color: color, fontWeight: bold ? FontWeight.w600 : FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.position != position ||
      old.t != t ||
      old.chart != chart ||
      old.events != events ||
      old.dragBeat != dragBeat ||
      old.durationBeats != durationBeats;
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
        const _WordsCard(),
        for (final role in const [
          SampleRole.pitch,
          SampleRole.bass,
          SampleRole.pad,
          SampleRole.kick,
          SampleRole.snare,
          SampleRole.hat,
        ])
          if (c.picks[role] != null) _SampleCard(pick: c.picks[role]!),
      ],
    );
  }
}

/// The line's words as they play (with Chorus Crisp etc.).
class _WordsCard extends StatelessWidget {
  const _WordsCard();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SpartaController>();
    final play = context.watch<SpartaPlayback>();
    final words = c.processed[SampleRole.word] ?? const [];
    final color = laneColor(SampleRole.word);
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
              Icon(laneIcon(SampleRole.word), size: 16, color: color),
              const SizedBox(width: 6),
              const Text('Chorus words & quote', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(onPressed: () => c.goTo(SpartaStep.line), child: const Text('Edit line')),
            ],
          ),
          Text(SampleRole.word.blurb, style: const TextStyle(fontSize: 11.5, color: AppColors.faint)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < words.length; i++)
                ActionChip(
                  avatar: Icon(
                    play.auditioning == 'w${words[i].slot}' && play.playing ? Icons.stop : Icons.play_arrow,
                    size: 15,
                    color: color,
                  ),
                  label: Text(words[i].slot, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  onPressed: !play.available
                      ? null
                      : () async {
                          final path = await c.auditionPath(SampleRole.word, which: i);
                          if (path != null) await play.audition(path, 'w${words[i].slot}');
                        },
                ),
              if (c.processed[SampleRole.quote] != null)
                ActionChip(
                  avatar: Icon(Icons.format_quote, size: 15, color: laneColor(SampleRole.quote)),
                  label: const Text('Quote', style: TextStyle(fontSize: 12)),
                  onPressed: !play.available
                      ? null
                      : () async {
                          final path = await c.auditionPath(SampleRole.quote);
                          if (path != null) await play.audition(path, 'quote');
                        },
                ),
            ],
          ),
        ],
      ),
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
                Pill('→ ${_noteOfHz(tuned)}', color: color, tooltip: 'Tuned to ${tuned.toStringAsFixed(1)} Hz'),
              const Spacer(),
              Pill('${(cand.score * 100).round()}%', tooltip: 'How well it fits this lane'),
              Tooltip(
                message: c.muted.contains(role) ? 'Off: switch the ${role.label.toLowerCase()} on' : 'Playing',
                child: Transform.scale(
                  scale: 0.72,
                  child: Switch(value: !c.muted.contains(role), onChanged: (on) => c.setLaneOn(role, on)),
                ),
              ),
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
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  side: BorderSide(color: color.withValues(alpha: 0.6)),
                  foregroundColor: color,
                ),
                onPressed: !play.available || processed == null
                    ? null
                    : () => play.auditioning == '${role.name}0' && play.playing ? play.stop() : audition(0),
                icon: Icon(
                  play.auditioning == '${role.name}0' && play.playing ? Icons.stop : Icons.play_arrow,
                  size: 16,
                ),
                label: const Text('Play', style: TextStyle(fontSize: 12)),
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
                    message: 'Alternate this lane between two samples, section by section',
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
    return keyName(midi);
  }
}
