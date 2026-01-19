import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/models/effect_mode.dart';
import 'package:video_effects_studio/models/effects_registry.dart';

void main() {
  group('EffectMode', () {
    test('creates effect with basic properties', () {
      final effect = EffectMode(
        id: 'test_effect',
        name: 'Test Effect',
        description: 'A test effect',
        category: 'Test',
        ffmpegFilter: '-vf test',
      );

      expect(effect.id, 'test_effect');
      expect(effect.name, 'Test Effect');
      expect(effect.description, 'A test effect');
      expect(effect.category, 'Test');
      expect(effect.ffmpegFilter, '-vf test');
    });

    test('creates effect with parameters', () {
      final effect = EffectMode(
        id: 'param_effect',
        name: 'Parametric Effect',
        description: 'An effect with parameters',
        category: 'Test',
        ffmpegFilter: '-vf test={value}',
        parameters: [
          EffectParameter(
            id: 'value',
            name: 'Value',
            description: 'Test value',
            type: ParameterType.slider,
            defaultValue: 0.5,
            minValue: 0.0,
            maxValue: 1.0,
          ),
        ],
      );

      expect(effect.parameters, isNotEmpty);
      expect(effect.parameters!.first.id, 'value');
      expect(effect.parameters!.first.defaultValue, 0.5);
    });

    test('effect parameter has correct type', () {
      final sliderParam = EffectParameter(
        id: 'slider',
        name: 'Slider',
        description: 'A slider',
        type: ParameterType.slider,
        defaultValue: 50,
        minValue: 0,
        maxValue: 100,
      );

      final dropdownParam = EffectParameter(
        id: 'dropdown',
        name: 'Dropdown',
        description: 'A dropdown',
        type: ParameterType.dropdown,
        defaultValue: 'option1',
        options: ['option1', 'option2', 'option3'],
      );

      final toggleParam = EffectParameter(
        id: 'toggle',
        name: 'Toggle',
        description: 'A toggle',
        type: ParameterType.toggle,
        defaultValue: true,
      );

      expect(sliderParam.type, ParameterType.slider);
      expect(dropdownParam.type, ParameterType.dropdown);
      expect(toggleParam.type, ParameterType.toggle);
    });

    test('effect equality based on id', () {
      final effect1 = EffectMode(
        id: 'same_id',
        name: 'Effect 1',
        description: 'First effect',
        category: 'Test',
        ffmpegFilter: '-vf test1',
      );

      final effect2 = EffectMode(
        id: 'same_id',
        name: 'Effect 2',
        description: 'Second effect',
        category: 'Test',
        ffmpegFilter: '-vf test2',
      );

      expect(effect1.id, effect2.id);
    });
  });

  group('EffectsRegistry', () {
    test('contains expected categories', () {
      final categories = EffectsRegistry.getAllCategories();
      
      expect(categories, contains('Vocoder'));
      expect(categories, contains('Color Grading'));
      expect(categories, contains('Glitch'));
      expect(categories, contains('Audio'));
      expect(categories, contains('YTPMV'));
    });

    test('contains vocoder effect', () {
      final vocoderEffect = EffectsRegistry.getEffectById('vocoder');
      
      expect(vocoderEffect, isNotNull);
      expect(vocoderEffect!.name, 'Vocoder');
      expect(vocoderEffect.category, 'Vocoder');
    });

    test('contains g_major effect', () {
      final gMajorEffect = EffectsRegistry.getEffectById('g_major');
      
      expect(gMajorEffect, isNotNull);
      expect(gMajorEffect!.name, 'G Major');
      expect(gMajorEffect.category, 'Vocoder');
    });

    test('getEffectsByCategory returns correct effects', () {
      final vocoderEffects = EffectsRegistry.getEffectsByCategory('Vocoder');
      
      expect(vocoderEffects, isNotEmpty);
      for (final effect in vocoderEffects) {
        expect(effect.category, 'Vocoder');
      }
    });

    test('all effects have required properties', () {
      final allEffects = EffectsRegistry.getAllEffects();
      
      for (final effect in allEffects) {
        expect(effect.id, isNotEmpty);
        expect(effect.name, isNotEmpty);
        expect(effect.description, isNotEmpty);
        expect(effect.category, isNotEmpty);
        expect(effect.ffmpegFilter, isNotEmpty);
      }
    });

    test('effect ids are unique', () {
      final allEffects = EffectsRegistry.getAllEffects();
      final ids = allEffects.map((e) => e.id).toList();
      final uniqueIds = ids.toSet();
      
      expect(ids.length, uniqueIds.length, reason: 'Effect IDs should be unique');
    });

    test('getEffectById returns null for unknown id', () {
      final unknownEffect = EffectsRegistry.getEffectById('unknown_effect_xyz');
      
      expect(unknownEffect, isNull);
    });

    test('getAllCategories returns unique categories', () {
      final categories = EffectsRegistry.getAllCategories();
      final uniqueCategories = categories.toSet();
      
      expect(categories.length, uniqueCategories.length);
    });
  });
}
