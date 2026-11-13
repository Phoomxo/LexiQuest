import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/application/model_benchmark.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/object_scanner_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/services/object_vocabulary_database.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  Future<void> openSelectedSetScanner(
    WidgetTester tester,
    _FakeScanner scanner,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final word = await Navigator.of(context).push<VocabularyWord>(
                  MaterialPageRoute<VocabularyWord>(
                    builder: (_) => ObjectScannerScreen(
                      scanner: scanner,
                      voice: VoiceUseCases(_FakeVoice()),
                      targetCategoryId: 'category:travel',
                      targetCategoryName: 'ชุดทดสอบ',
                    ),
                  ),
                );
                if (context.mounted && word != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('กลับชุด ${word.categoryId}')),
                  );
                }
              },
              child: const Text('ถ่ายภาพเพิ่มคำในชุด'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ถ่ายภาพเพิ่มคำในชุด'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('selected-set confirmation returns the saved word to its set', (
    tester,
  ) async {
    final scanner = _FakeScanner();
    await openSelectedSetScanner(tester, scanner);

    expect(find.text('เก็บในชุด ชุดทดสอบ'), findsOneWidget);
    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();

    expect(scanner.acceptedCategoryId, 'category:travel');
    expect(scanner.acceptCalls, 1);
    expect(find.text('กลับชุด category:travel'), findsOneWidget);
    expect(find.byType(ObjectScannerScreen), findsNothing);
  });

  testWidgets('pending confirmation blocks repeated taps capture and Back', (
    tester,
  ) async {
    final scanner = _FakeScanner()..pendingAccept = Completer<void>();
    await openSelectedSetScanner(tester, scanner);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'เพิ่มเข้าคลัง'),
    );
    confirm.onPressed!();
    confirm.onPressed!();
    await tester.pump();

    expect(scanner.acceptCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('object-scanner-capture-button')),
          )
          .onPressed,
      isNull,
    );
    await tester.pageBack();
    await tester.pump();
    expect(find.byType(ObjectScannerScreen), findsOneWidget);

    scanner.pendingAccept!.complete();
    await tester.pumpAndSettle();
    expect(find.text('กลับชุด category:travel'), findsOneWidget);
  });

  testWidgets('failed confirmation keeps the proposal for a safe retry', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..acceptFailure = StateError('synthetic save failure');
    await openSelectedSetScanner(tester, scanner);
    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();

    expect(find.text('apple'), findsOneWidget);
    expect(
      find.text('บันทึกคำศัพท์ไม่สำเร็จ กรุณาลองอีกครั้ง'),
      findsOneWidget,
    );
    expect(find.text('บันทึกแล้ว'), findsNothing);
    scanner.acceptFailure = null;
    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();
    expect(scanner.acceptCalls, 2);
    expect(find.text('กลับชุด category:travel'), findsOneWidget);
  });

  for (final selectedSet in [false, true]) {
    testWidgets(
      'owner switch stops confirmation before the scanner writes $selectedSet',
      (tester) async {
        final scanner = _FakeScanner();
        final owners = _MutableOwners();
        await tester.binding.setSurfaceSize(const Size(800, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: AppDependencies(
              runtimeStatus: const AppRuntimeStatus(
                localData: RuntimeAvailability.ready,
                firebase: RuntimeAvailability.unavailable,
                supabase: RuntimeAvailability.unavailable,
                backends: RuntimeAvailability.unavailable,
              ),
              config: null,
              guestSessionService: _UnusedGuestSession(),
              localOwners: owners,
            ),
            child: MaterialApp(
              home: ObjectScannerScreen(
                scanner: scanner,
                voice: VoiceUseCases(_FakeVoice()),
                targetCategoryId: selectedSet ? 'category:travel' : null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('object-scanner-capture-button')),
        );
        await tester.pumpAndSettle();
        owners.ownerId = 'owner:other';

        await tester.tap(find.text('เพิ่มเข้าคลัง'));
        await tester.pumpAndSettle();

        expect(scanner.acceptCalls, 0);
        expect(
          find.text('บัญชีหรือชุดคำเปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่'),
          findsOneWidget,
        );
        expect(find.text('บันทึกแล้ว'), findsNothing);
      },
    );
  }

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
    expect(find.text('ผลจากโมเดลสแกนวัตถุในอุปกรณ์'), findsOneWidget);
    expect(find.textContaining('model-v1'), findsNothing);

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
      find.ancestor(
        of: find.byKey(const ValueKey('object-scanner-error')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsAtLeastNWidgets(1),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ถ่ายภาพและวิเคราะห์'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('เปิดศูนย์สิทธิ์อุปกรณ์'), findsOneWidget);
  });

  testWidgets('retries one transient camera initialization failure', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..initializeFailure = const CameraPracticeException(
        CameraFailureCode.initializationFailed,
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('object-scanner-retry-camera')),
      200,
    );
    expect(find.text('ลองเปิดกล้องอีกครั้ง'), findsOneWidget);

    scanner.initializeFailure = null;
    await tester.tap(find.text('ลองเปิดกล้องอีกครั้ง'));
    await tester.pumpAndSettle();

    expect(scanner.initializeCalls, 2);
    expect(scanner.isReady, isTrue);
  });

  testWidgets('clears stale results and retries an uncertain scan', (
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
    expect(find.text('ถ่ายภาพหรือวิเคราะห์ไม่สำเร็จ'), findsOneWidget);

    scanner.captureFailure = const CameraPracticeException(
      CameraFailureCode.noConfidentMatch,
    );
    final capture = find.byKey(const ValueKey('object-scanner-capture-button'));
    await tester.tap(capture);
    await tester.pumpAndSettle();

    final guidance = find.text(
      'ยังระบุวัตถุไม่ได้ ลองเพิ่มแสงและถ่ายวัตถุทีละชิ้น',
    );
    expect(guidance, findsOneWidget);
    expect(find.text('รูปภาพนี้ไม่สามารถนำมาวิเคราะห์ได้'), findsNothing);
    expect(find.text('เพิ่มเข้าคลัง'), findsNothing);

    scanner.captureFailure = null;
    await tester.tap(capture);
    await tester.pumpAndSettle();
    expect(guidance, findsNothing);
    expect(find.text('apple'), findsOneWidget);
    expect(find.text('เพิ่มเข้าคลัง'), findsOneWidget);
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
    expect(find.textContaining('โหมดมาตรฐาน · ทดสอบ 10 ครั้ง'), findsOneWidget);
    expect(
      find.textContaining('โหมดเร่งความเร็ว · ทดสอบ 10 ครั้ง'),
      findsOneWidget,
    );
    expect(find.textContaining('XNNPACK'), findsNothing);
    expect(find.textContaining('90% ไม่เกิน'), findsNWidgets(2));
  });

  for (final size in const [Size(360, 800), Size(412, 915), Size(800, 360)]) {
    testWidgets('scanner result actions remain reachable at 2x on $size', (
      tester,
    ) async {
      final scanner = _FakeScanner();
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: ObjectScannerScreen(
              scanner: scanner,
              voice: VoiceUseCases(_FakeVoice()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final capture = find.byKey(
        const ValueKey('object-scanner-capture-button'),
      );
      await tester.scrollUntilVisible(capture, 200);
      await tester.tap(capture);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('เพิ่มเข้าคลัง'), 200);

      expect(find.text('ฟังเสียง'), findsOneWidget);
      expect(find.text('เพิ่มเข้าคลัง'), findsOneWidget);
      final title = find.text('สแกนวัตถุ');
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scanner route title stays readable with Back at 2x', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scanner = _FakeScanner();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ObjectScannerScreen(
                    scanner: scanner,
                    voice: VoiceUseCases(_FakeVoice()),
                  ),
                ),
              ),
              child: const Text('เปิดเครื่องสแกน'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดเครื่องสแกน'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    final title = find.text('สแกนวัตถุ');
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);
    expect(tester.takeException(), isNull);
  });
}

final class _FakeScanner implements ObjectScannerController {
  CameraPracticeException? initializeFailure;
  CameraPracticeException? captureFailure;
  int acceptCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  int benchmarkCalls = 0;
  int initializeCalls = 0;
  String? acceptedCategoryId;
  Completer<void>? pendingAccept;
  Object? acceptFailure;
  @override
  bool isReady = false;

  @override
  Future<VocabularyWord> accept(
    ObjectScanResult result, {
    String? categoryId,
    String? expectedOwnerId,
  }) async {
    acceptCalls += 1;
    acceptedCategoryId = categoryId;
    await pendingAccept?.future;
    final failure = acceptFailure;
    if (failure != null) throw failure;
    return VocabularyWord(
      id: 'word:apple',
      ownerId: 'owner:1',
      categoryId: categoryId ?? 'category:food',
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
    initializeCalls += 1;
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

final class _MutableOwners extends Fake implements LocalOwnerRepository {
  String ownerId = 'owner:1';

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: ownerId, createdAtUtc: DateTime.utc(2026, 11, 13));
}

final class _UnusedGuestSession extends Fake implements GuestSessionService {}

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
