import '../ffmpeg/filter_graph.dart';

/// Values chosen for an effect's parameters, keyed by [EffectParam.id].
typedef ParamValues = Map<String, Object?>;

/// Builds part of a filtergraph. Receives the label of the incoming stream
/// and returns the label of the processed stream.
typedef StreamBuilder = String Function(FilterGraph g, String input, ParamReader p, FxEnv env);

/// Information about the media an effect is being applied to.
class FxEnv {
  const FxEnv({
    required this.width,
    required this.height,
    required this.fps,
    required this.duration,
    this.sampleRate = 48000,
  });

  /// Frame size after input normalization (always even).
  final int width;
  final int height;
  final double fps;

  /// Duration in seconds of the (trimmed) input segment.
  final double duration;

  /// Audio is always resampled to this rate before effects run.
  final int sampleRate;
}

enum ParamType { integer, decimal, boolean, choice, text }

class EffectParam {
  const EffectParam({
    required this.id,
    required this.label,
    required this.type,
    required this.defaultValue,
    this.min,
    this.max,
    this.step,
    this.options,
    this.unit,
    this.hint,
  });

  const EffectParam.integer(
    this.id,
    this.label, {
    required int value,
    required int this.min,
    required int this.max,
    this.unit,
    this.hint,
  }) : type = ParamType.integer,
       defaultValue = value,
       step = 1,
       options = null;

  const EffectParam.decimal(
    this.id,
    this.label, {
    required double value,
    required double this.min,
    required double this.max,
    this.step,
    this.unit,
    this.hint,
  }) : type = ParamType.decimal,
       defaultValue = value,
       options = null;

  const EffectParam.toggle(this.id, this.label, {required bool value, this.hint})
    : type = ParamType.boolean,
      defaultValue = value,
      min = null,
      max = null,
      step = null,
      options = null,
      unit = null;

  const EffectParam.choice(this.id, this.label, {required String value, required List<String> this.options, this.hint})
    : type = ParamType.choice,
      defaultValue = value,
      min = null,
      max = null,
      step = null,
      unit = null;

  const EffectParam.text(this.id, this.label, {required String value, this.hint})
    : type = ParamType.text,
      defaultValue = value,
      min = null,
      max = null,
      step = null,
      options = null,
      unit = null;

  final String id;
  final String label;
  final ParamType type;
  final Object defaultValue;
  final num? min;
  final num? max;
  final num? step;
  final List<String>? options;
  final String? unit;
  final String? hint;

  /// Coerces [raw] into a valid value for this parameter, falling back to the
  /// default when it is missing or of the wrong type.
  Object sanitize(Object? raw) {
    switch (type) {
      case ParamType.integer:
        final v = raw is num ? raw.round() : int.tryParse('$raw');
        if (v == null) return defaultValue;
        return v.clamp(min!.toInt(), max!.toInt());
      case ParamType.decimal:
        final v = raw is num ? raw.toDouble() : double.tryParse('$raw');
        if (v == null || v.isNaN) return defaultValue;
        return v.clamp(min!.toDouble(), max!.toDouble());
      case ParamType.boolean:
        return raw is bool ? raw : defaultValue;
      case ParamType.choice:
        return raw is String && options!.contains(raw) ? raw : defaultValue;
      case ParamType.text:
        return raw is String ? raw : defaultValue;
    }
  }
}

/// Typed, sanitized access to parameter values inside effect builders.
class ParamReader {
  ParamReader(this._params, ParamValues values) : _values = {for (final p in _params) p.id: p.sanitize(values[p.id])};

  final List<EffectParam> _params;
  final Map<String, Object> _values;

  Map<String, Object> get values => Map.unmodifiable(_values);

  EffectParam _param(String id) =>
      _params.firstWhere((p) => p.id == id, orElse: () => throw ArgumentError('Unknown parameter "$id"'));

  int integer(String id) => (_values[id] ?? _param(id).defaultValue) as int;
  double decimal(String id) => ((_values[id] ?? _param(id).defaultValue) as num).toDouble();
  bool toggle(String id) => (_values[id] ?? _param(id).defaultValue) as bool;
  String choice(String id) => (_values[id] ?? _param(id).defaultValue) as String;
  String text(String id) => (_values[id] ?? _param(id).defaultValue) as String;
}

enum EffectCategory {
  logoEditing('Logo Editing', 'Classic effects from the logo-editing / Klasky Csupo community'),
  gMajor('G-Majors & Chords', 'Stacked pitch chords with color madness'),
  vocoder('Vocoders & Robots', 'Real voice processing: robotized, vocoded and chorded'),
  color('Color & Look', 'Color grading, film looks and stylized palettes'),
  distort('Distortion & Warp', 'Mirrors, waves, swirls, lenses and kaleidoscopes'),
  glitch('Glitch & Retro', 'VHS, CRT, RGB splits, datamosh-ish trails'),
  voice('Voice Changer', 'Popular voice effects: giant, baby, monster, radio, cave, cartoon and more'),
  audio('Audio FX', 'Pitch, bass, echo, crush and friends'),
  time('Time & Speed', 'Speed ramps, reversal, stutters and loops'),
  ytpmv('YTPMV Tools', 'Sparta pitches, sequencers and remix helpers'),
  custom('Custom', 'Your own FFmpeg filter chains');

  const EffectCategory(this.label, this.blurb);
  final String label;
  final String blurb;
}

class Effect {
  const Effect({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.video,
    this.audio,
    this.params = const [],
    this.outputSeconds,
    this.credit,
    this.loud = false,
    this.heavy = false,
    this.custom = false,
    this.keywords = const [],
  });

  final String id;
  final String name;
  final String description;
  final EffectCategory category;

  /// Video part of the effect. `null` passes video through untouched.
  final StreamBuilder? video;

  /// Audio part of the effect. `null` passes audio through untouched.
  final StreamBuilder? audio;

  final List<EffectParam> params;

  /// Output duration for a given input duration (seconds). `null` means the
  /// effect keeps the duration unchanged.
  final double Function(ParamReader p, double inputSeconds)? outputSeconds;

  /// Where the recipe comes from (creator / community reference).
  final String? credit;

  /// Output is much louder than the source.
  final bool loud;

  /// Buffers the whole clip in memory (reverse etc.) or is slow to render.
  final bool heavy;

  /// User-created effect.
  final bool custom;

  /// Extra search terms.
  final List<String> keywords;

  ParamReader reader(ParamValues values) => ParamReader(params, values);

  Map<String, Object> defaults() => {for (final p in params) p.id: p.defaultValue};

  double outputSecondsFor(ParamValues values, double inputSeconds) =>
      outputSeconds?.call(reader(values), inputSeconds) ?? inputSeconds;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        category.label.toLowerCase().contains(q) ||
        (credit?.toLowerCase().contains(q) ?? false) ||
        keywords.any((k) => k.toLowerCase().contains(q));
  }
}
