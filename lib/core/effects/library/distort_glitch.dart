import '../../ffmpeg/blocks.dart';
import '../effect.dart';
import 'helpers.dart';

final List<Effect> distortEffects = [
  Effect(
    id: 'mirror',
    name: 'Mirror',
    description: 'Vegas-style Reflect presets: one half mirrored onto the other.',
    category: EffectCategory.distort,
    params: const [
      EffectParam.choice('side', 'Reflect', value: 'Left', options: ['Left', 'Right', 'Top', 'Bottom']),
    ],
    video: (g, input, p, env) => mirror(g, input, switch (p.choice('side')) {
      'Right' => MirrorSide.right,
      'Top' => MirrorSide.top,
      'Bottom' => MirrorSide.bottom,
      _ => MirrorSide.left,
    }),
  ),
  Effect(
    id: 'flip',
    name: 'Flip',
    description: 'Flip horizontally, vertically or both (upside down).',
    category: EffectCategory.distort,
    params: const [
      EffectParam.choice('axis', 'Axis', value: 'Horizontal', options: ['Horizontal', 'Vertical', 'Both']),
    ],
    video: (g, input, p, env) => g.v(input, switch (p.choice('axis')) {
      'Vertical' => 'vflip',
      'Both' => 'hflip,vflip',
      _ => 'hflip',
    }),
  ),
  Effect(
    id: 'kaleidoscope',
    name: 'Kaleidoscope',
    description: 'Four-way mirror from the top-left quarter.',
    category: EffectCategory.distort,
    video: kaleidoscopeFx(),
  ),
  Effect(
    id: 'four_screens',
    name: 'Four Screens',
    description: '2×2 grid of flipped copies (Picture in Picture).',
    category: EffectCategory.distort,
    video: (g, input, p, env) => tile4(g, input),
  ),
  Effect(
    id: 'wave',
    name: 'Wave',
    description: 'Sine-wave ripple through the picture.',
    category: EffectCategory.distort,
    params: const [
      EffectParam.choice('direction', 'Direction', value: 'Horizontal', options: ['Horizontal', 'Vertical', 'Both']),
      EffectParam.decimal('amount', 'Amplitude', value: 0.04, min: 0.005, max: 0.15, step: 0.005),
      EffectParam.decimal('waves', 'Waves', value: 3, min: 0.5, max: 30, step: 0.5),
    ],
    video: (g, input, p, env) {
      final dir = p.choice('direction');
      final amt = p.decimal('amount');
      return g.v(
        input,
        wave(
          horizontalAmp: dir == 'Vertical' ? 0 : amt,
          verticalAmp: dir == 'Horizontal' ? 0 : amt,
          waves: p.decimal('waves'),
        ),
      );
    },
  ),
  Effect(
    id: 'swirl',
    name: 'Swirl',
    description: 'Twist the middle of the frame into a whirlpool.',
    category: EffectCategory.distort,
    params: const [EffectParam.decimal('strength', 'Strength', value: 2.5, min: -6, max: 6, step: 0.1)],
    video: (g, input, p, env) => g.v(input, swirl(strength: p.decimal('strength'))),
  ),
  Effect(
    id: 'pinch',
    name: 'Pinch',
    description: 'Squeeze the center inward (Pinch/Punch).',
    category: EffectCategory.distort,
    params: const [EffectParam.decimal('amount', 'Amount', value: 0.5, min: 0.1, max: 0.95, step: 0.05)],
    video: (g, input, p, env) => g.v(input, radial(1 - p.decimal('amount') * 0.7)),
  ),
  Effect(
    id: 'bulge',
    name: 'Bulge',
    description: 'Fisheye punch that blows up the middle.',
    category: EffectCategory.distort,
    keywords: const ['fisheye', 'sphere', 'punch'],
    params: const [EffectParam.decimal('amount', 'Amount', value: 0.6, min: 0.1, max: 1.5, step: 0.05)],
    video: (g, input, p, env) => g.v(input, radial(1 + p.decimal('amount'))),
  ),
  Effect(
    id: 'water_ripple',
    name: 'Water Ripple',
    description: 'Circular ripples spreading from the center.',
    category: EffectCategory.distort,
    video: vf(
      "geq='st(0,X-W/2);st(1,Y-H/2);st(2,max(hypot(ld(0),ld(1)),1));"
      'st(3,0.012*min(W,H)*sin(ld(2)/(0.035*min(W,H))-T*6));'
      "p(X+ld(0)/ld(2)*ld(3),Y+ld(1)/ld(2)*ld(3))'",
    ),
  ),
  Effect(
    id: 'zoom_pulse',
    name: 'Zoom Pulse',
    description: 'Rhythmic punch-in zoom.',
    category: EffectCategory.distort,
    params: const [
      EffectParam.decimal('amount', 'Zoom', value: 0.2, min: 0.05, max: 0.8, step: 0.05),
      EffectParam.decimal('speed', 'Speed', value: 4, min: 0.5, max: 15, step: 0.5),
    ],
    video: (g, input, p, env) => g.v(input, zoomPulse(amount: p.decimal('amount'), speed: p.decimal('speed'))),
  ),
  Effect(
    id: 'spin',
    name: 'Spin',
    description: 'The whole picture rotates.',
    category: EffectCategory.distort,
    params: const [EffectParam.decimal('speed', 'Turns per second', value: 0.5, min: -3, max: 3, step: 0.05)],
    video: (g, input, p, env) => g.v(input, 'rotate=a=t*${fmt(p.decimal('speed') * 6.283185)}:c=black'),
  ),
  Effect(
    id: 'diamond',
    name: 'Diamond',
    description: 'The clip turned 45° into a diamond over a blurred copy of itself.',
    category: EffectCategory.distort,
    video: (g, input, p, env) {
      final s = g.split(input, 2);
      final bg = g.v(s[0], 'boxblur=16:2,eq=brightness=-0.15');
      final fg = g.v(s[1], 'scale=trunc(iw*0.62/2)*2:-2,format=rgba,rotate=PI/4:c=none:ow=rotw(PI/4):oh=roth(PI/4)');
      return g.join([bg, fg], 'overlay=(W-w)/2:(H-h)/2:format=auto');
    },
  ),
  Effect(
    id: 'pixelate',
    name: 'Pixelate',
    description: 'Big chunky pixels.',
    category: EffectCategory.distort,
    params: const [EffectParam.integer('size', 'Block size', value: 16, min: 2, max: 64, unit: 'px')],
    video: (g, input, p, env) {
      final s = p.integer('size');
      return g.v(input, 'pixelize=w=$s:h=$s');
    },
  ),
  Effect(
    id: 'shake',
    name: 'Earthquake',
    description: 'Violent camera shake.',
    category: EffectCategory.distort,
    keywords: const ['camera shake'],
    params: const [EffectParam.integer('intensity', 'Intensity', value: 12, min: 2, max: 60, unit: 'px')],
    video: (g, input, p, env) =>
        g.v(input, shake(width: env.width, height: env.height, amplitude: p.integer('intensity'))),
  ),
  Effect(
    id: 'stretch_wobble',
    name: 'Jelly Wobble',
    description: 'The frame squashes and stretches like jelly.',
    category: EffectCategory.distort,
    video: vf("geq='st(0,1+0.12*sin(T*7));p(W/2+(X-W/2)*ld(0),H/2+(Y-H/2)/ld(0))'"),
  ),
];

final List<Effect> glitchEffects = [
  Effect(
    id: 'vhs',
    name: 'VHS Tape',
    description: 'Noisy vintage tape with chroma bleed and a wobbly, muffled soundtrack.',
    category: EffectCategory.glitch,
    video: vf('noise=alls=20:allf=t+u,curves=vintage,chromashift=cbh=3:crh=-3,eq=saturation=1.3'),
    audio: af('vibrato=f=0.8:d=0.08,lowpass=f=6000'),
  ),
  Effect(
    id: 'crt_tv',
    name: 'CRT TV',
    description: 'Scanlines, line-sync tearing and tube vignetting (TV Simulator).',
    category: EffectCategory.glitch,
    params: const [EffectParam.decimal('sync', 'Line sync', value: 0.5, min: 0.05, max: 1.0, step: 0.05)],
    video: (g, input, p, env) => g.v(input, '${tvSimulator(lineSync: p.decimal('sync'))},vignette=PI/4'),
  ),
  Effect(
    id: 'rgb_split',
    name: 'RGB Split',
    description: 'Red and blue channels drift apart and snap back.',
    category: EffectCategory.glitch,
    video: vf("format=gbrp,geq=r='p(X+W*0.03*sin(T*9),Y)':g='p(X,Y)':b='p(X-W*0.03*sin(T*7),Y+H*0.01*sin(T*5))'"),
  ),
  Effect(
    id: 'chromatic_aberration',
    name: 'Chromatic Aberration',
    description: 'Cheap-lens color fringing.',
    category: EffectCategory.glitch,
    params: const [EffectParam.integer('offset', 'Offset', value: 6, min: 1, max: 40, unit: 'px')],
    video: (g, input, p, env) {
      final o = p.integer('offset');
      return g.v(input, 'rgbashift=rh=-$o:bh=$o:rv=${o ~/ 2}:bv=-${o ~/ 2}');
    },
  ),
  Effect(
    id: 'ghost_trails',
    name: 'Ghost Trails',
    description: 'Bright things leave long glowing trails.',
    category: EffectCategory.glitch,
    video: vf('lagfun=decay=0.96'),
  ),
  Effect(
    id: 'echo_frames',
    name: 'Echo Frames',
    description: 'Motion smears across the last eight frames.',
    category: EffectCategory.glitch,
    video: vf("tmix=frames=8:weights='1 1 1 1 1 1 1 1'"),
  ),
  Effect(
    id: 'motion_amplify',
    name: 'Motion Amplify',
    description: 'Exaggerates every change between frames into strobing artifacts.',
    category: EffectCategory.glitch,
    video: vf('amplify=radius=2:factor=12:threshold=100'),
  ),
  Effect(
    id: 'melt',
    name: 'Datamosh Melt',
    description: 'Fake datamosh: frames bleed and melt into each other.',
    category: EffectCategory.glitch,
    keywords: const ['datamosh', 'bloom'],
    video: vf("tmix=frames=5:weights='4 3 2 1 1',lagfun=decay=0.9,amplify=radius=1:factor=4"),
  ),
  Effect(
    id: 'scramble',
    name: 'Block Scramble',
    description: 'The picture is diced into shuffled blocks.',
    category: EffectCategory.glitch,
    params: const [EffectParam.integer('block', 'Block size', value: 32, min: 8, max: 128, unit: 'px')],
    video: (g, input, p, env) {
      final b = p.integer('block');
      return g.v(input, 'shufflepixels=m=block:w=$b:h=$b:seed=7');
    },
  ),
  Effect(
    id: 'strobe',
    name: 'Invert Strobe',
    description: 'Flashes between normal and negative.',
    category: EffectCategory.glitch,
    params: const [EffectParam.decimal('rate', 'Flashes per second', value: 5, min: 1, max: 15, step: 0.5)],
    video: (g, input, p, env) {
      final period = 1 / p.decimal('rate');
      return g.v(input, "negate=enable='lt(mod(t,${fmt(period)}),${fmt(period / 2)})'");
    },
  ),
  Effect(
    id: 'lag',
    name: 'Laggy Stream',
    description: 'Choppy low frame rate with crunchy compression audio.',
    category: EffectCategory.glitch,
    video: vf('fps=6,noise=alls=6:allf=t'),
    audio: af('acrusher=bits=8:mode=log:aa=0.4:mix=0.6,highpass=f=200,lowpass=f=4000'),
  ),
  Effect(
    id: 'eight_bit',
    name: '8-Bit',
    description: 'Retro console pixels and a bitcrushed soundtrack.',
    category: EffectCategory.glitch,
    keywords: const ['retro', 'nes', 'chiptune'],
    video: vf(
      "pixelize=w=8:h=8,format=rgb24,lutrgb=r='floor(val/64)*64+32':g='floor(val/64)*64+32':b='floor(val/64)*64+32',eq=saturation=1.6",
    ),
    audio: af('acrusher=bits=4:mode=lin:aa=0:samples=6'),
  ),
  Effect(
    id: 'game_boy',
    name: 'Game Boy',
    description: 'Four shades of green and chunky pixels.',
    category: EffectCategory.glitch,
    video: vf(
      'pixelize=w=6:h=6,format=gray,format=rgb24,lutrgb='
      "r='if(lt(val,64),15,if(lt(val,128),48,if(lt(val,192),139,155)))':"
      "g='if(lt(val,64),56,if(lt(val,128),98,if(lt(val,192),172,188)))':"
      "b='if(lt(val,64),15,if(lt(val,128),48,if(lt(val,192),15,15)))'",
    ),
    audio: af('acrusher=bits=6:mode=lin:aa=0:samples=3,lowpass=f=4000'),
  ),
];
