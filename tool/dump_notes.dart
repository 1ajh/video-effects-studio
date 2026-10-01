import 'dart:io';
import 'package:video_effects_studio/core/sparta/flp.dart';

const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
String nn(int k) => '${names[k % 12]}${k ~/ 12}';

void main(List<String> args) {
  final proj = FlpProject.parse(File(args[0]).readAsBytesSync());
  final want = args.skip(1).map(int.parse).toSet();
  final q = proj.ppq / 4; // 16th
  for (final p in proj.patterns.values) {
    if (want.isNotEmpty && !want.contains(p.number)) continue;
    final ns = [...p.notes]..sort((a, b) => a.position - b.position);
    print('pattern ${p.number}: ' + ns.map((n) => '${nn(n.key)}@${(n.position / q).toStringAsFixed(1)}/${(n.length / q).toStringAsFixed(1)}c${n.channel}').join(' '));
  }
  // arrangement of chosen patterns
  final cl = [...proj.clips]..sort((a, b) => a.position - b.position);
  print('arrangement: ' + cl.where((c) => want.isEmpty || want.contains(c.pattern)).map((c) => 'b${(c.position / proj.ppq / 4 + 1).toStringAsFixed(1)}:p${c.pattern}').join(' '));
}
