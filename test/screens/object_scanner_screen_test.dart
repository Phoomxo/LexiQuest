import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/application/model_benchmark.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/media_practice/application/object_scanner_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/screens/media_dependency_unavailable.dart';
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
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
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
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
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

  testWidgets('renders a delayed camera initialization failure while current', (
    tester,
  ) async {
    final pending = Completer<void>();
    final scanner = _FakeScanner()..initializePending = pending;
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(scanner.initializeCalls, 1);

    pending.completeError(
      const CameraPracticeException(CameraFailureCode.permissionDenied),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('object-scanner-error')),
      findsOneWidget,
    );
    expect(find.textContaining('ไม่ได้รับสิทธิ์ใช้กล้อง'), findsOneWidget);
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
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
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
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(scanner.pauseCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(scanner.resumeCalls, 1);
    expect(scanner.isReady, isTrue);
  });

  testWidgets('background stops scanner result playback and pauses camera', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    final provider = _FakeVoice();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: ObjectScannerScreen(scanner: scanner, voice: voice),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('object-scanner-capture-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.volume_up_outlined));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.runAsync(
        () => provider.stopEntered.future.timeout(
          const Duration(milliseconds: 250),
        ),
      );

      expect(provider.stopCalls, 1);
      expect(scanner.pauseCalls, 1);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
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
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
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
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
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

  testWidgets('missing voice fails closed before camera initialization', (
    tester,
  ) async {
    final scanner = _FakeScanner();

    await tester.pumpWidget(
      MaterialApp(home: ObjectScannerScreen(scanner: scanner)),
    );
    await tester.pumpAndSettle();

    final state = tester.widget<MediaDependencyUnavailable>(
      find.byType(MediaDependencyUnavailable),
    );
    expect(state.reason, MediaDependencyUnavailableReason.voice);
    expect(scanner.initializeCalls, 0);
  });

  testWidgets('late camera initialization is paused after route disposal', (
    tester,
  ) async {
    final pending = Completer<void>();
    final scanner = _FakeScanner()..initializePending = pending;

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(scanner.initializeCalls, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(scanner.pauseCalls, 0);

    pending.complete();
    await tester.pump();
    await tester.pump();

    expect(scanner.isReady, isFalse);
    expect(scanner.pauseCalls, 1);
  });

  testWidgets('late camera initialization stays paused in background', (
    tester,
  ) async {
    final pending = Completer<void>();
    final scanner = _FakeScanner()..initializePending = pending;
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(
          scanner: scanner,
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(scanner.initializeCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(scanner.pauseCalls, 0);

    pending.complete();
    await tester.pump();
    await tester.pump();

    expect(scanner.isReady, isFalse);
    expect(scanner.pauseCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(scanner.resumeCalls, 1);
    expect(scanner.isReady, isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('object-scanner-capture-button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'stale route initialization cannot pause a newer shared scanner consumer',
    (tester) async {
      final oldPending = Completer<void>();
      final scanner = _FakeScanner()..initializePendings.add(oldPending);
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ObjectScannerScreen(
            key: const ValueKey<String>('old-scanner-route'),
            scanner: scanner,
            voice: voice,
          ),
        ),
      );
      await tester.pump();
      expect(scanner.initializeCalls, 1);

      await tester.pumpWidget(
        MaterialApp(
          home: ObjectScannerScreen(
            key: const ValueKey<String>('new-scanner-route'),
            scanner: scanner,
            voice: voice,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(scanner.initializeCalls, 1);
      expect(scanner.isReady, isFalse);

      oldPending.complete();
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(scanner.initializeCalls, 2);
      expect(scanner.isReady, isTrue);
      expect(scanner.pauseCalls, 1);
      expect(scanner.lifecycleEvents, [
        'initialize:1:start',
        'initialize:1:ready',
        'pause',
        'initialize:2:start',
        'initialize:2:ready',
      ]);
    },
  );

  for (final completesWithError in <bool>[false, true]) {
    final outcome = completesWithError ? 'failure' : 'result';
    testWidgets('covered scanner capture cannot publish a stale $outcome', (
      tester,
    ) async {
      final pendingCapture = Completer<ObjectScanResult>();
      final scanner = _FakeScanner()..capturePendings.add(pendingCapture);
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ObjectScannerScreen(
            key: const ValueKey<String>('capture-parent-scanner-route'),
            scanner: scanner,
            voice: voice,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('object-scanner-capture-button')),
      );
      await tester.pump();
      expect(scanner.captureCalls, 1);
      final parentCancellation = scanner.captureCancellations.single!;
      expect(parentCancellation.isCancelled, isFalse);

      final parentContext = tester.element(
        find.byKey(const ValueKey('capture-parent-scanner-route')),
      );
      unawaited(
        Navigator.of(parentContext).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ObjectScannerScreen(
              key: const ValueKey<String>('capture-child-scanner-route'),
              scanner: scanner,
              voice: voice,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(parentCancellation.isCancelled, isTrue);
      expect(scanner.initializeCalls, 2);
      expect(scanner.pauseCalls, 1);
      expect(scanner.isReady, isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('object-scanner-capture-button')),
            )
            .onPressed,
        isNotNull,
      );

      if (completesWithError) {
        pendingCapture.completeError(
          const CameraPracticeException(CameraFailureCode.captureFailed),
        );
      } else {
        pendingCapture.complete(_fakeObjectScanResult());
      }
      await tester.pump();
      await tester.pumpAndSettle();

      expect(scanner.isReady, isTrue);
      expect(scanner.pauseCalls, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('object-scanner-capture-button')),
            )
            .onPressed,
        isNotNull,
      );

      Navigator.of(
        tester.element(
          find.byKey(const ValueKey('capture-child-scanner-route')),
        ),
      ).pop();
      await tester.pumpAndSettle();

      expect(scanner.initializeCalls, 3);
      expect(scanner.isReady, isTrue);
      expect(find.text('apple'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('object-scanner-error')),
        findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('object-scanner-capture-button')),
            )
            .onPressed,
        isNotNull,
      );
    });
  }

  testWidgets(
    'scanner route reacquires its shared controller after child pop',
    (tester) async {
      final scanner = _FakeScanner();
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ObjectScannerScreen(
            key: const ValueKey<String>('parent-scanner-route'),
            scanner: scanner,
            voice: voice,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scanner.initializeCalls, 1);

      final context = tester.element(find.byType(ObjectScannerScreen));
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ObjectScannerScreen(
              key: const ValueKey<String>('child-scanner-route'),
              scanner: scanner,
              voice: voice,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scanner.initializeCalls, 2);

      Navigator.of(tester.element(find.byType(ObjectScannerScreen))).pop();
      await tester.pumpAndSettle();

      expect(scanner.initializeCalls, 3);
      expect(scanner.isReady, isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('object-scanner-capture-button')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}

final class _FakeScanner implements ObjectScannerController {
  CameraPracticeException? initializeFailure;
  CameraPracticeException? captureFailure;
  Completer<void>? initializePending;
  final List<Completer<void>> initializePendings = [];
  final List<Completer<ObjectScanResult>> capturePendings = [];
  final List<ModelCancellation?> captureCancellations = [];
  int acceptCalls = 0;
  int captureCalls = 0;
  int initializeCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int benchmarkCalls = 0;
  final List<String> lifecycleEvents = [];
  @override
  bool isReady = false;
  late final ObjectScannerLeaseManager _leaseManager =
      ObjectScannerLeaseManager(
        isReady: () => isReady,
        initialize: initialize,
        pause: pause,
        resume: resume,
      );

  @override
  ObjectScannerLease acquireLease() => _leaseManager.acquire();

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
    captureCalls += 1;
    captureCancellations.add(cancellation);
    final failure = captureFailure;
    if (failure != null) throw failure;
    if (capturePendings.isNotEmpty) {
      return capturePendings.removeAt(0).future;
    }
    return _fakeObjectScanResult();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    final call = initializeCalls;
    lifecycleEvents.add('initialize:$call:start');
    final failure = initializeFailure;
    if (failure != null) throw failure;
    final pending = initializePendings.isEmpty
        ? initializePending
        : initializePendings.removeAt(0);
    if (pending != null) await pending.future;
    isReady = true;
    lifecycleEvents.add('initialize:$call:ready');
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    lifecycleEvents.add('pause');
    isReady = false;
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    isReady = true;
  }
}

ObjectScanResult _fakeObjectScanResult() => ObjectScanResult(
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

final class _FakeVoice implements VoiceProvider {
  final Completer<void> stopEntered = Completer<void>();
  int stopCalls = 0;

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
  Future<void> stop() async {
    stopCalls += 1;
    if (!stopEntered.isCompleted) stopEntered.complete();
  }
}
