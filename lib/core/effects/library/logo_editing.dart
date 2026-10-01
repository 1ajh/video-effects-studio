import '../../ffmpeg/blocks.dart';
import '../effect.dart';
import 'helpers.dart';

/// Effects recreated from recipes documented by the logo-editing community
/// (Logo Editing Wiki / Klasky Csupo Effects Wiki). Vegas Pro plugins are
/// approximated with equivalent FFmpeg filters.
const _wiki = 'Logo Editing Wiki';

final List<Effect> logoEditingEffects = [
  Effect(
    id: 'low_voice',
    name: 'Low Voice',
    description: 'Playback rate 0.75 (voice drops), Invert Color hue flip and a Reflect Left mirror.',
    category: EffectCategory.logoEditing,
    credit: 'tnt2005 (2015) · $_wiki',
    keywords: const ['slow', 'mirror', 'csupo'],
    video: seq([vf('${setpts(0.75)},$hslInvert'), mirrorFx(MirrorSide.left)]),
    audio: af(tapeSpeed(0.75)),
    outputSeconds: (p, s) => s / 0.75,
  ),
  Effect(
    id: 'luig_group',
    name: 'Luig Group',
    description: 'HSL Adjust add-to-hue 0.85 (greens turn blue) with the pitch set to −1.',
    category: EffectCategory.logoEditing,
    credit: 'Losky (2014) · Vegas recipe · $_wiki',
    video: vf(addToHue(0.85)),
    audio: af(pitch(-1.00877)),
  ),
  Effect(
    id: 'luig_group_bgr',
    name: 'Luig Group (BGR)',
    description: 'RGB → BGR channel swap plus Invert, pitch −1.',
    category: EffectCategory.logoEditing,
    credit: 'Gears3000 variant · $_wiki',
    video: vf('$rgbToBgr,negate'),
    audio: af(pitch(-1)),
  ),
  Effect(
    id: 'confusion',
    name: 'CoNfUsIoN',
    description:
        'Invert Color + 100% Invert (light and dark swap, colors stay) and Reflect Left; the video plays '
        'forwards but the audio is reversed.',
    category: EffectCategory.logoEditing,
    credit: 'ThroatHead! (2014) · Preview 2 Effects · $_wiki',
    heavy: true,
    keywords: const ['confusion', 'reverse'],
    video: seq([vf(invertLuminosity), mirrorFx(MirrorSide.left)]),
    audio: reverseAudio,
  ),
  Effect(
    id: 'confusion_g_major_4',
    name: 'CoNfUsIoN G MaJoR 4',
    description:
        'CoNfUsIoN and G-Major 4 together: mirrored, luminosity inverted, solarized, with a reversed 0/+5 pair.',
    category: EffectCategory.logoEditing,
    credit: 'G-Major 4 + CoNfUsIoN · $_wiki',
    heavy: true,
    loud: true,
    video: seq([vf(invertLuminosity), mirrorFx(MirrorSide.left), vf(gMajor4Look)]),
    audio: chordFx(const [0, 5], pre: 'areverse'),
  ),
  Effect(
    id: 'devils_blast',
    name: "Devil's Blast",
    description: 'Channel Blend red only, moderate light rays and TV Simulator line sync 0.5; tracks at −12 and −5.',
    category: EffectCategory.logoEditing,
    credit: 'L15Edition (2012) · Preview 2 Effects · $_wiki',
    loud: true,
    video: seq([vf(redOnly), raysFx(), vf(tvSimulator(lineSync: 0.5))]),
    audio: chordFx(const [-12, -5]),
  ),
  Effect(
    id: 'angels_blast',
    name: "Angel's Blast",
    description: 'Hue +0.13, the picture tiled 4 × 4 and a swirl that unwinds; pitch −8.14 (AVS pitch 160).',
    category: EffectCategory.logoEditing,
    credit: "Angel's Blast · $_wiki",
    video: (g, input, p, env) {
      final tiled = g.v(input, addToHue(0.13));
      final grid = tile4(g, g.v(tiled, 'scale=trunc(iw/4)*2:trunc(ih/4)*2'), flipped: false);
      final big = tile4(g, grid, flipped: false);
      return g.v(
        big,
        "scale=${env.width}:${env.height},geq='st(0,X-W/2);st(1,Y-H/2);st(2,hypot(ld(0),ld(1))/(0.5*hypot(W,H)));"
        'st(3,max(0,1-T/${fmt(env.duration)})*3.1*max(0,1-ld(2)));'
        "p(W/2+ld(0)*cos(ld(3))-ld(1)*sin(ld(3)),H/2+ld(0)*sin(ld(3))+ld(1)*cos(ld(3)))'",
      );
    },
    audio: af(pitch(-8.13686)),
  ),
  Effect(
    id: 'chorded',
    name: 'Chorded',
    description:
        'The IL Vocodex "Chord" classic: the voice is robotized and stacked into a major chord over the Chorded '
        'gradient map (white, blue, cyan).',
    category: EffectCategory.logoEditing,
    credit: 'U-Man (2014) · $_wiki',
    loud: true,
    keywords: const ['vocodex', 'vocoder', 'chord'],
    video: vf(gradientMapEven(const ['ffffff', '0000ff', '00ffff'])),
    audio: chordFx(const [0, 4, 7, 12], pre: robot(winSize: 1024), post: softChorus),
  ),
  Effect(
    id: 'scariest_chorded',
    name: 'SCARIEST Chorded',
    description: 'Contrast halved and a cyan/blue gradient map; three Vocodex chord tracks at −4, −1 and +14.',
    category: EffectCategory.logoEditing,
    credit: 'SCARIEST Chorded · $_wiki',
    loud: true,
    video: vf('eq=contrast=0.5,${gradientMapStops(const [(0.45, '00ffff'), (0.5, '08a3ff'), (0.8, '00ffff')])}'),
    audio: chordFx(const [-4, -1, 14], pre: '${robot(winSize: 1024)},$softChorus'),
  ),
  Effect(
    id: 'crying',
    name: 'Crying',
    description: 'HSL add-to-hue 0.615, Invert and a horizontal-only wave; tracks at −5 and 0.',
    category: EffectCategory.logoEditing,
    credit: 'Jamie Shaffer (2014) · $_wiki',
    keywords: const ['crying x', 'expression'],
    video: vf('${addToHue(0.615)},negate,${wave(horizontalAmp: 0.012, waves: 5, speed: 0)}'),
    audio: chordFx(const [-5, 0]),
  ),
  Effect(
    id: 'angry',
    name: 'Angry',
    description: 'Invert, RGB → BGR, hue +0.15, maximum pinch and Reflect Left; two mangled tracks at 0 and −2.',
    category: EffectCategory.logoEditing,
    credit: 'Angry X · $_wiki',
    loud: true,
    keywords: const ['angry x', 'expression', 'distortion'],
    video: seq([vf('negate,$rgbToBgr,${addToHue(0.15)},${radial(0.55)}'), mirrorFx(MirrorSide.left)]),
    audio: chordFx(const [0, -2], perVoice: mangle(driveDb: 14)),
  ),
  Effect(
    id: 'weird_code',
    name: 'Weird Code',
    description: 'Invert Color hue flip, Reflect Right and a 0.174 swirl; ExpressFX "Wacky 4" chorus.',
    category: EffectCategory.logoEditing,
    credit: 'LF5 (2015) · Klasky Csupo 2001 Effects · $_wiki',
    video: seq([vf(hslInvert), mirrorFx(MirrorSide.right), vf(swirl(strength: 0.174 * 2 * 3.14159))]),
    audio: af(wackyChorus),
  ),
  Effect(
    id: 'awake',
    name: 'Awake',
    description: 'Invert, hue +0.725 and a 21.7-wave horizontal ripple; pitches +2 and +4.',
    category: EffectCategory.logoEditing,
    credit: 'Awake Effect · $_wiki',
    video: vf('negate,${addToHue(0.725)},${wave(horizontalAmp: 0.036, waves: 21.71, speed: 4)}'),
    audio: chordFx(const [2, 4]),
  ),
  Effect(
    id: 'hitting',
    name: 'Hitting',
    description: 'Invert + Invert Color + rotate hue 305 with a vertical-only wave; tracks at −8, −5 and +7.',
    category: EffectCategory.logoEditing,
    credit: 'Hitting · $_wiki',
    loud: true,
    video: vf('negate,$hslInvert,${hue(305)},${wave(horizontalAmp: 0, verticalAmp: 0.03, waves: 4)}'),
    audio: chordFx(const [-8, -5, 7]),
  ),
  Effect(
    id: 'sponge',
    name: 'Sponge',
    description: 'Four-point "Sponge" gradient map (orange, yellow, blue, cyan) with intense light rays; +3 and +9.',
    category: EffectCategory.logoEditing,
    credit: 'tnt2005 (2015) · Preview 2 Effects #17 · $_wiki',
    loud: true,
    video: seq([
      vf(gradientMapEven(const ['ffb000', 'ffff00', '00baff', '34ffff'])),
      raysFx(intense: true),
    ]),
    audio: chordFx(const [3, 9]),
  ),
  Effect(
    id: 'pitch_black',
    name: 'Pitch Black',
    description: 'A black gradient map turns the picture pitch black; the pitch drops two octaves.',
    category: EffectCategory.logoEditing,
    credit: 'Preview 2 Effects · $_wiki',
    params: const [EffectParam.integer('semitones', 'Pitch', value: -24, min: -36, max: -12, unit: 'st')],
    video: vf('colorlevels=romax=0:gomax=0:bomax=0'),
    audio: (g, input, p, env) => g.a(input, pitch(p.integer('semitones'))),
  ),
  Effect(
    id: 'crazy_diamond',
    name: 'Crazy Diamond',
    description:
        'TV Simulator (line sync 0.75), a blue-red-green-white gradient map, intense light rays and increased '
        'contrast; a deep, wide chorus on the audio.',
    category: EffectCategory.logoEditing,
    credit: 'GTOTORPD (2012) · Preview 2 Effects · $_wiki',
    video: seq([
      vf('${tvSimulator(lineSync: 0.75)},${gradientMapEven(const ['0000ff', 'ff0000', '00ff00', 'ffffff'])}'),
      raysFx(intense: true),
      vf("curves=all='0/0 0.25/0.12 0.75/0.9 1/1'"),
    ]),
    audio: af('chorus=1:1:34.2:0.9:1.342:4,lowpass=f=10000'),
  ),
  Effect(
    id: 'rgb_to_bgr',
    name: 'RGB to BGR',
    description: 'Channel Blend "RGB to BGR": red and blue swap places.',
    category: EffectCategory.logoEditing,
    credit: 'Preview 2 Effects · $_wiki',
    video: vf(rgbToBgr),
  ),
  Effect(
    id: 'rgb_to_bgr_reversed',
    name: 'RGB to BGR Reversed',
    description: 'RGB → BGR with the whole clip played backwards.',
    category: EffectCategory.logoEditing,
    credit: 'Preview 2 Effects · $_wiki',
    heavy: true,
    video: seq([vf(rgbToBgr), reverseVideo]),
    audio: reverseAudio,
  ),
  Effect(
    id: 'invert_color',
    name: 'Invert Color',
    description: 'HSL Adjust\'s "Invert Color" preset: every hue turns to its opposite (brightness stays).',
    category: EffectCategory.logoEditing,
    credit: 'Preview 2 Effects #12 · $_wiki',
    keywords: const ['hue invert', 'hsl'],
    video: vf(hslInvert),
  ),
  Effect(
    id: 'grey_invert_high_reversed',
    name: 'Grey Invert + High Pitch + Reversed',
    description: 'Greyscale negative, one octave up, and backwards.',
    category: EffectCategory.logoEditing,
    credit: 'Preview 2 Effects · $_wiki',
    heavy: true,
    video: seq([vf('hue=s=0,negate'), reverseVideo]),
    audio: af('${pitch(12)},areverse'),
  ),
  Effect(
    id: 'tint_effect_1',
    name: 'Tint Effect 1',
    description: 'HSL add-to-hue 0.442 with a horizontal-only wave; pitch +10.',
    category: EffectCategory.logoEditing,
    credit: 'WimmiLeafyTheObjectThing941 (2023) · $_wiki',
    video: vf('${addToHue(0.442)},${wave(horizontalAmp: 0.03, waves: 3)}'),
    audio: af(pitch(10)),
  ),
  Effect(
    id: 'tint_effect_2',
    name: 'Tint Effect 2',
    description: 'HSL add-to-hue 0.136 with a Reflect Top mirror; pitch −2.',
    category: EffectCategory.logoEditing,
    credit: 'WimmiLeafyTheObjectThing941 (2023) · $_wiki',
    video: seq([vf(addToHue(0.136)), mirrorFx(MirrorSide.top)]),
    audio: af(pitch(-2)),
  ),
  Effect(
    id: 'v_major',
    name: 'V-Major',
    description: '100% Invert, HSL Invert Color and Reflect Right; tracks at −10, −6, +3 and +9.',
    category: EffectCategory.logoEditing,
    credit: 'V-Major · Vegas recipe · $_wiki',
    loud: true,
    video: seq([vf('negate,$hslInvert'), mirrorFx(MirrorSide.right)]),
    audio: chordFx(const [-10, -6, 3, 9]),
  ),
  Effect(
    id: 'you_wiggled',
    name: 'You Wiggled X',
    description: 'HSL add-to-hue 0.192, Reflect Left and 10-wave wiggles both ways; pitched up +14.',
    category: EffectCategory.logoEditing,
    credit: 'You Wiggled X · $_wiki',
    video: seq([
      vf(addToHue(0.192)),
      mirrorFx(MirrorSide.left),
      vf(wave(horizontalAmp: 0.02, verticalAmp: 0.02, waves: 10, speed: 5)),
    ]),
    audio: af(pitch(13.82404)),
  ),
  Effect(
    id: 'dma_diamond_major',
    name: 'DMA Diamond Major',
    description: 'A rotated diamond over a blurred negative; audio stacked at −9 and +3.',
    category: EffectCategory.logoEditing,
    credit: 'Ocean1000 (2016) · $_wiki',
    loud: true,
    video: (g, input, p, env) {
      final s = g.split(input, 2);
      final bg = g.v(s[0], 'boxblur=12:2,negate');
      final fg = g.v(s[1], 'scale=trunc(iw*0.62/2)*2:-2,format=rgba,rotate=PI/4:c=none:ow=rotw(PI/4):oh=roth(PI/4)');
      return g.join([bg, fg], 'overlay=(W-w)/2:(H-h)/2:format=auto');
    },
    audio: chordFx(const [-9, 3]),
  ),
  Effect(
    id: 'vocoded_intel',
    name: 'Vocoded with Intel Inside',
    description: 'A vocoded top layer blended in Difference mode over the source; robot voice mixed with the original.',
    category: EffectCategory.logoEditing,
    credit: 'tnt2005 (2015) · Preview 2 Effects · $_wiki',
    video: (g, input, p, env) {
      final s = g.split(input, 2);
      final top = g.v(s[1], '$hslInvert,eq=saturation=1.8');
      return g.join([s[0], top], 'blend=all_mode=difference');
    },
    audio: (g, input, p, env) {
      final s = g.split(input, 2, audio: true);
      final voc = g.a(s[1], '${robot(winSize: 512)},${pitch(7)}');
      return g.join([s[0], voc], 'amix=inputs=2:duration=first:normalize=0');
    },
  ),
  Effect(
    id: 'fat',
    name: 'Fat',
    description:
        'The picture puffs out from the middle (Height Map / S_WarpPuff); pitch −4 through a low-pass radio filter.',
    category: EffectCategory.logoEditing,
    credit: 'Fat X · $_wiki',
    video: vf(radial(1.7)),
    audio: af('${pitch(-4)},lowpass=f=1200:width_type=q:w=4,volume=4dB'),
  ),
  Effect(
    id: 'skinny',
    name: 'Skinny',
    description: 'The picture pinches in toward the middle (inverted Height Map / S_WarpPuff −0.15); audio unchanged.',
    category: EffectCategory.logoEditing,
    credit: 'Skinny X · $_wiki',
    video: vf(radial(0.6)),
  ),
  Effect(
    id: 'sick',
    name: 'Sick',
    description: 'Flipped horizontally, red only, TV Simulator line sync 0.75; pitched down two octaves and mangled.',
    category: EffectCategory.logoEditing,
    credit: 'Carlos Jethro Masa (2019) · Sick X · $_wiki',
    video: vf('hflip,$redOnly,${tvSimulator(lineSync: 0.75)}'),
    audio: af('${pitch(-12)},${pitch(-12)},${mangle(driveDb: 14)}'),
  ),
  Effect(
    id: 'i_killed',
    name: 'I KILLED X',
    description: 'HSL add-to-hue 0.628 and an AVS-style sphere; pitch −8.14 (AVS pitch 160).',
    category: EffectCategory.logoEditing,
    credit: 'I KILLED X (Losky) · $_wiki',
    video: vf('${addToHue(0.628)},${radial(1.6)}'),
    audio: af(pitch(-8.13686)),
  ),
  Effect(
    id: 'congabusher',
    name: 'Congabusher',
    description:
        'Hue rotated 232.653° with Reflect Right; the audio bitcrushed to 1/21 of its sample rate (or a 3 kHz AM).',
    category: EffectCategory.logoEditing,
    credit: 'Conga Busher · $_wiki',
    params: const [
      EffectParam.choice('audio', 'Audio', value: 'Bitcrusher', options: ['Bitcrusher', '3 kHz AM']),
    ],
    video: seq([vf(hue(232.653)), mirrorFx(MirrorSide.right)]),
    audio: (g, input, p, env) => g.a(
      input,
      p.choice('audio') == 'Bitcrusher' ? 'acrusher=bits=16:samples=21:mode=lin:aa=0:mix=1' : 'tremolo=f=3000:d=1',
    ),
  ),
  Effect(
    id: 'cursed_christmas_v2',
    name: 'Cursed Christmas V2',
    description: 'Red/green curve mangling on greyscale with a blown-out −12/+9 chord.',
    category: EffectCategory.logoEditing,
    credit: 'NotSoBot tag',
    loud: true,
    video: vf("hue=s=0,curves=r='0/1 0.333/0 0.667/1 1/0':g='0/1 0.333/1 0.667/0 1/0':b='0/1 0.333/0 0.667/0 1/0'"),
    audio: chordFx(const [-12, 9], post: 'volume=100,asoftclip=type=hard'),
  ),
  Effect(
    id: 'mirrored_and_slow',
    name: 'Mirrored and Slow',
    description: 'Reflect Left at 0.3× speed; the voice slowed down with the pitch at AVS 125 (−3.9).',
    category: EffectCategory.logoEditing,
    credit: _wiki,
    video: seq([vf(setpts(0.3)), mirrorFx(MirrorSide.left)]),
    audio: af('${atempo(0.3)},${pitch(-3.86)}'),
    outputSeconds: (p, s) => s / 0.3,
  ),
  Effect(
    id: 'low_g_major_voice',
    name: 'Low G-Major Voice',
    description:
        'Playback rate 0.25, 100% Invert, Reflect Right and a vertical wiggle; the slowed voice (−24) stacked '
        'into +12, +7, +4, 0, −5 and −12.',
    category: EffectCategory.logoEditing,
    credit: 'Low G-Major Voice · $_wiki',
    loud: true,
    video: seq([
      vf('${setpts(0.25)},negate'),
      mirrorFx(MirrorSide.right),
      vf(wave(horizontalAmp: 0, verticalAmp: 0.02, waves: 3, speed: 22)),
    ]),
    audio: chordFx(const [12, 7, 4, 0, -5, -12], pre: tapeSpeed(0.25)),
    outputSeconds: (p, s) => s / 0.25,
  ),
  Effect(
    id: 'split_luig_group',
    name: 'Split Luig Group',
    description:
        'G-Major 20: hue +0.194 at double saturation, Invert, flipped, wiggling both ways; tracks at −1 and 0.',
    category: EffectCategory.logoEditing,
    credit: 'G-Major 20 (Split Luig Group) · $_wiki',
    video: vf(
      '${addToHue(0.194, saturation: 2)},negate,hflip,${wave(horizontalAmp: 0.012, verticalAmp: 0.012, waves: 2, speed: 22)}',
    ),
    audio: chordFx(const [-1.00877, 0]),
  ),
];
