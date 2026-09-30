import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_effects_studio/core/sparta/base_renderer.dart';
import 'package:video_effects_studio/core/sparta/chart_import.dart';
import 'package:video_effects_studio/core/sparta/composer.dart';
import 'package:video_effects_studio/core/sparta/flm.dart';
import 'package:video_effects_studio/core/sparta/flp.dart';
import 'package:video_effects_studio/core/sparta/midi.dart';
import 'package:video_effects_studio/core/sparta/model.dart';

void main() {
  group('MIDI', () {
    test('chart export round-trips through the importer', () {
      final base = Composer(seed: 4).compose(defaultPlan(length: RemixLength.short)).base;
      final bytes = MidiFile.fromChart(base).encode();
      final src = MidiFile.parse(bytes).toChartSource('Round trip', 'x.mid');
      expect(src.bpm, closeTo(base.bpm, 0.01));
      final mapping = src.guessMapping();
      expect(mapping.values.whereType<SampleRole>().toSet(), SampleRole.values.toSet());
      final back = src.toBase(mapping);
      int order(ChartNote x, ChartNote y) =>
          x.beat != y.beat ? x.beat.compareTo(y.beat) : x.semitone.compareTo(y.semitone);
      for (final role in SampleRole.values) {
        final a = base.lane(role)..sort(order), b = back.lane(role)..sort(order);
        expect(b.length, a.length, reason: role.name);
        for (var i = 0; i < a.length; i++) {
          expect(b[i].beat, closeTo(a[i].beat, 1e-3));
          expect(b[i].length, closeTo(a[i].length, 1e-3));
        }
        if (role.isTonal) {
          // Same melody up to a whole-octave choice of root.
          final offset = b.first.semitone - a.first.semitone;
          expect(offset % 12, 0);
          for (var i = 0; i < a.length; i++) {
            expect(b[i].semitone - a[i].semitone, offset);
          }
        }
      }
      // Section markers survive.
      expect(back.sections.map((s) => s.kind), base.sections.map((s) => s.kind));
    });

    test('an instrumental-only MIDI gets an automatic chart that follows its harmony', () {
      final original = Composer(seed: 2).compose(defaultPlan());
      final bytes = MidiFile.fromScore(original).encode();
      final src = MidiFile.parse(bytes).toChartSource('Instrumental', 'i.mid');
      expect(src.tracks.any((t) => t.drumKit), isTrue);
      final mapping = src.guessMapping();
      expect(mapping.values.whereType<SampleRole>(), isEmpty);
      final base = src.toBase(mapping, seed: 9);
      expect(base.lane(SampleRole.pitch), isNotEmpty);
      expect(base.notes, contains('automatically'));
      // Harmony detection: bar roots match what was composed.
      var agree = 0;
      for (var b = 0; b < original.base.barRoots.length; b++) {
        if (base.barRoots[b] == original.base.barRoots[b]) agree++;
      }
      expect(agree / original.base.barRoots.length, greaterThan(0.85));
      // Sample drums lock to the instrumental's own kicks.
      final kicks = original.score.where((e) => e.instrument == Instrument.kick).map((e) => e.beat).toSet();
      for (final n in base.lane(SampleRole.kick)) {
        expect(kicks.any((k) => (k - n.beat).abs() < 1e-3), isTrue, reason: '${n.beat}');
      }
    });

    test('a transposed instrumental shifts the sample melody with it', () {
      final original = Composer(seed: 2).compose(defaultPlan(length: RemixLength.short));
      final shifted = Composition(
        original.base,
        [
          for (final e in original.score)
            ScoreEvent(e.instrument, e.beat, e.length, midi: [for (final m in e.midi) m + 3], velocity: e.velocity),
        ],
        style: original.style,
        seed: original.seed,
      );
      final src = MidiFile.parse(MidiFile.fromScore(shifted).encode()).toChartSource('F', 'f.mid');
      final base = src.toBase(src.guessMapping(), seed: 1);
      final ref = MidiFile.parse(MidiFile.fromScore(original).encode()).toChartSource('D', 'd.mid');
      final refBase = ref.toBase(ref.guessMapping(), seed: 1);
      final a = refBase.lane(SampleRole.pitch), b = base.lane(SampleRole.pitch);
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect(b[i].semitone - a[i].semitone, 3);
      }
    });

    test('rejects non-MIDI data', () {
      expect(
        () => MidiFile.parse(Uint8List.fromList(utf8.encode('hello world, not midi'))),
        throwsA(isA<MidiFormatException>()),
      );
    });
  });

  test('imported projects re-synthesize into a playable base', () {
    final original = Composer(seed: 3).compose(defaultPlan(length: RemixLength.short, enabled: {SectionKind.chorus}));
    final src = MidiFile.parse(MidiFile.fromScore(original).encode()).toChartSource('R', 'r.mid');
    final mapping = src.guessMapping();
    final base = src.toBase(mapping);
    final comp = resynthesize(src, base, mapping);
    expect(
      comp.score.map((e) => e.instrument).toSet(),
      containsAll([Instrument.kick, Instrument.bass, Instrument.stab]),
    );
    final audio = BaseRenderer().render(comp);
    expect(audio.duration, closeTo(base.durationSeconds, 0.01));
    expect(audio.rms(), greaterThan(0.02));
  });

  group('FLP', () {
    test('reads tempo, channels, patterns, playlist and markers', () {
      final bytes = _FlpWriter.sample();
      final proj = FlpProject.parse(bytes);
      expect(proj.bpm, 150);
      expect(proj.ppq, 96);
      expect(proj.channels.map((c) => c.displayName), ['Kick', 'Pitch sample', 'Bass']);
      expect(proj.patterns[1]!.notes, hasLength(4));
      expect(proj.clips, hasLength(3));
      final src = proj.toChartSource('/bases/test.flp');
      expect(src.markers.map((m) => m.name), ['Intro', 'Chorus']);
      final pitch = src.tracks.firstWhere((t) => t.name == 'Pitch sample');
      // Pattern 2 is placed at bar 2 and bar 3 (8 and 12 beats).
      expect(pitch.notes.map((n) => n.beat), [8, 9, 12, 13]);
      final mapping = src.guessMapping();
      expect(mapping['c1'], SampleRole.pitch);
      expect(mapping['c0'], isNull);
      final base = src.toBase(mapping);
      expect(base.bpm, 150);
      expect(base.lane(SampleRole.pitch).map((n) => n.semitone).toSet(), {0, 3});
      // Sample kicks follow the Kick channel.
      expect(base.lane(SampleRole.kick).map((n) => n.beat), [0, 1, 2, 3]);
      expect(base.sections.first.kind, SectionKind.intro);
      expect(base.sections[1].kind, SectionKind.chorus);
    });

    test('rejects other files', () {
      expect(() => FlpProject.parse(Uint8List(40)), throwsA(isA<FlpFormatException>()));
    });
  });

  group('FLM (FL Studio Mobile)', () {
    test('decodes a real clip chunk', () {
      final clip = _realClip();
      final parsed = FlmProject.readClip(clip)!;
      expect(parsed.start, 0);
      expect(parsed.length, 8);
      expect(parsed.notes, hasLength(28));
      expect(parsed.notes.first.key, 58);
      expect(parsed.notes.first.lengthBeats, 1.0);
      expect(parsed.notes[3].tick, 32);
      expect(parsed.notes.last.tick, 768);
      expect(parsed.notes.every((n) => n.velocity == 127), isTrue);
    });

    test('reads tempo, tracks, clips and drum pads of a project', () {
      final proj = FlmProject.parse(_FlmWriter.sample());
      expect(proj.bpm, 140);
      expect(proj.name, 'test base');
      expect(proj.padNames, {0: 'FL Kick 1', 1: 'FL Snare 2', 2: 'FL Grv CH 03'});
      expect(proj.tracks.map((t) => t.name), ['Bass', 'Drums 1']);
      final src = proj.toChartSource('/x/test base.flm');
      final drums = src.tracks.firstWhere((t) => t.name == 'Drums 1');
      expect(drums.drumKit, isTrue);
      expect(drums.instrumentFor(drums.notes.first), Instrument.kick);
      final bass = src.tracks.firstWhere((t) => t.name == 'Bass');
      // Clip placed at beat 4 with note ticks 0 and 128 (one beat).
      expect(bass.notes.map((n) => n.beat), [4, 5, 8, 9]);
      final base = src.toBase(src.guessMapping());
      expect(base.bpm, 140);
      expect(base.lane(SampleRole.pitch), isNotEmpty);
      // Bar 1 has no harmony yet (carries D), bar 2 is D, bar 3 E-flat.
      expect(base.barRoots.take(3), [0, 0, 1]);
      expect(base.lane(SampleRole.kick), hasLength(16));
    });

    test('reads older projects: clip positions, loops, offsets and per-track kits', () {
      final proj = FlmProject.parse(_FlmWriter.oldFormat());
      expect(proj.bpm, 150);
      expect(proj.tracks.map((t) => t.name), ['Pluck', 'Beat']);
      final src = proj.toChartSource('/x/old.flm');
      final pluck = src.tracks.firstWhere((t) => t.name == 'Pluck');
      // The 4-beat loop plays twice; the trimmed clip starts 1 beat in.
      expect(pluck.notes.map((n) => n.beat), [8, 10, 12, 14, 20, 21]);
      expect(pluck.notes.map((n) => n.key), [62, 65, 62, 65, 63, 65]);
      expect(pluck.drumKit, isFalse);
      final beat = src.tracks.firstWhere((t) => t.name == 'Beat');
      expect(beat.drumKit, isTrue);
      expect(beat.padNames, {0: 'Big Boom', 1: 'Crack Snare'});
      expect(beat.notes.map(beat.instrumentFor).toSet(), {Instrument.kick, Instrument.snare});
    });

    test('rejects other files', () {
      expect(() => FlmProject.parse(Uint8List(40)), throwsA(isA<FlmFormatException>()));
    });
  });
}

// ----------------------------------------------------------------------------
// Fixtures
// ----------------------------------------------------------------------------

/// A CLIP chunk from a real FL Studio Mobile project, reassembled from its
/// base64 text (the prefix is re-aligned to the base64 quantum).
FlmChunk _realClip() {
  const head = 'ABDTElQewIAAAAAAAAyMExDQ0xIZCUAAAAAAAAAAAAAAAAAAAAAACBAAAAAAAAAAAABAAAAAAAAAAAAAAAA';
  const tail =
      'Wk9PTSAAAABBlPxdTmAHQCZLYgJZw0xACY8gY7emfD+hxzAEUfWyP0VWTjIWAgAAEwAAAAAAAAAAAAAA8D86ALJ//38AAAAAAAAAAAAAANA/PQCyf/9/'
      'AAAAAAAAAAAAAADQP0EAsn//fwAgAAAAAAAAAAAA0D8/ALJ//38AQAAAAAAAAAAAANA/PQCyf/9/AEAAAAAAAAAAAADQP0EAsn//fwBgAAAAAAAAAAAA0D89'
      'ALJ//38AYAAAAAAAAAAAANA/PwCyf/9/AIAAAAAAAAAAAADgPz8Asn//fwCAAAAAAAAAAAAA6D88ALJ//38AgAAAAAAAAAAAAPA/OACyf/9/AMAAAAAAAAAA'
      'AADgP0EAsn//fwDgAAAAAAAAAAAA0D87ALJ//38AAAEAAAAAAAAAAPA/NgCyf/9/AAABAAAAAAAAAADwPzoAsn//fwAAAQAAAAAAAAAA4D89ALJ//38AAAEA'
      'AAAAAAAAAOA/PwCyf/9/AEABAAAAAAAAAADgPz0Asn//fwBAAQAAAAAAAAAA4D9BALJ//38AgAEAAAAAAAAAAPA/PACyf/9/AIABAAAAAAAAAADwPz8Asn//'
      'fwCAAQAAAAAAAAAA4D9EALJ//38AwAEAAAAAAAAAAOA/QQCyf/9/AMABAAAAAAAAAADgP0MAsn//fwAAAgAAAAAAAAAA0D9BALJ//38AQAIAAAAAAAAAANA/'
      'QQCyf/9/AKACAAAAAAAAAADQP0EAsn//fwAAAwAAAAAAAAAA4D9BALJ//38A';
  var s = '${'A' * ((4 - head.length % 4) % 4)}$head$tail';
  s += '=' * ((4 - s.length % 4) % 4);
  final bytes = base64.decode(s);
  final at = _indexOf(bytes, ascii.encode('CLIP'));
  final bd = ByteData.sublistView(bytes);
  final size = bd.getUint32(at + 4, Endian.little);
  return FlmChunk('CLIP', Uint8List.sublistView(bytes, at + 8, at + 8 + size));
}

int _indexOf(List<int> hay, List<int> needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length && ok; j++) {
      ok = hay[i + j] == needle[j];
    }
    if (ok) return i;
  }
  return -1;
}

class _Bytes {
  final b = BytesBuilder();
  void u8(int v) => b.addByte(v & 0xFF);
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void i32(int v) => b.add((ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List());
  void f64(double v) => b.add((ByteData(8)..setFloat64(0, v, Endian.little)).buffer.asUint8List());
  void raw(List<int> v) => b.add(v);
  void zeros(int n) => b.add(Uint8List(n));
  Uint8List done() => b.toBytes();
}

/// Minimal FL Studio 20-style project writer for tests.
class _FlpWriter {
  static Uint8List sample() {
    final ev = _Bytes();
    void text(int id, String s, {bool utf16 = true}) {
      final data = utf16
          ? [
              for (final c in s.codeUnits) ...[c & 0xFF, c >> 8],
              0,
              0,
            ]
          : [...ascii.encode(s), 0];
      ev.u8(id);
      var len = data.length;
      do {
        var byte = len & 0x7F;
        len >>= 7;
        if (len > 0) byte |= 0x80;
        ev.u8(byte);
      } while (len > 0);
      ev.raw(data);
    }

    void word(int id, int v) {
      ev.u8(id);
      ev.u16(v);
    }

    void dword(int id, int v) {
      ev.u8(id);
      ev.u32(v);
    }

    void data(int id, List<int> d) {
      ev.u8(id);
      var len = d.length;
      do {
        var byte = len & 0x7F;
        len >>= 7;
        if (len > 0) byte |= 0x80;
        ev.u8(byte);
      } while (len > 0);
      ev.raw(d);
    }

    List<int> notes(List<(int pos, int ch, int len, int key)> n) {
      final b = _Bytes();
      for (final x in n) {
        b.u32(x.$1);
        b.u16(0);
        b.u16(x.$2);
        b.u32(x.$3);
        b.u16(x.$4);
        b.u16(0);
        b.raw([120, 0, 64, 0, 64, 100, 128, 128]);
      }
      return b.done();
    }

    List<int> item(int pos, int pattern, int len, int track) {
      final b = _Bytes();
      b.u32(pos);
      b.u16(20480);
      b.u16(20480 + pattern);
      b.u32(len);
      b.u16(499 - track);
      b.u16(0);
      b.u16(120);
      b.u16(64);
      b.raw([0x40, 0x64, 0x80, 0x80]);
      b.i32(-1);
      b.i32(-1);
      b.zeros(28);
      return b.done();
    }

    text(199, '20.8.4.1873', utf16: false);
    dword(156, 150000);
    ev.u8(17);
    ev.u8(4);
    // Patterns (notes first, like FL writes them).
    word(65, 1);
    data(224, notes([for (var i = 0; i < 4; i++) (i * 96, 0, 48, 60)]));
    word(65, 2);
    data(224, notes([(0, 1, 90, 62), (96, 1, 90, 65), (0, 2, 180, 38), (192, 2, 180, 39)]));
    word(65, 1);
    text(193, 'Intro');
    word(65, 2);
    text(193, 'Chorus');
    // Channels.
    for (final (i, name) in ['Kick', 'Pitch sample', 'Bass'].indexed) {
      word(64, i);
      ev.u8(21);
      ev.u8(0);
      text(201, '');
      text(203, name);
      if (i == 0) text(196, r'C:\Samples\kick.wav');
    }
    word(99, 0);
    text(241, 'Arrangement');
    data(233, [...item(0, 1, 384, 0), ...item(768, 2, 384, 1), ...item(1152, 2, 384, 1)]);

    final body = ev.done();
    final out = _Bytes();
    out.raw(ascii.encode('FLhd'));
    out.u32(6);
    out.u16(0);
    out.u16(3);
    out.u16(96);
    out.raw(ascii.encode('FLdt'));
    out.u32(body.length);
    out.raw(body);
    return out.done();
  }
}

/// Minimal FL Studio Mobile project writer mirroring the observed layout.
class _FlmWriter {
  static List<int> chunk(String tag, List<int> payload) {
    final b = _Bytes();
    b.raw(ascii.encode(tag));
    b.u32(payload.length);
    b.raw(payload);
    return b.done();
  }

  /// Containers start with a u32 (a clip's position in ticks, else 0) and a
  /// 4-byte magic.
  static List<int> container(String tag, String magic, List<List<int>> children, {int prefix = 0}) =>
      chunk(tag, [...(_Bytes()..u32(prefix)).done(), ...ascii.encode(magic), for (final c in children) ...c]);

  static List<int> padded(String s, int n) => [...utf8.encode(s), ...List.filled(n - utf8.encode(s).length, 0)];

  /// A clip at [start] beats. Newer apps write `CLHd` + `EVN2` (sized
  /// records); older ones `CLHD` + `EVNT` (bare 18-byte records).
  static List<int> clip(
    double start,
    double length,
    List<(int tick, double len, int key)> notes, {
    double loop = 0,
    double offset = 0,
    bool old = false,
  }) {
    final h = _Bytes()
      ..f64(loop)
      ..f64(length)
      ..f64(offset)
      ..u32(1)
      ..zeros(old ? 0 : 9);
    final z = _Bytes()..zeros(32);
    final e = _Bytes();
    if (!old) e.u16(20);
    for (final n in notes) {
      e
        ..u32(n.$1)
        ..f64(n.$2)
        ..u16(n.$3)
        ..raw([
          0xB2,
          0x7F,
          0xFF,
          0x7F,
          if (!old) ...[0, 0],
        ]);
    }
    return container('CLIP', old ? '10LC' : '20LC', [
      chunk(old ? 'CLHD' : 'CLHd', h.done()),
      chunk('ZOOM', z.done()),
      chunk(old ? 'EVNT' : 'EVN2', e.done()),
    ], prefix: (start * 128).round());
  }

  /// [kind]: 0 instrument, 1 master, 2 audio, 3 drum kit.
  static List<int> track(String name, List<List<int>> clips, {int kind = 0, bool old = false}) =>
      container('CHNL', old ? '10HC' : '20HC', [
        chunk('CHHD', padded(name, 1080)),
        chunk('TRKH', [
          ...chunk(
            'DESc',
            (_Bytes()
                  ..u32(kind)
                  ..zeros(12))
                .done(),
          ),
          for (final c in clips) ...c,
        ]),
      ]);

  static List<int> pad(int index, String name, {bool old = false}) {
    final main = _Bytes()
      ..i32(-1)
      ..f64(index.toDouble())
      ..raw(padded(name, 64));
    return chunk(old ? 'SMPL' : 'SMPl', [...ascii.encode(old ? '10LS' : '20LS'), ...chunk('MAIN', main.done())]);
  }

  static List<int> rack([List<List<int>> pads = const []]) => container('RACK', '10KR', [
    chunk('RHED', List.filled(16, 0xFF)),
    container('RSMP', '10MS', [chunk('PADS', List.generate(22, (i) => i)), ...pads]),
  ]);

  static List<int> head(String name, double bpm) {
    final h = _Bytes()
      ..u32(1)
      ..u32(0)
      ..raw(padded(name, 256))
      ..zeros(8)
      ..f64(bpm)
      ..f64(4.5)
      ..zeros(40);
    return chunk('HEAD', h.done());
  }

  /// An older-app project: one rack per channel, in order.
  static Uint8List oldFormat() => Uint8List.fromList([
    ...ascii.encode('10LF'),
    ...head('old base', 150),
    ...rack(),
    ...rack(),
    ...rack([pad(0, 'Big Boom', old: true), pad(1, 'Crack Snare', old: true)]),
    ...track('MASTER', [], kind: 1, old: true),
    ...track('Pluck', [
      // A 4-beat loop stretched to 8 beats, then a clip trimmed by 1 beat.
      clip(8, 8, [(0, 1, 62), (256, 1, 65)], loop: 4, old: true),
      clip(20, 2, [(0, 1, 62), (128, 1, 63), (256, 1, 65)], offset: 1, old: true),
    ], old: true),
    ...track(
      'Beat',
      [
        clip(0, 4, [(0, 0.125, 0), (128, 0.125, 1), (256, 0.125, 0), (384, 0.125, 1)], old: true),
      ],
      kind: 3,
      old: true,
    ),
  ]);

  static Uint8List sample() {
    final rack = container('RACK', '10KR', [
      chunk('RHED', List.filled(16, 0xFF)),
      container('RSMP', '10MS', [
        chunk('PADS', List.generate(22, (i) => i)),
        pad(0, 'FL Kick 1'),
        pad(1, 'FL Snare 2'),
        pad(2, 'FL Grv CH 03'),
        pad(3, '<empty>'),
      ]),
    ]);
    // D for a bar, then E-flat: bass notes on beats 1 and 2 of each bar.
    final bass = track('Bass', [
      clip(4, 8, [(0, 0.75, 38), (128, 0.75, 38), (512, 0.75, 39), (640, 0.75, 39)]),
    ]);
    final drums = track('Drums 1', [
      clip(0, 16, [
        for (var b = 0; b < 16; b++) ...[(b * 128, 0.0, 0), if (b.isOdd) (b * 128, 0.0, 1), (b * 128 + 64, 0.0, 2)],
      ]),
    ]);
    final master = container('CHNL', '20HC', [chunk('CHHD', padded('MASTER', 1080))]);
    return Uint8List.fromList([
      ...ascii.encode('10LF'),
      ...head('test base', 140),
      ...chunk('TDIV', [4, 4]),
      ...rack,
      ...master,
      ...bass,
      ...drums,
    ]);
  }
}
