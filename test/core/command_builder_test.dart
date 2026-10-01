import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/effects/registry.dart';
import 'package:video_effects_studio/core/ffmpeg/command_builder.dart';
import 'package:video_effects_studio/core/ffmpeg/media_info.dart';
import 'package:video_effects_studio/core/models/output_settings.dart';

MediaInfo clip({bool audio = true, int w = 1920, int h = 1080, double duration = 10}) =>
    MediaInfo(path: '/c/in.mov', duration: duration, hasVideo: true, hasAudio: audio, width: w, height: h, fps: 29.97);

void main() {
  final gMajor4 = EffectRegistry.builtIn.firstWhere((e) => e.id == 'g_major_4');
  final speed = EffectRegistry.builtIn.firstWhere((e) => e.id == 'speed');

  String argAfter(List<String> args, String flag) => args[args.indexOf(flag) + 1];

  test('trim becomes input seeking and duration', () {
    final cmd = CommandBuilder.build(
      RenderRequest(
        media: clip(),
        effect: gMajor4,
        params: gMajor4.defaults(),
        outputPath: '/o.mp4',
        start: 2,
        end: 5.5,
      ),
    );
    expect(argAfter(cmd.args, '-ss'), '2');
    expect(argAfter(cmd.args, '-t'), '3.5');
    expect(cmd.expectedSeconds, 3.5);
    expect(cmd.args.indexOf('-ss'), lessThan(cmd.args.indexOf('-i')));
  });

  test('always yuv420p, even dimensions and faststart for mp4', () {
    final cmd = CommandBuilder.build(
      RenderRequest(media: clip(w: 721, h: 405), effect: gMajor4, params: const {}, outputPath: '/o.mp4'),
    );
    expect(cmd.graph, contains('scale=720:404'));
    expect(cmd.args, containsAllInOrder(['-pix_fmt', 'yuv420p']));
    expect(cmd.args, containsAllInOrder(['-movflags', '+faststart']));
  });

  test('resolution cap keeps aspect and even sizes', () {
    expect(CommandBuilder.scaledSize(clip(), 720), (1280, 720));
    expect(CommandBuilder.scaledSize(clip(w: 1080, h: 1920), 480), (270, 480));
    expect(CommandBuilder.scaledSize(clip(w: 640, h: 360), 720), (640, 360));
  });

  test('clips without audio get generated silence and skip audio effects', () {
    final cmd = CommandBuilder.build(
      RenderRequest(media: clip(audio: false), effect: gMajor4, params: const {}, outputPath: '/o.mp4'),
    );
    expect(cmd.args.join(' '), contains('anullsrc'));
    expect(cmd.graph, isNot(contains('amix')));
    expect(cmd.graph, contains('[1:a]'));
  });

  test('speed changes expected length and uses atempo', () {
    final cmd = CommandBuilder.build(
      RenderRequest(
        media: clip(),
        effect: speed,
        params: const {'factor': 2.0, 'keepPitch': true},
        outputPath: '/o.mp4',
      ),
    );
    expect(cmd.expectedSeconds, 5);
    expect(cmd.graph, contains('setpts=PTS/2'));
    expect(cmd.graph, contains('atempo=2'));
    // Audio lands exactly on the new length.
    expect(cmd.graph, contains('atrim=duration=5'));
  });

  test('gif has a palette and no audio; audio formats drop video', () {
    final gif = CommandBuilder.build(
      RenderRequest(
        media: clip(),
        effect: gMajor4,
        params: const {},
        outputPath: '/o.gif',
        output: const OutputSettings(format: OutputFormat.gif),
      ),
    );
    expect(gif.graph, contains('palettegen'));
    expect(gif.graph, isNot(contains('aresample')));
    expect(gif.args, contains('-an'));

    final mp3 = CommandBuilder.build(
      RenderRequest(
        media: clip(),
        effect: gMajor4,
        params: const {},
        outputPath: '/o.mp3',
        output: const OutputSettings(format: OutputFormat.mp3),
      ),
    );
    expect(mp3.graph, isNot(contains('scale=')));
    expect(mp3.args, containsAllInOrder(['-c:a', 'libmp3lame']));
  });

  test('compilation segments are padded/trimmed to an exact length', () {
    final cmd = CommandBuilder.build(
      RenderRequest(
        media: clip(),
        effect: speed,
        params: const {'factor': 0.5},
        outputPath: 'seg.mkv',
        target: EncodeTarget.segment,
        segment: const SegmentFormat(
          width: 1280,
          height: 720,
          fps: 30,
          label: SegmentLabel(textFile: 'l.txt', text: '3. Speed', fontFile: 'f.ttf'),
        ),
      ),
    );
    expect(cmd.expectedSeconds, 20);
    expect(cmd.graph, contains('pad=1280:720'));
    expect(cmd.graph, contains('trim=duration=20'));
    expect(cmd.graph, contains('apad=whole_dur=20'));
    expect(cmd.graph, contains('drawtext=fontfile=f.ttf:textfile=l.txt:expansion=none'));
    expect(cmd.args, containsAllInOrder(['-c:a', 'pcm_s16le']));
    expect(cmd.args, containsAllInOrder(['-f', 'matroska']));
  });

  test('title cards size long names down', () {
    const kicker = SegmentLabel(textFile: 'k.txt', text: 'EFFECT 1 OF 3', fontFile: 'f.ttf');
    final short = CommandBuilder.titleCard(
      outputPath: 'c.mkv',
      width: 1280,
      height: 720,
      fps: 30,
      seconds: 1.2,
      kicker: kicker,
      title: const SegmentLabel(textFile: 't.txt', text: 'Luig Group', fontFile: 'f.ttf'),
    );
    final long = CommandBuilder.titleCard(
      outputPath: 'c.mkv',
      width: 1280,
      height: 720,
      fps: 30,
      seconds: 1.2,
      kicker: kicker,
      title: const SegmentLabel(textFile: 't.txt', text: 'Grey Invert + High Pitch + Reversed', fontFile: 'f.ttf'),
    );
    int bigSize(String graph) =>
        int.parse(RegExp(r'textfile=t\.txt:expansion=none:fontsize=(\d+)').firstMatch(graph)!.group(1)!);
    expect(bigSize(long.graph), lessThan(bigSize(short.graph)));
  });

  group('level matching', () {
    test('the gain brings audio to the target; loud effects are only turned up', () {
      expect(CommandBuilder.gainFor(-30, -9), 21);
      expect(CommandBuilder.gainFor(-5, -9), -4);
      expect(CommandBuilder.gainFor(-30, -9, loud: true), 21);
      expect(CommandBuilder.gainFor(-5, -9, loud: true), isNull);
      expect(CommandBuilder.gainFor(null, -9), isNull);
      expect(CommandBuilder.gainFor(-20, null), isNull);
      expect(CommandBuilder.gainFor(-80, -9), 30, reason: 'capped');
    });

    test("ebur128's summary is read; silence is ignored", () {
      const log = '''
[Parsed_ebur128_0 @ 0x1] Summary:

  Integrated loudness:
    I:         -21.4 LUFS
    Threshold: -32.0 LUFS
''';
      expect(CommandBuilder.parseLoudness(log), -21.4);
      expect(CommandBuilder.parseLoudness('    I:         -inf LUFS'), isNull);
      expect(CommandBuilder.parseLoudness('    I:         -120.7 LUFS'), isNull);
      expect(CommandBuilder.parseLoudness('nothing here'), isNull);
    });

    test('the measurement runs the effect audio alone; the gain adds a peak limiter', () {
      final vocoder = EffectRegistry.builtIn.firstWhere((e) => e.id == 'purple_vocoder');
      final r = RenderRequest(media: clip(), effect: vocoder, params: vocoder.defaults(), outputPath: '/o.mp4');
      final m = CommandBuilder.measure(r);
      expect(m.args, containsAllInOrder(['-f', 'null', '-']));
      expect(argAfter(m.args, '-filter_complex'), contains('ebur128'));
      expect(argAfter(m.args, '-filter_complex'), isNot(contains('alimiter')));
      expect(argAfter(CommandBuilder.build(r).args, '-filter_complex'), isNot(contains('alimiter')));
      final leveled = argAfter(CommandBuilder.build(r.withGain(12.5)).args, '-filter_complex');
      expect(leveled, contains('volume=12.5dB'));
      expect(leveled, contains('alimiter=limit=0.84'));
      expect(argAfter(CommandBuilder.measure(r.withGain(3)).args, '-filter_complex'), contains('volume=3dB'));
    });

    test('the volume setting is remembered with the output settings', () {
      expect(const OutputSettings().loudness, LoudnessTarget.loud);
      expect(LoudnessTarget.loud.lufs, -9);
      final back = OutputSettings.fromJson(const OutputSettings(loudness: LoudnessTarget.off).toJson());
      expect(back.loudness, LoudnessTarget.off);
      expect(OutputSettings.fromJson(const {'format': 'mp4'}).loudness, LoudnessTarget.loud);
    });
  });
}
