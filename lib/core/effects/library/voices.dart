import '../../ffmpeg/blocks.dart';
import '../effect.dart';
import 'helpers.dart';

const _wiki = 'Logo Editing Wiki';

/// IL Vocodex presets as the logo-editing community uses them: each one is
/// the preset's sound with the gradient map its wiki page gives.
///
/// Vocodex vocodes the voice onto a synth carrier. Here the voice is
/// robotized (FFT phase reset: a steady buzz shaped by the speech, which is
/// what a vocoder's carrier sounds like) and the preset's character is
/// built around it.
final List<Effect> vocodexEffects = [
  _vocodex(
    'vocodex_robot',
    'Robot (Vocodex)',
    'The Vocodex "Robot" preset: one steady robot buzz, with the Robot gradient map.',
    colors: const ['ff0000', '1efff8', '0000ff', '000000'],
    audio: af(robot(winSize: 1024)),
  ),
  _vocodex(
    'vocodex_helium',
    'Helium',
    'Vocodex "Helium": the vocoded voice an octave up and thin; green-to-blue gradient map.',
    credit: 'tnt2005 (2015)',
    colors: const ['00ff00', '00ffff', '0000ff'],
    audio: af('${robot(winSize: 512)},${pitch(12)},highpass=f=250'),
  ),
  _vocodex(
    'vocodex_elderly',
    'Elderly',
    'Vocodex "Elderly": a shaky, wavering vocoded voice; magenta-black-white-red gradient map.',
    credit: 'Lazy Butterfly (2015)',
    colors: const ['ff00ff', '000000', 'ffffff', 'ff0000'],
    audio: af('${robot(winSize: 1024)},${pitch(-2)},vibrato=f=5.5:d=0.45,lowpass=f=5000'),
  ),
  _vocodex(
    'vocodex_testosterone',
    'More Testosterone',
    'Vocodex "More testosterone": a deep vocoded voice an octave down with extra low end.',
    colors: const ['ff0000', '000000', '0000ff', '000000'],
    audio: af('${robot(winSize: 2048)},${pitch(-12)},bass=g=6:f=120'),
  ),
  _vocodex(
    'vocodex_group',
    'Group',
    'Vocodex "Group": a vocoded ensemble (detuned voices and an octave below); black-cyan-blue gradient map.',
    credit: 'MVEC296 (2015)',
    loud: true,
    colors: const ['000000', '00ffff', '0000ff', '000000'],
    audio: chordFx(const [-12, -0.15, 0, 0.15], pre: robot(winSize: 1024), post: softChorus),
  ),
  _vocodex(
    'vocodex_power',
    'Power',
    'Vocodex "Power": a thick, driven vocoded power chord; magenta-blue-cyan gradient map.',
    credit: 'MVEC296 (2015)',
    loud: true,
    colors: const ['ff00ff', '0000ff', '00ffff'],
    audio: chordFx(const [0, 7, 12], pre: robot(winSize: 1024), post: 'asoftclip=type=atan'),
  ),
  Effect(
    id: 'vocodex_old_school',
    name: 'Old School',
    description:
        'Vocodex "Old school": a band-limited, crunchy 80s vocoder; luminosity inverted with a swirl that winds '
        'one way then the other and TV Simulator tearing.',
    category: EffectCategory.vocoder,
    credit: 'Jamie Shaffer · $_wiki',
    keywords: const ['vocodex', 'vocoder', '80s'],
    video: (g, input, p, env) => g.v(input, '$invertLuminosity,${swirl(strength: 2.5)},${tvSimulator(lineSync: 0.75)}'),
    audio: af('${robot(winSize: 2048)},highpass=f=300,lowpass=f=3200,acrusher=bits=8:mode=log:aa=1:mix=0.5'),
  ),
  _vocodex(
    'vocodex_clearer',
    'Clearer',
    'Vocodex "Clearer": the vocoder with the natural voice blended back in so every word is clear.',
    colors: const ['ff1e1e', '0f31ff', '00d20c', 'ff4beb', '2dffff', 'ffff00', '000000', '960072'],
    audio: (g, input, p, env) {
      final s = g.split(input, 2, audio: true);
      final voc = g.a(s[1], '${robot(winSize: 1024)},treble=g=4');
      return g.join([s[0], voc], 'amix=inputs=2:duration=first:normalize=0');
    },
  ),
  Effect(
    id: 'vocodex_backing_voices',
    name: 'Backing Voices',
    description: 'Vocodex "Backing voices": your voice up front with a quiet vocoded choir (−5, +4, +7) behind it.',
    category: EffectCategory.vocoder,
    credit: _wiki,
    keywords: const ['vocodex', 'vocoder', 'harmony', 'choir'],
    audio: (g, input, p, env) {
      final s = g.split(input, 2, audio: true);
      final choir = chord(g, g.a(s[1], robot(winSize: 1024)), const [-5, 4, 7], sampleRate: env.sampleRate);
      final back = g.a(choir, 'volume=-9dB,$softChorus');
      return g.join([s[0], back], 'amix=inputs=2:duration=first:normalize=0');
    },
  ),
  _vocodex(
    'vocodex_droplets',
    'Droplets',
    'Vocodex "Droplets": a bubbling, dripping vocoded voice; yellow-magenta-blue-green-white gradient map.',
    colors: const ['ffff00', 'ff00ff', '0000ff', '00ff00', 'ffffff'],
    audio: af('${robot(winSize: 256)},tremolo=f=11:d=0.7,aecho=0.8:0.6:45|90:0.4|0.25'),
  ),
  _vocodex(
    'vocodex_autovocoding',
    'Autovocoding',
    'Vocodex "Autovocoding": the voice vocoded onto itself, so it keeps its own melody with a synthetic edge.',
    colors: const ['0000ff', '00ff00', '000000', 'ffffff'],
    audio: (g, input, p, env) {
      final s = g.split(input, 2, audio: true);
      final voc = g.a(s[1], '${robot(winSize: 512)},aphaser=type=t:speed=0.5:decay=0.4');
      return g.join([g.a(s[0], 'volume=-3dB'), voc], 'amix=inputs=2:duration=first:normalize=0');
    },
  ),
  Effect(
    id: 'vocodex_reverb',
    name: 'Reverb (Vocodex)',
    description: 'Vocodex "Reverb": the vocoded voice in a big hall; a black-blue-white gradient map.',
    category: EffectCategory.vocoder,
    credit: _wiki,
    keywords: const ['vocodex', 'vocoder'],
    video: vf(gradientMapStops(const [(0, '000000'), (0.216, '6375e1'), (0.649, 'ffffff')])),
    audio: af('${robot(winSize: 1024)},${reverb(wet: 0.85)}'),
  ),
  _vocodex(
    'vocodex_for_drums',
    'For Drums',
    'Vocodex "For drums": a short, gated, punchy vocoder; red-black-cyan gradient map.',
    colors: const ['ff0000', '000000', '00ffff'],
    audio: af(
      '${robot(winSize: 256)},agate=threshold=0.05:ratio=8:attack=1:release=60,'
      'acompressor=threshold=0.1:ratio=4:attack=2:release=80:makeup=2',
    ),
  ),
];

Effect _vocodex(
  String id,
  String name,
  String description, {
  required List<String> colors,
  required StreamBuilder audio,
  String? credit,
  bool loud = false,
}) => Effect(
  id: id,
  name: name,
  description: description,
  category: EffectCategory.vocoder,
  credit: credit == null ? 'IL Vocodex · $_wiki' : '$credit · IL Vocodex · $_wiki',
  loud: loud,
  keywords: const ['vocodex', 'vocoder', 'il vocodex'],
  video: vf(gradientMapEven(colors)),
  audio: audio,
);

/// Voice changer favourites (TikTok / CapCut / Discord soundboard style).
final List<Effect> voiceEffects = [
  _voice(
    'giant',
    'Giant',
    'A huge, booming voice: ten semitones down with room around it.',
    '${pitch(-10)},lowpass=f=6000,aecho=0.8:0.5:60:0.25',
    keywords: const ['big', 'deep'],
  ),
  _voice(
    'baby',
    'Baby',
    'A small, high voice: up six semitones, thin and bright.',
    '${pitch(6)},highpass=f=180,treble=g=3',
    keywords: const ['kid', 'child', 'high'],
  ),
  _voice(
    'monster',
    'Monster',
    'A growling monster: an octave and a fifth below, mixed and roughed up.',
    null,
    chordAudio: chordFx(const [-12, -7], perVoice: mangle(driveDb: 6, bits: 12)),
    keywords: const ['beast'],
  ),
  _voice(
    'demon',
    'Demon',
    'Your voice with an octave-down double in a dark reverb.',
    null,
    chordAudio: chordFx(const [-12, 0], post: '${reverb(wet: 0.5)},lowpass=f=7000'),
    keywords: const ['evil', 'devil'],
  ),
  _voice(
    'old_man',
    'Old Man',
    'A trembling, slightly lower, dull voice.',
    '${pitch(-1)},vibrato=f=5:d=0.35,lowpass=f=4500',
    keywords: const ['elderly', 'grandpa'],
  ),
  _voice(
    'radio',
    'Radio',
    'An AM radio: narrow band, a little crushed.',
    'highpass=f=400,lowpass=f=3400,acrusher=bits=10:mode=log:aa=1:mix=0.4,volume=3dB',
    keywords: const ['am', 'broadcast'],
  ),
  _voice(
    'walkie_talkie',
    'Walkie-Talkie',
    'A cheap handheld radio: very narrow, gritty and squashed.',
    'highpass=f=600,lowpass=f=2600,${mangle(driveDb: 10, bits: 6)},acompressor=threshold=0.05:ratio=8:makeup=4',
    keywords: const ['two-way', 'cb', 'police radio'],
  ),
  _voice(
    'cave',
    'Cave',
    'Long, dark echoes bouncing off rock.',
    'aecho=0.8:0.85:450|820|1300:0.5|0.35|0.2,lowpass=f=5000',
    keywords: const ['echo', 'canyon'],
  ),
  _voice(
    'stadium',
    'Stadium Announcer',
    'A big PA in a stadium: compressed, bright and echoing.',
    'acompressor=threshold=0.08:ratio=6:makeup=4,highpass=f=150,treble=g=4,aecho=0.8:0.7:180|360:0.4|0.25',
    keywords: const ['announcer', 'pa', 'arena'],
  ),
  _voice(
    'drunk',
    'Drunk',
    'A woozy, wobbling voice.',
    'vibrato=f=1.3:d=0.8,$softChorus',
    keywords: const ['dizzy', 'woozy'],
  ),
  _voice(
    'dark_lord',
    'Dark Lord',
    'A deep, masked, breathy villain voice.',
    '${pitch(-5)},bass=g=8:f=110,highpass=f=70,lowpass=f=5000,acompressor=threshold=0.1:ratio=5:makeup=3,'
        'aecho=0.6:0.4:25:0.3',
    keywords: const ['villain', 'mask', 'helmet'],
  ),
  _voice(
    'helium_squeak',
    'Helium Balloon',
    'A squeaky helium voice: an octave up.',
    '${pitch(12)},highpass=f=200',
    keywords: const ['squeaky', 'chipmunk'],
  ),
  Effect(
    id: 'cartoon',
    name: 'Cartoon',
    description: 'A fast, high cartoon voice: tape sped up 1.4×.',
    category: EffectCategory.voice,
    keywords: const ['toon', 'fast'],
    video: vf(setpts(1.4)),
    audio: af(tapeSpeed(1.4)),
    outputSeconds: (p, s) => s / 1.4,
  ),
  Effect(
    id: 'slow_mo_voice',
    name: 'Slow-Mo',
    description: 'The slow-motion voice: tape slowed to 0.6×, deep and dragging.',
    category: EffectCategory.voice,
    keywords: const ['slow motion', 'deep'],
    video: vf(setpts(0.6)),
    audio: af(tapeSpeed(0.6)),
    outputSeconds: (p, s) => s / 0.6,
  ),
  _voice(
    'space_radio',
    'Space Radio',
    'A transmission from orbit: frequency-shifted, narrow and flanged.',
    'afreqshift=shift=90,highpass=f=500,lowpass=f=3000,flanger=delay=2:depth=4:speed=0.4',
    keywords: const ['astronaut', 'transmission', 'nasa'],
  ),
  _voice(
    'in_a_can',
    'In a Can',
    'Your voice from inside a tin can.',
    'highpass=f=900,lowpass=f=4000,aecho=0.9:0.8:4|7:0.6|0.5',
    keywords: const ['tin', 'metal'],
  ),
];

Effect _voice(
  String id,
  String name,
  String description,
  String? chain, {
  StreamBuilder? chordAudio,
  List<String> keywords = const [],
}) => Effect(
  id: id,
  name: name,
  description: description,
  category: EffectCategory.voice,
  keywords: keywords,
  audio: chordAudio ?? af(chain!),
);

/// Pitch and chord effects: harmonies, doublers and wobbles.
final List<Effect> pitchChordEffects = [
  Effect(
    id: 'harmonizer',
    name: 'Harmonizer',
    description: 'Your voice with a harmony part: pick the interval.',
    category: EffectCategory.gMajor,
    keywords: const ['harmony', 'interval'],
    params: const [
      EffectParam.choice(
        'interval',
        'Harmony',
        value: 'Major third (+4)',
        options: [
          'Minor third (+3)',
          'Major third (+4)',
          'Fourth (+5)',
          'Fifth (+7)',
          'Octave (+12)',
          'Third below (−4)',
        ],
      ),
    ],
    audio: (g, input, p, env) {
      final v = switch (p.choice('interval')) {
        'Minor third (+3)' => 3.0,
        'Fourth (+5)' => 5.0,
        'Fifth (+7)' => 7.0,
        'Octave (+12)' => 12.0,
        'Third below (−4)' => -4.0,
        _ => 4.0,
      };
      return chord(g, input, [0, v], sampleRate: env.sampleRate);
    },
  ),
  Effect(
    id: 'doubler',
    name: 'Doubler',
    description: 'A thicker voice: two copies a hair sharp and flat, spread left and right.',
    category: EffectCategory.gMajor,
    keywords: const ['double', 'detune', 'thick'],
    audio: (g, input, p, env) {
      final s = g.split(input, 3, audio: true);
      final up = g.a(s[1], '${pitch(0.12)},adelay=12|0,pan=stereo|c0=c0|c1=0.3*c1');
      final down = g.a(s[2], '${pitch(-0.12)},adelay=0|20,pan=stereo|c0=0.3*c0|c1=c1');
      return g.join([s[0], up, down], 'amix=inputs=3:duration=first:normalize=0');
    },
  ),
  Effect(
    id: 'barbershop',
    name: 'Barbershop Quartet',
    description: 'Four voices in close harmony: a dominant seventh (−12, +4, +7, +10).',
    category: EffectCategory.gMajor,
    loud: true,
    keywords: const ['quartet', 'choir', 'harmony'],
    audio: chordFx(const [-12, 4, 7, 10], gain: 0.8),
  ),
  Effect(
    id: 'sus4_chord',
    name: 'Sus4 Chord',
    description: 'An open, unresolved 0/+5/+7 chord.',
    category: EffectCategory.gMajor,
    loud: true,
    audio: chordFx(const [0, 5, 7]),
  ),
  Effect(
    id: 'major_seventh',
    name: 'Major Seventh',
    description: 'A dreamy 0/+4/+7/+11 chord with a soft chorus.',
    category: EffectCategory.gMajor,
    loud: true,
    video: vf('eq=saturation=1.2,gblur=sigma=1.2'),
    audio: chordFx(const [0, 4, 7, 11], post: softChorus),
  ),
  Effect(
    id: 'augmented',
    name: 'Augmented',
    description: 'An eerie 0/+4/+8 augmented chord.',
    category: EffectCategory.gMajor,
    loud: true,
    audio: chordFx(const [0, 4, 8]),
  ),
  Effect(
    id: 'whole_tone',
    name: 'Whole Tone Cluster',
    description: 'A dreamlike cluster of whole steps (0, +2, +4, +6).',
    category: EffectCategory.gMajor,
    loud: true,
    audio: chordFx(const [0, 2, 4, 6]),
  ),
  Effect(
    id: 'pitch_wobble',
    name: 'Pitch Wobble',
    description: 'The pitch bends up and down: speed and depth are yours.',
    category: EffectCategory.audio,
    keywords: const ['vibrato', 'warble', 'bend'],
    params: const [
      EffectParam.decimal('rate', 'Speed', value: 3, min: 0.5, max: 12, step: 0.5, unit: 'Hz'),
      EffectParam.decimal('depth', 'Depth', value: 0.6, min: 0.1, max: 1, step: 0.05),
    ],
    audio: (g, input, p, env) => g.a(input, 'vibrato=f=${fmt(p.decimal('rate'))}:d=${fmt(p.decimal('depth'))}'),
  ),
];
