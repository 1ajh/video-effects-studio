import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/sparta/patterns.dart';

void main() {
  final lib = PatternLibrary.instance;

  List<double> steps(Pattern p, String slot) => [
    for (final h in p.hits)
      if (h.slot == slot) h.step,
  ];

  test('the standard chorus is the 11_11_111_1_1_11 / 222_2_222_222_2_ rhythm', () {
    final p = lib.classic(PatternKind.words, 'chorus')!;
    expect(p.name, 'Standard');
    expect(p.steps, 64);
    expect(steps(p, '1').where((s) => s < 16), [0, 1, 3, 4, 6, 7, 8, 10, 12, 14, 15]);
    expect(steps(p, '2').where((s) => s < 32), [16, 17, 18, 20, 22, 23, 24, 26, 27, 28, 30]);
    expect(p.hits.every((h) => h.length == 1), isTrue);
    expect(p.slots, ['1', '2']);
  });

  test('the chorus pitch is 0 0 +1 +1 -2 -2 +1 +1 on quarter notes', () {
    final p = lib.classic(PatternKind.pitch, 'chorus')!;
    expect([for (final h in p.hits) h.semitone], [0, 0, 1, 1, -2, -2, 1, 1]);
    expect([for (final h in p.hits) h.step], [0, 4, 8, 12, 16, 20, 24, 28]);
    expect(p.hits.every((h) => h.length == 4), isTrue);
    expect(p.steps, 32);
  });

  test('DunDunDenDen words are 1, 2, 3A, 3B on quarter notes', () {
    final p = lib.classic(PatternKind.words, 'dundundenden')!;
    expect(p.steps, 16);
    expect([for (final h in p.hits) '${h.slot}@${h.step}'], ['1@0.0', '2@4.0', '3A@8.0', '3B@12.0']);
  });

  test('the epicness word pattern layers its second line of 3s by column', () {
    final p = lib.classic(PatternKind.words, 'epicness')!;
    expect(p.steps, 64);
    expect(p.slots.toSet(), {'1', '2', '3'});
    // The second line's 3s land in the last bar and a half, under the 1s.
    final late3 = [
      for (final h in p.hits)
        if (h.slot == '3' && h.step >= 40) h.step,
    ];
    expect(late3, isNotEmpty);
    expect(late3.every((s) => s >= 40 && s < 64), isTrue);
  });

  test('madness: 8-bar word pattern, both halves of the pitch pattern and the KingSpartaX37 freestyle', () {
    final words = lib.classic(PatternKind.words, 'madness')!;
    expect(words.steps, 128);
    expect(words.hits.first.step, 0);
    expect(words.hits.first.length, 2);
    final first = lib.of(PatternKind.pitch, section: 'madness').firstWhere((p) => p.name == 'First Pattern');
    expect(first.steps, 32);
    expect(first.hits.take(4).map((h) => h.semitone), [0, 0, 0, 0]);
    expect(first.hits.map((h) => h.semitone).toSet(), {0, 1, -2});
    final second = lib.of(PatternKind.pitch, section: 'madness').firstWhere((p) => p.name.contains('second half'));
    expect(second.steps, 32);
    final king = lib.of(PatternKind.words, section: 'madness').where((p) => p.name.startsWith('KingSpartaX37'));
    expect(king, hasLength(1));
    expect(king.first.slots, containsAll(['1', '2', '3', '4', '5', '6']));
  });

  test('awesomeness 1 and 2 are four bars and reach two octaves up', () {
    for (final name in ['Awesomeness 1 (Major)', 'Awesomeness 2 (Major)', 'Awesomeness 1 (Minor)']) {
      final p = lib.of(PatternKind.pitch, section: 'awesomeness').firstWhere((x) => x.name == name);
      expect(p.steps, 64, reason: name);
      expect(p.classic, isTrue);
    }
    final a1 = lib.of(PatternKind.pitch, section: 'awesomeness').firstWhere((x) => x.name == 'Awesomeness 1 (Major)');
    expect(a1.hits.map((h) => h.semitone), contains(29));
  });

  test('every classic pattern parses to whole bars', () {
    final classics = lib.all.where((p) => p.classic && p.section != 'intro').toList();
    expect(classics.length, greaterThanOrEqualTo(12));
    for (final p in classics) {
      expect(p.steps % 16, 0, reason: p.id);
    }
  });

  test('most wiki patterns land on whole bars; the rest are flagged', () {
    final regular = lib.all.where((p) => !p.irregular).length;
    expect(lib.all.length, greaterThan(300));
    expect(regular / lib.all.length, greaterThan(0.9));
    for (final p in lib.all.where((p) => !p.irregular && p.section != 'intro')) {
      expect(p.steps % 8, 0, reason: p.id);
    }
  });

  test('compact madness notation splits digits; spaced notation keeps numbers', () {
    final compact = PatternNotation.parse(PatternKind.pitch, ['00_00_0011']);
    expect(compact.hits.map((h) => h.semitone), [0, 0, 0, 0, 0, 0, 1, 1]);
    final spaced = PatternNotation.parse(PatternKind.pitch, ['0 0 12 12']);
    expect(spaced.hits.map((h) => h.semitone), [0, 0, 12, 12]);
    final marked = PatternNotation.parse(PatternKind.pitch, ['0***12***1*1*13***10*10_']);
    expect(marked.hits.map((h) => h.semitone), [0, 12, 1, 1, 13, 10, 10]);
  });

  test('32nds, 64ths and rests', () {
    final p = PatternNotation.parse(PatternKind.words, ["1'1'/2''2\"\\_1"]);
    expect([for (final h in p.hits) h.length], [0.5, 0.5, 0.25, 0.25, 1]);
    expect(p.hits.last.step, 0.5 + 0.5 + 0.5 + 0.25 + 0.25 + 0.25 + 1);
  });

  test('custom patterns round-trip through the notation', () {
    final p = PatternLibrary.custom(PatternKind.pitch, '0*** 0*** 1*** 1*** -2*** -2*** 1*** 1***');
    final text = PatternNotation.format(PatternKind.pitch, p.hits, steps: p.steps);
    final again = PatternLibrary.custom(PatternKind.pitch, text);
    expect(
      again.hits.map((h) => '${h.semitone}@${h.step}+${h.length}'),
      p.hits.map((h) => '${h.semitone}@${h.step}+${h.length}'),
    );
    expect(() => PatternLibrary.custom(PatternKind.pitch, 'hello'), throwsA(isA<PatternFormatException>()));
  });

  test('looping fills a section and cuts the last repeat', () {
    final p = lib.classic(PatternKind.pitch, 'chorus')!;
    final hits = p.looped(40);
    expect(hits.length, 10);
    expect(hits.last.step, 36);
    expect(hits.last.length, 4);
  });
}
