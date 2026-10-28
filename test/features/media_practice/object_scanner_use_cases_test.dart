import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../../support/inert_research_dependencies.dart';
import '../../support/test_quest_use_cases.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/device_model/application/device_model_use_cases.dart';
import 'package:vocab_learning_app/features/device_model/application/model_download_manager.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/media_practice/application/image_preprocessor.dart';
import 'package:vocab_learning_app/features/media_practice/application/object_scanner_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';

void main() {
  test(
    'F01 scanner attempts camera cleanup after runtime close failure once',
    () async {
      final h = await _scannerHarness();
      final failure = StateError('runtime close failed');
      h.runtime.closeFailure = failure;
      try {
        await expectLater(h.scanner.dispose(), throwsA(same(failure)));
        await expectLater(h.scanner.dispose(), throwsA(same(failure)));
        expect(h.runtime.closeCalls, 1);
        expect(h.camera.disposeCalls, 1);
      } finally {
        await h.cleanupAfterDispose();
      }
    },
  );
  test(
    'B11 owner replacement during inference cannot publish old scan',
    () async {
      final h = await _scannerHarness();
      final pending = Completer<void>();
      final entered = Completer<void>();
      h.runtime.classifyPending = pending;
      h.runtime.classifyEntered = entered;
      final capture = h.scanner.captureAndClassify();
      final rejected = expectLater(
        capture,
        throwsA(isA<CameraPracticeException>()),
      );
      await entered.future;
      await h.database.customStatement('UPDATE local_owners SET is_active = 0');
      await h.owners.getOrCreateActiveOwner();
      pending.complete();
      await rejected;
      expect(
        await h.database.select(h.database.outboxOperations).get(),
        isEmpty,
      );
    },
  );

  testWidgets(
    'B11 real scanner UI saves into vocabulary and reopens after restart',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('b11-ui-restart-'),
      ))!;
      final file = File('${directory.path}/vocabulary.sqlite');
      final original = AppDatabase(NativeDatabase(file));
      var originalClosed = false;
      addTearDown(
        () => tester.runAsync(() async {
          if (!originalClosed) await original.close();
          debugPrint('B11 stage original closed');
          if (await directory.exists()) await directory.delete(recursive: true);
        }),
      );
      Widget app(AppDatabase db, VocabularyUseCases vocabulary, Widget home) {
        final research = InertResearchDependencies(db);
        return AppDependenciesScope(
          dependencies: AppDependencies(
            initialRoute: AppRoute.home,
            runtimeStatus: const AppRuntimeStatus(
              localData: RuntimeAvailability.ready,
              firebase: RuntimeAvailability.unavailable,
              supabase: RuntimeAvailability.unavailable,
              backends: RuntimeAvailability.unavailable,
            ),
            config: null,
            guestSessionService: _NoGuest(),
            quest: testQuestUseCases(),
            experiments: research.experiments,
            consents: research.consents,
            experimentAssignments: research.experimentAssignments,
            assignedLearningEventContext: research.assignedLearningEventContext,
            evidencePolicyRolloutModeProvider:
                research.evidencePolicyRolloutModeProvider,
            database: db,
            vocabulary: vocabulary,
          ),
          child: MaterialApp(home: home),
        );
      }

      final h = (await tester.runAsync(
        () => _scannerHarness(databaseOverride: original, widgetTester: tester),
      ))!;
      Future<void> drain(Future<void> operation) async {
        var done = false;
        Object? failure;
        operation.then(
          (_) => done = true,
          onError: (Object error) {
            failure = error;
            done = true;
          },
        );
        for (var i = 0; i < 100 && !done; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(
          done,
          isTrue,
          reason:
              'Database close must drain real I/O and widget-zone stream cancellation',
        );
        if (failure != null) throw failure!;
      }

      Future<void> until(Finder finder) async {
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          if (finder.evaluate().isNotEmpty) return;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        fail(
          'Missing expected UI: $finder; visible: ${tester.widgetList<Text>(find.byType(Text)).map((e) => e.data).toList()}',
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ObjectScannerScreen(
            scanner: h.scanner,
            voice: VoiceUseCases(
              provider: _NoAudioVoice(),
              disposeProvider: () async {},
            ),
          ),
        ),
      );
      final capture = find.byKey(
        const ValueKey('object-scanner-capture-button'),
      );
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (tester.widget<FilledButton>(capture).onPressed != null) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(tester.widget<FilledButton>(capture).onPressed, isNotNull);
      await tester.tap(capture);
      await until(find.text('เพิ่มเข้าคลัง'));
      expect(find.text('apple'), findsOneWidget);
      expect(find.text('บันทึกแล้ว'), findsNothing);
      await tester.tap(find.text('เพิ่มเข้าคลัง'));
      await until(find.text('บันทึกแล้ว'));
      debugPrint('B11 stage saved');
      await tester.pumpWidget(
        app(original, h.scanner.vocabulary, const CategoriesPage()),
      );
      await until(find.text('Food & Drinks'));
      await tester.tap(find.text('Food & Drinks'));
      await until(find.text('apple'));
      debugPrint('B11 stage vocabulary visible');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await drain(h.scanner.dispose());
      await drain(original.close());
      originalClosed = true;
      debugPrint('B11 stage original closed');
      final reopened = AppDatabase(NativeDatabase(file));
      var reopenedClosed = false;
      addTearDown(
        () => tester.runAsync(() async {
          if (!reopenedClosed) await reopened.close();
        }),
      );
      final vocabulary = VocabularyUseCases(
        owners: DriftLocalOwnerRepository(
          reopened,
          generateId: () => 'must-not-create',
          nowUtc: () => DateTime.utc(2026, 9, 13),
        ),
        vocabulary: DriftVocabularyRepository(reopened),
        generateId: () => 'must-not-write',
        nowUtc: () => DateTime.utc(2026, 9, 13),
      );
      await tester.pumpWidget(
        app(reopened, vocabulary, const CategoriesPage()),
      );
      await until(find.text('Food & Drinks'));
      await tester.tap(find.text('Food & Drinks'));
      await until(find.text('apple'));
      debugPrint('B11 stage vocabulary visible');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        expect(
          await reopened.select(reopened.vocabularyWords).get(),
          hasLength(1),
        );
        expect(
          await reopened.select(reopened.outboxOperations).get(),
          hasLength(2),
        );
      });
      await drain(reopened.close());
      reopenedClosed = true;
      await tester.runAsync(() => directory.delete(recursive: true));
      await tester.runAsync(h.cleanupAfterDispose);
      debugPrint('B11 stage file cleanup done');
    },
  );

  test(
    'B11 releasing lease invalidates save while native resume is pending',
    () async {
      final h = await _scannerHarness();
      final lease = h.scanner.acquireLease();
      await lease.initialize();
      final result = await h.scanner.captureAndClassify();
      final pending = Completer<void>();
      final entered = Completer<void>();
      h.camera.resumePending = pending;
      h.camera.resumeEntered = entered;
      final resume = lease.resume();
      await entered.future;
      final released = lease.release();
      try {
        await expectLater(h.scanner.accept(result), throwsA(anything));
        expect(
          await h.database.select(h.database.outboxOperations).get(),
          isEmpty,
        );
      } finally {
        pending.complete();
        await resume;
        await released;
      }
    },
  );

  test(
    'B11 lost acknowledgement and concurrent duplicate reuse one durable word',
    () async {
      var loseAck = true;
      final h = await _scannerHarness(
        onLocalMutation: () {
          if (loseAck) {
            loseAck = false;
            throw StateError('lost acknowledgement after commit');
          }
        },
      );
      final result = await h.scanner.captureAndClassify();
      await expectLater(h.scanner.accept(result), throwsA(isA<StateError>()));
      final stored = await h.database.select(h.database.vocabularyWords).get();
      expect(stored, hasLength(1));
      final retries = await Future.wait(
        List.generate(8, (_) => h.scanner.accept(result)),
      );
      expect(retries.map((word) => word.id).toSet(), {stored.single.id});
      expect(
        await h.database.select(h.database.vocabularyCategories).get(),
        hasLength(1),
      );
      expect(
        await h.database.select(h.database.vocabularyWords).get(),
        hasLength(1),
      );
      expect(
        await h.database.select(h.database.outboxOperations).get(),
        hasLength(2),
      );
    },
  );

  test(
    'B11 scanner save survives file database restart with original provenance',
    () async {
      final directory = await Directory.systemTemp.createTemp('b11-restart-');
      final file = File('${directory.path}/vocabulary.sqlite');
      final original = AppDatabase(NativeDatabase(file));
      final h = await _scannerHarness(databaseOverride: original);
      final result = await h.scanner.captureAndClassify();
      final saved = await h.scanner.accept(result);
      await h.scanner.dispose();
      await original.close();
      final reopened = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await reopened.close();
        await directory.delete(recursive: true);
      });
      final rows = await reopened.select(reopened.vocabularyWords).get();
      expect(rows.single.id, saved.id);
      expect(
        rows.single.source,
        'object-scanner:${result.modelId}@${result.modelVersion}',
      );
      expect(rows.single.ownerId, saved.ownerId);
      expect(
        await reopened.select(reopened.outboxOperations).get(),
        hasLength(2),
      );
      final repository = DriftVocabularyRepository(reopened);
      final visible = await repository
          .watchWords(saved.ownerId, saved.categoryId)
          .first;
      expect(visible.single.id, saved.id);
      expect(visible.single.spelling, 'apple');
    },
  );

  test(
    'B11 pending save rolls back when lifecycle expires before transaction',
    () async {
      final h = await _scannerHarness();
      final result = await h.scanner.captureAndClassify();
      final entered = Completer<void>();
      final release = Completer<void>();
      final held = h.database.transaction(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final save = h.scanner.accept(result);
      final rejected = expectLater(save, throwsA(anything));
      await h.scanner.pause();
      release.complete();
      await held;
      await rejected;
      expect(
        await h.database.select(h.database.vocabularyWords).get(),
        isEmpty,
      );
      expect(
        await h.database.select(h.database.vocabularyCategories).get(),
        isEmpty,
      );
      expect(
        await h.database.select(h.database.outboxOperations).get(),
        isEmpty,
      );
    },
  );

  test(
    'B11 disk failure rolls back scanner category word and outbox then retries',
    () async {
      final h = await _scannerHarness();
      final result = await h.scanner.captureAndClassify();
      await h.database.customStatement(
        "CREATE TRIGGER b11_disk_failure BEFORE INSERT ON vocabulary_words BEGIN SELECT RAISE(ABORT, 'simulated disk failure'); END",
      );
      await expectLater(h.scanner.accept(result), throwsA(anything));
      expect(
        await h.database.select(h.database.vocabularyCategories).get(),
        isEmpty,
      );
      expect(
        await h.database.select(h.database.vocabularyWords).get(),
        isEmpty,
      );
      expect(
        await h.database.select(h.database.outboxOperations).get(),
        isEmpty,
      );
      await h.database.customStatement('DROP TRIGGER b11_disk_failure');
      await h.scanner.accept(result);
      expect(
        await h.database.select(h.database.vocabularyWords).get(),
        hasLength(1),
      );
      expect(
        await h.database.select(h.database.outboxOperations).get(),
        hasLength(2),
      );
    },
  );

  test(
    'B11 owner change after preview rejects save into replacement owner',
    () async {
      final h = await _scannerHarness();
      final first = await h.owners.getOrCreateActiveOwner();
      final result = await h.scanner.captureAndClassify();
      await h.database.customStatement('UPDATE local_owners SET is_active = 0');
      final second = await h.owners.getOrCreateActiveOwner();
      expect(second.id, isNot(first.id));
      await expectLater(h.scanner.accept(result), throwsA(anything));
      expect(
        await h.database.select(h.database.vocabularyWords).get(),
        isEmpty,
      );
      expect(
        await h.database.select(h.database.outboxOperations).get(),
        isEmpty,
      );
    },
  );

  test(
    'B11 accept rejects a foreign mapped result without vocabulary writes',
    () async {
      final h = await _scannerHarness();
      final result = await h.scanner.captureAndClassify();
      final forged = ObjectScanResult(
        classifications: result.classifications,
        vocabulary: result.vocabulary,
        matchedClassification: result.matchedClassification,
        modelId: result.modelId,
        modelVersion: result.modelVersion,
        capturedAtUtc: result.capturedAtUtc,
      );
      await expectLater(
        h.scanner.accept(forged),
        throwsA(isA<CameraPracticeException>()),
      );
      expect(
        await h.database.select(h.database.vocabularyWords).get(),
        isEmpty,
      );
      expect(
        await h.database.select(h.database.outboxOperations).get(),
        isEmpty,
      );
      await h.scanner.accept(result);
      expect(
        await h.database.select(h.database.vocabularyWords).get(),
        hasLength(1),
      );
    },
  );

  test('B11 pause invalidates controller accept permission', () async {
    final h = await _scannerHarness();
    final result = await h.scanner.captureAndClassify();
    await h.scanner.pause();
    await h.scanner.resume();
    await expectLater(
      h.scanner.accept(result),
      throwsA(isA<CameraPracticeException>()),
    );
    expect(await h.database.select(h.database.outboxOperations).get(), isEmpty);
  });

  for (final score in [double.nan, double.infinity, 1.01, -0.01]) {
    test(
      'B11 invalid model score $score rejects whole output without promoting lower label',
      () async {
        final h = await _scannerHarness();
        h.runtime.classifications = [
          ModelClassification(index: 1, label: 'Apple', confidence: score),
          const ModelClassification(index: 1, label: 'Apple', confidence: 0.8),
        ];
        await expectLater(
          h.scanner.captureAndClassify(),
          throwsA(isA<CameraPracticeException>()),
        );
        expect(
          await h.database.select(h.database.outboxOperations).get(),
          isEmpty,
        );
      },
    );
  }

  test('B11 invalid class index cannot become accepted vocabulary', () async {
    final h = await _scannerHarness();
    h.runtime.classifications = const [
      ModelClassification(index: 99, label: 'Apple', confidence: 0.9),
    ];
    await expectLater(
      h.scanner.captureAndClassify(),
      throwsA(isA<CameraPracticeException>()),
    );
    expect(await h.database.select(h.database.outboxOperations).get(), isEmpty);
  });

  test(
    'B11 permission plugin exception becomes recoverable initialization failure',
    () async {
      final camera = _FakeCamera()
        ..permissionFailure = StateError('native permission');
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
            (e) => e.code,
            'code',
            CameraFailureCode.initializationFailed,
          ),
        ),
      );
      expect(camera.initializeCalls, 0);
      expect(scanner.isReady, isFalse);
      await scanner.dispose();
    },
  );

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

  for (final backgroundIndex in <int?>[0, null]) {
    test(
      'classifies and persists locally with background index $backgroundIndex',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'scanner-usecase-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final modelBytes = utf8.encode('verified-test-model');
        final modelFile = File('${directory.path}/model.tflite');
        await modelFile.writeAsBytes(modelBytes);
        final manifest = _manifest(
          modelBytes,
          backgroundClassIndex: backgroundIndex,
        );
        final runtime = _FakeRuntime();
        if (backgroundIndex == null) {
          runtime.classifications = const [
            ModelClassification(index: 0, label: 'Apple', confidence: 0.92),
          ];
        }
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
        expect(runtime.requestedTopK, 2);
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
  }
  test(
    'does not replace an unmapped primary prediction with a lower mapped one',
    () async {
      final directory = await Directory.systemTemp.createTemp('scanner-map-');
      addTearDown(() => directory.delete(recursive: true));
      final modelBytes = utf8.encode('verified-test-model');
      final modelFile = File('${directory.path}/model.tflite');
      await modelFile.writeAsBytes(modelBytes);
      final manifest = _manifest(modelBytes, backgroundClassIndex: null);
      final repository = _ModelRepository(
        _activeRecord(manifest, modelFile.path),
      );
      final runtime = _FakeRuntime()
        ..classifications = const [
          ModelClassification(index: 0, label: 'Unknown', confidence: 0.98),
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
      expect(result.matchedClassification, isNull);
      expect(result.vocabulary, isNull);
    },
  );

  test('reports scores below the minimum as not confident', () async {
    final directory = await Directory.systemTemp.createTemp(
      'scanner-not-confident-',
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
          CameraFailureCode.notConfident,
        ),
      ),
    );
  });

  test(
    'preserves invalid image when captured bytes cannot be decoded',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'scanner-invalid-image-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final modelBytes = utf8.encode('verified-test-model');
      final modelFile = File('${directory.path}/model.tflite');
      await modelFile.writeAsBytes(modelBytes);
      final manifest = _manifest(modelBytes);
      final repository = _ModelRepository(
        _activeRecord(manifest, modelFile.path),
      );
      final scanner = ObjectScannerUseCases(
        camera: _FakeCamera(),
        deviceModels: DeviceModelUseCases(
          manifest: manifest,
          repository: repository,
          downloadManager: _uncalledManager(repository, directory),
          openRuntime:
              ({required path, required manifest, required delegate}) async =>
                  _FakeRuntime(),
        ),
        vocabulary: _throwingVocabulary(),
        preprocessor: const DartImagePreprocessor(),
      );

      await scanner.initialize();

      await expectLater(
        scanner.captureAndClassify(),
        throwsA(
          isA<CameraPracticeException>().having(
            (error) => error.code,
            'code',
            CameraFailureCode.invalidImage,
          ),
        ),
      );
    },
  );

  test(
    'dispose drains lease initialization and closes a late runtime',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'scanner-dispose-race-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final modelBytes = utf8.encode('verified-test-model');
      final modelFile = File('${directory.path}/model.tflite');
      await modelFile.writeAsBytes(modelBytes);
      final manifest = _manifest(modelBytes);
      final repository = _ModelRepository(
        _activeRecord(manifest, modelFile.path),
      );
      final runtime = _FakeRuntime();
      final runtimeOpen = Completer<ImageClassifierRuntime>();
      final openCalled = Completer<void>();
      final camera = _FakeCamera();
      final scanner = ObjectScannerUseCases(
        camera: camera,
        deviceModels: DeviceModelUseCases(
          manifest: manifest,
          repository: repository,
          downloadManager: _uncalledManager(repository, directory),
          openRuntime: ({required path, required manifest, required delegate}) {
            openCalled.complete();
            return runtimeOpen.future;
          },
        ),
        vocabulary: _throwingVocabulary(),
        preprocessor: _FakePreprocessor(),
      );
      final lease = scanner.acquireLease();
      final initialization = lease.initialize();
      await openCalled.future;

      var disposeCompleted = false;
      final disposeFuture = scanner.dispose().then((_) {
        disposeCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(disposeCompleted, isFalse);

      runtimeOpen.complete(runtime);
      expect(await initialization, isFalse);
      await disposeFuture;

      expect(disposeCompleted, isTrue);
      expect(runtime.closeCalls, 1);
      expect(camera.isInitialized, isFalse);
      expect(scanner.isReady, isFalse);
      expect(scanner.acquireLease, throwsStateError);
    },
  );
}

ModelManifest _manifest(List<int> bytes, {int? backgroundClassIndex = 0}) =>
    ModelManifest(
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
      backgroundClassIndex: backgroundClassIndex,
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
  int disposeCalls = 0;
  MediaPermissionState permission = MediaPermissionState.granted;
  Object? permissionFailure;
  Completer<void>? resumePending;
  Completer<void>? resumeEntered;
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
    disposeCalls++;
    isInitialized = false;
  }

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    isInitialized = true;
  }

  @override
  Future<void> pause() async {
    isInitialized = false;
  }

  @override
  Future<MediaPermissionState> requestPermission() async {
    final failure = permissionFailure;
    if (failure != null) throw failure;
    return permission;
  }

  @override
  Future<void> resume() async {
    resumeEntered?.complete();
    await resumePending?.future;
    await initialize();
  }
}

final class _FakePreprocessor implements ImagePreprocessor {
  @override
  Uint8List toRawRgb224(Uint8List encodedBytes) => Uint8List(224 * 224 * 3);
}

final class _FakeRuntime implements ImageClassifierRuntime {
  Object? closeFailure;
  List<ModelClassification> classifications = const [
    ModelClassification(index: 1, label: 'Apple', confidence: 0.92),
    ModelClassification(index: 0, label: 'background', confidence: 0.05),
  ];
  Completer<void>? classifyPending;
  Completer<void>? classifyEntered;
  int closeCalls = 0;
  int? requestedTopK;

  @override
  ModelDelegate get delegate => ModelDelegate.xnnpack;

  @override
  Future<List<ModelClassification>> classify(
    Uint8List rgbBytes, {
    int topK = 5,
  }) async {
    requestedTopK = topK;
    classifyEntered?.complete();
    await classifyPending?.future;
    return classifications;
  }

  @override
  void close() {
    closeCalls += 1;
    if (closeFailure != null) throw closeFailure!;
  }

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
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'test-owner',
        createdAtUtc: DateTime.utc(2026, 9, 13),
      );
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _ThrowingVocabularyRepository implements VocabularyRepository {
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<
  ({
    ObjectScannerUseCases scanner,
    _FakeCamera camera,
    _FakeRuntime runtime,
    AppDatabase database,
    DriftLocalOwnerRepository owners,
    Future<void> Function() cleanupAfterDispose,
  })
>
_scannerHarness({
  AppDatabase? databaseOverride,
  void Function()? onLocalMutation,
  WidgetTester? widgetTester,
}) async {
  final directory = await Directory.systemTemp.createTemp('b11-scanner-');
  final database = databaseOverride ?? AppDatabase(NativeDatabase.memory());
  final bytes = utf8.encode('verified-test-model');
  final file = File('${directory.path}/model.tflite');
  await file.writeAsBytes(bytes);
  final manifest = _manifest(bytes);
  final repository = _ModelRepository(_activeRecord(manifest, file.path));
  final runtime = _FakeRuntime();
  final camera = _FakeCamera();
  var id = 0;
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'owner-${id++}',
    nowUtc: () => DateTime.utc(2026, 9, 13),
  );
  final scanner = ObjectScannerUseCases(
    camera: camera,
    deviceModels: DeviceModelUseCases(
      manifest: manifest,
      repository: repository,
      downloadManager: _uncalledManager(repository, directory),
      openRuntime:
          ({required path, required manifest, required delegate}) async =>
              runtime,
    ),
    vocabulary: VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'id-${id++}',
      nowUtc: () => DateTime.utc(2026, 9, 13),
      onLocalMutation: onLocalMutation,
    ),
    preprocessor: _FakePreprocessor(),
  );
  var cleaned = false;
  Future<void> cleanup({bool alreadyDisposed = false}) async {
    if (cleaned) return;
    if (!alreadyDisposed) await scanner.dispose();
    if (databaseOverride == null) await database.close();
    await directory.delete(recursive: true);
    cleaned = true;
  }

  addTearDown(() async {
    if (cleaned) return;
    if (widgetTester == null) {
      await cleanup();
    } else {
      await widgetTester.runAsync(cleanup);
    }
  });
  await scanner.initialize();
  return (
    scanner: scanner,
    camera: camera,
    runtime: runtime,
    database: database,
    owners: owners,
    cleanupAfterDispose: () => cleanup(alreadyDisposed: true),
  );
}

final class _NoAudioVoice implements VoiceProvider {
  @override
  Future<void> stop() async {}
  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'b11-local');
}
