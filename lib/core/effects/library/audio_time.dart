import 'dart:math' as math;

import '../../ffmpeg/blocks.dart';
import '../../ffmpeg/filter_graph.dart';
import '../../sparta/model.dart';
import '../../sparta/patterns.dart';
import '../effect.dart';
import 'helpers.dart';

final List<Effect> audioEffects = [
  Effect(
    id: 'pitch_shift',
    name: 'Pitch Shift',
    description: 'Shift the pitch without changing speed.',
    category: EffectCategory.audio,
    params: const [EffectParam.integer('semitones', 'Semitones', value: -5, min: -24, max: 24, unit: 'st')],
    audio: (g, input, p, env) => g.a(input, pitch(p.integer('semitones'), sampleRate: env.sampleRate)),
  ),
  Effect(
    id: 'chipmunk',
    name: 'Chipmunk',
    description: 'High squeaky voice (+8 semitones).',
    category: EffectCategory.audio,
    keywords: const ['helium', 'high pitch'],
    audio: af(pitch(8)),
  ),
  Effect(
    id: 'deep_voice',
    name: 'Deep Voice',
    description: 'Low, heavy voice (−7 semitones).',
    category: EffectCategory.audio,
    keywords: const ['low pitch'],
    audio: af(pitch(-7)),
  ),
  Effect(
    id: 'bass_boost',
    name: 'Bass Boost',
    description: 'Heavy low end.',
    category: EffectCategory.audio,
    loud: true,
    params: const [EffectParam.integer('gain', 'Bass gain', value: 15, min: 3, max: 40, unit: 'dB')],
    audio: (g, input, p, env) => g.a(input, 'bass=g=${p.integer('gain')}:f=100:w=0.6'),
  ),
  Effect(
    id: 'earrape',
    name: 'Earrape',
    description: 'Extremely loud, clipped and crushed. You were warned.',
    category: EffectCategory.audio,
    credit: 'NotSoBot tag',
    loud: true,
    video: vf('eq=saturation=2.2:contrast=1.4'),
    audio: af('bass=g=20:f=80,volume=20dB,acrusher=bits=4:mode=log:aa=0,asoftclip=type=hard'),
  ),
  Effect(
    id: 'distortion',
    name: 'Distortion',
    description: 'Overdriven, clipped crunch.',
    category: EffectCategory.audio,
    loud: true,
    params: const [EffectParam.integer('drive', 'Drive', value: 18, min: 3, max: 40, unit: 'dB')],
    audio: (g, input, p, env) => g.a(input, mangle(driveDb: p.integer('drive').toDouble())),
  ),
  Effect(
    id: 'echo',
    name: 'Echo',
    description: 'Repeating delay.',
    category: EffectCategory.audio,
    params: const [
      EffectParam.integer('delay', 'Delay', value: 400, min: 50, max: 2000, unit: 'ms'),
      EffectParam.decimal('decay', 'Decay', value: 0.45, min: 0.1, max: 0.9, step: 0.05),
    ],
    audio: (g, input, p, env) {
      final d = p.integer('delay');
      final k = p.decimal('decay');
      return g.a(input, 'aecho=0.8:0.9:$d|${d * 2}|${d * 3}:${fmt(k)}|${fmt(k * k)}|${fmt(k * k * k)}');
    },
  ),
  Effect(
    id: 'reverb',
    name: 'Reverb',
    description: 'Big room ambience.',
    category: EffectCategory.audio,
    params: const [EffectParam.decimal('wet', 'Wet', value: 0.6, min: 0.1, max: 1.0, step: 0.05)],
    audio: (g, input, p, env) => g.a(input, reverb(wet: p.decimal('wet'))),
  ),
  Effect(
    id: 'chorus',
    name: 'Chorus',
    description: 'Thick doubled voices.',
    category: EffectCategory.audio,
    params: const [EffectParam.toggle('wacky', 'Wacky (ExpressFX)', value: false)],
    audio: (g, input, p, env) => g.a(input, p.toggle('wacky') ? wackyChorus : softChorus),
  ),
  Effect(
    id: 'flanger',
    name: 'Flanger',
    description: 'Jet-plane sweep.',
    category: EffectCategory.audio,
    audio: af('flanger=delay=5:depth=8:speed=0.4:regen=40:width=80'),
  ),
  Effect(
    id: 'phaser',
    name: 'Phaser',
    description: 'Swirling phase sweep.',
    category: EffectCategory.audio,
    audio: af('aphaser=type=t:speed=1.2:decay=0.6:in_gain=0.6:out_gain=0.9'),
  ),
  Effect(
    id: 'tremolo',
    name: 'Tremolo',
    description: 'Volume chopped up rhythmically.',
    category: EffectCategory.audio,
    params: const [EffectParam.decimal('rate', 'Rate', value: 8, min: 1, max: 40, step: 0.5, unit: 'Hz')],
    audio: (g, input, p, env) => g.a(input, 'tremolo=f=${fmt(p.decimal('rate'))}:d=0.9'),
  ),
  Effect(
    id: 'vibrato',
    name: 'Vibrato',
    description: 'Wobbling pitch.',
    category: EffectCategory.audio,
    params: const [
      EffectParam.decimal('rate', 'Rate', value: 6, min: 1, max: 20, step: 0.5, unit: 'Hz'),
      EffectParam.decimal('depth', 'Depth', value: 0.6, min: 0.1, max: 1.0, step: 0.05),
    ],
    audio: (g, input, p, env) => g.a(input, 'vibrato=f=${fmt(p.decimal('rate'))}:d=${fmt(p.decimal('depth'))}'),
  ),
  Effect(
    id: 'bitcrusher',
    name: 'Bitcrusher',
    description: 'Lo-fi digital grit.',
    category: EffectCategory.audio,
    params: const [EffectParam.integer('bits', 'Bits', value: 6, min: 2, max: 12)],
    audio: (g, input, p, env) => g.a(input, 'acrusher=bits=${p.integer('bits')}:mode=log:aa=0.5'),
  ),
  Effect(
    id: 'telephone',
    name: 'Telephone',
    description: 'Tiny, band-limited phone speaker.',
    category: EffectCategory.audio,
    audio: af('highpass=f=400,lowpass=f=3200,acrusher=bits=10:mode=log:aa=1:mix=0.4,volume=1.5'),
  ),
  Effect(
    id: 'megaphone',
    name: 'Megaphone',
    description: 'Shouted through a cheap bullhorn.',
    category: EffectCategory.audio,
    loud: true,
    audio: af('highpass=f=600,lowpass=f=3000,${mangle(driveDb: 10, bits: 10)},volume=1.3'),
  ),
  Effect(
    id: 'underwater',
    name: 'Underwater',
    description: 'Muffled, wobbly audio with a blue, rippling picture.',
    category: EffectCategory.audio,
    video: vf(
      'colorbalance=bs=0.4:bm=0.3:rs=-0.2:rm=-0.2,${wave(horizontalAmp: 0.01, verticalAmp: 0.01, waves: 2, speed: 2)}',
    ),
    audio: af('lowpass=f=450,vibrato=f=1.5:d=0.3,$softChorus'),
  ),
  Effect(
    id: 'eight_d',
    name: '8D Audio',
    description: 'The sound circles around your head (use headphones).',
    category: EffectCategory.audio,
    audio: af('apulsator=hz=0.125:amount=0.9,${reverb(wet: 0.3)}'),
  ),
  Effect(
    id: 'reverse_audio',
    name: 'Reverse Audio',
    description: 'Only the soundtrack plays backwards.',
    category: EffectCategory.audio,
    heavy: true,
    audio: reverseAudio,
  ),
];

final List<Effect> timeEffects = [
  Effect(
    id: 'speed',
    name: 'Speed',
    description: 'Speed up or slow down, with or without pitch change.',
    category: EffectCategory.time,
    keywords: const ['fast', 'slow motion', 'speed up', 'slow down'],
    params: const [
      EffectParam.decimal('factor', 'Speed', value: 2.0, min: 0.25, max: 4.0, step: 0.05, unit: '×'),
      EffectParam.toggle('keepPitch', 'Keep pitch', value: true),
    ],
    video: (g, input, p, env) => g.v(input, setpts(p.decimal('factor'))),
    audio: (g, input, p, env) {
      final f = p.decimal('factor');
      return g.a(input, p.toggle('keepPitch') ? atempo(f) : tapeSpeed(f, sampleRate: env.sampleRate));
    },
    outputSeconds: (p, s) => s / p.decimal('factor'),
  ),
  Effect(
    id: 'reverse',
    name: 'Reverse',
    description: 'Play everything backwards.',
    category: EffectCategory.time,
    credit: 'NotSoBot tag',
    heavy: true,
    video: reverseVideo,
    audio: reverseAudio,
  ),
  Effect(
    id: 'boomerang',
    name: 'Boomerang',
    description: 'Forwards, then backwards.',
    category: EffectCategory.time,
    heavy: true,
    keywords: const ['ping pong'],
    video: (g, input, p, env) {
      final s = g.split(input, 2);
      final r = g.v(s[1], 'reverse');
      return g.join([s[0], r], 'concat=n=2:v=1:a=0');
    },
    audio: (g, input, p, env) {
      final s = g.split(input, 2, audio: true);
      final r = g.a(s[1], 'areverse');
      return g.join([s[0], r], 'concat=n=2:v=0:a=1');
    },
    outputSeconds: (p, s) => s * 2,
  ),
  Effect(
    id: 'loop',
    name: 'Loop',
    description: 'Repeat the clip several times.',
    category: EffectCategory.time,
    params: const [EffectParam.integer('times', 'Times', value: 3, min: 2, max: 8)],
    video: (g, input, p, env) => repeatStream(g, input, p.integer('times'), audio: false),
    audio: (g, input, p, env) => repeatStream(g, input, p.integer('times'), audio: true),
    outputSeconds: (p, s) => s * p.integer('times'),
  ),
  Effect(
    id: 'stutter',
    name: 'Stutter',
    description: 'The first moment repeats — "b-b-b-b-bruh" — before the clip plays.',
    category: EffectCategory.time,
    params: const [
      EffectParam.decimal('chunk', 'Chunk length', value: 0.2, min: 0.05, max: 1.5, step: 0.05, unit: 's'),
      EffectParam.integer('repeats', 'Repeats', value: 4, min: 1, max: 16),
    ],
    video: (g, input, p, env) => _stutter(g, input, p, env, audio: false),
    audio: (g, input, p, env) => _stutter(g, input, p, env, audio: true),
    outputSeconds: (p, s) => s + p.integer('repeats') * math.min(p.decimal('chunk'), s),
  ),
  Effect(
    id: 'nightcore',
    name: 'Nightcore',
    description: 'Faster and higher, with extra saturation.',
    category: EffectCategory.time,
    video: vf('${setpts(1.3)},eq=saturation=1.5:contrast=1.1'),
    audio: af(tapeSpeed(1.3)),
    outputSeconds: (p, s) => s / 1.3,
  ),
  Effect(
    id: 'slowed_reverb',
    name: 'Slowed + Reverb',
    description: 'Slowed tape pitch in a dreamy reverb with a purple haze.',
    category: EffectCategory.time,
    video: vf('${setpts(0.8)},colorbalance=rs=0.2:bs=0.35,eq=saturation=0.9:brightness=-0.03'),
    audio: af('${tapeSpeed(0.8)},${reverb(wet: 0.8)}'),
    outputSeconds: (p, s) => s / 0.8,
  ),
  Effect(
    id: 'vhs_rewind',
    name: 'VHS Rewind',
    description: 'Rewinding tape: backwards at double speed with squeaky audio and tracking noise.',
    category: EffectCategory.time,
    heavy: true,
    video: vf('reverse,${setpts(2)},noise=alls=30:allf=t,curves=vintage,${tvSimulator(lineSync: 0.8, noise: 10)}'),
    audio: af('areverse,${tapeSpeed(2)},lowpass=f=7000'),
    outputSeconds: (p, s) => s / 2,
  ),
];

final List<Effect> ytpmvEffects = [
  Effect(
    id: 'sparta_sequencer',
    name: 'Sparta Sequencer',
    description:
        'Plays one short sample from the clip as a Sparta pitch pattern: the chorus pitch (0 0 +1 +1 -2 -2 +1 +1) '
        'or any pattern from the Sparta Remix Wiki, or your own, in time at a BPM.',
    category: EffectCategory.ytpmv,
    credit: 'Patterns: Sparta Remix Wiki',
    keywords: const ['sparta', 'ytpmv', 'melody', 'pitch pattern', 'chorus', 'madness', 'epicness'],
    params: [
      EffectParam.choice('pattern', 'Pattern', value: sequencerPatternNames.first, options: sequencerPatternNames),
      const EffectParam.text(
        'custom',
        'Custom pattern',
        value: '0 0 +1 +1 -2 -2 +1 +1',
        hint: 'Used with "Custom": semitones in wiki notation (* longer, _ rest)',
      ),
      const EffectParam.decimal('bpm', 'Tempo', value: 140, min: 60, max: 240, step: 1, unit: 'BPM'),
      const EffectParam.decimal('start', 'Sample start', value: 0.0, min: 0.0, max: 600.0, step: 0.05, unit: 's'),
      const EffectParam.decimal('sample', 'Sample length', value: 0.4, min: 0.05, max: 2.0, step: 0.01, unit: 's'),
      const EffectParam.integer('repeats', 'Repeats', value: 2, min: 1, max: 8),
      const EffectParam.toggle('flash', 'Flip and colour each hit', value: true),
    ],
    video: (g, input, p, env) => _sequence(g, input, p, env, audio: false),
    audio: (g, input, p, env) => _sequence(g, input, p, env, audio: true),
    outputSeconds: (p, s) => _SequencePlan.from(p, s).totalSeconds,
  ),
  Effect(
    id: 'beat_chop',
    name: 'Beat Chop',
    description: 'Slice the clip into beats and replay them in a pattern like "1 1 2 1 3 3 4 4".',
    category: EffectCategory.ytpmv,
    keywords: const ['chop', 'remix', 'ytp'],
    params: const [
      EffectParam.text('pattern', 'Slice pattern', value: '1 1 2 1 3 3 4 4', hint: 'Slice numbers (max 48)'),
      EffectParam.decimal('beat', 'Slice length', value: 0.3, min: 0.05, max: 2.0, step: 0.01, unit: 's'),
    ],
    video: (g, input, p, env) => _chop(g, input, p, env, audio: false),
    audio: (g, input, p, env) => _chop(g, input, p, env, audio: true),
    outputSeconds: (p, s) => _chopPattern(p, s).length * math.min(p.decimal('beat'), s),
  ),
  Effect(
    id: 'pitch_ladder',
    name: 'Pitch Ladder',
    description: 'The opening sample repeats, climbing higher each time.',
    category: EffectCategory.ytpmv,
    params: const [
      EffectParam.integer('steps', 'Steps', value: 6, min: 2, max: 16),
      EffectParam.integer('interval', 'Step size', value: 2, min: -12, max: 12, unit: 'st'),
      EffectParam.decimal('length', 'Sample length', value: 0.5, min: 0.1, max: 3.0, step: 0.05, unit: 's'),
    ],
    video: (g, input, p, env) {
      final len = math.min(p.decimal('length'), env.duration);
      final steps = p.integer('steps');
      final src = g.v(input, 'trim=duration=${fmt(len)},setpts=PTS-STARTPTS');
      final copies = g.split(src, steps);
      final parts = [
        for (var i = 0; i < steps; i++)
          g.v(copies[i], hue((i * p.integer('interval') * 30) % 360, saturation: 1 + i * 0.1)),
      ];
      return g.join(parts, 'concat=n=$steps:v=1:a=0');
    },
    audio: (g, input, p, env) {
      final len = math.min(p.decimal('length'), env.duration);
      final steps = p.integer('steps');
      final src = g.a(input, 'atrim=duration=${fmt(len)},asetpts=PTS-STARTPTS');
      final copies = g.split(src, steps, audio: true);
      final parts = [
        for (var i = 0; i < steps; i++) g.a(copies[i], pitch(i * p.integer('interval'), sampleRate: env.sampleRate)),
      ];
      return g.join(parts, 'concat=n=$steps:v=0:a=1');
    },
    outputSeconds: (p, s) => p.integer('steps') * math.min(p.decimal('length'), s),
  ),
];

String _stutter(FilterGraph g, String input, ParamReader p, FxEnv env, {required bool audio}) {
  final chunk = math.min(p.decimal('chunk'), env.duration);
  final reps = p.integer('repeats');
  final s = g.split(input, 2, audio: audio);
  final trimmed = audio
      ? g.a(s[0], 'atrim=duration=${fmt(chunk)},asetpts=PTS-STARTPTS')
      : g.v(s[0], 'trim=duration=${fmt(chunk)},setpts=PTS-STARTPTS');
  final chunks = g.split(trimmed, reps, audio: audio);
  return g.join([...chunks, s[1]], 'concat=n=${reps + 1}:v=${audio ? 0 : 1}:a=${audio ? 1 : 0}');
}

/// The Sequencer's pattern choices: the chorus pitch, every classic, every
/// other wiki pitch pattern, then your own.
final Map<String, Pattern?> _sequencerPatterns = () {
  final lib = PatternLibrary.instance;
  final out = <String, Pattern?>{};
  final chorus = lib.classic(PatternKind.pitch, 'chorus');
  if (chorus != null) out['Chorus pitch (0 0 +1 +1 -2 -2 +1 +1)'] = chorus;
  String name(Pattern p) {
    final section = SectionKind.byWiki(p.section)?.label ?? '${p.section[0].toUpperCase()}${p.section.substring(1)}';
    var n = '$section › ${p.title}${p.classic ? ' (classic)' : ''}';
    for (var i = 2; out.containsKey(n); i++) {
      n = '$section › ${p.title} ($i)';
    }
    return n;
  }

  final all = lib.of(PatternKind.pitch).where((p) => p != chorus && p.section != 'chords').toList();
  for (final p in all.where((p) => p.classic)) {
    out[name(p)] = p;
  }
  for (final p in all.where((p) => !p.classic)) {
    out[name(p)] = p;
  }
  out[_customPattern] = null;
  return out;
}();

const _customPattern = 'Custom (type it below)';

/// Names of the Sequencer's pattern choices, in menu order.
final List<String> sequencerPatternNames = _sequencerPatterns.keys.toList();

class _SequencePlan {
  _SequencePlan(this.start, this.sampleLength, this.stepSeconds, this.totalSteps, this.hits);

  factory _SequencePlan.from(ParamReader p, double duration) {
    final choice = p.choice('pattern');
    Pattern? pattern = _sequencerPatterns[choice];
    if (choice == _customPattern) {
      try {
        pattern = PatternLibrary.custom(PatternKind.pitch, p.text('custom').replaceAll('+', ''));
      } on PatternFormatException {
        pattern = null;
      }
    }
    pattern ??= _sequencerPatterns.values.first ?? PatternLibrary.custom(PatternKind.pitch, '0 0 1 1 -2 -2 1 1');
    final stepSeconds = 15 / p.decimal('bpm');
    final sampleLength = math.min(p.decimal('sample'), math.max(duration, 0.04));
    final start = math.max(0.0, math.min(p.decimal('start'), duration - sampleLength));
    var totalSteps = pattern.bars * 16.0 * p.integer('repeats');
    var hits = pattern.looped(totalSteps);
    // Keep the graph a sensible size.
    if (hits.length > 128) {
      final cut = hits[128].step;
      hits = hits.take(128).toList();
      totalSteps = (cut / 16).ceil() * 16.0;
    }
    return _SequencePlan(start, sampleLength, stepSeconds, totalSteps, hits);
  }

  final double start;
  final double sampleLength;
  final double stepSeconds;
  final double totalSteps;
  final List<PatternHit> hits;

  double get totalSeconds => totalSteps * stepSeconds;
}

String _sequence(FilterGraph g, String input, ParamReader p, FxEnv env, {required bool audio}) {
  final plan = _SequencePlan.from(p, env.duration);
  final hits = plan.hits;
  // Slots: an optional leading rest, then each hit until the next one.
  final slots = <(PatternHit?, double)>[];
  if (hits.isEmpty || hits.first.step > 0) {
    slots.add((null, (hits.isEmpty ? plan.totalSteps : hits.first.step) * plan.stepSeconds));
  }
  for (var i = 0; i < hits.length; i++) {
    final end = i + 1 < hits.length ? hits[i + 1].step : plan.totalSteps;
    slots.add((hits[i], (end - hits[i].step) * plan.stepSeconds));
  }
  final copies = g.split(input, slots.length, audio: audio);
  final parts = <String>[];
  var hitIndex = 0;
  for (var i = 0; i < slots.length; i++) {
    final (hit, slot) = slots[i];
    final d = fmt(slot);
    if (hit == null) {
      parts.add(
        audio
            ? g.a(copies[i], 'atrim=duration=0.02,volume=0,apad=whole_dur=$d,atrim=duration=$d,asetpts=PTS-STARTPTS')
            : g.v(
                copies[i],
                'trim=end_frame=1,setpts=PTS-STARTPTS,drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill,'
                'tpad=stop_mode=clone:stop_duration=$d,trim=duration=$d,setpts=PTS-STARTPTS',
              ),
      );
      continue;
    }
    // The sample sounds for the note's length (cut by the next hit).
    final sounds = math.min(plan.sampleLength, math.min(hit.length * plan.stepSeconds, slot));
    final cut = 'start=${fmt(plan.start)}:duration=${fmt(math.max(0.02, sounds))}';
    if (audio) {
      parts.add(
        g.a(
          copies[i],
          'atrim=$cut,asetpts=PTS-STARTPTS,${pitch(hit.semitone, sampleRate: env.sampleRate)},'
          'afade=t=out:st=${fmt(math.max(0, sounds - 0.008))}:d=0.008,apad=whole_dur=$d,atrim=duration=$d,'
          'asetpts=PTS-STARTPTS',
        ),
      );
    } else {
      final flip = p.toggle('flash') && hitIndex.isOdd ? ',hflip' : '';
      final tint = p.toggle('flash') && hit.semitone != 0 ? ',${hue((hit.semitone * 30) % 360, saturation: 1.3)}' : '';
      parts.add(
        g.v(
          copies[i],
          'trim=$cut,setpts=PTS-STARTPTS$flip$tint,tpad=stop_mode=clone:stop_duration=$d,trim=duration=$d,'
          'setpts=PTS-STARTPTS',
        ),
      );
    }
    hitIndex++;
  }
  final n = parts.length;
  return g.join(parts, 'concat=n=$n:v=${audio ? 0 : 1}:a=${audio ? 1 : 0}');
}

List<int> _chopPattern(ParamReader p, double duration) {
  final beat = math.min(p.decimal('beat'), math.max(duration, 0.04));
  final slices = math.max(1, (duration / beat).floor());
  final pattern = p
      .text('pattern')
      .split(RegExp(r'[\s,;|]+'))
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .where((i) => i >= 1)
      .map((i) => math.min(i, slices))
      .take(48)
      .toList();
  return pattern.isEmpty ? [1] : pattern;
}

String _chop(FilterGraph g, String input, ParamReader p, FxEnv env, {required bool audio}) {
  final beat = math.min(p.decimal('beat'), math.max(env.duration, 0.04));
  final pattern = _chopPattern(p, env.duration);
  final copies = g.split(input, pattern.length, audio: audio);
  final parts = <String>[];
  for (var i = 0; i < pattern.length; i++) {
    final start = fmt((pattern[i] - 1) * beat);
    parts.add(
      audio
          ? g.a(copies[i], 'atrim=start=$start:duration=${fmt(beat)},asetpts=PTS-STARTPTS')
          : g.v(copies[i], 'trim=start=$start:duration=${fmt(beat)},setpts=PTS-STARTPTS'),
    );
  }
  final n = parts.length;
  return g.join(parts, 'concat=n=$n:v=${audio ? 0 : 1}:a=${audio ? 1 : 0}');
}
