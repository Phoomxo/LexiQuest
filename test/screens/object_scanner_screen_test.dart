import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/application/model_benchmark.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/media_practice/application/object_scanner_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/services/object_vocabulary_database.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('captures real adapter result and persists accepted vocabulary', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('object-scanner-simulate-button')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(find.textContaining('91.0%'), findsOneWidget);
    expect(find.textContaining('model-v1'), findsOneWidget);

    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();

    expect(scanner.acceptCalls, 1);
    expect(find.text('บันทึกแล้ว'), findsOneWidget);
  });

  testWidgets('shows honest permanent camera permission failure', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..initializeFailure = const CameraPracticeException(
        CameraFailureCode.permissionPermanentlyDenied,
      );
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('สิทธิ์กล้องถูกปิดถาวร'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ถ่ายภาพและวิเคราะห์'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('clears stale result before a failed new capture', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsOneWidget);

    scanner.captureFailure = const CameraPracticeException(
      CameraFailureCode.captureFailed,
    );
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsNothing);
    expect(find.text('เพิ่มเข้าคลัง'), findsNothing);
  });

  testWidgets('releases and restores camera across app lifecycle', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(scanner.pauseCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(scanner.resumeCalls, 1);
    expect(scanner.isReady, isTrue);
  });

  testWidgets('offers verified model download when no active model exists', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..initializeFailure = const CameraPracticeException(
        CameraFailureCode.modelUnavailable,
      );
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('object-scanner-download-model')),
      findsOneWidget,
    );
    expect(find.textContaining('ยังไม่มีโมเดลที่ตรวจสอบแล้ว'), findsOneWidget);
  });
  testWidgets('runs bounded CPU and XNNPACK benchmarks on demand', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(_FakeVoice()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('object-scanner-benchmark-model')),
    );
    await tester.pumpAndSettle();

    expect(scanner.benchmarkCalls, 1);
    expect(find.textContaining('CPU n=10'), findsOneWidget);
    expect(find.textContaining('XNNPACK n=10'), findsOneWidget);
  });
}

final class _FakeScanner implements ObjectScannerController {
  CameraPracticeException? initializeFailure;
  CameraPracticeException? captureFailure;
  int acceptCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int benchmarkCalls = 0;
  @override
  bool isReady = false;

  @override
  Future<VocabularyWord> accept(ObjectScanResult result) async {
    acceptCalls += 1;
    return VocabularyWord(
      id: 'word:apple',
      ownerId: 'owner:1',
      categoryId: 'category:food',
      spelling: 'apple',
      normalizedSpelling: 'apple',
      meaning: 'แอปเปิล',
      normalizedMeaning: 'แอปเปิล',
      partOfSpeech: 'noun',
      cefrLevel: 'A1',
      source: 'object-scanner:model@model-v1',
      isGlobal: false,
      localRevision: 1,
      isDeleted: false,
      createdAtUtc: DateTime.utc(2026, 7, 30),
      updatedAtUtc: DateTime.utc(2026, 7, 30),
    );
  }

  @override
  Widget buildPreview() =>
      const ColoredBox(key: ValueKey('camera-preview'), color: Colors.black);

  @override
  Future<ModelDownloadRecord> downloadModel({
    ModelCancellation? cancellation,
  }) => throw UnimplementedError();

  @override
  Future<ModelDownloadRecord?> modelStatus() async => null;

  @override
  Future<List<ModelBenchmarkResult>> benchmarkModel({
    String deviceTier = 'field-device',
    int warmupRuns = 3,
    int measuredRuns = 20,
  }) async {
    benchmarkCalls += 1;
    return const [
      ModelBenchmarkResult(
        delegate: ModelDelegate.cpu,
        modelId: 'model',
        modelVersion: 'model-v1',
        deviceTier: 'field-device',
        sampleSize: 10,
        medianMicros: 1000,
        p90Micros: 1200,
        minimumMicros: 900,
        maximumMicros: 1300,
        peakWorkingSetBytes: 1000000,
      ),
      ModelBenchmarkResult(
        delegate: ModelDelegate.xnnpack,
        modelId: 'model',
        modelVersion: 'model-v1',
        deviceTier: 'field-device',
        sampleSize: 10,
        medianMicros: 500,
        p90Micros: 700,
        minimumMicros: 450,
        maximumMicros: 750,
        peakWorkingSetBytes: 1100000,
      ),
    ];
  }

  @override
  Future<ObjectScanResult> captureAndClassify({
    ModelCancellation? cancellation,
  }) async {
    final failure = captureFailure;
    if (failure != null) throw failure;
    return ObjectScanResult(
      classifications: const [
        ModelClassification(index: 1, label: 'Apple', confidence: 0.91),
      ],
      vocabulary: const ScannedVocabulary(
        mlLabel: 'Apple',
        englishWord: 'apple',
        thaiTranslation: 'แอปเปิล',
        cefrLevel: 'A1',
        phonetic: '/apple/',
        exampleSentence: 'I eat an apple.',
        category: 'Food',
      ),
      matchedClassification: const ModelClassification(
        index: 1,
        label: 'Apple',
        confidence: 0.91,
      ),
      modelId: 'model',
      modelVersion: 'model-v1',
      capturedAtUtc: DateTime.utc(2026, 7, 30),
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {
    final failure = initializeFailure;
    if (failure != null) throw failure;
    isReady = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    isReady = false;
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    isReady = true;
  }
}

final class _FakeVoice implements VoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}
