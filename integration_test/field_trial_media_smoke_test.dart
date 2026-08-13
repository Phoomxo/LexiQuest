import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import 'support/field_trial_external_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'host fakes render camera microphone and model unavailable states',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-field-media-',
      );
      final databasePath =
          '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      final entryState = _GuestEntryStateStore();
      AppDependencies? mountedDependencies;

      try {
        final deniedCamera = _FakeCamera(MediaPermissionState.denied);
        final first = await _bootstrap(
          databasePath,
          entryState: entryState,
          camera: deniedCamera,
          speech: _FakeSpeech(MediaPermissionState.unavailable),
        ).initialize();
        mountedDependencies = first;
        final category = await first.vocabulary!.createCategory('Media words');
        await first.vocabulary!.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'station',
            meaning: 'transport stop',
            partOfSpeech: 'noun',
          ),
        );
        await tester.pumpWidget(MyApp(dependencies: first));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        await _openObjectScanner(tester);
        await tester.runAsync(
          () => deniedCamera.permissionRequested.future.timeout(
            const Duration(seconds: 1),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        deniedCamera.completePermission();
        await tester.pump();
        await _scrollUntilFound(
          tester,
          find.byKey(const ValueKey('object-scanner-error')),
          scrollable: find.descendant(
            of: find.byType(ObjectScannerScreen),
            matching: find.byType(ListView),
          ),
        );
        expect(deniedCamera.requestPermissionCalls, 1);
        expect(deniedCamera.initializeCalls, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(first.dispose);
        mountedDependencies = null;

        final grantedCamera = _FakeCamera(MediaPermissionState.granted);
        final second = await _bootstrap(
          databasePath,
          entryState: entryState,
          camera: grantedCamera,
          speech: _FakeSpeech(MediaPermissionState.unavailable),
        ).initialize();
        mountedDependencies = second;
        await tester.pumpWidget(MyApp(dependencies: second));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        await _openObjectScanner(tester);
        await tester.runAsync(
          () => grantedCamera.permissionRequested.future.timeout(
            const Duration(seconds: 1),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        grantedCamera.completePermission();
        await tester.pump();
        await _scrollUntilFound(
          tester,
          find.byKey(const ValueKey('object-scanner-error')),
          scrollable: find.descendant(
            of: find.byType(ObjectScannerScreen),
            matching: find.byType(ListView),
          ),
        );
        expect(grantedCamera.requestPermissionCalls, 1);
        expect(grantedCamera.initializeCalls, 1);
        expect(
          find.byKey(const ValueKey('object-scanner-download-model')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(second.dispose);
        mountedDependencies = null;

        final deniedSpeech = _FakeSpeech(MediaPermissionState.denied);
        final third = await _bootstrap(
          databasePath,
          entryState: entryState,
          camera: _FakeCamera(MediaPermissionState.unavailable),
          speech: deniedSpeech,
        ).initialize();
        mountedDependencies = third;
        await tester.pumpWidget(MyApp(dependencies: third));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        await tester.tap(find.byKey(const ValueKey('home/learn')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shadowing Challenge'));
        await _pumpUntilFound(tester, find.byType(ShadowingChallengeScreen));
        await _pumpUntilFound(tester, find.text('station'));
        await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
        await _pumpUntilFound(tester, find.textContaining('ไมโครโฟน'));
        expect(deniedSpeech.requestPermissionCalls, 1);

        expect(
          find.textContaining('physical device'),
          findsNothing,
          reason:
              'Host fake results must remain distinct from physical-device '
              'camera, microphone, and model evidence.',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (mountedDependencies case final dependencies?) {
          await tester.runAsync(dependencies.dispose);
        }
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

AppBootstrap _bootstrap(
  String databasePath, {
  required _GuestEntryStateStore entryState,
  required CameraGateway camera,
  required SpeechRecognitionGateway speech,
}) => AppBootstrap(
  initializeFirebase: () async => throw StateError('firebase unavailable'),
  initializeSupabase: () async => throw StateError('supabase unavailable'),
  loadConfig: () => throw StateError('backend config unavailable'),
  guestSessionService: _GuestSession(),
  createDatabase: () => AppDatabase(NativeDatabase(File(databasePath))),
  createEntryStateStore: () async => entryState,
  exportStoreFactory: HostFakeExportStore.new,
  cameraGatewayFactory: () => camera,
  speechRecognitionGatewayFactory: () => speech,
  buildAiTutor: (_) => throw StateError('host fake: AI unavailable'),
  buildVoice: (_) => _FakeVoice(),
);

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 250,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Widget did not appear after $maxPumps bounded pumps: $finder');
}

Future<void> _scrollUntilFound(
  WidgetTester tester,
  Finder target, {
  required Finder scrollable,
  int maxScrolls = 12,
}) async {
  for (var index = 0; index < maxScrolls; index++) {
    await tester.pump();
    if (target.evaluate().isNotEmpty) return;
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pump();
  }
  fail('Widget did not appear after $maxScrolls bounded scrolls: $target');
}

Future<void> _openObjectScanner(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
  await tester.pumpAndSettle();
  final target = find.byKey(const ValueKey('drawer/practice/object-scanner'));
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(target);
  await _pumpUntilFound(tester, find.byType(ObjectScannerScreen));
}

final class _GuestEntryStateStore implements AppEntryStateStore {
  @override
  Future<void> clear() async {}

  @override
  Future<void> markGuest() async {}

  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.firebaseUnavailable);
}

final class _FakeCamera implements CameraGateway {
  _FakeCamera(this.permission);

  final MediaPermissionState permission;
  final Completer<void> permissionRequested = Completer<void>();
  final Completer<MediaPermissionState> _permissionResult =
      Completer<MediaPermissionState>();
  int requestPermissionCalls = 0;
  int initializeCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;

  void completePermission() {
    if (!_permissionResult.isCompleted) _permissionResult.complete(permission);
  }

  @override
  bool isInitialized = false;

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);

  @override
  Future<CapturedImage> capture() async => CapturedImage(
    bytes: Uint8List(0),
    capturedAtUtc: DateTime.utc(2026, 8, 13),
    rotationDegrees: 0,
  );

  @override
  Future<void> dispose() async => isInitialized = false;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    isInitialized = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    isInitialized = false;
  }

  @override
  Future<MediaPermissionState> requestPermission() async {
    requestPermissionCalls += 1;
    if (!permissionRequested.isCompleted) permissionRequested.complete();
    return _permissionResult.future;
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
    isInitialized = true;
  }
}

final class _FakeSpeech implements SpeechRecognitionGateway {
  _FakeSpeech(this.permission);

  final MediaPermissionState permission;
  int requestPermissionCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async => isListening = false;

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async {
    requestPermissionCalls += 1;
    return permission;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async => isListening = true;

  @override
  Future<void> stop() async => isListening = false;
}

final class _FakeVoice implements ManagedVoiceProvider {
  @override
  Future<void> dispose() async {}

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async =>
      const VoicePlaybackResult(
        requestedEngine: VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
      );

  @override
  Future<void> stop() async {}
}
