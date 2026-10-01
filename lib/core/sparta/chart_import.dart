import 'dart:math' as math;

import 'model.dart';
import 'score.dart';

/// A note read from a MIDI/FLP/FLM project, in beats.
class RawNote {
  const RawNote(this.beat, this.length, this.key, {this.velocity = 1});
  final double beat;
  final double length;
  final int key;
  final double velocity;
  double get end => beat + length;
}

/// One instrument/track of an imported project (MIDI track, FL channel…).
class ChartTrack {
  ChartTrack({
    required this.id,
    required this.name,
    required this.notes,
    this.detail = '',
    this.drumKit = false,
    this.padNames = const {},
  });

  final String id;
  final String name;
  final List<RawNote> notes;

  /// Extra info shown in the lane mapper (sample file, plugin…).
  final String detail;

  /// Notes select drum sounds (GM drum keys, or pads of a kit).
  final bool drumKit;

  /// Kit pad names by key, when the project stores them.
  final Map<int, String> padNames;

  /// What the track is for when its name says so ("Pitch", "Chorus", "Quote"…).
  SampleRole? get guess => drumKit ? null : guessRole(name, detail);

  int get distinctKeys => notes.map((n) => n.key).toSet().length;

  double get medianKey {
    if (notes.isEmpty) return 60;
    final k = notes.map((n) => n.key).toList()..sort();
    return k[k.length ~/ 2].toDouble();
  }

  double get meanLength => notes.isEmpty ? 0 : notes.fold<double>(0, (s, n) => s + n.length) / notes.length;

  /// Looks like a drum part (kit, or a single drum sound by name).
  bool get isDrums => drumKit || drumForName(name, detail) != null;

  /// The synth voice used when re-synthesizing this track as part of a base.
  Instrument instrumentFor(RawNote n) {
    if (drumKit) {
      final pad = padNames[n.key];
      return (pad == null ? null : drumForName(pad)) ?? drumForKey(n.key, pads: padNames.isNotEmpty || n.key < 27);
    }
    final named = drumForName(name, detail);
    if (named != null) return named;
    if (medianKey < 50) return Instrument.bass;
    if (meanLength >= 1.5) return Instrument.pad;
    return Instrument.stab;
  }
}

class ChartMarker {
  const ChartMarker(this.beat, this.name);
  final double beat;
  final String name;
}

/// A project read from MIDI/FLP/FLM: its tracks, tempo and markers.
class ChartSource {
  ChartSource({
    required this.name,
    required this.path,
    required this.bpm,
    required this.tracks,
    this.beatsPerBar = 4,
    this.markers = const [],
    this.warnings = const [],
  });

  final String name;
  final String path;
  final double bpm;
  final int beatsPerBar;
  final List<ChartTrack> tracks;
  final List<ChartMarker> markers;
  final List<String> warnings;

  double get lengthBeats => tracks.fold<double>(0, (m, t) => t.notes.fold(m, (m2, n) => math.max(m2, n.end)));

  int get bars => math.max(1, (lengthBeats / beatsPerBar - 1e-6).ceil());

  /// Where the project's drums hit, in beats: kick, snare (and claps), hats.
  Map<SampleRole, List<double>> drumHits({Set<String> skip = const {}}) {
    final out = {SampleRole.kick: <double>[], SampleRole.snare: <double>[], SampleRole.hat: <double>[]};
    for (final t in tracks) {
      if (skip.contains(t.id) || !t.isDrums) continue;
      for (final n in t.notes) {
        final role = switch (t.instrumentFor(n)) {
          Instrument.kick => SampleRole.kick,
          Instrument.snare || Instrument.clap => SampleRole.snare,
          Instrument.hat || Instrument.openHat => SampleRole.hat,
          _ => null,
        };
        if (role != null) out[role]!.add(n.beat);
      }
    }
    for (final e in out.entries) {
      e.value.sort();
      // Layered hits (two kick samples, clap on the snare) count once.
      final merged = <double>[];
      for (final b in e.value) {
        if (merged.isEmpty || b - merged.last >= 1 / 8) merged.add(b);
      }
      out[e.key] = merged;
    }
    return out;
  }

  /// Sections from the project's time markers or section-named patterns.
  List<Section> markedSections(double length) {
    final named = markers.where((m) => m.beat < length).toList()..sort((a, b) => a.beat.compareTo(b.beat));
    final out = <Section>[];
    if (named.isEmpty) return out;
    if (named.first.beat > 0) out.add(Section(SectionKind.intro, 0, named.first.beat));
    for (var i = 0; i < named.length; i++) {
      final end = i + 1 < named.length ? named[i + 1].beat : length;
      if (end <= named[i].beat) continue;
      out.add(Section(sectionKindFor(named[i].name), named[i].beat, end, name: named[i].name));
    }
    return out;
  }
}

/// Splits into 8-bar blocks (4 for short projects) and labels them by how
/// busy they are, so visuals get calmer and wilder with the music.
List<Section> autoSections(List<ChartNote> chart, double length, int beatsPerBar) {
  final totalBars = (length / beatsPerBar).ceil();
  final blockBars = totalBars <= 16 ? 4 : 8;
  final block = blockBars * beatsPerBar.toDouble();
  final count = math.max(1, (length / block - 1e-6).ceil());
  final density = List<double>.filled(count, 0);
  var quoteBlock = -1;
  for (final n in chart) {
    final b = (n.beat / block).floor().clamp(0, count - 1);
    if (n.role == SampleRole.quote && quoteBlock < 0) quoteBlock = b;
    density[b] += n.role == SampleRole.pitch || n.role == SampleRole.word ? 1 : 0.5;
  }
  final ranked = List.generate(count, (i) => i)..sort((a, b) => density[b].compareTo(density[a]));
  final kinds = List<SectionKind>.filled(count, SectionKind.chorus);
  const middle = [SectionKind.chorus, SectionKind.dundundenden, SectionKind.epicness];
  for (var r = 0; r < ranked.length; r++) {
    kinds[ranked[r]] = switch (r) {
      0 when count > 2 => SectionKind.madness,
      1 when count > 3 => SectionKind.awesomeness,
      _ => middle[r % middle.length],
    };
  }
  final peak = density.reduce(math.max);
  if (count > 2) {
    if (quoteBlock == 0 || density[0] < peak * 0.35) kinds[0] = SectionKind.intro;
    if (density[count - 1] < peak * 0.5) kinds[count - 1] = SectionKind.outro;
  }
  return [for (var i = 0; i < count; i++) Section(kinds[i], i * block, math.min(length, (i + 1) * block))];
}

/// Section markers from where section-named parts play (FL patterns named
/// "perc intro", "madness bassline"…): each bar takes the section most of
/// its named parts belong to; bars with none continue the previous one.
/// Empty when names cover too little of the project to trust.
List<ChartMarker> markersFromNamedParts(List<({double beat, double length, String name})> parts, int beatsPerBar) {
  final bpb = beatsPerBar.toDouble();
  final named = [
    for (final x in parts)
      if (x.length > 0 && sectionKindFor(x.name) != SectionKind.other) x,
  ];
  if (named.isEmpty) return const [];
  final bars = (parts.map((x) => x.beat + x.length).reduce(math.max) / bpb).ceil();
  final votes = List.generate(bars, (_) => <SectionKind, double>{});
  final labels = List.generate(bars, (_) => <String, double>{});
  for (final x in named) {
    final kind = sectionKindFor(x.name);
    for (var b = (x.beat / bpb).floor(); b < bars && b * bpb < x.beat + x.length; b++) {
      final overlap = math.min((b + 1) * bpb, x.beat + x.length) - math.max(b * bpb, x.beat);
      if (overlap <= 0) continue;
      votes[b][kind] = (votes[b][kind] ?? 0) + overlap;
      labels[b][x.name.trim()] = (labels[b][x.name.trim()] ?? 0) + overlap;
    }
  }
  final kinds = List<SectionKind?>.filled(bars, null);
  var voted = 0;
  for (var b = 0; b < bars; b++) {
    if (votes[b].isEmpty) {
      if (b > 0) kinds[b] = kinds[b - 1];
      continue;
    }
    voted++;
    kinds[b] = votes[b].entries.reduce((a, z) => z.value > a.value ? z : a).key;
  }
  if (voted < bars * 0.4 || kinds.whereType<SectionKind>().toSet().length < 2) return const [];
  // Runs of one bar are fills or pickups: fold them into their neighbours.
  for (var b = 0; b < bars; b++) {
    final k = kinds[b];
    if (k == null) continue;
    final single = (b == 0 || kinds[b - 1] != k) && (b + 1 >= bars || kinds[b + 1] != k);
    if (single) kinds[b] = b > 0 && kinds[b - 1] != null ? kinds[b - 1] : (b + 1 < bars ? kinds[b + 1] : k);
  }
  final out = <ChartMarker>[];
  for (var b = 0; b < bars; b++) {
    final k = kinds[b];
    if (k == null || (b > 0 && kinds[b - 1] == k)) continue;
    // Label the run by its most-played name of that kind.
    final names = <String, double>{};
    for (var e = b; e < bars && kinds[e] == k; e++) {
      for (final l in labels[e].entries) {
        if (sectionKindFor(l.key) == k) names[l.key] = (names[l.key] ?? 0) + l.value;
      }
    }
    final name = names.isEmpty ? k.label : names.entries.reduce((a, z) => z.value > a.value ? z : a).key;
    out.add(ChartMarker(b * bpb, name));
  }
  return out;
}

SectionKind sectionKindFor(String name) {
  final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (s.contains('intro') || s.contains('quote') || s.contains('begin')) return SectionKind.intro;
  if (s.contains('dun') || s.contains('denden') || s.contains('buildup')) return SectionKind.dundundenden;
  if (s.contains('preepic')) return SectionKind.preEpicness;
  if (s.contains('postepic')) return SectionKind.postEpicness;
  if (s.contains('epic')) return SectionKind.epicness;
  if (s.contains('mad') || s.contains('chaos') || s.contains('crazy')) return SectionKind.madness;
  if (s.contains('awesom') || s.contains('climax') || s.contains('drop')) return SectionKind.awesomeness;
  if (s.contains('outro') || s.contains('end') || s.contains('finale')) return SectionKind.outro;
  if (s.contains('chorus') || s.contains('hook') || s.contains('verse')) return SectionKind.chorus;
  return SectionKind.other;
}

/// Guesses a sample lane from a track/channel name (and sample file name).
SampleRole? guessRole(String name, [String detail = '']) {
  final s = ' ${name.toLowerCase()} ';
  final d = detail.toLowerCase();
  bool has(Iterable<String> words, String t) => words.any(t.contains);
  if (has(const ['quote', 'intro sample', 'this is sparta', 'leonidas', 'speech', 'dialog', 'voice line'], s)) {
    return SampleRole.quote;
  }
  if (has(const ['chop', 'chorus sample', 'stutter', 'sample chop', 'chorus word'], s)) return SampleRole.word;
  if (has(const ['pitch', 'melody sample', 'vocal', 'voice', 'sample lead', 'placeholder', 'your sample'], s)) {
    return SampleRole.pitch;
  }
  if (has(const ['sample kick', 'kick sample', 'bd sample'], s)) return SampleRole.kick;
  if (has(const ['sample snare', 'snare sample'], s)) return SampleRole.snare;
  if (has(const ['sample hat', 'hat sample'], s)) return SampleRole.hat;
  if (d.isNotEmpty && d != name.toLowerCase() && has(const ['pitch', 'vocal', 'quote', 'chop'], d)) {
    return guessRole(d);
  }
  return null;
}

/// Drum sound implied by a name (channel, pad or sample file), e.g.
/// "Grv Kick 17", "VEC4 Open HH 031", "Attack OHat 06", "FPC_SdSt_B_004".
Instrument? drumForName(String name, [String detail = '']) {
  final s = ' ${'$name $detail'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
  bool has(List<String> w) => w.any(s.contains);
  if (has(const ['kick', ' bd ', 'bassdrum', 'bass drum', ' kik'])) return Instrument.kick;
  if (has(const ['clap'])) return Instrument.clap;
  if (has(const ['snare', ' sd ', 'sdst', ' snr', ' rim'])) return Instrument.snare;
  // Short words only at a word start ("Custom" is no tom, "Phat" no hat).
  final hat = has(const [' hat', 'hihat', 'ohat', 'closedhat', ' hh', 'clhh', ' ch ', 'shaker']);
  if (has(const ['ohat', ' oh ', 'ohh', 'hatopen', 'openhat', 'ophh', 'hat op ', 'hh op ']) ||
      (hat && has(const [' open', ' op ']))) {
    return Instrument.openHat;
  }
  if (hat) return Instrument.hat;
  if (has(const ['crash', 'cymbal', ' ride', 'splash'])) return Instrument.crash;
  if (has(const [' tom', 'timpani', 'taiko', ' perc', 'bongo', 'conga'])) return Instrument.tom;
  if (has(const ['riser', 'sweep', 'uplifter'])) return Instrument.riser;
  return null;
}

/// Drum sound for a key: General MIDI drum keys, or kit pad order.
Instrument drumForKey(int key, {bool pads = false}) {
  if (pads) {
    const order = [
      Instrument.kick,
      Instrument.snare,
      Instrument.hat,
      Instrument.hat,
      Instrument.clap,
      Instrument.openHat,
      Instrument.crash,
      Instrument.tom,
    ];
    return order[key.clamp(0, order.length - 1)];
  }
  return switch (key) {
    35 || 36 => Instrument.kick,
    37 || 38 || 40 => Instrument.snare,
    39 => Instrument.clap,
    46 => Instrument.openHat,
    49 || 51 || 52 || 55 || 57 || 59 => Instrument.crash,
    41 || 43 || 45 || 47 || 48 || 50 => Instrument.tom,
    _ => Instrument.hat,
  };
}

/// D Phrygian (== G natural minor) in semitones above D.
const phrygian = [0, 1, 3, 5, 7, 8, 10];

/// Pitch class (C = 0) of the Phrygian mode (the Sparta tonality) whose
/// notes cover the project's pitches best; D = 2 on near-ties.
///
/// Only the note collection matters: the sample chart follows the base's
/// own bar roots, and its passing tones stay inside this collection. (A
/// G-minor base reads as D Phrygian, the same seven notes; calling it
/// G Phrygian would put A♭ against its A.)
int tonicPitchClass(List<RawNote> notes) {
  final pc = List<double>.filled(12, 0);
  final low = notes.map((n) => n.key).fold<int>(127, math.min);
  for (final n in notes) {
    // Low notes (bass) define the harmony more than high ones.
    final weight = math.max(0.125, n.length) * (n.key < low + 12 ? 2 : 1);
    pc[n.key % 12] += weight;
  }
  double fit(int o) => phrygian.fold(0.0, (s, d) => s + pc[(o + d) % 12]);
  var best = 2;
  var bestFit = fit(2);
  for (var o = 0; o < 12; o++) {
    if (fit(o) > bestFit * 1.04) {
      best = o;
      bestFit = fit(o);
    }
  }
  return best;
}

/// Re-synthesizes a project's own parts (tracks not in [skip]) so a base
/// works without its rendered audio.
Score resynthesize(ChartSource src, {Set<String> skip = const {}, int seed = 1}) {
  final events = <ScoreEvent>[];
  for (final t in src.tracks) {
    if (skip.contains(t.id)) continue;
    for (final n in t.notes) {
      final inst = t.instrumentFor(n);
      final drum = t.isDrums || const {Instrument.kick, Instrument.snare, Instrument.hat}.contains(inst);
      events.add(
        ScoreEvent(
          inst,
          n.beat,
          drum ? 0.25 : math.max(0.1, n.length),
          midi: drum && inst != Instrument.tom ? const [] : [n.key.toDouble()],
          velocity: n.velocity,
        ),
      );
    }
  }
  events.sort((a, b) => a.beat.compareTo(b.beat));
  final length = (src.bars + 1) * src.beatsPerBar.toDouble();
  return Score(events, bpm: src.bpm, lengthBeats: length, seed: seed);
}
