import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/audio_buffer.dart';
import '../audio/dsp.dart';
import '../audio/fft.dart';
import 'chart_import.dart' show phrygian;

/// What was learned from a base supplied only as audio.
class AudioBaseAnalysis {
  AudioBaseAnalysis({
    required this.bpm,
    required this.firstDownbeat,
    required this.bars,
    required this.barRoots,
    required this.tonicPc,
    required this.barEnergy,
    required this.tempoConfidence,
    this.signal,
    this.onsets,
  });

  /// The analysed mono signal at [AudioBaseAnalyzer.sampleRate].
  final Float32List? signal;

  /// Whitened onset strength per STFT frame, per band.
  final OnsetBands? onsets;

  final double bpm;

  /// Seconds into the audio where bar 1 starts.
  final double firstDownbeat;
  final int bars;

  /// Harmonic root per bar, semitones from the tonic (-6..5).
  final List<int> barRoots;

  /// Tonic pitch class (C = 0) under a Phrygian reading.
  final int tonicPc;
  final List<double> barEnergy;

  /// 0..1: how clearly one tempo stood out.
  final double tempoConfidence;

  double get barSeconds => 4 * 60 / bpm;

  /// The same analysis with bar 1 moved to [downbeat] (seconds).
  AudioBaseAnalysis withDownbeat(double downbeat) => AudioBaseAnalysis(
    bpm: bpm,
    firstDownbeat: downbeat,
    bars: signal == null
        ? bars
        : math.max(1, ((signal!.length / AudioBaseAnalyzer.sampleRate - downbeat) / barSeconds).floor()),
    barRoots: barRoots,
    tonicPc: tonicPc,
    barEnergy: barEnergy,
    tempoConfidence: tempoConfidence,
    signal: signal,
    onsets: onsets,
  );
}

/// Whitened onset envelopes (frames of [AudioBaseAnalyzer.hop] samples).
class OnsetBands {
  OnsetBands({required this.full, required this.sub, required this.low, required this.mid, required this.high});
  final Float64List full, sub, low, mid, high;

  int get frames => full.length;

  /// Frame index for an attack at [seconds].
  static double frameOf(double seconds) =>
      (seconds - AudioBaseAnalyzer.onsetLatency) * AudioBaseAnalyzer.sampleRate / AudioBaseAnalyzer.hop -
      AudioBaseAnalyzer.window / 2 / AudioBaseAnalyzer.hop;

  /// Strongest onset of [band] within ±[radius] frames of [seconds].
  static double peak(Float64List band, double seconds, {int radius = 2}) {
    final f = frameOf(seconds).round();
    var m = 0.0;
    for (var i = f - radius; i <= f + radius; i++) {
      if (i >= 0 && i < band.length && band[i] > m) m = band[i];
    }
    return m;
  }
}

class _Flux {
  _Flux(int frames)
    : full = Float64List(frames),
      sub = Float64List(frames),
      low = Float64List(frames),
      mid = Float64List(frames),
      high = Float64List(frames);
  final Float64List full, sub, low, mid, high;
}

/// Beat/tempo/downbeat tracking, chord roots and sectioning for audio bases.
class AudioBaseAnalyzer {
  static const sampleRate = 22050;

  /// Onset STFT (timing): short window, fine hop.
  static const hop = 128;
  static const window = 512;

  /// Chroma STFT (harmony): long window resolves bass semitones.
  static const chromaHop = 2048;
  static const chromaWindow = 8192;

  /// Onset frames are reported late relative to the attack by about this
  /// many seconds (window build-up), compensated below.
  static const onsetLatency = -0.004;

  /// Analyses [audio]; a [tempo] (BPM) is used as given instead of detected,
  /// e.g. to fix a half- or double-time reading.
  AudioBaseAnalysis analyze(AudioBuffer audio, {double? tempo}) {
    final mono = audio.mono();
    final x = mono.sampleRate == sampleRate
        ? mono.data
        : resample(mono.data, mono.sampleRate / sampleRate, sampleRate: mono.sampleRate);
    final frames = math.max(0, (x.length - window) ~/ hop + 1);
    if (frames < 400) throw ArgumentError('Audio is too short to analyse as a base.');

    // Onsets ------------------------------------------------------------------
    final flux = _onsetFlux(x, frames);
    final onset = _whiten(flux.full);
    final kick = _whiten(flux.low);
    final mid = _whiten(flux.mid);
    final high = _whiten(flux.high);
    final fps = sampleRate / hop;
    // Frame index → seconds of the attack it reports.
    double timeOf(double frame) => (frame * hop + window / 2) / sampleRate + onsetLatency;

    // Chroma ------------------------------------------------------------------
    final cFrames = math.max(1, (x.length - chromaWindow) ~/ chromaHop + 1);
    final chroma = Float64List(cFrames * 12);
    final bass = Float64List(cFrames * 12);
    {
      final fft = Fft(chromaWindow);
      final w = hann(chromaWindow);
      final bins = chromaWindow ~/ 2;
      final binPc = Int8List(bins)..fillRange(0, bins, -1);
      final binBass = Uint8List(bins);
      for (var k = 1; k < bins; k++) {
        final f = k * sampleRate / chromaWindow;
        // Kick drums ring (often tuned) below ~70 Hz, so harmony is read
        // above that; bass notes show up through their octave band.
        if (f < 75 || f > 1500) continue;
        binPc[k] = ((12 * math.log(f / 440) / math.ln2 + 69).round() % 12 + 12) % 12;
        if (f < 175) binBass[k] = 1;
      }
      final re = Float64List(chromaWindow), im = Float64List(chromaWindow);
      for (var fr = 0; fr < cFrames; fr++) {
        final o = fr * chromaHop;
        for (var i = 0; i < chromaWindow; i++) {
          re[i] = o + i < x.length ? x[o + i] * w[i] : 0;
          im[i] = 0;
        }
        fft.transform(re, im);
        for (var k = 1; k < bins; k++) {
          final pc = binPc[k];
          if (pc < 0) continue;
          final mag = math.sqrt(re[k] * re[k] + im[k] * im[k]);
          chroma[fr * 12 + pc] += mag;
          if (binBass[k] == 1) bass[fr * 12 + pc] += mag * mag;
        }
      }
    }
    double chromaTime(int fr) => (fr * chromaHop + chromaWindow / 2) / sampleRate;

    // Tempo: the user's, or autocorrelation with a prior near 140, refined by
    // how well a long beat comb stays in phase with the onsets.
    var bpm = tempo ?? 0;
    var confidence = 1.0;
    if (tempo == null) {
      final (coarse, conf) = _tempo(onset, fps);
      confidence = conf;
      bpm = coarse;
      var bestScore = -1.0;
      for (var cand = coarse - 1.6; cand <= coarse + 1.6; cand += 0.02) {
        final s = _bestPhase(onset, fps * 60 / cand, frames).$2;
        if (s > bestScore) {
          bestScore = s;
          bpm = cand;
        }
      }
      final whole = bpm.roundToDouble();
      if ((bpm - whole).abs() < 0.3) {
        bpm = whole;
      } else if ((bpm * 2 - (bpm * 2).round()).abs() < 0.2) {
        bpm = (bpm * 2).round() / 2;
      }
    }
    final period = fps * 60 / bpm;
    final bestPhase = _beatPhase(flux, period, frames);

    // Downbeat. In real Sparta bases the kick hits every beat but most on
    // beat 1, the snare 2 and 4, and the bass/chords change on the bar
    // line; sections (energy jumps) start on beat 1 or 3. Each cue is
    // compared across the four beat positions, relative to its average.
    final sub = _whiten(flux.sub);
    final beatSec = 60 / bpm;
    final subAt = List<double>.filled(4, 0), lowAt = List<double>.filled(4, 0), highAt = List<double>.filled(4, 0);
    final jumpAt = List<double>.filled(4, 0), bassAt = List<double>.filled(4, 0);
    double? lastRms;
    var i = 0;
    for (var t = bestPhase; t < frames - 1; t += period, i++) {
      final b = i % 4;
      subAt[b] += _at(sub, t);
      lowAt[b] += _at(kick, t);
      highAt[b] += _at(high, t);
      bassAt[b] += _bassChange(bass, timeOf(t), beatSec, chromaTime);
      final rms = _rms(x, timeOf(t), timeOf(t) + beatSec) + 1e-6;
      if (lastRms != null) {
        final db = gainToDb(rms / lastRms);
        if (db > 2) jumpAt[b] += db;
      }
      lastRms = rms;
    }
    List<double> rel(List<double> v) {
      final m = v.fold<double>(0, (a, b) => a + b) / 4 + 1e-9;
      return [for (final x in v) x / m];
    }

    final cues = [rel(subAt), rel(lowAt), rel(highAt), rel(jumpAt), rel(bassAt)];
    double single(List<double> v, int b) => v[b] - (v[(b + 1) % 4] + v[(b + 2) % 4] + v[(b + 3) % 4]) / 3;
    double halfBar(List<double> v, int b) => v[b] + v[(b + 2) % 4] - v[(b + 1) % 4] - v[(b + 3) % 4];
    var bestBar = 0;
    var bestBarScore = double.negativeInfinity;
    for (var b = 0; b < 4; b++) {
      final score =
          2 * single(cues[0], b) + // sub kick on 1
          halfBar(cues[1], b) + // kicks on 1 and 3
          -0.5 * halfBar(cues[2], b) + // snare on 2 and 4
          halfBar(cues[3], b) +
          0.25 * single(cues[3], b) + // sections start on 1 (or 3)
          2 * single(cues[4], b); // bass/chord changes on 1
      if (score > bestBarScore) {
        bestBarScore = score;
        bestBar = b;
      }
    }
    var downbeat = timeOf(bestPhase + bestBar * period);
    final barSec = 4 * 60 / bpm;
    while (downbeat - barSec > -0.02) {
      downbeat -= barSec;
    }
    if (downbeat < -0.02) downbeat += barSec;
    downbeat = math.max(0, downbeat);
    final duration = x.length / sampleRate;
    final bars = math.max(1, ((duration - downbeat) / barSec).floor());

    // Per-bar harmony and energy. Kicks hit nearly every beat and their
    // tuned body reads as a constant bass "note" (as does any drone), so each
    // pitch class's floor is removed first, leaving the parts that move.
    final harm = _withoutFloor(chroma, cFrames), harmBass = _withoutFloor(bass, cFrames);
    final total = Float64List(12);
    final barChroma = <Float64List>[];
    final barBass = <Float64List>[];
    final energy = <double>[];
    for (var b = 0; b < bars; b++) {
      final t0 = downbeat + b * barSec, t1 = t0 + barSec;
      final c = Float64List(12), bb = Float64List(12);
      for (var fr = 0; fr < cFrames; fr++) {
        final t = chromaTime(fr);
        if (t < t0 || t >= t1) continue;
        // The first half of the bar defines its chord most.
        final weight = t < t0 + barSec / 2 ? 1.5 : 1.0;
        for (var p = 0; p < 12; p++) {
          c[p] += harm[fr * 12 + p] * weight;
          bb[p] += harmBass[fr * 12 + p] * weight;
          total[p] += harm[fr * 12 + p];
        }
      }
      barChroma.add(c);
      barBass.add(bb);
      energy.add(_rms(x, t0, t1));
    }
    final tonic = _tonic(total);
    final roots = <int>[];
    for (var b = 0; b < bars; b++) {
      final nb = _norm(barBass[b]), nc = _norm(barChroma[b]);
      var best = 0;
      var bestV = -1.0;
      for (var p = 0; p < 12; p++) {
        final v = nb[p] * 2 + nc[p] * 0.5;
        if (v > bestV) {
          bestV = v;
          best = p;
        }
      }
      roots.add(((best - tonic) % 12 + 18) % 12 - 6);
    }
    return AudioBaseAnalysis(
      bpm: bpm,
      firstDownbeat: downbeat,
      bars: bars,
      barRoots: roots,
      tonicPc: tonic,
      barEnergy: energy,
      tempoConfidence: confidence,
      signal: x,
      onsets: OnsetBands(full: onset, sub: sub, low: kick, mid: mid, high: high),
    );
  }

  /// Spectral flux per frame: full band, plus low (< 160 Hz: kick, bass),
  /// mid (160 Hz–2 kHz: snare body, stabs) and high (2–8 kHz: snare noise,
  /// hats, cymbals) bands.
  static _Flux _onsetFlux(Float32List x, int frames) {
    final flux = _Flux(frames);
    final fft = Fft(window);
    final w = hann(window);
    final bins = window ~/ 2;
    final subBin = (110 * window / sampleRate).floor();
    final lowBin = (160 * window / sampleRate).ceil();
    final midBin = (2000 * window / sampleRate).ceil();
    final highBin = (8000 * window / sampleRate).ceil();
    final re = Float64List(window), im = Float64List(window);
    var prev = Float64List(bins), cur = Float64List(bins);
    for (var fr = 0; fr < frames; fr++) {
      final o = fr * hop;
      for (var i = 0; i < window; i++) {
        re[i] = x[o + i] * w[i];
        im[i] = 0;
      }
      fft.transform(re, im);
      var sf = 0.0, bf = 0.0, lf = 0.0, mf = 0.0, hf = 0.0;
      for (var k = 1; k < bins; k++) {
        final lm = math.log(1 + 100 * math.sqrt(re[k] * re[k] + im[k] * im[k]));
        cur[k] = lm;
        final d = lm - prev[k];
        if (d > 0) {
          sf += d;
          if (k <= subBin) bf += d;
          if (k <= lowBin) {
            lf += d;
          } else if (k <= midBin) {
            mf += d;
          } else if (k <= highBin) {
            hf += d;
          }
        }
      }
      flux.full[fr] = sf;
      flux.sub[fr] = bf;
      flux.low[fr] = lf;
      flux.mid[fr] = mf;
      flux.high[fr] = hf;
      final t = prev;
      prev = cur;
      cur = t;
    }
    return flux;
  }

  /// Finds where beat 0 of a chart lands in its audio render: the offset
  /// (seconds, within [minOffset, maxOffset]) that lines the chart's drum
  /// hits ([hitSeconds], relative to beat 0) up with the audio's onsets.
  ///
  /// Repetitive grooves line up equally well a beat or two off, so when the
  /// project's first note time is known ([firstNoteSeconds]) the search is
  /// anchored on where the audio first makes sound.
  ///
  /// With the project's tempo ([bpm]) the offset is kept on the audio's own
  /// beats: hats and off-beat stabs can line up a 16th or 8th note off,
  /// which plays every sample off the beat. The audio's beat phase was right
  /// on all 17 community bases with a render, where drum matching alone
  /// missed by a 16th or 8th on 6.
  double alignHits(
    AudioBuffer audio,
    List<double> hitSeconds, {
    double minOffset = -0.5,
    double maxOffset = 8,
    double? firstNoteSeconds,
    double? bpm,
  }) {
    final mono = audio.mono();
    final x = mono.sampleRate == sampleRate
        ? mono.data
        : resample(mono.data, mono.sampleRate / sampleRate, sampleRate: mono.sampleRate);
    final frames = math.max(0, (x.length - window) ~/ hop + 1);
    double? anchor;
    if (firstNoteSeconds != null) {
      final first = _firstSound(x);
      if (first != null) anchor = (first - firstNoteSeconds).clamp(minOffset, maxOffset);
    }
    if (hitSeconds.isEmpty || frames < 10) return anchor ?? 0;
    final flux = _onsetFlux(x, frames);
    final onset = _whiten(flux.full);
    final fps = sampleRate / hop;
    final base = (window / 2) / sampleRate + onsetLatency;
    final hits = hitSeconds.take(400).toList();
    double score(double off) {
      var s = 0.0;
      for (final h in hits) {
        s += _at(onset, (h + off - base) * fps);
      }
      return s;
    }

    if (bpm != null && bpm > 0 && frames > 400) {
      // Beat 0 sits on one of the audio's beats: the one nearest the anchor
      // unless another lines the drums up clearly better.
      final spb = 60 / bpm;
      final phase = ((_beatPhase(flux, fps * 60 / bpm, frames) * hop + window / 2) / sampleRate + onsetLatency) % spb;
      final lo = anchor == null ? minOffset : math.max(minOffset, anchor - 0.6 * spb);
      final hi = anchor == null ? maxOffset : math.min(maxOffset, anchor + 0.6 * spb);
      double? best;
      var bestScore = -1.0;
      for (var off = phase + ((lo - phase) / spb).ceil() * spb; off <= hi + 1e-9; off += spb) {
        final near = anchor == null ? 1.0 : 1 - 0.15 * (off - anchor).abs() / spb;
        final s = score(off) * near;
        if (s > bestScore) {
          bestScore = s;
          best = off;
        }
      }
      if (best != null) return best;
      // The anchor sits outside the allowed range (a trimmed render): the
      // nearest beat to it.
      if (anchor != null) return phase + ((anchor - phase) / spb).round() * spb;
    }
    var lo = minOffset, hi = maxOffset;
    if (anchor != null) {
      lo = math.max(minOffset, anchor - 0.12);
      hi = math.min(maxOffset, anchor + 0.12);
      if (hi < lo) return anchor;
    }
    var best = lo, bestScore = -1.0;
    for (var off = lo; off <= hi + 1e-9; off += 1 / fps) {
      final s = score(off);
      if (s > bestScore) {
        bestScore = s;
        best = off;
      }
    }
    return best;
  }

  /// Frame (fractional) of the first beat: the comb over kick and snare
  /// onsets. Open hats (loud, and everywhere in Sparta bases) sit between
  /// beats, so the full band can't place beats. At half time the comb can
  /// lock onto the snare beats (kick + snare is louder than a lone kick):
  /// the beats are where the kick's sub sits.
  static double _beatPhase(_Flux flux, double period, int frames) {
    final kick = _whiten(flux.low), mid = _whiten(flux.mid);
    final onBeat = Float64List(frames);
    for (var i = 0; i < frames; i++) {
      onBeat[i] = kick[i] + mid[i];
    }
    var phase = _bestPhase(onBeat, period, frames).$1;
    final subBand = _whiten(flux.sub);
    double subSum(double p) {
      var s = 0.0;
      for (var t = p; t < frames - 1; t += period) {
        s += _at(subBand, t);
      }
      return s;
    }

    final alt = (phase + period / 2) % period;
    if (subSum(alt) > subSum(phase) * 1.15) phase = alt;
    return phase;
  }

  static double _rms(Float32List x, double from, double to) {
    final a = (from * sampleRate).round().clamp(0, x.length), z = (to * sampleRate).round().clamp(a, x.length);
    var e = 0.0;
    for (var i = a; i < z; i++) {
      e += x[i] * x[i];
    }
    return z > a ? math.sqrt(e / (z - a)) : 0;
  }

  /// Time of the first sound above −40 dB relative to the loudest 10 ms.
  /// Seconds where the audio's last sound ends (a 10 ms block within 40 dB
  /// of the loudest), or null for silence.
  static double? lastSound(AudioBuffer audio) {
    final mono = audio.mono();
    final x = mono.data, rate = mono.sampleRate;
    final block = rate ~/ 100;
    final n = block == 0 ? 0 : x.length ~/ block;
    if (n == 0) return null;
    final rms = Float64List(n);
    var peak = 0.0;
    for (var b = 0; b < n; b++) {
      var e = 0.0;
      for (var i = b * block; i < (b + 1) * block; i++) {
        e += x[i] * x[i];
      }
      rms[b] = math.sqrt(e / block);
      peak = math.max(peak, rms[b]);
    }
    if (peak <= 0) return null;
    for (var b = n - 1; b >= 0; b--) {
      if (rms[b] > peak * 0.01) return (b + 1) * block / rate;
    }
    return null;
  }

  static double? _firstSound(Float32List x) {
    const block = sampleRate ~/ 100;
    final n = x.length ~/ block;
    if (n == 0) return null;
    final rms = Float64List(n);
    var peak = 0.0;
    for (var b = 0; b < n; b++) {
      var e = 0.0;
      for (var i = b * block; i < (b + 1) * block; i++) {
        e += x[i] * x[i];
      }
      rms[b] = math.sqrt(e / block);
      peak = math.max(peak, rms[b]);
    }
    if (peak <= 0) return null;
    final threshold = peak * 0.01;
    for (var b = 0; b < n; b++) {
      if (rms[b] > threshold) {
        // Refine to the sample where it crosses within the block.
        for (var i = b * block; i < (b + 1) * block; i++) {
          if (x[i].abs() > threshold) return i / sampleRate;
        }
        return b * block / sampleRate;
      }
    }
    return null;
  }

  static (double, double) _tempo(Float64List onset, double fps) {
    final minLag = (fps * 60 / 200).floor(), maxLag = (fps * 60 / 70).ceil();
    final n = onset.length;
    final ac = Float64List(maxLag * 2 + 2);
    for (var l = minLag ~/ 2; l < ac.length && l < n; l++) {
      var s = 0.0;
      for (var i = 0; i + l < n; i++) {
        s += onset[i] * onset[i + l];
      }
      ac[l] = s / (n - l);
    }
    double acAt(double l) {
      final i = l.floor();
      if (i + 1 >= ac.length || i < 0) return 0;
      return ac[i] + (ac[i + 1] - ac[i]) * (l - i);
    }

    const center = 140.0;
    var best = center, bestScore = -1.0;
    final scores = <double>[];
    for (var bpm = 70.0; bpm <= 200; bpm += 0.05) {
      final l = fps * 60 / bpm;
      final s = acAt(l) + 0.5 * acAt(2 * l) + 0.25 * acAt(l / 2);
      final prior = math.exp(-math.pow(math.log(bpm / center) / math.ln2, 2) / (2 * 0.35 * 0.35));
      final v = s * (0.4 + 0.6 * prior);
      scores.add(v);
      if (v > bestScore) {
        bestScore = v;
        best = bpm;
      }
    }
    final sorted = [...scores]..sort();
    final median = sorted[sorted.length ~/ 2];
    final confidence = bestScore <= 0 ? 0.0 : ((bestScore - median) / bestScore).clamp(0.0, 1.0);
    return (best, confidence);
  }

  /// How much the bass pitch content differs just before/after [t].
  static double _bassChange(Float64List bass, double t, double beat, double Function(int) timeOf) {
    final frames = bass.length ~/ 12;
    Float64List avg(double from, double to) {
      final out = Float64List(12);
      for (var f = 0; f < frames; f++) {
        final ft = timeOf(f);
        if (ft < from || ft >= to) continue;
        for (var p = 0; p < 12; p++) {
          out[p] += bass[f * 12 + p];
        }
      }
      return _norm(out);
    }

    final x = avg(t - beat, t), y = avg(t, t + beat);
    var d = 0.0;
    for (var p = 0; p < 12; p++) {
      d += (x[p] - y[p]).abs();
    }
    return d / 2;
  }

  static (double, double) _bestPhase(Float64List onset, double period, int frames) {
    var bestPhase = 0.0, bestScore = -1.0;
    for (var ph = 0.0; ph < period; ph += 0.5) {
      var s = 0.0;
      for (var t = ph; t < frames - 1; t += period) {
        s += _at(onset, t);
      }
      if (s > bestScore) {
        bestScore = s;
        bestPhase = ph;
      }
    }
    return (bestPhase, bestScore);
  }

  /// Root of the Phrygian mode (the Sparta tonality) that fits the pitch
  /// content best; D on near-ties.
  static int _tonic(Float64List pc) {
    double fit(int o) => phrygian.fold(0.0, (s, d) => s + pc[(o + d) % 12]);
    var best = 2;
    for (var o = 0; o < 12; o++) {
      if (fit(o) > fit(best) * 1.03) best = o;
    }
    return best;
  }

  /// [v] (frames × 12) minus each pitch class's 35th percentile over time.
  static Float64List _withoutFloor(Float64List v, int frames) {
    final out = Float64List(v.length);
    final column = Float64List(frames);
    for (var p = 0; p < 12; p++) {
      for (var f = 0; f < frames; f++) {
        column[f] = v[f * 12 + p];
      }
      final sorted = Float64List.fromList(column)..sort();
      final floor = sorted[((frames - 1) * 0.35).floor()];
      for (var f = 0; f < frames; f++) {
        out[f * 12 + p] = math.max(0, column[f] - floor);
      }
    }
    return out;
  }

  static Float64List _norm(Float64List v) {
    final s = v.fold<double>(0, (a, b) => a + b);
    return s <= 0 ? Float64List(12) : Float64List.fromList([for (final x in v) x / s]);
  }

  /// Local-mean-subtracted, half-wave rectified envelope, scaled so its
  /// strong onsets sit near 1.
  static Float64List _whiten(Float64List x) {
    final n = x.length;
    final out = Float64List(n);
    final prefix = Float64List(n + 1);
    for (var i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + x[i];
    }
    const r = 8;
    for (var i = 0; i < n; i++) {
      final lo = math.max(0, i - r), hi = math.min(n, i + r + 1);
      out[i] = math.max(0, x[i] - (prefix[hi] - prefix[lo]) / (hi - lo));
    }
    // Scale by the 99th percentile, not the peak, and cap outliers: one huge
    // onset (a part entering from silence) must not flatten all the others.
    final sorted = Float64List.fromList(out)..sort();
    var scale = sorted[((n - 1) * 0.99).floor()];
    if (scale <= 0) scale = sorted.isEmpty ? 0 : sorted.last;
    if (scale > 0) {
      for (var i = 0; i < n; i++) {
        out[i] = math.min(1.5, out[i] / scale);
      }
    }
    return out;
  }

  static double _at(Float64List x, double t) {
    final i = t.floor();
    if (i < 0 || i + 1 >= x.length) return 0;
    // Tolerate ±1 frame of jitter.
    var m = x[i] + (x[i + 1] - x[i]) * (t - i);
    if (i > 0) m = math.max(m, x[i - 1] * 0.7);
    if (i + 2 < x.length) m = math.max(m, x[i + 2] * 0.7);
    return m;
  }
}
