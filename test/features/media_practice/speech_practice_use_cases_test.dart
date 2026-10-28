import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';

void main() {
  test(
    'engine failure retires callbacks and permits a fresh attempt',
    () async {
      final gateway = _FinalOnStopSpeechGateway();
      final session = SpeechPracticeUseCases(gateway).acquireSession();
      final events = <SpeechRecognitionEvent>[];
      final failures = <SpeechFailureCode>[];
      await session.start(
        locale: 'en-US',
        onEvent: events.add,
        onFailure: failures.add,
        onStatus: (_) {},
      );
      gateway.emitFailure(SpeechFailureCode.engine);
      gateway.emitFinal();
      expect(events, isEmpty);
      expect(failures, [SpeechFailureCode.engine]);
      await session.start(
        locale: 'en-US',
        onEvent: events.add,
        onFailure: failures.add,
        onStatus: (_) {},
      );
      gateway.emitFinal();
      expect(events, hasLength(1));
    },
  );

  test(
    'failed start retires retained callback and reports a speech failure',
    () async {
      final completion = Completer<void>();
      final gateway = _ControlledSpeechGateway([completion]);
      final session = SpeechPracticeUseCases(gateway).acquireSession();
      final events = <SpeechRecognitionEvent>[];
      final start = session.start(
        locale: 'en-US',
        onEvent: events.add,
        onFailure: (_) {},
        onStatus: (_) {},
      );
      final assertion = expectLater(
        start,
        throwsA(isA<SpeechPracticeException>()),
      );
      await Future<void>.delayed(Duration.zero);
      completion.completeError(StateError('native start failed'));
      await assertion;
      gateway.emitFinalForStart(0, transcript: 'late');
      expect(events, isEmpty);
    },
  );

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
      final assessment = useCases.assess(target: 'Apple', event: received!)!;
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

    expect(
      assessment,
      isNull,
      reason: 'silence is missing evidence, not zero skill',
    );
  });

  for (final values in [
    ('', 'station', true),
    ('station', '   ', true),
    ('station', 'station', false),
  ]) {
    test('unscorable transcript ${values.toString()} has no assessment', () {
      final assessment = SpeechPracticeUseCases(_FakeSpeechGateway()).assess(
        target: values.$1,
        event: SpeechRecognitionEvent(
          transcript: values.$2,
          isFinal: values.$3,
          recognizedAtUtc: DateTime.utc(2026, 9, 14),
          engine: 'fixture',
          locale: 'en-US',
        ),
      );
      expect(assessment, isNull);
    });
  }

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
      throwsA(isA<SpeechPracticeException>()),
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

  test('queued stop survives release before a later owner starts', () async {
    final firstStart = Completer<void>();
    final gateway = _ControlledSpeechGateway([
      firstStart,
    ], emitFinalBeforeFirstStartReturns: true);
    final useCases = SpeechPracticeUseCases(gateway);
    final first = useCases.acquireSession();
    final firstEvents = <SpeechRecognitionEvent>[];
    Future<void>? queuedStop;

    final firstResult = first.start(
      locale: 'en-US',
      onEvent: (event) {
        firstEvents.add(event);
        if (event.isFinal) queuedStop = first.stop();
      },
      onFailure: (_) {},
      onStatus: (_) {},
    );
    await Future<void>.delayed(Duration.zero);

    expect(firstEvents, hasLength(1));
    expect(gateway.isListening, isFalse);
    expect(queuedStop, isNotNull);

    final second = useCases.acquireSession();
    final secondEvents = <SpeechRecognitionEvent>[];
    final secondResult = second.start(
      locale: 'en-US',
      onEvent: secondEvents.add,
      onFailure: (_) {},
      onStatus: (_) {},
    );
    await first.release();
    await Future<void>.delayed(Duration.zero);

    expect(gateway.startCalls, 1);
    expect(gateway.stopCalls, 0);

    firstStart.complete();
    expect(await firstResult, isFalse);
    await queuedStop!;
    expect(await secondResult, isTrue);

    expect(gateway.stopCalls, 1);
    expect(gateway.operations, [
      'start-1:entered',
      'start-1:returned',
      'stop',
      'start-2:entered',
      'start-2:returned',
    ]);
    gateway.emitFinalForStart(0, transcript: 'late stale final');
    expect(firstEvents, hasLength(1));
    expect(secondEvents, isEmpty);
    expect(second.isListening, isTrue);
  });

  test('stop accepts one final callback from the current attempt', () async {
    final gateway = _FinalOnStopSpeechGateway();
    final useCases = SpeechPracticeUseCases(gateway);
    final session = useCases.acquireSession();
    final events = <SpeechRecognitionEvent>[];
    await session.start(
      locale: 'en-US',
      onEvent: events.add,
      onFailure: (_) {},
      onStatus: (_) {},
    );

    await session.stop();

    expect(events.where((event) => event.isFinal), hasLength(1));
    expect(events.last.transcript, 'station');
  });

  test('stop accepts a final callback after the stop future returns', () async {
    final gateway = _FinalOnStopSpeechGateway(delayFinalUntilAfterStop: true);
    final useCases = SpeechPracticeUseCases(gateway);
    final session = useCases.acquireSession();
    final events = <SpeechRecognitionEvent>[];
    await session.start(
      locale: 'en-US',
      onEvent: events.add,
      onFailure: (_) {},
      onStatus: (_) {},
    );
    await session.stop();
    expect(events, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(events.where((event) => event.isFinal), hasLength(1));
  });

  test('cancel retires the attempt and drops a late final callback', () async {
    final gateway = _FinalOnStopSpeechGateway(emitFinalOnCancel: true);
    final useCases = SpeechPracticeUseCases(gateway);
    final session = useCases.acquireSession();
    final events = <SpeechRecognitionEvent>[];
    await session.start(
      locale: 'en-US',
      onEvent: events.add,
      onFailure: (_) {},
      onStatus: (_) {},
    );

    await session.cancel();

    expect(events, isEmpty);
  });

  test('noMatch after stop acknowledgement retires its late final', () async {
    final gateway = _FinalOnStopSpeechGateway(delayFinalUntilAfterStop: true);
    final useCases = SpeechPracticeUseCases(gateway);
    final session = useCases.acquireSession();
    final events = <SpeechRecognitionEvent>[];
    final failures = <SpeechFailureCode>[];
    await session.start(
      locale: 'en-US',
      onEvent: events.add,
      onFailure: failures.add,
      onStatus: (_) {},
    );
    await session.stop();
    gateway.emitFailure(SpeechFailureCode.noMatch);
    await Future<void>.delayed(Duration.zero);
    expect(failures, [SpeechFailureCode.noMatch]);
    expect(events, isEmpty);
  });

  test(
    'accepted final fences duplicate final and late failure without dropping cleanup',
    () async {
      final gateway = _FinalOnStopSpeechGateway();
      final useCases = SpeechPracticeUseCases(gateway);
      final session = useCases.acquireSession();
      final events = <SpeechRecognitionEvent>[];
      final failures = <SpeechFailureCode>[];
      await session.start(
        locale: 'en-US',
        onEvent: (event) {
          events.add(event);
          if (event.isFinal) session.stop().ignore();
        },
        onFailure: failures.add,
        onStatus: (_) {},
      );

      gateway.emitFinal();
      gateway.emitFailure(SpeechFailureCode.noMatch);
      gateway.emitFinal();
      await Future<void>.delayed(Duration.zero);

      expect(events.where((event) => event.isFinal), hasLength(1));
      expect(failures, isEmpty);
      expect(gateway.stopCalls, 1);
    },
  );
}

final class _FinalOnStopSpeechGateway implements SpeechRecognitionGateway {
  _FinalOnStopSpeechGateway({
    this.emitFinalOnCancel = false,
    this.delayFinalUntilAfterStop = false,
  });
  final bool emitFinalOnCancel;
  final bool delayFinalUntilAfterStop;
  SpeechEventCallback? _onEvent;
  SpeechFailureCallback? _onFailure;
  int stopCalls = 0;
  @override
  bool isListening = false;
  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;
  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    _onFailure = onFailure;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    isListening = true;
    _onEvent = onEvent;
  }

  void _emitFinal() => _onEvent?.call(
    SpeechRecognitionEvent(
      transcript: 'station',
      isFinal: true,
      recognizedAtUtc: DateTime.utc(2026, 9, 9),
      engine: 'synthetic',
      locale: 'en-US',
    ),
  );
  void emitFailure(SpeechFailureCode failure) => _onFailure?.call(failure);
  void emitFinal() => _emitFinal();
  @override
  Future<void> stop() async {
    stopCalls += 1;
    isListening = false;
    if (delayFinalUntilAfterStop) {
      Future<void>.delayed(Duration.zero, _emitFinal);
    } else {
      _emitFinal();
    }
  }

  @override
  Future<void> cancel() async {
    isListening = false;
    if (emitFinalOnCancel) _emitFinal();
  }
}

final class _ControlledSpeechGateway implements SpeechRecognitionGateway {
  _ControlledSpeechGateway(
    this.startCompletions, {
    this.emitFinalBeforeFirstStartReturns = false,
  });

  final List<Completer<void>> startCompletions;
  final bool emitFinalBeforeFirstStartReturns;
  final List<SpeechEventCallback> _eventCallbacks = <SpeechEventCallback>[];
  final List<String> operations = <String>[];
  int startCalls = 0;
  int stopCalls = 0;
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
    operations.add('start-${call + 1}:entered');
    if (failNextStart) {
      failNextStart = false;
      throw StateError('controlled start failure');
    }
    _eventCallbacks.add(onEvent);
    if (emitFinalBeforeFirstStartReturns && call == 0) {
      isListening = true;
      onEvent(_controlledFinalEvent('accepted final'));
      isListening = false;
    }
    if (call < startCompletions.length) {
      await startCompletions[call].future;
    }
    if (!(emitFinalBeforeFirstStartReturns && call == 0)) {
      isListening = true;
    }
    operations.add('start-${call + 1}:returned');
  }

  void emitFinalForStart(int call, {required String transcript}) {
    _eventCallbacks[call](_controlledFinalEvent(transcript));
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    operations.add('stop');
    isListening = false;
  }
}

SpeechRecognitionEvent _controlledFinalEvent(String transcript) =>
    SpeechRecognitionEvent(
      transcript: transcript,
      isFinal: true,
      recognizedAtUtc: DateTime.utc(2026, 9, 9),
      engine: 'synthetic-controlled',
      locale: 'en-US',
    );

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
