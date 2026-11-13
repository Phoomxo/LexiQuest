import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/device_model/application/device_model_use_cases.dart';
import 'package:vocab_learning_app/features/device_model/application/model_download_manager.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as domain_owner;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/image_preprocessor.dart';
import 'package:vocab_learning_app/features/media_practice/application/object_scanner_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';

void main() {
  Future<
    ({
      AppDatabase database,
      LocalOwnerRepository owners,
      VocabularyUseCases vocabulary,
      ObjectScannerUseCases scanner,
    })
  >
  selectedSetFixture({
    LocalOwnerRepository Function(DriftLocalOwnerRepository, AppDatabase)?
    ownerBoundary,
  }) async {
    final directory = await Directory.systemTemp.createTemp('scanner-set-');
    addTearDown(() => directory.delete(recursive: true));
    final modelBytes = utf8.encode('verified-test-model');
    final modelFile = File('${directory.path}/model.tflite');
    await modelFile.writeAsBytes(modelBytes);
    final manifest = _manifest(modelBytes);
    final models = _ModelRepository(_activeRecord(manifest, modelFile.path));
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var id = 0;
    final persistentOwners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner-${id++}',
      nowUtc: () => DateTime.utc(2026, 11, 13),
    );
    final owners =
        ownerBoundary?.call(persistentOwners, database) ?? persistentOwners;
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'id-${id++}',
      nowUtc: () => DateTime.utc(2026, 11, 13),
    );
    final scanner = ObjectScannerUseCases(
      camera: _FakeCamera(),
      deviceModels: DeviceModelUseCases(
        manifest: manifest,
        repository: models,
        downloadManager: _uncalledManager(models, directory),
        openRuntime:
            ({required path, required manifest, required delegate}) async =>
                _FakeRuntime(),
      ),
      vocabulary: vocabulary,
      preprocessor: _FakePreprocessor(),
    );
    await scanner.initialize();
    return (
      database: database,
      owners: owners,
      vocabulary: vocabulary,
      scanner: scanner,
    );
  }

  test(
    'standalone confirmation rejects an owner switch inside category creation',
    () async {
      late _SwitchOwnerOnLookup owners;
      final fixture = await selectedSetFixture(
        ownerBoundary: (persistent, database) =>
            owners = _SwitchOwnerOnLookup(persistent, database),
      );
      final owner = await owners.getOrCreateActiveOwner();
      final result = await fixture.scanner.captureAndClassify();
      owners.switchOnLookup = owners.lookupCount + 4;

      await expectLater(
        fixture.scanner.accept(result, expectedOwnerId: owner.id),
        throwsA(isA<VocabularyNotFoundFailure>()),
      );

      expect(owners.switched, isTrue);
      expect(
        await fixture.database
            .select(fixture.database.vocabularyCategories)
            .get(),
        isEmpty,
      );
      expect(
        await fixture.database.select(fixture.database.vocabularyWords).get(),
        isEmpty,
      );
      expect(
        await fixture.database.select(fixture.database.outboxOperations).get(),
        isEmpty,
      );
    },
  );

  test(
    'selected-set confirmation rejects an owner switch inside word creation',
    () async {
      late _SwitchOwnerOnLookup owners;
      final fixture = await selectedSetFixture(
        ownerBoundary: (persistent, database) =>
            owners = _SwitchOwnerOnLookup(persistent, database),
      );
      final category = await fixture.vocabulary.createCategory(
        'Synthetic camera set',
      );
      final owner = await owners.getOrCreateActiveOwner();
      final result = await fixture.scanner.captureAndClassify();
      final outboxBefore = await fixture.database
          .select(fixture.database.outboxOperations)
          .get();
      owners.switchOnLookup = owners.lookupCount + 6;

      await expectLater(
        fixture.scanner.accept(
          result,
          categoryId: category.id,
          expectedOwnerId: owner.id,
        ),
        throwsA(isA<VocabularyNotFoundFailure>()),
      );

      expect(owners.switched, isTrue);
      final categories = await fixture.database
          .select(fixture.database.vocabularyCategories)
          .get();
      expect(categories, hasLength(1));
      expect(categories.single.ownerId, owner.id);
      expect(
        await fixture.database.select(fixture.database.vocabularyWords).get(),
        isEmpty,
      );
      expect(
        await fixture.database.select(fixture.database.outboxOperations).get(),
        outboxBefore,
      );
    },
  );

  test(
    'selected-set acceptance preserves destination and deduplicates',
    () async {
      final fixture = await selectedSetFixture();
      final category = await fixture.vocabulary.createCategory(
        'Synthetic travel',
      );
      final owner = await fixture.owners.getOrCreateActiveOwner();
      final result = await fixture.scanner.captureAndClassify();
      final word = await fixture.scanner.accept(
        result,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );
      final duplicate = await fixture.scanner.accept(
        result,
        categoryId: category.id,
        expectedOwnerId: owner.id,
      );

      expect(word.categoryId, category.id);
      expect(duplicate.id, word.id);
      expect(await fixture.vocabulary.watchCategories().first, hasLength(1));
      expect(
        await fixture.vocabulary.watchWords(category.id).first,
        hasLength(1),
      );
    },
  );

  test(
    'owner switch before confirmation writes no words or new category',
    () async {
      final fixture = await selectedSetFixture();
      final category = await fixture.vocabulary.createCategory(
        'Synthetic travel',
      );
      final owner = await fixture.owners.getOrCreateActiveOwner();
      final result = await fixture.scanner.captureAndClassify();
      await fixture.database.customStatement(
        'UPDATE local_owners SET is_active = 0',
      );
      final nextOwner = await fixture.owners.getOrCreateActiveOwner();
      expect(nextOwner.id, isNot(owner.id));

      await expectLater(
        fixture.scanner.accept(
          result,
          categoryId: category.id,
          expectedOwnerId: owner.id,
        ),
        throwsA(isA<VocabularyNotFoundFailure>()),
      );
      expect(
        await fixture.database.select(fixture.database.vocabularyWords).get(),
        isEmpty,
      );
      expect(
        await fixture.database
            .select(fixture.database.vocabularyCategories)
            .get(),
        hasLength(1),
      );
    },
  );

  test('missing selected set fails without creating a replacement', () async {
    final fixture = await selectedSetFixture();
    final owner = await fixture.owners.getOrCreateActiveOwner();
    final result = await fixture.scanner.captureAndClassify();
    await expectLater(
      fixture.scanner.accept(
        result,
        categoryId: 'category:missing',
        expectedOwnerId: owner.id,
      ),
      throwsA(isA<VocabularyNotFoundFailure>()),
    );
    expect(await fixture.vocabulary.watchCategories().first, isEmpty);
    expect(
      await fixture.database.select(fixture.database.vocabularyWords).get(),
      isEmpty,
    );
  });

  test('denied camera permission stops before initialization', () async {
    final camera = _FakeCamera()
      ..permission = MediaPermissionState.permanentlyDenied;
    final scanner = ObjectScannerUseCases(
      camera: camera,
      deviceModels: _unavailableDeviceModels(),
      vocabulary: _throwingVocabulary(),
      preprocessor: _FakePreprocessor(),
    );

    await expectLater(
      scanner.initialize(),
      throwsA(
        isA<CameraPracticeException>().having(
          (error) => error.code,
          'code',
          CameraFailureCode.permissionPermanentlyDenied,
        ),
      ),
    );

    expect(camera.initializeCalls, 0);
  });

  test(
    'rejects camera initialization that completes without readiness',
    () async {
      final camera = _FakeCamera()..completeWithoutReadiness = true;
      final scanner = ObjectScannerUseCases(
        camera: camera,
        deviceModels: _unavailableDeviceModels(),
        vocabulary: _throwingVocabulary(),
        preprocessor: _FakePreprocessor(),
      );

      await expectLater(
        scanner.initialize(),
        throwsA(
          isA<CameraPracticeException>().having(
            (error) => error.code,
            'code',
            CameraFailureCode.initializationFailed,
          ),
        ),
      );
    },
  );

  test('rejects camera resume that completes without readiness', () async {
    final camera = _FakeCamera()..completeWithoutReadiness = true;
    final scanner = ObjectScannerUseCases(
      camera: camera,
      deviceModels: _unavailableDeviceModels(),
      vocabulary: _throwingVocabulary(),
      preprocessor: _FakePreprocessor(),
    );

    await expectLater(
      scanner.resume(),
      throwsA(
        isA<CameraPracticeException>().having(
          (error) => error.code,
          'code',
          CameraFailureCode.initializationFailed,
        ),
      ),
    );
  });

  test(
    'classifies captured bytes and persists accepted word locally',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'scanner-usecase-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final modelBytes = utf8.encode('verified-test-model');
      final modelFile = File('${directory.path}/model.tflite');
      await modelFile.writeAsBytes(modelBytes);
      final manifest = _manifest(modelBytes);
      final runtime = _FakeRuntime();
      ModelDelegate? openedDelegate;
      final repository = _ModelRepository(
        _activeRecord(manifest, modelFile.path),
      );
      final deviceModels = DeviceModelUseCases(
        manifest: manifest,
        repository: repository,
        downloadManager: _uncalledManager(repository, directory),
        openRuntime:
            ({required path, required manifest, required delegate}) async {
              openedDelegate = delegate;
              return runtime;
            },
      );
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      var id = 0;
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner-${id++}',
        nowUtc: () => DateTime.utc(2026, 7, 30),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: () => 'id-${id++}',
        nowUtc: () => DateTime.utc(2026, 7, 30),
      );
      final camera = _FakeCamera();
      final scanner = ObjectScannerUseCases(
        camera: camera,
        deviceModels: deviceModels,
        vocabulary: vocabulary,
        preprocessor: _FakePreprocessor(),
      );

      await scanner.initialize();
      expect(openedDelegate, ModelDelegate.cpu);
      final result = await scanner.captureAndClassify();
      final accepted = await scanner.accept(result);

      expect(result.primary.label, 'Apple');
      expect(result.primary.confidence, 0.92);
      expect(result.matchedClassification?.label, 'Apple');
      expect(result.vocabulary?.englishWord, 'apple');
      expect(result.modelId, manifest.id);
      expect(
        accepted.source,
        'object-scanner:${manifest.id}@${manifest.version}',
      );
      expect(
        await database.select(database.vocabularyWords).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(2),
      );

      final duplicate = await scanner.accept(result);
      expect(duplicate.id, accepted.id);
      expect(
        await database.select(database.vocabularyWords).get(),
        hasLength(1),
      );
    },
  );

  test('keeps confidence paired with the classification that mapped', () async {
    final directory = await Directory.systemTemp.createTemp('scanner-map-');
    addTearDown(() => directory.delete(recursive: true));
    final modelBytes = utf8.encode('verified-test-model');
    final modelFile = File('${directory.path}/model.tflite');
    await modelFile.writeAsBytes(modelBytes);
    final manifest = _manifest(modelBytes);
    final repository = _ModelRepository(
      _activeRecord(manifest, modelFile.path),
    );
    final runtime = _FakeRuntime()
      ..classifications = const [
        ModelClassification(index: 2, label: 'Unknown', confidence: 0.98),
        ModelClassification(index: 1, label: 'Apple', confidence: 0.73),
      ];
    final scanner = ObjectScannerUseCases(
      camera: _FakeCamera(),
      deviceModels: DeviceModelUseCases(
        manifest: manifest,
        repository: repository,
        downloadManager: _uncalledManager(repository, directory),
        openRuntime:
            ({required path, required manifest, required delegate}) async =>
                runtime,
      ),
      vocabulary: _throwingVocabulary(),
      preprocessor: _FakePreprocessor(),
    );

    await scanner.initialize();
    final result = await scanner.captureAndClassify();

    expect(result.primary.label, 'Unknown');
    expect(result.matchedClassification?.label, 'Apple');
    expect(result.matchedClassification?.confidence, 0.73);
    expect(result.vocabulary?.englishWord, 'apple');
  });

  test('reports no match for uncertain predictions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'scanner-no-match-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final modelBytes = utf8.encode('verified-test-model');
    final modelFile = File('${directory.path}/model.tflite');
    await modelFile.writeAsBytes(modelBytes);
    final manifest = _manifest(modelBytes);
    final repository = _ModelRepository(
      _activeRecord(manifest, modelFile.path),
    );
    final runtime = _FakeRuntime()
      ..classifications = const [
        ModelClassification(index: 0, label: 'background', confidence: 0.99),
        ModelClassification(index: 1, label: 'Apple', confidence: 0.14),
      ];
    final scanner = ObjectScannerUseCases(
      camera: _FakeCamera(),
      deviceModels: DeviceModelUseCases(
        manifest: manifest,
        repository: repository,
        downloadManager: _uncalledManager(repository, directory),
        openRuntime:
            ({required path, required manifest, required delegate}) async =>
                runtime,
      ),
      vocabulary: _throwingVocabulary(),
      preprocessor: _FakePreprocessor(),
    );

    await scanner.initialize();

    await expectLater(
      scanner.captureAndClassify(),
      throwsA(
        isA<CameraPracticeException>().having(
          (error) => error.code,
          'code',
          CameraFailureCode.noConfidentMatch,
        ),
      ),
    );
  });
}

final class _SwitchOwnerOnLookup implements LocalOwnerRepository {
  _SwitchOwnerOnLookup(this.persistent, this.database);

  final DriftLocalOwnerRepository persistent;
  final AppDatabase database;
  var lookupCount = 0;
  int? switchOnLookup;
  var switched = false;

  @override
  Future<domain_owner.LocalOwner> getOrCreateActiveOwner() async {
    lookupCount++;
    if (lookupCount == switchOnLookup) {
      switched = true;
      await database.customStatement('UPDATE local_owners SET is_active = 0');
    }
    return persistent.getOrCreateActiveOwner();
  }

  @override
  Future<domain_owner.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => persistent.bindFirebaseUid(ownerId, firebaseUid);
}

ModelManifest _manifest(List<int> bytes) => ModelManifest(
  id: 'scanner-model',
  version: 'v1',
  minimumAppVersion: '1.0.0+1',
  sourceUri: Uri.https('models.example', '/scanner.tflite'),
  license: 'Apache-2.0',
  licenseUri: Uri.https('models.example', '/LICENSE'),
  expectedSha256: sha256.convert(bytes).toString(),
  expectedBytes: bytes.length,
  inputShape: const [1, 224, 224, 3],
  inputType: ModelTensorType.uint8,
  outputShape: const [1, 2],
  outputType: ModelTensorType.uint8,
  inputEncoding: ModelInputEncoding.rawUint8Rgb,
  labelAssetName: 'labels.txt',
  supportedDelegates: const {ModelDelegate.cpu, ModelDelegate.xnnpack},
);

ModelDownloadRecord _activeRecord(ModelManifest manifest, String path) {
  return ModelDownloadRecord(
    id: manifest.recordId,
    modelVersion: manifest.version,
    sourceUrl: manifest.sourceUri.toString(),
    expectedChecksum: manifest.expectedSha256,
    expectedBytes: manifest.expectedBytes,
    downloadedBytes: manifest.expectedBytes,
    retryCount: 0,
    state: ModelDownloadState.active,
    updatedAtUtc: DateTime.utc(2026, 7, 30),
    localPath: path,
  );
}

ModelDownloadManager _uncalledManager(
  ModelDownloadRepository repository,
  Directory directory,
) {
  return ModelDownloadManager(
    repository: repository,
    source: _UncalledSource(),
    verifier: _UncalledVerifier(),
    modelDirectory: () async => directory,
    nowUtc: () => DateTime.utc(2026, 7, 30),
  );
}

DeviceModelUseCases _unavailableDeviceModels() {
  final repository = _ModelRepository(null);
  return DeviceModelUseCases(
    manifest: ModelManifest.fieldImageClassifier,
    repository: repository,
    downloadManager: _uncalledManager(repository, Directory.systemTemp),
    openRuntime: ({required path, required manifest, required delegate}) =>
        throw UnimplementedError(),
  );
}

VocabularyUseCases _throwingVocabulary() => VocabularyUseCases(
  owners: _ThrowingOwners(),
  vocabulary: _ThrowingVocabularyRepository(),
  generateId: () => throw UnimplementedError(),
  nowUtc: () => DateTime.utc(2026, 7, 30),
);

final class _FakeCamera implements CameraGateway {
  MediaPermissionState permission = MediaPermissionState.granted;
  bool completeWithoutReadiness = false;
  int initializeCalls = 0;
  @override
  bool isInitialized = false;

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<CapturedImage> capture() async => CapturedImage(
    bytes: Uint8List.fromList([1, 2, 3]),
    capturedAtUtc: DateTime.utc(2026, 7, 30),
    rotationDegrees: 90,
  );

  @override
  Future<void> dispose() async {
    isInitialized = false;
  }

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    isInitialized = !completeWithoutReadiness;
  }

  @override
  Future<void> pause() async {
    isInitialized = false;
  }

  @override
  Future<MediaPermissionState> requestPermission() async => permission;

  @override
  Future<void> resume() => initialize();
}

final class _FakePreprocessor implements ImagePreprocessor {
  @override
  Uint8List toRawRgb224(Uint8List encodedBytes) => Uint8List(224 * 224 * 3);
}

final class _FakeRuntime implements ImageClassifierRuntime {
  List<ModelClassification> classifications = const [
    ModelClassification(index: 1, label: 'Apple', confidence: 0.92),
    ModelClassification(index: 0, label: 'background', confidence: 0.05),
  ];

  @override
  ModelDelegate get delegate => ModelDelegate.xnnpack;

  @override
  Future<List<ModelClassification>> classify(
    Uint8List rgbBytes, {
    int topK = 5,
  }) async => classifications;

  @override
  void close() {}

  @override
  Future<void> run(Uint8List input) async {}
}

final class _ModelRepository implements ModelDownloadRepository {
  _ModelRepository(this.record);
  ModelDownloadRecord? record;

  @override
  Future<void> activate(ModelDownloadRecord record) async {
    this.record = record;
  }

  @override
  Future<ModelDownloadRecord?> find(String id) async => record;

  @override
  Future<void> save(ModelDownloadRecord record) async {
    this.record = record;
  }
}

final class _UncalledSource implements ModelByteSource {
  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) => throw UnimplementedError();
}

final class _UncalledVerifier implements ModelFileVerifier {
  @override
  Future<void> verify(String path, ModelManifest manifest) =>
      throw UnimplementedError();
}

// These throwers are never reached by the permission-denial test.
final class _ThrowingOwners implements LocalOwnerRepository {
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _ThrowingVocabularyRepository implements VocabularyRepository {
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
