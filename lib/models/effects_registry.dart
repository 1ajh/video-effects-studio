import 'effect_mode.dart';

/// Registry of all available video effects
class EffectsRegistry {
  static final List<EffectMode> allEffects = [
    // ===== VOCODER EFFECTS =====
    EffectMode(
      id: 'purple_vocoder',
      name: 'Purple Vocoder',
      description: 'Autotuned audio with purple color overlay',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "colorbalance=rs=0.5:gs=-0.5:bs=0.5" -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'techno',
      name: 'Techno',
      description: 'Blue-tinted techno vocoder effect',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "colorchannelmixer=rr=0:rg=0:rb=1:gr=0:gg=0:gb=1:br=0:bg=1:bb=0" -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'gansta',
      name: 'Gansta',
      description: 'Blue-tinted gangsta vocoder effect',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=s=0,colorbalance=bs=1:bm=0.5:bh=0.5" -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'xtal_vocoder',
      name: 'Xtal Vocoder',
      description: 'Crystal-style vocoder with blue tint',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=s=0,colorbalance=bs=1:bm=0.5:bh=0.5" -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'daft_vocoder',
      name: 'Daft Vocoder',
      description: 'Daft Punk style green vocoder',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=s=0,colorbalance=gs=1:gm=0.8:gh=0.5" -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'electric',
      name: 'Electric',
      description: 'Electric vocoder with LUT color grading',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "curves=vintage" -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'capcut_robot',
      name: 'CapCut Robot Effect',
      description: 'Robot voice with wavy visuals',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "geq=lum='lum(X,Y)':cb='cb(X,Y)+10*sin(2*PI*X/30+T*5)':cr='cr(X,Y)+10*sin(2*PI*Y/30+T*5)'" -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'white_robotic_dimension',
      name: 'White Robotic Dimension',
      description: 'White-washed robotic vocoder',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "curves=lighter" -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'discord_electronic',
      name: 'Discord Electronic Sounds',
      description: 'Discord-themed electronic vocoder',
      category: EffectCategory.vocoder,
      requiresDesktop: true,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=s=0,colorbalance=bs=0.8:bm=0.6:rs=0.3:rm=0.3" -c:a aac "$output"
''',
    ),

    // ===== COLOR GRADING =====
    EffectMode(
      id: 'loud_rainbow',
      name: 'Loud Rainbow',
      description: 'Rainbow hue shift with boosted audio',
      category: EffectCategory.colorGrade,
      parameters: [
        EffectParameter(
          id: 'speed',
          name: 'Rainbow Speed',
          type: ParameterType.decimal,
          defaultValue: 1.0,
          minValue: 0.1,
          maxValue: 5.0,
        ),
      ],
      buildCommand: (input, output, params) {
        double speed = params['speed'] ?? 1.0;
        return '''
ffmpeg -i "$input" -vf "hue=h=t*${speed * 60}:s=1.5" -af "volume=2" -c:v libx264 -c:a aac "$output"
''';
      },
    ),

    EffectMode(
      id: 'fast_color',
      name: 'Fast Color',
      description: 'Speed up video with rainbow hue shift',
      category: EffectCategory.colorGrade,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "setpts=PTS/1.5,hue=h=t*60:s=1.5" -af "atempo=1.5,rubberband=pitch=1.5" -c:v libx264 -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'blue_distorted_pitches',
      name: 'Blue Distorted Pitches',
      description: 'Blue tint with pitch-shifted audio and waves',
      category: EffectCategory.colorGrade,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "colorbalance=bs=1:bm=0.8:bh=0.6,geq=lum='lum(X,Y)':cb='cb(X,Y)+5*sin(Y/10+T*3)':cr='cr(X,Y)'" -filter_complex "[0:a]rubberband=pitch=0.5[a1];[0:a]rubberband=pitch=1.06[a2];[a1][a2]amix=2,volume=2[outa]" -map 0:v -map "[outa]" -c:v libx264 -c:a aac "$output"
''',
    ),

    // ===== GLITCH & DISTORTION =====
    EffectMode(
      id: 'g_major_kyoobur9000',
      name: 'G Major Kyoobur9000',
      description: 'Classic Kyoobur9000 G Major effect',
      category: EffectCategory.glitch,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=s=0,colorchannelmixer=rr=0.3:rg=0:rb=0:gr=0:gg=0:gb=0:br=0:bg=0:bb=0,geq='p(X,abs(Y+tan(sin(T*10+X*0.01)*50)))'" -filter_complex "[0:a]rubberband=pitch=0.265[a1];[0:a]rubberband=pitch=0.472[a2];[0:a]rubberband=pitch=0.667[a3];[0:a]rubberband=pitch=1.26[a4];[a1][a2][a3][a4]amix=4,volume=4[outa]" -map 0:v -map "[outa]" -c:v libx264 -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'g_major_adrian_sparino_v2',
      name: 'G Major Adrian Sparino V2',
      description: 'Adrian Sparino style G Major',
      category: EffectCategory.glitch,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "negate" -filter_complex "[0:a]rubberband=pitch=0.5[a1];[0:a]rubberband=pitch=0.707[a2];[0:a]rubberband=pitch=1.414[a3];[0:a]rubberband=pitch=2[a4];[a1][a2][a3][a4]amix=4,volume=3[outa]" -map 0:v -map "[outa]" -c:v libx264 -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'g_major_2_ltv_mca',
      name: 'G Major 2 LTV MCA',
      description: 'LTV MCA style G Major 2',
      category: EffectCategory.glitch,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "colorchannelmixer=rr=1:rg=0:rb=0:gr=0:gg=-1:gb=0:br=0:bg=0:bb=-1" -filter_complex "[0:a]rubberband=pitch=1.498[a1];[0:a]rubberband=pitch=2[a2];[0:a]rubberband=pitch=1.26[a3];[0:a]rubberband=pitch=0.749[a4];[0:a]rubberband=pitch=0.5[a5];[a1][a2][a3][a4][a5]amix=5,volume=4[outa]" -map 0:v -map "[outa]" -c:v libx264 -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'g_major_3_ltv_mca',
      name: 'G Major 3 LTV MCA',
      description: 'LTV MCA style G Major 3 with waves',
      category: EffectCategory.glitch,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "colorchannelmixer=rr=1:rg=0:rb=0:gr=0:gg=0:gb=0:br=0:bg=0:bb=0,geq=lum='lum(X,Y)':cb='cb(X,Y)+10*sin(Y/15+T*4.5)':cr='cr(X,Y)'" -filter_complex "[0:a]rubberband=pitch=0.707[a1];[0:a]rubberband=pitch=0.5[a2];[0:a]adelay=34|34[a1d];[0:a]adelay=68|68[a2d];[a1][a1d][a2][a2d]amix=4,volume=3[outa]" -map 0:v -map "[outa]" -c:v libx264 -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'g_major_alapat1',
      name: 'G Major Alapat1',
      description: 'Alapat1 style G Major with rainbow',
      category: EffectCategory.glitch,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=h=t*60:s=1.2" -filter_complex "[0:a]rubberband=pitch=0.667[a1];[0:a]amix=inputs=1[orig];[orig][a1]amix=2,volume=1.5[outa]" -map 0:v -map "[outa]" -c:v libx264 -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'congabusher',
      name: 'Congabusher',
      description: 'Mirrored with extreme tremolo',
      category: EffectCategory.glitch,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=h=232.653,hflip,crop=iw/2:ih:0:0,pad=iw*2:ih:0:0[left];[left]hflip[right];[left][right]overlay=W/2:0" -af "tremolo=f=3000:d=1,tremolo=f=3000:d=1,tremolo=f=3000:d=1" -c:v libx264 -c:a aac "$output"
''',
    ),

    // ===== CURSED EFFECTS =====
    EffectMode(
      id: 'cursed_christmas_v2',
      name: 'Cursed Christmas V2',
      description: 'Recursive Christmas color effect with chord',
      category: EffectCategory.glitch,
      parameters: [
        EffectParameter(
          id: 'iterations',
          name: 'Iterations',
          type: ParameterType.integer,
          defaultValue: 25,
          minValue: 1,
          maxValue: 50,
        ),
        EffectParameter(
          id: 'duration',
          name: 'Segment Duration (sec)',
          type: ParameterType.decimal,
          defaultValue: 1.0,
          minValue: 0.1,
          maxValue: 5.0,
        ),
      ],
      buildCommand: (input, output, params) {
        double duration = params['duration'] ?? 1.0;
        return '''
ffmpeg -i "$input" -vf "hue=s=0,curves=r='0/1 0.333/0 0.667/1 1/0':g='0/1 0.333/1 0.667/0 1/0':b='0/1 0.333/0 0.667/0 1/0',format=yuv420p" -filter_complex "[0:a]rubberband=pitch=0.5[a1];[0:a][a1]amix=2;[0:a]rubberband=pitch=1.682[a2];amix=inputs=2,volume=100" -t $duration -c:v libx264 -c:a aac "$output"
''';
      },
    ),

    EffectMode(
      id: 'jctotboi_g_major',
      name: 'JCTOTBOI G Major June 23rd 2023',
      description: 'JCTOTBOI style G Major with rainbow',
      category: EffectCategory.glitch,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "colorchannelmixer=rr=1:rg=0:rb=0:gr=0:gg=1:gb=0:br=0:bg=0:bb=-1,hue=h=t*60" -filter_complex "[0:a]rubberband=pitch=0.891[a1];[0:a]rubberband=pitch=1.682[a2];[0:a]rubberband=pitch=2.245[a3];[a1][a2][a3]amix=3,volume=2.25[outa]" -map 0:v -map "[outa]" -c:v libx264 -c:a aac "$output"
''',
    ),

    // ===== AUDIO EFFECTS =====
    EffectMode(
      id: 'pitch_shift',
      name: 'Pitch Shift',
      description: 'Shift audio pitch by semitones',
      category: EffectCategory.audio,
      parameters: [
        EffectParameter(
          id: 'semitones',
          name: 'Semitones',
          type: ParameterType.integer,
          defaultValue: 0,
          minValue: -12,
          maxValue: 12,
        ),
      ],
      buildCommand: (input, output, params) {
        int semitones = params['semitones'] ?? 0;
        double pitchFactor = _semitoneToPitch(semitones);
        return '''
ffmpeg -i "$input" -af "rubberband=pitch=$pitchFactor" -c:v copy -c:a aac "$output"
''';
      },
    ),

    EffectMode(
      id: 'pitch_maker',
      name: 'Pitch Maker',
      description: 'Creates autotuned pitch effect (desktop only)',
      category: EffectCategory.audio,
      requiresDesktop: true,
      parameters: [
        EffectParameter(
          id: 'output_format',
          name: 'Output Format',
          type: ParameterType.dropdown,
          defaultValue: 'mp4',
          options: ['mp4', 'wav'],
        ),
      ],
      buildCommand: (input, output, params) {
        String format = params['output_format'] ?? 'mp4';
        if (format == 'wav') {
          return '''
ffmpeg -i "$input" -vn -acodec pcm_s16le -ar 48000 -ac 1 "$output"
''';
        }
        return '''
ffmpeg -i "$input" -c:v libx264 -c:a aac "$output"
''';
      },
    ),

    // ===== YTPMV TOOLS =====
    EffectMode(
      id: 'sparta_pitch',
      name: 'Sparta Pitch',
      description: 'Create Sparta remix style pitch sequences',
      category: EffectCategory.ytpmv,
      parameters: [
        EffectParameter(
          id: 'pitches',
          name: 'Pitch Sequence (comma separated)',
          type: ParameterType.text,
          defaultValue: '0,0,7,0',
        ),
        EffectParameter(
          id: 'beat_duration',
          name: 'Beat Duration',
          type: ParameterType.dropdown,
          defaultValue: '1/4',
          options: ['1/2', '1/4', '1/8'],
        ),
      ],
      buildCommand: (input, output, params) {
        String pitches = params['pitches'] ?? '0,0,7,0';
        String beat = params['beat_duration'] ?? '1/4';
        double beatDur = beat == '1/2' ? 0.5 : (beat == '1/8' ? 0.125 : 0.25);
        
        List<String> pitchList = pitches.split(',').map((e) => e.trim()).toList();
        StringBuffer filterComplex = StringBuffer();
        
        for (int i = 0; i < pitchList.length; i++) {
          int semitone = int.tryParse(pitchList[i]) ?? 0;
          double pitch = _semitoneToPitch(semitone);
          filterComplex.write('[0:a]rubberband=pitch=$pitch,atrim=0:$beatDur,asetpts=PTS-STARTPTS[a$i];');
        }
        
        filterComplex.write(pitchList.asMap().entries.map((e) => '[a${e.key}]').join());
        filterComplex.write('concat=n=${pitchList.length}:v=0:a=1[outa]');
        
        return '''
ffmpeg -i "$input" -filter_complex "${filterComplex.toString()}" -map 0:v -map "[outa]" -c:v libx264 -c:a aac -shortest "$output"
''';
      },
    ),

    // ===== OTHER =====
    EffectMode(
      id: 'diamond_video',
      name: 'Diamond Video',
      description: 'Four-way rotated overlay effect',
      category: EffectCategory.other,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -filter_complex "[0:v]scale=720:480[base];[0:v]scale=360:240,rotate=PI:c=none[r1];[0:v]scale=360:240,rotate=PI/2:c=none[r2];[0:v]scale=360:240,rotate=-PI/2:c=none[r3];[0:v]scale=360:240[r4];[base][r1]overlay=180:120:format=auto[t1];[t1][r2]overlay=0:0:format=auto[t2];[t2][r3]overlay=360:0:format=auto[t3];[t3][r4]overlay=180:240:format=auto" -c:v libx264 -c:a aac "$output"
''',
    ),

    // ===== ADDITIONAL EFFECTS =====
    EffectMode(
      id: 'mirror_horizontal',
      name: 'Mirror Horizontal',
      description: 'Mirror video horizontally',
      category: EffectCategory.other,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hflip" -c:v libx264 -c:a copy "$output"
''',
    ),

    EffectMode(
      id: 'mirror_vertical',
      name: 'Mirror Vertical',
      description: 'Mirror video vertically',
      category: EffectCategory.other,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "vflip" -c:v libx264 -c:a copy "$output"
''',
    ),

    EffectMode(
      id: 'reverse_video',
      name: 'Reverse Video',
      description: 'Play video in reverse',
      category: EffectCategory.other,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "reverse" -af "areverse" -c:v libx264 -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'speed_up',
      name: 'Speed Up',
      description: 'Speed up video playback',
      category: EffectCategory.other,
      parameters: [
        EffectParameter(
          id: 'speed',
          name: 'Speed Multiplier',
          type: ParameterType.decimal,
          defaultValue: 2.0,
          minValue: 1.1,
          maxValue: 4.0,
        ),
      ],
      buildCommand: (input, output, params) {
        double speed = params['speed'] ?? 2.0;
        return '''
ffmpeg -i "$input" -vf "setpts=PTS/$speed" -af "atempo=$speed" -c:v libx264 -c:a aac "$output"
''';
      },
    ),

    EffectMode(
      id: 'slow_down',
      name: 'Slow Motion',
      description: 'Slow down video playback',
      category: EffectCategory.other,
      parameters: [
        EffectParameter(
          id: 'speed',
          name: 'Speed Factor',
          type: ParameterType.decimal,
          defaultValue: 0.5,
          minValue: 0.25,
          maxValue: 0.9,
        ),
      ],
      buildCommand: (input, output, params) {
        double speed = params['speed'] ?? 0.5;
        return '''
ffmpeg -i "$input" -vf "setpts=PTS/$speed" -af "atempo=$speed" -c:v libx264 -c:a aac "$output"
''';
      },
    ),

    EffectMode(
      id: 'grayscale',
      name: 'Grayscale',
      description: 'Convert video to black and white',
      category: EffectCategory.colorGrade,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=s=0" -c:v libx264 -c:a copy "$output"
''',
    ),

    EffectMode(
      id: 'sepia',
      name: 'Sepia',
      description: 'Apply sepia tone filter',
      category: EffectCategory.colorGrade,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131" -c:v libx264 -c:a copy "$output"
''',
    ),

    EffectMode(
      id: 'vhs_effect',
      name: 'VHS Effect',
      description: 'Retro VHS tape look',
      category: EffectCategory.glitch,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "noise=alls=20:allf=t+u,curves=vintage,chromashift=cbh=3:crh=-3" -c:v libx264 -c:a copy "$output"
''',
    ),

    EffectMode(
      id: 'shake',
      name: 'Camera Shake',
      description: 'Add camera shake effect',
      category: EffectCategory.glitch,
      parameters: [
        EffectParameter(
          id: 'intensity',
          name: 'Intensity',
          type: ParameterType.integer,
          defaultValue: 5,
          minValue: 1,
          maxValue: 20,
        ),
      ],
      buildCommand: (input, output, params) {
        int intensity = params['intensity'] ?? 5;
        return '''
ffmpeg -i "$input" -vf "crop=in_w-$intensity:in_h-$intensity:random(1)*$intensity:random(1)*$intensity" -c:v libx264 -c:a copy "$output"
''';
      },
    ),

    EffectMode(
      id: 'edge_detect',
      name: 'Edge Detection',
      description: 'Show only edges of the video',
      category: EffectCategory.other,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "edgedetect=mode=colormix" -c:v libx264 -c:a copy "$output"
''',
    ),

    EffectMode(
      id: 'posterize',
      name: 'Posterize',
      description: 'Reduce color palette for poster effect',
      category: EffectCategory.colorGrade,
      parameters: [
        EffectParameter(
          id: 'colors',
          name: 'Color Levels',
          type: ParameterType.integer,
          defaultValue: 4,
          minValue: 2,
          maxValue: 8,
        ),
      ],
      buildCommand: (input, output, params) {
        int colors = params['colors'] ?? 4;
        return '''
ffmpeg -i "$input" -vf "format=rgb24,split[a][b];[a]palettegen=max_colors=${colors * colors * colors}[p];[b][p]paletteuse" -c:v libx264 -c:a copy "$output"
''';
      },
    ),

    EffectMode(
      id: 'nightvision',
      name: 'Night Vision',
      description: 'Green night vision camera effect',
      category: EffectCategory.colorGrade,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "colorchannelmixer=rr=0:rg=0:rb=0:gr=0.2:gg=1:gb=0.2:br=0:bg=0:bb=0,noise=alls=10:allf=t" -c:v libx264 -c:a copy "$output"
''',
    ),

    EffectMode(
      id: 'thermal',
      name: 'Thermal Camera',
      description: 'Thermal imaging effect',
      category: EffectCategory.colorGrade,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -vf "hue=s=0,curves=r='0/0 0.5/1 1/0.5':g='0/0 0.5/0.5 1/1':b='0/0.5 0.5/0 1/0'" -c:v libx264 -c:a copy "$output"
''',
    ),

    EffectMode(
      id: 'bass_boost',
      name: 'Bass Boost',
      description: 'Heavily boosted bass audio',
      category: EffectCategory.audio,
      parameters: [
        EffectParameter(
          id: 'gain',
          name: 'Bass Gain (dB)',
          type: ParameterType.integer,
          defaultValue: 10,
          minValue: 5,
          maxValue: 30,
        ),
      ],
      buildCommand: (input, output, params) {
        int gain = params['gain'] ?? 10;
        return '''
ffmpeg -i "$input" -af "equalizer=f=80:width_type=o:width=2:g=$gain" -c:v copy -c:a aac "$output"
''';
      },
    ),

    EffectMode(
      id: 'earrape',
      name: 'Earrape',
      description: 'Extremely loud distorted audio',
      category: EffectCategory.audio,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -af "volume=10,lowpass=f=3000,highpass=f=200,acompressor=threshold=0.1:ratio=20,alimiter=limit=0.9" -c:v copy -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'echo',
      name: 'Echo',
      description: 'Add echo effect to audio',
      category: EffectCategory.audio,
      parameters: [
        EffectParameter(
          id: 'delay',
          name: 'Delay (ms)',
          type: ParameterType.integer,
          defaultValue: 500,
          minValue: 100,
          maxValue: 2000,
        ),
      ],
      buildCommand: (input, output, params) {
        int delay = params['delay'] ?? 500;
        return '''
ffmpeg -i "$input" -af "aecho=0.8:0.88:$delay:0.4" -c:v copy -c:a aac "$output"
''';
      },
    ),

    EffectMode(
      id: 'reverb',
      name: 'Reverb',
      description: 'Add reverb effect to audio',
      category: EffectCategory.audio,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -af "aecho=0.8:0.9:1000|1800:0.3|0.25" -c:v copy -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'chipmunk',
      name: 'Chipmunk',
      description: 'High-pitched chipmunk voice',
      category: EffectCategory.audio,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -af "asetrate=44100*1.5,aresample=44100" -c:v copy -c:a aac "$output"
''',
    ),

    EffectMode(
      id: 'deep_voice',
      name: 'Deep Voice',
      description: 'Low-pitched deep voice',
      category: EffectCategory.audio,
      buildCommand: (input, output, params) => '''
ffmpeg -i "$input" -af "asetrate=44100*0.7,aresample=44100" -c:v copy -c:a aac "$output"
''',
    ),
  ];

  /// Get effects by category
  static List<EffectMode> getByCategory(String category) {
    return allEffects.where((e) => e.category == category).toList();
  }

  /// Get all categories
  static List<String> get categories {
    return allEffects.map((e) => e.category).toSet().toList();
  }

  /// Find effect by ID
  static EffectMode? findById(String id) {
    try {
      return allEffects.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Convert semitones to pitch factor
  static double _semitoneToPitch(int semitones) {
    return _pitchFactors[semitones] ?? 1.0;
  }

  static const Map<int, double> _pitchFactors = {
    -12: 0.5,
    -11: 0.53,
    -10: 0.56,
    -9: 0.594,
    -8: 0.63,
    -7: 0.667,
    -6: 0.707,
    -5: 0.749,
    -4: 0.794,
    -3: 0.841,
    -2: 0.891,
    -1: 0.944,
    0: 1.0,
    1: 1.059,
    2: 1.122,
    3: 1.189,
    4: 1.26,
    5: 1.335,
    6: 1.414,
    7: 1.498,
    8: 1.587,
    9: 1.682,
    10: 1.782,
    11: 1.888,
    12: 2.0,
  };
}

// Helper function for external use
double semitoneToPitch(int semitones) {
  return EffectsRegistry._semitoneToPitch(semitones);
}
