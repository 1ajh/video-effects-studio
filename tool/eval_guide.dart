import 'dart:io';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/flp.dart';
import 'package:video_effects_studio/core/sparta/pattern_match.dart';

void main(List<String> args) {
  final files = Directory(args[0]).listSync(recursive: true).whereType<File>().where((f) => f.path.toLowerCase().endsWith('.flp')).toList()..sort((a, b) => a.path.compareTo(b.path));
  final limit = args.length > 1 ? int.parse(args[1]) : files.length;
  final matcher = PatternMatcher();
  var found = 0, total = 0;
  final sw = Stopwatch()..start();
  for (final f in files.take(limit)) {
    ChartSource src;
    try {
      src = FlpProject.parse(f.readAsBytesSync()).toChartSource(f.path);
    } catch (_) {
      continue;
    }
    total++;
    final bars = src.bars;
    final results = <String, (double, int, Map<String, int>)>{};
    for (final t in src.tracks) {
      if (t.isDrums || t.notes.isEmpty) continue;
      final onsets = [for (final n in t.notes) Onset(n.beat * 4, n.key, length: n.length * 4)]..sort((a, b) => a.step.compareTo(b.step));
      var sum = 0.0;
      var windows = 0;
      final secs = <String, int>{};
      for (var b = 0; b < bars; b += 2) {
        final m = matcher.best(onsets, b, maxBars: 4);
        if (m != null && m.score >= 0.75) {
          sum += m.score;
          windows++;
          secs[m.pattern.section] = (secs[m.pattern.section] ?? 0) + 1;
        }
      }
      results[t.name] = (sum, windows, secs);
    }
    final ranked = results.entries.toList()..sort((a, b) => b.value.$1.compareTo(a.value.$1));
    final top = ranked.isEmpty ? null : ranked.first;
    if (top != null && top.value.$2 >= 2) found++;
    final rel = f.path.substring(args[0].length);
    print('${rel.padRight(70).substring(0, 70)} | ${top == null ? '-' : '${top.key} (${top.value.$2}/${(bars / 2).ceil()} win) ${top.value.$3}'}${ranked.length > 1 ? ' | 2nd: ${ranked[1].key} (${ranked[1].value.$2})' : ''}');
  }
  print('guide found in $found / $total bases, ${sw.elapsed.inSeconds}s');
}
