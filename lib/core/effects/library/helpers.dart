import '../../ffmpeg/blocks.dart';
import '../../ffmpeg/filter_graph.dart';
import '../effect.dart';

/// A plain video filter chain.
StreamBuilder vf(String chain) =>
    (g, input, p, env) => g.v(input, chain);

/// A plain audio filter chain.
StreamBuilder af(String chain) =>
    (g, input, p, env) => g.a(input, chain);

/// Pitched duplicate tracks mixed together (optionally wrapped in extra
/// chains before/after).
StreamBuilder chordFx(
  List<num> semitones, {
  double gain = 1,
  String pre = '',
  String post = '',
  String perVoice = '',
}) => (g, input, p, env) {
  var x = pre.isEmpty ? input : g.a(input, pre);
  x = chord(g, x, semitones, sampleRate: env.sampleRate, gain: gain, perVoice: perVoice);
  return post.isEmpty ? x : g.a(x, post);
};

/// Runs several builders in sequence.
StreamBuilder seq(List<StreamBuilder> steps) => (g, input, p, env) {
  var x = input;
  for (final s in steps) {
    x = s(g, x, p, env);
  }
  return x;
};

StreamBuilder mirrorFx(MirrorSide side) =>
    (g, input, p, env) => mirror(g, input, side);

StreamBuilder kaleidoscopeFx() =>
    (g, input, p, env) => kaleidoscope(g, input);

StreamBuilder raysFx({bool intense = false}) =>
    (g, input, p, env) => lightRays(g, input, intense: intense);

/// Full reversal of video (buffers the clip in memory).
final StreamBuilder reverseVideo = vf('reverse');

/// Full reversal of audio (buffers the clip in memory).
final StreamBuilder reverseAudio = af('areverse');

/// Plays the stream [times] times back to back.
String repeatStream(FilterGraph g, String input, int times, {required bool audio}) {
  if (times <= 1) return input;
  final copies = g.split(input, times, audio: audio);
  return g.join(copies, 'concat=n=$times:v=${audio ? 0 : 1}:a=${audio ? 1 : 0}');
}

/// Seconds -> sample count at [rate].
int samples(double seconds, int rate) => (seconds * rate).round();
