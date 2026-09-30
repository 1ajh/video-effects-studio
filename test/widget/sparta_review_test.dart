import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/app.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/audio/dsp.dart';
import 'package:video_effects_studio/core/sparta/arranger.dart';
import 'package:video_effects_studio/core/sparta/base_renderer.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/midi.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sample_finder.dart';
import 'package:video_effects_studio/core/sparta/sample_processing.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';
import 'package:video_effects_studio/state/sparta_controller.dart';
import 'package:video_effects_studio/state/store.dart';
import 'package:video_effects_studio/ui/sparta/sparta_workspace.dart';

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(File('assets/fonts/Inter-$w.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
    }
    await inter.load();
  });

  testWidgets('section boundaries can be dragged on the timeline, snapping to bars', (tester) async {
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

    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('sparta_review_'));
    addTearDown(() => tmp!.delete(recursive: true));
    await tester.runAsync(() async {
      final comp = Composer(
        seed: 3,
      ).compose(defaultPlan(length: RemixLength.short, enabled: {SectionKind.chorus, SectionKind.madness}));
      final midi = p.join(tmp!.path, 'base.mid');
      await File(midi).writeAsBytes(MidiFile.fromScore(comp).encode());
      await c.setProject(midi);
      final base = c.chart!.toBase(c.mapping, seed: c.seed, style: c.style);
      final audio = BaseRenderer().render(comp);
      const path = 'test/fixtures/speech_a.wav';
      final source = SourceAnalysis.fromAudio(0, path, AudioBuffer.fromWav(File(path).readAsBytesSync()));
      final raw = AudioBuffer(resample(source.audio.data, source.audio.sampleRate / 48000), sampleRate: 48000);
      final samples = {
        for (final e in SampleFinder([source]).find().assignDistinct().entries)
          e.key: [SampleEnhancer().process(e.value, raw.slice(e.value.start, e.value.end), path)],
      };
      c.processed = samples;
      c.mix = Arranger(base: base, samples: samples, baseAudio: audio).mix(stems: false);
      c.previewPath = p.join(tmp.path, 'preview.wav');
      c.stage = SpartaStage.ready;
      c.debugUseBase(PreparedBase(base: base, audio: audio, chart: c.chart));
    });
    await tester.pumpAndSettle();

    final base = c.prepared!.base, mix = c.mix!;
    expect(base.sections.length, greaterThan(1));
    final timeline = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_TimelinePainter',
    );
    final rect = tester.getRect(timeline);
    double xOf(double beat) => rect.left + base.seconds(beat) / mix.duration * rect.width;
    final boundary = base.sections.first.endBeat;
    // Drag the first boundary about two bars later (and a little off-grid).
    await tester.dragFrom(Offset(xOf(boundary), rect.top + 10), Offset(xOf(boundary + 8.6) - xOf(boundary), 0));
    await tester.pumpAndSettle();
    expect(c.currentSections.first.endBeat, boundary + 8);
    expect(c.currentSections[1].startBeat, boundary + 8);
    expect(c.sectionsEdited, isTrue);
  });
}
