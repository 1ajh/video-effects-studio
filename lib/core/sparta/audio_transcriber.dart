import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/fft.dart';
import 'audio_base.dart';
import 'audio_sections.dart';
import 'chart_import.dart';
import 'model.dart';
import 'pattern_match.dart';
import 'patterns.dart';
import 'sectioning.dart';
import 'transcription.dart';

/// Transcribes a base from its audio alone: where its kicks, snares and
/// hats hit, what its hit / lead plays and where its sections are.
///
/// Drums: a base reuses the same few drum samples all the way through, so
/// the attacks on the 16th-note grid are grouped by how they sound (their
/// band-energy rise) and each group is named by its balance of lows, mids
/// and highs. Pitched hits: every wiki pitch pattern is scored, in every
/// key, against how the audio's pitch content rises on each 16th; where
/// one clearly fits, the base is taken to play it (which also restores the
/// octave jumps audio can't tell apart). Elsewhere the clearest pitched
/// attacks are kept, folded around the root, and the transcription says
/// it's less sure.
class AudioTranscriber {
  AudioTranscriber({Iterable<Pattern>? patterns})
    : _patterns = PatternMatcher(patterns: patterns, byPitchClass: true).patterns;

  final List<Pattern> _patterns;

  static const _fftSize = 2048;

  BaseTranscription transcribe(AudioBaseAnalysis a, {String name = '', bool rephased = false}) {
    final x = a.signal, bands = a.onsets;
    if (x == null || bands == null) throw ArgumentError('The analysis kept no signal to transcribe.');
    final sr = AudioBaseAnalyzer.sampleRate;
    final stepSec = 60 / a.bpm / 4;
    // Where the music ends, its sections and chords (the ring-out after the
    // last bar is left out: nothing plays over it).
    final structure = AudioSectioner().analyze(
      x,
      sr,
      bpm: a.bpm,
      firstDownbeat: a.firstDownbeat,
      bars: a.bars,
      rootPc: a.tonicPc,
    );
    // Drums can't always tell beat 1 from beat 3; the chord loop can. Bar 1
    // moves onto the loop's first chord: back by up to half a bar (a moment
    // of silence before the base), else forward.
    final phase = rephased ? 0 : AudioSectioner.cyclePhase(structure.chords);
    if (phase != 0) {
      final half = a.barSeconds / 2;
      var downbeat = a.firstDownbeat + phase * half;
      while (downbeat - 4 * half >= -half) {
        downbeat -= 4 * half;
      }
      return transcribe(a.withDownbeat(downbeat), name: name, rephased: true);
    }
    final bars = math.max(1, math.min(a.bars, structure.musicBars));
    final steps = bars * 16;
    double at(int s) => a.firstDownbeat + s * stepSec;

    final fft = Fft(_fftSize);
    final window = Float64List.fromList([
      for (var i = 0; i < _fftSize; i++) 0.5 - 0.5 * math.cos(2 * math.pi * i / (_fftSize - 1)),
    ]);
    final re = Float64List(_fftSize), im = Float64List(_fftSize);
    // Magnitude spectrum of [len] samples from [t] (zero padded).
    Float64List spectrum(double t, int len) {
      final o = (t * sr).round();
      for (var i = 0; i < _fftSize; i++) {
        final j = o + i;
        re[i] = i < len && j >= 0 && j < x.length
            ? x[j] * window[(i * _fftSize / len).floor().clamp(0, _fftSize - 1)]
            : 0;
        im[i] = 0;
      }
      fft.transform(re, im);
      return Float64List.fromList([for (var k = 0; k < _fftSize ~/ 2; k++) math.sqrt(re[k] * re[k] + im[k] * im[k])]);
    }

    // --- drums ---------------------------------------------------------------
    // Sparta percussion sits on a grid (kick on the beat, snare/clap on 2 and
    // 4, hats between): a grid position is kept when the audio has a real
    // attack of that kind there, so breaks and sparse parts stay empty, and
    // off-grid hits are only taken when they're unmistakable.
    final kickV = Float64List(steps), snareV = Float64List(steps), hatV = Float64List(steps);
    for (var s = 0; s < steps; s++) {
      final t = at(s);
      final sub = OnsetBands.peak(bands.sub, t), low = OnsetBands.peak(bands.low, t);
      final mid = OnsetBands.peak(bands.mid, t), high = OnsetBands.peak(bands.high, t);
      kickV[s] = 0.6 * sub + 0.4 * low;
      snareV[s] = math.sqrt(mid * high);
      hatV[s] = high;
    }
    final drums = {
      SampleRole.kick: _gated(kickV, (s) => s % 4 == 0, onGrid: kickOnGrid, offGrid: kickOffGrid),
      SampleRole.snare: _gated(snareV, (s) => s % 8 == 4, onGrid: snareOnGrid, offGrid: snareOffGrid),
      SampleRole.hat: _gated(hatV, (s) => s % 4 == 2, onGrid: hatOnGrid, offGrid: hatOffGrid),
    };

    // --- pitched hits ---------------------------------------------------------
    // Rise of each pitch class on every 16th.
    final rise = List.generate(steps, (_) => Float64List(12));
    Float64List chroma(double t) {
      final mag = spectrum(t, _fftSize);
      final c = Float64List(12);
      for (var k = 1; k < mag.length; k++) {
        final f = k * sr / _fftSize;
        if (f < 220 || f > 2600) continue;
        c[((12 * math.log(f / 440) / math.ln2 + 69).round() % 12 + 12) % 12] += mag[k];
      }
      return c;
    }

    for (var s = 0; s < steps; s++) {
      final before = chroma(at(s) - 0.093), after = chroma(at(s) + 0.008);
      var total = 0.0;
      for (var p = 0; p < 12; p++) {
        rise[s][p] = math.max(0, after[p] - before[p]);
        total += after[p];
      }
      if (total > 0) {
        for (var p = 0; p < 12; p++) {
          rise[s][p] /= total;
        }
      }
    }
    // Typical rise, to judge a pattern against chance.
    final flat = [for (final r in rise) ...r]..sort();
    final typical = flat.isEmpty ? 0.0 : flat[(flat.length * 0.75).floor()];

    final matches = <({Pattern p, int bar, int offset, double score})>[];
    var bar = 0;
    while (bar < bars) {
      ({Pattern p, int bar, int offset, double score})? best;
      for (final p in _patterns) {
        if (p.bars > 4 || bar + p.bars > bars) continue;
        final hs = p.looped(p.bars * 16.0);
        for (var o = 0; o < 12; o++) {
          var on = 0.0;
          for (final h in hs) {
            final s = bar * 16 + h.step.round();
            if (s >= steps) continue;
            on += rise[s][(o + h.semitone) % 12];
          }
          final score = on / hs.length / (typical + 1e-9);
          if (best == null || score > best.score + (o == a.tonicPc ? -1e-6 : 1e-6)) {
            best = (p: p, bar: bar, offset: o, score: score);
          }
        }
      }
      if (best != null && best.score >= 2.2) {
        matches.add(best);
        bar += best.p.bars;
      } else {
        bar += 2;
      }
    }

    final votes = <int, double>{};
    for (final m in matches) {
      votes[m.offset] = (votes[m.offset] ?? 0) + m.p.bars.toDouble();
    }
    var rootPc = a.tonicPc;
    if (votes.isNotEmpty) {
      final top = votes.entries.reduce((p, q) => q.value > p.value ? q : p);
      if (top.value >= 8) rootPc = top.key;
    }
    int wrap(int v) => ((v % 12) + 18) % 12 - 6;

    final guide = <GuideNote>[];
    final patterns = <int, String>{};
    final covered = List<bool>.filled(bars, false);
    for (final m in matches) {
      final shift = wrap(m.offset - rootPc);
      for (final h in m.p.looped(m.p.bars * 16.0)) {
        guide.add(GuideNote((m.bar * 16 + h.step) / 4, h.length / 4, h.semitone + shift));
      }
      patterns[m.bar] = m.p.id;
      for (var b = m.bar; b < m.bar + m.p.bars && b < bars; b++) {
        covered[b] = true;
      }
    }
    // Chords, moved to the root found above.
    final chordShift = wrap(a.tonicPc - rootPc);
    final chords = [for (final c in structure.chords) c.copyWith(semitone: c.semitone + chordShift)];
    // Unexplained bars: clear pitched attacks, as heard — unless the chords
    // are known, when the wiki's patterns fitted to them sound far better than
    // attacks guessed from a full mix.
    final tonal = Float64List(steps);
    for (var s = 0; s < steps; s++) {
      tonal[s] = rise[s].reduce(math.max);
    }
    final raw = chords.isNotEmpty
        ? const <int>[]
        : [
            for (final s in _peaks(tonal, floor: typical * 2.5, relative: 0.5))
              if (!covered[(s / 16).floor().clamp(0, bars - 1)]) s,
          ];
    for (var i = 0; i < raw.length; i++) {
      final s = raw[i];
      final next = i + 1 < raw.length ? raw[i + 1] : s + 4;
      var pc = 0;
      for (var p = 1; p < 12; p++) {
        if (rise[s][p] > rise[s][pc]) pc = p;
      }
      var semi = (pc - rootPc) % 12;
      if (semi > 7) semi -= 12;
      guide.add(GuideNote(s / 4, math.max(1, math.min(4, next - s)) / 4, semi));
    }
    guide.sort((p, q) => p.beat.compareTo(q.beat));

    // --- sections ------------------------------------------------------------
    List<RawNote> notes(Iterable<int> ss, int key) => [for (final i in ss) RawNote(i / 4, 0.25, key)];
    final pseudo = [
      ChartTrack(id: 'kick', name: 'Kick', notes: notes(drums[SampleRole.kick]!, 36), drumKit: true),
      ChartTrack(id: 'snare', name: 'Snare', notes: notes(drums[SampleRole.snare]!, 38), drumKit: true),
      ChartTrack(id: 'hat', name: 'Hat', notes: notes(drums[SampleRole.hat]!, 42), drumKit: true),
      ChartTrack(id: 'hit', name: 'Hits', notes: [for (final g in guide) RawNote(g.beat, g.length, 60 + g.semitone)]),
    ];
    var sections = structure.sections;
    if (sections.isEmpty) {
      // No recurring chorus to anchor on: label by how the parts play.
      sections = _hint(sectionsFromTracks(pseudo, bars, 4), matches);
    }
    if (sections.isEmpty) sections = [Section(SectionKind.other, 0, bars * 4.0)];

    final coverage = covered.where((c) => c).length / math.max(1, bars);
    return BaseTranscription(
      bpm: a.bpm,
      rootKey: 60 + rootPc,
      lengthBeats: bars * 4.0,
      sections: sections,
      hits: guide,
      chords: chords,
      kick: [for (final s in drums[SampleRole.kick]!) s / 4],
      snare: [for (final s in drums[SampleRole.snare]!) s / 4],
      hat: [for (final s in drums[SampleRole.hat]!) s / 4],
      audioOffset: a.firstDownbeat,
      source: TranscriptionSource.audio,
      confidence: (0.25 + 0.35 * coverage + (structure.sections.isEmpty ? 0 : 0.2) + 0.2 * a.tempoConfidence)
          .clamp(0, 1)
          .toDouble(),
      patterns: patterns,
      baseName: name,
    );
  }

  /// Thresholds (whitened onset strength) for grid and off-grid drums.
  static double kickOnGrid = 0.1, kickOffGrid = 1.2;
  static double snareOnGrid = 0.1, snareOffGrid = 1.2;
  static double hatOnGrid = 0.1, hatOffGrid = 0.8;

  static List<int> _gated(Float64List v, bool Function(int) grid, {required double onGrid, required double offGrid}) {
    final out = <int>[];
    for (var s = 0; s < v.length; s++) {
      if (grid(s)) {
        if (v[s] >= onGrid) out.add(s);
      } else if (v[s] >= offGrid && (s == 0 || v[s] >= v[s - 1]) && (s + 1 >= v.length || v[s] > v[s + 1])) {
        out.add(s);
      }
    }
    return out;
  }

  /// Local maxima of [v] at least [floor] and [relative] × the loudest
  /// value within two bars.
  static List<int> _peaks(Float64List v, {required double floor, required double relative}) {
    final out = <int>[];
    for (var s = 0; s < v.length; s++) {
      if (v[s] < floor) continue;
      if (s > 0 && v[s - 1] > v[s]) continue;
      if (s + 1 < v.length && v[s + 1] >= v[s]) continue;
      var local = 0.0;
      for (var i = math.max(0, s - 32); i < math.min(v.length, s + 32); i++) {
        local = math.max(local, v[i]);
      }
      if (v[s] >= relative * local) out.add(s);
    }
    return out;
  }

  /// Sections the base clearly plays the epicness or awesomeness pitch
  /// patterns in take that label.
  static List<Section> _hint(List<Section> sections, List<({Pattern p, int bar, int offset, double score})> matched) {
    return [
      for (final s in sections)
        () {
          if (s.kind == SectionKind.intro) return s;
          final counts = <SectionKind, int>{};
          for (final m in matched) {
            final k = SectionKind.byWiki(m.p.section);
            if (k != SectionKind.epicness && k != SectionKind.awesomeness) continue;
            final a = m.bar * 4.0, z = (m.bar + m.p.bars) * 4.0;
            final overlap = math.min(z, s.endBeat) - math.max(a, s.startBeat);
            if (overlap > 0) counts[k!] = (counts[k] ?? 0) + (overlap / 4).round();
          }
          if (counts.isEmpty) return s;
          final top = counts.entries.reduce((p, q) => q.value > p.value ? q : p);
          return top.value * 2 >= s.lengthBeats / 4 ? Section(top.key, s.startBeat, s.endBeat, name: s.name) : s;
        }(),
    ];
  }
}
