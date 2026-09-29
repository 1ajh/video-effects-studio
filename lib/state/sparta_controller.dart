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
import '../core/sparta/chart_import.dart';
import '../core/sparta/composer.dart';
import '../core/sparta/model.dart';
import '../core/sparta/sample_finder.dart';
import '../core/sparta/sample_processing.dart';
import '../core/sparta/sparta_engine.dart';
import '../core/sparta/visual_renderer.dart';
import 'engine_controller.dart';
import 'project_controller.dart';
import 'render_queue.dart';

enum BaseMode {
  builtIn('Built-in', 'Procedurally composed Sparta bases'),
  project('FL / MIDI project', 'FL Studio .flp, FL Studio Mobile .flm or MIDI, with or without its audio'),
  audio('Audio file', 'Any base as MP3/WAV: tempo, bars and chords are detected');

  const BaseMode(this.label, this.blurb);
  final String label;
  final String blurb;
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

  /// Second sample alternating with the first (multiple sources).
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
  SpartaController(this._engine) {
    _engine.addListener(_onEngine);
  }

  final EngineController _engine;
  SpartaEngine? _sparta;

  // --- sources -----------------------------------------------------------------
  final List<SpartaSource> _sources = [];
  List<SpartaSource> get sources => List.unmodifiable(_sources);

  // --- base --------------------------------------------------------------------
  BaseMode baseMode = BaseMode.builtIn;
  BaseStyle style = BaseStyle.classic;
  RemixLength length = RemixLength.standard;
  final Set<SectionKind> sections = {
    SectionKind.intro,
    SectionKind.chorus,
    SectionKind.dundundenden,
    SectionKind.epicness,
    SectionKind.madness,
    SectionKind.awesomeness,
    SectionKind.outro,
  };
  int seed = 1;
  final Map<SectionKind, int> sectionSeeds = {};

  String? projectPath;
  String? projectAudioPath;
  ChartSource? chart;
  String? chartError;
  Map<String, SampleRole?> mapping = {};
  int transpose = 0;
  double? manualOffset;

  String? audioBasePath;
  double? bpmHint;

  // --- options -----------------------------------------------------------------
  EnhanceOptions enhance = const EnhanceOptions();
  MixSettings mixSettings = const MixSettings();
  VisualPreset preset = VisualPreset.classic;
  bool exportStems = false;
  bool exportMidi = false;

  void setExport({bool? stems, bool? midi}) {
    exportStems = stems ?? exportStems;
    exportMidi = midi ?? exportMidi;
    notifyListeners();
  }

  // --- results -----------------------------------------------------------------
  SpartaStage stage = SpartaStage.idle;
  String status = '';
  double? progress;
  String? error;
  final Map<SampleRole, RolePick> picks = {};
  Map<SampleRole, List<ProcessedSample>> processed = {};
  PreparedBase? prepared;
  RemixMix? mix;
  String? previewPath;

  /// Bumped whenever a new preview file is written.
  int previewVersion = 0;

  bool get busy => stage == SpartaStage.working;
  bool get hasResult => mix != null && previewPath != null;
  bool get engineReady => _engine.ready;
  int get readySources => _sources.where((s) => s.analysis != null).length;

  bool get baseReady => switch (baseMode) {
    BaseMode.builtIn => sections.isNotEmpty,
    BaseMode.project => chart != null,
    BaseMode.audio => audioBasePath != null,
  };

  bool get canGenerate => engineReady && readySources > 0 && baseReady && !busy;

  String get remixName {
    final src = _sources.isEmpty ? 'Sparta' : p.basenameWithoutExtension(_sources.first.path);
    final baseName = switch (baseMode) {
      BaseMode.builtIn => style.label.replaceFirst('Sparta ', ''),
      BaseMode.project => chart?.name ?? 'base',
      BaseMode.audio => p.basenameWithoutExtension(audioBasePath ?? 'base'),
    };
    return '$src - Sparta Remix ($baseName)';
  }

  void _onEngine() {
    _sparta = null;
    notifyListeners();
    if (_engine.ready) {
      for (final s in _sources) {
        if (s.analysis == null && s.error != null) _analyze(s);
      }
    }
  }

  SpartaEngine? get _eng {
    if (!_engine.ready) return null;
    return _sparta ??= SpartaEngine(ffmpegPath: _engine.toolkit!.ffmpegPath, cacheDir: _engine.cacheDir);
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngine);
    _debounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sources
  // ---------------------------------------------------------------------------

  /// Adds media files as sources. Returns how many were added.
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
      _invalidatePicks();
      notifyListeners();
    }
    return added;
  }

  void removeSource(SpartaSource s) {
    _sources.remove(s);
    _invalidatePicks();
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
      final index = _sources.indexOf(s);
      s.analysis = await eng.analyzeSource(index, s.path);
    } catch (e) {
      s.error = e is FormatException ? e.message : _short(e);
    } finally {
      s.busy = false;
      if (_sources.contains(s)) {
        _invalidatePicks();
        notifyListeners();
      }
    }
  }

  void _invalidatePicks() {
    picks.clear();
    processed = {};
  }

  // ---------------------------------------------------------------------------
  // Base settings
  // ---------------------------------------------------------------------------

  void setBaseMode(BaseMode m) {
    if (baseMode == m) return;
    baseMode = m;
    _baseChanged();
  }

  void setStyle(BaseStyle s) {
    style = s;
    _baseChanged();
  }

  void setLength(RemixLength l) {
    length = l;
    _baseChanged();
  }

  void toggleSection(SectionKind k) {
    if (sections.contains(k)) {
      if (sections.length == 1) return;
      sections.remove(k);
    } else {
      sections.add(k);
    }
    _baseChanged();
  }

  void rerollSection(SectionKind k) {
    sectionSeeds[k] = (sectionSeeds[k] ?? 0) + 1;
    _baseChanged();
  }

  void newVariation() {
    seed++;
    sectionSeeds.clear();
    _baseChanged();
  }

  /// Loads an FL Studio / FL Studio Mobile / MIDI project as the base.
  Future<void> setProject(String path) async {
    projectPath = path;
    chart = null;
    chartError = null;
    mapping = {};
    manualOffset = null;
    baseMode = BaseMode.project;
    notifyListeners();
    try {
      final c = await Future(() => SpartaEngine.readProject(path));
      chart = c;
      mapping = c.guessMapping();
    } catch (e) {
      chartError = _short(e);
    }
    _baseChanged();
  }

  void setProjectAudio(String? path) {
    projectAudioPath = path;
    manualOffset = null;
    _baseChanged();
  }

  void setMapping(String trackId, SampleRole? role) {
    mapping = {...mapping, trackId: role};
    _baseChanged();
  }

  void setTranspose(int t) {
    transpose = t.clamp(-12, 12);
    _baseChanged();
  }

  void setManualOffset(double? seconds) {
    manualOffset = seconds;
    _baseChanged();
  }

  void setAudioBase(String path) {
    audioBasePath = path;
    baseMode = BaseMode.audio;
    _baseChanged();
  }

  void setBpmHint(double? bpm) {
    bpmHint = bpm;
    _baseChanged();
  }

  void _baseChanged() {
    notifyListeners();
    if (hasResult || prepared != null) _schedule(_rebuildBase);
  }

  // ---------------------------------------------------------------------------
  // Sound & look
  // ---------------------------------------------------------------------------

  void setEnhance(EnhanceOptions o) {
    enhance = o;
    processed = {};
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

  void setPreset(VisualPreset v) {
    preset = v;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Sample review
  // ---------------------------------------------------------------------------

  void swap(SampleRole role, int delta) {
    final pick = picks[role];
    if (pick == null || pick.options.length < 2) return;
    final previous = pick.index;
    pick
      ..index = (pick.index + delta) % pick.options.length
      ..nudgeStart = 0
      ..nudgeEnd = 0;
    // Landing on the second sample swaps the two.
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

  /// Turns alternation with a second sample (from another source when
  /// possible) on or off.
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

  /// Writes a role's processed sample to a WAV for auditioning.
  Future<String?> auditionPath(SampleRole role, {int which = 0}) async {
    final list = processed[role];
    if (list == null || which >= list.length) return null;
    final s = list[which];
    final dir = p.join(_engine.cacheDir, 'sparta', 'audition');
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, '${role.name}_$which.wav');
    await AudioBuffer(s.audio, sampleRate: ProcessedSample.sampleRate).writeWav(path);
    return path;
  }

  String sourceName(int index) =>
      index >= 0 && index < _analyzedPaths.length ? p.basename(_analyzedPaths[index]) : 'source ${index + 1}';

  // ---------------------------------------------------------------------------
  // Pipeline
  // ---------------------------------------------------------------------------

  Timer? _debounce;
  int _token = 0;
  Future<void> _chain = Future.value();
  List<String> _analyzedPaths = [];

  void _schedule(Future<void> Function(int token) step) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(step));
  }

  /// One-click: pick samples, prepare everything, mix a preview.
  Future<void> generate() => _run((t) async {
    picks.clear();
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
    final eng = _eng;
    if (eng == null) throw FfmpegException('FFmpeg is not available.');
    // Wait for any source still being analysed.
    while (_sources.any((s) => s.busy)) {
      _status('Listening to your sources…');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (t != _token) return;
    }
    if (picks.isEmpty) await _findPicks(eng, t);
    if (t != _token) return;
    await _prepareSamples(eng, t);
    if (t != _token) return;
    await _rebuildBase(t, remix: false);
    if (t != _token) return;
    await _remixOnly(t);
  }

  Future<void> _findPicks(SpartaEngine eng, int t) async {
    final ready = _sources.where((s) => s.analysis != null).toList();
    if (ready.isEmpty) throw StateError('Add at least one source with audio.');
    _status('Finding pitch, chop, drum and quote samples…');
    final analyses = [
      for (var i = 0; i < ready.length; i++)
        SourceAnalysis(i, ready[i].path, ready[i].analysis!.audio, ready[i].analysis!.features),
    ];
    _analyzedPaths = [for (final s in ready) s.path];
    final found = await eng.findSamples(analyses);
    if (t != _token) return;
    final chosen = found.assignDistinct();
    picks.clear();
    for (final role in SampleRole.values) {
      final options = [...found.of(role)];
      final best = chosen[role];
      if (best == null && options.isEmpty) continue;
      if (best != null) {
        options.removeWhere((c) => c.sourceIndex == best.sourceIndex && (c.start - best.start).abs() < 1e-6);
        options.insert(0, best);
      }
      picks[role] = RolePick(role, options);
    }
    // With several sources, pitch and chop alternate between two voices.
    if (ready.length > 1) {
      for (final role in const [SampleRole.pitch, SampleRole.chop]) {
        final pick = picks[role];
        if (pick == null) continue;
        final other = pick.options.indexWhere((c) => c.sourceIndex != pick.options[pick.index].sourceIndex);
        if (other > 0) pick.alternate = other;
      }
    }
    processed = {};
  }

  final Map<String, ProcessedSample> _sampleCache = {};

  Future<void> _prepareSamples(SpartaEngine eng, int t) async {
    final out = <SampleRole, List<ProcessedSample>>{};
    final roles = picks.keys.toList();
    for (var i = 0; i < roles.length; i++) {
      final pick = picks[roles[i]]!;
      _status('Tuning and enhancing ${pick.role.label.toLowerCase()} sample…', i / roles.length);
      final list = <ProcessedSample>[];
      for (final c in [pick.current, ?pick.alternateCandidate]) {
        final key =
            '${c.role.name}|${c.sourceIndex}|${c.start.toStringAsFixed(4)}|${c.end.toStringAsFixed(4)}|'
            '${enhance.chorusCrisp}|${enhance.layerDrums}|${enhance.forceOctave}|${_analyzedPaths.join(',')}';
        final cached = _sampleCache[key];
        if (cached != null) {
          list.add(cached);
          continue;
        }
        final s = await eng.prepareSample(c, _analyzedPaths[c.sourceIndex], options: enhance);
        if (t != _token) return;
        _sampleCache[key] = s;
        list.add(s);
      }
      out[pick.role] = list;
    }
    processed = out;
  }

  Future<void> _resampleAndMix(int t) async {
    final eng = _eng;
    if (eng == null || picks.isEmpty) return;
    await _prepareSamples(eng, t);
    if (t != _token) return;
    if (prepared == null) await _rebuildBase(t, remix: false);
    if (t != _token) return;
    await _remixOnly(t);
  }

  Future<void> _rebuildBase(int t, {bool remix = true}) async {
    final eng = _eng;
    if (eng == null || !baseReady) return;
    _status(switch (baseMode) {
      BaseMode.builtIn => 'Composing the ${style.label} base…',
      BaseMode.project => 'Reading the project and lining it up…',
      BaseMode.audio => 'Detecting tempo, bars and chords…',
    });
    final source = switch (baseMode) {
      BaseMode.builtIn => BuiltInBaseSource(
        style: style,
        length: length,
        sections: {...sections},
        seed: seed,
        sectionSeeds: {...sectionSeeds},
      ),
      BaseMode.project => ProjectBaseSource(
        projectPath: projectPath!,
        audioPath: projectAudioPath,
        mapping: mapping,
        transpose: transpose,
        audioOffset: manualOffset,
        style: style,
        seed: seed,
      ),
      BaseMode.audio => AudioBaseSource(
        audioPath: audioBasePath!,
        bpmHint: bpmHint,
        transpose: transpose,
        style: style,
        seed: seed,
      ),
    };
    final base = await eng.prepareBase(source);
    if (t != _token) return;
    prepared = base;
    if (remix && processed.isNotEmpty) await _remixOnly(t);
  }

  Future<void> _remixOnly(int t) async {
    final eng = _eng;
    final base = prepared;
    if (eng == null || base == null || processed.isEmpty) return;
    _status('Mixing and mastering…');
    final m = await eng.mix(base, processed, mixSettings);
    if (t != _token) return;
    _status('Writing preview…');
    final dir = p.join(_engine.cacheDir, 'sparta');
    await Directory(dir).create(recursive: true);
    // Alternate between two files so a playing preview is never overwritten.
    final path = p.join(dir, 'preview_${previewVersion % 2}.wav');
    await m.master.writeWav(path);
    if (t != _token) return;
    mix = m;
    previewPath = path;
    previewVersion++;
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  /// A queue job rendering the current remix (video or audio, per [output]).
  RenderJob renderJob({required String outDir, required OutputSettings output, bool stems = false, bool midi = false}) {
    final eng = _eng!;
    final base = prepared!;
    final m = mix!;
    final samples = processed;
    final hasVideo = {for (final s in _sources) s.path: s.hasVideo};
    final name = RenderEngine.slug(remixName).isEmpty ? 'Sparta Remix' : remixName;
    final look = preset;
    return RenderJob(
      title: 'Sparta Remix · ${look.label}',
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
          preset: look,
          output: output,
          onProgress: job.report,
          cancel: cancel,
        );
        return RenderOutcome(out.output);
      },
    );
  }

  static String _short(Object e) {
    final s = e.toString().replaceFirst(RegExp(r'^(Exception|StateError|Bad state|FormatException): ?'), '');
    return s.length > 240 ? '${s.substring(0, 240)}…' : s;
  }
}
