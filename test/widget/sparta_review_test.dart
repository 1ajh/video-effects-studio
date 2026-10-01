import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/app.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/sparta/base.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';
import 'package:video_effects_studio/state/sparta_controller.dart';
import 'package:video_effects_studio/state/store.dart';
import 'package:video_effects_studio/ui/shell/queue_drawer.dart';
import 'package:video_effects_studio/ui/sparta/sparta_workspace.dart';

PreparedBase _prepared() {
  final t = BaseTranscription(
    bpm: 140,
    rootKey: 62,
    lengthBeats: 96,
    sections: const [
      Section(SectionKind.intro, 0, 16),
      Section(SectionKind.chorus, 16, 48),
      Section(SectionKind.epicness, 48, 96),
    ],
    hits: [for (var b = 0.0; b < 96; b++) GuideNote(b, 0.5, b.toInt() % 3)],
    kick: [for (var b = 16.0; b < 96; b++) b],
    source: TranscriptionSource.audio,
    confidence: 0.6,
    baseName: 'Sparta Review Base',
  );
  return PreparedBase(
    base: SpartaBase(id: 'x', name: t.baseName, kind: BaseKind.audio, transcription: t, audioPath: '/x.mp3'),
    audio: AudioBuffer(Float32List(2), sampleRate: 48000),
    auto: t,
  );
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(File('assets/fonts/Inter-$w.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await inter.load();
  });

  Future<SpartaController> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(StudioApp(store: store, playerAvailable: false, autoInit: false));
    await tester.pump();
    await tester.tap(find.byTooltip('Sparta Remix generator (Ctrl+3)'));
    await tester.pumpAndSettle();
    final c = tester.element(find.byType(SpartaWorkspace)).read<SpartaController>();
    c.debugUseBase(_prepared(), source: const AudioBaseSource(audioPath: '/x.mp3'));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('the base review shows a draft to check, and section edges drag to bar lines', (tester) async {
    final c = await open(tester);
    expect(find.text('Sparta Review Base'), findsWidgets);
    expect(find.text('Root D4'), findsOneWidget);
    expect(find.textContaining('60% sure'), findsOneWidget);
    expect(find.text('Send this transcription'), findsOneWidget);

    final timeline = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_TimelinePainter',
    );
    final rect = tester.getRect(timeline);
    double xOf(double beat) => rect.left + beat / 96 * rect.width;
    // Drag the first boundary about two bars later (and a little off-grid).
    await tester.dragFrom(Offset(xOf(16), rect.top + 10), Offset(xOf(24.6) - xOf(16), 0));
    await tester.pumpAndSettle();
    expect(c.currentSections.first.endBeat, 24);
    expect(c.currentSections[1].startBeat, 24);
    expect(c.transcriptionFixed, isTrue);
    expect(find.text('Send your fixes'), findsOneWidget);
    expect(find.text('Undo all fixes'), findsOneWidget);
  });

  testWidgets('each section picks its words and pitch from the wiki patterns', (tester) async {
    final c = await open(tester);
    expect(find.text('Words: Standard'), findsOneWidget);
    expect(find.text('Words: Original'), findsOneWidget);
    expect(find.text('No pitch'), findsOneWidget);
    await tester.tap(find.text('Words: Standard'));
    await tester.pumpAndSettle();
    expect(find.text('Chorus words in Chorus'), findsOneWidget);
    expect(find.text('Classic'), findsWidgets);
    await tester.tap(find.text('No words here'));
    await tester.pumpAndSettle();
    expect(c.choiceAt(1).words, '');

    // A typed pitch pattern.
    await tester.tap(find.text('Pitch: base hits').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0 0 +1 +1 -2 -2 +1 +1');
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(c.choiceAt(0).pitchPattern, 'custom:0 0 1 1 -2 -2 1 1');
    expect(c.chart.where((n) => n.role == SampleRole.pitch && n.beat < 8).map((n) => n.semitone).take(8), [
      0,
      0,
      1,
      1,
      -2,
      -2,
      1,
      1,
    ]);
  });

  testWidgets('"Clear finished" needs a second click', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var cleared = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfirmTextButton(label: 'Clear finished', onConfirmed: () => cleared++),
        ),
      ),
    );
    await tester.tap(find.text('Clear finished'));
    await tester.pump();
    expect(cleared, 0);
    expect(find.text('Click again to clear'), findsOneWidget);
    await tester.tap(find.text('Click again to clear'));
    await tester.pump();
    expect(cleared, 1);
    // Unconfirmed, it forgets after a few seconds.
    await tester.tap(find.text('Clear finished'));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Clear finished'), findsOneWidget);
    expect(cleared, 1);
  });
}
