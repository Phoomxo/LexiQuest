import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
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
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import '../support/r15_visual_capture.dart';

void main() {
  testWidgets('camera assistance distinguishes ready camera from failed scan and retry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final registry = MenuActionRegistry(currentOwner: () => 'test');
    final voice = VoiceUseCases(provider: _FakeVoice(), disposeProvider: () async {});
    addTearDown(voice.dispose);
    final scanner = _FakeScanner()
      ..captureFailure = const CameraPracticeException(CameraFailureCode.notConfident);
    await tester.pumpWidget(MenuActionScope(
      registry: registry,
      child: MaterialApp(home: ObjectScannerScreen(scanner: scanner, voice: voice)),
    ));
    await tester.pumpAndSettle();
    Map read() => jsonDecode((registry.snapshot()['context'] as List).single['value'] as String) as Map;
    expect(read()['cameraReady'], true);
    expect(read()['scanResultAvailable'], false);
    expect(read()['visibleMessage'], isNull);
    await tester.tap(find.byKey(const ValueKey('object-scanner-capture-button')));
    await tester.pumpAndSettle();
    final failed = read();
    expect(failed['cameraReady'], true);
    expect(failed['scanResultAvailable'], false);
    expect(failed['visibleMessage'], 'ยังระบุวัตถุไม่ได้ กรุณาถ่ายใหม่ให้วัตถุอยู่กลางภาพและมีแสงเพียงพอ');
    expect(find.text(failed['visibleMessage'] as String), findsOneWidget);
    expect(failed.containsKey('label'), false);
    scanner.captureFailure = null;
    await tester.tap(find.byKey(const ValueKey('object-scanner-capture-button')));
    await tester.pumpAndSettle();
    expect(read()['scanResultAvailable'], true);
    expect(read()['visibleMessage'], isNull);
    expect(read()['english'], 'apple');
    expect(registry.snapshot()['actions'], isEmpty);
    expect(scanner.captureCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final mapped in [true, false]) {
    testWidgets(
      'optional camera context distinguishes mapping mapped=$mapped',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final registry = MenuActionRegistry(currentOwner: () => 'test');
        final voice = VoiceUseCases(
          provider: _FakeVoice(),
          disposeProvider: () async {},
        );
        addTearDown(voice.dispose);
        final scanner = _FakeScanner()
          ..captureResult = mapped
              ? _fakeObjectScanResult()
              : _fakeUnmappedScanResult();
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: MaterialApp(
              home: ObjectScannerScreen(scanner: scanner, voice: voice),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('object-scanner-capture-button')),
        );
        await tester.pumpAndSettle();
        final data = jsonDecode(
          (registry.snapshot()['context'] as List).single['value'] as String,
        );
        expect(data['vocabularyMapped'], mapped);
        expect(data['saved'], false);
        expect(data['english'], mapped ? 'apple' : null);
        expect(data['confidence'], mapped ? 0.91 : 0.78);
        expect(data.containsKey('image'), false);
        expect(registry.snapshot()['actions'], isEmpty);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        final cleared = jsonDecode(
          (registry.snapshot()['context'] as List).single['value'] as String,
        );
        expect(cleared.containsKey('english'), false);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final interruption in [
    'replacement',
    'background',
    'cover',
    'new-scan',
  ]) {
    testWidgets('F04 stale scanner speech stays silent after $interruption', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final provider = _DeferredScannerVoice();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [appRouteObserver],
          home: ObjectScannerScreen(scanner: _FakeScanner(), voice: voice),
        ),
      );
      await tester.pumpAndSettle();
      final capture = find.byKey(
        const ValueKey('object-scanner-capture-button'),
      );
      await tester.tap(capture);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.volume_up_outlined));
      await tester.pump();
      expect(provider.calls, hasLength(1));
      switch (interruption) {
        case 'replacement':
          await tester.tap(find.byIcon(Icons.volume_up_outlined));
          await tester.pump();
          expect(provider.calls, hasLength(2));
          provider.calls[1].complete(_scannerVoiceResult);
        case 'background':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        case 'cover':
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Cover')),
              ),
            ),
          );
        case 'new-scan':
          await tester.tap(capture);
      }
      await tester.pumpAndSettle();
      expect(
        find.text('ระบบอ่านออกเสียงไม่พร้อมใช้งาน', skipOffstage: false),
        findsNothing,
      );
      provider.calls[0].completeError(StateError('retired speech'));
      await tester.pumpAndSettle();
      expect(
        find.text('ระบบอ่านออกเสียงไม่พร้อมใช้งาน', skipOffstage: false),
        findsNothing,
      );
      if (interruption == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
      }
      if (interruption == 'cover') {
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      expect(find.text('ระบบอ่านออกเสียงไม่พร้อมใช้งาน'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('F04 current scanner speech failure remains visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final provider = _DeferredScannerVoice();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ObjectScannerScreen(scanner: _FakeScanner(), voice: voice),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pump();
    provider.calls.single.completeError(StateError('current failure'));
    await tester.pumpAndSettle();
    expect(find.text('ระบบอ่านออกเสียงไม่พร้อมใช้งาน'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final fails in [false, true]) {
    testWidgets(
      'F01 background benchmark cannot publish after resume fails=$fails',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final pending = Completer<void>();
        final scanner = _FakeScanner()..benchmarkPending = pending;
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
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        if (fails) {
          pending.completeError(StateError('old benchmark'));
        } else {
          pending.complete();
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('peakRSS='), findsNothing);
        expect(find.text('การทดสอบประสิทธิภาพโมเดลไม่สำเร็จ'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'B11 save error retains preview and retry waits for durable acknowledgement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<void>();
      final scanner = _FakeScanner()..acceptPending = pending;
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
      await tester.tap(find.text('เพิ่มเข้าคลัง'));
      await tester.pump();
      expect(find.text('กำลังบันทึก...'), findsOneWidget);
      expect(find.text('บันทึกแล้ว'), findsNothing);
      pending.completeError(StateError('disk or lost ack'));
      await tester.pumpAndSettle();
      expect(
        find.text('บันทึกคำศัพท์ไม่สำเร็จ กรุณาลองอีกครั้ง'),
        findsOneWidget,
      );
      expect(find.text('apple'), findsOneWidget);
      expect(find.text('บันทึกแล้ว'), findsNothing);
      final retry = Completer<void>();
      scanner.acceptPending = retry;
      await tester.tap(find.text('เพิ่มเข้าคลัง'));
      await tester.pump();
      expect(find.text('บันทึกแล้ว'), findsNothing);
      retry.complete();
      await tester.pumpAndSettle();
      expect(find.text('บันทึกแล้ว'), findsOneWidget);
      expect(scanner.acceptCalls, 2);
    },
  );

  testWidgets('B11 stale accept callback cannot approve a new scan', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scanner = _FakeScanner();
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
    final capture = find.byKey(const ValueKey('object-scanner-capture-button'));
    await tester.tap(capture);
    await tester.pumpAndSettle();
    final oldAccept = tester
        .widget<FilledButton>(
          find.widgetWithText(FilledButton, 'เพิ่มเข้าคลัง'),
        )
        .onPressed!;
    scanner.captureResult = _fakeObjectScanResult();
    await tester.tap(capture);
    await tester.pumpAndSettle();
    oldAccept();
    await tester.pumpAndSettle();
    expect(scanner.acceptCalls, 0);
    await tester.tap(find.text('เพิ่มเข้าคลัง'));
    await tester.pumpAndSettle();
    expect(scanner.acceptCalls, 1);
  });

  testWidgets('B11 old resume failure cannot overwrite replacement scanner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<void>();
    final first = _FakeScanner()..resumePending = pending;
    final second = _FakeScanner();
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    Widget app(_FakeScanner scanner) => MaterialApp(
      home: ObjectScannerScreen(scanner: scanner, voice: voice),
    );
    await tester.pumpWidget(app(first));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(first.resumeCalls, 1);
    await tester.pumpWidget(app(second));
    await tester.pumpAndSettle();
    pending.completeError(StateError('old resume'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('object-scanner-error')), findsNothing);
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
  });

  for (final fails in [false, true]) {
    testWidgets('B11 stale benchmark after scanner replacement fails=$fails', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<void>();
      final first = _FakeScanner()..benchmarkPending = pending;
      final second = _FakeScanner();
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );
      Widget app(_FakeScanner scanner) => MaterialApp(
        home: ObjectScannerScreen(scanner: scanner, voice: voice),
      );
      await tester.pumpWidget(app(first));
      await tester.pumpAndSettle();
      final button = find.byKey(
        const ValueKey('object-scanner-benchmark-model'),
      );
      await tester.tap(button);
      await tester.pump();
      await tester.pumpWidget(app(second));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      if (fails) {
        pending.completeError(StateError('old benchmark'));
      } else {
        pending.complete();
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('peakRSS='), findsNothing);
      expect(find.text('การทดสอบประสิทธิภาพโมเดลไม่สำเร็จ'), findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(second.benchmarkCalls, 1);
      expect(find.textContaining('peakRSS='), findsNWidgets(2));
    });
  }

  testWidgets(
    'R15.6 unsupported result offers existing manual vocabulary route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final scanner = _FakeScanner()..captureResult = _fakeUnmappedScanResult();
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
      expect(find.text('ถ่ายใหม่'), findsOneWidget);
      await tester.tap(find.text('เพิ่มคำด้วยตนเอง'));
      await tester.pumpAndSettle();
      expect(find.byType(CategoriesPage), findsOneWidget);
      expect(scanner.acceptCalls, 0);
    },
  );

  testWidgets(
    'R15.6 actual scanner results remain readable at 200 percent text',
    (tester) async {
      await loadR15Fonts();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final mapped in [true, false]) {
        final scanner = _FakeScanner()
          ..captureResult = mapped
              ? _fakeObjectScanResult()
              : _fakeUnmappedScanResult();
        await tester.pumpWidget(
          MaterialApp(
            theme: M3Theme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: const ValueKey('synthetic-r15-surface'),
              child: ObjectScannerScreen(
                scanner: scanner,
                voice: VoiceUseCases(
                  provider: _FakeVoice(),
                  disposeProvider: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('object-scanner-capture-button')),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -700));
        await tester.pumpAndSettle();
        await captureR15Surface(
          tester,
          mapped
              ? 'r15-camera-mapped-text200'
              : 'r15-camera-unsupported-text200',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'R15.6 download cancellation keeps capture disabled and allows retry',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final pending = Completer<ModelDownloadRecord>();
      final scanner = _FakeScanner()
        ..modelRuntimeAvailable = false
        ..downloadPending = pending;
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
      final download = find.byKey(
        const ValueKey('object-scanner-download-model'),
      );
      await tester.tap(download);
      await tester.pump();
      expect(find.text('ยกเลิกดาวน์โหลด'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('object-scanner-capture-button')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(download);
      expect(scanner.downloadCancellation!.isCancelled, isTrue);
      pending.completeError(
        const ModelLifecycleException(ModelFailureCode.cancelled),
      );
      await tester.pumpAndSettle();
      expect(find.text('ยกเลิกการดาวน์โหลดแล้ว'), findsOneWidget);
      expect(find.text('ดาวน์โหลดโมเดลที่ตรวจสอบแล้ว'), findsOneWidget);
      expect(scanner.captureCalls, 0);
      final retry = Completer<ModelDownloadRecord>();
      scanner.downloadPending = retry;
      await tester.tap(download);
      await tester.pump();
      scanner.modelRuntimeAvailable = true;
      retry.complete(
        ModelDownloadRecord(
          id: 'model',
          modelVersion: 'model-v1',
          sourceUrl: 'https://example.invalid/model',
          expectedChecksum: 'synthetic',
          expectedBytes: 1,
          downloadedBytes: 1,
          retryCount: 0,
          state: ModelDownloadState.active,
          updatedAtUtc: DateTime.utc(2026, 9, 13),
        ),
      );
      await tester.pumpAndSettle();
      expect(scanner.initializeCalls, 2);
      expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
      expect(download, findsNothing);
      expect(find.byKey(const ValueKey('object-scanner-error')), findsNothing);
    },
  );

  testWidgets('R15.6 old download failure cannot replace new scanner state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pending = Completer<ModelDownloadRecord>();
    final first = _FakeScanner()
      ..modelRuntimeAvailable = false
      ..downloadPending = pending;
    final second = _FakeScanner();
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    Future<void> show(_FakeScanner scanner) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ObjectScannerScreen(scanner: scanner, voice: voice),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(first);
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-download-model')),
    );
    await tester.pump();
    await show(second);
    expect(first.downloadCancellation!.isCancelled, isTrue);
    pending.completeError(
      const ModelLifecycleException(ModelFailureCode.cancelled),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('object-scanner-error')), findsNothing);
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
  });

  testWidgets('R15.6 clears a displayed result after scanner replacement', (
    tester,
  ) async {
    final first = _FakeScanner();
    final second = _FakeScanner();
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    Future<void> show(_FakeScanner scanner) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ObjectScannerScreen(scanner: scanner, voice: voice),
        ),
      );
      await tester.pumpAndSettle();
    }

    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(first);
    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มเข้าคลัง'), findsOneWidget);
    await show(second);
    expect(find.text('apple'), findsNothing);
    expect(find.text('เพิ่มเข้าคลัง'), findsNothing);
    expect(second.acceptCalls, 0);
  });

  testWidgets(
    'R15.6 saving blocks duplicate accept and ignores old completion',
    (tester) async {
      final pending = Completer<void>();
      final first = _FakeScanner()..acceptPending = pending;
      final second = _FakeScanner();
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );
      Future<void> show(_FakeScanner scanner) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ObjectScannerScreen(scanner: scanner, voice: voice),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await show(first);
      await tester.tap(
        find.byKey(const ValueKey('object-scanner-capture-button')),
      );
      await tester.pumpAndSettle();
      final save = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'เพิ่มเข้าคลัง'),
          )
          .onPressed!;
      save();
      save();
      await tester.pump();
      expect(first.acceptCalls, 1);
      expect(find.text('กำลังบันทึก...'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('object-scanner-capture-button')),
            )
            .onPressed,
        isNull,
      );
      await show(second);
      await tester.tap(
        find.byKey(const ValueKey('object-scanner-capture-button')),
      );
      await tester.pumpAndSettle();
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('บันทึกแล้ว'), findsNothing);
      expect(find.text('เพิ่มเข้าคลัง'), findsOneWidget);
    },
  );

  testWidgets('R15.6 permission failure can retry initialization', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final scanner = _FakeScanner()
      ..initializeFailure = const CameraPracticeException(
        CameraFailureCode.permissionDenied,
      );
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
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('object-scanner-capture-button')),
          )
          .onPressed,
      isNull,
    );
    scanner.initializeFailure = null;
    await tester.tap(find.text('ลองเปิดกล้องอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('camera-preview')), findsOneWidget);
    expect(scanner.initializeCalls, 2);
  });

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
    expect(find.text('คะแนนจากโมเดล: 91.0%'), findsOneWidget);
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

  testWidgets('low model score asks the learner to retake the photo', (
    tester,
  ) async {
    final scanner = _FakeScanner()
      ..captureFailure = const CameraPracticeException(
        CameraFailureCode.notConfident,
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

    await tester.tap(
      find.byKey(const ValueKey('object-scanner-capture-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'ยังระบุวัตถุไม่ได้ กรุณาถ่ายใหม่ให้วัตถุอยู่กลางภาพและมีแสงเพียงพอ',
      ),
      findsOneWidget,
    );
    expect(find.text('รูปภาพนี้ไม่สามารถนำมาวิเคราะห์ได้'), findsNothing);
  });

  testWidgets('unmapped prediction copy stays bounded to model evidence', (
    tester,
  ) async {
    final scanner = _FakeScanner()..captureResult = _fakeUnmappedScanResult();
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

    expect(
      find.text(
        'โมเดลแสดงผลลัพธ์นี้ แต่ยังไม่มีคำแปลที่ตรวจสอบแล้วในคลังคำศัพท์',
      ),
      findsOneWidget,
    );
    expect(
      find.text('พบวัตถุจริง แต่ยังไม่มีคำแปลที่ตรวจสอบแล้วในคลังคำศัพท์'),
      findsNothing,
    );
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
    'restores model download after initialization fails while inactive',
    (tester) async {
      final pending = Completer<void>();
      final scanner = _FakeScanner()
        ..initializePending = pending
        ..modelRuntimeAvailable = false;
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(() {
        if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      });
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
      expect(scanner.acquireCalls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      pending.complete();
      await tester.pump();
      await tester.pump();
      expect(scanner.pauseCalls, 1);
      expect(scanner.isReady, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      // Resuming the camera cannot manufacture the missing model runtime.
      expect(scanner.acquireCalls, 1);
      expect(scanner.isReady, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('camera-preview')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('object-scanner-capture-button')),
            )
            .onPressed,
        isNull,
      );
      final downloadButton = find.byKey(
        const ValueKey('object-scanner-download-model'),
      );
      expect(downloadButton, findsOneWidget);
      expect(
        find.textContaining('ยังไม่มีโมเดลที่ตรวจสอบแล้ว'),
        findsOneWidget,
      );
      await tester.ensureVisible(downloadButton);
      expect(downloadButton.hitTestable(), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(downloadButton).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
  ObjectScanResult captureResult = _fakeObjectScanResult();
  Completer<void>? initializePending;
  Completer<void>? acceptPending;
  Completer<void>? benchmarkPending;
  Completer<void>? resumePending;
  Completer<ModelDownloadRecord>? downloadPending;
  ModelCancellation? downloadCancellation;
  bool modelRuntimeAvailable = true;
  final List<Completer<void>> initializePendings = [];
  final List<Completer<ObjectScanResult>> capturePendings = [];
  final List<ModelCancellation?> captureCancellations = [];
  int acceptCalls = 0;
  int acquireCalls = 0;
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
  ObjectScannerLease acquireLease() {
    acquireCalls += 1;
    return _leaseManager.acquire();
  }

  @override
  Future<VocabularyWord> accept(ObjectScanResult result) async {
    acceptCalls += 1;
    await acceptPending?.future;
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
  Future<ModelDownloadRecord> downloadModel({ModelCancellation? cancellation}) {
    downloadCancellation = cancellation;
    return downloadPending!.future;
  }

  @override
  Future<ModelDownloadRecord?> modelStatus() async => null;

  @override
  Future<List<ModelBenchmarkResult>> benchmarkModel({
    String deviceTier = 'field-device',
    int warmupRuns = 3,
    int measuredRuns = 20,
  }) async {
    benchmarkCalls += 1;
    await benchmarkPending?.future;
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
    return captureResult;
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
    if (!modelRuntimeAvailable) {
      throw const CameraPracticeException(CameraFailureCode.modelUnavailable);
    }
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
    await resumePending?.future;
    isReady = modelRuntimeAvailable;
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

ObjectScanResult _fakeUnmappedScanResult() => ObjectScanResult(
  classifications: const [
    ModelClassification(index: 2, label: 'Unknown', confidence: 0.78),
  ],
  vocabulary: null,
  matchedClassification: null,
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

const _scannerVoiceResult = VoicePlaybackResult(
  requestedEngine: VoiceEngine.nativeTts,
  actualEngine: VoiceEngine.nativeTts,
  usedFallback: false,
  cacheHit: false,
);

final class _DeferredScannerVoice implements VoiceProvider {
  final calls = <Completer<VoicePlaybackResult>>[];
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    final call = Completer<VoicePlaybackResult>();
    calls.add(call);
    return call.future;
  }

  @override
  Future<void> stop() async {}
}
