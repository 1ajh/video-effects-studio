import 'dart:io';
import 'package:video_effects_studio/core/sparta/flp.dart';

void main(List<String> args) {
  final proj = FlpProject.parse(File(args[0]).readAsBytesSync());
  final ppq = proj.ppq;
  print('version ${proj.version} ppq $ppq bpm ${proj.bpm} ts ${proj.timeSigNum} title "${proj.title}"');
  print('markers: ${proj.markers.map((m) => '${(m.$1 / ppq / 4).toStringAsFixed(1)}:${m.$2}').join(', ')}');
  print('channels:');
  for (final c in proj.channels) {
    print('  ${c.index}: ${c.displayName} | ${c.plugin ?? ''} | ${c.samplePath ?? ''}');
  }
  print('patterns:');
  for (final p in proj.patterns.values) {
    final chans = <int, int>{};
    for (final n in p.notes) { chans[n.channel] = (chans[n.channel] ?? 0) + 1; }
    print('  ${p.number}: "${p.name ?? ''}" len ${(p.lengthTicks / ppq / 4).toStringAsFixed(2)} bars, notes by ch $chans');
  }
  print('clips (bar: pattern@track len):');
  final cl = [...proj.clips]..sort((a, b) => a.position != b.position ? a.position - b.position : a.track - b.track);
  for (final c in cl) {
    final p = proj.patterns[c.pattern];
    print('  bar ${(c.position / ppq / 4 + 1).toStringAsFixed(2)} len ${(c.length / ppq / 4).toStringAsFixed(2)} t${c.track} p${c.pattern} "${p?.name ?? ''}"');
  }
}
