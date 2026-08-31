import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/device_model/application/model_download_manager.dart';
import 'package:vocab_learning_app/features/device_model/data/drift_model_download_repository.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';
import 'package:vocab_learning_app/runtime/download_counter.dart';

void main() {
  late Directory directory;
  late _MemoryModelDownloadRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lexiquest-model-test-');
    repository = _MemoryModelDownloadRepository();
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'resumes valid partial bytes, verifies, and activates atomically',
    () async {
      final bytes = utf8.encode('verified-model-bytes');
      final manifest = _manifestFor(bytes);
      final partial = File(
        '${directory.path}${Platform.pathSeparator}'
        '${manifest.fileStem}.tflite.partial',
      );
      await partial.writeAsBytes(bytes.take(8).toList(), flush: true);
      final source = _MemoryRangeSource(bytes);
      final verifier = _RecordingVerifier();
      final completedVersions = <String>[];
      final manager = ModelDownloadManager(
        repository: repository,
        source: source,
        verifier: verifier,
        modelDirectory: () async => directory,
        nowUtc: () => DateTime.utc(2026, 7, 30, 8),
        onDownloadCompleted: (version) async {
          completedVersions.add(version);
        },
      );

      final result = await manager.downloadAndActivate(manifest);

      expect(source.requestedStarts, [8]);
      expect(result.state, ModelDownloadState.active);
      expect(result.downloadedBytes, bytes.length);
      expect(await File(result.localPath!).readAsBytes(), bytes);
      expect(await partial.exists(), isFalse);
      expect(verifier.paths.single, endsWith('.tflite.partial'));
      expect(repository.activations, 1);
      expect(completedVersions, [manifest.version]);
    },
  );

  test(
    'restarts safely when a range request receives a full response',
    () async {
      final bytes = utf8.encode('complete-model');
      final manifest = _manifestFor(bytes);
      final partial = File(
        '${directory.path}${Platform.pathSeparator}'
        '${manifest.fileStem}.tflite.partial',
      );
      await partial.writeAsBytes(utf8.encode('stale'), flush: true);
      final source = _MemoryRangeSource(bytes, ignoreRange: true);
      final manager = ModelDownloadManager(
        repository: repository,
        source: source,
        verifier: _RecordingVerifier(),
        modelDirectory: () async => directory,
        nowUtc: () => DateTime.utc(2026, 7, 30, 8),
      );

      final result = await manager.downloadAndActivate(manifest);

      expect(source.requestedStarts, [5]);
      expect(await File(result.localPath!).readAsBytes(), bytes);
    },
  );

  test('revalidates an active file and replaces corrupted bytes', () async {
    final bytes = utf8.encode('known-good-model');
    final manifest = _manifestFor(bytes);
    final active = File(
      '${directory.path}${Platform.pathSeparator}'
      '${manifest.fileStem}.tflite',
    );
    await active.writeAsBytes(utf8.encode('corrupted-model!'), flush: true);
    repository.record = ModelDownloadRecord(
      id: manifest.recordId,
      modelVersion: manifest.version,
      sourceUrl: manifest.sourceUri.toString(),
      expectedChecksum: manifest.expectedSha256,
      expectedBytes: manifest.expectedBytes,
      downloadedBytes: manifest.expectedBytes,
      retryCount: 0,
      state: ModelDownloadState.active,
      updatedAtUtc: DateTime.utc(2026, 7, 30, 7),
      localPath: active.path,
    );
    final source = _MemoryRangeSource(bytes);
    final manager = ModelDownloadManager(
      repository: repository,
      source: source,
      verifier: _RecordingVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 7, 30, 8),
    );

    final result = await manager.downloadAndActivate(manifest);

    expect(source.requestedStarts, [0]);
    expect(result.state, ModelDownloadState.active);
    expect(await active.readAsBytes(), bytes);
  });

  test('coalesces concurrent activation requests into one download', () async {
    final bytes = utf8.encode('single-download');
    final manifest = _manifestFor(bytes);
    final source = _MemoryRangeSource(bytes, chunkSize: 2);
    final completedVersions = <String>[];
    final manager = ModelDownloadManager(
      repository: repository,
      source: source,
      verifier: _RecordingVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 7, 30, 8),
      onDownloadCompleted: (version) async {
        completedVersions.add(version);
      },
    );

    final results = await Future.wait([
      manager.downloadAndActivate(manifest),
      manager.downloadAndActivate(manifest),
    ]);

    expect(source.requestedStarts, [0]);
    expect(repository.activations, 1);
    expect(completedVersions, [manifest.version]);
    expect(results.map((result) => result.localPath).toSet(), hasLength(1));
  });

  test('serializes the same model across manager instances', () async {
    final bytes = utf8.encode('cross-manager-download');
    final manifest = _manifestFor(bytes);
    final source = _MemoryRangeSource(bytes, chunkSize: 2);
    final completedVersions = <String>[];
    ModelDownloadManager createManager() => ModelDownloadManager(
      repository: repository,
      source: source,
      verifier: _RecordingVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 7, 30, 8),
      lockRetryDelay: const Duration(milliseconds: 1),
      onDownloadCompleted: (version) async {
        completedVersions.add(version);
      },
    );
    final first = createManager();
    final second = createManager();

    final results = await Future.wait([
      first.downloadAndActivate(manifest),
      second.downloadAndActivate(manifest),
    ]);

    expect(source.requestedStarts, [0]);
    expect(repository.activations, 1);
    expect(completedVersions, [manifest.version]);
    expect(
      results.every((result) => result.state == ModelDownloadState.active),
      isTrue,
    );
  });

  test('recovers a verified final file after a pre-activation crash', () async {
    final bytes = utf8.encode('already-renamed-model');
    final manifest = _manifestFor(bytes);
    final finalFile = File(
      '${directory.path}${Platform.pathSeparator}'
      '${manifest.fileStem}.tflite',
    );
    await finalFile.writeAsBytes(bytes, flush: true);
    repository.record = ModelDownloadRecord(
      id: manifest.recordId,
      modelVersion: manifest.version,
      sourceUrl: manifest.sourceUri.toString(),
      expectedChecksum: manifest.expectedSha256,
      expectedBytes: manifest.expectedBytes,
      downloadedBytes: bytes.length,
      retryCount: 0,
      state: ModelDownloadState.verifying,
      updatedAtUtc: DateTime.utc(2026, 7, 30, 7),
      localPath: '${finalFile.path}.partial',
    );
    final source = _MemoryRangeSource(bytes);
    final manager = ModelDownloadManager(
      repository: repository,
      source: source,
      verifier: _RecordingVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 7, 30, 8),
    );

    final result = await manager.downloadAndActivate(manifest);

    expect(source.requestedStarts, isEmpty);
    expect(repository.activations, 1);
    expect(result.state, ModelDownloadState.active);
    expect(result.localPath, finalFile.path);
  });

  test('observability failure never changes a successful activation', () async {
    final bytes = utf8.encode('verified-despite-counter');
    final manifest = _manifestFor(bytes);
    final manager = ModelDownloadManager(
      repository: repository,
      source: _MemoryRangeSource(bytes),
      verifier: _RecordingVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 7, 30, 8),
      onDownloadCompleted: (_) async => throw StateError('counter unavailable'),
    );

    final result = await manager.downloadAndActivate(manifest);

    expect(result.state, ModelDownloadState.active);
    expect(repository.record?.state, ModelDownloadState.active);
    expect(repository.activations, 1);
  });

  test(
    'restart reconciles one missed activation count without inflation',
    () async {
      final bytes = utf8.encode('verified-reconciled-model');
      final manifest = _manifestFor(bytes);
      final databaseFile = File(
        '${directory.path}${Platform.pathSeparator}model-state.sqlite',
      );
      var database = AppDatabase(NativeDatabase(databaseFile));
      addTearDown(() => database.close());
      var failFirstRecord = true;

      ModelDownloadManager buildManager() {
        final counter = DownloadCounter(
          database,
          generateEventId: () => 'unused-random-event',
          nowUtc: () => DateTime.utc(2026, 7, 30, 8),
        );
        return ModelDownloadManager(
          repository: DriftModelDownloadRepository(database),
          source: _MemoryRangeSource(bytes),
          verifier: _RecordingVerifier(),
          modelDirectory: () async => directory,
          nowUtc: () => DateTime.utc(2026, 7, 30, 8),
          onVerifiedActivation:
              ({required modelVersion, required completionId}) async {
                if (failFirstRecord) {
                  failFirstRecord = false;
                  throw StateError('counter unavailable after activation');
                }
                await counter.recordCompletion(modelVersion, completionId);
              },
        );
      }

      final first = await buildManager().downloadAndActivate(manifest);
      expect(first.state, ModelDownloadState.active);
      expect(
        await DownloadCounter(
          database,
          generateEventId: () => 'unused',
        ).count(manifest.version),
        0,
      );

      await database.close();
      database = AppDatabase(NativeDatabase(databaseFile));
      final recovered = await buildManager().downloadAndActivate(manifest);
      expect(recovered.state, ModelDownloadState.active);
      expect(
        await DownloadCounter(
          database,
          generateEventId: () => 'unused',
        ).count(manifest.version),
        1,
      );

      await database.close();
      database = AppDatabase(NativeDatabase(databaseFile));
      final cached = await buildManager().downloadAndActivate(manifest);
      expect(cached.state, ModelDownloadState.active);
      expect(
        await DownloadCounter(
          database,
          generateEventId: () => 'unused',
        ).count(manifest.version),
        1,
      );

      await File(cached.localPath!).delete();
      final redownloaded = await buildManager().downloadAndActivate(manifest);
      expect(redownloaded.state, ModelDownloadState.active);
      expect(
        await DownloadCounter(
          database,
          generateEventId: () => 'unused',
        ).count(manifest.version),
        2,
        reason: 'a second verified network transfer is a second success',
      );

      await buildManager().downloadAndActivate(manifest);
      expect(
        await DownloadCounter(
          database,
          generateEventId: () => 'unused',
        ).count(manifest.version),
        2,
        reason: 'a cached verified open must not inflate the counter',
      );
    },
  );

  test(
    'upgraded cached artifact does not add to its legacy success count',
    () async {
      final bytes = utf8.encode('verified-before-task-eight');
      final manifest = _manifestFor(bytes);
      final source = _MemoryRangeSource(bytes);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final counter = DownloadCounter(
        database,
        generateEventId: () => '123e4567-e89b-42d3-a456-426614174000',
        nowUtc: () => DateTime.utc(2026, 7, 30, 8),
      );
      final repository = DriftModelDownloadRepository(database);

      await ModelDownloadManager(
        repository: repository,
        source: source,
        verifier: _RecordingVerifier(),
        modelDirectory: () async => directory,
        nowUtc: () => DateTime.utc(2026, 7, 30, 8),
        onDownloadCompleted: counter.increment,
      ).downloadAndActivate(manifest);
      expect(await counter.count(manifest.version), 1);

      await ModelDownloadManager(
        repository: repository,
        source: source,
        verifier: _RecordingVerifier(),
        modelDirectory: () async => directory,
        nowUtc: () => DateTime.utc(2026, 7, 30, 9),
        onVerifiedActivation:
            ({required modelVersion, required completionId}) =>
                counter.recordCompletion(modelVersion, completionId),
        onCachedArtifactVerified:
            ({required modelVersion, required completionId}) =>
                counter.reconcileCompletion(modelVersion, completionId),
      ).downloadAndActivate(manifest);

      expect(source.requestedStarts, [0]);
      expect(
        await counter.count(manifest.version),
        1,
        reason: 'migration replaces one legacy marker; it is not a transfer',
      );
    },
  );

  test(
    'cached cross-version reactivation preserves the original completion',
    () async {
      final bytesA = utf8.encode('verified-model-version-a');
      final bytesB = utf8.encode('verified-model-version-b');
      final manifestA = _manifestFor(
        bytesA,
        id: 'test-model-a',
        version: 'v-a',
      );
      final manifestB = _manifestFor(
        bytesB,
        id: 'test-model-b',
        version: 'v-b',
      );
      final sourceA = _MemoryRangeSource(bytesA);
      final sourceB = _MemoryRangeSource(bytesB);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final counter = DownloadCounter(
        database,
        generateEventId: () => 'unused-random-event',
        nowUtc: () => DateTime.utc(2026, 7, 30, 8),
      );

      ModelDownloadManager buildManager(
        ModelManifest manifest,
        ModelByteSource source,
      ) {
        return ModelDownloadManager(
          repository: DriftModelDownloadRepository(database),
          source: source,
          verifier: _RecordingVerifier(),
          modelDirectory: () async => directory,
          nowUtc: () => DateTime.utc(2026, 7, 30, 8),
          onVerifiedActivation:
              ({required modelVersion, required completionId}) =>
                  counter.recordCompletion(modelVersion, completionId),
        );
      }

      await buildManager(manifestA, sourceA).downloadAndActivate(manifestA);
      await buildManager(manifestB, sourceB).downloadAndActivate(manifestB);
      await buildManager(manifestA, sourceA).downloadAndActivate(manifestA);

      expect(sourceA.requestedStarts, [0]);
      expect(sourceB.requestedStarts, [0]);
      expect(await counter.count(manifestA.version), 1);
      expect(await counter.count(manifestB.version), 1);
    },
  );

  test('rejects a mismatched Content-Range before appending', () async {
    final bytes = utf8.encode('range-protected-model');
    final manifest = _manifestFor(bytes);
    final partial = File(
      '${directory.path}${Platform.pathSeparator}'
      '${manifest.fileStem}.tflite.partial',
    );
    await partial.writeAsBytes(bytes.take(5).toList(), flush: true);
    final source = _MemoryRangeSource(bytes, reportedRangeStart: 0);
    final manager = ModelDownloadManager(
      repository: repository,
      source: source,
      verifier: _RecordingVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 7, 30, 8),
    );

    await expectLater(
      manager.downloadAndActivate(manifest),
      throwsA(
        isA<ModelLifecycleException>().having(
          (error) => error.code,
          'code',
          ModelFailureCode.invalidResponse,
        ),
      ),
    );

    expect(await partial.length(), 5);
    expect(repository.activations, 0);
  });

  test('checksum mismatch never activates corrupt bytes', () async {
    final expected = utf8.encode('expected-model');
    final received = utf8.encode('corrupt--model');
    expect(received.length, expected.length);
    final manifest = _manifestFor(expected);
    final manager = ModelDownloadManager(
      repository: repository,
      source: _MemoryRangeSource(received),
      verifier: _RecordingVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 7, 30, 8),
    );

    await expectLater(
      manager.downloadAndActivate(manifest),
      throwsA(
        isA<ModelLifecycleException>().having(
          (error) => error.code,
          'code',
          ModelFailureCode.checksumMismatch,
        ),
      ),
    );

    expect(repository.activations, 0);
    expect(repository.record!.state, ModelDownloadState.failed);
    expect(repository.record!.failureCode, ModelFailureCode.checksumMismatch);
    expect(
      await File(
        '${directory.path}${Platform.pathSeparator}'
        '${manifest.fileStem}.tflite.partial',
      ).exists(),
      isFalse,
    );
  });

  test(
    'cancellation preserves resumable bytes and records honest state',
    () async {
      final bytes = utf8.encode('download-that-will-be-cancelled');
      final manifest = _manifestFor(bytes);
      final cancellation = ModelCancellation();
      final source = _MemoryRangeSource(
        bytes,
        onChunk: (index) {
          if (index == 0) cancellation.cancel();
        },
        chunkSize: 5,
      );
      final manager = ModelDownloadManager(
        repository: repository,
        source: source,
        verifier: _RecordingVerifier(),
        modelDirectory: () async => directory,
        nowUtc: () => DateTime.utc(2026, 7, 30, 8),
      );

      await expectLater(
        manager.downloadAndActivate(manifest, cancellation: cancellation),
        throwsA(
          isA<ModelLifecycleException>().having(
            (error) => error.code,
            'code',
            ModelFailureCode.cancelled,
          ),
        ),
      );

      expect(repository.record!.state, ModelDownloadState.cancelled);
      expect(repository.record!.downloadedBytes, 5);
      expect(repository.activations, 0);
    },
  );

  test(
    'f44 review removal serializes with the active model download authority',
    () async {
      final bytes = utf8.encode('serialized-model-removal');
      final manifest = _manifestFor(bytes);
      final source = _BlockingModelSource(bytes);
      final manager = ModelDownloadManager(
        repository: repository,
        source: source,
        verifier: _RecordingVerifier(),
        modelDirectory: () async => directory,
        nowUtc: () => DateTime.utc(2026, 7, 30, 8),
      );

      final download = manager.downloadAndActivate(manifest);
      await source.started.future;
      var removalCompleted = false;
      var removedRecords = 0;
      final removal = manager
          .removeInstalled(
            manifest,
            removeRecord: () async {
              removedRecords += 1;
              repository.record = null;
            },
          )
          .whenComplete(() => removalCompleted = true);

      await Future<void>.delayed(Duration.zero);
      expect(removalCompleted, isFalse);
      source.release.complete();
      final activated = await download;
      expect(await File(activated.localPath!).exists(), isTrue);

      expect(await removal, bytes.length);
      expect(await File(activated.localPath!).exists(), isFalse);
      expect(repository.record, isNull);
      expect(removedRecords, 1);
    },
  );

  test('dispose cancels and waits for an active download', () async {
    final bytes = utf8.encode('stalled-download');
    final manifest = _manifestFor(bytes);
    final source = _CancellationAwareSource();
    final manager = ModelDownloadManager(
      repository: repository,
      source: source,
      verifier: _RecordingVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 7, 30, 8),
    );

    final operation = manager.downloadAndActivate(manifest);
    final assertion = expectLater(
      operation,
      throwsA(
        isA<ModelLifecycleException>().having(
          (error) => error.code,
          'code',
          ModelFailureCode.cancelled,
        ),
      ),
    );
    await source.started.future;

    await manager.dispose();

    await assertion;
    expect(source.finished.isCompleted, isTrue);
    expect(repository.record!.state, ModelDownloadState.cancelled);
    expect(() => manager.downloadAndActivate(manifest), throwsStateError);
  });
}

ModelManifest _manifestFor(
  List<int> bytes, {
  String id = 'test-model',
  String version = 'v1',
}) => ModelManifest(
  id: id,
  version: version,
  minimumAppVersion: '1.0.0+1',
  sourceUri: Uri.https('models.example', '/test.tflite'),
  license: 'Apache-2.0',
  licenseUri: Uri.https('models.example', '/LICENSE'),
  expectedSha256: sha256.convert(bytes).toString(),
  expectedBytes: bytes.length,
  inputShape: const [1, 1, 1, 1],
  inputType: ModelTensorType.uint8,
  outputShape: const [1, 1],
  outputType: ModelTensorType.uint8,
  inputEncoding: ModelInputEncoding.rawUint8Rgb,
  labelAssetName: 'labels.txt',
  supportedDelegates: const {ModelDelegate.cpu},
);

final class _MemoryModelDownloadRepository implements ModelDownloadRepository {
  ModelDownloadRecord? record;
  int activations = 0;

  @override
  Future<void> activate(ModelDownloadRecord next) async {
    activations += 1;
    record = next.copyWith(state: ModelDownloadState.active);
  }

  @override
  Future<ModelDownloadRecord?> find(String id) async => record;

  @override
  Future<void> save(ModelDownloadRecord next) async {
    record = next;
  }
}

final class _MemoryRangeSource implements ModelByteSource {
  _MemoryRangeSource(
    this.bytes, {
    this.ignoreRange = false,
    this.onChunk,
    this.chunkSize = 1024,
    this.reportedRangeStart,
  });

  final List<int> bytes;
  final bool ignoreRange;
  final void Function(int index)? onChunk;
  final int chunkSize;
  final int? reportedRangeStart;
  final List<int> requestedStarts = [];

  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) async {
    requestedStarts.add(start);
    final actualStart = ignoreRange ? 0 : start;
    final chunks = <List<int>>[];
    for (var offset = actualStart; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      chunks.add(bytes.sublist(offset, end));
    }
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () async {
        for (var index = 0; index < chunks.length; index += 1) {
          controller.add(chunks[index]);
          onChunk?.call(index);
          await Future<void>.delayed(Duration.zero);
        }
        await controller.close();
      },
    );
    return ModelByteResponse(
      statusCode: ignoreRange || start == 0 ? 200 : 206,
      bytes: controller.stream,
      contentRangeStart: ignoreRange || start == 0
          ? null
          : reportedRangeStart ?? start,
    );
  }
}

final class _CancellationAwareSource implements ModelByteSource {
  final Completer<void> started = Completer<void>();
  final Completer<void> finished = Completer<void>();

  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) async {
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () async {
        started.complete();
        await cancellation!.whenCancelled;
        controller.addError(
          const ModelLifecycleException(ModelFailureCode.cancelled),
        );
        await controller.close();
        finished.complete();
      },
    );
    return ModelByteResponse(statusCode: 200, bytes: controller.stream);
  }
}

final class _BlockingModelSource implements ModelByteSource {
  _BlockingModelSource(this.bytes);

  final List<int> bytes;
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) async {
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () async {
        started.complete();
        await release.future;
        controller.add(bytes.sublist(start));
        await controller.close();
      },
    );
    return ModelByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: controller.stream,
    );
  }
}

final class _RecordingVerifier implements ModelFileVerifier {
  final List<String> paths = [];

  @override
  Future<void> verify(String path, ModelManifest manifest) async {
    paths.add(path);
  }
}
