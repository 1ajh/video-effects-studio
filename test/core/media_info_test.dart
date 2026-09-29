import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/ffmpeg/ffmpeg_runner.dart';
import 'package:video_effects_studio/core/ffmpeg/media_info.dart';

void main() {
  test('parses ffprobe JSON with a rotated phone video', () {
    const json = '''
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080,
     "avg_frame_rate": "30000/1001", "side_data_list": [{"side_data_type": "Display Matrix", "rotation": -90}]},
    {"codec_type": "audio", "codec_name": "aac", "sample_rate": "44100"}
  ],
  "format": {"duration": "12.345000"}
}''';
    final info = MediaInfo.fromProbeJson('/v.mp4', json);
    expect(info.width, 1080);
    expect(info.height, 1920);
    expect(info.fps, closeTo(29.97, 0.01));
    expect(info.duration, closeTo(12.345, 1e-6));
    expect(info.hasAudio, isTrue);
    expect(info.sampleRate, 44100);
  });

  test('ignores cover art when looking for video', () {
    const json = '''
{"streams": [
  {"codec_type": "audio", "codec_name": "mp3", "sample_rate": "48000"},
  {"codec_type": "video", "codec_name": "mjpeg", "width": 500, "height": 500, "disposition": {"attached_pic": 1}}
], "format": {"duration": "3.0"}}''';
    final info = MediaInfo.fromProbeJson('/a.mp3', json);
    expect(info.hasVideo, isFalse);
    expect(info.hasAudio, isTrue);
  });

  test('falls back to the ffmpeg banner', () {
    const banner = '''
Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'x.mp4':
  Duration: 00:01:02.50, start: 0.000000, bitrate: 1200 kb/s
  Stream #0:0[0x1](und): Video: h264 (High) (avc1 / 0x31637661), yuv420p(progressive), 640x360 [SAR 1:1 DAR 16:9], 1000 kb/s, 25 fps, 25 tbr, 12800 tbn (default)
  Stream #0:1[0x2](und): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 128 kb/s (default)
''';
    final info = MediaInfo.fromFfmpegBanner('/x.mp4', banner);
    expect(info.duration, closeTo(62.5, 1e-9));
    expect(info.width, 640);
    expect(info.height, 360);
    expect(info.fps, 25);
    expect(info.hasAudio, isTrue);
    expect(info.sampleRate, 48000);
    expect(info.videoCodec, 'h264');
  });

  test('error summaries pick the useful line', () {
    final msg = FfmpegRunner.summarizeError([
      'something harmless',
      '[AVFilterGraph @ 0x1] No such filter: \'definitely_not_a_filter\'',
      'Error : Filter not found',
    ], 8);
    expect(msg, "No such filter: 'definitely_not_a_filter'");
    expect(FfmpegRunner.summarizeError([], 3), 'FFmpeg exited with code 3');
  });
}
