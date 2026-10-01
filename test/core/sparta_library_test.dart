import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:video_effects_studio/core/sparta/base_library.dart';
import 'package:video_effects_studio/core/sparta/model.dart';
import 'package:video_effects_studio/core/sparta/transcription.dart';

const _catalog = '''{"version":1,"bases":[
 {"id":"keaton/sparta-extended","name":"Sparta Extended Remix (official instrumental base)","maker":"Keaton (Funtastic Power!)","collection":"Keaton's World","audio":"https://example.org/extended.mp3","page":"https://keaton-world.com/music.php","featured":true},
 {"id":"flp-archive/x","name":"Sparta Keel Base","maker":"Dalton Stephens","collection":"Sparta Archive FLP Remixes","audio":"https://example.org/keel.mp3","flp":"https://example.org/keel.flp","size":5},
 {"id":"hb/venom","name":"Sparta Venom Base","maker":"","collection":"Sparta Bases","audio":"https://example.org/venom.mp3","sha1":"ABCDEF","transcription":"transcriptions/hb-venom.json"}
]}''';

void main() {
  test('the bundled catalog parses and lists real bases with credits', () {
    final text = File('bases/catalog.json').readAsStringSync();
    final c = BaseCatalog.parse(text);
    expect(c.bases.length, greaterThan(400));
    final extended = c.byId('keaton/sparta-extended')!;
    expect(extended.featured, isTrue);
    expect(extended.maker, contains('Keaton'));
    final exact = c.bases.where((b) => b.flpUrl != null).toList();
    expect(exact.length, greaterThanOrEqualTo(10));
    // Each project's audio is its render, not a sample from its folder.
    for (final b in exact) {
      expect(b.audioUrl, isNot(matches(RegExp(r'kick|snare|crash|korg|intro|vox|loop', caseSensitive: false))));
    }
    for (final b in c.bases) {
      expect(Uri.parse(b.audioUrl).isAbsolute, isTrue, reason: b.id);
      expect(b.credit, isNotEmpty, reason: b.id);
    }
  });

  test('search, exact bases and recognising a file by its SHA-1', () {
    final c = BaseCatalog.parse(_catalog);
    expect(c.search('keel').single.name, 'Sparta Keel Base');
    expect(c.search('sparta base').length, 3);
    expect(c.search('venom bases').single.id, 'hb/venom');
    expect(c.search('', exactOnly: true).map((b) => b.id), ['flp-archive/x', 'hb/venom']);
    expect(c.bySha1('abcdef')!.id, 'hb/venom');
    expect(c.byId('hb/venom')!.exact, isTrue);
    expect(c.byId('keaton/sparta-extended')!.exact, isFalse);
  });

  test('downloads once into the cache, prefers a newer remote catalog, fetches checked transcriptions', () async {
    final dir = await Directory.systemTemp.createTemp('lib_test');
    var downloads = 0;
    final transcription = BaseTranscription(bpm: 140, rootKey: 63, lengthBeats: 16, credit: 'Tester').encode();
    final client = MockClient.streaming((request, _) async {
      final url = request.url.toString();
      if (url.endsWith('catalog.json')) {
        return http.StreamedResponse(Stream.value(utf8.encode(_catalog)), 200);
      }
      if (url.endsWith('hb-venom.json')) {
        return http.StreamedResponse(Stream.value(utf8.encode(transcription)), 200);
      }
      if (url.endsWith('keel.mp3')) {
        downloads++;
        return http.StreamedResponse(Stream.value([1, 2, 3, 4, 5]), 200, contentLength: 5);
      }
      return http.StreamedResponse(const Stream.empty(), 404);
    });
    final lib = BaseLibrary(cacheDir: dir.path, client: client);
    final c = await lib.catalog('{"version":1,"bases":[]}');
    expect(c.bases, hasLength(3));
    final keel = c.byId('flp-archive/x')!;
    var last = 0.0;
    final path = await lib.audio(keel, onProgress: (f) => last = f);
    expect(File(path).readAsBytesSync(), [1, 2, 3, 4, 5]);
    expect(last, 1);
    await lib.audio(keel);
    expect(downloads, 1, reason: 'cached');
    expect(await lib.isDownloaded(keel), isTrue);
    final t = await lib.checkedTranscription(c.byId('hb/venom')!);
    expect(t!.credit, 'Tester');
    expect(t.rootName, 'D#');
    // Offline afterwards: the cached remote catalog still loads.
    final offline = BaseLibrary(
      cacheDir: dir.path,
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    expect((await offline.catalog('{"version":1,"bases":[]}')).bases, hasLength(3));
    await expectLater(offline.audio(c.byId('keaton/sparta-extended')!), throwsA(isA<SocketException>()));
    await dir.delete(recursive: true);
  });

  test('a fixed transcription is saved and sent as a prefilled issue', () async {
    final t = BaseTranscription(
      bpm: 140,
      rootKey: 62,
      lengthBeats: 32,
      sections: const [Section(SectionKind.chorus, 0, 32)],
      baseName: 'Sparta Venom Base',
      catalogId: 'hb/venom',
      audioSha1: 'abc',
    );
    expect(BaseLibrary.submissionFileName(t), 'Sparta Venom Base.sparta.json');
    final url = BaseLibrary.submissionUrl(t, credit: 'Me');
    expect(url.host, 'github.com');
    expect(url.path, '/1ajh/video-effects-studio/issues/new');
    expect(url.queryParameters['template'], 'base-transcription.yml');
    expect(url.queryParameters['base'], 'Sparta Venom Base');
    expect(url.queryParameters['catalog'], 'hb/venom');
    expect(url.queryParameters['sha1'], 'abc');
    expect(url.queryParameters['credit'], 'Me');
    // The issue form has a field for every prefilled value.
    final form = File(p.join('.github', 'ISSUE_TEMPLATE', 'base-transcription.yml')).readAsStringSync();
    for (final id in ['base', 'maker', 'catalog', 'sha1', 'credit', 'notes', 'transcription']) {
      expect(form, contains('id: $id'), reason: id);
    }
  });
}
