import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Audio player for the remix preview and sample auditions.
class SpartaPlayback extends ChangeNotifier {
  SpartaPlayback({required bool available}) {
    if (!available) return;
    try {
      _player = Player(configuration: const PlayerConfiguration(title: 'Sparta preview'));
      _subs
        ..add(
          _player!.stream.position.listen((d) {
            _position = d;
            notifyListeners();
          }),
        )
        ..add(
          _player!.stream.duration.listen((d) {
            _duration = d;
            notifyListeners();
          }),
        )
        ..add(
          _player!.stream.playing.listen((v) {
            _playing = v;
            notifyListeners();
          }),
        )
        ..add(
          _player!.stream.completed.listen((done) {
            if (done && _auditioning != null) {
              _auditioning = null;
              notifyListeners();
            }
          }),
        );
    } catch (_) {
      _player = null;
    }
  }

  Player? _player;
  final List<StreamSubscription> _subs = [];
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  String? _loaded;
  String? _auditioning;
  int _loadedVersion = -1;

  bool get available => _player != null;
  bool get playing => _playing;
  double get position => _position.inMicroseconds / 1e6;
  double get duration => _duration.inMicroseconds / 1e6;

  /// Which audition clip is playing (null while the remix preview is loaded).
  String? get auditioning => _auditioning;

  /// Loads the remix preview [path] (version-tagged so a rewritten file
  /// reloads), keeping the playhead when the remix is updated.
  Future<void> loadPreview(String path, int version, {bool play = false}) async {
    final player = _player;
    if (player == null) return;
    if (_loaded == path && _loadedVersion == version && _auditioning == null) {
      if (play) await player.play();
      return;
    }
    final keep = _auditioning == null && _loaded != null ? _position : Duration.zero;
    final wasPlaying = _playing && _auditioning == null;
    _auditioning = null;
    _loaded = path;
    _loadedVersion = version;
    try {
      await player.open(Media(path), play: false);
      if (keep > Duration.zero) await player.seek(keep);
      if (play || wasPlaying) await player.play();
    } catch (e) {
      // A preview replaced while it was opening: the next one loads anyway.
      debugPrint('Preview load failed: $e');
      _loaded = null;
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    final player = _player;
    if (player == null) return;
    await player.playOrPause();
  }

  Future<void> seek(double seconds) async {
    await _player?.seek(Duration(microseconds: (seconds * 1e6).round()));
  }

  /// Plays a single sample; the preview reloads on the next play.
  Future<void> audition(String path, String id) async {
    final player = _player;
    if (player == null) return;
    _auditioning = id;
    _loaded = null;
    notifyListeners();
    try {
      await player.open(Media(path), play: true);
    } catch (e) {
      debugPrint('Audition failed: $e');
      _auditioning = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _player?.pause();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }
}
