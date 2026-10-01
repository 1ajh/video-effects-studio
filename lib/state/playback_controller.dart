import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'preview_controller.dart';
import 'project_controller.dart';

/// Owns the two in-app players (original + effect preview) and keeps them in
/// step with the project, trim range and preview.
class PlaybackController extends ChangeNotifier {
  PlaybackController({required bool available, required this.project, required this.preview}) {
    if (available) {
      try {
        _original = Player(configuration: const PlayerConfiguration(title: 'Original'));
        _effect = Player(configuration: const PlayerConfiguration(title: 'Effect'));
        originalVideo = VideoController(_original!);
        effectVideo = VideoController(_effect!);
        _available = true;
      } catch (e) {
        _unavailableReason = '$e';
        _original = null;
        _effect = null;
      }
    }
    if (_available) {
      _subs.add(_original!.stream.position.listen(_onOriginalPosition));
      _subs.add(
        _effect!.stream.position.listen((p) {
          if (_primaryIsEffect) _setPosition(p);
        }),
      );
      _subs.add(_original!.stream.playing.listen((_) => _syncPlaying()));
      _subs.add(_effect!.stream.playing.listen((_) => _syncPlaying()));
      _original!.setVolume(_volume);
      _effect!.setVolume(_volume);
    }
    project.addListener(_onProject);
    preview.addListener(_onPreview);
  }

  final ProjectController project;
  final PreviewController preview;

  Player? _original;
  Player? _effect;
  VideoController? originalVideo;
  VideoController? effectVideo;
  bool _available = false;
  String? _unavailableReason;
  final List<StreamSubscription> _subs = [];

  String? _originalPath;
  String? _effectPath;
  ViewMode _mode = ViewMode.original;
  bool _playing = false;
  Duration _position = Duration.zero;
  double _volume = 80;

  bool get available => _available;
  String? get unavailableReason => _unavailableReason;
  bool get playing => _playing;
  double get volume => _volume;

  /// Position of the visible player in seconds (absolute time in the source
  /// for the original player, relative for the preview).
  double get positionSeconds => _position.inMicroseconds / 1e6;

  bool get _primaryIsEffect => _mode != ViewMode.original && _effectPath != null;

  /// Playhead in source time (for the trim bar).
  double get sourcePosition {
    final clip = project.active;
    if (clip == null) return 0;
    return _primaryIsEffect ? clip.trimStart + positionSeconds : positionSeconds;
  }

  void _setPosition(Duration p) {
    _position = p;
    notifyListeners();
  }

  void _onOriginalPosition(Duration p) {
    final clip = project.active;
    if (clip != null && clip.info != null) {
      final end = clip.effectiveEnd;
      final secs = p.inMicroseconds / 1e6;
      // Loop inside the trim range.
      if (end > 0 && (secs >= end - 0.02 || secs < clip.trimStart - 0.25) && _playing && !_primaryIsEffect) {
        _original?.seek(Duration(microseconds: (clip.trimStart * 1e6).round()));
      }
    }
    if (!_primaryIsEffect) _setPosition(p);
  }

  void _syncPlaying() {
    final playing = (_original?.state.playing ?? false) || (_effect?.state.playing ?? false);
    if (playing != _playing) {
      _playing = playing;
      notifyListeners();
    }
  }

  Future<void> _onProject() async {
    if (!_available) return;
    final clip = project.active;
    final path = clip?.info?.hasVideo == true || clip?.info?.hasAudio == true ? clip!.path : null;
    if (path != _originalPath) {
      _originalPath = path;
      if (path == null) {
        await _original!.stop();
      } else {
        await _original!.open(Media(path), play: false);
        await _original!.setPlaylistMode(PlaylistMode.single);
        await _seekOriginalToTrim();
      }
      notifyListeners();
    } else if (clip != null && !_primaryIsEffect) {
      // Trim changed: keep the playhead inside the range.
      final pos = positionSeconds;
      if (pos < clip.trimStart || pos > clip.effectiveEnd) await _seekOriginalToTrim();
    }
  }

  Future<void> _seekOriginalToTrim() async {
    final clip = project.active;
    if (clip == null) return;
    await _original?.seek(Duration(microseconds: (clip.trimStart * 1e6).round()));
  }

  Future<void> _onPreview() async {
    if (_mode != preview.viewMode) await _applyMode(preview.viewMode);
    if (!_available) return;
    final path = preview.path;
    if (path != _effectPath && path != null) {
      _effectPath = path;
      final wasPlaying = _playing;
      await _effect!.open(Media(path), play: false);
      await _effect!.setPlaylistMode(PlaylistMode.single);
      if (_mode == ViewMode.split) {
        await _seekOriginalToTrim();
        await _effect!.seek(Duration.zero);
      }
      if (wasPlaying || _mode != ViewMode.original) await play();
      notifyListeners();
    }
  }

  Future<void> _applyMode(ViewMode m) async {
    final previous = _mode;
    _mode = m;
    if (!_available) {
      notifyListeners();
      return;
    }
    // Audio follows what you are looking at; split plays the effect's audio.
    await _original!.setVolume(m == ViewMode.original ? _volume : 0);
    await _effect!.setVolume(m == ViewMode.original ? 0 : _volume);
    if (m == ViewMode.original) {
      await _effect!.pause();
    } else if (m == ViewMode.effect) {
      await _original!.pause();
    }
    if (m == ViewMode.split && previous != ViewMode.split) {
      await _seekOriginalToTrim();
      await _effect!.seek(Duration.zero);
      if (_playing) {
        await _original!.play();
        await _effect!.play();
      }
    }
    _position = (_primaryIsEffect ? _effect! : _original!).state.position;
    notifyListeners();
  }

  List<Player> get _activePlayers {
    if (!_available) return const [];
    return switch (_mode) {
      ViewMode.original => [_original!],
      ViewMode.effect => [if (_effectPath != null) _effect! else _original!],
      ViewMode.split => [_original!, if (_effectPath != null) _effect!],
    };
  }

  Future<void> play() async {
    for (final p in _activePlayers) {
      await p.play();
    }
  }

  Future<void> pause() async {
    for (final p in [?_original, ?_effect]) {
      await p.pause();
    }
  }

  Future<void> togglePlay() => _playing ? pause() : play();

  /// Back to the start of the trim range / preview.
  Future<void> restart() async {
    if (!_available) return;
    await _seekOriginalToTrim();
    await _effect!.seek(Duration.zero);
  }

  /// Seek in source seconds (original) — used by the trim bar.
  Future<void> seekSource(double seconds) async {
    if (!_available) return;
    final clip = project.active;
    if (clip == null) return;
    if (_primaryIsEffect) {
      final rel = (seconds - clip.trimStart).clamp(0, double.infinity);
      await _effect!.seek(Duration(microseconds: (rel * 1e6).round()));
      if (_mode == ViewMode.split) await _original!.seek(Duration(microseconds: (seconds * 1e6).round()));
    } else {
      await _original!.seek(Duration(microseconds: (seconds * 1e6).round()));
    }
  }

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0, 100);
    if (_available) {
      await _original!.setVolume(_mode == ViewMode.original ? _volume : 0);
      await _effect!.setVolume(_mode == ViewMode.original ? 0 : _volume);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    project.removeListener(_onProject);
    preview.removeListener(_onPreview);
    for (final s in _subs) {
      s.cancel();
    }
    _original?.dispose();
    _effect?.dispose();
    super.dispose();
  }
}
