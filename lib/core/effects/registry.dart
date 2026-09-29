import 'custom_effect.dart';
import 'effect.dart';
import 'library/audio_time.dart';
import 'library/color.dart';
import 'library/distort_glitch.dart';
import 'library/g_majors.dart';
import 'library/logo_editing.dart';
import 'library/vocoders.dart';

/// Every effect the app knows about: the built-in library plus the user's
/// custom effects.
class EffectRegistry {
  EffectRegistry({List<CustomEffectDef> custom = const []}) : _custom = [for (final c in custom) c.toEffect()] {
    _byId = {for (final e in all) e.id: e, original.id: original};
  }

  static final List<Effect> builtIn = List.unmodifiable([
    ...logoEditingEffects,
    ...gMajorEffects,
    ...vocoderEffects,
    ...colorEffects,
    ...distortEffects,
    ...glitchEffects,
    ...audioEffects,
    ...timeEffects,
    ...ytpmvEffects,
  ]);

  /// Pass-through effect used for the "original clip first" segment.
  static const Effect original = Effect(
    id: 'original',
    name: 'Original',
    description: 'The unedited clip.',
    category: EffectCategory.custom,
  );

  final List<Effect> _custom;
  late final Map<String, Effect> _byId;

  List<Effect> get custom => List.unmodifiable(_custom);

  List<Effect> get all => [...builtIn, ..._custom];

  Effect? byId(String id) => _byId[id];

  List<Effect> inCategory(EffectCategory c) => all.where((e) => e.category == c).toList();

  /// Categories that currently contain at least one effect, in display order.
  List<EffectCategory> get categories => EffectCategory.values.where((c) => all.any((e) => e.category == c)).toList();
}
