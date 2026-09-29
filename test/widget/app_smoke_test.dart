import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/app.dart';
import 'package:video_effects_studio/core/effects/registry.dart';
import 'package:video_effects_studio/state/store.dart';

void main() {
  // Real Inter metrics, so layout checks measure what users see (the
  // default test font draws every glyph 1 em wide).
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(File('assets/fonts/Inter-$w.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await inter.load();
  });

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StudioApp(store: store, playerAvailable: false, autoInit: false));
    await tester.pump();
  }

  testWidgets('editor shell renders the browser, preview and inspector', (tester) async {
    await pumpApp(tester);
    expect(find.byTooltip('Sparta Remix generator (Ctrl+3)'), findsOneWidget);
    expect(find.text('Drop a video to get started'), findsOneWidget);
    expect(find.text('Pick an effect'), findsOneWidget);
    expect(find.text('${EffectRegistry.builtIn.length}'), findsWidgets);
    expect(find.text('Low Voice'), findsOneWidget);
  });

  testWidgets('selecting an effect fills the inspector', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Luig Group').first);
    await tester.pump();
    expect(find.textContaining('pitch set to −1'), findsWidgets);
    expect(find.byTooltip('Add to favorites'), findsOneWidget);
  });

  testWidgets('compilation mode shows the dock and adds effects', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Compilation'));
    await tester.pumpAndSettle();
    expect(find.text('COMPILATION'), findsOneWidget);
    expect(find.text('Use every effect'), findsOneWidget);

    await tester.tap(find.text('Use every effect'));
    await tester.pumpAndSettle();
    expect(find.text('Compilation (${EffectRegistry.builtIn.length})'), findsOneWidget);
  });

  testWidgets('Sparta mode shows setup and onboarding', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Sparta Remix generator (Ctrl+3)'));
    await tester.pumpAndSettle();
    expect(find.text('Sparta Remix Generator'), findsOneWidget);
    expect(find.text('Make a real Sparta remix'), findsOneWidget);
    expect(find.text('Drop videos or audio here'), findsOneWidget);
    expect(find.text('Sparta Classic'), findsOneWidget);
    // Nothing to generate from yet.
    final generate = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Generate remix'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
    );
    expect(generate.onPressed, isNull);
    expect(find.text('Render remix'), findsOneWidget);
  });

  testWidgets('Sparta base modes and section toggles', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Sparta Remix generator (Ctrl+3)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sparta Venom'));
    await tester.pump();
    expect(find.text('Madness'), findsWidgets);
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'Madness'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Madness'));
    await tester.pump();
    final chip = tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Madness'));
    expect(chip.selected, isFalse);

    await tester.ensureVisible(find.text('Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project'));
    await tester.pumpAndSettle();
    expect(find.text('Choose .flp / .flm / .mid'), findsOneWidget);

    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a base audio file'), findsOneWidget);
    expect(find.text('Tempo hint'), findsOneWidget);
  });

  for (final width in [1100.0, 1280.0, 1600.0]) {
    testWidgets('every mode fits a ${width.round()} px window', (tester) async {
      await pumpApp(tester, size: Size(width, 900));
      await tester.tap(find.text('Compilation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use every effect'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sparta Remix generator (Ctrl+3)'));
      await tester.pumpAndSettle();
      expect(find.text('Sparta Remix Generator'), findsOneWidget);
      await tester.tap(find.byTooltip('Single effect (Ctrl+1)'));
      await tester.pumpAndSettle();
      // Layout overflows fail the test on their own.
    });
  }

  testWidgets('search filters the list', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).first, 'sparta');
    await tester.pump();
    expect(find.text('Sparta Sequencer'), findsWidgets);
    expect(find.text('Low Voice'), findsNothing);
  });
}
