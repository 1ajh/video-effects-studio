import 'dart:io';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/flp.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/pattern_match.dart';
import 'package:video_effects_studio/core/sparta/sectioning.dart';

const letter = {
  SectionKind.intro: 'I', SectionKind.chorus: 'C', SectionKind.dundundenden: 'D', SectionKind.epicness: 'E',
  SectionKind.awesomeness: 'A', SectionKind.madness: 'M', SectionKind.outro: 'O', SectionKind.preEpicness: 'E',
  SectionKind.postEpicness: 'E', SectionKind.other: '?',
};

void main(List<String> args) {
  final root = args[0];
  final rows = File(args[1]).readAsLinesSync().where((l) => l.trim().isNotEmpty);
  var right = 0, total = 0, rightHint = 0;
  final matcher = PatternMatcher();
  final confusion = <String, int>{};
  final hintStats = <String, int>{};
  for (final row in rows) {
    final parts = row.split('\t');
    final truth = <String>[];
    for (final tok in parts[1].split(' ')) {
      final n = int.parse(tok.substring(1));
      truth.addAll(List.filled(n, tok[0]));
    }
    ChartSource src;
    try {
      src = FlpProject.parse(File('$root/${parts[0]}').readAsBytesSync()).toChartSource(parts[0]);
    } catch (e) {
      continue;
    }
    final bars = src.bars;
    final secs = sectionsFromTracks(src.tracks, bars, src.beatsPerBar);
    final pred = List.filled(bars, '?');
    for (final s in secs) {
      for (var b = (s.startBeat / 4).round(); b < (s.endBeat / 4).round() && b < bars; b++) {
        pred[b] = letter[s.kind]!;
      }
    }
    // Pattern hints: best match per 2-bar window over all non-drum tracks.
    final hint = List<String?>.filled(bars, null);
    for (var b = 0; b < bars; b += 2) {
      PatternMatch? best;
      for (final t in src.tracks) {
        if (t.isDrums || t.notes.isEmpty) continue;
        final on = [for (final n in t.notes) Onset(n.beat * 4, n.key, length: n.length * 4)]..sort((a, c) => a.step.compareTo(c.step));
        final m = matcher.best(on, b, maxBars: 4, sections: {'awesomeness'});
        if (m != null && m.score >= 0.85 && (best == null || m.score > best.score)) best = m;
      }
      if (best != null) {
        final l = {'awesomeness': 'A', 'madness': 'M', 'epicness': 'E', 'dundundenden': 'D', 'intro': 'I'}[best.pattern.section]!;
        for (var k = b; k < b + best.bars && k < bars; k++) {
          hint[k] = l;
        }
      }
    }
    for (var b = 0; b < bars && b < truth.length; b++) {
      if (truth[b] == '?') continue;
      total++;
      if (pred[b] == truth[b]) right++;
      final h = hint[b] ?? pred[b];
      if (h == truth[b]) rightHint++;
      if (hint[b] != null) {
        final key = '${hint[b]}->${truth[b]}';
        hintStats[key] = (hintStats[key] ?? 0) + 1;
      }
      final key = '${pred[b]}->${truth[b]}';
      confusion[key] = (confusion[key] ?? 0) + 1;
    }
  }
  print('bars $total: tracks ${(100 * right / total).toStringAsFixed(1)}%, with pattern hints ${(100 * rightHint / total).toStringAsFixed(1)}%');
  final hs = hintStats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  print('hint label -> truth: ${hs.map((e) => '${e.key}:${e.value}').join(' ')}');
}
