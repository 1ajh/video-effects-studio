import 'dart:math' as math;

import 'filter_graph.dart';

/// Reusable FFmpeg building blocks shared by the effect library.
///
/// Everything here only relies on filters that ship with every mainstream
/// FFmpeg build (no rubberband / frei0r), so effects behave the same with the
/// bundled binary and with a system FFmpeg.

/// Formats a number for use inside filter arguments (no exponent notation,
/// at most 6 decimals, trailing zeros trimmed).
String fmt(num v) {
  if (v is int) return v.toString();
  final d = v.toDouble();
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.round().toString();
  var s = d.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s == '-0' ? '0' : s;
}

/// Frequency ratio for a pitch change in semitones.
double semitoneRatio(num semitones) => math.pow(2, semitones / 12).toDouble();

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------

/// `atempo` chain for any positive factor. Each stage stays inside
/// [0.5, 2.0], which every FFmpeg version accepts.
String atempo(double factor) {
  if (factor <= 0 || factor.isNaN) throw ArgumentError.value(factor, 'factor');
  if ((factor - 1).abs() < 1e-6) return 'anull';
  final stages = <String>[];
  var f = factor;
  while (f > 2.0) {
    stages.add('atempo=2');
    f /= 2.0;
  }
  while (f < 0.5) {
    stages.add('atempo=0.5');
    f /= 0.5;
  }
  if ((f - 1).abs() > 1e-6) stages.add('atempo=${fmt(f)}');
  return stages.isEmpty ? 'anull' : stages.join(',');
}

/// Pitch shift that keeps the duration (like Vegas' "Pitch Shift" plugin).
///
/// The trailing `asetnsamples` re-chunks atempo's uneven output frames;
/// without it FFmpeg 6.x can deadlock when several pitched copies meet in
/// `amix`.
String pitch(num semitones, {int sampleRate = 48000}) {
  if (semitones == 0) return 'anull';
  final rate = (sampleRate * semitoneRatio(semitones)).round();
  final actual = rate / sampleRate;
  return 'asetrate=$rate,aresample=$sampleRate,${atempo(1 / actual)},asetnsamples=n=1024:p=0';
}

/// Tape-style speed change: pitch and tempo move together
/// (Vegas "playback rate" without pitch lock). Pair with [setpts].
String tapeSpeed(double factor, {int sampleRate = 48000}) {
  if ((factor - 1).abs() < 1e-6) return 'anull';
  final rate = (sampleRate * factor).round();
  return 'asetrate=$rate,aresample=$sampleRate';
}

/// Video speed change matching [atempo]/[tapeSpeed].
String setpts(double factor) => (factor - 1).abs() < 1e-6 ? 'null' : 'setpts=PTS/${fmt(factor)}';

/// Duplicates the audio into one track per semitone value, pitches each and
/// sums them without normalization — the classic "duplicate the audio into
/// N tracks" logo-editing move. Loud by design.
String chord(
  FilterGraph g,
  String input,
  List<num> semitones, {
  int sampleRate = 48000,
  double gain = 1.0,
  String perVoice = '',
}) {
  if (semitones.isEmpty) return input;
  String voice(String inLabel, num s) {
    final chain = [
      pitch(s, sampleRate: sampleRate),
      if (perVoice.isNotEmpty) perVoice,
    ].where((c) => c != 'anull').join(',');
    return g.a(inLabel, chain);
  }

  final tail = (gain - 1).abs() > 1e-6 ? ',volume=${fmt(gain)}' : '';
  if (semitones.length == 1) {
    final out = voice(input, semitones.first);
    return tail.isEmpty ? out : g.a(out, tail.substring(1));
  }
  final branches = g.split(input, semitones.length, audio: true);
  final voices = [for (var i = 0; i < semitones.length; i++) voice(branches[i], semitones[i])];
  return g.join(voices, 'amix=inputs=${voices.length}:duration=first:dropout_transition=0:normalize=0$tail');
}

/// Parses "0, 4, 7" / "-12 -5 0" style pitch lists.
List<double> parsePitchList(String text, {int maxItems = 16}) {
  final values = text
      .split(RegExp(r'[\s,;|]+'))
      .where((s) => s.trim().isNotEmpty)
      .map((s) => double.tryParse(s.trim().replaceAll('+', '')))
      .whereType<double>()
      .map((v) => v.clamp(-48.0, 48.0))
      .take(maxItems)
      .toList();
  return values;
}

/// Robotization: zeroes every FFT bin phase, turning the voice into a
/// monotone buzz whose pitch is set by the window hop size.
String robot({int winSize = 1024, double overlap = 0.75}) =>
    "afftfilt=real='hypot(re,im)*sin(0)':imag='hypot(re,im)*cos(0)':win_size=$winSize:overlap=${fmt(overlap)}";

/// Whisperization: randomized phases.
String whisper({int winSize = 256}) =>
    "afftfilt=real='hypot(re,im)*cos((random(0)*2-1)*2*3.14)':imag='hypot(re,im)*sin((random(1)*2-1)*2*3.14)':win_size=$winSize:overlap=0.8";

/// Hard, crunchy distortion (Vegas ExpressFX "[Sys] Mangle"-ish).
String mangle({double driveDb = 18, int bits = 8}) =>
    'volume=${fmt(driveDb)}dB,acrusher=bits=$bits:mode=log:aa=0.5:mix=0.6,asoftclip=type=hard';

/// Extreme chorus (ExpressFX Chorus "[Sys] Wacky").
const wackyChorus = 'chorus=0.6:0.9:55|40|25:0.6|0.5|0.4:0.3|0.9|1.8:6|4|8';

/// Mild chorus / doubling.
const softChorus = 'chorus=0.5:0.9:50|60|40:0.4|0.32|0.3:0.25|0.4|0.3:2|2.3|1.3';

/// Small-room-ish reverb built from multi-tap echoes.
String reverb({double wet = 0.5}) =>
    'aecho=0.8:${fmt(0.4 + wet * 0.5)}:43|79|131|191|263:${fmt(0.5 * wet)}|${fmt(0.42 * wet)}|${fmt(0.35 * wet)}|${fmt(0.28 * wet)}|${fmt(0.2 * wet)}';

/// Ring modulation against a sine carrier.
String ringMod(FilterGraph g, String input, double hz, {required double seconds, int sampleRate = 48000}) {
  final carrier = g.source(
    "aevalsrc='sin(2*PI*${fmt(hz)}*t)|sin(2*PI*${fmt(hz)}*t)':s=$sampleRate:d=${fmt(seconds + 1)}",
  );
  final x = g.a(input, 'aformat=sample_fmts=fltp:channel_layouts=stereo');
  final c = g.a(carrier, 'aformat=sample_fmts=fltp:channel_layouts=stereo');
  return g.join([x, c], 'amultiply');
}

// ---------------------------------------------------------------------------
// Video
// ---------------------------------------------------------------------------

enum MirrorSide { left, right, top, bottom }

/// Vegas "Mirror" presets: Reflect Left keeps the left half and mirrors it
/// onto the right half, etc.
String mirror(FilterGraph g, String input, MirrorSide side) {
  switch (side) {
    case MirrorSide.left:
      final half = g.v(input, 'crop=trunc(iw/4)*2:ih:0:0');
      final s = g.split(half, 2);
      final f = g.v(s[1], 'hflip');
      return g.join([s[0], f], 'hstack=inputs=2');
    case MirrorSide.right:
      final half = g.v(input, 'crop=trunc(iw/4)*2:ih:iw-trunc(iw/4)*2:0');
      final s = g.split(half, 2);
      final f = g.v(s[0], 'hflip');
      return g.join([f, s[1]], 'hstack=inputs=2');
    case MirrorSide.top:
      final half = g.v(input, 'crop=iw:trunc(ih/4)*2:0:0');
      final s = g.split(half, 2);
      final f = g.v(s[1], 'vflip');
      return g.join([s[0], f], 'vstack=inputs=2');
    case MirrorSide.bottom:
      final half = g.v(input, 'crop=iw:trunc(ih/4)*2:0:ih-trunc(ih/4)*2');
      final s = g.split(half, 2);
      final f = g.v(s[0], 'vflip');
      return g.join([f, s[1]], 'vstack=inputs=2');
  }
}

/// Four-way kaleidoscope from the top-left quadrant.
String kaleidoscope(FilterGraph g, String input) {
  final q = g.v(input, 'crop=trunc(iw/4)*2:trunc(ih/4)*2:0:0');
  final s = g.split(q, 2);
  final hf = g.v(s[1], 'hflip');
  final top = g.join([s[0], hf], 'hstack=inputs=2');
  final t = g.split(top, 2);
  final vf = g.v(t[1], 'vflip');
  return g.join([t[0], vf], 'vstack=inputs=2');
}

/// 2×2 grid of flipped copies ("Picture in Picture" / 4 screens).
String tile4(FilterGraph g, String input, {bool flipped = true}) {
  final small = g.v(input, 'scale=trunc(iw/4)*2:trunc(ih/4)*2');
  final s = g.split(small, 4);
  final b = flipped ? g.v(s[1], 'hflip') : s[1];
  final c = flipped ? g.v(s[2], 'vflip') : s[2];
  final d = flipped ? g.v(s[3], 'hflip,vflip') : s[3];
  return g.join([s[0], b, c, d], 'xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0');
}

/// Sine displacement ("Wave"). Amplitudes are fractions of the frame size.
String wave({double horizontalAmp = 0.03, double verticalAmp = 0, double waves = 3, double speed = 4}) {
  final dx = horizontalAmp == 0 ? '0' : 'W*${fmt(horizontalAmp)}*sin(2*PI*Y/H*${fmt(waves)}+T*${fmt(speed)})';
  final dy = verticalAmp == 0 ? '0' : 'H*${fmt(verticalAmp)}*sin(2*PI*X/W*${fmt(waves)}+T*${fmt(speed)}+1.3)';
  return "geq='p(X+$dx,Y+$dy)'";
}

/// Swirl around the center. [strength] is the rotation (radians) at center.
String swirl({double strength = 2.5, double radius = 0.5}) =>
    "geq='st(0,X-W/2);st(1,Y-H/2);st(2,hypot(ld(0),ld(1)));"
    'st(3,atan2(ld(1),ld(0))+${fmt(strength)}*max(0,1-ld(2)/(${fmt(radius)}*min(W,H))));'
    "p(W/2+ld(2)*cos(ld(3)),H/2+ld(2)*sin(ld(3)))'";

/// Radial remap. `exponent > 1` magnifies the center (bulge / punch),
/// `exponent < 1` squeezes it (pinch).
String radial(double exponent) =>
    "geq='st(0,X-W/2);st(1,Y-H/2);st(2,max(hypot(ld(0),ld(1))/(0.5*hypot(W,H)),0.0001));"
    "st(3,pow(ld(2),${fmt(exponent - 1)}));p(W/2+ld(0)*ld(3),H/2+ld(1)*ld(3))'";

/// Rhythmic zoom in/out around the center.
String zoomPulse({double amount = 0.15, double speed = 4}) =>
    "geq='st(0,1+${fmt(amount)}*abs(sin(T*${fmt(speed)})));p(W/2+(X-W/2)/ld(0),H/2+(Y-H/2)/ld(0))'";

/// Vegas "TV Simulator": scanlines, noise and line-sync tearing.
String tvSimulator({double lineSync = 0.6, int noise = 18}) =>
    "geq=lum='p(X+W*0.025*sin(Y*0.35+T*40)*gt(random(1),${fmt(1 - lineSync)}),Y)*(0.75+0.25*mod(Y,2))':"
    "cb='p(X+W*0.012*sin(Y*0.7+T*40),Y)':cr='p(X+W*0.012*sin(Y*0.7+T*40),Y)',"
    'noise=alls=$noise:allf=t';

/// Glow standing in for Vegas "Light Rays".
String lightRays(FilterGraph g, String input, {double sigma = 14, bool intense = false}) {
  final s = g.split(input, 2);
  final glow = g.v(
    s[1],
    "gblur=sigma=${fmt(intense ? sigma * 1.6 : sigma)},curves=all='0/0 0.45/${intense ? '0.95' : '0.75'} 1/1'",
  );
  return g.join([s[0], glow], 'blend=all_mode=screen');
}

/// Duotone gradient map from a dark color to a light color (hex RRGGBB).
String gradientMap(String darkHex, String lightHex) {
  int ch(String hex, int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  String lut(int i) {
    final a = ch(darkHex, i);
    final b = ch(lightHex, i);
    return '$a+(${b - a})*val/255';
  }

  return "format=gray,format=rgb24,lutrgb=r='${lut(0)}':g='${lut(1)}':b='${lut(2)}'";
}

/// FFmpeg pseudocolor presets used as "Gradient Map" presets.
String pseudocolor(String preset) => 'format=yuv444p,pseudocolor=p=$preset';

/// Swap red and blue ("Channel Blend: RGB to BGR").
const rgbToBgr = 'colorchannelmixer=rr=0:rb=1:br=1:bb=0';

/// Vegas "HSL Adjust: Invert Color" preset — rotates hue by 180°.
const hslInvert = 'hue=h=180';

/// Hue rotation in degrees with optional saturation multiplier.
String hue(num degrees, {double saturation = 1}) =>
    'hue=h=${fmt(degrees)}${saturation != 1 ? ':s=${fmt(saturation)}' : ''}';

/// Vegas HSL Adjust "Add to hue" (0..1 of a full turn).
String addToHue(double turns, {double saturation = 1}) => hue((turns * 360) % 360, saturation: saturation);

/// Solid color wash (e.g. the "red filter" in Devil's Blast).
String tint(String hex, {double amount = 0.55}) {
  double c(int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16) / 255;
  final r = c(0), gg = c(1), b = c(2);
  final keep = 1 - amount;
  return 'colorchannelmixer='
      'rr=${fmt(keep + amount * r)}:rg=${fmt(amount * r * 0.5)}:rb=${fmt(amount * r * 0.3)}:'
      'gr=${fmt(amount * gg * 0.3)}:gg=${fmt(keep + amount * gg)}:gb=${fmt(amount * gg * 0.3)}:'
      'br=${fmt(amount * b * 0.3)}:bg=${fmt(amount * b * 0.5)}:bb=${fmt(keep + amount * b)}';
}

/// Camera shake via a moving crop scaled back to the frame size.
String shake({required int width, required int height, int amplitude = 10, double speed = 1}) {
  final a = (amplitude ~/ 2) * 2; // keep dimensions even
  if (a == 0) return 'null';
  final s = fmt(speed);
  return 'crop=iw-${2 * a}:ih-${2 * a}:'
      "'$a+$a*sin(t*43*$s)*cos(t*17*$s)':'$a+$a*cos(t*37*$s)*sin(t*23*$s)',"
      'scale=$width:$height';
}

/// Classic film grain + flicker.
String filmFlicker({int grain = 14}) => "noise=alls=$grain:allf=t,eq=brightness='0.04*sin(t*47)':eval=frame";
