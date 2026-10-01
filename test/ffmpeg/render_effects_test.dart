@Tags(['ffmpeg'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/audio/dsp.dart';
import 'package:video_effects_studio/core/audio/psola.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
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

  test('the Sparta Sequencer plays the chorus pitch in time', () async {
    if (kit == null) return markTestSkipped('ffmpeg not found');
    final effect = EffectRegistry.builtIn.firstWhere((e) => e.id == 'sparta_sequencer');
    final out = p.join(tmp.path, 'sequencer.wav');
    final params = {...effect.defaults(), 'sample': 0.3, 'repeats': 1};
    await engine.render(
      RenderRequest(
        media: withAudio,
        effect: effect,
        params: params,
        outputPath: out,
        output: const OutputSettings(format: OutputFormat.wav),
      ),
    );
    final a = AudioBuffer.fromWav(File(out).readAsBytesSync()).mono();
    // Two bars of quarter notes at 140 BPM.
    expect(a.duration, closeTo(8 * 60 / 140, 0.05));
    final semis = <int>[];
    for (var i = 0; i < 8; i++) {
      final at = ((i * 60 / 140 + 0.08) * a.sampleRate).round();
      final track = trackPitch(a.data.sublist(at, at + (0.15 * a.sampleRate).round()), a.sampleRate)!;
      semis.add((12 * math.log(track.medianHz / 220) / math.ln2).round());
    }
    expect(semis, [0, 0, 1, 1, -2, -2, 1, 1]);

    // A typed pattern with a rest.
    final custom = p.join(tmp.path, 'sequencer_custom.wav');
    await engine.render(
      RenderRequest(
        media: withAudio,
        effect: effect,
        params: {...params, 'pattern': 'Custom (type it below)', 'custom': '0*** 7*** ______ 12*'},
        outputPath: custom,
        output: const OutputSettings(format: OutputFormat.wav, loudness: LoudnessTarget.off),
      ),
    );
    final c = AudioBuffer.fromWav(File(custom).readAsBytesSync()).mono();
    expect(c.duration, closeTo(16 * 15 / 140, 0.05), reason: 'one bar');
    final restAt = ((10 * 15 / 140) * c.sampleRate).round();
    expect(c.slice(restAt / c.sampleRate, (restAt / c.sampleRate) + 0.2).rms(), lessThan(0.001));
  });

  test('level matching makes quiet effects loud and leaves loud ones alone', () async {
    if (kit == null) return markTestSkipped('ffmpeg not found');
    final speech = p.join(tmp.path, 'speech.mp4');
    final r = await Process.run(kit!.ffmpegPath, [
      '-hide_banner', '-loglevel', 'error', '-y', //
      '-f', 'lavfi', '-i', 'testsrc2=s=320x240:r=25',
      '-i', 'test/fixtures/speech_a.wav', '-shortest',
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', speech,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final media = await engine.probe(speech);
    Future<double> lufsOf(String id, LoudnessTarget target) async {
      final effect = EffectRegistry.builtIn.firstWhere((e) => e.id == id);
      final out = p.join(tmp.path, 'level_${id}_${target.name}.wav');
      await engine.render(
        RenderRequest(
          media: media,
          effect: effect,
          params: effect.defaults(),
          outputPath: out,
          output: OutputSettings(format: OutputFormat.wav, loudness: target),
        ),
      );
      final a = AudioBuffer.fromWav(File(out).readAsBytesSync());
      if (target != LoudnessTarget.off && id != 'earrape') {
        expect(gainToDb(a.peak()), lessThanOrEqualTo(-0.9), reason: '$id peak');
      }
      return loudness(a.data, a.sampleRate, channels: a.channels);
    }

    // A vocoder that comes out ~13 dB quieter than the voice on its own.
    expect(await lufsOf('daft_vocoder', LoudnessTarget.off), lessThan(-30));
    expect(await lufsOf('daft_vocoder', LoudnessTarget.loud), closeTo(-9, 1.5));
    expect(await lufsOf('daft_vocoder', LoudnessTarget.standard), closeTo(-14, 1.5));
    expect(await lufsOf('pitch_shift', LoudnessTarget.loud), closeTo(-9, 1.5));
    // Earrape is louder than the target on purpose: it isn't turned down.
    expect(await lufsOf('earrape', LoudnessTarget.loud), greaterThan(-7));
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
