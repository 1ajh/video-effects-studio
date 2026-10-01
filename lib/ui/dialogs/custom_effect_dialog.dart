import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/effects/custom_effect.dart';
import '../../core/ffmpeg/command_builder.dart';
import '../../core/ffmpeg/ffmpeg_runner.dart';
import '../../state/editor_controller.dart';
import '../../state/engine_controller.dart';
import '../../state/library_controller.dart';
import '../../state/project_controller.dart';
import '../platform_actions.dart';
import '../theme.dart';

Future<void> showCustomEffectDialog(BuildContext context, {CustomEffectDef? existing}) {
  return showDialog(
    context: context,
    builder: (_) => _CustomEffectDialog(existing: existing),
  );
}

const _examples = <(String, String, String)>[
  ('Invert + hue', 'negate,hue=h=90', ''),
  ('Chipmunk', '', 'asetrate=48000*1.5,aresample=48000,atempo=0.6667'),
  ('Blur + shake', "gblur=sigma=6,crop=iw-20:ih-20:'10+10*sin(t*40)':'10+10*cos(t*33)'", ''),
  ('Echo cave', '', 'aecho=0.8:0.9:500|1000:0.4|0.3'),
  ('Rainbow edges', 'edgedetect=mode=colormix,hue=h=t*120', ''),
];

class _CustomEffectDialog extends StatefulWidget {
  const _CustomEffectDialog({this.existing});
  final CustomEffectDef? existing;

  @override
  State<_CustomEffectDialog> createState() => _CustomEffectDialogState();
}

class _CustomEffectDialogState extends State<_CustomEffectDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _desc = TextEditingController(text: widget.existing?.description ?? '');
  late final _video = TextEditingController(text: widget.existing?.videoChain ?? '');
  late final _audio = TextEditingController(text: widget.existing?.audioChain ?? '');
  late double _length = widget.existing?.lengthFactor ?? 1.0;

  bool _testing = false;
  String? _testError;
  bool _testOk = false;

  @override
  void dispose() {
    for (final c in [_name, _desc, _video, _audio]) {
      c.dispose();
    }
    super.dispose();
  }

  CustomEffectDef _build() => CustomEffectDef(
    id: widget.existing?.id ?? CustomEffectDef.newId(),
    name: _name.text.trim(),
    description: _desc.text.trim(),
    videoChain: _video.text,
    audioChain: _audio.text,
    lengthFactor: _length,
  );

  /// Renders half a second through the chains to validate them.
  Future<void> _test() async {
    final engine = context.read<EngineController>().engine;
    final activeMedia = context.read<ProjectController>().active?.info;
    if (engine == null) return;
    setState(() {
      _testing = true;
      _testError = null;
      _testOk = false;
    });
    final tmp = await Directory.systemTemp.createTemp('vfx_custom_');
    try {
      var media = activeMedia;
      if (media == null) {
        final src = p.join(tmp.path, 'src.mp4');
        final r = await Process.run(engine.toolkit.ffmpegPath, [
          '-hide_banner', '-loglevel', 'error', '-y', //
          '-f', 'lavfi', '-i', 'testsrc2=s=320x240:r=25:d=1',
          '-f', 'lavfi', '-i', 'sine=f=330:r=48000:d=1',
          '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', src,
        ]);
        if (r.exitCode != 0) throw FfmpegException('${r.stderr}');
        media = await engine.probe(src);
      }
      await engine.render(
        RenderRequest(
          media: media,
          effect: _build().toEffect(),
          params: const {},
          outputPath: p.join(tmp.path, 'out.mp4'),
          start: 0,
          end: media.duration < 0.6 ? media.duration : 0.6,
          target: EncodeTarget.preview,
        ),
      );
      if (mounted) setState(() => _testOk = true);
    } catch (e) {
      if (mounted) setState(() => _testError = '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _testError = 'Give the effect a name.');
      return;
    }
    if (_video.text.trim().isEmpty && _audio.text.trim().isEmpty) {
      setState(() => _testError = 'Add at least a video or an audio filter chain.');
      return;
    }
    final def = _build();
    final library = context.read<LibraryController>();
    library.saveCustom(def);
    final effect = library.registry.byId(def.id);
    if (effect != null) context.read<EditorController>().select(effect);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ready = context.watch<EngineController>().ready;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4);
    return AlertDialog(
      title: Text(widget.existing == null ? 'New custom effect' : 'Edit custom effect'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Write FFmpeg filter chains (comma separated). The video chain gets the clip as yuv420p; '
                'the audio chain gets 48 kHz stereo. Output is normalized for you.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _desc,
                      decoration: const InputDecoration(labelText: 'Description (optional)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _video,
                minLines: 2,
                maxLines: 5,
                style: mono,
                decoration: const InputDecoration(
                  labelText: 'Video filters',
                  hintText: 'e.g. negate,hue=h=90,vflip',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _audio,
                minLines: 2,
                maxLines: 5,
                style: mono,
                decoration: const InputDecoration(
                  labelText: 'Audio filters',
                  hintText: 'e.g. aecho=0.8:0.9:500:0.3,volume=2',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Output length', style: TextStyle(fontSize: 12.5)),
                  Expanded(
                    child: Slider(
                      value: _length,
                      min: 0.25,
                      max: 4,
                      divisions: 75,
                      onChanged: (v) => setState(() => _length = v),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text('${_length.toStringAsFixed(2)}×', style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
              const Text(
                'Set this if your chain changes speed (e.g. 0.5× for atempo=2) so compilations line up.',
                style: TextStyle(fontSize: 11, color: AppColors.faint),
              ),
              const SizedBox(height: 12),
              const Text(
                'Examples',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.muted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (label, v, a) in _examples)
                    ActionChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() {
                        _video.text = v;
                        _audio.text = a;
                        if (_name.text.isEmpty) _name.text = label;
                      }),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.menu_book_outlined, size: 14),
                    label: const Text('FFmpeg filter docs', style: TextStyle(fontSize: 12)),
                    onPressed: () => openUrl('https://ffmpeg.org/ffmpeg-filters.html'),
                  ),
                ],
              ),
              if (_testError != null || _testOk) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (_testOk ? AppColors.success : AppColors.danger).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _testOk ? Icons.check_circle_outline : Icons.error_outline,
                        size: 16,
                        color: _testOk ? AppColors.success : AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          _testOk ? 'Works! FFmpeg accepted both chains.' : _testError!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _testing || !ready ? null : _test,
          icon: _testing
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.science_outlined, size: 16),
          label: const Text('Test'),
        ),
        const SizedBox(width: 12),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save effect')),
      ],
    );
  }
}
