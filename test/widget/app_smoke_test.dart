import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/app.dart';
import 'package:video_effects_studio/core/effects/registry.dart';
import 'package:video_effects_studio/state/store.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StudioApp(store: store, playerAvailable: false, autoInit: false));
    await tester.pump();
  }

  testWidgets('editor shell renders the browser, preview and inspector', (tester) async {
    await pumpApp(tester);
    expect(find.text('Video Effects Studio'), findsOneWidget);
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

  testWidgets('search filters the list', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).first, 'sparta');
    await tester.pump();
    expect(find.text('Sparta Sequencer'), findsWidgets);
    expect(find.text('Low Voice'), findsNothing);
  });
}
