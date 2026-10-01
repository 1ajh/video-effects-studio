import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'base.dart';
import 'chart_import.dart';
import 'model.dart';
import 'transcription.dart';

class MidiNote {
  MidiNote(this.tick, this.length, this.key, this.velocity, {this.channel = 0});
  final int tick;
  int length;
  final int key;
  final int velocity;
  final int channel;
}

class MidiTrack {
  MidiTrack(this.name, [List<MidiNote>? notes]) : notes = notes ?? [];
  String name;
  final List<MidiNote> notes;
  int? program;
}

class MidiFormatException implements Exception {
  MidiFormatException(this.message);
  final String message;
  @override
  String toString() => 'Not a readable MIDI file: $message';
}

/// Standard MIDI File (format 0/1) reader and format-1 writer.
class MidiFile {
  MidiFile({this.ppq = 480, List<MidiTrack>? tracks, this.bpm = 120, List<(int, String)>? markers})
    : tracks = tracks ?? [],
      markers = markers ?? [];

  final int ppq;
  final List<MidiTrack> tracks;

  /// First tempo in the file (tempo changes are rare in Sparta bases).
  double bpm;
  int timeSigNum = 4;
  final List<(int, String)> markers;

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  static MidiFile parse(Uint8List bytes) {
    final r = _Reader(bytes);
    if (bytes.length < 14 || r.ascii(4) != 'MThd') throw MidiFormatException('missing MThd header');
    final hlen = r.u32();
    final format = r.u16();
    final ntrks = r.u16();
    final division = r.u16();
    r.pos = 8 + hlen;
    if (division & 0x8000 != 0) throw MidiFormatException('SMPTE time division is not supported');
    final file = MidiFile(ppq: division);
    var tempoSet = false;
    for (var t = 0; t < ntrks && r.pos + 8 <= bytes.length; t++) {
      final id = r.ascii(4);
      final len = r.u32();
      final end = math.min(bytes.length, r.pos + len);
      if (id != 'MTrk') {
        r.pos = end;
        continue;
      }
      var tick = 0;
      var status = 0;
      String? name;
      final open = <int, List<MidiNote>>{};
      final byChannel = <int, List<MidiNote>>{};
      final programs = <int, int>{};
      while (r.pos < end) {
        tick += r.varint();
        var b = r.u8();
        if (b < 0x80) {
          // Running status.
          r.pos--;
          b = status;
        } else if (b < 0xF0) {
          status = b;
        }
        if (b == 0xFF) {
          final type = r.u8();
          final l = r.varint();
          final data = r.bytes(l);
          switch (type) {
            case 0x03:
              name ??= _text(data);
            case 0x06:
              file.markers.add((tick, _text(data)));
            case 0x51 when data.length == 3 && !tempoSet:
              final us = (data[0] << 16) | (data[1] << 8) | data[2];
              if (us > 0) file.bpm = 60000000 / us;
              tempoSet = true;
            case 0x58 when data.isNotEmpty:
              file.timeSigNum = data[0];
            case 0x2F:
              r.pos = end;
          }
          continue;
        }
        if (b == 0xF0 || b == 0xF7) {
          r.pos += r.varint();
          continue;
        }
        final kind = b & 0xF0, ch = b & 0x0F;
        switch (kind) {
          case 0x90 || 0x80:
            final key = r.u8(), vel = r.u8();
            final slot = ch * 128 + key;
            if (kind == 0x90 && vel > 0) {
              final n = MidiNote(tick, 0, key, vel, channel: ch);
              open.putIfAbsent(slot, () => []).add(n);
              byChannel.putIfAbsent(ch, () => []).add(n);
            } else {
              final q = open[slot];
              if (q != null && q.isNotEmpty) {
                final n = q.removeAt(0);
                n.length = math.max(1, tick - n.tick);
              }
            }
          case 0xC0:
            programs[ch] = r.u8();
          case 0xD0:
            r.u8();
          default:
            r.pos += 2;
        }
      }
      r.pos = end;
      // Notes never released last a 16th.
      for (final q in open.values) {
        for (final n in q) {
          if (n.length == 0) n.length = math.max(1, division ~/ 4);
        }
      }
      final channels = byChannel.keys.toList()..sort();
      if (channels.length <= 1 || format == 1) {
        final track = MidiTrack(name ?? 'Track ${t + 1}', [for (final c in channels) ...byChannel[c]!]);
        if (channels.isNotEmpty) track.program = programs[channels.first];
        if (track.notes.isNotEmpty || name != null) file.tracks.add(track);
      } else {
        // Format 0: one track per channel.
        for (final c in channels) {
          file.tracks.add(
            MidiTrack(c == 9 ? 'Drums (ch 10)' : 'Channel ${c + 1}', byChannel[c]!)..program = programs[c],
          );
        }
      }
    }
    file.tracks.removeWhere((t) => t.notes.isEmpty);
    return file;
  }

  static String _text(List<int> data) {
    try {
      return utf8.decode(data).trim();
    } catch (_) {
      return latin1.decode(data).trim();
    }
  }

  /// Converts to an importable chart.
  ChartSource toChartSource(String name, String path) => ChartSource(
    name: name,
    path: path,
    bpm: double.parse(bpm.toStringAsFixed(3)),
    beatsPerBar: timeSigNum <= 0 ? 4 : timeSigNum,
    tracks: [
      for (var i = 0; i < tracks.length; i++)
        ChartTrack(
          id: 'm$i',
          name: tracks[i].name,
          detail: '${tracks[i].notes.length} notes',
          drumKit: tracks[i].notes.isNotEmpty && tracks[i].notes.every((n) => n.channel == 9),
          notes: [
            for (final n in tracks[i].notes..sort((a, b) => a.tick.compareTo(b.tick)))
              RawNote(n.tick / ppq, n.length / ppq, n.key, velocity: n.velocity / 127),
          ],
        ),
    ],
    markers: [for (final m in markers) ChartMarker(m.$1 / ppq, m.$2)],
  );

  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------

  Uint8List encode() {
    final out = BytesBuilder();
    out.add(ascii.encode('MThd'));
    out.add(_u32(6));
    out.add(_u16(1));
    out.add(_u16(tracks.length + 1));
    out.add(_u16(ppq));

    // Conductor track: tempo, time signature, section markers.
    final conductor = <(int, List<int>)>[
      (0, [0xFF, 0x03, ..._vlq('Tempo'.length), ...ascii.encode('Tempo')]),
      (0, [0xFF, 0x58, 4, timeSigNum, 2, 24, 8]),
      (0, [0xFF, 0x51, 3, ..._u24((60000000 / bpm).round())]),
      for (final m in markers) (m.$1, [0xFF, 0x06, ..._vlq(utf8.encode(m.$2).length), ...utf8.encode(m.$2)]),
    ];
    out.add(_track(conductor));

    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      final nameBytes = utf8.encode(t.name);
      final ev = <(int, List<int>)>[
        (0, [0xFF, 0x03, ..._vlq(nameBytes.length), ...nameBytes]),
        if (t.program != null) (0, [0xC0 | (t.notes.isEmpty ? 0 : t.notes.first.channel), t.program!]),
      ];
      for (final n in t.notes) {
        ev.add((n.tick + n.length, [0x80 | n.channel, n.key, 0]));
        ev.add((n.tick, [0x90 | n.channel, n.key, n.velocity.clamp(1, 127)]));
      }
      out.add(_track(ev));
    }
    return out.toBytes();
  }

  static List<int> _track(List<(int, List<int>)> events) {
    // Stable sort by tick; note-offs were added before note-ons at equal ticks.
    final indexed = [for (var i = 0; i < events.length; i++) (events[i].$1, i, events[i].$2)]
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final body = <int>[];
    var last = 0;
    for (final e in indexed) {
      body.addAll(_vlq(e.$1 - last));
      body.addAll(e.$3);
      last = e.$1;
    }
    body.addAll([0, 0xFF, 0x2F, 0]);
    return [...ascii.encode('MTrk'), ..._u32(body.length), ...body];
  }

  static List<int> _vlq(int v) {
    final bytes = <int>[v & 0x7F];
    v >>= 7;
    while (v > 0) {
      bytes.insert(0, (v & 0x7F) | 0x80);
      v >>= 7;
    }
    return bytes;
  }

  static List<int> _u32(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
  static List<int> _u24(int v) => [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
  static List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

  // ---------------------------------------------------------------------------
  // Sparta exports
  // ---------------------------------------------------------------------------

  /// The remix chart, one track per lane: the pitch lane at the base's
  /// root key plus its semitones, chorus words on C4, C#4… (1, 2, 3…),
  /// percussion on GM drum keys, the quote on C5.
  static MidiFile fromChart(SpartaBase base) {
    const ppq = 480;
    int t(double beats) => (beats * ppq).round();
    const drumKeys = {SampleRole.kick: 36, SampleRole.snare: 38, SampleRole.hat: 42, SampleRole.quote: 72};
    final file = MidiFile(ppq: ppq, bpm: base.bpm, markers: [for (final s in base.sections) (t(s.startBeat), s.title)])
      ..timeSigNum = base.beatsPerBar;
    final slots = wordSlotOrder(base.chart);
    for (final (i, role) in SampleRole.values.indexed) {
      final lane = base.lane(role);
      if (lane.isEmpty) continue;
      int key(ChartNote n) => switch (role) {
        SampleRole.pitch => base.rootKey + n.semitone,
        SampleRole.word => 60 + math.max(0, slots.indexOf(n.slot)),
        _ => drumKeys[role]!,
      };
      file.tracks.add(
        MidiTrack(role == SampleRole.word ? 'Chorus words (${slots.join(' ')})' : '${role.label} sample', [
          for (final n in lane)
            MidiNote(t(n.beat), math.max(1, t(n.length)), key(n).clamp(0, 127), (n.velocity * 127).round(), channel: i),
        ]),
      );
    }
    return file;
  }

  /// What the base plays, as transcribed: its hit / lead notes and its
  /// kicks, snares and hats.
  static MidiFile fromTranscription(BaseTranscription tr) {
    const ppq = 480;
    int t(double beats) => (beats * ppq).round();
    final file = MidiFile(ppq: ppq, bpm: tr.bpm, markers: [for (final s in tr.sections) (t(s.startBeat), s.title)])
      ..timeSigNum = tr.beatsPerBar;
    file.tracks.add(
      MidiTrack('Hits (${tr.rootName} root)', [
        for (final h in tr.hits)
          MidiNote(
            t(h.beat),
            math.max(1, t(h.length)),
            (tr.rootKey + h.semitone).clamp(0, 127),
            (h.velocity * 127).round(),
          ),
      ]),
    );
    for (final (role, key) in const [(SampleRole.kick, 36), (SampleRole.snare, 38), (SampleRole.hat, 42)]) {
      final beats = tr.drums(role);
      if (beats.isEmpty) continue;
      file.tracks.add(MidiTrack(role.label, [for (final b in beats) MidiNote(t(b), t(0.25), key, 110, channel: 9)]));
    }
    return file;
  }
}

/// The chorus-word slots a chart uses, in natural order (1, 2, 3, 3A, 3B, 4…).
List<String> wordSlotOrder(Iterable<ChartNote> chart) {
  final slots = {
    for (final n in chart)
      if (n.role == SampleRole.word && n.slot.isNotEmpty) n.slot,
  }.toList()..sort(compareSlots);
  return slots;
}

int compareSlots(String a, String b) {
  final na = int.tryParse(a.replaceAll(RegExp('[A-Z]'), '')) ?? 0;
  final nb = int.tryParse(b.replaceAll(RegExp('[A-Z]'), '')) ?? 0;
  return na != nb ? na.compareTo(nb) : a.compareTo(b);
}

class _Reader {
  _Reader(this.data);
  final Uint8List data;
  int pos = 0;

  int u8() => pos < data.length ? data[pos++] : 0;
  int u16() => (u8() << 8) | u8();
  int u32() => (u16() << 16) | u16();
  String ascii(int n) => String.fromCharCodes(bytes(n));
  List<int> bytes(int n) {
    final start = math.min(pos, data.length);
    final end = math.min(data.length, pos + n);
    final out = data.sublist(start, end);
    pos = pos + n;
    return out;
  }

  int varint() {
    var v = 0;
    for (var i = 0; i < 4; i++) {
      final b = u8();
      v = (v << 7) | (b & 0x7F);
      if (b & 0x80 == 0) break;
    }
    return v;
  }
}
