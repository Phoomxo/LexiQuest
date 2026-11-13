import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/device_model/application/device_model_use_cases.dart';
import 'package:vocab_learning_app/features/device_model/application/model_download_manager.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/image_preprocessor.dart';
import 'package:vocab_learning_app/features/media_practice/application/object_scanner_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as domain;
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/services/object_vocabulary_database.dart';

const _setA = 'ชุด A เป้าหมายของกล้อง';
const _setB = 'ชุด B เก็บข้อมูลเดิม';

void main() {
  testWidgets(
    'camera confirmation stays in selected A through practice and SQLite reopen',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );
      Directory? directory;
      late File file;
      late _Journey fixture;
      var databaseOpen = false;
      late String categoryA;
      late String categoryB;
      late String ticketId;
      late List<Map<String, dynamic>> originalB;
      try {
        await tester.runAsync(() async {
          directory = await Directory.systemTemp.createTemp(
            'lexiquest-synthetic-camera-',
          );
          file = File('${directory!.path}/journey.sqlite');
          fixture = _Journey.open(file);
          databaseOpen = true;
          final vocabulary = fixture.dependencies.vocabulary!;
          categoryA = (await vocabulary.createCategory(_setA)).id;
          categoryB = (await vocabulary.createCategory(_setB)).id;
          ticketId = (await vocabulary.createWord(
            CreateWordCommand(
              categoryId: categoryA,
              spelling: 'ticket',
              meaning: 'ตั๋ว',
              partOfSpeech: 'noun',
            ),
          )).id;
          await vocabulary.createWord(
            CreateWordCommand(
              categoryId: categoryB,
              spelling: 'banana',
              meaning: 'กล้วย',
              partOfSpeech: 'noun',
            ),
          );
          originalB =
              (await (fixture.database.select(
                    fixture.database.vocabularyWords,
                  )..where((word) => word.categoryId.equals(categoryB))).get())
                  .map((word) => word.toJson())
                  .toList();
        });
        await _openLibrary(tester, fixture.dependencies);
        await _pumpUntil(tester, find.text(_setA));
        expect(find.text(_setB), findsOneWidget);
        await tester.tap(find.text(_setA));
        await _pumpUntil(tester, find.text('ticket'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('add-word')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ถ่ายภาพ'));
        await _pumpUntil(
          tester,
          find.byKey(const ValueKey('synthetic-camera-preview')),
        );
        await tester.pumpAndSettle();
        expect(find.text('เก็บในชุด $_setA'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('object-scanner-capture-button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('object-scanner-capture-button')),
        );
        await _pumpUntil(tester, find.text('apple'));
        await tester.pumpAndSettle();
        expect(find.byType(ObjectScannerScreen), findsOneWidget);
        expect(
          await tester.runAsync(
            () =>
                fixture.database.select(fixture.database.vocabularyWords).get(),
          ),
          hasLength(2),
          reason: 'a camera proposal must not write before confirmation',
        );
        await tester.ensureVisible(find.text('เพิ่มเข้าคลัง'));
        await tester.tap(find.text('เพิ่มเข้าคลัง'));
        await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
        await tester.pumpAndSettle();
        expect(find.byType(ObjectScannerScreen), findsNothing);
        expect(fixture.scanner.acceptedCategoryId, categoryA);
        expect(find.text(_setA), findsOneWidget);
        expect(find.text('apple'), findsOneWidget);
        expect(find.text('banana'), findsNothing);
        await tester.tap(find.text('ฝึกจากชุดนี้'));
        const meanings = {'apple': 'แอปเปิล', 'ticket': 'ตั๋ว'};
        final practiced = <String>{};
        for (var index = 0; index < 2; index++) {
          final prompt = find.descendant(
            of: find.byType(QuizScreen),
            matching: find.byWidgetPredicate(
              (widget) => widget is Text && meanings.containsKey(widget.data),
            ),
          );
          await _pumpUntil(tester, prompt);
          await tester.pumpAndSettle();
          final spelling = tester.widget<Text>(prompt).data!;
          expect(practiced.add(spelling), isTrue);
          expect(find.text('banana'), findsNothing);
          final answer = find.widgetWithText(FilledButton, meanings[spelling]!);
          await tester.ensureVisible(answer);
          await tester.tap(answer);
          final next = index == 0 ? 'คำถามถัดไป' : 'ดูผลการเรียน';
          await _pumpUntil(tester, find.text(next));
          await tester.ensureVisible(find.text(next));
          await tester.tap(find.text(next));
        }
        expect(practiced, {'apple', 'ticket'});
        await _pumpUntil(tester, find.byType(ScoreScreen));
        await tester.pumpAndSettle();
        expect(find.text(_setA), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);
        final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        final sessionId = score.sessionId;
        expect(sessionId, isNotNull);
        expect(score.correctAnswers, 2);
        await tester.ensureVisible(find.text('กลับไปที่ชุดคำ'));
        await tester.tap(find.text('กลับไปที่ชุดคำ'));
        await _pumpUntil(tester, find.text('ฝึกจากชุดนี้'));
        await tester.pumpAndSettle();
        expect(find.text(_setA), findsOneWidget);
        expect(find.text('apple'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(fixture.database.close);
        databaseOpen = false;
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() async {
          fixture = _Journey.open(file);
          databaseOpen = true;
          final categories = await fixture.database
              .select(fixture.database.vocabularyCategories)
              .get();
          expect(categories.map((category) => category.id).toSet(), {
            categoryA,
            categoryB,
          });
          final words = await fixture.database
              .select(fixture.database.vocabularyWords)
              .get();
          final scanned = words.singleWhere((word) => word.spelling == 'apple');
          expect(scanned.categoryId, categoryA);
          expect(scanned.source, 'object-scanner:synthetic-known-object@1');
          expect(
            words.where((word) => word.categoryId == categoryA),
            hasLength(2),
          );
          expect(
            words
                .where((word) => word.categoryId == categoryB)
                .map((word) => word.toJson())
                .toList(),
            originalB,
          );
          final attempts = await fixture.database
              .select(fixture.database.answerAttempts)
              .get();
          expect(attempts, hasLength(2));
          expect(attempts.map((answer) => answer.wordId).toSet(), {
            ticketId,
            scanned.id,
          });
          expect(attempts.map((answer) => answer.sessionId).toSet(), {
            sessionId,
          });
          final progress = await fixture.dependencies.progress!.load();
          expect(progress.recentSessions.single.summary.id, sessionId);
          expect(progress.recentSessions.single.summary.score, 100);
          expect(progress.recentSessions.single.summary.state, 'completed');
        });
        await _openLibrary(tester, fixture.dependencies);
        await _pumpUntil(tester, find.text(_setA));
        expect(find.text(_setB), findsOneWidget);
        await tester.tap(find.text(_setA));
        await _pumpUntil(tester, find.text('apple'));
        await tester.pumpAndSettle();
        expect(find.text('ticket'), findsOneWidget);
        expect(find.text('banana'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        if (databaseOpen) await tester.runAsync(fixture.database.close);
        await tester.pump(const Duration(milliseconds: 1));
        if (directory != null)
          await tester.runAsync(() => directory!.delete(recursive: true));
        messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_tts'),
          null,
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

final class _Journey {
  _Journey(this.database, this.dependencies, this.scanner);
  final AppDatabase database;
  final AppDependencies dependencies;
  final _CameraBoundary scanner;

  static _Journey open(File file) {
    final database = AppDatabase(NativeDatabase(file));
    var nextId = 0;
    final now = DateTime.now().toUtc();
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-camera-owner',
      nowUtc: () => now,
    );
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'synthetic-word-${++nextId}',
      nowUtc: () => now,
    );
    final models = _UnusedModelPorts();
    final scanner = _CameraBoundary(
      ObjectScannerUseCases(
        camera: _UnusedCamera(),
        deviceModels: DeviceModelUseCases(
          manifest: ModelManifest.fieldImageClassifier,
          repository: models,
          downloadManager: ModelDownloadManager(
            repository: models,
            source: models,
            verifier: models,
            modelDirectory: () async => file.parent,
            nowUtc: () => now,
          ),
          openRuntime:
              ({required path, required manifest, required delegate}) =>
                  throw StateError('camera/model inference is stubbed'),
        ),
        vocabulary: vocabulary,
        preprocessor: const DartImagePreprocessor(),
      ),
    );
    return _Journey(
      database,
      AppDependencies(
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _UnusedGuestSession(),
        localOwners: owners,
        vocabulary: vocabulary,
        objectScanner: scanner,
        learning: LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(database),
          generateId: () => 'synthetic-learning-${++nextId}',
          nowUtc: () => now,
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
        ),
        progress: ProgressUseCases(
          owners: owners,
          queries: DriftProgressQueries(database),
          nowUtc: () => now,
        ),
      ),
      scanner,
    );
  }
}

final class _CameraBoundary extends Fake implements ObjectScannerController {
  _CameraBoundary(this.writer);
  final ObjectScannerUseCases writer;
  String? acceptedCategoryId;
  @override
  bool isReady = false;
  @override
  Future<void> initialize() async {
    isReady = true;
  }

  @override
  Widget buildPreview() =>
      const SizedBox(height: 120, key: ValueKey('synthetic-camera-preview'));
  @override
  Future<ModelDownloadRecord?> modelStatus() async => null;
  @override
  Future<void> pause() async {
    isReady = false;
  }

  @override
  Future<void> resume() async {
    isReady = true;
  }

  @override
  Future<ObjectScanResult> captureAndClassify({
    ModelCancellation? cancellation,
  }) async => ObjectScanResult(
    classifications: const [
      ModelClassification(index: 1, label: 'Apple', confidence: 0.99),
    ],
    vocabulary: const ScannedVocabulary(
      mlLabel: 'Apple',
      englishWord: 'apple',
      thaiTranslation: 'แอปเปิล',
      cefrLevel: 'A1',
      phonetic: '/apple/',
      exampleSentence: 'I eat an apple.',
      category: _setB,
    ),
    matchedClassification: const ModelClassification(
      index: 1,
      label: 'Apple',
      confidence: 0.99,
    ),
    modelId: 'synthetic-known-object',
    modelVersion: '1',
    capturedAtUtc: DateTime.now().toUtc(),
  );
  @override
  Future<domain.VocabularyWord> accept(
    ObjectScanResult result, {
    String? categoryId,
    String? expectedOwnerId,
  }) {
    acceptedCategoryId = categoryId;
    return writer.accept(
      result,
      categoryId: categoryId,
      expectedOwnerId: expectedOwnerId,
    );
  }
}

final class _UnusedModelPorts extends Fake
    implements ModelDownloadRepository, ModelByteSource, ModelFileVerifier {}

final class _UnusedCamera extends Fake implements CameraGateway {}

final class _UnusedGuestSession extends Fake implements GuestSessionService {}

Future<void> _openLibrary(WidgetTester tester, AppDependencies dependencies) =>
    tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const MaterialApp(home: CategoriesPage()),
      ),
    );

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 100; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}
