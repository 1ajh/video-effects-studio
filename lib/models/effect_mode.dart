/// Represents a video effect mode with its FFmpeg configuration
class EffectMode {
  final String id;
  final String name;
  final String description;
  final String category;
  final String iconPath;
  final bool requiresDesktop; // For effects that need Wine/autotune.exe
  final List<EffectParameter> parameters;
  final String Function(
    String inputPath,
    String outputPath,
    Map<String, dynamic> params,
  ) buildCommand;

  const EffectMode({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.iconPath = 'assets/icons/default.png',
    this.requiresDesktop = false,
    this.parameters = const [],
    required this.buildCommand,
  });
}

/// Parameter for customizable effects
class EffectParameter {
  final String id;
  final String name;
  final ParameterType type;
  final dynamic defaultValue;
  final dynamic minValue;
  final dynamic maxValue;
  final List<String>? options;

  const EffectParameter({
    required this.id,
    required this.name,
    required this.type,
    required this.defaultValue,
    this.minValue,
    this.maxValue,
    this.options,
  });
}

enum ParameterType {
  integer,
  decimal,
  boolean,
  dropdown,
  text,
}

/// Categories for organizing effects
class EffectCategory {
  static const String vocoder = 'Vocoder Effects';
  static const String colorGrade = 'Color Grading';
  static const String glitch = 'Glitch & Distortion';
  static const String audio = 'Audio Effects';
  static const String ytpmv = 'YTPMV Tools';
  static const String other = 'Other';
}
