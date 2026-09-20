import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speaking_capture.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  late Gateway gateway;
  late SpeakingCapture capture;
  var current = true;
  setUp(() {
    current = true;
    gateway = Gateway();
    capture = SpeakingCapture(
      speech: SpeechPracticeUseCases(gateway),
      requireCurrent: () async {
        if (!current) throw StateError('retired');
      },
      timeout: const Duration(milliseconds: 30),
    );
  });
  tearDown(() async {
    await capture.close();
    capture.dispose();
  });
  test(
    'takeover during permission wait clears the rejected start immediately',
    () async {
      final permission = Completer<MediaPermissionState>();
      gateway.permissionResult = permission.future;
      final start = capture.start();
      await Future<void>.delayed(Duration.zero);
      final replacement = capture.speech.acquireSession();
      permission.complete(MediaPermissionState.granted);
      await start;
      expect(gateway.callback, isNull);
      expect(capture.listening, isFalse);
      expect(capture.operationId, isNull);
      await replacement.release();
    },
  );
  test('permission completion after close never starts recognition', () async {
    final permission = Completer<MediaPermissionState>();
    gateway.permissionResult = permission.future;
    final start = capture.start();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final closed = capture.close();
    permission.complete(MediaPermissionState.granted);
    await start;
    await closed;
    expect(gateway.callback, isNull);
    expect(capture.event, isNull);
  });
  test(
    'retry waits for retained native cancellation acknowledgement',
    () async {
      await capture.start();
      final old = gateway.callback;
      final cleanup = Completer<void>();
      gateway.cancellationResult = cleanup.future;
      final cancelled = capture.cancel();
      final retry = capture.start();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(gateway.callback, same(old));
      cleanup.complete();
      await cancelled;
      await retry;
      expect(gateway.callback, isNot(same(old)));
    },
  );
  test(
    'stop accepts one final result and rejects duplicate completion',
    () async {
      await capture.start();
      await capture.stop();
      gateway.emit('i read a book', true);
      gateway.emit('duplicate', true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(capture.event?.transcript, 'i read a book');
      expect(capture.confirmed, isFalse);
    },
  );
  test(
    'takeover while callback validation awaits rejects the old transcript',
    () async {
      await capture.start();
      gateway.emit('old session transcript', true);
      final replacement = capture.speech.acquireSession();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(capture.event, isNull);
      await replacement.release();
    },
  );
  test(
    'final transcript needs explicit confirmation and has stable attempt identity',
    () async {
      await capture.start();
      final id = capture.operationId;
      gateway.emit('i read a book', true);
      await Future<void>.delayed(Duration.zero);
      expect(capture.event?.transcript, 'i read a book');
      expect(capture.confirmed, isFalse);
      await capture.confirm();
      expect(capture.confirmed, isTrue);
      expect(capture.operationId, id);
    },
  );
  test('cancel and retry discard old callbacks and drain cleanup', () async {
    await capture.start();
    final old = gateway.callback!;
    final oldId = capture.operationId;
    await capture.cancel();
    await capture.start();
    old(event('late', true));
    await Future<void>.delayed(Duration.zero);
    expect(capture.event, isNull);
    expect(capture.operationId, isNot(oldId));
    expect(gateway.cancels, greaterThan(0));
  });
  test('owner invalidation prevents late transcript delivery', () async {
    await capture.start();
    current = false;
    gateway.emit('secret owner a', true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(capture.event, isNull);
    expect(capture.confirmed, isFalse);
  });
  test(
    'permission denial is retryable without fabricated transcript',
    () async {
      gateway.permission = MediaPermissionState.denied;
      await capture.start();
      expect(capture.failure, contains('permissionDenied'));
      expect(capture.event, isNull);
      gateway.permission = MediaPermissionState.granted;
      await capture.start();
      expect(capture.listening, isTrue);
    },
  );
  test('timeout retires callbacks and exposes repeat without scores', () async {
    await capture.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(capture.failure, contains('timed out'));
    gateway.emit('late', true);
    await Future<void>.delayed(Duration.zero);
    expect(capture.event, isNull);
    expect(capture.listening, isFalse);
  });
  test(
    'engine offline failure cannot be followed by accepted transcript',
    () async {
      await capture.start();
      gateway.failure!(SpeechFailureCode.engine);
      gateway.emit('late', true);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(capture.failure, contains('engine'));
      expect(capture.event, isNull);
    },
  );
  test('empty and partial finality cannot be confirmed', () async {
    await capture.start();
    gateway.emit('partial', false);
    await Future<void>.delayed(Duration.zero);
    await capture.confirm();
    expect(capture.confirmed, isFalse);
    gateway.emit('', true);
    await Future<void>.delayed(Duration.zero);
    await capture.confirm();
    expect(capture.confirmed, isFalse);
  });
}

SpeechRecognitionEvent event(String text, bool finalResult) =>
    SpeechRecognitionEvent(
      transcript: text,
      isFinal: finalResult,
      recognizedAtUtc: DateTime.utc(2026),
      engine: 'local-test-gateway',
      locale: 'en-US',
    );

class Gateway implements SpeechRecognitionGateway {
  SpeechEventCallback? callback;
  SpeechFailureCallback? failure;
  MediaPermissionState permission = MediaPermissionState.granted;
  @override
  bool isListening = false;
  int cancels = 0;
  Future<MediaPermissionState>? permissionResult;
  Future<void>? cancellationResult;
  void emit(String text, bool finalResult) =>
      callback!(event(text, finalResult));
  @override
  Future<MediaPermissionState> requestPermission() async =>
      permissionResult == null ? permission : await permissionResult!;
  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String) onStatus,
  }) async {
    failure = onFailure;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    callback = onEvent;
    isListening = true;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }

  @override
  Future<void> cancel() async {
    await cancellationResult;
    isListening = false;
    cancels++;
  }
}
