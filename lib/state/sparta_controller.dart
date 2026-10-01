import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/audio/audio_buffer.dart';
import '../core/ffmpeg/ffmpeg_runner.dart';
import '../core/ffmpeg/media_info.dart';
import '../core/models/output_settings.dart';
import '../core/render/render_engine.dart';
import '../core/sparta/arranger.dart';
import '../core/sparta/base_library.dart';
import '../core/sparta/chart_import.dart';
import '../core/sparta/charter.dart';
import '../core/sparta/model.dart';
import '../core/sparta/patterns.dart';
import '../core/sparta/project_transcriber.dart';
import '../core/sparta/sample_finder.dart';
import '../core/sparta/sample_processing.dart';
import '../core/sparta/section_edits.dart';
import '../core/sparta/sparta_engine.dart';
import '../core/sparta/transcription.dart';
import '../core/sparta/visual_renderer.dart';
import 'engine_controller.dart';
import 'project_controller.dart';
import 'render_queue.dart';
import 'store.dart';

/// The Sparta workflow: pick a base, add sources, confirm the line, generate.
enum SpartaStep {
  base('Base', 'Pick the base your remix follows'),
  source('Source', 'Videos or audio of the person / character'),
  line('Line', 'The spoken line: the quote and the chorus words'),
  generate('Generate', 'Sound, video and random mode');

  const SpartaStep(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// Where the base comes from.
enum BaseTab {
  library('Library', 'Real Sparta bases, downloaded when you pick one'),
  audio('Your audio', 'A base you have as MP3 / WAV: transcribed by listening'),
  project('Your project', "An FL Studio .flp / FL Mobile .flm / MIDI file: the base's exact notes");

  const BaseTab(this.label, this.blurb);
  final String label;
  final String blurb;
}

/// Quick drum fixes for a section of the transcription.
enum DrumFill {
  clear('Clear'),
  standard('Standard groove'),
  auto('As transcribed');

  const DrumFill(this.label);
  final String label;
}

const projectFileExtensions = {'flp', 'flm', 'mid', 'midi'};

bool isProjectFile(String path) =>
    projectFileExtensions.contains(p.extension(path).replaceFirst('.', '').toLowerCase());

class SpartaSource {
  SpartaSource(this.path);
  final String path;
  MediaInfo? info;
  SourceAnalysis? analysis;
  String? error;
  bool busy = true;

  String get name => p.basename(path);
  bool get hasVideo => info?.hasVideo ?? false;
}

/// The candidates for one lane and which ones are in use.
class RolePick {
  RolePick(this.role, this.options);
  final SampleRole role;
  final List<SampleCandidate> options;
  int index = 0;

  /// Second sample alternating with the first, per section.
  int? alternate;
  double nudgeStart = 0;
  double nudgeEnd = 0;

  SampleCandidate get current => _nudged(options[index]);
  SampleCandidate? get alternateCandidate => alternate == null ? null : options[alternate!];

  SampleCandidate _nudged(SampleCandidate c) {
    final s = math.max(0.0, c.start + nudgeStart);
    final e = math.max(s + 0.03, c.end + nudgeEnd);
    return c.withRange(s, e);
  }
}

enum SpartaStage { idle, working, ready, failed }

/// State and pipeline of the Sparta Remix mode.
class SpartaController extends ChangeNotifier {
  SpartaController(this._engine, {Store? store, Future<String> Function()? loadBundledCatalog})
    : _store = store,
      _loadBundled = loadBundledCatalog {
    _engine.addListener(_onEngine);
    _loadOptions();
  }

  final EngineController _engine;
  final Store? _store;
  final Future<String> Function()? _loadBundled;
  SpartaEngine? _sparta;
  String _bundled = '{"version":1,"bases":[]}';

  SpartaStep step = SpartaStep.base;

  void goTo(SpartaStep s) {
    step = s;
    notifyListeners();
    if (s == SpartaStep.line && found == null) _schedule(_findLines);
  }

  bool stepDone(SpartaStep s) => switch (s) {
    SpartaStep.base => prepared != null,
    SpartaStep.source => readySources > 0,
    SpartaStep.line => line != null && line!.words.isNotEmpty,
    SpartaStep.generate => hasResult,
  };

  // ===========================================================================
  // Base
  // ===========================================================================

  BaseTab tab = BaseTab.library;
  BaseCatalog? catalog;
  bool catalogLoading = false;
  String query = '';
  bool exactOnly = false;

  /// Download progress of the base being fetched (0..1).
  double? downloadProgress;

  BaseSource? baseSource;

  String? projectPath;
  String? projectAudioPath;
  ChartSource? projectChart;
  String? projectError;
  Map<String, TrackUse> uses = {};
  double? manualOffset;

  String? audioBasePath;

  /// Tempo of an audio base set by the user instead of detected.
  double? bpmOverride;

  PreparedBase? prepared;
  String? baseError;
  bool baseLoading = false;
  String baseStatus = '';

  /// The user's fixes to the transcription (null: the automatic one).
  BaseTranscription? _fixed;

  BaseTranscription? get transcription => prepared?.transcription;
  bool get transcriptionFixed => _fixed != null;

  void setTab(BaseTab t) {
    tab = t;
    notifyListeners();
  }

  Future<void> loadCatalog({bool refresh = true}) async {
    if (catalogLoading) return;
    catalogLoading = true;
    notifyListeners();
    try {
      final bundled = await (_loadBundled?.call() ?? Future.value(_bundled));
      if (bundled != _bundled) _sparta = null;
      _bundled = bundled;
      catalog = BaseCatalog.parse(_bundled);
      notifyListeners();
      // Newer bases and checked transcriptions from the repository.
      if (_engine.ready || refresh) {
        final lib = _eng?.library ?? BaseLibrary(cacheDir: p.join(Directory.systemTemp.path, 'vfx_sparta'));
        catalog = await lib.catalog(_bundled, refresh: refresh);
      }
    } catch (e) {
      debugPrint('Base catalog: $e');
    } finally {
      catalogLoading = false;
      notifyListeners();
    }
  }

  void setQuery(String q) {
    query = q;
    notifyListeners();
  }

  void setExactOnly(bool v) {
    exactOnly = v;
    notifyListeners();
  }

  /// Catalog bases matching the search: featured and exact ones first.
  List<CatalogBase> get results {
    final c = catalog;
    if (c == null) return const [];
    return c.search(query, exactOnly: exactOnly);
  }

  String? get selectedCatalogId => switch (baseSource) {
    LibraryBaseSource(:final base) => base.id,
    _ => null,
  };

  void selectCatalogBase(CatalogBase b) {
    baseSource = LibraryBaseSource(b);
    _baseChanged();
  }

  void setAudioBase(String path) {
    audioBasePath = path;
    tab = BaseTab.audio;
    bpmOverride = null;
    baseSource = AudioBaseSource(audioPath: path);
    _baseChanged();
  }

  /// Uses [bpm] for the audio base instead of the detected tempo (null goes
  /// back to detection). Bars move, so the base is transcribed again.
  void setBpm(double? bpm) {
    final v = bpm == null || !bpm.isFinite || bpm < 40 || bpm > 400 ? null : (bpm * 100).roundToDouble() / 100;
    if (v == bpmOverride || audioBasePath == null) return;
    bpmOverride = v;
    baseSource = AudioBaseSource(audioPath: audioBasePath!, bpm: v);
    _dropFixes();
    _baseChanged();
  }

  double? get audioBpm => bpmOverride ?? prepared?.analysis?.bpm;
  void halveTempo() => setBpm(audioBpm == null ? null : audioBpm! / 2);
  void doubleTempo() => setBpm(audioBpm == null ? null : audioBpm! * 2);

  Future<void> setProject(String path) async {
    projectPath = path;
    projectChart = null;
    projectError = null;
    uses = {};
    manualOffset = null;
    tab = BaseTab.project;
    notifyListeners();
    try {
      projectChart = await Future(() => SpartaEngine.readProject(path));
    } catch (e) {
      projectError = _short(e);
      notifyListeners();
      return;
    }
    _setProjectSource();
  }

  void setProjectAudio(String? path) {
    projectAudioPath = path;
    manualOffset = null;
    _setProjectSource();
  }

  void setTrackUse(String trackId, TrackUse use) {
    uses = {...uses, trackId: use};
    _dropFixes();
    _setProjectSource();
  }

  void setManualOffset(double? seconds) {
    manualOffset = seconds;
    _setProjectSource();
  }

  void _setProjectSource() {
    final path = projectPath;
    if (path == null || projectChart == null) return;
    baseSource = ProjectBaseSource(
      projectPath: path,
      audioPath: projectAudioPath,
      uses: uses,
      audioOffset: manualOffset,
    );
    _baseChanged();
  }

  void _baseChanged() {
    final source = baseSource;
    _fixed = null;
    choices = {};
    if (source != null) _loadFixes(source.key);
    notifyListeners();
    _schedule(_loadBase, immediate: true);
  }

  Future<void> _loadBase(int t) async {
    final eng = _eng;
    final source = baseSource;
    if (eng == null || source == null) return;
    baseLoading = true;
    baseError = null;
    downloadProgress = null;
    prepared = null;
    mix = null;
    previewPath = null;
    notifyListeners();
    try {
      final base = await eng.prepareBase(
        source,
        fixed: _fixed,
        onStatus: (s, f) {
          if (t != _token) return;
          baseStatus = s;
          downloadProgress = f;
          _status(s, f);
        },
      );
      if (t != _token) return;
      prepared = base;
      if (step == SpartaStep.base && readySources == 0) step = SpartaStep.source;
      if (processed.isNotEmpty) await _resampleAndMix(t);
    } catch (e) {
      if (t == _token) baseError = _short(e);
      rethrow;
    } finally {
      if (t == _token) {
        baseLoading = false;
        downloadProgress = null;
        baseStatus = '';
      }
    }
  }

  // --- fixing the transcription -------------------------------------------------

  List<Section> get currentSections => transcription?.sections ?? const [];

  void _fix(BaseTranscription Function(BaseTranscription t) change, {bool retune = false}) {
    final base = prepared;
    if (base == null) return;
    final t = change(base.transcription).copyWith(source: TranscriptionSource.user, confidence: 1);
    _fixed = t;
    prepared = base.withTranscription(t);
    _saveFixes();
    notifyListeners();
    if (hasResult || processed.isNotEmpty) _schedule(retune ? _resampleAndMix : _remixOnly);
  }

  void relabelSection(int i, SectionKind kind) {
    _fix((t) => t.copyWith(sections: SectionOps.relabel(t.sections, i, kind)));
    choices.remove(i);
  }

  void renameSection(int i, String name) => _fix((t) => t.copyWith(sections: SectionOps.rename(t.sections, i, name)));

  void splitSection(int i, double beat) {
    choices = {
      for (final e in choices.entries)
        if (e.key <= i) e.key: e.value else e.key + 1: e.value,
      if (choices[i] != null) i + 1: choices[i]!,
    };
    _fix((t) => t.copyWith(sections: SectionOps.split(t.sections, i, beat)));
  }

  void mergeSectionWithNext(int i) {
    choices = {
      for (final e in choices.entries)
        if (e.key <= i) e.key: e.value else if (e.key > i + 1) e.key - 1: e.value,
    };
    _fix((t) => t.copyWith(sections: SectionOps.mergeWithNext(t.sections, i)));
  }

  void moveSectionBoundary(int i, double beat) =>
      _fix((t) => t.copyWith(sections: SectionOps.moveBoundary(t.sections, i, beat, t.beatsPerBar)));

  /// Uses another base's section layout here, bar for bar.
  void copySections(List<Section> layout) =>
      _fix((t) => t.copyWith(sections: SectionOps.fit(layout, t.lengthBeats, t.beatsPerBar)));

  /// The base's root note (the pitch sample is tuned to it).
  void setRoot(int key) => _fix((t) => t.copyWith(rootKey: key.clamp(24, 96)), retune: true);

  /// Seconds into the audio where beat 0 lands.
  void setOffset(double seconds) => _fix((t) => t.copyWith(audioOffset: seconds));

  /// Moves the hits of section [i] up or down.
  void transposeSectionHits(int i, int semitones) => _fix((t) {
    final s = t.sections[i];
    return t.copyWith(
      hits: [for (final h in t.hits) s.contains(h.beat) ? h.copyWith(semitone: h.semitone + semitones) : h],
    );
  });

  /// Replaces the hits of section [i] with a wiki (or typed) pitch pattern,
  /// or clears them when [patternId] is empty.
  void setSectionHits(int i, String patternId) => _fix((t) {
    final s = t.sections[i];
    final pat = patternId.isEmpty ? null : Charter().pattern(PatternKind.pitch, patternId);
    final steps = (s.lengthBeats * 4).roundToDouble();
    return t.copyWith(
      hits: [
        for (final h in t.hits)
          if (!s.contains(h.beat)) h,
        if (pat != null)
          for (final h in pat.looped(steps)) GuideNote(s.startBeat + h.step / 4, h.length / 4, h.semitone),
      ]..sort((a, b) => a.beat.compareTo(b.beat)),
    );
  });

  /// Sets the kick, snare or hat of section [i].
  void setSectionDrums(int i, SampleRole role, DrumFill fill) => _fix((t) {
    final s = t.sections[i];
    final auto = prepared!.auto;
    final kept = [
      for (final b in t.drums(role))
        if (!s.contains(b)) b,
    ];
    final fresh = switch (fill) {
      DrumFill.clear => const <double>[],
      DrumFill.auto => [
        for (final b in auto.drums(role))
          if (s.contains(b)) b,
      ],
      // Kick on every beat, snare on 2 and 4, hats between the beats.
      DrumFill.standard => [
        for (var k = 0; s.startBeat + k < s.endBeat - 1e-9; k++)
          ?switch (role) {
            SampleRole.kick => s.startBeat + k,
            SampleRole.snare => k.isOdd ? s.startBeat + k : null,
            _ => s.startBeat + k + 0.5,
          },
      ],
    };
    final all = [...kept, ...fresh]..sort();
    return switch (role) {
      SampleRole.kick => t.copyWith(kick: all),
      SampleRole.snare => t.copyWith(snare: all),
      _ => t.copyWith(hat: all),
    };
  });

  /// Back to the automatic transcription (and default section choices).
  void resetFixes() {
    final base = prepared;
    if (base == null) return;
    _dropFixes();
    prepared = base.withTranscription(base.auto);
    notifyListeners();
    if (hasResult) _schedule(_resampleAndMix);
  }

  void _dropFixes() {
    _fixed = null;
    choices = {};
    final key = baseSource?.key;
    if (key != null) _store?.remove('sparta.fix.$key');
  }

  void _loadFixes(String key) {
    final j = _store?.readJson<Map<String, dynamic>>('sparta.fix.$key');
    if (j == null) return;
    try {
      final t = j['transcription'];
      if (t is Map) _fixed = BaseTranscription.fromJson(t.cast<String, Object?>());
      final c = j['choices'];
      if (c is Map) {
        choices = {
          for (final e in c.entries)
            if (int.tryParse('${e.key}') != null && e.value is Map)
              int.parse('${e.key}'): SectionChoice.fromJson((e.value as Map).cast<String, Object?>()),
        };
      }
    } catch (e) {
      debugPrint('Ignoring saved Sparta fixes: $e');
    }
  }

  void _saveFixes() {
    final key = baseSource?.key, store = _store;
    if (key == null || store == null) return;
    if (_fixed == null && choices.isEmpty) {
      store.remove('sparta.fix.$key');
      return;
    }
    store.writeJson('sparta.fix.$key', {
      if (_fixed != null) 'transcription': _fixed!.toJson(),
      'choices': {for (final e in choices.entries) '${e.key}': e.value.toJson()},
    });
  }

  /// Other bases whose sections you fixed, to copy their layout.
  List<({String name, List<Section> layout})> get savedLayouts {
    final store = _store;
    if (store == null) return const [];
    const prefix = 'sparta.fix.';
    final out = <({String name, List<Section> layout})>[];
    for (final key in store.keysStartingWith(prefix)) {
      if (key == '$prefix${baseSource?.key}') continue;
      try {
        final t = store.readJson<Map<String, dynamic>>(key)?['transcription'];
        if (t is! Map) continue;
        final tr = BaseTranscription.fromJson(t.cast<String, Object?>());
        if (tr.sections.isEmpty) continue;
        final name = tr.baseName.isNotEmpty ? tr.baseName : p.basename(key.substring(prefix.length));
        out.add((name: name, layout: tr.sections));
      } catch (_) {}
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Saves the (fixed) transcription for sending in; returns its path.
  Future<String> saveTranscription(String dir, {String credit = ''}) async {
    final t = transcription!.copyWith(credit: credit.trim().isEmpty ? null : credit.trim());
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, BaseLibrary.submissionFileName(t));
    await File(path).writeAsString(t.encode());
    return path;
  }

  Uri submissionUrl({String credit = '', String notes = ''}) =>
      BaseLibrary.submissionUrl(transcription!, credit: credit, notes: notes);

  // ===========================================================================
  // Per-section choices and random mode
  // ===========================================================================

  Map<int, SectionChoice> choices = {};
  RandomOptions random = const RandomOptions();

  /// Pitch also plays in the chorus (off: the chorus is words only).
  bool pitchInChorus = false;

  SectionChoice choiceAt(int i) => choices[i] ?? const SectionChoice();

  void setChoice(int i, SectionChoice c) {
    choices = {...choices, i: c};
    if (c.isDefault) choices.remove(i);
    _saveFixes();
    notifyListeners();
    if (hasResult) _schedule(_remixOnly);
  }

  void setWords(int i, String? id) =>
      setChoice(i, id == null ? choiceAt(i).copyWith(clearWords: true) : choiceAt(i).copyWith(words: id));

  void setPitch(int i, PitchMode mode, {String? pattern}) =>
      setChoice(i, choiceAt(i).copyWith(pitch: mode, pitchPattern: pattern));

  void resetChoice(int i) => setChoice(i, const SectionChoice());

  /// Another random take for section [i] (random mode).
  void rerollSection(int i) => setChoice(i, choiceAt(i).copyWith(variant: choiceAt(i).variant + 1));

  void setRandom(RandomOptions r) {
    random = r;
    _saveOptions();
    notifyListeners();
    if (hasResult) _schedule(_remixOnly);
  }

  void rerollAll() => setRandom(random.copyWith(seed: random.seed + 1));

  void setPitchInChorus(bool v) {
    pitchInChorus = v;
    notifyListeners();
    if (hasResult) _schedule(_remixOnly);
  }

  // ===========================================================================
  // Sources
  // ===========================================================================

  final List<SpartaSource> _sources = [];
  List<SpartaSource> get sources => List.unmodifiable(_sources);
  int get readySources => _sources.where((s) => s.analysis != null).length;
  bool get sourcesBusy => _sources.any((s) => s.busy);

  int addSources(Iterable<String> paths) {
    var added = 0;
    for (final path in paths) {
      if (!isMediaFile(path) || _sources.any((s) => s.path == path)) continue;
      final s = SpartaSource(path);
      _sources.add(s);
      added++;
      _analyze(s);
    }
    if (added > 0) {
      _invalidateSamples();
      notifyListeners();
    }
    return added;
  }

  void removeSource(SpartaSource s) {
    _sources.remove(s);
    _invalidateSamples();
    notifyListeners();
  }

  Future<void> _analyze(SpartaSource s) async {
    final eng = _eng;
    final probe = _engine.engine;
    if (eng == null || probe == null) {
      s
        ..busy = false
        ..error = 'Waiting for FFmpeg';
      notifyListeners();
      return;
    }
    s
      ..busy = true
      ..error = null;
    notifyListeners();
    try {
      s.info = await probe.probe(s.path);
      if (!s.info!.hasAudio) throw const FormatException('has no audio track to take samples from');
      s.analysis = await eng.analyzeSource(_sources.indexOf(s), s.path);
    } catch (e) {
      s.error = e is FormatException ? e.message : _short(e);
    } finally {
      s.busy = false;
      if (_sources.contains(s)) {
        _invalidateSamples();
        notifyListeners();
        if (step == SpartaStep.line && !sourcesBusy) _schedule(_findLines);
      }
    }
  }

  void _invalidateSamples() {
    found = null;
    lineIndex = 0;
    line = null;
    picks.clear();
    processed = {};
  }

  // ===========================================================================
  // Line
  // ===========================================================================

  SamplePicks? found;
  List<String> _analyzedPaths = [];
  int lineIndex = 0;

  /// The chosen line, with your word edits.
  SpokenLine? line;

  List<SpokenLine> get lines => found?.lines ?? const [];

  void chooseLine(int i) {
    if (i < 0 || i >= lines.length) return;
    lineIndex = i;
    line = lines[i];
    _rankPitch();
    _lineChanged();
  }

  /// Replaces the chosen line (word edits: split, merge, trim…).
  void editLine(SpokenLine Function(SpokenLine l) change) {
    final l = line;
    if (l == null) return;
    line = change(l);
    _lineChanged();
  }

  void _lineChanged() {
    notifyListeners();
    if (hasResult) _schedule(_resampleAndMix);
  }

  String sourceName(int index) =>
      index >= 0 && index < _analyzedPaths.length ? p.basename(_analyzedPaths[index]) : 'source ${index + 1}';

  /// Loudness (dB, 10 ms frames) of the line's source around it, for drawing.
  List<double> envelope(int sourceIndex, double start, double end) {
    if (sourceIndex >= _analyzedPaths.length) return const [];
    final src = _sources.where((s) => s.path == _analyzedPaths[sourceIndex]).firstOrNull?.analysis;
    if (src == null) return const [];
    final f = src.features;
    final a = f.frameAt(start), b = f.frameAt(end);
    return [for (var i = a; i <= b; i++) f.rmsDb[i]];
  }

  /// Writes a piece of a source to a WAV for listening.
  Future<String?> clipPath(int sourceIndex, double start, double end) async {
    final eng = _eng;
    if (eng == null || sourceIndex >= _analyzedPaths.length) return null;
    final audio = await eng.sourceClip(_analyzedPaths[sourceIndex], start, end);
    final dir = p.join(_engine.cacheDir, 'sparta', 'audition');
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, 'clip_${(start * 1000).round()}_${(end * 1000).round()}.wav');
    await audio.writeWav(path);
    return path;
  }

  Future<void> _findLines(int t) async {
    final eng = _eng;
    if (eng == null) return;
    while (sourcesBusy) {
      _status('Listening to your sources…');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (t != _token) return;
    }
    final ready = _sources.where((s) => s.analysis != null).toList();
    if (ready.isEmpty) return;
    _status('Finding spoken lines, pitch and percussion samples…');
    final analyses = [
      for (var i = 0; i < ready.length; i++)
        SourceAnalysis(i, ready[i].path, ready[i].analysis!.audio, ready[i].analysis!.features),
    ];
    final paths = [for (final s in ready) s.path];
    final f = await eng.findSamples(analyses);
    if (t != _token) return;
    _analyzedPaths = paths;
    found = f;
    lineIndex = 0;
    line = f.lines.isEmpty ? null : f.lines.first;
    picks.clear();
    _rankPitch();
    processed = {};
  }

  /// Pitch / percussion picks, with the chosen line's own vowels first.
  void _rankPitch() {
    final f = found;
    if (f == null) return;
    final chosen = f.assignDistinct(line: line);
    picks.clear();
    for (final role in const [SampleRole.pitch, SampleRole.kick, SampleRole.snare, SampleRole.hat]) {
      final options = role == SampleRole.pitch ? f.pitchFor(line) : [...f.of(role)];
      final best = chosen[role];
      if (best == null && options.isEmpty) continue;
      if (best != null) {
        options.removeWhere((c) => c.sourceIndex == best.sourceIndex && (c.start - best.start).abs() < 1e-6);
        options.insert(0, best);
      }
      picks[role] = RolePick(role, options);
    }
  }

  // ===========================================================================
  // Samples
  // ===========================================================================

  final Map<SampleRole, RolePick> picks = {};
  Map<SampleRole, List<ProcessedSample>> processed = {};

  /// Pitch candidates the tuner couldn't follow (skipped).
  final Set<String> _untunable = {};

  void swap(SampleRole role, int delta) {
    final pick = picks[role];
    if (pick == null || pick.options.length < 2) return;
    final previous = pick.index;
    pick
      ..index = (pick.index + delta) % pick.options.length
      ..nudgeStart = 0
      ..nudgeEnd = 0;
    if (pick.alternate == pick.index) pick.alternate = previous;
    notifyListeners();
    _schedule(_resampleAndMix);
  }

  void choose(SampleRole role, int index) {
    final pick = picks[role];
    if (pick == null || index < 0 || index >= pick.options.length) return;
    final previous = pick.index;
    pick
      ..index = index
      ..nudgeStart = 0
      ..nudgeEnd = 0;
    if (pick.alternate == index) pick.alternate = previous;
    notifyListeners();
    _schedule(_resampleAndMix);
  }

  void nudge(SampleRole role, {double start = 0, double end = 0}) {
    final pick = picks[role];
    if (pick == null) return;
    pick
      ..nudgeStart += start
      ..nudgeEnd += end;
    notifyListeners();
    _schedule(_resampleAndMix);
  }

  void toggleAlternate(SampleRole role) {
    final pick = picks[role];
    if (pick == null) return;
    if (pick.alternate != null) {
      pick.alternate = null;
    } else {
      final primary = pick.options[pick.index];
      var best = -1;
      for (var i = 0; i < pick.options.length; i++) {
        if (i == pick.index) continue;
        if (best < 0 ||
            (pick.options[i].sourceIndex != primary.sourceIndex &&
                pick.options[best].sourceIndex == primary.sourceIndex)) {
          best = i;
        }
      }
      if (best < 0) return;
      pick.alternate = best;
    }
    notifyListeners();
    _schedule(_resampleAndMix);
  }

  /// Writes a processed sample to a WAV for auditioning.
  Future<String?> auditionPath(SampleRole role, {int which = 0}) async {
    final list = processed[role];
    if (list == null || which >= list.length) return null;
    final s = list[which];
    final dir = p.join(_engine.cacheDir, 'sparta', 'audition');
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, '${role.name}_${s.slot}_$which.wav');
    await AudioBuffer(s.audio, sampleRate: ProcessedSample.sampleRate).writeWav(path);
    return path;
  }

  // ===========================================================================
  // Options
  // ===========================================================================

  EnhanceOptions enhance = const EnhanceOptions();
  MixSettings mixSettings = const MixSettings();
  VisualOptions visuals = const VisualOptions();
  bool exportStems = false;
  bool exportMidi = false;

  void setEnhance(EnhanceOptions o) {
    enhance = o;
    _saveOptions();
    notifyListeners();
    if (hasResult) _schedule(_resampleAndMix);
  }

  void setMixSettings(MixSettings m) {
    mixSettings = m;
    notifyListeners();
    if (hasResult) _schedule(_remixOnly);
  }

  void setLaneDb(SampleRole role, double db) =>
      setMixSettings(mixSettings.copyWith(laneDb: {...mixSettings.laneDb, role: db}));

  void setVisuals(VisualOptions v) {
    visuals = v;
    _saveOptions();
    notifyListeners();
  }

  void setExport({bool? stems, bool? midi}) {
    exportStems = stems ?? exportStems;
    exportMidi = midi ?? exportMidi;
    notifyListeners();
  }

  void _loadOptions() {
    final j = _store?.readJson<Map<String, dynamic>>('sparta.options');
    if (j == null) return;
    try {
      final v = j['visuals'];
      if (v is Map) visuals = VisualOptions.fromJson(v.cast<String, Object?>());
      final r = j['random'];
      if (r is Map) random = RandomOptions.fromJson(r.cast<String, Object?>());
      final e = j['enhance'];
      if (e is Map) {
        enhance = EnhanceOptions(
          chorusCrisp: e['chorusCrisp'] as bool? ?? true,
          layerDrums: e['layerDrums'] as bool? ?? false,
          tuning: PitchTuning.values.asNameMap()[e['tuning']] ?? PitchTuning.hard,
          forceOctave: (e['octave'] as num?)?.toInt(),
        );
      }
    } catch (_) {}
  }

  void _saveOptions() => _store?.writeJson('sparta.options', {
    'visuals': visuals.toJson(),
    'random': random.toJson(),
    'enhance': {
      'chorusCrisp': enhance.chorusCrisp,
      'layerDrums': enhance.layerDrums,
      'tuning': enhance.tuning.name,
      'octave': ?enhance.forceOctave,
    },
  });

  // ===========================================================================
  // Results & pipeline
  // ===========================================================================

  SpartaStage stage = SpartaStage.idle;
  String status = '';
  double? progress;
  String? error;
  RemixMix? mix;
  String? previewPath;
  int previewVersion = 0;

  bool get busy => stage == SpartaStage.working;
  bool get hasResult => mix != null && previewPath != null;
  bool get engineReady => _engine.ready;

  /// What still stands between you and a remix (null: ready).
  String? get missing {
    if (!engineReady) return 'FFmpeg is needed — see Settings.';
    if (prepared == null) return baseLoading ? 'Loading the base…' : 'Pick a base first.';
    if (readySources == 0) return sourcesBusy ? 'Listening to your sources…' : 'Add a source.';
    if (found != null && lines.isEmpty) return 'No spoken line was found in your sources.';
    if (found != null && line == null) return 'Choose a line.';
    return null;
  }

  bool get canGenerate => missing == null && !busy;

  String get remixName {
    final src = _sources.isEmpty ? 'Sparta' : p.basenameWithoutExtension(_sources.first.path);
    final base = prepared?.base.name ?? baseSource?.name ?? 'base';
    return '$src - Sparta Remix ($base)';
  }

  /// The remix's chart, written over the transcription.
  List<ChartNote> get chart {
    final t = transcription;
    if (t == null) return const [];
    return Charter().write(t, choices: choices, random: random, pitchInChorus: pitchInChorus);
  }

  void _onEngine() {
    _sparta = null;
    notifyListeners();
    if (_engine.ready) {
      for (final s in _sources) {
        if (s.analysis == null && s.error != null) _analyze(s);
      }
      if (catalog == null) loadCatalog();
      if (baseSource != null && prepared == null && !baseLoading) _schedule(_loadBase, immediate: true);
    }
  }

  SpartaEngine? get _eng {
    if (!_engine.ready) return null;
    return _sparta ??= SpartaEngine(
      ffmpegPath: _engine.toolkit!.ffmpegPath,
      cacheDir: _engine.cacheDir,
      bundledCatalog: _bundled,
    );
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngine);
    _debounce?.cancel();
    super.dispose();
  }

  Timer? _debounce;
  int _token = 0;
  Future<void> _chain = Future.value();

  void _schedule(Future<void> Function(int token) step, {bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      _run(step);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(step));
  }

  /// Makes the remix: samples from your line and sources over the base.
  Future<void> generate() => _run((t) async {
    step = SpartaStep.generate;
    await _full(t);
  });

  Future<void> _run(Future<void> Function(int token) step) {
    final token = ++_token;
    _chain = _chain.then((_) async {
      if (token != _token) return;
      stage = SpartaStage.working;
      error = null;
      progress = null;
      notifyListeners();
      try {
        await step(token);
        if (token == _token) stage = hasResult ? SpartaStage.ready : SpartaStage.idle;
      } catch (e, st) {
        debugPrint('Sparta pipeline failed: $e\n$st');
        if (token == _token) {
          stage = SpartaStage.failed;
          error = _short(e);
        }
      } finally {
        if (token == _token) {
          status = '';
          progress = null;
          notifyListeners();
        }
      }
    });
    return _chain;
  }

  void _status(String s, [double? f]) {
    status = s;
    progress = f;
    notifyListeners();
  }

  Future<void> _full(int t) async {
    if (_eng == null) throw FfmpegException('FFmpeg is not available.');
    if (prepared == null && baseSource != null) await _loadBase(t);
    if (t != _token) return;
    if (prepared == null) throw StateError('Pick a base first.');
    if (found == null) await _findLines(t);
    if (t != _token) return;
    if (line == null) throw StateError('No spoken line was found in your sources — add a source with clear speech.');
    await _resampleAndMix(t);
  }

  final Map<String, ProcessedSample> _sampleCache = {};

  Future<void> _prepareSamples(int t) async {
    final eng = _eng;
    final l = line;
    final base = prepared;
    if (eng == null || l == null || base == null) return;
    final rootPc = base.transcription.rootPitchClass;
    final out = <SampleRole, List<ProcessedSample>>{};

    Future<ProcessedSample?> prepare(SampleCandidate c) async {
      final key =
          '${c.role.name}|${c.slot}|${c.sourceIndex}|${c.start.toStringAsFixed(4)}|${c.end.toStringAsFixed(4)}|'
          '${enhance.key}|$rootPc|${_analyzedPaths.join(',')}';
      final cached = _sampleCache[key];
      if (cached != null) return cached;
      try {
        final s = await eng.prepareSample(c, _analyzedPaths[c.sourceIndex], options: enhance, rootPc: rootPc);
        _sampleCache[key] = s;
        return s;
      } on UntunableSample {
        _untunable.add('${c.sourceIndex}|${c.start}');
        return null;
      }
    }

    // Words and the quote, from the line.
    _status('Cutting the words of your line…', 0);
    final words = <ProcessedSample>[];
    for (final c in l.wordCandidates) {
      final s = await prepare(c);
      if (t != _token) return;
      if (s != null) words.add(s);
    }
    out[SampleRole.word] = words;
    final quote = await prepare(l.quote);
    if (t != _token) return;
    if (quote != null) out[SampleRole.quote] = [quote];

    // Pitch (tuned to the base's root; untunable picks are skipped) and drums.
    final roles = picks.keys.toList();
    for (var i = 0; i < roles.length; i++) {
      final pick = picks[roles[i]]!;
      _status(
        pick.role == SampleRole.pitch
            ? 'Tuning the pitch sample to ${base.transcription.rootName}…'
            : 'Cleaning up the ${pick.role.label.toLowerCase()} sample…',
        (i + 1) / (roles.length + 1),
      );
      final list = <ProcessedSample>[];
      var s = await prepare(pick.current);
      if (t != _token) return;
      // A pitch pick that can't be tuned: move on to the next candidate.
      var tries = 0;
      while (s == null && pick.role == SampleRole.pitch && tries < pick.options.length - 1) {
        tries++;
        pick
          ..index = (pick.index + 1) % pick.options.length
          ..nudgeStart = 0
          ..nudgeEnd = 0;
        s = await prepare(pick.current);
        if (t != _token) return;
      }
      if (s != null) list.add(s);
      final alt = pick.alternateCandidate;
      if (alt != null) {
        final a = await prepare(alt);
        if (t != _token) return;
        if (a != null) list.add(a);
      }
      if (list.isNotEmpty) out[pick.role] = list;
    }
    processed = out;
  }

  Future<void> _resampleAndMix(int t) async {
    if (line == null) return;
    await _prepareSamples(t);
    if (t != _token) return;
    await _remixOnly(t);
  }

  Future<void> _remixOnly(int t) async {
    final eng = _eng;
    final base = prepared;
    if (eng == null || base == null || processed.isEmpty) return;
    _status('Writing the chart, mixing and mastering…');
    final charted = base.withChart(chart);
    final m = await eng.mix(
      charted,
      processed,
      mixSettings,
      shuffleSamples: random.enabled && random.samples,
      seed: random.seed,
    );
    if (t != _token) return;
    _status('Writing preview…');
    final dir = p.join(_engine.cacheDir, 'sparta');
    await Directory(dir).create(recursive: true);
    // Alternate between two files so a playing preview is never overwritten.
    final path = p.join(dir, 'preview_${previewVersion % 2}.wav');
    await m.master.writeWav(path);
    if (t != _token) return;
    prepared = charted;
    mix = m;
    previewPath = path;
    previewVersion++;
  }

  // ===========================================================================
  // Render
  // ===========================================================================

  /// A queue job rendering the current remix (video or audio, per [output]).
  RenderJob renderJob({required String outDir, required OutputSettings output, bool stems = false, bool midi = false}) {
    final eng = _eng!;
    final base = prepared!;
    final m = mix!;
    final samples = processed;
    final hasVideo = {for (final s in _sources) s.path: s.hasVideo};
    final name = RenderEngine.slug(remixName).isEmpty ? 'Sparta Remix' : remixName;
    final look = visuals;
    final font = _engine.fontPath;
    final title = '${p.basenameWithoutExtension(_sources.isEmpty ? 'Sparta' : _sources.first.path)}\nSparta Remix';
    return RenderJob(
      title: 'Sparta Remix · ${look.style.label}',
      subtitle: name,
      isCompilation: true,
      task: (job, cancel) async {
        final out = await eng.export(
          base: base,
          mix: m,
          samples: samples,
          sourceHasVideo: hasVideo,
          outDir: outDir,
          name: name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_'),
          stems: stems,
          midi: midi,
          visuals: look,
          title: title,
          fontPath: font,
          output: output,
          onProgress: job.report,
          cancel: cancel,
        );
        return RenderOutcome(out.output);
      },
    );
  }

  /// Uses [base] as the prepared base, as loading [source] would (tests).
  @visibleForTesting
  void debugUseBase(PreparedBase base, {BaseSource? source}) {
    baseSource = source;
    _fixed = null;
    choices = {};
    if (source != null) _loadFixes(source.key);
    prepared = _fixed == null ? base : base.withTranscription(_fixed!);
    notifyListeners();
  }

  /// Uses [l] as the chosen line (tests).
  @visibleForTesting
  void debugUseLine(SpokenLine l, {List<String> paths = const []}) {
    _analyzedPaths = paths;
    found = SamplePicks(const {}, lines: [l]);
    lineIndex = 0;
    line = l;
    notifyListeners();
  }

  static String _short(Object e) {
    final s = e.toString().replaceFirst(RegExp(r'^(Exception|StateError|Bad state|FormatException): ?'), '');
    return s.length > 240 ? '${s.substring(0, 240)}…' : s;
  }
}
