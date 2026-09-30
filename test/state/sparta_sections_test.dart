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
  late String otherPath;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('sparta_sections_');
    final comp = Composer(seed: 2).compose(
      defaultPlan(length: RemixLength.short, enabled: {SectionKind.intro, SectionKind.chorus, SectionKind.madness}),
    );
    projectPath = p.join(tmp.path, 'base.mid');
    await File(projectPath).writeAsBytes(MidiFile.fromScore(comp).encode());
    final longer = Composer(
      seed: 5,
    ).compose(defaultPlan(enabled: {SectionKind.intro, SectionKind.chorus, SectionKind.epicness, SectionKind.madness}));
    otherPath = p.join(tmp.path, 'other base.mid');
    await File(otherPath).writeAsBytes(MidiFile.fromScore(longer).encode());
  });
  tearDownAll(() => tmp.delete(recursive: true));

  Future<(SpartaController, Store)> controller({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await Store.open();
    return (SpartaController(EngineController(), store: store), store);
  }

  /// Loads the project and prepares its base like the pipeline does.
  Future<void> load(SpartaController c, [String? path]) async {
    await c.setProject(path ?? projectPath);
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

  test('edited sections keep their notes when samples are re-picked', () async {
    final (c, _) = await controller();
    await load(c);
    c.relabelSection(0, SectionKind.madness, rewrite: true);
    c.splitSection(1, c.currentSections[1].startBeat + 4);
    String sig() => c.prepared!.base.chart.map((n) => '${n.role.name}${n.beat}/${n.semitone}').join(' ');
    final notes = sig(), kinds = c.currentSections.map((s) => s.kind).toList();
    // Re-picking samples prepares the same automatic base again.
    final chart = c.chart!;
    c.debugUseBase(
      PreparedBase(
        base: chart.toBase(c.mapping, seed: c.seed, style: c.style),
        audio: AudioBuffer(Float32List(2), sampleRate: 48000),
        chart: chart,
      ),
    );
    expect(sig(), notes);
    expect(c.currentSections.map((s) => s.kind), kinds);
  });

  test("another base's sections can be copied bar for bar", () async {
    final (c, store) = await controller();
    await load(c, otherPath);
    final other = c.currentSections;
    // Edit the other base so it has a saved layout.
    c.relabelSection(0, SectionKind.madness);
    c.renameSection(1, 'Build');
    final saved = c.currentSections;

    final c2 = SpartaController(EngineController(), store: store);
    await load(c2);
    expect(c2.savedLayouts.map((l) => p.basename(l.path)), ['other base.mid']);
    final end = c2.currentSections.last.endBeat;
    c2.copySections(c2.savedLayouts.single.layout, rewrite: true);
    final copied = c2.currentSections;
    expect(copied.first.kind, SectionKind.madness);
    expect(copied.first.endBeat, saved.first.endBeat.clamp(0, end));
    if (copied.length > 1) expect(copied[1].title, 'Build');
    expect(copied.last.endBeat, end);
    for (var i = 1; i < copied.length; i++) {
      expect(copied[i].startBeat, copied[i - 1].endBeat);
    }
    expect(c2.edits.rewrites, hasLength(copied.length));
    // The base being edited never lists itself.
    expect(c.savedLayouts.where((l) => l.path == otherPath), isEmpty);
    expect(other, isNotEmpty);
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

  testWidgets('copy sections dialog', (tester) async {
    late SpartaController c;
    await tester.runAsync(() async {
      final (a, store) = await controller();
      await load(a, otherPath);
      a.relabelSection(0, SectionKind.outro);
      c = SpartaController(EngineController(), store: store);
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
    await tester.tap(find.text('Copy sections from…'));
    await tester.pumpAndSettle();
    expect(find.text('other base.mid'), findsOneWidget);
    expect(find.text('Rewrite the sample notes to match'), findsOneWidget);
    await tester.tap(find.text('Copy sections'));
    await tester.pumpAndSettle();
    expect(c.currentSections.first.kind, SectionKind.outro);
    expect(c.edits.rewrites, isNotEmpty);
  });
}
