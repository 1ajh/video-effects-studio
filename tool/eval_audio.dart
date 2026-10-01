import 'dart:io';
import 'dart:math' as math;
import 'package:video_effects_studio/core/audio/audio_buffer.dart';
import 'package:video_effects_studio/core/sparta/audio_base.dart';
import 'package:video_effects_studio/core/sparta/audio_transcriber.dart';
import 'package:video_effects_studio/core/sparta/flp.dart';
import 'package:video_effects_studio/core/sparta/project_transcriber.dart';

double f1(List<double> ref, List<double> est, {double tol = 0.045}) {
  if (ref.isEmpty && est.isEmpty) return 1;
  if (ref.isEmpty || est.isEmpty) return 0;
  var hit = 0;
  final used = <int>{};
  for (final r in ref) {
    for (var i = 0; i < est.length; i++) {
      if (!used.contains(i) && (est[i] - r).abs() <= tol) {
        used.add(i);
        hit++;
        break;
      }
    }
  }
  final p = hit / est.length, rr = hit / ref.length;
  return p + rr == 0 ? 0 : 2 * p * rr / (p + rr);
}

Future<void> main(List<String> args) async {
  final root = Directory(args[0]);
  final dirs = root.listSync(recursive: true).whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
  final totals = <String, List<double>>{};
  for (final d in dirs) {
    final files = d.listSync().whereType<File>().toList();
    final flps = files.where((f) => f.path.toLowerCase().endsWith('.flp')).toList();
    final mp3s = files.where((f) => f.path.toLowerCase().endsWith('.mp3')).toList();
    if (flps.isEmpty || mp3s.isEmpty) continue;
    final flp = flps.first, mp3 = mp3s.first;
    try {
      final src = FlpProject.parse(flp.readAsBytesSync()).toChartSource(flp.path);
      final p = ProjectTranscriber().transcribe(src);
      final audio = await AudioBuffer.decode('ffmpeg', mp3.path, sampleRate: AudioBaseAnalyzer.sampleRate);
      final analysis = AudioBaseAnalyzer().analyze(audio, tempo: null);
      if ((analysis.bpm - p.bpm).abs() > 0.5) {
        print('${d.path.split('/').last}: tempo ${analysis.bpm} vs ${p.bpm} — skipped');
        continue;
      }
      final a = AudioTranscriber().transcribe(analysis);
      // Where the project's beat 0 is in the render.
      final spb = 60 / p.bpm;
      final hitsSec = [for (final b in [...p.kick, ...p.snare]) b * spb]..sort();
      final full = await AudioBuffer.decode('ffmpeg', mp3.path, sampleRate: AudioBaseAnalyzer.sampleRate);
      final firstBeat = src.tracks.expand((t) => t.notes).fold<double?>(null, (m, n) => m == null || n.beat < m ? n.beat : m);
      final off = AudioBaseAnalyzer().alignHits(full, hitsSec, firstNoteSeconds: firstBeat == null ? null : firstBeat * spb);
      List<double> secA(List<double> beats) => [for (final b in beats) a.audioOffset + b * spb];
      List<double> secP(List<double> beats) => [for (final b in beats) off + b * spb];
      final k = f1(secP(p.kick), secA(a.kick)), s = f1(secP(p.snare), secA(a.snare)), h = f1(secP(p.hat), secA(a.hat));
      final hp = [for (final x in p.hits) off + x.beat * spb], ha = [for (final x in a.hits) a.audioOffset + x.beat * spb];
      final on = f1(hp, ha);
      // Pitch class agreement on matched onsets.
      var agree = 0, n = 0;
      for (final x in a.hits) {
        final t = a.audioOffset + x.beat * spb;
        for (final y in p.hits) {
          if ((off + y.beat * spb - t).abs() <= 0.045) {
            n++;
            if ((a.rootKey + x.semitone - p.rootKey - y.semitone) % 12 == 0) agree++;
            break;
          }
        }
      }
      final pc = n == 0 ? 0.0 : agree / n;
      final rootOk = (a.rootKey - p.rootKey) % 12 == 0 ? 1.0 : 0.0;
      // Baseline: the wiki's Normal Percussion on the detected grid.
      final bars = (a.lengthBeats / 4).round();
      final nk = [for (var b = 0; b < bars * 4; b++) b.toDouble()];
      final ns = [for (var b = 0; b < bars * 4; b++) if (b % 2 == 1) b.toDouble()];
      final nh = [for (var b = 0; b < bars * 4; b++) b + 0.5];
      final bk = f1(secP(p.kick), secA(nk)), bs = f1(secP(p.snare), secA(ns)), bh = f1(secP(p.hat), secA(nh));
      for (final e in {'kick': k, 'snare': s, 'hat': h, 'hitOnset': on, 'hitPc': pc, 'root': rootOk, 'NPkick': bk, 'NPsnare': bs, 'NPhat': bh}.entries) {
        totals.putIfAbsent(e.key, () => []).add(e.value);
      }
      print('${d.path.split('/').last.padRight(34).substring(0, 34)} kick ${k.toStringAsFixed(2)} snare ${s.toStringAsFixed(2)} hat ${h.toStringAsFixed(2)} hits ${on.toStringAsFixed(2)} pc ${pc.toStringAsFixed(2)} root ${rootOk == 1 ? 'ok' : 'NO (${a.rootKey % 12} vs ${p.rootKey % 12})'} p.hits ${p.hits.length} a.hits ${a.hits.length} matchedBars ${a.patterns.length} conf ${a.confidence.toStringAsFixed(2)}');
    } catch (e) {
      print('${d.path.split('/').last}: error $e');
    }
  }
  print('MEAN ${totals.entries.map((e) => '${e.key} ${(e.value.reduce((x, y) => x + y) / e.value.length).toStringAsFixed(2)}').join('  ')}');
}
