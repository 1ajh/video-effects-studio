import 'dart:io';
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/sparta/audio_base.dart';
import 'package:video_effects_studio/core/sparta/audio_transcriber.dart';

import 'package:video_effects_studio/core/sparta/flp.dart';
import 'package:video_effects_studio/core/sparta/project_transcriber.dart';

Future<void> main(List<String> args) async {
  final src = FlpProject.parse(File(args[0]).readAsBytesSync()).toChartSource(args[0]);
  final p = ProjectTranscriber().transcribe(src);
  final audio = await AudioBuffer.decode('ffmpeg', args[1], sampleRate: AudioBaseAnalyzer.sampleRate);
  final an = AudioBaseAnalyzer().analyze(audio);

  final a = AudioTranscriber().transcribe(an);
  final spb = 60 / p.bpm;
  final firstBeat = src.tracks.expand((t) => t.notes).fold<double?>(null, (m, n) => m == null || n.beat < m ? n.beat : m);
  final off = AudioBaseAnalyzer().alignHits(audio, [for (final b in [...p.kick, ...p.snare]) b * spb]..sort(), firstNoteSeconds: firstBeat == null ? null : firstBeat * spb);
  print('bpm p ${p.bpm} a ${an.bpm}; project beat0 at $off s; audio bar1 at ${an.firstDownbeat}; diff beats ${(an.firstDownbeat - off) / spb}');
  print('P kick ${p.kick.length} snare ${p.snare.length} hat ${p.hat.length}; A kick ${a.kick.length} snare ${a.snare.length} hat ${a.hat.length}');
  String row(List<double> beats, double o, double from) => beats.where((b) => o + b * spb >= from && o + b * spb < from + 4 * 4 * spb).map((b) => (o + b * spb).toStringAsFixed(2)).join(' ');
  for (final t0 in [10.0, 30.0, 60.0]) {
    print('--- window from $t0 s');
    print('P kick : ${row(p.kick, off, t0)}');
    print('A kick : ${row(a.kick, a.audioOffset, t0)}');
    print('P snare: ${row(p.snare, off, t0)}');
    print('A snare: ${row(a.snare, a.audioOffset, t0)}');
    print('P hat  : ${row(p.hat, off, t0)}');
    print('A hat  : ${row(a.hat, a.audioOffset, t0)}');
  }
  for (final t in src.tracks.where((t) => t.isDrums)) {
    print('drum track ${t.name} ${t.detail} notes ${t.notes.length}');
  }
}
