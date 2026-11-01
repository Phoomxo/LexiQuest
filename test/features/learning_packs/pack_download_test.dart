import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/learning_packs/data/http_learning_pack_source.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_download.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';

void main() {
  test(
    'configured download verifies exact anonymous bytes and manifest',
    () async {
      final pack = _pack();
      final descriptor = _descriptor(pack);
      var calls = 0;
      final progress = <int>[];
      final source = HttpLearningPackSource(
        catalog: [descriptor],
        client: MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.url, descriptor.uri);
          expect(request.followRedirects, isFalse);
          expect(request.headers.containsKey('authorization'), isFalse);
          expect(request.headers.containsKey('cookie'), isFalse);
          return http.Response.bytes(pack.bytes, 200);
        }),
      );
      addTearDown(source.dispose);
      final loaded = await source.download(
        descriptor,
        stillCurrent: () => true,
        onProgress: (received, _) => progress.add(received),
      );
      expect(calls, 1);
      expect(loaded.bytes, pack.bytes);
      expect(loaded.packageSha256, descriptor.packageSha256);
      expect(progress.last, pack.byteCount);
    },
  );
  test(
    'a descriptor outside the configured catalog cannot send a request',
    () async {
      final pack = _pack();
      var calls = 0;
      final source = HttpLearningPackSource(
        catalog: [_descriptor(pack)],
        client: MockClient((_) async {
          calls++;
          return http.Response.bytes(pack.bytes, 200);
        }),
      );
      addTearDown(source.dispose);
      await expectLater(
        source.download(_descriptor(pack), stillCurrent: () => true),
        throwsA(
          isA<PackStorageException>().having(
            (e) => e.code,
            'code',
            PackStorageFailureCode.invalid,
          ),
        ),
      );
      expect(calls, 0);
    },
  );

  for (final status in [302, 307, 401, 500]) {
    test('HTTP $status cannot follow redirects or produce a package', () async {
      final pack = _pack();
      final descriptor = _descriptor(pack);
      var calls = 0;
      final source = HttpLearningPackSource(
        catalog: [descriptor],
        client: MockClient((request) async {
          calls++;
          expect(request.followRedirects, isFalse);
          return http.Response.bytes(
            pack.bytes,
            status,
            headers: {'location': 'https://127.0.0.1/private'},
          );
        }),
      );
      addTearDown(source.dispose);
      await expectLater(
        source.download(descriptor, stillCurrent: () => true),
        throwsA(isA<PackStorageException>()),
      );
      expect(calls, 1);
    });
  }

  for (final change in ['checksum', 'size', 'manifest']) {
    test('download rejects a mismatched $change', () async {
      final pack = _pack();
      final descriptor = LearningPackDownloadDescriptor(
        catalogId: 'synthetic-source',
        manifest: change == 'manifest'
            ? _pack(meaning: 'different').manifest
            : pack.manifest,
        uri: Uri.parse('https://packs.example.com/package'),
        packageSha256: change == 'checksum' ? '0' * 64 : pack.packageSha256,
        packageByteCount: pack.byteCount + (change == 'size' ? 1 : 0),
      );
      final source = HttpLearningPackSource(
        catalog: [descriptor],
        client: MockClient((_) async => http.Response.bytes(pack.bytes, 200)),
      );
      addTearDown(source.dispose);
      await expectLater(
        source.download(descriptor, stillCurrent: () => true),
        throwsA(
          isA<LearningPackException>().having(
            (e) => e.code,
            'code',
            LearningPackFailureCode.integrityMismatch,
          ),
        ),
      );
    });
  }

  test('streaming response cannot exceed its pinned byte count', () async {
    final pack = _pack();
    final descriptor = _descriptor(pack);
    final source = HttpLearningPackSource(
      catalog: [descriptor],
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([
            pack.bytes,
            [0],
          ]),
          200,
        ),
      ),
    );
    addTearDown(source.dispose);
    await expectLater(
      source.download(descriptor, stillCurrent: () => true),
      throwsA(
        isA<LearningPackException>().having(
          (e) => e.code,
          'code',
          LearningPackFailureCode.tooLarge,
        ),
      ),
    );
  });

  test(
    'caller retirement while bytes arrive prevents a returned package',
    () async {
      final pack = _pack();
      final descriptor = _descriptor(pack);
      var current = true;
      final source = HttpLearningPackSource(
        catalog: [descriptor],
        client: MockClient((_) async => http.Response.bytes(pack.bytes, 200)),
      );
      addTearDown(source.dispose);
      await expectLater(
        source.download(
          descriptor,
          stillCurrent: () => current,
          onProgress: (received, _) {
            if (received > 0) current = false;
          },
        ),
        throwsA(
          isA<PackStorageException>().having(
            (e) => e.code,
            'code',
            PackStorageFailureCode.ownerChanged,
          ),
        ),
      );
    },
  );

  test(
    'whole-response deadline retires late progress as well as the request',
    () async {
      final pack = _pack();
      final descriptor = _descriptor(pack);
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final progress = <int>[];
      final source = HttpLearningPackSource(
        catalog: [descriptor],
        timeout: const Duration(milliseconds: 20),
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            body.stream,
            200,
            contentLength: pack.byteCount,
          ),
        ),
      );
      addTearDown(source.dispose);
      await expectLater(
        source.download(
          descriptor,
          stillCurrent: () => true,
          onProgress: (received, _) => progress.add(received),
        ),
        throwsA(
          isA<PackStorageException>().having(
            (e) => e.code,
            'code',
            PackStorageFailureCode.unavailable,
          ),
        ),
      );
      body.add(pack.bytes);
      await Future<void>.delayed(Duration.zero);
      expect(progress, [0]);
    },
  );

  test(
    'disposing cancels a pending request and never publishes late bytes',
    () async {
      final pack = _pack();
      final descriptor = _descriptor(pack);
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final progress = <int>[];
      final source = HttpLearningPackSource(
        catalog: [descriptor],
        client: MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final download = source.download(
        descriptor,
        stillCurrent: () => true,
        onProgress: (received, _) => progress.add(received),
      );
      await started.future;
      source.dispose();
      source.dispose();
      await expectLater(
        download,
        throwsA(
          isA<PackStorageException>().having(
            (e) => e.code,
            'code',
            PackStorageFailureCode.ownerChanged,
          ),
        ),
      );
      response.complete(http.Response.bytes(pack.bytes, 200));
      await Future<void>.delayed(Duration.zero);
      expect(progress, isEmpty);
    },
  );

  for (final uri in [
    'http://packs.example.com/p',
    'https://127.0.0.1/p',
    'https://2130706433/p',
    'https://[::1]/p',
    'https://localhost/p',
    'https://host.local/p',
    'https://host.internal/p',
    'https://user:secret@packs.example.com/p',
    'https://packs.example.com/p#fragment',
    'https://packs.example.com:8443/p',
  ]) {
    test('catalog rejects unsafe address $uri', () {
      final pack = _pack();
      expect(
        () => LearningPackDownloadDescriptor(
          catalogId: 'synthetic-source',
          manifest: pack.manifest,
          uri: Uri.parse(uri),
          packageSha256: pack.packageSha256,
          packageByteCount: pack.byteCount,
        ),
        throwsA(isA<PackStorageException>()),
      );
    });
  }
}

LearningPackDownloadDescriptor _descriptor(LearningPack pack) =>
    LearningPackDownloadDescriptor(
      catalogId: 'synthetic-pack-source',
      manifest: pack.manifest,
      uri: Uri.parse('https://packs.example.com/fixture.json'),
      packageSha256: pack.packageSha256,
      packageByteCount: pack.byteCount,
    );

LearningPack _pack({String meaning = 'a cat'}) =>
    const LearningPackCodec().decode(
      const LearningPackCodec().encode(
        metadata: LearningPackMetadata(
          packId: 'synthetic-download',
          version: '1',
          title: 'Synthetic download',
          objectives: ['Synthetic objective'],
          cefrLevel: 'A1',
          language: 'en',
          meaningLanguage: 'en',
          provenance: const LearningPackProvenance(
            author: 'Synthetic fixture',
            source: 'Synthetic fixture',
            license: 'Synthetic test only',
            attribution: 'No real publisher',
          ),
        ),
        entries: [
          LearningPackEntry(
            code: 'word',
            spelling: 'cat',
            meaning: meaning,
            partOfSpeech: 'noun',
          ),
        ],
      ),
    );
