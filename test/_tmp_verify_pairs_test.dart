@Tags(['ffmpeg'])
@Timeout(Duration(minutes: 90))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/ffmpeg/ffmpeg_toolkit.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

const sp = '/tmp/claude-0/-home-user-video-effects-studio/fb8202e8-b6c2-5e4b-9a7d-190fe5ee267a/scratchpad';

int? lowAt(List<GuideNote> notes, double beat) {
  int? best;
  for (final n in notes) {
    if (n.beat <= beat + 0.25 && n.beat + n.length > beat + 0.05) {
      if (best == null || n.semitone < best) best = n.semitone;
    }
  }
  return best;
}

void main() {
  test('verify pairs', () async {
    final kit = (await FfmpegToolkit.locate())!;
    final engine = SpartaEngine(ffmpegPath: kit.ffmpegPath, cacheDir: '$sp/vp_cache');
    final cands = (jsonDecode(File('$sp/flp_candidates.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final results = <Map<String, Object?>>[];
    for (final c in cands) {
      final flp = '$sp/bases/files/${c['folder']}/${c['flp']}';
      final audio = '$sp/bases/files/${c['folder']}/${c['audio']}';
      try {
        final pb = await engine.prepareBase(ProjectBaseSource(projectPath: flp, audioPath: audio));
        final p = pb.transcription;
        final ab = await engine.prepareBase(AudioBaseSource(audioPath: audio));
        final a = ab.transcription;
        final dur = pb.audio.duration;
        final projSec = p.lengthBeats * 60 / p.bpm;
        final ratio = a.bpm / p.bpm;
        final tempoOk = [1.0, 2.0, 0.5].any((r) => (ratio / r - 1).abs() < 0.02);
        final agree = List<int>.filled(12, 0);
        var n = 0;
        for (var beat = 0.0; beat < p.lengthBeats; beat += 2) {
          final truth = lowAt(p.bass, beat) ?? lowAt(p.chords, beat);
          if (truth == null) continue;
          final time = p.audioOffset + beat * 60 / p.bpm;
          final ab2 = (time - a.audioOffset) * a.bpm / 60;
          if (ab2 < 0 || ab2 >= a.lengthBeats) continue;
          final r = a.chordRootAt(ab2 + 0.05);
          if (r == null) continue;
          n++;
          final tp = (p.rootKey + truth) % 12, ap = (a.rootKey + r) % 12;
          agree[(ap - tp) % 12]++;
        }
        var bestShift = 0;
        for (var s = 1; s < 12; s++) {
          if (agree[s] > agree[bestShift]) bestShift = s;
        }
        final res = {
          ...c,
          'bpm': p.bpm,
          'audioBpm': a.bpm,
          'tempoOk': tempoOk,
          'duration': dur,
          'projectSeconds': projSec,
          'n': n,
          'agree0': n == 0 ? 0 : agree[0] / n,
          'bestShift': bestShift,
          'agreeBest': n == 0 ? 0 : agree[bestShift] / n,
        };
        results.add(res);
        print(
          '${tempoOk ? 'T' : '-'} ${(dur / projSec).toStringAsFixed(2)} agree ${(res['agree0']! as double).toStringAsFixed(2)} '
          'best +$bestShift ${(res['agreeBest']! as double).toStringAsFixed(2)} n $n bpm ${p.bpm}/${a.bpm.toStringAsFixed(1)} '
          '${c['folder']} :: ${c['audio']}',
        );
      } catch (e) {
        print('ERR ${c['folder']} :: ${c['audio']}: ${'$e'.split('\n').first}');
        results.add({...c, 'error': '$e'.split('\n').first});
      }
    }
    File('$sp/flp_verified.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(results));
  });
}
