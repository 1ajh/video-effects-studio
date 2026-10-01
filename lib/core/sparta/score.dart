/// Instrument parts for re-synthesizing a base project that came without
/// its audio.
library;

/// Voices of the base re-synthesizer.
enum Instrument { kick, snare, clap, hat, openHat, crash, tom, riser, bass, stab, pad }

/// One note for the base re-synthesizer.
class ScoreEvent {
  const ScoreEvent(this.instrument, this.beat, this.length, {this.midi = const [], this.velocity = 1});
  final Instrument instrument;
  final double beat;
  final double length;
  final List<double> midi;
  final double velocity;
}

/// A project's own parts, ready to render.
class Score {
  Score(this.events, {required this.bpm, required this.lengthBeats, this.seed = 1});
  final List<ScoreEvent> events;
  final double bpm;
  final double lengthBeats;
  final int seed;

  double get durationSeconds => lengthBeats * 60 / bpm;
}
