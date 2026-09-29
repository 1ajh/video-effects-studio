import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'base.dart';
import 'chart_import.dart';
import 'model.dart';

class FlpFormatException implements Exception {
  FlpFormatException(this.message);
  final String message;
  @override
  String toString() => 'Not a readable FL Studio project: $message';
}

class FlpChannel {
  FlpChannel(this.index);
  final int index;
  int type = 0;
  String? name;
  String? legacyName;
  String? plugin;
  String? samplePath;

  String get displayName {
    for (final n in [name, legacyName]) {
      if (n != null && n.trim().isNotEmpty) return n.trim();
    }
    final s = samplePath;
    if (s != null && s.isNotEmpty) return p.basenameWithoutExtension(s.replaceAll('\\', '/'));
    if (plugin != null && plugin!.isNotEmpty) return plugin!;
    return 'Channel ${index + 1}';
  }
}

class FlpNote {
  const FlpNote(this.position, this.channel, this.length, this.key, this.velocity);
  final int position;
  final int channel;
  final int length;
  final int key;
  final int velocity;
}

class FlpPattern {
  FlpPattern(this.number);
  final int number;
  String? name;
  final List<FlpNote> notes = [];

  int get lengthTicks => notes.fold(0, (m, n) => math.max(m, n.position + math.max(1, n.length)));
}

class FlpClip {
  const FlpClip(this.position, this.pattern, this.length, this.track, this.startOffset, this.endOffset);
  final int position;
  final int pattern;
  final int length;
  final int track;
  final int startOffset;
  final int endOffset;
}

/// Reads the parts of an FL Studio `.flp` needed to use it as a Sparta base:
/// tempo, channels, pattern notes, playlist arrangement and markers.
///
/// Walks the event stream by ID range (byte/word/dword/varlen), so unknown
/// events from any FL version are skipped safely.
class FlpProject {
  FlpProject._();

  String version = '';
  int ppq = 96;
  double? bpm;
  int timeSigNum = 4;
  String title = '';
  final List<FlpChannel> channels = [];
  final Map<int, FlpPattern> patterns = {};
  final List<FlpClip> clips = [];
  final List<(int, String)> markers = [];
  final List<String> warnings = [];

  static FlpProject parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 22 || ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'FLhd') {
      throw FlpFormatException('missing FLhd header');
    }
    final proj = FlpProject._();
    final headerLen = bd.getUint32(4, Endian.little);
    proj.ppq = bd.getUint16(12, Endian.little);
    var pos = 8 + headerLen;
    if (pos + 8 > bytes.length || ascii.decode(bytes.sublist(pos, pos + 4), allowInvalid: true) != 'FLdt') {
      throw FlpFormatException('missing FLdt chunk');
    }
    final dataLen = bd.getUint32(pos + 4, Endian.little);
    pos += 8;
    final end = math.min(bytes.length, pos + dataLen);

    var utf16 = true;
    FlpChannel? channel;
    FlpPattern? pattern;
    var arrangement = -1;
    var inChannelScope = false;
    int? coarseTempo;
    int? fineTempo;
    int? markerPos;
    var playlistRead = false;

    String text(Uint8List d) {
      if (utf16 && d.length >= 2) {
        final units = <int>[];
        for (var i = 0; i + 1 < d.length; i += 2) {
          final u = d[i] | (d[i + 1] << 8);
          if (u == 0) break;
          units.add(u);
        }
        return String.fromCharCodes(units);
      }
      final z = d.indexOf(0);
      return latin1.decode(z < 0 ? d : d.sublist(0, z));
    }

    FlpPattern pat(int n) => proj.patterns.putIfAbsent(n, () => FlpPattern(n));

    while (pos < end) {
      final id = bytes[pos++];
      int value = 0;
      Uint8List? data;
      if (id < 64) {
        if (pos >= end) break;
        value = bytes[pos];
        pos += 1;
      } else if (id < 128) {
        if (pos + 2 > end) break;
        value = bd.getUint16(pos, Endian.little);
        pos += 2;
      } else if (id < 192) {
        if (pos + 4 > end) break;
        value = bd.getUint32(pos, Endian.little);
        pos += 4;
      } else {
        var len = 0, shift = 0;
        while (pos < end) {
          final b = bytes[pos++];
          len |= (b & 0x7F) << shift;
          shift += 7;
          if (b & 0x80 == 0 || shift > 28) break;
        }
        if (pos + len > end) {
          proj.warnings.add('Project data ends early; read what was there.');
          break;
        }
        data = Uint8List.sublistView(bytes, pos, pos + len);
        pos += len;
      }

      switch (id) {
        case 199: // FLVersion (ASCII)
          proj.version = latin1.decode(data!.where((b) => b != 0).toList());
          final parts = proj.version.split('.').map((s) => int.tryParse(s) ?? 0).toList();
          final major = parts.isNotEmpty ? parts[0] : 0, minor = parts.length > 1 ? parts[1] : 0;
          utf16 = major > 11 || (major == 11 && minor >= 5);
        case 156: // Tempo ×1000
          if (value > 10000) proj.bpm = value / 1000;
        case 66: // legacy coarse tempo
          coarseTempo = value;
        case 93: // legacy fine tempo
          fineTempo = value;
        case 17:
          if (value > 0) proj.timeSigNum = value;
        case 194:
          proj.title = text(data!);
        case 64: // Channel new
          channel = FlpChannel(value);
          proj.channels.add(channel);
          inChannelScope = true;
        case 21:
          if (inChannelScope) channel?.type = value;
        case 192: // Channel _Name (old)
          if (inChannelScope) channel?.legacyName ??= text(data!);
        case 203: // Plugin display name
          if (inChannelScope) channel?.name ??= text(data!);
        case 201: // Plugin internal name
          if (inChannelScope) channel?.plugin ??= text(data!);
        case 196: // Sample path
          if (inChannelScope) channel?.samplePath ??= text(data!);
        case 65: // Pattern new
          pattern = pat(value);
          inChannelScope = false;
        case 193:
          pattern?.name = text(data!);
        case 224: // Pattern notes
          if (pattern != null) _readNotes(data!, pattern, proj);
        case 99: // Arrangement new
          arrangement = value;
          inChannelScope = false;
        case 148: // Time marker position
          if (arrangement <= 0) markerPos = value;
        case 205: // Time marker name
          if (markerPos != null && markerPos < 0x08000000) proj.markers.add((markerPos, text(data!)));
          markerPos = null;
        case 233: // Playlist
          if (!playlistRead && arrangement <= 0) {
            _readPlaylist(data!, proj);
            playlistRead = true;
          }
          inChannelScope = false;
      }
    }
    if (proj.bpm == null && coarseTempo != null) {
      proj.bpm = coarseTempo + (fineTempo ?? 0) / 1000;
    }
    return proj;
  }

  static void _readNotes(Uint8List d, FlpPattern pattern, FlpProject proj) {
    const size = 24;
    if (d.length % size != 0) {
      proj.warnings.add('Pattern ${pattern.number} uses an unknown note layout and was skipped.');
      return;
    }
    final bd = ByteData.sublistView(d);
    for (var i = 0; i + size <= d.length; i += size) {
      final key = bd.getUint16(i + 12, Endian.little);
      final vel = d[i + 21];
      if (key > 131) continue;
      pattern.notes.add(
        FlpNote(
          bd.getUint32(i, Endian.little),
          bd.getUint16(i + 6, Endian.little),
          math.max(1, bd.getUint32(i + 8, Endian.little)),
          key,
          vel,
        ),
      );
    }
  }

  static void _readPlaylist(Uint8List d, FlpProject proj) {
    final bd = ByteData.sublistView(d);
    // Item size changed across FL versions; pick the one that decodes.
    int? size;
    for (final s in const [80, 60, 32]) {
      if (d.length % s != 0) continue;
      var ok = true;
      for (var i = 0; i + s <= d.length && ok; i += s) {
        final base = bd.getUint16(i + 4, Endian.little);
        final len = bd.getUint32(i + 8, Endian.little);
        ok = base == 20480 && len > 0 && len < 1 << 28;
      }
      if (ok) {
        size = s;
        break;
      }
    }
    if (size == null) {
      if (d.isNotEmpty) proj.warnings.add('Playlist layout not recognised; using patterns in order.');
      return;
    }
    for (var i = 0; i + size <= d.length; i += size) {
      final index = bd.getUint16(i + 6, Endian.little);
      if (index <= 20480) continue; // audio/automation clip
      final track = 499 - bd.getUint16(i + 12, Endian.little);
      final start = bd.getInt32(i + 24, Endian.little);
      final stop = bd.getInt32(i + 28, Endian.little);
      proj.clips.add(
        FlpClip(bd.getUint32(i, Endian.little), index - 20480, bd.getUint32(i + 8, Endian.little), track, start, stop),
      );
    }
  }

  /// Flattens the arrangement into per-channel note tracks.
  ChartSource toChartSource(String path) {
    final ppqD = ppq <= 0 ? 96.0 : ppq.toDouble();
    final byChannel = <int, List<RawNote>>{};
    void add(FlpNote n, int at, int maxLen) {
      final len = math.min(n.length, maxLen);
      if (len <= 0) return;
      byChannel
          .putIfAbsent(n.channel, () => [])
          .add(RawNote(at / ppqD, len / ppqD, n.key, velocity: (n.velocity.clamp(0, 128)) / 128));
    }

    final warn = [...warnings];
    if (clips.isNotEmpty) {
      for (final c in clips) {
        final pattern = patterns[c.pattern];
        if (pattern == null) continue;
        final from = c.startOffset < 0 ? 0 : c.startOffset;
        final to = c.endOffset < 0 ? from + c.length : c.endOffset;
        for (final n in pattern.notes) {
          if (n.position < from || n.position >= to) continue;
          final rel = n.position - from;
          if (rel >= c.length) continue;
          add(n, c.position + rel, math.min(c.length - rel, to - n.position));
        }
      }
    } else {
      // No playlist (pattern mode): chain patterns in number order.
      var at = 0;
      final ordered = patterns.values.where((p) => p.notes.isNotEmpty).toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      for (final pt in ordered) {
        for (final n in pt.notes) {
          add(n, at + n.position, n.length);
        }
        final bar = (ppqD * timeSigNum).round();
        at += ((pt.lengthTicks + bar - 1) ~/ bar) * bar;
      }
      if (ordered.isNotEmpty) warn.add('No playlist found; patterns were chained in order.');
    }

    // Section markers: time markers, else section-named pattern clips.
    final marks = [for (final m in markers) ChartMarker(m.$1 / ppqD, m.$2)];
    if (marks.isEmpty) {
      final sorted = [...clips]..sort((a, b) => a.position.compareTo(b.position));
      String? last;
      for (final c in sorted) {
        final name = patterns[c.pattern]?.name;
        if (name == null || sectionKindFor(name) == SectionKind.other || name == last) continue;
        if (marks.isNotEmpty && (c.position / ppqD - marks.last.beat).abs() < 1e-6) continue;
        marks.add(ChartMarker(c.position / ppqD, name));
        last = name;
      }
    }

    final byIndex = {for (final c in channels) c.index: c};
    final tracks = <ChartTrack>[];
    for (final e in (byChannel.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
      final ch = byIndex[e.key];
      final name = ch?.displayName ?? 'Channel ${e.key + 1}';
      final sample = ch?.samplePath;
      final isFpc = (ch?.plugin ?? '').toLowerCase().contains('fpc');
      tracks.add(
        ChartTrack(
          id: 'c${e.key}',
          name: name,
          notes: e.value..sort((a, b) => a.beat.compareTo(b.beat)),
          drumKit: isFpc,
          detail: [
            if (sample != null && sample.isNotEmpty) p.basename(sample.replaceAll('\\', '/')),
            if (ch?.plugin != null && ch!.plugin!.isNotEmpty) ch.plugin!,
          ].join(' · '),
        ),
      );
    }
    if (bpm == null) warn.add('Tempo not found in the project; assuming 140 BPM.');
    return ChartSource(
      name: title.isNotEmpty ? title : p.basenameWithoutExtension(path),
      path: path,
      kind: BaseKind.flp,
      bpm: bpm ?? 140,
      beatsPerBar: timeSigNum,
      tracks: tracks,
      markers: marks,
      warnings: warn,
    );
  }
}
