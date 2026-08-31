import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/offline_content/data/voice_pack_download_adapter.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_download_manager.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_manifest.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

StandardVoicePackManifest _manifest(
  List<int> bytes, {
  String packId = 'core-en',
  String version = '1.0.0',
  String modelVersion = '2.0.3',
}) {
  return StandardVoicePackManifest.fromJson({
    'schemaVersion': 1,
    'packId': packId,
    'version': version,
    'locale': 'en',
    'voiceId': 'teacher_female',
    'engine': 'voxcpm2',
    'modelVersion': modelVersion,
    'license': 'Apache-2.0',
    'licenseUri': 'https://github.com/OpenBMB/VoxCPM/blob/main/LICENSE',
    'minimumAppVersion': '1.0.0+1',
    'baseUri': 'https://assets.example.com/$packId/$version/',
    'generatedAtUtc': '2026-07-31T00:00:00Z',
    'totalBytes': bytes.length,
    'files': [
      {
        'contentId': 'word-cat',
        'normalizedTextSha256':
            '48735c4fae42d1501164976afec76730b9e5fe467f680bdd8daff4bb77674045',
        'relativePath': 'words/cat.wav',
        'byteSize': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      },
    ],
  });
}

final class _Source implements StandardVoicePackByteSource {
  _Source(this.bytes, {this.corrupt = false});

  final List<int> bytes;
  final bool corrupt;
  final starts = <int>[];

  @override
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  }) async {
    starts.add(start);
    final served = [...bytes];
    if (corrupt) served[0] = served[0] ^ 0xff;
    return StandardVoicePackByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: Stream.value(served.sublist(start)),
    );
  }
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lexiquest-pack-manager-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'resumes a partial file, verifies SHA-256 and atomically activates',
    () async {
      final bytes = _validTestWav();
      final manifest = _manifest(bytes);
      final source = _Source(bytes);
      final staging = Directory(
        '${root.path}${Platform.pathSeparator}${manifest.recordId}.partial',
      );
      final partial = File(
        '${staging.path}${Platform.pathSeparator}words'
        '${Platform.pathSeparator}cat.wav.partial',
      );
      await partial.parent.create(recursive: true);
      await partial.writeAsBytes(bytes.sublist(0, 4));
      final manager = StandardVoicePackDownloadManager(
        rootDirectory: () async => root,
        source: source,
        availableBytes: (_) async => 1024 * 1024,
        storageReserveBytes: 0,
      );

      final installed = await manager.install(manifest);

      expect(source.starts, [4]);
      expect(
        await File(installed.pathFor('words/cat.wav')).readAsBytes(),
        bytes,
      );
      expect(await File(installed.manifestPath).exists(), isTrue);
      expect(await File(installed.activeMarkerPath).readAsString(), '1.0.0');
      expect(await staging.exists(), isFalse);
    },
  );

  test('checksum corruption is rejected and never activated', () async {
    final bytes = _validTestWav();
    final manager = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: _Source(bytes, corrupt: true),
      availableBytes: (_) async => 1024 * 1024,
      storageReserveBytes: 0,
    );

    await expectLater(
      manager.install(_manifest(bytes)),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.checksumMismatch,
        ),
      ),
    );

    expect(
      await File(
        '${root.path}${Platform.pathSeparator}core-en.active',
      ).exists(),
      isFalse,
    );
  });

  test('f44 final review truncated RIFF bytes never activate', () async {
    final bytes = Uint8List.fromList(<int>[82, 73, 70, 70]);
    final manager = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: _Source(bytes),
      availableBytes: (_) async => 1024 * 1024,
      storageReserveBytes: 0,
    );

    await expectLater(
      manager.install(_manifest(bytes)),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.checksumMismatch,
        ),
      ),
    );
    expect(
      await File(
        '${root.path}${Platform.pathSeparator}core-en.active',
      ).exists(),
      isFalse,
    );
  });

  test(
    'f44 final review packaged production WAV installs without network',
    () async {
      final catalog = OfflineVoicePackManifestCatalog.production;
      final identity = catalog.identities.single;
      final manifest = catalog.requireManifest(identity);
      final descriptor = manifest.files.single;
      final bytes = catalog.requirePackagedFileBytes(descriptor.uri);
      final source = _Source(bytes);
      final manager = StandardVoicePackDownloadManager(
        rootDirectory: () async => root,
        source: source,
        availableBytes: (_) async => 1024 * 1024,
        storageReserveBytes: 0,
      );

      final installed = await manager.install(manifest);

      expect(
        await File(installed.pathFor(descriptor.relativePath)).readAsBytes(),
        bytes,
      );
      expect(source.starts, <int>[0]);
    },
  );

  test('free-space preflight and cancellation fail closed', () async {
    final bytes = _validTestWav();
    final manifest = _manifest(bytes);
    final noSpace = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: _Source(bytes),
      availableBytes: (_) async => bytes.length - 1,
      storageReserveBytes: 0,
    );
    await expectLater(
      noSpace.install(manifest),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.insufficientStorage,
        ),
      ),
    );

    final cancellation = StandardVoicePackCancellation()..cancel();
    final cancelled = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: _Source(bytes),
      availableBytes: (_) async => 1024,
      storageReserveBytes: 0,
    );
    await expectLater(
      cancelled.install(manifest, cancellation: cancellation),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.cancelled,
        ),
      ),
    );
  });

  test(
    'f44 second review installed manifest must exactly match canonical voice mapping',
    () async {
      final bytes = _validTestWav();
      final canonical = _manifest(bytes);
      final manager = StandardVoicePackDownloadManager(
        rootDirectory: () async => root,
        source: _Source(bytes),
        availableBytes: (_) async => 1024 * 1024,
        storageReserveBytes: 0,
      );
      final mutations = <void Function(Map<String, dynamic>)>[
        (json) => json['modelVersion'] = '2.0.4',
        (json) {
          final files = json['files']! as List<dynamic>;
          (files.single as Map<String, dynamic>)['contentId'] = 'word-dog';
        },
        (json) {
          final files = json['files']! as List<dynamic>;
          (files.single as Map<String, dynamic>)['normalizedTextSha256'] =
              List<String>.filled(64, 'a').join();
        },
      ];

      for (final mutate in mutations) {
        final installed = await manager.install(canonical);
        final tampered =
            jsonDecode(jsonEncode(canonical.toJson())) as Map<String, dynamic>;
        mutate(tampered);
        await File(installed.manifestPath).writeAsString(jsonEncode(tampered));

        expect(await manager.findVerifiedInstalled(canonical), isNull);

        final directory = Directory(installed.rootPath);
        if (await directory.exists()) await directory.delete(recursive: true);
        final marker = File(installed.activeMarkerPath);
        if (await marker.exists()) await marker.delete();
      }
    },
  );

  test(
    'f44 review storage preflight includes receipt metadata marker and reserve',
    () async {
      final bytes = _validTestWav();
      final manifest = _manifest(bytes);
      const receiptBytes = 73;
      const reserveBytes = 4096;
      late int available;
      final manager = StandardVoicePackDownloadManager(
        rootDirectory: () async => root,
        source: _Source(bytes),
        availableBytes: (_) async => available,
        storageReserveBytes: reserveBytes,
      );
      final required = manager.requiredInstallationBytes(
        manifest,
        receiptBytes: receiptBytes,
      );
      final installedManifestBytes = utf8
          .encode('${jsonEncode(manifest.toJson())}\n')
          .length;
      final markerBytes = utf8.encode(manifest.version).length;

      expect(
        required,
        bytes.length +
            installedManifestBytes +
            markerBytes +
            receiptBytes +
            reserveBytes,
      );
      available = required - 1;
      await expectLater(
        manager.install(manifest, receiptBytes: receiptBytes),
        throwsA(
          isA<VoiceFailure>().having(
            (failure) => failure.category,
            'category',
            VoiceFailureCategory.insufficientStorage,
          ),
        ),
      );
    },
  );

  test(
    'f44 review identical installs coalesce while pack revisions serialize',
    () async {
      final firstBytes = _validTestWav();
      final secondBytes = _validTestWav(amplitude: 2048);
      final firstManifest = _manifest(firstBytes);
      final secondManifest = _manifest(secondBytes, version: '1.1.0');
      final source = _BlockingVoiceSource(<Uri, List<int>>{
        firstManifest.files.single.uri: firstBytes,
        secondManifest.files.single.uri: secondBytes,
      });
      final manager = StandardVoicePackDownloadManager(
        rootDirectory: () async => root,
        source: source,
        availableBytes: (_) async => 1024 * 1024,
        storageReserveBytes: 0,
      );

      final first = manager.install(firstManifest);
      final firstReplay = manager.install(firstManifest);
      expect(identical(first, firstReplay), isTrue);
      await source.started(firstManifest.files.single.uri);
      final second = manager.install(secondManifest);
      final revisionsHaveDistinctOperations = !identical(first, second);
      await Future<void>.delayed(Duration.zero);
      expect(source.openedUris, <Uri>[firstManifest.files.single.uri]);

      source.release(firstManifest.files.single.uri);
      await first;
      await firstReplay;
      if (revisionsHaveDistinctOperations) {
        await source.started(secondManifest.files.single.uri);
        source.release(secondManifest.files.single.uri);
        await second;
      }

      expect(revisionsHaveDistinctOperations, isTrue);
      expect(source.openedUris, <Uri>[
        firstManifest.files.single.uri,
        secondManifest.files.single.uri,
      ]);
    },
  );

  test('f44 review canonical record identity cannot be overwritten', () async {
    final bytes = _validTestWav();
    final canonical = _manifest(bytes);
    final conflicting = _manifest(bytes, modelVersion: '2.0.4');
    final manager = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: _Source(bytes),
      availableBytes: (_) async => 1024 * 1024,
      storageReserveBytes: 0,
    );
    await manager.install(canonical);

    await expectLater(
      manager.install(conflicting),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.checksumMismatch,
        ),
      ),
    );
    expect(await manager.findVerifiedInstalled(canonical), isNotNull);
  });

  test('f44 review stalled response bodies time out and cancel', () async {
    final bytes = _validTestWav();
    final source = _StalledVoiceSource();
    final manager = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: source,
      availableBytes: (_) async => 1024 * 1024,
      storageReserveBytes: 0,
      bodyInactivityTimeout: const Duration(milliseconds: 10),
      cancellationDrainTimeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      manager
          .install(_manifest(bytes))
          .timeout(const Duration(milliseconds: 200)),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.timeout,
        ),
      ),
    );
    expect(source.cancelCalls, 1);
    await source.closed.future.timeout(const Duration(milliseconds: 200));
  });

  test(
    'f44 final review slow trickle cannot evade the total body deadline',
    () async {
      final bytes = _validTestWav();
      final source = _SlowTrickleVoiceSource(bytes);
      final manager = StandardVoicePackDownloadManager(
        rootDirectory: () async => root,
        source: source,
        availableBytes: (_) async => 1024 * 1024,
        storageReserveBytes: 0,
        bodyInactivityTimeout: const Duration(milliseconds: 50),
        bodyTotalTimeout: const Duration(milliseconds: 20),
        cancellationDrainTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        manager.install(_manifest(bytes)),
        throwsA(
          isA<VoiceFailure>().having(
            (failure) => failure.category,
            'category',
            VoiceFailureCategory.timeout,
          ),
        ),
      );
      expect(source.cancelCalls, 1);
      await source.closed.future.timeout(const Duration(milliseconds: 200));
    },
  );

  test('f44 review dispose cancels and drains stalled voice work', () async {
    final bytes = _validTestWav();
    final manifest = _manifest(bytes);
    final source = _StalledVoiceSource();
    final manager = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: source,
      availableBytes: (_) async => 1024 * 1024,
      storageReserveBytes: 0,
      bodyInactivityTimeout: const Duration(minutes: 1),
      cancellationDrainTimeout: const Duration(milliseconds: 50),
    );
    final operation = manager.install(manifest);
    final result = expectLater(
      operation,
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.cancelled,
        ),
      ),
    );
    await source.started.future;

    await manager.dispose().timeout(const Duration(milliseconds: 200));

    await result;
    expect(source.cancelCalls, 1);
    await source.closed.future.timeout(const Duration(milliseconds: 200));
    expect(() => manager.install(manifest), throwsStateError);
  });
}

final class _BlockingVoiceSource implements StandardVoicePackByteSource {
  _BlockingVoiceSource(this.bytesByUri);

  final Map<Uri, List<int>> bytesByUri;
  final List<Uri> openedUris = <Uri>[];
  final Map<Uri, Completer<void>> _started = <Uri, Completer<void>>{};
  final Map<Uri, Completer<void>> _release = <Uri, Completer<void>>{};

  Future<void> started(Uri uri) => (_started[uri] ??= Completer<void>()).future;

  void release(Uri uri) {
    final completer = _release[uri] ??= Completer<void>();
    if (!completer.isCompleted) completer.complete();
  }

  @override
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  }) async {
    openedUris.add(uri);
    final started = _started[uri] ??= Completer<void>();
    if (!started.isCompleted) started.complete();
    final release = _release[uri] ??= Completer<void>();
    await release.future;
    final bytes = bytesByUri[uri]!;
    return StandardVoicePackByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: Stream<List<int>>.value(bytes.sublist(start)),
    );
  }
}

final class _StalledVoiceSource implements StandardVoicePackByteSource {
  final Completer<void> started = Completer<void>();
  final Completer<void> closed = Completer<void>();
  int cancelCalls = 0;

  @override
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  }) async {
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        if (!started.isCompleted) started.complete();
      },
      onCancel: () {
        cancelCalls += 1;
        scheduleMicrotask(() async {
          if (!controller.isClosed) await controller.close();
          if (!closed.isCompleted) closed.complete();
        });
      },
    );
    return StandardVoicePackByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: controller.stream,
    );
  }
}

final class _SlowTrickleVoiceSource implements StandardVoicePackByteSource {
  _SlowTrickleVoiceSource(this.bytes);

  final Uint8List bytes;
  final Completer<void> closed = Completer<void>();
  int cancelCalls = 0;

  @override
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  }) async {
    var subscriptionCancelled = false;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () async {
        for (final byte in bytes.skip(start)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (subscriptionCancelled ||
              cancellation?.isCancelled == true ||
              controller.isClosed) {
            break;
          }
          controller.add(<int>[byte]);
        }
        if (!subscriptionCancelled && !controller.isClosed) {
          await controller.close();
          if (!closed.isCompleted) closed.complete();
        }
      },
      onCancel: () {
        subscriptionCancelled = true;
        cancelCalls += 1;
        scheduleMicrotask(() async {
          if (!controller.isClosed) await controller.close();
          if (!closed.isCompleted) closed.complete();
        });
      },
    );
    return StandardVoicePackByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: controller.stream,
    );
  }
}

Uint8List _validTestWav({int amplitude = 4096}) {
  final samples = <int>[
    0,
    amplitude,
    0,
    -amplitude,
    0,
    amplitude,
    0,
    -amplitude,
  ];
  final dataBytes = samples.length * 2;
  final result = ByteData(44 + dataBytes);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      result.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  result.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  result.setUint32(16, 16, Endian.little);
  result.setUint16(20, 1, Endian.little);
  result.setUint16(22, 1, Endian.little);
  result.setUint32(24, 8000, Endian.little);
  result.setUint32(28, 16000, Endian.little);
  result.setUint16(32, 2, Endian.little);
  result.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  result.setUint32(40, dataBytes, Endian.little);
  for (var index = 0; index < samples.length; index += 1) {
    result.setInt16(44 + index * 2, samples[index], Endian.little);
  }
  return result.buffer.asUint8List();
}
