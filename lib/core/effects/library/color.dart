import '../../ffmpeg/blocks.dart';
import '../effect.dart';
import 'helpers.dart';

const _gradientPresets = [
  'magma',
  'inferno',
  'plasma',
  'viridis',
  'turbo',
  'cividis',
  'heat',
  'fiery',
  'cool',
  'spectral',
  'helix',
  'solar',
];

const _duotones = {
  'Sunset': ('2d0038', 'ffb347'),
  'Ocean': ('001b3a', '4dd9ff'),
  'Matrix': ('000a00', '39ff14'),
  'Blurple': ('1e1f4d', 'aab4ff'),
  'Blood': ('150000', 'ff2a2a'),
  'Gold': ('2b1a00', 'ffd54a'),
  'Cotton Candy': ('3a0a5c', 'ff9ee6'),
};

final List<Effect> colorEffects = [
  Effect(
    id: 'loud_rainbow',
    name: 'Loud Rainbow',
    description: 'Cycling rainbow hue with doubled volume.',
    category: EffectCategory.color,
    credit: 'NotSoBot tag',
    loud: true,
    params: const [EffectParam.decimal('speed', 'Rainbow speed', value: 1.0, min: 0.1, max: 5.0, step: 0.1, unit: '×')],
    video: (g, input, p, env) => g.v(input, 'hue=h=t*${fmt(p.decimal('speed') * 60)}:s=1.5'),
    audio: af('volume=2'),
  ),
  Effect(
    id: 'fast_color',
    name: 'Fast Color',
    description: '1.5× speed-up with raised pitch and a racing rainbow.',
    category: EffectCategory.color,
    credit: 'NotSoBot tag',
    video: vf('${setpts(1.5)},hue=h=t*60:s=1.5'),
    audio: af(tapeSpeed(1.5)),
    outputSeconds: (p, s) => s / 1.5,
  ),
  Effect(
    id: 'hue_shift',
    name: 'Hue Shift',
    description: 'Rotate every color around the wheel.',
    category: EffectCategory.color,
    params: const [
      EffectParam.integer('degrees', 'Hue', value: 120, min: 0, max: 359, unit: '°'),
      EffectParam.decimal('saturation', 'Saturation', value: 1.0, min: 0.0, max: 3.0, step: 0.05, unit: '×'),
    ],
    video: (g, input, p, env) => g.v(input, hue(p.integer('degrees'), saturation: p.decimal('saturation'))),
  ),
  Effect(
    id: 'grayscale',
    name: 'Grayscale',
    description: 'Black and white.',
    category: EffectCategory.color,
    keywords: const ['black and white', 'mono'],
    video: vf('hue=s=0'),
  ),
  Effect(
    id: 'sepia',
    name: 'Sepia',
    description: 'Old-photo brown tones.',
    category: EffectCategory.color,
    video: vf('colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131'),
  ),
  Effect(
    id: 'noir',
    name: 'Film Noir',
    description: 'High-contrast black and white with a heavy vignette.',
    category: EffectCategory.color,
    video: vf("hue=s=0,curves=all='0/0 0.3/0.15 0.7/0.85 1/1',vignette=PI/3.5"),
  ),
  Effect(
    id: 'posterize',
    name: 'Posterize',
    description: 'Crush each color channel down to a few levels.',
    category: EffectCategory.color,
    params: const [EffectParam.integer('levels', 'Levels', value: 4, min: 2, max: 8)],
    video: (g, input, p, env) {
      final step = (256 / p.integer('levels')).floor();
      final e = "'floor(val/$step)*$step+${step ~/ 2}'";
      return g.v(input, 'format=rgb24,lutrgb=r=$e:g=$e:b=$e');
    },
  ),
  Effect(
    id: 'solarize',
    name: 'Solarize',
    description: 'Highlights flip to negative — the darkroom accident.',
    category: EffectCategory.color,
    video: vf(
      "format=rgb24,lutrgb=r='if(gt(val,128),255-val,val)*1.8':g='if(gt(val,128),255-val,val)*1.8':b='if(gt(val,128),255-val,val)*1.8'",
    ),
  ),
  Effect(
    id: 'gradient_map',
    name: 'Gradient Map',
    description: 'Map brightness onto a color gradient (Vegas "Gradient Map").',
    category: EffectCategory.color,
    params: const [EffectParam.choice('preset', 'Gradient', value: 'turbo', options: _gradientPresets)],
    video: (g, input, p, env) => g.v(input, pseudocolor(p.choice('preset'))),
  ),
  Effect(
    id: 'duotone',
    name: 'Duotone',
    description: 'Two-color print look.',
    category: EffectCategory.color,
    params: [EffectParam.choice('palette', 'Palette', value: 'Sunset', options: _duotones.keys.toList())],
    video: (g, input, p, env) {
      final (dark, light) = _duotones[p.choice('palette')]!;
      return g.v(input, gradientMap(dark, light));
    },
  ),
  Effect(
    id: 'thermal',
    name: 'Thermal Camera',
    description: 'Heat-vision palette.',
    category: EffectCategory.color,
    video: vf('hue=s=0,${pseudocolor('inferno')}'),
  ),
  Effect(
    id: 'night_vision',
    name: 'Night Vision',
    description: 'Green, grainy military goggles.',
    category: EffectCategory.color,
    video: vf('hue=s=0,colorchannelmixer=rr=0.1:gg=1.2:bb=0.1,noise=alls=22:allf=t,vignette=PI/3,eq=brightness=0.05'),
  ),
  Effect(
    id: 'deep_fried',
    name: 'Deep Fried',
    description: 'Oversaturated, oversharpened meme look with blown-out bass and distortion.',
    category: EffectCategory.color,
    loud: true,
    keywords: const ['meme', 'fried'],
    video: vf('eq=saturation=3:contrast=1.9:brightness=0.06,unsharp=7:7:3,noise=alls=12:allf=t'),
    audio: af('bass=g=18:f=90,${mangle(driveDb: 16, bits: 7)}'),
  ),
  Effect(
    id: 'vaporwave',
    name: 'Vaporwave',
    description: 'Pink-and-cyan aesthetic, slowed down with reverb.',
    category: EffectCategory.color,
    keywords: const ['aesthetic', 'slowed'],
    video: vf(
      '${setpts(0.85)},colorbalance=rs=0.35:bs=0.45:gm=-0.2:rh=0.2:bh=0.3,eq=saturation=1.4,rgbashift=rh=-4:bh=4',
    ),
    audio: af('${tapeSpeed(0.85)},${reverb(wet: 0.6)}'),
    outputSeconds: (p, s) => s / 0.85,
  ),
  Effect(
    id: 'old_film',
    name: 'Old Film',
    description: 'Sepia grain and flicker with a band-limited, crackly soundtrack.',
    category: EffectCategory.color,
    video: vf('colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131,${filmFlicker()},vignette=PI/4'),
    audio: af('highpass=f=250,lowpass=f=3500,acrusher=bits=12:mode=log:aa=1:mix=0.3'),
  ),
  Effect(
    id: 'warm_glow',
    name: 'Warm Glow',
    description: 'Golden-hour warmth with a soft bloom.',
    category: EffectCategory.color,
    video: seq([vf('colorbalance=rs=0.15:rm=0.12:bs=-0.15:bm=-0.1,eq=saturation=1.2'), raysFx()]),
  ),
  Effect(
    id: 'ice_cold',
    name: 'Ice Cold',
    description: 'Frozen blue tones.',
    category: EffectCategory.color,
    video: vf('colorbalance=rs=-0.25:rm=-0.2:bs=0.3:bm=0.25:bh=0.2,eq=saturation=0.8:brightness=0.03'),
  ),
  Effect(
    id: 'bloom',
    name: 'Bloom',
    description: 'Dreamy glow around bright areas (Light Rays).',
    category: EffectCategory.color,
    params: const [EffectParam.toggle('intense', 'Intense', value: false)],
    video: (g, input, p, env) => lightRays(g, input, intense: p.toggle('intense')),
  ),
  Effect(
    id: 'oversaturated',
    name: 'Oversaturated',
    description: 'Every color turned all the way up.',
    category: EffectCategory.color,
    video: vf('eq=saturation=3:contrast=1.15'),
  ),
  Effect(
    id: 'edge_detect',
    name: 'Edge Detection',
    description: 'Only the outlines survive.',
    category: EffectCategory.color,
    video: vf('edgedetect=mode=colormix:high=0.15'),
  ),
  Effect(
    id: 'neon_edges',
    name: 'Neon Edges',
    description: 'Glowing neon outlines on black.',
    category: EffectCategory.color,
    video: seq([vf('edgedetect=low=0.05:high=0.2,hue=h=t*40,eq=saturation=3,format=yuv420p'), raysFx(intense: true)]),
  ),
  Effect(
    id: 'emboss',
    name: 'Emboss',
    description: 'Stamped-metal relief.',
    category: EffectCategory.color,
    video: vf(
      "hue=s=0,convolution='-2 -1 0 -1 1 1 0 1 2:-2 -1 0 -1 1 1 0 1 2:-2 -1 0 -1 1 1 0 1 2:-2 -1 0 -1 1 1 0 1 2'",
    ),
  ),
  Effect(
    id: 'sketch',
    name: 'Pencil Sketch',
    description: 'Dark lines on paper.',
    category: EffectCategory.color,
    video: vf('edgedetect=low=0.1:high=0.3,negate,hue=s=0,eq=contrast=1.3'),
  ),
  Effect(
    id: 'vignette',
    name: 'Vignette',
    description: 'Darkened corners.',
    category: EffectCategory.color,
    params: const [EffectParam.decimal('strength', 'Strength', value: 0.8, min: 0.2, max: 1.5, step: 0.05)],
    video: (g, input, p, env) => g.v(input, 'vignette=${fmt(p.decimal('strength'))}'),
  ),
];
