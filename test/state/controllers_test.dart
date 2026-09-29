import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/core/effects/custom_effect.dart';
import 'package:video_effects_studio/core/effects/effect.dart';
import 'package:video_effects_studio/core/effects/registry.dart';
import 'package:video_effects_studio/core/models/output_settings.dart';
import 'package:video_effects_studio/core/render/render_engine.dart';
import 'package:video_effects_studio/state/compilation_controller.dart';
import 'package:video_effects_studio/state/editor_controller.dart';
import 'package:video_effects_studio/state/library_controller.dart';
import 'package:video_effects_studio/state/settings_controller.dart';
import 'package:video_effects_studio/state/store.dart';
import 'package:video_effects_studio/state/update_controller.dart';

void main() {
  final reg = EffectRegistry();
  Effect byId(String id) => reg.byId(id)!;

  group('CompilationController', () {
    late CompilationController comp;
    setUp(() => comp = CompilationController(random: math.Random(1)));

    test('select all uses every effect in order', () {
      comp.selectAll(reg);
      expect(comp.items.map((i) => i.effectId), reg.all.map((e) => e.id));
    });

    test('add category appends only that category', () {
      comp.add(byId('invert_color'), const {});
      comp.addCategory(reg, EffectCategory.gMajor);
      expect(comp.length, 1 + reg.inCategory(EffectCategory.gMajor).length);
      expect(comp.items.skip(1).every((i) => byId(i.effectId).category == EffectCategory.gMajor), isTrue);
    });

    test('random N picks distinct effects from the pool', () {
      comp.randomize(reg, 12);
      expect(comp.length, 12);
      expect(comp.items.map((i) => i.effectId).toSet().length, 12);
      comp.randomize(reg, 999, category: EffectCategory.time);
      expect(comp.length, reg.inCategory(EffectCategory.time).length);
    });

    test('reorder and shuffle keep the selected item selected', () {
      comp.addAll([byId('low_voice'), byId('g_major_4'), byId('reverse'), byId('swirl')]);
      comp.select(1);
      final selected = comp.selectedItem;
      comp.move(1, 3);
      expect(comp.selectedItem, same(selected));
      expect(comp.items.last.effectId, 'g_major_4');
      comp.shuffle();
      expect(comp.selectedItem, same(selected));
      comp.removeAt(comp.selectedIndex!);
      expect(comp.selectedIndex, isNull);
    });

    test('items keep their own parameters', () {
      comp.add(byId('speed'), {'factor': 3.0});
      comp.add(byId('speed'), {'factor': 0.5});
      expect(comp.items.map((i) => i.params['factor']), [3.0, 0.5]);
      comp.setItemParam(0, 'factor', 1.5);
      expect(comp.items.first.params['factor'], 1.5);
    });

    test('estimate includes the original, length changes and title cards', () {
      comp.add(byId('invert_color'), const {});
      comp.add(byId('speed'), {'factor': 2.0});
      expect(comp.estimateSeconds(reg, 4, originalFirst: false, labelMode: LabelMode.none), 4 + 2);
      expect(comp.estimateSeconds(reg, 4, originalFirst: true, labelMode: LabelMode.none), 4 + 4 + 2);
      expect(
        comp.estimateSeconds(reg, 4, originalFirst: true, labelMode: LabelMode.titleCard, titleCardSeconds: 1),
        10 + 3,
      );
    });

    test('prune drops deleted custom effects', () {
      final withCustom = EffectRegistry(
        custom: [const CustomEffectDef(id: 'c1', name: 'C', videoChain: 'negate')],
      );
      comp.add(withCustom.byId('c1')!, const {});
      comp.add(byId('invert_color'), const {});
      comp.prune(reg);
      expect(comp.items.map((i) => i.effectId), ['invert_color']);
    });
  });

  group('library + editor', () {
    late Store store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = await Store.open();
    });

    test('favorites, recents, presets and custom effects persist', () async {
      final lib = LibraryController(store);
      lib.toggleFavorite('g_major_4');
      lib.markUsed('swirl');
      lib.markUsed('g_major_4');
      lib.savePreset('swirl', 'Big', {'strength': 5.0});
      lib.saveCustom(const CustomEffectDef(id: 'custom_z', name: 'Z', videoChain: 'vflip'));

      final again = LibraryController(store);
      expect(again.isFavorite('g_major_4'), isTrue);
      expect(again.recents, ['g_major_4', 'swirl']);
      expect(again.presetsFor('swirl').single.values['strength'], 5.0);
      expect(again.registry.byId('custom_z'), isNotNull);

      again.deleteCustom('custom_z');
      expect(LibraryController(store).registry.byId('custom_z'), isNull);
    });

    test('editor remembers params per effect and filters the browser', () {
      final lib = LibraryController(store);
      final editor = EditorController(lib);
      final swirl = byId('swirl');
      expect(editor.paramsFor(swirl)['strength'], 2.5);
      editor.setParam(swirl, 'strength', 4.0);
      expect(editor.paramsFor(swirl)['strength'], 4.0);
      editor.resetParams(swirl);
      expect(editor.paramsFor(swirl)['strength'], 2.5);

      editor.setFilter(const BrowserFilter.category(EffectCategory.vocoder));
      expect(editor.visibleEffects().every((e) => e.category == EffectCategory.vocoder), isTrue);
      // Search spans the whole library even inside a category.
      editor.setSearch('luig');
      expect(editor.visibleEffects().map((e) => e.id), contains('luig_group'));

      editor.setSearch('');
      editor.setFilter(BrowserFilter.favorites);
      expect(editor.visibleEffects(), isEmpty);
    });

    test('settings persist output choices', () {
      final s = SettingsController(store);
      s.setOutput(
        const OutputSettings(format: OutputFormat.webm, quality: OutputQuality.small, resolution: ResolutionCap.p720),
      );
      s.setLabelMode(LabelMode.titleCard);
      s.setConcurrency(9);
      final again = SettingsController(store);
      expect(again.output.format, OutputFormat.webm);
      expect(again.output.resolution, ResolutionCap.p720);
      expect(again.labelMode, LabelMode.titleCard);
      expect(again.concurrency, 4);
    });
  });

  test('version comparison', () {
    expect(UpdateController.isNewer('2.1.0', '2.0.9'), isTrue);
    expect(UpdateController.isNewer('2.0.0', '2.0.0'), isFalse);
    expect(UpdateController.isNewer('1.9', '2.0.0'), isFalse);
    expect(UpdateController.isNewer('10.0.0', '9.9.9'), isTrue);
    expect(UpdateController.isNewer('', '1.0.0'), isFalse);
  });
}
