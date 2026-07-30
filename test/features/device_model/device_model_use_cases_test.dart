import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/application/device_model_use_cases.dart';
import 'package:vocab_learning_app/features/device_model/application/model_download_manager.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';

void main() {
  test('open verifies checksum again before creating a runtime', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-model-use-case-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bytes = utf8.encode('model');
    final file = File('${directory.path}${Platform.pathSeparator}model.tflite');
    await file.writeAsBytes(bytes);
    final manifest = ModelManifest(
      id: 'vision',
      version: '1',
      minimumAppVersion: '1.0.0+1',
      sourceUri: Uri.https('models.example', '/model.tflite'),
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
      supportedDelegates: const {ModelDelegate.cpu, ModelDelegate.xnnpack},
    );
    final repository = _UseCaseRepository(
      ModelDownloadRecord(
        id: manifest.recordId,
        modelVersion: manifest.version,
        sourceUrl: manifest.sourceUri.toString(),
        expectedChecksum: manifest.expectedSha256,
        expectedBytes: manifest.expectedBytes,
        downloadedBytes: bytes.length,
        retryCount: 0,
        state: ModelDownloadState.active,
        updatedAtUtc: DateTime.utc(2026, 7, 30),
        localPath: file.path,
      ),
    );
    final runtime = _FakeImageRuntime();
    final useCases = DeviceModelUseCases(
      manifest: manifest,
      repository: repository,
      downloadManager: _uncalledDownloadManager(),
      openRuntime:
          ({required path, required manifest, required delegate}) async =>
              runtime,
    );

    expect(await useCases.openActive(), same(runtime));

    await file.writeAsBytes(utf8.encode('bad!!'));
    await expectLater(
      useCases.openActive(),
      throwsA(
        isA<ModelLifecycleException>().having(
          (error) => error.code,
          'code',
          ModelFailureCode.checksumMismatch,
        ),
      ),
    );
    expect(repository.record.state, ModelDownloadState.failed);
  });
}

final class _UseCaseRepository implements ModelDownloadRepository {
  _UseCaseRepository(this.record);

  ModelDownloadRecord record;

  @override
  Future<void> activate(ModelDownloadRecord next) async {
    record = next;
  }

  @override
  Future<ModelDownloadRecord?> find(String id) async => record;

  @override
  Future<void> save(ModelDownloadRecord next) async {
    record = next;
  }
}

ModelDownloadManager _uncalledDownloadManager() => ModelDownloadManager(
  repository: _ThrowingRepository(),
  source: _ThrowingSource(),
  verifier: _ThrowingVerifier(),
  modelDirectory: _throwingDirectory,
  nowUtc: DateTime.now,
);

Future<Directory> _throwingDirectory() => throw UnimplementedError();

final class _ThrowingRepository implements ModelDownloadRepository {
  @override
  Future<void> activate(ModelDownloadRecord record) =>
      throw UnimplementedError();

  @override
  Future<ModelDownloadRecord?> find(String id) => throw UnimplementedError();

  @override
  Future<void> save(ModelDownloadRecord record) => throw UnimplementedError();
}

final class _ThrowingSource implements ModelByteSource {
  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) => throw UnimplementedError();
}

final class _ThrowingVerifier implements ModelFileVerifier {
  @override
  Future<void> verify(String path, ModelManifest manifest) =>
      throw UnimplementedError();
}

final class _FakeImageRuntime implements ImageClassifierRuntime {
  @override
  ModelDelegate get delegate => ModelDelegate.xnnpack;

  @override
  Future<List<ModelClassification>> classify(
    Uint8List rgbBytes, {
    int topK = 5,
  }) async => const [];

  @override
  void close() {}

  @override
  Future<void> run(Uint8List input) async {}
}
