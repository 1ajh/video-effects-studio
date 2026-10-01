import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/sparta/base.dart';
import 'package:video_effects_studio/core/sparta/base_library.dart';
import 'package:video_effects_studio/core/sparta/charter.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';
import 'package:video_effects_studio/state/engine_controller.dart';
import 'package:video_effects_studio/state/sparta_controller.dart';
import 'package:video_effects_studio/state/store.dart';

BaseTranscription _auto() => BaseTranscription(
  bpm: 140,
  rootKey: 62,
  lengthBeats: 96,
  sections: const [
    Section(SectionKind.intro, 0, 16),
    Section(SectionKind.chorus, 16, 48),
    Section(SectionKind.other, 48, 96),
  ],
  hits: [for (var b = 0.0; b < 96; b++) GuideNote(b, 0.5, 0)],
  kick: [for (var b = 16.0; b < 96; b++) b],
  snare: [for (var b = 17.0; b < 96; b += 2) b],
  hat: [for (var b = 16.5; b < 96; b++) b],
  source: TranscriptionSource.audio,
  confidence: 0.6,
  baseName: 'Sparta Test Base',
  catalogId: 'test/base',
  audioSha1: 'abc',
);

PreparedBase _prepared() {
  final t = _auto();
  return PreparedBase(
    base: SpartaBase(id: 'catalog:test/base', name: t.baseName, kind: BaseKind.library, transcription: t),
    audio: AudioBuffer(Float32List(2), sampleRate: 48000),
    auto: t,
  );
}

const _source = AudioBaseSource(audioPath: '/bases/test.mp3');

void main() {
  Future<(SpartaController, Store)> controller({Map<String, Object> prefs = const {}}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await Store.open();
    final c = SpartaController(EngineController(), store: store)..debugUseBase(_prepared(), source: _source);
    return (c, store);
  }

  test('fixes to the transcription apply at once and are kept for that base', () async {
    final (c, store) = await controller();
    expect(c.transcriptionFixed, isFalse);
    c.relabelSection(2, SectionKind.madness);
    c.renameSection(1, 'The drop');
    c.setRoot(63);
    c.setSectionHits(2, 'pitch/madness/First Pattern');
    c.setSectionDrums(0, SampleRole.kick, DrumFill.standard);
    c.setSectionDrums(1, SampleRole.hat, DrumFill.clear);
    final t = c.transcription!;
    expect(t.source, TranscriptionSource.user);
    expect(t.sections[2].kind, SectionKind.madness);
    expect(t.sections[1].title, 'The drop');
    expect(t.rootKey, 63);
    expect(t.kick.where((b) => b < 16), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
    expect(t.hat.where((b) => b >= 16 && b < 48), isEmpty);
    expect(t.hits.where((h) => h.beat >= 48).map((h) => h.semitone).toSet(), isNot({0}));
    expect(store.readJson<Map<String, dynamic>>('sparta.fix.${_source.key}'), isNotNull);

    // The same base again: the fixes come back.
    final c2 = SpartaController(EngineController(), store: store)..debugUseBase(_prepared(), source: _source);
    expect(c2.transcriptionFixed, isTrue);
    expect(c2.transcription!.sections[2].kind, SectionKind.madness);
    expect(c2.transcription!.rootKey, 63);

    c2.resetFixes();
    expect(c2.transcriptionFixed, isFalse);
    expect(c2.transcription!.rootKey, 62);
    expect(store.readJson<Map<String, dynamic>>('sparta.fix.${_source.key}'), isNull);
  });

  test('section choices follow their section through splits and merges', () async {
    final (c, _) = await controller();
    c.setWords(2, '');
    c.setPitch(1, PitchMode.pattern, pattern: 'pitch/chorus/Original');
    c.splitSection(1, 32);
    expect(c.currentSections.length, 4);
    expect(c.choiceAt(1).pitch, PitchMode.pattern);
    expect(c.choiceAt(2).pitch, PitchMode.pattern);
    expect(c.choiceAt(3).words, '');
    c.mergeSectionWithNext(1);
    expect(c.currentSections.length, 3);
    expect(c.choiceAt(1).pitch, PitchMode.pattern);
    expect(c.choiceAt(2).words, '');
  });

  test('the chart follows the base: words in the chorus, base hits elsewhere, drums on its drums', () async {
    final (c, _) = await controller();
    final chart = c.chart;
    final chorus = c.currentSections[1];
    expect(chart.where((n) => n.role == SampleRole.pitch && chorus.contains(n.beat)), isEmpty);
    expect(chart.where((n) => n.role == SampleRole.word && chorus.contains(n.beat)), isNotEmpty);
    expect(chart.where((n) => n.role == SampleRole.kick).map((n) => n.beat), c.transcription!.kick);
    expect(chart.where((n) => n.role == SampleRole.quote), hasLength(1));
    // No words outside the sections the wiki has word patterns for.
    expect(chart.where((n) => n.role == SampleRole.word && n.beat >= 48), isEmpty);
    // Pitch in the chorus is an option.
    c.setPitchInChorus(true);
    expect(c.chart.where((n) => n.role == SampleRole.pitch && chorus.contains(n.beat)), isNotEmpty);
  });

  test('the line can be edited word by word', () async {
    final (c, _) = await controller();
    c.debugUseLine(
      const SpokenLine(
        sourceIndex: 0,
        start: 0,
        end: 1,
        words: [
          LineWord(0, 0.4),
          LineWord(0.4, 1.0, cuts: [0.7]),
        ],
      ),
    );
    expect(c.stepDone(SpartaStep.line), isTrue);
    c.editLine((l) => l.splitWord(1, 0.7));
    expect(c.line!.words.length, 3);
    c.editLine((l) => l.mergeWithNext(0));
    expect(c.line!.slots.keys, ['1', '1A', '1B', '2']);
  });

  test('a fixed transcription is saved and sent as a prefilled issue', () async {
    final (c, _) = await controller();
    c.setRoot(63);
    final dir = await Directory.systemTemp.createTemp('sparta_submit_');
    addTearDown(() => dir.delete(recursive: true));
    final path = await c.saveTranscription(dir.path, credit: 'Tester');
    expect(p.basename(path), 'Sparta Test Base.sparta.json');
    final saved = BaseTranscription.decode(File(path).readAsStringSync());
    expect(saved.rootKey, 63);
    expect(saved.credit, 'Tester');
    expect(saved.catalogId, 'test/base');
    final url = c.submissionUrl(credit: 'Tester', notes: 'root was D#');
    expect(url.toString(), startsWith(BaseLibrary.issueUrl));
    expect(url.queryParameters['catalog'], 'test/base');
    expect(url.queryParameters['notes'], 'root was D#');
  });

  test('random mode is off by default and remembered when changed', () async {
    final (c, store) = await controller();
    expect(c.random.enabled, isFalse);
    expect(c.visuals.style.name, 'classic');
    expect(c.enhance.layerDrums, isFalse);
    c.setRandom(c.random.copyWith(enabled: true, freestyles: false));
    final c2 = SpartaController(EngineController(), store: store);
    expect(c2.random.enabled, isTrue);
    expect(c2.random.freestyles, isFalse);
    expect(const RandomOptions().enabled, isFalse);
  });
}
