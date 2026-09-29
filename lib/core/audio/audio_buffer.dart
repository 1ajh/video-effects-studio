import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Mono or stereo float audio (interleaved when stereo), -1..1 nominal.
class AudioBuffer {
  AudioBuffer(this.data, {required this.sampleRate, this.channels = 1})
    : assert(channels == 1 || channels == 2),
      assert(data.length % channels == 0);

  AudioBuffer.silence(double seconds, {required this.sampleRate, this.channels = 1})
    : data = Float32List((seconds * sampleRate).round() * channels);

  final Float32List data;
  final int sampleRate;
  final int channels;

  int get frames => data.length ~/ channels;
  double get duration => frames / sampleRate;
  bool get isEmpty => frames == 0;

  /// Mono mixdown (a copy when stereo, the same buffer when already mono).
  AudioBuffer mono() {
    if (channels == 1) return this;
    final out = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      out[i] = (data[2 * i] + data[2 * i + 1]) * 0.5;
    }
    return AudioBuffer(out, sampleRate: sampleRate);
  }

  /// Stereo copy (duplicates mono).
  AudioBuffer stereo() {
    if (channels == 2) return this;
    final out = Float32List(frames * 2);
    for (var i = 0; i < frames; i++) {
      out[2 * i] = data[i];
      out[2 * i + 1] = data[i];
    }
    return AudioBuffer(out, sampleRate: sampleRate, channels: 2);
  }

  /// Sub-range in seconds (copied).
  AudioBuffer slice(double start, double end) {
    final a = (start * sampleRate).round().clamp(0, frames);
    final b = (end * sampleRate).round().clamp(a, frames);
    return AudioBuffer(
      Float32List.fromList(data.sublist(a * channels, b * channels)),
      sampleRate: sampleRate,
      channels: channels,
    );
  }

  double peak() {
    var p = 0.0;
    for (final v in data) {
      final a = v.abs();
      if (a > p) p = a;
    }
    return p;
  }

  double rms() {
    if (data.isEmpty) return 0;
    var s = 0.0;
    for (final v in data) {
      s += v * v;
    }
    return math.sqrt(s / data.length);
  }

  AudioBuffer copy() => AudioBuffer(Float32List.fromList(data), sampleRate: sampleRate, channels: channels);

  /// In-place gain.
  void scale(double gain) {
    for (var i = 0; i < data.length; i++) {
      data[i] *= gain;
    }
  }

  /// Scales so the peak hits [target] (no-op for silence).
  void normalize([double target = 0.95]) {
    final p = peak();
    if (p > 1e-9) scale(target / p);
  }

  // ---------------------------------------------------------------------------
  // WAV I/O
  // ---------------------------------------------------------------------------

  /// 16-bit PCM or 32-bit float WAV bytes.
  Uint8List toWav({bool float32 = false}) {
    final bytesPerSample = float32 ? 4 : 2;
    final dataBytes = data.length * bytesPerSample;
    final b = BytesBuilder(copy: false);
    final header = ByteData(44);
    void str(int off, String s) {
      for (var i = 0; i < 4; i++) {
        header.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    header.setUint32(4, 36 + dataBytes, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, float32 ? 3 : 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
    header.setUint16(32, channels * bytesPerSample, Endian.little);
    header.setUint16(34, bytesPerSample * 8, Endian.little);
    str(36, 'data');
    header.setUint32(40, dataBytes, Endian.little);
    b.add(header.buffer.asUint8List());
    final body = ByteData(dataBytes);
    for (var i = 0; i < data.length; i++) {
      if (float32) {
        body.setFloat32(i * 4, data[i], Endian.little);
      } else {
        final v = (data[i].clamp(-1.0, 1.0) * 32767).round();
        body.setInt16(i * 2, v, Endian.little);
      }
    }
    b.add(body.buffer.asUint8List());
    return b.takeBytes();
  }

  Future<void> writeWav(String path, {bool float32 = false}) async {
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(toWav(float32: float32), flush: true);
  }

  /// Parses PCM16 / PCM24 / float32 WAV.
  static AudioBuffer fromWav(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    String tag(int off) => String.fromCharCodes(bytes.sublist(off, off + 4));
    if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('Not a WAV file');
    }
    var off = 12;
    int? format, ch, sr, bits;
    while (off + 8 <= bytes.length) {
      final id = tag(off);
      final size = bd.getUint32(off + 4, Endian.little);
      final body = off + 8;
      if (id == 'fmt ') {
        format = bd.getUint16(body, Endian.little);
        ch = bd.getUint16(body + 2, Endian.little);
        sr = bd.getUint32(body + 4, Endian.little);
        bits = bd.getUint16(body + 14, Endian.little);
        if (format == 0xFFFE && size >= 26) format = bd.getUint16(body + 24, Endian.little);
      } else if (id == 'data') {
        if (format == null) throw const FormatException('WAV data before fmt');
        final bytesPer = bits! ~/ 8;
        final end = math.min(bytes.length, body + size);
        final n = (end - body) ~/ bytesPer;
        final out = Float32List(n);
        for (var i = 0; i < n; i++) {
          final p = body + i * bytesPer;
          out[i] = switch ((format, bits)) {
            (3, 32) => bd.getFloat32(p, Endian.little),
            (1, 16) => bd.getInt16(p, Endian.little) / 32768.0,
            (1, 24) => (((bytes[p + 2] << 24) | (bytes[p + 1] << 16) | (bytes[p] << 8)) >> 8) / 8388608.0,
            (1, 32) => bd.getInt32(p, Endian.little) / 2147483648.0,
            (1, 8) => (bytes[p] - 128) / 128.0,
            _ => throw FormatException('Unsupported WAV encoding $format/$bits'),
          };
        }
        final channels = ch!;
        if (channels > 2) {
          // Downmix to stereo by taking the first two channels.
          final frames = n ~/ channels;
          final st = Float32List(frames * 2);
          for (var i = 0; i < frames; i++) {
            st[2 * i] = out[i * channels];
            st[2 * i + 1] = out[i * channels + 1];
          }
          return AudioBuffer(st, sampleRate: sr!, channels: 2);
        }
        return AudioBuffer(
          Float32List.sublistView(out, 0, (n ~/ channels) * channels),
          sampleRate: sr!,
          channels: channels,
        );
      }
      off = body + size + (size.isOdd ? 1 : 0);
    }
    throw const FormatException('WAV has no data chunk');
  }

  // ---------------------------------------------------------------------------
  // Decoding through FFmpeg
  // ---------------------------------------------------------------------------

  /// Decodes any audio/video file's audio to float PCM via FFmpeg.
  static Future<AudioBuffer> decode(
    String ffmpeg,
    String path, {
    int sampleRate = 48000,
    int channels = 1,
    double? start,
    double? duration,
  }) async {
    final args = [
      '-hide_banner', '-nostdin', '-loglevel', 'error', //
      if (start != null && start > 0) ...['-ss', start.toStringAsFixed(4)],
      if (duration != null) ...['-t', duration.toStringAsFixed(4)],
      '-i', path, '-vn', '-ac', '$channels', '-ar', '$sampleRate', '-f', 'f32le', 'pipe:1',
    ];
    final proc = await Process.start(ffmpeg, args);
    final chunks = BytesBuilder(copy: false);
    final err = StringBuffer();
    final errDone = proc.stderr.listen((d) => err.write(String.fromCharCodes(d))).asFuture<void>();
    await proc.stdout.forEach(chunks.add);
    final code = await proc.exitCode;
    await errDone;
    final bytes = chunks.takeBytes();
    if (code != 0 && bytes.isEmpty) {
      throw ProcessException(ffmpeg, args, err.toString().trim(), code);
    }
    final usable = bytes.length - bytes.length % (4 * channels);
    final floats = Float32List(usable ~/ 4);
    final bd = ByteData.sublistView(bytes);
    for (var i = 0; i < floats.length; i++) {
      floats[i] = bd.getFloat32(i * 4, Endian.little);
    }
    return AudioBuffer(floats, sampleRate: sampleRate, channels: channels);
  }
}
