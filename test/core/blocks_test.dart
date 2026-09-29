import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/ffmpeg/blocks.dart';
import 'package:video_effects_studio/core/ffmpeg/filter_graph.dart';

void main() {
  group('fmt', () {
    test('formats without exponents or trailing zeros', () {
      expect(fmt(2), '2');
      expect(fmt(2.0), '2');
      expect(fmt(0.5), '0.5');
      expect(fmt(1 / 3), '0.333333');
      expect(fmt(-0.0000001), '0');
      expect(fmt(1e-7), '0');
      expect(fmt(123456.789), '123456.789');
    });
  });

  group('atempo', () {
    double product(String chain) =>
        RegExp(r'atempo=([\d.]+)').allMatches(chain).map((m) => double.parse(m.group(1)!)).fold(1.0, (a, b) => a * b);

    for (final f in [0.1, 0.25, 0.5, 0.75, 1.5, 2.0, 3.0, 8.0, 16.0]) {
      test('factor $f stays within [0.5, 2] per stage', () {
        final chain = atempo(f);
        for (final m in RegExp(r'atempo=([\d.]+)').allMatches(chain)) {
          final v = double.parse(m.group(1)!);
          expect(v, inInclusiveRange(0.5, 2.0));
        }
        expect(product(chain), closeTo(f, 1e-4));
      });
    }

    test('identity is a no-op', () => expect(atempo(1), 'anull'));
    test('rejects non-positive', () => expect(() => atempo(0), throwsArgumentError));
  });

  group('pitch', () {
    test('zero semitones is a no-op', () => expect(pitch(0), 'anull'));

    test('octave up doubles the rate and halves the tempo', () {
      final chain = pitch(12);
      expect(chain, startsWith('asetrate=96000,aresample=48000,atempo=0.5'));
      expect(chain, endsWith('asetnsamples=n=1024:p=0'));
    });

    test('never depends on rubberband', () {
      for (var s = -36; s <= 36; s++) {
        expect(pitch(s), isNot(contains('rubberband')));
      }
    });

    test('semitone ratio', () {
      expect(semitoneRatio(12), closeTo(2, 1e-9));
      expect(semitoneRatio(-12), closeTo(0.5, 1e-9));
      expect(semitoneRatio(7), closeTo(1.4983, 1e-4));
    });
  });

  group('parsePitchList', () {
    test('accepts commas, spaces and plus signs', () {
      expect(parsePitchList('-12, 0 +4;7|12'), [-12, 0, 4, 7, 12]);
    });
    test('drops junk and clamps', () {
      expect(parsePitchList('a, 99, -99, 3.5'), [48, -48, 3.5]);
    });
    test('respects the max', () {
      expect(parsePitchList(List.filled(40, '1').join(','), maxItems: 16), hasLength(16));
    });
  });

  group('chord', () {
    test('mixes one pitched branch per voice without normalizing', () {
      final g = FilterGraph();
      final out = chord(g, 'in', [-5, 0, 4]);
      final graph = g.build();
      expect(graph, contains('asplit=3'));
      expect(graph, contains('amix=inputs=3:duration=first:dropout_transition=0:normalize=0'));
      expect(graph, endsWith('[$out]'));
    });

    test('single voice skips split/mix', () {
      final g = FilterGraph();
      chord(g, 'in', [7]);
      expect(g.build(), isNot(contains('amix')));
    });
  });

  group('FilterGraph', () {
    test('labels are unique and chains are joined with ;', () {
      final g = FilterGraph();
      final a = g.v('0:v', 'negate');
      final b = g.v(a, '');
      final parts = g.split(b, 2);
      g.join(parts, 'hstack');
      expect({a, b, ...parts}.length, 4);
      expect(g.build(), '[0:v]negate[n0];[n0]null[n1];[n1]split=2[n2][n3];[n2][n3]hstack[n4]');
    });
  });
}
