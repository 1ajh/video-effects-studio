import 'dart:io';
import 'package:video_effects_studio/core/sparta/flp.dart';
import 'package:video_effects_studio/core/sparta/project_transcriber.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

void main(List<String> args) {
  final src = FlpProject.parse(File(args[0]).readAsBytesSync()).toChartSource(args[0]);
  final t = ProjectTranscriber().transcribe(src);
  print('bpm ${t.bpm} root ${keyName(t.rootKey)} bars ${t.bars} hits ${t.hits.length} kick ${t.kick.length} snare ${t.snare.length} hat ${t.hat.length}');
  print('sections: ${t.sections.map((s) => '${s.kind.name}@${(s.startBeat / 4).round()}-${(s.endBeat / 4).round()}').join(' ')}');
  print('patterns: ${t.patterns.entries.map((e) => 'b${e.key}:${e.value.split('/').last}').join(', ')}');
  for (var bar = 0; bar < t.bars; bar += 2) {
    final hs = t.hits.where((h) => h.beat >= bar * 4 && h.beat < bar * 4 + 8).toList();
    if (hs.isEmpty) continue;
    print('bar ${bar + 1}: ${hs.map((h) => '${h.semitone}@${(h.beat * 4 - bar * 16).toStringAsFixed(1)}').join(' ')}');
  }
}
