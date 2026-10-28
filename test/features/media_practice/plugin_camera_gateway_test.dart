import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/data/plugin_camera_gateway.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  const camera = CameraDescription(
    name: 'back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  test(
    'R15.6 unexpected initialization failure cleans session and can retry',
    () async {
      final failed = _FakeCameraSession();
      final ready = _FakeCameraSession()..completeInitialization();
      final sessions = [failed, ready];
      final gateway = PluginCameraGateway(
        discoverCameras: () async => [camera],
        createSession: (_) => sessions.removeAt(0),
      );
      final initialization = gateway.initialize();
      final expectation = expectLater(
        initialization,
        throwsA(
          isA<CameraPracticeException>().having(
            (e) => e.code,
            'code',
            CameraFailureCode.initializationFailed,
          ),
        ),
      );
      failed._initialization.completeError(StateError('native session failed'));
      await expectation;
      expect(failed.disposeCalls, 1);
      expect(gateway.isInitialized, isFalse);
      await gateway.initialize();
      expect(gateway.isInitialized, isTrue);
      await gateway.dispose();
      expect(ready.disposeCalls, 1);
    },
  );

  test('R15.6 repeated open pause resume closes every session once', () async {
    final sessions = <_FakeCameraSession>[];
    final gateway = PluginCameraGateway(
      discoverCameras: () async => [camera],
      createSession: (_) {
        final session = _FakeCameraSession()..completeInitialization();
        sessions.add(session);
        return session;
      },
    );
    for (var cycle = 0; cycle < 5; cycle++) {
      await gateway.resume();
      expect(gateway.isInitialized, isTrue);
      await gateway.pause();
      expect(gateway.isInitialized, isFalse);
    }
    await gateway.dispose();
    await gateway.dispose();
    expect(sessions, hasLength(5));
    expect(sessions.map((s) => s.disposeCalls), everyElement(1));
  });

  test('pause waits for an in-flight initialization and disposes it', () async {
    final session = _FakeCameraSession();
    final gateway = PluginCameraGateway(
      discoverCameras: () async => const [camera],
      createSession: (_) => session,
    );

    final initialization = gateway.initialize();
    final pause = gateway.pause();
    session.completeInitialization();

    await Future.wait([initialization, pause]);

    expect(session.disposeCalls, 1);
    expect(gateway.isInitialized, isFalse);
  });

  test('concurrent initialize calls share one camera session', () async {
    final session = _FakeCameraSession();
    var createCalls = 0;
    final gateway = PluginCameraGateway(
      discoverCameras: () async => const [camera],
      createSession: (_) {
        createCalls += 1;
        return session;
      },
    );

    final first = gateway.initialize();
    final second = gateway.initialize();
    session.completeInitialization();
    await Future.wait([first, second]);

    expect(createCalls, 1);
    expect(gateway.isInitialized, isTrue);
    await gateway.dispose();
    expect(session.disposeCalls, 1);
  });

  test('resume replaces an initialization invalidated by pause', () async {
    final staleSession = _FakeCameraSession();
    final resumedSession = _FakeCameraSession();
    final sessions = <_FakeCameraSession>[staleSession, resumedSession];
    var createCalls = 0;
    final gateway = PluginCameraGateway(
      discoverCameras: () async => const [camera],
      createSession: (_) => sessions[createCalls++],
    );

    final initialization = gateway.initialize();
    final pause = gateway.pause();
    final resume = gateway.resume();
    staleSession.completeInitialization();
    await initialization;
    await pause;
    await Future<void>.delayed(Duration.zero);
    resumedSession.completeInitialization();
    await resume;

    expect(createCalls, 2);
    expect(staleSession.disposeCalls, 1);
    expect(gateway.isInitialized, isTrue);
    await gateway.dispose();
  });
}

final class _FakeCameraSession implements CameraSession {
  final Completer<void> _initialization = Completer<void>();
  int disposeCalls = 0;
  bool _initialized = false;

  void completeInitialization() {
    _initialized = true;
    _initialization.complete();
  }

  @override
  bool get isInitialized => _initialized;

  @override
  int get sensorOrientation => 90;

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<void> initialize() => _initialization.future;

  @override
  Future<XFile> takePicture() => throw UnimplementedError();

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    _initialized = false;
  }
}
