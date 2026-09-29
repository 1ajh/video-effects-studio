enum OutputFormat {
  mp4('MP4', 'mp4', 'H.264 + AAC — plays everywhere (Discord, YouTube, phones)'),
  webm('WebM', 'webm', 'VP9 + Opus — small, web friendly'),
  gif('GIF', 'gif', 'Animated GIF, no sound'),
  mp3('MP3', 'mp3', 'Audio only'),
  wav('WAV', 'wav', 'Uncompressed audio only');

  const OutputFormat(this.label, this.extension, this.blurb);
  final String label;
  final String extension;
  final String blurb;

  bool get hasVideo => this == mp4 || this == webm || this == gif;
  bool get hasAudio => this != gif;
}

enum OutputQuality {
  high('High', 18, 'medium', 256),
  balanced('Balanced', 23, 'fast', 192),
  small('Small file', 28, 'medium', 128);

  const OutputQuality(this.label, this.crf, this.preset, this.audioKbps);
  final String label;
  final int crf;
  final String preset;
  final int audioKbps;
}

enum ResolutionCap {
  original('Original', null),
  p1080('1080p', 1080),
  p720('720p', 720),
  p480('480p', 480),
  p360('360p', 360);

  const ResolutionCap(this.label, this.maxHeight);
  final String label;
  final int? maxHeight;
}

class OutputSettings {
  const OutputSettings({
    this.format = OutputFormat.mp4,
    this.quality = OutputQuality.high,
    this.resolution = ResolutionCap.original,
    this.gifFps = 15,
  });

  final OutputFormat format;
  final OutputQuality quality;
  final ResolutionCap resolution;
  final int gifFps;

  OutputSettings copyWith({OutputFormat? format, OutputQuality? quality, ResolutionCap? resolution, int? gifFps}) =>
      OutputSettings(
        format: format ?? this.format,
        quality: quality ?? this.quality,
        resolution: resolution ?? this.resolution,
        gifFps: gifFps ?? this.gifFps,
      );

  Map<String, Object?> toJson() => {
    'format': format.name,
    'quality': quality.name,
    'resolution': resolution.name,
    'gifFps': gifFps,
  };

  factory OutputSettings.fromJson(Map<String, Object?>? json) {
    if (json == null) return const OutputSettings();
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    return OutputSettings(
      format: pick(OutputFormat.values, json['format'], OutputFormat.mp4),
      quality: pick(OutputQuality.values, json['quality'], OutputQuality.high),
      resolution: pick(ResolutionCap.values, json['resolution'], ResolutionCap.original),
      gifFps: (json['gifFps'] as num?)?.toInt().clamp(5, 30) ?? 15,
    );
  }
}
