import 'dart:math' as math;

import 'model.dart';

/// Edits to a base's sections (kinds, names, boundaries). Sections are
/// labels over the base: they choose which word / pitch patterns play and
/// how the video is laid out, never the base's own notes.
class SectionOps {
  const SectionOps._();

  /// Changes the kind of section [i] (its custom name no longer applies).
  static List<Section> relabel(List<Section> s, int i, SectionKind kind) {
    final x = s[i];
    return [...s]..[i] = Section(kind, x.startBeat, x.endBeat);
  }

  /// A custom name for section [i] (empty restores the kind's name).
  static List<Section> rename(List<Section> s, int i, String name) {
    final x = s[i];
    return [...s]..[i] = Section(x.kind, x.startBeat, x.endBeat, name: name.trim());
  }

  /// Splits section [i] at [beat] (strictly inside it); both halves keep
  /// its kind and name.
  static List<Section> split(List<Section> s, int i, double beat) {
    final x = s[i];
    if (beat <= x.startBeat + 1e-9 || beat >= x.endBeat - 1e-9) return s;
    return [
      ...s.take(i),
      Section(x.kind, x.startBeat, beat, name: x.name),
      Section(x.kind, beat, x.endBeat, name: x.name),
      ...s.skip(i + 1),
    ];
  }

  /// Joins section [i] with the next one, keeping [i]'s kind and name.
  static List<Section> mergeWithNext(List<Section> s, int i) {
    if (i + 1 >= s.length) return s;
    final x = s[i];
    return [...s.take(i), Section(x.kind, x.startBeat, s[i + 1].endBeat, name: x.name), ...s.skip(i + 2)];
  }

  /// Moves the boundary between sections [i] and [i] + 1 to the bar line
  /// nearest [beat], keeping both at least one bar long.
  static List<Section> moveBoundary(List<Section> s, int i, double beat, int beatsPerBar) {
    if (i + 1 >= s.length) return s;
    final a = s[i], b = s[i + 1];
    final bpb = beatsPerBar.toDouble();
    if (b.endBeat - a.startBeat < 2 * bpb) return s;
    final at = ((beat / bpb).round() * bpb).clamp(a.startBeat + bpb, b.endBeat - bpb).toDouble();
    if ((at - a.endBeat).abs() < 1e-9) return s;
    return [...s]
      ..[i] = Section(a.kind, a.startBeat, at, name: a.name)
      ..[i + 1] = Section(b.kind, at, b.endBeat, name: b.name);
  }

  /// Another base's layout fitted to a base [endBeat] long, bar for bar
  /// (cut or stretched at the end).
  static List<Section> fit(List<Section> layout, double endBeat, int beatsPerBar) {
    final bpb = beatsPerBar.toDouble();
    final out = <Section>[];
    for (final s in layout) {
      final start = out.isEmpty ? 0.0 : out.last.endBeat;
      if (start >= endBeat - 1e-9) break;
      final stop = math.min(endBeat, (s.endBeat / bpb).round() * bpb);
      if (stop <= start + 1e-9) continue;
      out.add(Section(s.kind, start, stop, name: s.name));
    }
    if (out.isEmpty) return [Section(SectionKind.other, 0, endBeat)];
    final last = out.last;
    if (last.endBeat < endBeat) out[out.length - 1] = Section(last.kind, last.startBeat, endBeat, name: last.name);
    return out;
  }

  /// Whether [s] covers 0..[endBeat] without gaps or overlaps.
  static bool valid(List<Section> s, double endBeat) {
    if (s.isEmpty || s.first.startBeat.abs() > 1e-6 || (s.last.endBeat - endBeat).abs() > 1e-6) return false;
    for (var i = 0; i < s.length; i++) {
      if (s[i].endBeat <= s[i].startBeat) return false;
      if (i > 0 && (s[i].startBeat - s[i - 1].endBeat).abs() > 1e-6) return false;
    }
    return true;
  }
}
