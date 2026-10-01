import 'package:video_effects_studio/core/sparta/patterns.dart';

void main() {
  final lib = PatternLibrary.instance;
  var bad = 0;
  for (final p in lib.all) {
    final whole = (p.steps % 16).abs() < 1e-6 || (p.steps % 8).abs() < 1e-6;
    if (!whole) bad++;
    print('${whole ? '  ' : '!!'} ${p.kind.name.padRight(5)} ${p.section.padRight(12)} ${p.steps.toStringAsFixed(2).padLeft(7)} ${p.hits.length.toString().padLeft(3)} ${p.title}');
  }
  print('${lib.all.length} patterns, $bad not on a half-bar');
}
