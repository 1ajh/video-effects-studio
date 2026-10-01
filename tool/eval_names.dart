import 'dart:io';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/flp.dart';

void main(List<String> args) {
  final files = Directory(args[0]).listSync(recursive: true).whereType<File>().where((f) => f.path.toLowerCase().endsWith('.flp')).toList();
  final words = <String, int>{};
  var bases = 0, withPitchName = 0, withHitName = 0, withLeadName = 0;
  for (final f in files) {
    ChartSource src;
    try { src = FlpProject.parse(f.readAsBytesSync()).toChartSource(f.path); } catch (_) { continue; }
    bases++;
    var p = false, h = false, l = false;
    for (final t in src.tracks) {
      if (t.isDrums || t.notes.isEmpty) continue;
      final n = t.name.toLowerCase();
      for (final w in n.split(RegExp(r'[^a-z]+'))) { if (w.length > 2) words[w] = (words[w] ?? 0) + 1; }
      if (n.contains('pitch')) p = true;
      if (n.contains('hit') || n.contains('orch') || n.contains('stab')) h = true;
      if (n.contains('lead') || n.contains('main') || n.contains('melod')) l = true;
    }
    if (p) withPitchName++; if (h) withHitName++; if (l) withLeadName++;
  }
  print('bases $bases, pitch-named $withPitchName, hit/orch/stab $withHitName, lead/main/melody $withLeadName');
  final top = words.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  print(top.take(80).map((e) => '${e.key}:${e.value}').join('  '));
}
