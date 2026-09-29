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

/// Ranked candidates per role.
class SamplePicks {
  SamplePicks(this.byRole);

  final Map<SampleRole, List<SampleCandidate>> byRole;

  List<SampleCandidate> of(SampleRole r) => byRole[r] ?? const [];
  SampleCandidate? best(SampleRole r) => of(r).isEmpty ? null : of(r).first;

  /// One pick per role, preferring material no other role already uses
  /// (as long as the alternative scores at least [tolerance] × the best).
  Map<SampleRole, SampleCandidate> assignDistinct({double tolerance = 0.7}) {
    const order = [
      SampleRole.quote,
      SampleRole.pitch,
      SampleRole.chop,
      SampleRole.snare,
      SampleRole.kick,
      SampleRole.hat,
    ];
    final chosen = <SampleRole, SampleCandidate>{};
    bool clashes(SampleCandidate c) => chosen.entries.any(
      (e) =>
          e.key != SampleRole.quote &&
          e.value.sourceIndex == c.sourceIndex &&
          c.start < e.value.end - 0.01 &&
          e.value.start < c.end - 0.01,
    );
    for (final role in order) {
      final list = of(role);
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
/// UI can explain the choice.
class SampleFinder {
  SampleFinder(this.sources);

  final List<SourceAnalysis> sources;

  SamplePicks find({int keep = 8}) {
    final all = <SampleRole, List<SampleCandidate>>{for (final r in SampleRole.values) r: []};
    for (final s in sources) {
      final onsets = detectOnsets(s.features, sensitivity: 1.2);
      all[SampleRole.pitch]!.addAll(_pitchCandidates(s, onsets));
      all[SampleRole.chop]!.addAll(_chopCandidates(s, onsets));
      final hits = _hits(s, onsets);
      all[SampleRole.kick]!.addAll(hits.map((h) => h.scored(SampleRole.kick)));
      all[SampleRole.snare]!.addAll(hits.map((h) => h.scored(SampleRole.snare)));
      all[SampleRole.hat]!.addAll(hits.map((h) => h.scored(SampleRole.hat)));
      all[SampleRole.quote]!.addAll(_quoteCandidates(s));
    }
    final out = <SampleRole, List<SampleCandidate>>{};
    for (final e in all.entries) {
      final list = e.value..sort((a, b) => b.score.compareTo(a.score));
      out[e.key] = _dedupe(list).take(keep).toList();
    }
    return SamplePicks(out);
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
  // Chop: short syllables with a hard attack.
  // ---------------------------------------------------------------------------

  List<SampleCandidate> _chopCandidates(SourceAnalysis s, List<int> onsets) {
    final f = s.features;
    final peak = f.rmsDb.fold<double>(-180, math.max);
    final maxFlux = f.flux.fold<double>(0, math.max);
    final out = <SampleCandidate>[];
    for (var k = 0; k < onsets.length; k++) {
      final a = onsets[k];
      final limit = k + 1 < onsets.length ? onsets[k + 1] : f.length;
      var b = a + 1;
      while (b < limit && b - a < 32 && f.rmsDb[b] > peak - 32) {
        b++;
      }
      final len = b - a;
      if (len < 8) continue;
      final voicedShare = [for (var i = a; i < b; i++) f.voiced(i) ? 1 : 0].fold<int>(0, (x, y) => x + y) / len;
      final attack = maxFlux > 0 ? (f.flux[a] / maxFlux).clamp(0.0, 1.0) : 0.0;
      final loud = ((_max(f.rmsDb, a, b) - (peak - 30)) / 30).clamp(0.0, 1.0);
      final dur = len * f.frameSeconds;
      final durFit = _bell(dur, 0.1, 0.3);
      final voiceFit = _bell(voicedShare, 0.35, 0.9);
      final score = 0.3 * attack + 0.25 * loud + 0.2 * durFit + 0.25 * voiceFit;
      final hz = [for (var i = a; i < b; i++) f.f0[i]];
      out.add(
        SampleCandidate(
          role: SampleRole.chop,
          sourceIndex: s.index,
          start: math.max(0, f.timeOf(a) - 0.005),
          end: f.timeOf(b),
          score: score,
          f0: median(hz.where((h) => h > 0)),
          details: {'attack': attack, 'loudness': loud, 'length': durFit, 'voiced': voiceFit},
        ),
      );
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
  // Quote: a dense spoken phrase bounded by pauses, ideally 1–2 bars long.
  // ---------------------------------------------------------------------------

  List<SampleCandidate> _quoteCandidates(SourceAnalysis s) {
    final f = s.features;
    final peak = f.rmsDb.fold<double>(-180, math.max);
    final active = [for (var i = 0; i < f.length; i++) f.rmsDb[i] > peak - 35];
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
    final out = <SampleCandidate>[];
    for (final (a, b) in phrases) {
      final dur = (b - a) * f.frameSeconds;
      if (dur < 0.5) continue;
      final voiced = [for (var k = a; k < b; k++) f.voiced(k) ? 1.0 : 0.0].fold<double>(0, (x, y) => x + y) / (b - a);
      final durFit = _bell(dur, 1.0, 3.6);
      final loud = ((_mean(f.rmsDb, a, b) - (peak - 30)) / 30).clamp(0.0, 1.0);
      final speech = _bell(voiced, 0.35, 0.85);
      out.add(
        SampleCandidate(
          role: SampleRole.quote,
          sourceIndex: s.index,
          start: math.max(0, f.timeOf(a) - 0.03),
          end: math.min(s.duration, f.timeOf(b) + 0.05),
          score: 0.4 * durFit + 0.3 * speech + 0.3 * loud,
          details: {'length': durFit, 'speech': speech, 'loudness': loud},
        ),
      );
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

  static double _max(Float64List x, int a, int b) {
    var m = -double.infinity;
    for (var i = a; i < b; i++) {
      m = math.max(m, x[i]);
    }
    return m;
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
