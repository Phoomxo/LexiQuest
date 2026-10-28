import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  test(
    'starts only after microphone permission and preserves provenance',
    () async {
      final gateway = _FakeSpeechGateway();
      final useCases = SpeechPracticeUseCases(gateway);
      SpeechRecognitionEvent? received;

      await useCases.start(
        locale: 'en-US',
        onEvent: (event) => received = event,
        onFailure: (_) {},
        onStatus: (_) {},
      );

      expect(gateway.permissionRequests, 1);
      expect(gateway.initializeCalls, 1);
      expect(received!.transcript, 'apple');
      final assessment = useCases.assess(target: 'Apple', event: received!);
      expect(assessment.similarityPercent, 100);
      expect(assessment.isExactMatch, isTrue);
      expect(assessment.method, 'transcript-edit-distance-v1');
      expect(assessment.engine, 'fake-device-stt');
      expect(assessment.hasAcousticPitchMeasurement, isFalse);
      expect(assessment.hasPhonemeAlignment, isFalse);
    },
  );

  test('permission denial prevents recognizer initialization', () async {
    final gateway = _FakeSpeechGateway()
      ..permission = MediaPermissionState.denied;
    final useCases = SpeechPracticeUseCases(gateway);

    await expectLater(
      useCases.start(
        locale: 'en-US',
        onEvent: (_) {},
        onFailure: (_) {},
        onStatus: (_) {},
      ),
      throwsA(
        isA<SpeechPracticeException>().having(
          (error) => error.code,
          'code',
          SpeechFailureCode.permissionDenied,
        ),
      ),
    );

    expect(gateway.initializeCalls, 0);
  });

  test('empty or unmatched transcript never invents an acoustic score', () {
    final useCases = SpeechPracticeUseCases(_FakeSpeechGateway());
    final assessment = useCases.assess(
      target: 'practice',
      event: SpeechRecognitionEvent(
        transcript: '',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'fake-device-stt',
        locale: 'en-US',
      ),
    );

    expect(assessment.similarityPercent, 0);
    expect(assessment.hasAcousticPitchMeasurement, isFalse);
    expect(assessment.hasPhonemeAlignment, isFalse);
  });

  test(
    'sessions serialize takeover and stale consumers cannot cancel the owner',
    () async {
      final firstStart = Completer<void>();
      final secondStart = Completer<void>();
      final gateway = _ControlledSpeechGateway([firstStart, secondStart]);
      final useCases = SpeechPracticeUseCases(gateway);
      final first = useCases.acquireSession();

      final firstResult = first.start(
        locale: 'en-US',
        onEvent: (_) {},
        onFailure: (_) {},
        onStatus: (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(gateway.startCalls, 1);

      final second = useCases.acquireSession();
      final secondResult = second.start(
        locale: 'en-US',
        onEvent: (_) {},
        onFailure: (_) {},
        onStatus: (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(gateway.startCalls, 1);
      expect(gateway.cancelCalls, 0);

      firstStart.complete();
      expect(await firstResult, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(gateway.cancelCalls, 1);
      expect(gateway.startCalls, 2);

      secondStart.complete();
      expect(await secondResult, isTrue);
      expect(second.isListening, isTrue);

      await first.cancel();
      await first.release();
      expect(gateway.cancelCalls, 1);
      expect(second.isListening, isTrue);

      await second.cancel();
      expect(gateway.cancelCalls, 2);
      expect(second.isListening, isFalse);
    },
  );

  test('a failed session operation does not poison the next session', () async {
    final gateway = _ControlledSpeechGateway(const [])..failNextStart = true;
    final useCases = SpeechPracticeUseCases(gateway);
    final first = useCases.acquireSession();

    await expectLater(
      first.start(
        locale: 'en-US',
        onEvent: (_) {},
        onFailure: (_) {},
        onStatus: (_) {},
      ),
      throwsStateError,
    );

    final second = useCases.acquireSession();
    expect(
      await second.start(
        locale: 'en-US',
        onEvent: (_) {},
        onFailure: (_) {},
        onStatus: (_) {},
      ),
      isTrue,
    );
    expect(second.isListening, isTrue);
  });

  test('dispose drains a superseded pending start before returning', () async {
    final firstStart = Completer<void>();
    final gateway = _ControlledSpeechGateway([firstStart]);
    final useCases = SpeechPracticeUseCases(gateway);
    final first = useCases.acquireSession();

    final firstResult = first.start(
      locale: 'en-US',
      onEvent: (_) {},
      onFailure: (_) {},
      onStatus: (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(gateway.startCalls, 1);

    useCases.acquireSession();
    var disposeCompleted = false;
    final disposeFuture = useCases.dispose().then((_) {
      disposeCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);

    expect(disposeCompleted, isFalse);
    expect(gateway.cancelCalls, 0);

    firstStart.complete();
    expect(await firstResult, isFalse);
    await disposeFuture;

    expect(disposeCompleted, isTrue);
    expect(gateway.cancelCalls, 1);
    expect(gateway.isListening, isFalse);
  });
}

final class _ControlledSpeechGateway implements SpeechRecognitionGateway {
  _ControlledSpeechGateway(this.startCompletions);

  final List<Completer<void>> startCompletions;
  int startCalls = 0;
  int cancelCalls = 0;
  bool failNextStart = false;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    final call = startCalls++;
    if (failNextStart) {
      failNextStart = false;
      throw StateError('controlled start failure');
    }
    if (call < startCompletions.length) {
      await startCompletions[call].future;
    }
    isListening = true;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  MediaPermissionState permission = MediaPermissionState.granted;
  int permissionRequests = 0;
  int initializeCalls = 0;
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    initializeCalls += 1;
  }

  @override
  Future<MediaPermissionState> requestPermission() async {
    permissionRequests += 1;
    return permission;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    isListening = true;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'apple',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'fake-device-stt',
        locale: locale,
        recognitionConfidence: 0.8,
      ),
    );
    isListening = false;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}
