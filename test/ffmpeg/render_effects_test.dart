@Tags(['ffmpeg'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:video_effects_studio/core/effects/custom_effect.dart';
import 'package:video_effects_studio/core/effects/effect.dart';
import 'package:video_effects_studio/core/effects/registry.dart';
import 'package:video_effects_studio/core/ffmpeg/command_builder.dart';
import 'package:video_effects_studio/core/ffmpeg/ffmpeg_toolkit.dart';
import 'package:video_effects_studio/core/ffmpeg/media_info.dart';
import 'package:video_effects_studio/core/models/output_settings.dart';
import 'package:video_effects_studio/core/render/render_engine.dart';

/// Renders every built-in effect with a real FFmpeg and checks the output.
///
/// Uses the ffmpeg from `VFX_FFMPEG` or PATH; skipped when none is found.
void main() {
  FfmpegToolkit? kit;
  late RenderEngine engine;
  late Directory tmp;
  late MediaInfo withAudio;
  late MediaInfo oddNoAudio;

  setUpAll(() async {
    kit = await FfmpegToolkit.locate();
    if (kit == null) return;
    engine = RenderEngine(kit!);
    tmp = await Directory.systemTemp.createTemp('vfx_test_');

    Future<void> make(List<String> args) async {
      final r = await Process.run(kit!.ffmpegPath, ['-hide_banner', '-loglevel', 'error', '-y', ...args]);
      if (r.exitCode != 0) throw StateError('fixture failed: ${r.stderr}');
    }

    final a = p.join(tmp.path, 'src.mp4');
    await make([
      '-f', 'lavfi', '-i', 'testsrc2=s=320x240:r=25:d=1.6', //
      '-f', 'lavfi', '-i', 'sine=f=220:r=44100:d=1.6',
      '-ac', '2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', a,
    ]);
    final b = p.join(tmp.path, 'odd.mp4');
    await make([
      '-f', 'lavfi', '-i', 'testsrc2=s=321x241:r=24:d=1.2', //
      '-c:v', 'libx264', '-pix_fmt', 'yuv444p', b,
    ]);
    withAudio = await engine.probe(a);
    oddNoAudio = await engine.probe(b);
  });

  tearDownAll(() async {
    if (kit != null) await tmp.delete(recursive: true);
  });

  Future<MediaInfo> renderAndProbe(
    Effect effect,
    MediaInfo media, {
    OutputSettings output = const OutputSettings(quality: OutputQuality.small),
    ParamValues? params,
  }) async {
    final out = p.join(tmp.path, 'out_${effect.id}_${media.fileName}.${output.format.extension}');
    await engine.render(
      RenderRequest(media: media, effect: effect, params: params ?? effect.defaults(), outputPath: out, output: output),
    );
    return engine.probe(out);
  }

  void expectDuration(MediaInfo info, double expected) {
    final tolerance = 0.3 + expected * 0.06;
    expect(info.duration, closeTo(expected, tolerance), reason: 'duration of ${info.fileName}');
  }

  group('every built-in effect renders', () {
    for (final effect in EffectRegistry.builtIn) {
      test(effect.id, () async {
        if (kit == null) return markTestSkipped('ffmpeg not found');
        for (final media in [withAudio, oddNoAudio]) {
          final info = await renderAndProbe(effect, media);
          expect(info.hasVideo, isTrue, reason: '${effect.id} video on ${media.fileName}');
          expect(info.hasAudio, isTrue, reason: '${effect.id} audio on ${media.fileName}');
          expect(info.width.isEven && info.height.isEven, isTrue);
          expectDuration(info, effect.outputSecondsFor(effect.defaults(), media.duration));
        }
      });
    }
  });

  test('custom effect chain renders', () async {
    if (kit == null) return markTestSkipped('ffmpeg not found');
    final custom = const CustomEffectDef(
      id: 'custom_x',
      name: 'Mine',
      videoChain: 'negate,\n hue=h=90',
      audioChain: 'atempo=2',
      lengthFactor: 1.0,
    ).toEffect();
    final info = await renderAndProbe(custom, withAudio);
    expect(info.hasVideo && info.hasAudio, isTrue);
  });

  group('output formats', () {
    final effect = EffectRegistry.builtIn.firstWhere((e) => e.id == 'g_major_4');
    for (final format in OutputFormat.values) {
      test(format.name, () async {
        if (kit == null) return markTestSkipped('ffmpeg not found');
        final info = await renderAndProbe(
          effect,
          withAudio,
          output: OutputSettings(format: format, quality: OutputQuality.small, resolution: ResolutionCap.p360),
        );
        expect(info.hasVideo, format.hasVideo);
        expect(info.hasAudio, format.hasAudio);
      });
    }
  });

  group('compilation', () {
    final picks = ['g_major_4', 'low_voice', 'boomerang', 'sparta_sequencer'];
    for (final mode in LabelMode.values) {
      test('label mode ${mode.name}', () async {
        if (kit == null) return markTestSkipped('ffmpeg not found');
        final entries = [
          for (final id in picks)
            CompilationEntry(
              EffectRegistry.builtIn.firstWhere((e) => e.id == id),
              EffectRegistry.builtIn.firstWhere((e) => e.id == id).defaults(),
            ),
        ];
        final out = p.join(tmp.path, 'comp_${mode.name}.mp4');
        final fractions = <double>[];
        final result = await engine.renderCompilation(
          CompilationRequest(
            media: withAudio,
            entries: entries,
            outputPath: out,
            labelMode: mode,
            fontPath: p.join(Directory.current.path, 'assets', 'fonts', 'Inter-ExtraBold.ttf'),
            originalFirst: true,
            output: const OutputSettings(quality: OutputQuality.small),
          ),
          onProgress: (f, _) => fractions.add(f),
        );
        expect(result.failures, isEmpty);
        final info = await engine.probe(out);
        var expected = withAudio.duration; // original first
        for (final e in entries) {
          expected += e.effect.outputSecondsFor(e.params, withAudio.duration);
        }
        if (mode == LabelMode.titleCard && kit!.hasDrawtext) expected += 1.2 * (entries.length + 1);
        expectDuration(info, expected);
        expect(fractions.last, 1.0);
      });
    }

    test('failed segments are skipped and reported', () async {
      if (kit == null) return markTestSkipped('ffmpeg not found');
      final broken = const CustomEffectDef(
        id: 'broken',
        name: 'Broken',
        videoChain: 'definitely_not_a_filter',
      ).toEffect();
      final ok = EffectRegistry.builtIn.firstWhere((e) => e.id == 'invert_color');
      final out = p.join(tmp.path, 'comp_broken.mp4');
      final result = await engine.renderCompilation(
        CompilationRequest(
          media: withAudio,
          entries: [CompilationEntry(broken, const {}), CompilationEntry(ok, const {})],
          outputPath: out,
          labelMode: LabelMode.none,
          originalFirst: false,
        ),
      );
      expect(result.failures.map((f) => f.effectName), ['Broken']);
      expectDuration(await engine.probe(out), withAudio.duration);
    });
  });

  test('preview and thumbnail', () async {
    if (kit == null) return markTestSkipped('ffmpeg not found');
    final effect = EffectRegistry.builtIn.firstWhere((e) => e.id == 'swirl');
    final cache = p.join(tmp.path, 'cache');
    final preview = await engine.preview(
      media: withAudio,
      effect: effect,
      params: effect.defaults(),
      start: 0.2,
      seconds: 1,
      cacheDir: cache,
    );
    expectDuration(await engine.probe(preview), 1);
    final thumb = await engine.thumbnail(
      media: withAudio,
      effect: effect,
      params: effect.defaults(),
      atSeconds: 0.5,
      cacheDir: cache,
    );
    expect(thumb, isNotNull);
    expect(File(thumb!).lengthSync(), greaterThan(500));
  });
}
