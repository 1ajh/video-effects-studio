import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/midi.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';
import 'package:video_effects_studio/state/engine_controller.dart';
import 'package:video_effects_studio/state/sparta_controller.dart';
import 'package:video_effects_studio/state/store.dart';
import 'package:video_effects_studio/ui/sparta/sparta_sections.dart';
import 'package:video_effects_studio/ui/theme.dart';

void main() {
  late Directory tmp;
  late String projectPath;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('sparta_sections_');
    final comp = Composer(seed: 2).compose(
      defaultPlan(length: RemixLength.short, enabled: {SectionKind.intro, SectionKind.chorus, SectionKind.madness}),
    );
    projectPath = p.join(tmp.path, 'base.mid');
    await File(projectPath).writeAsBytes(MidiFile.fromScore(comp).encode());
  });
  tearDownAll(() => tmp.delete(recursive: true));

  Future<(SpartaController, Store)> controller({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await Store.open();
    return (SpartaController(EngineController(), store: store), store);
  }

  /// Loads the project and prepares its base like the pipeline does.
  Future<void> load(SpartaController c) async {
    await c.setProject(projectPath);
    final chart = c.chart!;
    final base = chart.toBase(c.mapping, seed: c.seed, style: c.style);
    c.debugUseBase(PreparedBase(base: base, audio: AudioBuffer(Float32List(2), sampleRate: 48000), chart: chart));
  }

  test('section edits apply at once and are saved per base file', () async {
    final (c, store) = await controller();
    await load(c);
    expect(c.canRewriteSections, isTrue);
    final before = c.prepared!.base.chart.length;
    final first = c.currentSections.first;
    c.relabelSection(0, SectionKind.madness, rewrite: true);
    c.renameSection(1, 'The drop');
    expect(c.currentSections.first.kind, SectionKind.madness);
    expect(c.currentSections[1].title, 'The drop');
    expect(c.sectionsEdited, isTrue);
    expect(c.prepared!.base.chart.where((n) => first.contains(n.beat)), isNotEmpty);
    expect(store.readJson<Map<String, dynamic>>('sparta.base.$projectPath'), isNotNull);

    // Re-opening the same project restores them.
    final c2 = SpartaController(EngineController(), store: store);
    await load(c2);
    expect(c2.currentSections.first.kind, SectionKind.madness);
    expect(c2.currentSections[1].title, 'The drop');
    expect(c2.prepared!.base.chart.map((n) => n.beat), c.prepared!.base.chart.map((n) => n.beat));

    c2.resetSections();
    expect(c2.sectionsEdited, isFalse);
    expect(c2.prepared!.base.chart.length, isNot(0));
    expect(store.readJson<Map<String, dynamic>>('sparta.base.$projectPath'), isNull);
    expect(before, isPositive);
  });

  test('audio base tempo can be set, halved and doubled, and is remembered', () async {
    final (c, store) = await controller();
    c.setAudioBase('/music/base.mp3');
    expect(c.audioBpm, isNull);
    c.setBpm(170);
    expect(c.bpmOverride, 170);
    c.halveTempo();
    expect(c.bpmOverride, 85);
    c.doubleTempo();
    c.doubleTempo();
    expect(c.bpmOverride, 340);
    c.setBpm(1000); // nonsense goes back to detection
    expect(c.bpmOverride, isNull);
    c.setBpm(142.5);

    final c2 = SpartaController(EngineController(), store: store);
    c2.setAudioBase('/music/base.mp3');
    expect(c2.bpmOverride, 142.5);
    c2.setAudioBase('/music/other.mp3');
    expect(c2.bpmOverride, isNull);
  });

  testWidgets('relabelling from a chip asks whether to rewrite the notes', (tester) async {
    late SpartaController c;
    await tester.runAsync(() async {
      c = (await controller()).$1;
      await load(c);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: Consumer<SpartaController>(builder: (_, c, _) => SectionChips(base: c.prepared!.base)),
          ),
        ),
      ),
    );
    final firstTitle = c.currentSections.first.title;
    await tester.tap(find.textContaining(firstTitle).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Awesomeness').last);
    await tester.pumpAndSettle();
    expect(find.text('Make this section Awesomeness?'), findsOneWidget);
    await tester.tap(find.text('Rewrite notes'));
    await tester.pumpAndSettle();
    expect(c.currentSections.first.kind, SectionKind.awesomeness);
    expect(c.edits.rewrites, hasLength(1));

    // Keep the notes this time.
    await tester.tap(find.textContaining('Awesomeness').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Epicness').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep notes'));
    await tester.pumpAndSettle();
    expect(c.currentSections.first.kind, SectionKind.epicness);
    expect(c.edits.rewrites, hasLength(1));
    expect(find.text('Reset sections'), findsOneWidget);

    // Split the first section in two, then merge it back.
    final n = c.currentSections.length;
    await tester.tap(find.textContaining('Epicness').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Split'));
    await tester.pumpAndSettle();
    expect(c.currentSections.length, n + 1);
    await tester.tap(find.textContaining('Epicness').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge with next'));
    await tester.pumpAndSettle();
    expect(c.currentSections.length, n);
  });
}
