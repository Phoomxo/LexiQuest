import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/device_model/data/drift_model_download_repository.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';

void main() {
  late AppDatabase database;
  late DriftModelDownloadRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftModelDownloadRepository(database);
  });

  tearDown(() => database.close());

  test('persists resumable progress and typed failure state', () async {
    final record = _record(
      id: 'vision@1',
      version: '1',
      state: ModelDownloadState.failed,
      failureCode: ModelFailureCode.checksumMismatch,
      downloadedBytes: 12,
    );

    await repository.save(record);
    final restored = await repository.find(record.id);

    expect(restored!.downloadedBytes, 12);
    expect(restored.state, ModelDownloadState.failed);
    expect(restored.failureCode, ModelFailureCode.checksumMismatch);
    expect(restored.updatedAtUtc.isUtc, isTrue);
  });

  test('activation demotes the previous model in one transaction', () async {
    final previous = _record(
      id: 'vision@1',
      version: '1',
      state: ModelDownloadState.ready,
    );
    final next = _record(
      id: 'vision@2',
      version: '2',
      state: ModelDownloadState.ready,
    );
    await repository.save(previous);
    await repository.activate(previous);
    await repository.save(next);

    await repository.activate(next);

    expect(
      (await repository.find(previous.id))!.state,
      ModelDownloadState.ready,
    );
    expect((await repository.find(next.id))!.state, ModelDownloadState.active);
  });
}

ModelDownloadRecord _record({
  required String id,
  required String version,
  required ModelDownloadState state,
  ModelFailureCode? failureCode,
  int downloadedBytes = 20,
}) {
  return ModelDownloadRecord(
    id: id,
    modelVersion: version,
    sourceUrl: 'https://models.example/$version.tflite',
    expectedChecksum: 'a' * 64,
    expectedBytes: 20,
    downloadedBytes: downloadedBytes,
    retryCount: 1,
    state: state,
    updatedAtUtc: DateTime.utc(2026, 7, 30, 8),
    localPath: 'models/$version.tflite',
    failureCode: failureCode,
  );
}
