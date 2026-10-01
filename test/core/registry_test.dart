import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/effects/custom_effect.dart';
import 'package:video_effects_studio/core/effects/effect.dart';
import 'package:video_effects_studio/core/effects/registry.dart';
import 'package:video_effects_studio/core/ffmpeg/command_builder.dart';
import 'package:video_effects_studio/core/ffmpeg/media_info.dart';

const media = MediaInfo(
  path: '/clips/logo.mp4',
  duration: 5,
  hasVideo: true,
  hasAudio: true,
  width: 1280,
  height: 720,
  fps: 30,
);

void main() {
  final effects = EffectRegistry.builtIn;

  test('the library is big', () {
    expect(effects.length, greaterThanOrEqualTo(120));
  });

  test('ids are unique and slug-like', () {
    final ids = effects.map((e) => e.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[a-z0-9_]+$')));
    }
  });

  test('names are unique', () {
    final names = effects.map((e) => e.name.toLowerCase()).toList();
    expect(names.toSet().length, names.length);
  });

  test('every category except custom has effects', () {
    for (final c in EffectCategory.values.where((c) => c != EffectCategory.custom)) {
      expect(effects.where((e) => e.category == c), isNotEmpty, reason: c.label);
    }
  });

  for (final e in effects) {
    group(e.id, () {
      test('has text and does something', () {
        expect(e.name.trim(), isNotEmpty);
        expect(e.description.trim(), isNotEmpty);
        expect(e.video != null || e.audio != null, isTrue);
      });

      test('parameter defaults are valid', () {
        for (final p in e.params) {
          expect(p.sanitize(p.defaultValue), p.defaultValue, reason: p.id);
          if (p.type == ParamType.choice) expect(p.options, contains(p.defaultValue));
          if (p.min != null) expect(p.min! <= p.max!, isTrue);
        }
      });

      test('builds a valid-looking command with defaults and extremes', () {
        final variants = <Map<String, Object?>>[
          e.defaults(),
          {
            for (final p in e.params)
              if (p.min != null) p.id: p.min,
          },
          {
            for (final p in e.params)
              if (p.max != null) p.id: p.max,
          },
        ];
        for (final values in variants) {
          final cmd = CommandBuilder.build(
            RenderRequest(media: media, effect: e, params: values, outputPath: '/out/x.mp4'),
          );
          final graph = cmd.graph;
          expect(graph, isNot(contains('rubberband')));
          expect(graph, isNot(contains('[]')));
          expect(RegExp(r"'").allMatches(graph).length.isEven, isTrue, reason: 'balanced quotes');
          // Every produced label is consumed exactly once (except outputs).
          final produced = RegExp(r'\[([a-z_0-9]+)\](?=;|$)').allMatches(graph).map((m) => m.group(1)!).toList();
          expect(produced.toSet().length, produced.length, reason: 'duplicate output labels');
          expect(cmd.expectedSeconds, greaterThan(0));
        }
      });
    });
  }

  test('custom effects join the registry and clean their chains', () {
    final reg = EffectRegistry(
      custom: [const CustomEffectDef(id: 'custom_a', name: 'Mine', videoChain: 'negate,\n  hflip,', audioChain: '')],
    );
    final e = reg.byId('custom_a')!;
    expect(e.custom, isTrue);
    expect(e.category, EffectCategory.custom);
    expect(e.audio, isNull);
    final cmd = CommandBuilder.build(RenderRequest(media: media, effect: e, params: const {}, outputPath: '/o.mp4'));
    expect(cmd.graph, contains('negate,hflip['));
  });

  test('custom effect JSON round trip', () {
    const def = CustomEffectDef(
      id: 'x',
      name: 'N',
      description: 'D',
      videoChain: 'v',
      audioChain: 'a',
      lengthFactor: 0.5,
    );
    final back = CustomEffectDef.fromJson(def.toJson());
    expect(back.toJson(), def.toJson());
  });

  test('search matches names, descriptions, credits and keywords', () {
    final reg = EffectRegistry();
    expect(reg.all.where((e) => e.matches('csupo')), isNotEmpty);
    expect(reg.all.where((e) => e.matches('sparta')).map((e) => e.id), contains('sparta_sequencer'));
    expect(reg.all.where((e) => e.matches('zzzz-nothing')), isEmpty);
  });
}
