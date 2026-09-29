import '../../ffmpeg/blocks.dart';
import '../effect.dart';
import 'helpers.dart';

final List<Effect> gMajorEffects = [
  Effect(
    id: 'g_major_2',
    name: 'G-Major 2',
    description: 'Inverted picture with the audio duplicated into −5, 0 and +4 tracks.',
    category: EffectCategory.gMajor,
    credit: 'Gecile2000 (Feb 2014) · Logo Editing Wiki',
    loud: true,
    video: vf('negate'),
    audio: chordFx(const [-5, 0, 4]),
  ),
  Effect(
    id: 'g_major_4',
    name: 'G-Major 4',
    description: 'Color Correction hue 144 at full saturation with a −4/0/+4 chord — "Klasky Csupo in G-Major 4".',
    category: EffectCategory.gMajor,
    credit: 'Gecile2000 (Mar 2014) · Logo Editing Wiki',
    loud: true,
    video: vf(hue(144, saturation: 2)),
    audio: chordFx(const [-4, 0, 4]),
  ),
  Effect(
    id: 'g_major_kyoobur9000',
    name: 'G-Major (Kyoobur9000)',
    description: 'Red-only greyscale with a tangent wobble; four-voice chord at −23, −13, −7 and +4.',
    category: EffectCategory.gMajor,
    credit: 'Kyoobur9000 · NotSoBot tag',
    loud: true,
    video: vf(
      'hue=s=0,colorchannelmixer=rr=1:rg=0:rb=0:gr=0:gg=0.12:gb=0:br=0:bg=0:bb=0.12,'
      "geq='p(X,Y+H*0.02*tan(sin(T*10+X*0.01)*1.2))'",
    ),
    audio: chordFx(const [-23, -13, -7, 4], gain: 4),
  ),
  Effect(
    id: 'g_major_adrian_sparino_v2',
    name: 'G-Major (Adrian Sparino V2)',
    description: 'Negative image; tritone-heavy chord at −12, −6, +6 and +12.',
    category: EffectCategory.gMajor,
    credit: 'Adrian Sparino · NotSoBot tag',
    loud: true,
    video: vf('negate'),
    audio: chordFx(const [-12, -6, 6, 12], gain: 3),
  ),
  Effect(
    id: 'g_major_2_ltv_mca',
    name: 'G-Major 2 (LTV MCA)',
    description: 'Red kept, green/blue inverted; five voices from −12 up to +12.',
    category: EffectCategory.gMajor,
    credit: 'LTV MCA · NotSoBot tag',
    loud: true,
    video: vf('lutrgb=g=negval:b=negval'),
    audio: chordFx(const [7, 12, 4, -5, -12], gain: 4),
  ),
  Effect(
    id: 'g_major_3_ltv_mca',
    name: 'G-Major 3 (LTV MCA)',
    description: 'Pure red with chroma waves; −6/−12 voices plus 34 ms and 68 ms slap echoes.',
    category: EffectCategory.gMajor,
    credit: 'LTV MCA · NotSoBot tag',
    loud: true,
    video: vf(
      'colorchannelmixer=rr=1:rg=0:rb=0:gr=0:gg=0:gb=0:br=0:bg=0:bb=0,'
      "geq=lum='lum(X,Y)':cb='cb(X,Y)+10*sin(Y/15+T*4.5)':cr='cr(X,Y)'",
    ),
    audio: (g, input, p, env) {
      final s = g.split(input, 4, audio: true);
      final a1 = g.a(s[0], pitch(-6));
      final a2 = g.a(s[1], pitch(-12));
      final d1 = g.a(s[2], 'adelay=34|34');
      final d2 = g.a(s[3], 'adelay=68|68');
      return g.join([a1, d1, a2, d2], 'amix=inputs=4:duration=first:normalize=0,volume=3');
    },
  ),
  Effect(
    id: 'g_major_alapat1',
    name: 'G-Major (Alapat1)',
    description: 'Rainbow hue cycle with the original voice doubled a fifth below.',
    category: EffectCategory.gMajor,
    credit: 'Alapat1 · NotSoBot tag',
    loud: true,
    video: vf('hue=h=t*60:s=1.2'),
    audio: chordFx(const [0, -7], gain: 1.5),
  ),
  Effect(
    id: 'jctotboi_g_major',
    name: 'JCTOTBOI G-Major',
    description: 'Blue channel flipped with a rainbow cycle; voices at −2, +9 and +14.',
    category: EffectCategory.gMajor,
    credit: 'JCTOTBOI (June 23rd 2023) · NotSoBot tag',
    loud: true,
    video: vf('lutrgb=b=negval,hue=h=t*60'),
    audio: chordFx(const [-2, 9, 14], gain: 2.25),
  ),
  Effect(
    id: 'blue_distorted_pitches',
    name: 'Blue Distorted Pitches',
    description: 'Blue tint with chroma waves; an octave-down and +1 voice mixed hot.',
    category: EffectCategory.gMajor,
    credit: 'NotSoBot tag',
    loud: true,
    video: vf("colorbalance=bs=1:bm=0.8:bh=0.6,geq=lum='lum(X,Y)':cb='cb(X,Y)+5*sin(Y/10+T*3)':cr='cr(X,Y)'"),
    audio: chordFx(const [-12, 1], gain: 2),
  ),
  Effect(
    id: 'chord_builder',
    name: 'Chord Builder',
    description: 'Make your own G-Major: list the pitches of each duplicated track and pick a look.',
    category: EffectCategory.gMajor,
    loud: true,
    keywords: const ['custom', 'pitches', 'g major'],
    params: const [
      EffectParam.text('pitches', 'Track pitches', value: '-12, 0, 4, 7', hint: 'Semitones, comma separated (max 16)'),
      EffectParam.choice(
        'look',
        'Look',
        value: 'Invert',
        options: ['None', 'Invert', 'Hue 144', 'Rainbow', 'RGB to BGR', 'Luig Group'],
      ),
      EffectParam.decimal('gain', 'Mix gain', value: 1.0, min: 0.25, max: 4.0, step: 0.05, unit: '×'),
    ],
    video: (g, input, p, env) {
      final look = switch (p.choice('look')) {
        'Invert' => 'negate',
        'Hue 144' => hue(144, saturation: 2),
        'Rainbow' => 'hue=h=t*90:s=1.4',
        'RGB to BGR' => rgbToBgr,
        'Luig Group' => hslInvert,
        _ => 'null',
      };
      return g.v(input, look);
    },
    audio: (g, input, p, env) {
      final list = parsePitchList(p.text('pitches'));
      return chord(g, input, list.isEmpty ? const [0] : list, sampleRate: env.sampleRate, gain: p.decimal('gain'));
    },
  ),
  Effect(
    id: 'major_chord',
    name: 'Major Chord',
    description: 'Root, major third and fifth (0/+4/+7) with a warm glow.',
    category: EffectCategory.gMajor,
    loud: true,
    video: seq([vf('eq=saturation=1.4:gamma=1.05'), raysFx()]),
    audio: chordFx(const [0, 4, 7]),
  ),
  Effect(
    id: 'minor_chord',
    name: 'Minor Chord',
    description: 'Moody 0/+3/+7 minor triad over a cold, desaturated picture.',
    category: EffectCategory.gMajor,
    loud: true,
    video: vf('eq=saturation=0.4:contrast=1.2,colorbalance=bs=0.3:bm=0.2:rs=-0.2'),
    audio: chordFx(const [0, 3, 7]),
  ),
  Effect(
    id: 'diminished_horror',
    name: 'Diminished Horror',
    description: 'Stacked minor thirds (0/+3/+6/+9) on a blood-red, crushed image.',
    category: EffectCategory.gMajor,
    loud: true,
    video: vf("${tint('8b0000', amount: 0.8)},curves=all='0/0 0.5/0.3 1/0.9',vignette=PI/3"),
    audio: chordFx(const [0, 3, 6, 9], gain: 1.2),
  ),
  Effect(
    id: 'octave_stack',
    name: 'Octave Stack',
    description: 'The voice an octave below and above at the same time; mirrored four ways.',
    category: EffectCategory.gMajor,
    loud: true,
    video: kaleidoscopeFx(),
    audio: chordFx(const [-12, 0, 12]),
  ),
  Effect(
    id: 'power_chord',
    name: 'Power Chord',
    description: 'Distorted 0/+7/+12 power chord with a punchy high-contrast look.',
    category: EffectCategory.gMajor,
    loud: true,
    video: vf('eq=contrast=1.6:saturation=1.5,unsharp=5:5:1.5'),
    audio: chordFx(const [0, 7, 12], perVoice: mangle(driveDb: 10, bits: 10)),
  ),
];
