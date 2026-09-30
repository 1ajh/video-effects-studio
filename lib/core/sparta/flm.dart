import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'base.dart';
import 'chart_import.dart';

class FlmFormatException implements Exception {
  FlmFormatException(this.message);
  final String message;
  @override
  String toString() => 'Not a readable FL Studio Mobile project: $message';
}

/// A chunk of an FL Studio Mobile project: 4-char tag, u32 size, payload.
class FlmChunk {
  FlmChunk(this.tag, this.data);
  final String tag;
  final Uint8List data;

  /// Sub-chunks starting at [offset] (containers prefix them with a few
  /// header bytes, e.g. `u32 + "20HC"` for tracks).
  List<FlmChunk> children([int offset = 0]) => FlmProject.walk(data, offset);

  /// Sub-chunks after the first [skip] bytes, trying the usual container
  /// header sizes.
  List<FlmChunk> childrenAuto() {
    for (final skip in const [8, 0, 4, 12]) {
      final c = children(skip);
      if (c.isNotEmpty) return c;
    }
    return const [];
  }

  FlmChunk? find(String t) {
    for (final c in childrenAuto()) {
      if (c.tag == t) return c;
    }
    return null;
  }
}

class FlmNote {
  const FlmNote(this.tick, this.lengthBeats, this.key, this.velocity);
  final int tick;
  final double lengthBeats;
  final int key;
  final int velocity;
}

class FlmClip {
  FlmClip(this.start, this.length, this.offset, this.notes, {this.loop = 0});

  /// Timeline position and length, in beats.
  final double start;
  final double length;

  /// Where in its content the clip starts, in beats.
  final double offset;

  /// Content loop length in beats: a clip stretched past it repeats its
  /// content (0 = no loop).
  final double loop;
  final List<FlmNote> notes;

  /// The clip's notes on the timeline: (beat, length, note).
  Iterable<(double, double, FlmNote)> placed() sync* {
    final looping = loop >= 0.25 && length / loop < 4096;
    for (final n in notes) {
      final at = n.tick / FlmProject.ticksPerBeat;
      if (looping && at >= loop - 1e-9) continue;
      var t = at - offset;
      if (looping) {
        while (t < -1e-9) {
          t += loop;
        }
      }
      for (; t < length - 1e-9; t += loop) {
        if (t >= -1e-9) {
          var len = n.lengthBeats <= 0 ? 0.25 : n.lengthBeats;
          len = math.min(len, length - t);
          if (looping) len = math.min(len, loop - at);
          yield (start + math.max(0, t), len, n);
        }
        if (!looping) break;
      }
    }
  }
}

class FlmTrack {
  FlmTrack(this.name, {this.kind = 0, this.channel = 0});
  final String name;

  /// Position among the project's channels (the master included).
  final int channel;

  /// Track type from its descriptor: 0 instrument, 1 master, 2 audio,
  /// 3 drum kit.
  final int kind;
  final List<FlmClip> clips = [];
  Map<int, String> padNames = const {};

  bool get isDrumKit => kind == 3;
}

/// Reader for FL Studio Mobile `.flm` projects (reverse-engineered: tempo,
/// tracks, clips and their notes, drum-kit pad names).
class FlmProject {
  FlmProject._();

  /// Note positions inside clips are in ticks of this many per beat.
  static const ticksPerBeat = 128;

  String name = '';
  double? bpm;
  final List<FlmTrack> tracks = [];
  final Map<int, String> padNames = {};
  final List<String> warnings = [];
  int _channels = 0;

  static List<FlmChunk> walk(Uint8List d, int offset, {bool strict = true}) {
    final out = <FlmChunk>[];
    var pos = offset;
    final bd = ByteData.sublistView(d);
    while (pos + 8 <= d.length) {
      final tag = d.sublist(pos, pos + 4);
      if (!tag.every((b) => (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A))) {
        break;
      }
      final size = bd.getUint32(pos + 4, Endian.little);
      if (pos + 8 + size > d.length) break;
      out.add(FlmChunk(ascii.decode(tag), Uint8List.sublistView(d, pos + 8, pos + 8 + size)));
      pos += 8 + size;
    }
    // Containers only count when the whole region parses cleanly.
    return !strict || pos == d.length ? out : const [];
  }

  static String cString(Uint8List d, [int offset = 0]) {
    if (offset >= d.length) return '';
    var end = d.indexOf(0, offset);
    if (end < 0) end = d.length;
    try {
      return utf8.decode(d.sublist(offset, end)).trim();
    } catch (_) {
      return latin1.decode(d.sublist(offset, end)).trim();
    }
  }

  static FlmProject parse(Uint8List bytes) {
    if (bytes.length < 12 || ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != '10LF') {
      throw FlmFormatException('missing 10LF header');
    }
    final chunks = walk(bytes, 4, strict: false);
    if (chunks.isEmpty) throw FlmFormatException('unrecognised chunk layout');
    final proj = FlmProject._();
    final racks = <Map<int, String>>[];
    for (final c in chunks) {
      switch (c.tag) {
        case 'HEAD':
          proj.name = cString(c.data, 8);
          proj.bpm = _findTempo(c.data);
        case 'RACK':
          racks.add(_readPads(c));
        case 'CHNL':
          proj._readTrack(c);
      }
    }
    // Each track (the master included) has its own instrument rack, in the
    // same order; otherwise the first kit in the project is used.
    final firstKit = racks.firstWhere((r) => r.isNotEmpty, orElse: () => const {});
    proj.padNames.addAll(firstKit);
    for (final t in proj.tracks) {
      final pads = racks.length == proj._channels ? racks[t.channel] : const <int, String>{};
      t.padNames = pads.isNotEmpty ? pads : firstKit;
    }
    if (proj.bpm == null) proj.warnings.add('Tempo not found in the project; assuming 140 BPM.');
    return proj;
  }

  /// The tempo is stored as a float64; take the first "round" value in a
  /// plausible BPM range (layouts differ between app versions).
  static double? _findTempo(Uint8List d) {
    final bd = ByteData.sublistView(d);
    for (var i = 8; i + 8 <= d.length; i++) {
      if (bd.getUint32(i, Endian.little) != 0) continue;
      final v = bd.getFloat64(i, Endian.little);
      if (v >= 40 && v <= 400 && (v * 1000).roundToDouble() == v * 1000) return v;
    }
    return null;
  }

  /// Drum kit pads: SMPl { MAIN(i32, f64 pad, name…), … } inside RSMP.
  static Map<int, String> _readPads(FlmChunk rack) {
    final rsmp = rack.find('RSMP');
    if (rsmp == null) return const {};
    final pads = <int, String>{};
    for (final smpl in rsmp.childrenAuto().where((c) => c.tag == 'SMPl' || c.tag == 'SMPL')) {
      final main = smpl.find('MAIN');
      if (main == null || main.data.length < 13) continue;
      final pad = ByteData.sublistView(main.data).getFloat64(4, Endian.little);
      final name = cString(main.data, 12);
      if (name.isEmpty || name == '<empty>' || pad.isNaN || pad < 0 || pad > 127) continue;
      pads[pad.round()] = name;
    }
    return pads;
  }

  void _readTrack(FlmChunk chnl) {
    final parts = chnl.childrenAuto();
    String name = '';
    var kind = 0;
    final clips = <FlmClip>[];
    for (final c in parts) {
      if (c.tag == 'CHHD') name = cString(c.data);
      if (c.tag == 'TRKH') {
        for (final x in c.children()) {
          if (x.tag == 'DESc' && x.data.length >= 4) kind = ByteData.sublistView(x.data).getUint32(0, Endian.little);
          if (x.tag != 'CLIP') continue;
          final parsed = readClip(x, warnings);
          if (parsed != null) clips.add(parsed);
        }
      }
    }
    final index = _channels++;
    if (kind == 1 || (name.toUpperCase() == 'MASTER' && clips.isEmpty)) return;
    tracks.add(
      FlmTrack(name.isEmpty ? 'Track ${tracks.length + 1}' : name, kind: kind, channel: index)..clips.addAll(clips),
    );
  }

  /// Decodes one `CLIP` chunk: its timeline position (u32 ticks before the
  /// container magic), header (loop length, length, content offset in
  /// beats) and note records. Two generations exist: `CLHd` + `EVN2`
  /// (u16 record size, then records) and `CLHD`/`CLHd` + `EVNT` (18-byte
  /// records); both share the record layout (u32 tick, f64 length, u16 key).
  static FlmClip? readClip(FlmChunk clip, [List<String>? warnings]) {
    final head = clip.find('CLHd') ?? clip.find('CLHD');
    if (head == null || head.data.length < 24 || clip.data.length < 8) return null;
    final start = ByteData.sublistView(clip.data).getUint32(0, Endian.little) / ticksPerBeat;
    final hb = ByteData.sublistView(head.data);
    final loop = hb.getFloat64(0, Endian.little);
    final length = hb.getFloat64(8, Endian.little);
    final offset = hb.getFloat64(16, Endian.little);
    final notes = <FlmNote>[];
    final ev2 = clip.find('EVN2'), ev = ev2 ?? clip.find('EVNT');
    if (ev != null && ev.data.isNotEmpty) {
      final eb = ByteData.sublistView(ev.data);
      var first = 0, size = 18;
      if (ev2 != null) {
        size = ev.data.length >= 2 ? eb.getUint16(0, Endian.little) : 0;
        first = 2;
      }
      if (size >= 16 && size <= 64 && (ev2 != null || ev.data.length % size == 0)) {
        for (var i = first; i + size <= ev.data.length; i += size) {
          final len = eb.getFloat64(i + 4, Endian.little);
          notes.add(
            FlmNote(
              eb.getUint32(i, Endian.little),
              len.isFinite && len >= 0 && len < 1e4 ? len : 0,
              eb.getUint16(i + 12, Endian.little) & 0xFF,
              ev.data[i + 15] & 0x7F,
            ),
          );
        }
      } else {
        warnings?.add('A clip uses an unknown note layout and was skipped.');
      }
    }
    if (!length.isFinite || length <= 0) return null;
    return FlmClip(
      start,
      length,
      offset.isFinite && offset > 0 ? offset : 0,
      notes,
      loop: loop.isFinite && loop > 0 ? loop : 0,
    );
  }

  ChartSource toChartSource(String path) {
    final out = <ChartTrack>[];
    for (var t = 0; t < tracks.length; t++) {
      final track = tracks[t];
      final notes = <RawNote>[
        for (final c in track.clips)
          for (final (beat, len, n) in c.placed())
            RawNote(beat, len, n.key, velocity: n.velocity == 0 ? 1 : n.velocity / 127),
      ];
      if (notes.isEmpty) continue;
      notes.sort((a, b) => a.beat.compareTo(b.beat));
      final lower = track.name.toLowerCase();
      final kit =
          track.isDrumKit ||
          lower.contains('drum') ||
          lower.contains('kit') ||
          (track.kind == 0 && notes.every((n) => n.key < 16));
      out.add(
        ChartTrack(
          id: 't$t',
          name: track.name,
          notes: notes,
          drumKit: kit,
          padNames: kit ? track.padNames : const {},
          detail: '${track.clips.length} clip${track.clips.length == 1 ? '' : 's'}',
        ),
      );
    }
    return ChartSource(
      name: name.isNotEmpty ? name : p.basenameWithoutExtension(path),
      path: path,
      kind: BaseKind.flp,
      bpm: bpm ?? 140,
      tracks: out,
      warnings: warnings,
    );
  }
}
