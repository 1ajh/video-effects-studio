import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/fft.dart';
import 'model.dart';
import 'transcription.dart';

/// What [AudioSectioner] hears in a base.
class AudioSectionResult {
  AudioSectionResult({required this.musicBars, required this.sections, required this.chords});

  /// Bars of music (the ring-out and silence after it are left out).
  final int musicBars;

  /// Sections in the Sparta template, or empty when the base has no
  /// recurring chorus to anchor them on.
  final List<Section> sections;

  /// Chord voices per half bar (semitones from the root; see
  /// [BaseTranscription.chords]).
  final List<GuideNote> chords;
}

/// Finds a base's sections, chords and end from its audio.
///
/// Sections: every bar gets a timbre / rhythm / harmony fingerprint; where
/// the fingerprints change most are the boundaries. The chorus is the loud
/// part the base keeps coming back to (Sparta bases are built around it), so
/// the segments most like each other and loudest are the choruses, what
/// comes before the first is the intro, and the parts between choruses follow
/// the Sparta order: DunDunDenDen, epicness, madness, epicness… On Keaton's
/// Sparta Extended base this gives exactly its 13 sections.
class AudioSectioner {
  static const _fftSize = 2048;
  static const _hop = 1024;

  /// Bands for the timbre fingerprint (Hz).
  static const _bands = [20.0, 150.0, 500.0, 2000.0, 6000.0, 11000.0];

  AudioSectionResult analyze(
    Float32List x,
    int sampleRate, {
    required double bpm,
    required double firstDownbeat,
    required int bars,
    required int rootPc,
  }) {
    final barSec = 4 * 60 / bpm;
    final frames = math.max(0, (x.length - _fftSize) ~/ _hop + 1);
    final fft = Fft(_fftSize);
    final window = hann(_fftSize);
    final re = Float64List(_fftSize), im = Float64List(_fftSize);
    final bins = _fftSize ~/ 2;
    final binBand = Int8List(bins)..fillRange(0, bins, -1);
    final binPc = Int8List(bins)..fillRange(0, bins, -1);
    for (var k = 1; k < bins; k++) {
      final f = k * sampleRate / _fftSize;
      for (var b = 0; b + 1 < _bands.length; b++) {
        if (f >= _bands[b] && f < _bands[b + 1]) binBand[k] = b;
      }
      if (f >= 60 && f <= 1800) binPc[k] = ((12 * math.log(f / 440) / math.ln2 + 69).round() % 12 + 12) % 12;
    }
    final nb = _bands.length - 1;
    final band = List.generate(frames, (_) => Float64List(nb));
    final chroma = List.generate(frames, (_) => Float64List(12));
    final flux = Float64List(frames);
    final bandFlux = List.generate(frames, (_) => Float64List(3));
    var prev = Float64List(bins), cur = Float64List(bins);
    for (var fr = 0; fr < frames; fr++) {
      final o = fr * _hop;
      for (var i = 0; i < _fftSize; i++) {
        re[i] = x[o + i] * window[i];
        im[i] = 0;
      }
      fft.transform(re, im);
      var fl = 0.0;
      for (var k = 1; k < bins; k++) {
        final p = re[k] * re[k] + im[k] * im[k];
        final m = math.sqrt(p);
        if (binBand[k] >= 0) band[fr][binBand[k]] += p;
        if (binPc[k] >= 0) chroma[fr][binPc[k]] += m;
        cur[k] = math.log(1 + 100 * m);
        final d = cur[k] - prev[k];
        if (d > 0) {
          fl += d;
          final f = k * sampleRate / _fftSize;
          bandFlux[fr][f < 150 ? 0 : (f < 2000 ? 1 : (f > 5000 ? 2 : 1))] += d;
        }
      }
      flux[fr] = fl;
      final t = prev;
      prev = cur;
      cur = t;
    }
    double timeOf(int fr) => (fr * _hop + _fftSize / 2) / sampleRate;
    int frameAt(double t) => ((t * sampleRate - _fftSize / 2) / _hop).round();

    // --- per bar -------------------------------------------------------------
    final level = Float64List(bars);
    final feats = <List<double>>[];
    for (var b = 0; b < bars; b++) {
      final t0 = firstDownbeat + b * barSec;
      final a = frameAt(t0).clamp(0, frames), z = frameAt(t0 + barSec).clamp(a, frames);
      final e = Float64List(nb), c = Float64List(12);
      final rhythm = Float64List(16);
      final bf = Float64List(3);
      for (var fr = a; fr < z; fr++) {
        for (var i = 0; i < nb; i++) {
          e[i] += band[fr][i];
        }
        for (var i = 0; i < 12; i++) {
          c[i] += chroma[fr][i];
        }
        final step = ((timeOf(fr) - t0) / barSec * 16).floor().clamp(0, 15);
        rhythm[step] += flux[fr];
        for (var i = 0; i < 3; i++) {
          bf[i] += bandFlux[fr][i];
        }
      }
      final n = math.max(1, z - a);
      var total = 0.0;
      for (var i = 0; i < nb; i++) {
        total += e[i] / n;
      }
      level[b] = 10 * math.log(total + 1e-12) / math.ln10;
      final cs = c.fold<double>(0, (s, v) => s + v) + 1e-12;
      final rs = rhythm.fold<double>(0, (s, v) => s + v) + 1e-12;
      feats.add([
        for (var i = 0; i < nb; i++) 10 * math.log(e[i] / n + 1e-12) / math.ln10,
        for (var i = 0; i < 12; i++) c[i] / cs * 4,
        for (var i = 0; i < 16; i++) rhythm[i] / rs * 6,
        for (var i = 0; i < 3; i++) math.log(1 + bf[i] / n),
      ]);
    }

    // --- where the music ends ------------------------------------------------
    final sortedLevel = [...level]..sort();
    final median = sortedLevel.isEmpty ? 0.0 : sortedLevel[sortedLevel.length ~/ 2];
    var musicBars = bars;
    while (musicBars > 1 && level[musicBars - 1] < median - 10) {
      musicBars--;
    }

    final chords = _chords(x, sampleRate, chroma, frameAt, firstDownbeat, barSec, musicBars, rootPc, frames);
    if (musicBars < 8) return AudioSectionResult(musicBars: musicBars, sections: const [], chords: chords);

    // --- fingerprints, compared --------------------------------------------------
    final dims = feats.first.length;
    final mean = List<double>.filled(dims, 0), sd = List<double>.filled(dims, 0);
    for (var b = 0; b < musicBars; b++) {
      for (var d = 0; d < dims; d++) {
        mean[d] += feats[b][d] / musicBars;
      }
    }
    for (var b = 0; b < musicBars; b++) {
      for (var d = 0; d < dims; d++) {
        sd[d] += math.pow(feats[b][d] - mean[d], 2) / musicBars;
      }
    }
    final z = [
      for (var b = 0; b < musicBars; b++)
        [for (var d = 0; d < dims; d++) (feats[b][d] - mean[d]) / (math.sqrt(sd[d]) + 1e-6) * _weight(d)],
    ];
    double sim(List<double> p, List<double> q) {
      var dot = 0.0, np = 0.0, nq = 0.0;
      for (var d = 0; d < p.length; d++) {
        dot += p[d] * q[d];
        np += p[d] * p[d];
        nq += q[d] * q[d];
      }
      return np == 0 || nq == 0 ? 0 : dot / math.sqrt(np * nq);
    }

    // Sparta bases are built from 2- and 4-bar blocks: each 2-bar unit is a
    // building block, compared with every other.
    final units = <(int, int)>[for (var u = 0; u < musicBars; u += 2) (u, math.min(u + 2, musicBars))];
    List<double> centroidOf(Iterable<int> bs) {
      final m = List<double>.filled(dims, 0);
      var n = 0;
      for (final b in bs) {
        for (var d = 0; d < dims; d++) {
          m[d] += z[b][d];
        }
        n++;
      }
      return [for (final v in m) v / math.max(1, n)];
    }

    double levelOf(Iterable<int> bs) {
      var e = 0.0, n = 0;
      for (final b in bs) {
        e += level[b];
        n++;
      }
      return e / math.max(1, n);
    }

    Iterable<int> barsOf((int, int) u) sync* {
      for (var b = u.$1; b < u.$2; b++) {
        yield b;
      }
    }

    final uVec = [for (final u in units) centroidOf(barsOf(u))];
    final uLevel = [for (final u in units) levelOf(barsOf(u))];
    final top = uLevel.reduce(math.max);

    // The chorus: the loud block the base keeps coming back to.
    var seed = 0;
    var seedScore = double.negativeInfinity;
    for (var i = 0; i < units.length; i++) {
      if (uLevel[i] < top - 6) continue;
      var rep = 0.0;
      for (var j = 0; j < units.length; j++) {
        if ((i - j).abs() > 1) rep += math.max(0, sim(uVec[i], uVec[j]));
      }
      final score = rep + (uLevel[i] - top) * 0.3;
      if (score > seedScore) {
        seedScore = score;
        seed = i;
      }
    }
    var chorusVec = uVec[seed];
    var chorusLevel = uLevel[seed];
    List<bool> classify(double minSim) => [
      for (var i = 0; i < units.length; i++) sim(uVec[i], chorusVec) >= minSim && uLevel[i] >= chorusLevel - 4.5,
    ];
    var isChorus = classify(0.5);
    // Refine around the average chorus block.
    final members = [
      for (var i = 0; i < units.length; i++)
        if (isChorus[i]) i,
    ];
    chorusVec = centroidOf([for (final i in members) ...barsOf(units[i])]);
    chorusLevel = levelOf([for (final i in members) ...barsOf(units[i])]);
    isChorus = classify(0.4);
    // A lone block between two of the other kind follows its neighbours.
    for (var i = 1; i + 1 < units.length; i++) {
      if (isChorus[i - 1] == isChorus[i + 1] && isChorus[i] != isChorus[i - 1]) isChorus[i] = isChorus[i - 1];
    }
    if (isChorus.where((c) => c).length < 2) {
      return AudioSectionResult(musicBars: musicBars, sections: const [], chords: chords);
    }

    // Runs of blocks; the parts between choruses split where they change.
    final segs = <(int, int, bool)>[];
    for (var i = 0; i < units.length; i++) {
      final startsNew =
          segs.isEmpty ||
          segs.last.$3 != isChorus[i] ||
          (!isChorus[i] && sim(uVec[i], uVec[i - 1]) < 0.25 && units[i].$1 - segs.last.$1 >= 4);
      if (startsNew) {
        segs.add((units[i].$1, units[i].$2, isChorus[i]));
      } else {
        segs[segs.length - 1] = (segs.last.$1, units[i].$2, segs.last.$3);
      }
    }

    // --- labels in the Sparta order ------------------------------------------------
    const template = [
      SectionKind.dundundenden,
      SectionKind.epicness,
      SectionKind.madness,
      SectionKind.epicness,
      SectionKind.madness,
    ];
    final first = segs.indexWhere((s) => s.$3);
    final last = segs.lastIndexWhere((s) => s.$3);
    final kinds = <SectionKind>[];
    var gap = 0;
    for (var i = 0; i < segs.length; i++) {
      final (a, z, chorus) = segs[i];
      if (chorus) {
        kinds.add(SectionKind.chorus);
      } else if (i < first) {
        kinds.add(SectionKind.intro);
      } else if (i > last && levelOf([for (var b = a; b < z; b++) b]) < chorusLevel - 6) {
        kinds.add(SectionKind.outro);
      } else if (segs[i - 1].$3) {
        // The first part of each gap between choruses sets its kind.
        kinds.add(template[math.min(gap, template.length - 1)]);
        gap++;
      } else {
        final k = kinds.last;
        final endsGap = i + 1 >= segs.length || segs[i + 1].$3;
        kinds.add(k == SectionKind.epicness && endsGap && z - a <= 4 ? SectionKind.postEpicness : k);
      }
    }
    final sections = <Section>[
      for (var i = 0; i < segs.length; i++) Section(kinds[i], segs[i].$1 * 4.0, segs[i].$2 * 4.0),
    ];
    return AudioSectionResult(musicBars: musicBars, sections: sections, chords: chords);
  }

  /// Fingerprint weights: timbre and which drums play count most, then
  /// rhythm, then harmony (the chords loop through every section).
  static double _weight(int d) {
    if (d < 5) return 2.0;
    if (d < 17) return 0.3;
    if (d < 33) return 0.5;
    return 1.8;
  }

  /// The chord on every half bar: its root from the bass (40–180 Hz), major
  /// or minor from the third above it. Half bars without a clear bass get
  /// no chord.
  static List<GuideNote> _chords(
    Float32List x,
    int sampleRate,
    List<Float64List> chroma,
    int Function(double) frameAt,
    double downbeat,
    double barSec,
    int bars,
    int rootPc,
    int frames,
  ) {
    final out = <GuideNote>[];
    // Bass notes a semitone apart are 4 Hz apart down there: a long window.
    // Kicks ring (often tuned) below ~70 Hz, so bass notes are read from
    // 75 Hz up, where their octave shows even when the fundamental is lower.
    const n = 8192, hop = 2048;
    final bFrames = math.max(0, (x.length - n) ~/ hop + 1);
    final fft = Fft(n);
    final w = hann(n);
    final binPc = Int8List(n ~/ 2)..fillRange(0, n ~/ 2, -1);
    for (var k = 1; k < n ~/ 2; k++) {
      final f = k * sampleRate / n;
      if (f >= 75 && f < 200) binPc[k] = ((12 * math.log(f / 440) / math.ln2 + 69).round() % 12 + 12) % 12;
    }
    final bass = List.generate(bFrames, (_) => Float64List(12));
    final re = Float64List(n), im = Float64List(n);
    for (var fr = 0; fr < bFrames; fr++) {
      for (var i = 0; i < n; i++) {
        re[i] = x[fr * hop + i] * w[i];
        im[i] = 0;
      }
      fft.transform(re, im);
      for (var k = 1; k < n ~/ 2; k++) {
        if (binPc[k] >= 0) bass[fr][binPc[k]] += re[k] * re[k] + im[k] * im[k];
      }
    }
    int bassFrameAt(double t) => ((t * sampleRate - n / 2) / hop).round();
    // A drone or a tuned kick reads as a constant note: each pitch class's
    // floor (its 20th percentile over the song) is taken off first.
    final floorOf = List<double>.filled(12, 0);
    if (bass.isNotEmpty) {
      for (var p = 0; p < 12; p++) {
        final v = [for (final f in bass) f[p]]..sort();
        floorOf[p] = v[(v.length * 0.2).floor()];
      }
    }
    final strengths = <double>[];
    final roots = <(int, double, int, double)>[]; // (pc, strength, quality, beat)
    for (var h = 0; h < bars * 2; h++) {
      final t0 = downbeat + h * barSec / 2;
      final a = frameAt(t0 + 0.03).clamp(0, frames), z = frameAt(t0 + barSec / 2 - 0.03).clamp(a, frames);
      if (z <= a) continue;
      final b = Float64List(12), c = Float64List(12);
      for (var fr = a; fr < z; fr++) {
        for (var p = 0; p < 12; p++) {
          c[p] += chroma[fr][p];
        }
      }
      final ba = bassFrameAt(t0 + 0.05).clamp(0, bFrames), bz = bassFrameAt(t0 + barSec / 2 - 0.05).clamp(ba, bFrames);
      for (var fr = ba; fr <= math.min(bz, bFrames - 1); fr++) {
        for (var p = 0; p < 12; p++) {
          b[p] += math.max(0, bass[fr][p] - floorOf[p]);
        }
      }
      var pc = 0;
      for (var p = 1; p < 12; p++) {
        if (b[p] > b[pc]) pc = p;
      }
      final total = b.fold<double>(0, (s, v) => s + v) + 1e-12;
      final share = b[pc] / total;
      final third = c[(pc + 4) % 12] >= c[(pc + 3) % 12] ? 4 : 3;
      strengths.add(total);
      roots.add((pc, share, third, h * 2.0));
    }
    if (roots.isEmpty) return out;
    final sorted = [...strengths]..sort();
    final floor = sorted[(sorted.length * 0.25).floor()] * 0.5;
    for (var i = 0; i < roots.length; i++) {
      final (pc, share, third, beat) = roots[i];
      // A clear bass note: loud enough and standing out from the rest.
      if (strengths[i] < floor || share < 0.22) continue;
      final root = ((pc - rootPc) % 12 + 18) % 12 - 6;
      for (final iv in [0, third, 7]) {
        out.add(GuideNote(beat, 2, root + iv));
      }
    }
    return out;
  }
}
