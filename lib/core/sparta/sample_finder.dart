import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/analysis.dart';
import '../audio/audio_buffer.dart';
import 'model.dart';

/// Audio + features for one source clip.
class SourceAnalysis {
  SourceAnalysis(this.index, this.path, this.audio, this.features);

  final int index;
  final String path;

  /// Mono analysis audio (24 kHz).
  final AudioBuffer audio;
  final FrameFeatures features;

  double get duration => audio.duration;

  static const analysisRate = 24000;

  /// Decodes (first [maxSeconds]) and analyzes a source.
  static Future<SourceAnalysis> load(String ffmpeg, int index, String path, {double maxSeconds = 360}) async {
    final audio = await AudioBuffer.decode(ffmpeg, path, sampleRate: analysisRate, duration: maxSeconds);
    return fromAudio(index, path, audio);
  }

  static SourceAnalysis fromAudio(int index, String path, AudioBuffer audio) {
    final mono = audio.mono();
    final f = analyze(mono.data, mono.sampleRate, hop: mono.sampleRate ~/ 100, yinWindow: 512);
    return SourceAnalysis(index, path, mono, f);
  }
}

/// What was found in the sources: spoken lines (for the quote and the
/// chorus words) and ranked pitch / percussion candidates.
class SamplePicks {
  SamplePicks(this.byRole, {this.lines = const []});

  final Map<SampleRole, List<SampleCandidate>> byRole;

  /// Spoken lines, best first.
  final List<SpokenLine> lines;

  List<SampleCandidate> of(SampleRole r) => byRole[r] ?? const [];
  SampleCandidate? best(SampleRole r) => of(r).isEmpty ? null : of(r).first;

  /// Pitch candidates with the line's own voiced syllables first (the
  /// pitch sample is classically a vowel of the line).
  List<SampleCandidate> pitchFor(SpokenLine? line) {
    final list = [...of(SampleRole.pitch)];
    if (line == null) return list;
    double rank(SampleCandidate c) {
      final inLine =
          c.sourceIndex == line.sourceIndex && c.start >= line.start - 0.05 && c.end <= line.end + 0.05;
      return c.score + (inLine ? 0.12 : 0);
    }

    list.sort((a, b) => rank(b).compareTo(rank(a)));
    return list;
  }

  /// One pick per percussion / pitch role, preferring material no other
  /// role already uses (as long as the alternative scores at least
  /// [tolerance] × the best).
  Map<SampleRole, SampleCandidate> assignDistinct({SpokenLine? line, double tolerance = 0.7}) {
    const order = [SampleRole.pitch, SampleRole.snare, SampleRole.kick, SampleRole.hat];
    final chosen = <SampleRole, SampleCandidate>{};
    bool clashes(SampleCandidate c) => chosen.values.any(
      (o) => o.sourceIndex == c.sourceIndex && c.start < o.end - 0.01 && o.start < c.end - 0.01,
    );
    for (final role in order) {
      final list = role == SampleRole.pitch ? pitchFor(line) : of(role);
      if (list.isEmpty) continue;
      final floor = list.first.score * tolerance;
      chosen[role] = list.firstWhere((c) => c.score >= floor && !clashes(c), orElse: () => list.first);
    }
    return chosen;
  }
}

/// Finds usable samples in speech / game / movie audio.
///
/// Every candidate gets a 0..1 score from interpretable terms so the review
/// UI can explain the choice. Nothing is synthesized: every sample is a
/// piece of a source.
class SampleFinder {
  SampleFinder(this.sources);

  final List<SourceAnalysis> sources;

  SamplePicks find({int keep = 8, int keepLines = 12}) {
    final all = <SampleRole, List<SampleCandidate>>{
      for (final r in const [SampleRole.pitch, SampleRole.kick, SampleRole.snare, SampleRole.hat]) r: [],
    };
    final lines = <SpokenLine>[];
    for (final s in sources) {
      final onsets = detectOnsets(s.features, sensitivity: 1.2);
      all[SampleRole.pitch]!.addAll(_pitchCandidates(s, onsets));
      final hits = _hits(s, onsets);
      all[SampleRole.kick]!.addAll(hits.map((h) => h.scored(SampleRole.kick)));
      all[SampleRole.snare]!.addAll(hits.map((h) => h.scored(SampleRole.snare)));
      all[SampleRole.hat]!.addAll(hits.map((h) => h.scored(SampleRole.hat)));
      lines.addAll(findLines(s));
    }
    final out = <SampleRole, List<SampleCandidate>>{};
    for (final e in all.entries) {
      final list = e.value..sort((a, b) => b.score.compareTo(a.score));
      out[e.key] = _dedupe(list).take(keep).toList();
    }
    lines.sort((a, b) => b.score.compareTo(a.score));
    return SamplePicks(out, lines: lines.take(keepLines).toList());
  }

  /// Drops candidates overlapping a better one from the same source.
  static List<SampleCandidate> _dedupe(List<SampleCandidate> sorted) {
    final kept = <SampleCandidate>[];
    for (final c in sorted) {
      final overlaps = kept.any(
        (k) => k.sourceIndex == c.sourceIndex && c.start < k.end - 0.02 && k.start < c.end - 0.02,
      );
      if (!overlaps) kept.add(c);
    }
    return kept;
  }

  // ---------------------------------------------------------------------------
  // Pitch: clear, steady, vowel-like voiced regions.
  // ---------------------------------------------------------------------------

  List<SampleCandidate> _pitchCandidates(SourceAnalysis s, List<int> onsets) {
    final f = s.features;
    final peak = f.rmsDb.fold<double>(-180, math.max);
    final regions = _voicedRegions(f, peak - 30, maxAperiodicity: 0.25, minFrames: 10);
    final out = <SampleCandidate>[];
    for (final (a0, b0) in regions) {
      // Long regions: slide a window and keep the steadiest part.
      final windows = <(int, int)>[];
      const maxLen = 70; // 0.7 s
      if (b0 - a0 <= maxLen) {
        windows.add((a0, b0));
      } else {
        for (var a = a0; a + 25 <= b0; a += 12) {
          windows.add((a, math.min(b0, a + maxLen)));
        }
      }
      for (final (a, b) in windows) {
        final hz = [for (var i = a; i < b; i++) f.f0[i]];
        final spread = centsSpread(hz);
        final clarity = 1 - _mean(f.aperiodicity, a, b).clamp(0, 1);
        final loud = ((_mean(f.rmsDb, a, b) - (peak - 30)) / 30).clamp(0.0, 1.0);
        final dur = (b - a) * f.frameSeconds;
        final durFit = _bell(dur, 0.2, 0.75);
        final vowel = _vowelness(f, a, b);
        final stability = math.exp(-spread / 70);
        // Syllable start: an onset just before the region (includes the consonant).
        var start = f.timeOf(a);
        final lead = onsets.where((o) => o <= a && a - o <= 15).toList();
        final attack = lead.isNotEmpty;
        if (attack) start = f.timeOf(lead.last);
        final medianHz = median(hz);
        final rangeOk = medianHz > 70 && medianHz < 700 ? 1.0 : 0.3;
        final score =
            (0.28 * clarity + 0.24 * stability + 0.14 * loud + 0.14 * durFit + 0.14 * vowel + 0.06 * (attack ? 1 : 0)) *
            rangeOk;
        out.add(
          SampleCandidate(
            role: SampleRole.pitch,
            sourceIndex: s.index,
            start: start,
            end: f.timeOf(b),
            score: score,
            f0: medianHz,
            details: {
              'clarity': clarity.toDouble(),
              'stability': stability,
              'loudness': loud,
              'length': durFit,
              'vowel': vowel,
            },
          ),
        );
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Percussion.
  // ---------------------------------------------------------------------------

  List<_Hit> _hits(SourceAnalysis s, List<int> onsets) {
    final f = s.features;
    final peak = f.rmsDb.fold<double>(-180, math.max);
    final maxFlux = f.flux.fold<double>(0, math.max);
    final hits = <_Hit>[];
    for (var k = 0; k < onsets.length; k++) {
      final a = onsets[k];
      final limit = math.min(k + 1 < onsets.length ? onsets[k + 1] : f.length, a + 40);
      // Decay: frames until 20 dB below the hit's own peak.
      var top = a;
      for (var i = a; i < math.min(limit, a + 4); i++) {
        if (f.rmsDb[i] > f.rmsDb[top]) top = i;
      }
      var b = top;
      while (b < limit && f.rmsDb[b] > f.rmsDb[top] - 20) {
        b++;
      }
      if (b - a < 3) continue;
      final n = b - a;
      double band(int i) => _mean(f.bands[i], a, math.min(b, a + 6));
      hits.add(
        _Hit(
          source: s.index,
          start: math.max(0, f.timeOf(a) - 0.004),
          end: f.timeOf(b),
          attack: maxFlux > 0 ? (f.flux[a] / maxFlux).clamp(0.0, 1.0) : 0,
          loud: ((f.rmsDb[top] - (peak - 36)) / 36).clamp(0.0, 1.0),
          decay: n * f.frameSeconds,
          low: band(0) + 0.5 * band(1),
          mid: band(2) + 0.5 * band(1),
          high: band(3) + band(4),
          air: band(4),
          flatness: _mean(f.flatness, a, math.min(b, a + 6)),
          centroid: _mean(f.centroid, a, math.min(b, a + 6)),
          voiced: [for (var i = a; i < b; i++) f.voiced(i) ? 1.0 : 0.0].fold<double>(0, (x, y) => x + y) / n,
        ),
      );
    }
    return hits;
  }

  // ---------------------------------------------------------------------------
  // Lines: spoken phrases bounded by pauses, split into words and syllables.
  // ---------------------------------------------------------------------------

  /// Spoken lines in [s]: phrases between pauses, 0.5–6 s long, split into
  /// words at silences and deep dips, and words into syllables at the
  /// smaller dips between vowels.
  static List<SpokenLine> findLines(SourceAnalysis s) {
    final f = s.features;
    if (f.length == 0) return const [];
    final peak = f.rmsDb.fold<double>(-180, math.max);
    final floor = peak - 35;
    final env = _smooth(f.rmsDb, 2);
    final active = [for (var i = 0; i < f.length; i++) env[i] > floor];
    // Phrases: active runs, merging gaps shorter than 250 ms.
    final phrases = <(int, int)>[];
    var i = 0;
    while (i < f.length) {
      if (!active[i]) {
        i++;
        continue;
      }
      final a = i;
      var b = i;
      var gap = 0;
      while (i < f.length) {
        if (active[i]) {
          b = i + 1;
          gap = 0;
        } else if (++gap > 25) {
          break;
        }
        i++;
      }
      phrases.add((a, b));
    }
    final out = <SpokenLine>[];
    for (final (a, b) in phrases) {
      final dur = (b - a) * f.frameSeconds;
      if (dur < 0.45 || dur > 7) continue;
      final words = _words(f, env, a, b, floor);
      if (words.isEmpty) continue;
      final voiced = [for (var k = a; k < b; k++) f.voiced(k) ? 1.0 : 0.0].fold<double>(0, (x, y) => x + y) / (b - a);
      final durFit = _bell(dur, 0.9, 3.6);
      final count = _bell(words.length.toDouble(), 2, 6);
      final loud = ((_mean(f.rmsDb, a, b) - (peak - 30)) / 30).clamp(0.0, 1.0);
      final speech = _bell(voiced, 0.35, 0.85);
      // Clean pauses around it make a clean quote.
      final before = a > 0 ? _mean(env, math.max(0, a - 15), a) : floor - 10;
      final after = b < f.length ? _mean(env, b, math.min(f.length, b + 15)) : floor - 10;
      final clean = (((peak - 12) - math.max(before, after)) / 25).clamp(0.0, 1.0);
      final score = 0.25 * durFit + 0.2 * count + 0.2 * speech + 0.2 * loud + 0.15 * clean;
      out.add(
        SpokenLine(
          sourceIndex: s.index,
          start: math.max(0, f.timeOf(a) - 0.02),
          end: math.min(s.duration, f.timeOf(b) + 0.04),
          words: words,
          score: score,
          details: {'length': durFit, 'words': count, 'speech': speech, 'loudness': loud, 'clean': clean},
        ),
      );
    }
    return out;
  }

  /// Word / syllable splitting thresholds (frames of 10 ms, dB). Loudness
  /// alone can't always tell a word gap from a stop inside a word (about
  /// half the cuts in connected speech), so the Line step lets the user
  /// split and merge words.
  static int wordGapFrames = 2;
  static double wordDipDb = 8, syllableDipDb = 4;

  /// Words of the phrase [a, b): split at silences (30 ms+) and dips at least
  /// 10 dB below both neighbouring peaks; syllables at 4 dB+ dips between
  /// voiced peaks.
  static List<LineWord> _words(FrameFeatures f, Float64List env, int a, int b, double floor) {
    // Valleys: local minima with their depth below the smaller neighbour peak.
    final cutsWord = <int>{};
    final cutsSyllable = <int>{};
    var k = a;
    while (k < b) {
      if (env[k] <= floor) {
        final s0 = k;
        while (k < b && env[k] <= floor) {
          k++;
        }
        if (k - s0 >= wordGapFrames && s0 > a && k < b) cutsWord.add((s0 + k) ~/ 2);
        continue;
      }
      k++;
    }
    for (var j = a + 2; j < b - 2; j++) {
      if (env[j] > env[j - 1] || env[j] > env[j + 1] || env[j] <= floor) continue;
      var left = env[j], right = env[j];
      for (var q = j - 1; q >= math.max(a, j - 25); q--) {
        left = math.max(left, env[q]);
      }
      for (var q = j + 1; q < math.min(b, j + 26); q++) {
        right = math.max(right, env[q]);
      }
      final depth = math.min(left, right) - env[j];
      if (depth >= wordDipDb) {
        cutsWord.add(j);
      } else if (depth >= syllableDipDb) {
        cutsSyllable.add(j);
      }
    }
    // Words from the word cuts (dropping crumbs shorter than 70 ms).
    final edges = [a, ...(cutsWord.toList()..sort()), b];
    final spans = <(int, int)>[];
    for (var q = 0; q + 1 < edges.length; q++) {
      var s0 = edges[q], s1 = edges[q + 1];
      // Trim silence at the word's edges.
      while (s0 < s1 && env[s0] <= floor) {
        s0++;
      }
      while (s1 > s0 && env[s1 - 1] <= floor) {
        s1--;
      }
      if (s1 - s0 < 7) continue;
      spans.add((s0, s1));
    }
    return [
      for (final (s0, s1) in spans)
        LineWord(
          math.max(0, f.timeOf(s0) - 0.012),
          f.timeOf(s1) + 0.02,
          cuts: [
            for (final c in cutsSyllable.toList()..sort())
              if (c - s0 >= 6 && s1 - c >= 6) f.timeOf(c),
          ],
        ),
    ];
  }

  static Float64List _smooth(Float64List x, int radius) {
    final out = Float64List(x.length);
    for (var i = 0; i < x.length; i++) {
      var s = 0.0, n = 0;
      for (var j = math.max(0, i - radius); j <= math.min(x.length - 1, i + radius); j++) {
        s += x[j];
        n++;
      }
      out[i] = s / n;
    }
    return out;
  }

  // ---------------------------------------------------------------------------

  static List<(int, int)> _voicedRegions(
    FrameFeatures f,
    double minDb, {
    required double maxAperiodicity,
    required int minFrames,
  }) {
    final regions = <(int, int)>[];
    var a = -1;
    var gap = 0;
    for (var i = 0; i <= f.length; i++) {
      final ok = i < f.length && f.voiced(i) && f.aperiodicity[i] < maxAperiodicity && f.rmsDb[i] > minDb;
      if (ok) {
        if (a < 0) a = i;
        gap = 0;
      } else if (a >= 0) {
        gap++;
        if (gap > 3 || i == f.length) {
          final b = i - gap + 1;
          if (b - a >= minFrames) regions.add((a, b));
          a = -1;
          gap = 0;
        }
      }
    }
    return regions;
  }

  static double _vowelness(FrameFeatures f, int a, int b) {
    final flat = _mean(f.flatness, a, b);
    final zcr = _mean(f.zcr, a, b);
    final cen = _mean(f.centroid, a, b);
    final flatScore = (1 - flat * 4).clamp(0.0, 1.0);
    final zcrScore = (1 - zcr * 8).clamp(0.0, 1.0);
    final cenScore = _bell(cen, 250, 2200);
    return (flatScore + zcrScore + cenScore) / 3;
  }

  static double _mean(Float64List x, int a, int b) {
    if (b <= a) return 0;
    var s = 0.0;
    for (var i = a; i < b; i++) {
      s += x[i];
    }
    return s / (b - a);
  }

  /// 1 inside [lo, hi], falling off smoothly outside.
  static double _bell(double v, double lo, double hi) {
    if (v >= lo && v <= hi) return 1;
    final width = (hi - lo).abs() * 0.75 + 1e-9;
    final d = v < lo ? lo - v : v - hi;
    return math.exp(-(d / width) * (d / width) * 2);
  }
}

class _Hit {
  _Hit({
    required this.source,
    required this.start,
    required this.end,
    required this.attack,
    required this.loud,
    required this.decay,
    required this.low,
    required this.mid,
    required this.high,
    required this.air,
    required this.flatness,
    required this.centroid,
    required this.voiced,
  });

  final int source;
  final double start, end, attack, loud, decay, low, mid, high, air, flatness, centroid, voiced;

  SampleCandidate scored(SampleRole role) {
    final double score;
    final Map<String, double> d;
    switch (role) {
      case SampleRole.kick:
        final lowness = (low * 1.6).clamp(0.0, 1.0);
        final dark = SampleFinder._bell(centroid, 0, 900);
        final len = SampleFinder._bell(decay, 0.08, 0.35);
        score = 0.3 * lowness + 0.2 * dark + 0.25 * attack + 0.15 * loud + 0.1 * len;
        d = {'low end': lowness, 'darkness': dark, 'attack': attack, 'loudness': loud};
      case SampleRole.snare:
        final body = (mid * 1.5).clamp(0.0, 1.0);
        final noise = SampleFinder._bell(flatness, 0.15, 0.6);
        final len = SampleFinder._bell(decay, 0.06, 0.25);
        score = 0.25 * body + 0.25 * noise + 0.25 * attack + 0.15 * loud + 0.1 * len;
        d = {'body': body, 'noise': noise, 'attack': attack, 'loudness': loud};
      case SampleRole.hat:
        final bright = (high * 1.8 + air).clamp(0.0, 1.0);
        final noise = SampleFinder._bell(flatness, 0.3, 1.0);
        final short = SampleFinder._bell(decay, 0.02, 0.12);
        final unvoiced = 1 - voiced;
        score = 0.35 * bright + 0.2 * noise + 0.2 * short + 0.15 * unvoiced + 0.1 * attack;
        d = {'brightness': bright, 'noise': noise, 'shortness': short, 'unvoiced': unvoiced};
      default:
        throw ArgumentError(role);
    }
    return SampleCandidate(
      role: role,
      sourceIndex: source,
      start: start,
      end: role == SampleRole.hat ? math.min(end, start + 0.15) : math.min(end, start + 0.4),
      score: score,
      details: d,
    );
  }
}
