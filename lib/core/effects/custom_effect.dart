import 'effect.dart';
import 'library/helpers.dart';

/// A user-defined effect made of raw FFmpeg filter chains.
class CustomEffectDef {
  const CustomEffectDef({
    required this.id,
    required this.name,
    this.description = '',
    this.videoChain = '',
    this.audioChain = '',
    this.lengthFactor = 1.0,
  });

  final String id;
  final String name;
  final String description;

  /// Comma separated video filters, e.g. `negate,hue=h=90`.
  final String videoChain;

  /// Comma separated audio filters, e.g. `atempo=1.5,aecho=0.8:0.9:500:0.3`.
  final String audioChain;

  /// Output length relative to the input (e.g. 0.5 if the chain doubles speed).
  final double lengthFactor;

  static String newId() => 'custom_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  CustomEffectDef copyWith({
    String? name,
    String? description,
    String? videoChain,
    String? audioChain,
    double? lengthFactor,
  }) => CustomEffectDef(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    videoChain: videoChain ?? this.videoChain,
    audioChain: audioChain ?? this.audioChain,
    lengthFactor: lengthFactor ?? this.lengthFactor,
  );

  Effect toEffect() {
    final v = _clean(videoChain);
    final a = _clean(audioChain);
    final factor = lengthFactor <= 0 ? 1.0 : lengthFactor;
    return Effect(
      id: id,
      name: name.trim().isEmpty ? 'Untitled effect' : name.trim(),
      description: description.trim().isEmpty ? 'Custom FFmpeg effect' : description.trim(),
      category: EffectCategory.custom,
      custom: true,
      video: v.isEmpty ? null : vf(v),
      audio: a.isEmpty ? null : af(a),
      outputSeconds: (factor - 1).abs() < 1e-6 ? null : (p, s) => s * factor,
      keywords: const ['custom'],
    );
  }

  /// Collapses whitespace/newlines so multi-line chains typed into the editor
  /// stay a single valid filter chain.
  static String _clean(String chain) => chain.replaceAll(RegExp(r'\s*\n\s*'), '').trim().replaceAll(RegExp(r',+$'), '');

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'video': videoChain,
    'audio': audioChain,
    'lengthFactor': lengthFactor,
  };

  factory CustomEffectDef.fromJson(Map<String, Object?> json) => CustomEffectDef(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? 'Untitled effect',
    description: json['description'] as String? ?? '',
    videoChain: json['video'] as String? ?? '',
    audioChain: json['audio'] as String? ?? '',
    lengthFactor: (json['lengthFactor'] as num?)?.toDouble() ?? 1.0,
  );
}
