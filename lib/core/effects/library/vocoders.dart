import '../../ffmpeg/blocks.dart';
import '../effect.dart';
import 'helpers.dart';

/// Vocoder-style voices built entirely from FFmpeg filters.
///
/// The originals (NotSoBot tags) ran the audio through autotune.exe under
/// Wine. Here the voice is robotized with an FFT phase reset (which turns it
/// into a steady buzz that follows the speech envelope — the core of a
/// vocoder sound), then pitched into chords and colored per style.
final List<Effect> vocoderEffects = [
  Effect(
    id: 'purple_vocoder',
    name: 'Purple Vocoder',
    description: 'Robotized voice stacked with a fifth, chorus shimmer and a purple wash.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    loud: true,
    video: vf('colorbalance=rs=0.45:gs=-0.45:bs=0.55:rm=0.2:bm=0.3,eq=saturation=1.3'),
    audio: chordFx(const [0, 7], pre: robot(winSize: 1024), post: softChorus),
  ),
  Effect(
    id: 'techno',
    name: 'Techno',
    description: 'Octave-stacked robot through a bitcrusher and an 8 Hz gate; cyan strobing picture.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    loud: true,
    video: vf(
      "colorchannelmixer=rr=0:rg=0:rb=1:gr=0:gg=0:gb=1:br=0:bg=1:bb=0,eq=brightness='0.12*sin(t*50)':eval=frame",
    ),
    audio: chordFx(
      const [0, 12],
      pre: robot(winSize: 512),
      post: 'acrusher=bits=10:mode=log:aa=1:mix=0.5,tremolo=f=8:d=0.7',
    ),
  ),
  Effect(
    id: 'gansta',
    name: 'Gansta',
    description: 'Deep, slow robot buzz with boosted bass over a steel-blue picture.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    video: vf('hue=s=0,colorbalance=bs=1:bm=0.5:bh=0.5'),
    audio: af('${robot(winSize: 2048)},${pitch(-5)},bass=g=12:f=90'),
  ),
  Effect(
    id: 'xtal_vocoder',
    name: 'Xtal Vocoder',
    description: 'Crystal robot choir (root, octave, octave+fifth) with shimmering echoes and an icy glow.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    loud: true,
    video: seq([vf('hue=s=0,colorbalance=bs=1:bm=0.5:bh=0.5'), raysFx()]),
    audio: chordFx(const [0, 12, 19], pre: robot(winSize: 512), post: 'aecho=0.8:0.7:60|120:0.35|0.25'),
  ),
  Effect(
    id: 'daft_vocoder',
    name: 'Daft Vocoder',
    description: 'Talk-box style major triad through a phaser; monochrome green.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    loud: true,
    video: vf('hue=s=0,colorbalance=gs=1:gm=0.8:gh=0.5'),
    audio: chordFx(const [0, 4, 7], pre: robot(winSize: 1024), post: 'aphaser=type=t:speed=0.8:decay=0.5'),
  ),
  Effect(
    id: 'electric',
    name: 'Electric',
    description: 'Robot voice frequency-shifted into metallic territory with a flanger; glowing edges.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    video: (g, input, p, env) {
      final s = g.split(input, 2);
      final base = g.v(s[0], 'curves=vintage');
      final edges = g.v(s[1], 'edgedetect=mode=colormix:high=0.2,eq=brightness=0.1:saturation=2');
      return g.join([base, edges], 'blend=all_mode=screen');
    },
    audio: af('${robot(winSize: 1024)},afreqshift=shift=120,flanger=delay=3:depth=6:speed=0.6'),
  ),
  Effect(
    id: 'capcut_robot',
    name: 'CapCut Robot',
    description: 'The TikTok robot: buzzing voice with a fast ring-mod flutter and wobbly chroma.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    video: vf("geq=lum='lum(X,Y)':cb='cb(X,Y)+10*sin(2*PI*X/30+T*5)':cr='cr(X,Y)+10*sin(2*PI*Y/30+T*5)'"),
    audio: af('${robot(winSize: 1024)},tremolo=f=40:d=0.6'),
  ),
  Effect(
    id: 'white_robotic_dimension',
    name: 'White Robotic Dimension',
    description: 'Robot voice a fifth up in a big reverb; washed-out white dimension glow.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    video: seq([vf("hue=s=0.2,curves=preset=lighter,curves=all='0/0.25 1/1'"), raysFx(intense: true)]),
    audio: af('${robot(winSize: 1024)},${pitch(7)},${reverb(wet: 0.7)}'),
  ),
  Effect(
    id: 'discord_electronic',
    name: 'Discord Electronic Sounds',
    description: 'Bitcrushed, band-limited robot call quality in Discord blurple.',
    category: EffectCategory.vocoder,
    credit: 'NotSoBot tag (reworked)',
    video: vf(gradientMap('1e1f4d', 'aab4ff')),
    audio: af('acrusher=bits=6:mode=lin:aa=0.3,${robot(winSize: 512)},highpass=f=300,lowpass=f=5000'),
  ),
  Effect(
    id: 'yellow_vocoder',
    name: 'Yellow Vocoder',
    description: 'Warm robot choir on a fourth over a golden gradient.',
    category: EffectCategory.vocoder,
    loud: true,
    video: vf(gradientMap('3d2200', 'ffe14d')),
    audio: chordFx(const [0, 5], pre: robot(winSize: 1024)),
  ),
  Effect(
    id: 'chromatic_vocoder',
    name: 'Chromatic Vocoder',
    description: 'Major-seventh robot chord with a spinning rainbow and RGB fringing.',
    category: EffectCategory.vocoder,
    loud: true,
    video: vf('hue=h=t*120:s=1.6,rgbashift=rh=-6:bh=6'),
    audio: chordFx(const [0, 4, 7, 11], pre: robot(winSize: 1024)),
  ),
  Effect(
    id: 'glitch_vocoder',
    name: 'Glitch Vocoder',
    description: 'High, crushed robot with chorus smear; noisy picture with RGB tearing.',
    category: EffectCategory.vocoder,
    video: vf(
      "format=gbrp,geq=r='p(X+W*0.02*sin(T*23),Y)':g='p(X,Y)':b='p(X-W*0.02*sin(T*17),Y)',noise=alls=25:allf=t",
    ),
    audio: af('${robot(winSize: 256)},acrusher=bits=5:mode=log:aa=0.2:mix=0.7,$softChorus'),
  ),
  Effect(
    id: 'robot_voice',
    name: 'Robot Voice',
    description: 'Plain robotization. Pick how low or high the robot buzzes.',
    category: EffectCategory.vocoder,
    params: const [
      EffectParam.choice('pitch', 'Robot pitch', value: 'Mid', options: ['Low', 'Mid', 'High']),
    ],
    audio: (g, input, p, env) {
      final win = switch (p.choice('pitch')) {
        'Low' => 2048,
        'High' => 512,
        _ => 1024,
      };
      return g.a(input, robot(winSize: win));
    },
  ),
  Effect(
    id: 'ghost_whisper',
    name: 'Ghost Whisper',
    description: 'Whisperized voice in a long reverb with ghost trails in the picture.',
    category: EffectCategory.vocoder,
    video: vf('hue=s=0.1,eq=brightness=-0.08:contrast=1.2,lagfun=decay=0.96'),
    audio: af('${whisper(winSize: 256)},${reverb(wet: 0.8)}'),
  ),
  Effect(
    id: 'alien',
    name: 'Alien Transmission',
    description: 'Frequency-shifted robot with ring modulation, green bulge picture.',
    category: EffectCategory.vocoder,
    video: vf("${gradientMap('001a0a', '66ff99')},${radial(1.6)}"),
    audio: (g, input, p, env) {
      final shifted = g.a(input, '${robot(winSize: 512)},afreqshift=shift=300');
      return ringMod(g, shifted, 55, seconds: env.duration, sampleRate: env.sampleRate);
    },
  ),
];
