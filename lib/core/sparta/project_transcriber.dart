import 'dart:math' as math;

import 'chart_import.dart';
import 'model.dart';
import 'pattern_match.dart';
import 'sectioning.dart';
import 'transcription.dart';

/// How a project track is used when transcribing.
enum TrackUse {
  /// Decided by the transcriber.
  auto('Auto'),

  /// The pitch guide: the pitch sample plays this track's notes.
  guide('Pitch guide'),

  /// Never the pitch guide.
  ignore('Not the guide');

  const TrackUse(this.label);
  final String label;
}

/// Reads what a base project plays: its pitch guide (the hit / lead whose
/// notes the pitch sample doubles), its drums and its sections.
///
/// The guide is chosen every two bars: the track that best follows one of
/// the wiki's pitch patterns there (in any key), helped by its name (hits,
/// orchestra stabs, leads, "pitch" tracks) and kept on the same track when
/// it's a close call. Bass and pad tracks play the same progression but
/// aren't what a pitch sample follows, so they rank lower.
class ProjectTranscriber {
  ProjectTranscriber({PatternMatcher? matcher}) : _matcher = matcher ?? PatternMatcher();

  final PatternMatcher _matcher;

  static const _window = 2; // bars

  BaseTranscription transcribe(ChartSource src, {Map<String, TrackUse> uses = const {}}) {
    final bpb = src.beatsPerBar;
    final bars = src.bars;
    final length = bars * bpb.toDouble();
    final drums = src.drumHits(
      skip: {
        for (final e in uses.entries)
          if (e.value == TrackUse.guide) e.key,
      },
    );

    final candidates = [
      for (final t in src.tracks)
        if (t.notes.isNotEmpty && uses[t.id] != TrackUse.ignore && (!t.isDrums || uses[t.id] == TrackUse.guide)) t,
    ];
    // Bass lines play the same progression (often the wiki's "0, 12"
    // octaves) but a pitch sample doubles the hits and leads above them.
    final upper = candidates.where((t) => !_isBass(t)).toList();
    final tonal = upper.isNotEmpty ? upper : candidates;
    final forced = [
      for (final t in candidates)
        if (uses[t.id] == TrackUse.guide) t,
    ];
    // A track named for the pitch sample ("Pitch", "Pitch guide") is the guide.
    final named = forced.isNotEmpty
        ? forced
        : [
            for (final t in tonal)
              if (t.guess == SampleRole.pitch) t,
          ];

    // Steps are 16th notes (4 per beat) so the wiki's patterns line up.
    final onsets = {
      for (final t in tonal)
        t.id: [for (final n in t.notes) Onset(n.beat * 4, n.key, length: n.length * 4)]
          ..sort((a, b) => a.step.compareTo(b.step)),
    };

    final windows = (bars / _window).ceil();
    final matches = {for (final t in tonal) t.id: List<PatternMatch?>.filled(windows, null)};
    for (final t in tonal) {
      for (var w = 0; w < windows; w++) {
        final m = _matcher.best(onsets[t.id]!, w * _window, maxBars: 4);
        if (m != null && m.score >= 0.5) matches[t.id]![w] = m;
      }
    }
    final prior = {for (final t in tonal) t.id: _prior(t)};
    double hitScore(String id, int w) => matches[id]![w]?.score ?? 0;
    final total = {
      for (final t in tonal)
        t.id: [for (var w = 0; w < windows; w++) hitScore(t.id, w)].fold<double>(0, (a, b) => a + b),
    };
    ChartTrack? fallback;
    for (final t in tonal) {
      final score = total[t.id]! + 4 * prior[t.id]!;
      if (fallback == null || score > total[fallback.id]! + 4 * prior[fallback.id]!) fallback = t;
    }

    // Pick the guide track per window.
    final choice = List<ChartTrack?>.filled(windows, null);
    ChartTrack? previous;
    for (var w = 0; w < windows; w++) {
      final from = w * _window * bpb.toDouble(), to = from + _window * bpb;
      final playing = [
        for (final t in named.isNotEmpty ? named : tonal)
          if (t.notes.any((n) => n.beat >= from - 1e-6 && n.beat < to - 1e-6)) t,
      ];
      if (playing.isEmpty) continue;
      if (named.isNotEmpty) {
        choice[w] = playing.first;
        continue;
      }
      ChartTrack? best;
      var bestScore = double.negativeInfinity;
      for (final t in playing) {
        final s = hitScore(t.id, w) + prior[t.id]! + (identical(t, previous) ? 0.15 : 0);
        if (s > bestScore) {
          bestScore = s;
          best = t;
        }
      }
      // Nothing follows a known pattern here: stay with the base's main guide.
      if (best != null && hitScore(best.id, w) < 0.5) {
        best = fallback != null && playing.contains(fallback)
            ? fallback
            : (previous != null && playing.contains(previous) ? previous : best);
      }
      choice[w] = best;
      previous = best;
    }

    // Root key: where the guide's patterns put their 0.
    final offsetVotes = <int, double>{};
    for (var w = 0; w < windows; w++) {
      final t = choice[w];
      final m = t == null ? null : matches[t.id]?[w];
      if (m != null) offsetVotes[m.offset] = (offsetVotes[m.offset] ?? 0) + m.score;
    }
    final guideNotes = <RawNote>[];
    for (var w = 0; w < windows; w++) {
      final t = choice[w];
      if (t == null) continue;
      final from = w * _window * bpb.toDouble(), to = from + _window * bpb;
      guideNotes.addAll(t.notes.where((n) => n.beat >= from - 1e-6 && n.beat < to - 1e-6));
    }
    final rootKey = offsetVotes.isNotEmpty
        ? offsetVotes.entries.reduce((a, b) => b.value > a.value ? b : a).key
        : _rootFromNotes(guideNotes.isNotEmpty ? guideNotes : [for (final t in tonal) ...t.notes]);

    // One note per onset: the one on the pattern, else the chord's root.
    final hits = <GuideNote>[];
    for (var w = 0; w < windows; w++) {
      final t = choice[w];
      if (t == null) continue;
      final from = w * _window * bpb.toDouble(), to = from + _window * bpb;
      final m = matches[t.id]?[w];
      final inWindow = t.notes.where((n) => n.beat >= from - 1e-6 && n.beat < to - 1e-6).toList()
        ..sort((a, b) => a.beat != b.beat ? a.beat.compareTo(b.beat) : a.key.compareTo(b.key));
      var i = 0;
      while (i < inWindow.length) {
        var j = i;
        while (j < inWindow.length && (inWindow[j].beat - inWindow[i].beat).abs() < 1 / 32) {
          j++;
        }
        final chord = inWindow.sublist(i, j);
        final pick = _pickNote(chord, m, rootKey);
        hits.add(GuideNote(pick.beat, math.max(1 / 16, pick.length), pick.key - rootKey, velocity: pick.velocity));
        i = j;
      }
    }
    hits.sort((a, b) => a.beat.compareTo(b.beat));
    // The guide's octave is the instrument's, not the pattern's: centre it
    // the way the wiki writes patterns (0 = the root, mostly −2..13).
    final shift = bestOctave(hits);
    final root = rootKey + 12 * shift;
    final centred = [for (final h in hits) h.copyWith(semitone: h.semitone - 12 * shift)];

    final patterns = <int, String>{};
    for (var w = 0; w < windows; w++) {
      final t = choice[w];
      final m = t == null ? null : matches[t.id]?[w];
      if (m != null && m.score >= 0.7) patterns[w * _window] = m.pattern.id;
    }

    var sections = src.markedSections(length);
    if (sections.isEmpty) {
      sections = _withPatternHints(sectionsFromTracks(src.tracks, bars, bpb), tonal, onsets, bpb);
    }
    if (sections.isEmpty) sections = [Section(SectionKind.other, 0, length)];

    // The bass line and the chords, from the base's bass and pad / chord
    // tracks (what the bass sample and the pads play).
    final guides = {for (final t in choice) ?t?.id};
    final bassTracks = [
      for (final t in candidates)
        if (_isBass(t) && !guides.contains(t.id)) t,
    ];
    final bass = _lowestLine([for (final t in bassTracks) ...t.notes], root);
    final chordTracks = [
      for (final t in candidates)
        if (!_isBass(t) && !guides.contains(t.id) && _isChords(t)) t,
    ];
    var chords = _voicings([for (final t in chordTracks) ...t.notes], root);
    if (chords.isEmpty && bass.isNotEmpty) {
      // No chord part: power chords on the bass line's notes.
      chords = [
        for (final b in bass)
          if (b.length >= 0.5)
            for (final iv in const [0, 7, 12])
              GuideNote(b.beat, b.length, b.semitone % 12 - (b.semitone % 12 > 5 ? 12 : 0) + iv),
      ];
    }

    return BaseTranscription(
      bpm: src.bpm,
      beatsPerBar: bpb,
      rootKey: root,
      lengthBeats: length,
      sections: sections,
      hits: centred,
      bass: bass,
      chords: chords,
      kick: drums[SampleRole.kick]!,
      snare: drums[SampleRole.snare]!,
      hat: drums[SampleRole.hat]!,
      source: TranscriptionSource.project,
      patterns: patterns,
      baseName: src.name,
    );
  }

  /// A pad / chord part: named so, or mostly playing several notes at once.
  static bool _isChords(ChartTrack t) {
    if (t.isDrums) return false;
    final n = ' ${'${t.name} ${t.detail}'.toLowerCase()} ';
    if (RegExp(r'pad|chord|string|choir|organ|piano|synth ?chord').hasMatch(n)) return true;
    final onsets = t.notes.map((x) => (x.beat * 32).round()).toSet().length;
    return onsets > 0 && t.notes.length / onsets >= 2.5;
  }

  /// One bass note per onset (the lowest), as semitones from [root].
  static List<GuideNote> _lowestLine(List<RawNote> notes, int root) {
    final byOnset = <int, RawNote>{};
    for (final n in notes) {
      final k = (n.beat * 32).round();
      final o = byOnset[k];
      if (o == null || n.key < o.key) byOnset[k] = n;
    }
    final keys = byOnset.keys.toList()..sort();
    return [
      for (final k in keys) GuideNote(byOnset[k]!.beat, math.max(1 / 16, byOnset[k]!.length), byOnset[k]!.key - root),
    ];
  }

  /// Chord voices (at most four per chord, the lowest), as semitones from
  /// [root].
  static List<GuideNote> _voicings(List<RawNote> notes, int root) {
    final byOnset = <int, List<RawNote>>{};
    for (final n in notes) {
      byOnset.putIfAbsent((n.beat * 32).round(), () => []).add(n);
    }
    final keys = byOnset.keys.toList()..sort();
    return [
      for (final k in keys)
        for (final n in (byOnset[k]!..sort((a, b) => a.key.compareTo(b.key))).take(4))
          GuideNote(n.beat, math.max(1 / 16, n.length), n.key - root),
    ];
  }

  static bool _isBass(ChartTrack t) {
    final n = ' ${'${t.name} ${t.detail}'.toLowerCase()} ';
    if (RegExp(r'bass|\bsub|808|reese').hasMatch(n)) return true;
    final keys = t.notes.map((x) => x.key).toList()..sort();
    return keys.isNotEmpty && keys[keys.length ~/ 2] < 50;
  }

  /// Relabels sections where the base clearly plays the wiki's epicness
  /// or awesomeness pitch patterns (checked against 52 bases that name
  /// their sections: other patterns, like DunDunDenDen's, show up
  /// everywhere and would mislead).
  List<Section> _withPatternHints(
    List<Section> sections,
    List<ChartTrack> tracks,
    Map<String, List<Onset>> onsets,
    int bpb,
  ) {
    if (sections.isEmpty) return sections;
    final bars = (sections.last.endBeat / bpb).round();
    final hint = List<SectionKind?>.filled(bars, null);
    for (var b = 0; b < bars; b += _window) {
      PatternMatch? best;
      for (final t in tracks) {
        final m = _matcher.best(onsets[t.id]!, b, maxBars: 4, sections: const {'epicness', 'awesomeness'});
        if (m != null && m.score >= 0.85 && (best == null || m.score > best.score)) best = m;
      }
      if (best == null) continue;
      for (var k = b; k < b + best.bars && k < bars; k++) {
        hint[k] = SectionKind.byWiki(best.pattern.section);
      }
    }
    return [
      for (final s in sections)
        () {
          final a = (s.startBeat / bpb).round(), z = (s.endBeat / bpb).round();
          final counts = <SectionKind, int>{};
          for (var b = a; b < z && b < bars; b++) {
            final h = hint[b];
            if (h != null) counts[h] = (counts[h] ?? 0) + 1;
          }
          if (counts.isEmpty || s.kind == SectionKind.intro) return s;
          final top = counts.entries.reduce((x, y) => y.value > x.value ? y : x);
          return top.value * 2 >= z - a ? Section(top.key, s.startBeat, s.endBeat, name: s.name) : s;
        }(),
    ];
  }

  /// Octaves to move the root up by so [hits] sit where the wiki's
  /// patterns do (around 0..+7), weighted by note length.
  static int bestOctave(List<GuideNote> hits) {
    if (hits.isEmpty) return 0;
    var best = 0;
    var bestCost = double.infinity;
    for (var k = -4; k <= 4; k++) {
      var cost = 0.0;
      for (final h in hits) {
        cost += math.min(24, (h.semitone - 12 * k - 3).abs()) * math.max(0.25, math.min(2, h.length));
      }
      if (cost < bestCost - 1e-9) {
        bestCost = cost;
        best = k;
      }
    }
    return best;
  }

  /// Name and register hints for "is this what the pitch sample follows".
  static double _prior(ChartTrack t) {
    final n = ' ${'${t.name} ${t.detail}'.toLowerCase()} ';
    var p = 0.0;
    if (RegExp(r'pitch|hit|orch|stab|lead|main|melod|awesom|epic|madness|brass|bell').hasMatch(n)) p += 0.5;
    if (RegExp(r'pad|chord|string|choir|arp|atmos|drone|fx|riser|sweep|noise').hasMatch(n)) p -= 0.4;
    // Chords everywhere: a pad or chord layer rather than a hit line.
    final onsets = t.notes.map((x) => (x.beat * 32).round()).toSet().length;
    if (onsets > 0 && t.notes.length / onsets > 2.5) p -= 0.2;
    if (t.meanLength >= 2) p -= 0.15;
    return p;
  }

  static RawNote _pickNote(List<RawNote> chord, PatternMatch? m, int rootKey) {
    if (chord.length == 1) return chord.first;
    if (m != null) {
      // The note the pattern expects at this step.
      final step = chord.first.beat * 4 - m.bar * 16;
      for (final h in m.pattern.looped(m.pattern.bars * 16.0)) {
        if ((h.step - step).abs() > 0.3) continue;
        for (final n in chord) {
          if (n.key == m.offset + h.semitone) return n;
        }
      }
    }
    // Power chords (root, fifth, octave): the root. Otherwise the top line.
    final low = chord.first;
    final stacked = chord.skip(1).every((n) => const {0, 7, 12, 19, 24}.contains(n.key - low.key));
    return stacked ? low : chord.last;
  }

  /// Root key from notes alone: the Phrygian collection's tonic, placed at
  /// or just below the notes' median.
  static int _rootFromNotes(List<RawNote> notes) {
    if (notes.isEmpty) return 62;
    final pc = tonicPitchClass(notes);
    final keys = notes.map((n) => n.key).toList()..sort();
    final median = keys[keys.length ~/ 2];
    return median - ((median - pc) % 12);
  }
}
