// Writes a base transcription (.sparta.json) for the catalog, from a base's
// FL Studio / FL Studio Mobile / MIDI project (exact) or its audio (a draft
// to check), optionally lined up with the base's audio.
//
//   dart run tool/transcribe_base.dart <base.flp|.flm|.mid|.mp3|.wav> [--audio base.mp3] [--name "Base"]
//       [--maker "Who"] [--catalog id] [--credit "Who checked it"] [--out file.sparta.json]
//
// Audio needs FFmpeg on the PATH (or --ffmpeg path/to/ffmpeg).
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:video_effects_studio/core/sparta/base_library.dart';
import 'package:video_effects_studio/core/sparta/sparta_engine.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    print(
      'usage: dart run tool/transcribe_base.dart <base file> [--audio file] [--name] [--maker] [--catalog] '
      '[--credit] [--out] [--ffmpeg]',
    );
    exit(64);
  }
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final input = args.first;
  final audio = opt('audio');
  final engine = SpartaEngine(
    ffmpegPath: opt('ffmpeg') ?? 'ffmpeg',
    cacheDir: p.join(Directory.systemTemp.path, 'sparta_transcribe'),
  );
  final isProject = SpartaEngine.projectExtensions.contains(p.extension(input).toLowerCase());
  final prepared = await engine.prepareBase(
    isProject ? ProjectBaseSource(projectPath: input, audioPath: audio) : AudioBaseSource(audioPath: input),
    onStatus: (s, _) => print(s),
  );
  final audioPath = audio ?? (isProject ? null : input);
  var t = prepared.transcription.copyWith(
    baseName: opt('name'),
    maker: opt('maker'),
    catalogId: opt('catalog'),
    credit: opt('credit'),
    audioSha1: audioPath == null ? null : await BaseLibrary.sha1Of(audioPath),
  );
  if (opt('credit') != null) t = t.copyWith(source: TranscriptionSource.curated);
  final out = opt('out') ?? BaseLibrary.submissionFileName(t);
  await File(out).writeAsString(t.encode());
  print(
    '${t.source.label}: ${t.bpm} BPM, root ${keyName(t.rootKey)}, ${t.bars} bars, ${t.hits.length} hits, '
    '${t.kick.length}/${t.snare.length}/${t.hat.length} kick/snare/hat, '
    'sections ${t.sections.map((s) => '${s.kind.name} ${(s.lengthBeats / t.beatsPerBar).round()}').join(', ')}',
  );
  print('wrote $out');
  exit(0);
}
