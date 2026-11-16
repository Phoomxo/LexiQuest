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

  test('empty transcript is unavailable rather than a zero score', () {
    final useCases = SpeechPracticeUseCases(_FakeSpeechGateway());
    expect(
      () => useCases.assess(
        target: 'practice',
        event: SpeechRecognitionEvent(
          transcript: '',
          isFinal: true,
          recognizedAtUtc: DateTime.utc(2026, 7, 30),
          engine: 'fake-device-stt',
          locale: 'en-US',
        ),
      ),
      throwsA(_failure(SpeechFailureCode.noMatch)),
    );
  });

  for (final stage in ['permission', 'initialize']) {
    for (final dispose in [false, true]) {
      test(
        '${dispose ? 'dispose' : 'cancel'} during $stage prevents start',
        () async {
          final gate = Completer<void>();
          final gateway = _FakeSpeechGateway()..emitResult = false;
          if (stage == 'permission') {
            gateway.permissionGate = gate;
          } else {
            gateway.initializeGate = gate;
          }
          final useCases = SpeechPracticeUseCases(gateway);
          final operation = _start(useCases);
          final expectation = expectLater(
            operation,
            throwsA(_failure(SpeechFailureCode.cancelled)),
          );
          await (stage == 'permission'
              ? gateway.permissionEntered.future
              : gateway.initializeEntered.future);
          if (dispose) {
            await useCases.dispose();
          } else {
            await useCases.cancel();
          }
          gate.complete();
          await expectation;
          expect(gateway.startCalls, 0);
          expect(gateway.cancelCalls, 1);
        },
      );
    }
  }

  test(
    'double start before permission resolves starts the engine once',
    () async {
      final gate = Completer<void>();
      final gateway = _FakeSpeechGateway()
        ..permissionGate = gate
        ..emitResult = false;
      final useCases = SpeechPracticeUseCases(gateway);
      final first = _start(useCases);
      final second = _start(useCases);
      expect(gateway.permissionRequests, 1);
      gate.complete();
      await Future.wait([first, second]);
      expect(gateway.initializeCalls, 1);
      expect(gateway.startCalls, 1);
    },
  );

  test(
    'cancel invalidates late result, status and failure before awaiting cleanup',
    () async {
      final gate = Completer<void>();
      final gateway = _FakeSpeechGateway()
        ..emitResult = false
        ..cancelGate = gate;
      final useCases = SpeechPracticeUseCases(gateway);
      final events = <SpeechRecognitionEvent>[];
      final failures = <SpeechFailureCode>[];
      final statuses = <String>[];
      await useCases.start(
        locale: 'en-US',
        onEvent: events.add,
        onFailure: failures.add,
        onStatus: statuses.add,
      );
      final cancel = useCases.cancel();
      gateway.emit('apple');
      gateway.onStatus!('listening');
      gateway.onFailure!(SpeechFailureCode.engine);
      expect(events, isEmpty);
      expect(statuses, isEmpty);
      expect(failures, isEmpty);
      gate.complete();
      await cancel;
    },
  );

  test('final is delivered once with original provenance', () async {
    final gateway = _FakeSpeechGateway()..emitResult = false;
    final useCases = SpeechPracticeUseCases(gateway);
    final events = <SpeechRecognitionEvent>[];
    final statuses = <String>[];
    await useCases.start(
      locale: 'en-US',
      onEvent: events.add,
      onFailure: (_) {},
      onStatus: statuses.add,
    );
    gateway.emit('apple');
    gateway.emit('banana');
    gateway.onStatus!('listening');
    expect(events, hasLength(1));
    expect(events.single.engine, 'fake-device-stt');
    expect(events.single.recognizedAtUtc, DateTime.utc(2026, 7, 30));
    expect(statuses, isEmpty);
  });

  test(
    'logical listening ends at final before the platform done status',
    () async {
      final gateway = _FakeSpeechGateway()..leaveListeningAfterFinal = true;
      final useCases = SpeechPracticeUseCases(gateway);
      await _start(useCases);
      expect(gateway.isListening, isTrue);
      expect(useCases.isListening, isFalse);
      gateway.isListening = false;
      gateway.onStatus!('done');
      expect(useCases.isListening, isFalse);
    },
  );

  test(
    'done without a final reports noMatch once and permits restart',
    () async {
      final gateway = _FakeSpeechGateway()..emitResult = false;
      final useCases = SpeechPracticeUseCases(gateway);
      final failures = <SpeechFailureCode>[];
      await useCases.start(
        locale: 'en-US',
        onEvent: (_) {},
        onFailure: failures.add,
        onStatus: (_) {},
      );
      gateway.isListening = false;
      gateway.onStatus!('done');
      gateway.onStatus!('done');
      expect(failures, [SpeechFailureCode.noMatch]);
      await _start(useCases);
      expect(gateway.startCalls, 2);
    },
  );

  test(
    'notListening preserves delayed final until a replacement starts',
    () async {
      final gateway = _FakeSpeechGateway()..emitResult = false;
      final useCases = SpeechPracticeUseCases(gateway);
      final events = <SpeechRecognitionEvent>[];
      await _start(useCases, onEvent: events.add);
      gateway.isListening = false;
      gateway.onStatus!('notListening');
      gateway.emit('apple');
      expect(events.single.transcript, 'apple');
      await _start(useCases, onEvent: events.add);
      final oldCallback = gateway.onEvent!;
      gateway.isListening = false;
      gateway.onStatus!('notListening');
      await _start(useCases, onEvent: events.add);
      oldCallback(
        SpeechRecognitionEvent(
          transcript: 'stale',
          isFinal: true,
          recognizedAtUtc: DateTime.utc(2026),
          engine: 'synthetic',
          locale: 'en-US',
        ),
      );
      expect(events, hasLength(1));
      expect(gateway.startCalls, 3);
    },
  );

  test('queued replacement cannot skip a failed compensating cancel', () async {
    final gate = Completer<void>();
    final gateway = _FakeSpeechGateway()
      ..startGate = gate
      ..emitResult = false;
    final useCases = SpeechPracticeUseCases(gateway);
    final first = expectLater(
      _start(useCases),
      throwsA(_failure(SpeechFailureCode.engine)),
    );
    await gateway.startEntered.future;
    await useCases.cancel();
    final replacement = expectLater(
      _start(useCases),
      throwsA(_failure(SpeechFailureCode.engine)),
    );
    gateway.cancelFailure = true;
    gate.complete();
    await first;
    await replacement;
    expect(gateway.startCalls, 1);
    gateway.cancelFailure = false;
    await useCases.cancel();
    await _start(useCases);
    expect(gateway.startCalls, 2);
  });

  test(
    'empty partial is ignored and empty final reports noMatch without an event',
    () async {
      final gateway = _FakeSpeechGateway()..emitResult = false;
      final useCases = SpeechPracticeUseCases(gateway);
      final events = <SpeechRecognitionEvent>[];
      final failures = <SpeechFailureCode>[];
      await useCases.start(
        locale: 'en-US',
        onEvent: events.add,
        onFailure: failures.add,
        onStatus: (_) {},
      );
      gateway.emit(' ', isFinal: false);
      expect(failures, isEmpty);
      gateway.emit(' ');
      gateway.emit('apple');
      expect(events, isEmpty);
      expect(failures, [SpeechFailureCode.noMatch]);
    },
  );

  test(
    'explicit stop preserves its final then allows the next session',
    () async {
      final gateway = _FakeSpeechGateway()
        ..emitResult = false
        ..emitOnStop = true;
      final useCases = SpeechPracticeUseCases(gateway);
      final events = <SpeechRecognitionEvent>[];
      await _start(useCases, onEvent: events.add);
      await useCases.stop();
      expect(events.single.transcript, 'apple');
      await _start(useCases, onEvent: events.add);
      gateway.emit('banana');
      expect(events.map((e) => e.transcript), ['apple', 'banana']);
    },
  );

  test('late startup failure after cancel remains cancellation', () async {
    final gate = Completer<void>();
    final gateway = _FakeSpeechGateway()..initializeGate = gate;
    final useCases = SpeechPracticeUseCases(gateway);
    final expectation = expectLater(
      _start(useCases),
      throwsA(_failure(SpeechFailureCode.cancelled)),
    );
    await gateway.initializeEntered.future;
    await useCases.cancel();
    gate.completeError(const SpeechPracticeException(SpeechFailureCode.engine));
    await expectation;
  });

  test(
    'failed cleanup blocks a new start until an explicit successful cancel',
    () async {
      final gateway = _FakeSpeechGateway()
        ..emitResult = false
        ..cancelFailure = true;
      final useCases = SpeechPracticeUseCases(gateway);
      await _start(useCases);
      await expectLater(
        useCases.cancel(),
        throwsA(_failure(SpeechFailureCode.engine)),
      );
      await expectLater(
        _start(useCases),
        throwsA(_failure(SpeechFailureCode.engine)),
      );
      expect(gateway.startCalls, 1);
      gateway.cancelFailure = false;
      await useCases.cancel();
      await _start(useCases);
      expect(gateway.startCalls, 2);
    },
  );

  test('duplicate final emitted synchronously by start is ignored', () async {
    final gateway = _FakeSpeechGateway()..duplicateResult = true;
    final events = <SpeechRecognitionEvent>[];
    await _start(SpeechPracticeUseCases(gateway), onEvent: events.add);
    expect(events, hasLength(1));
  });

  test(
    'late start completion after cancel is stopped before a replacement can listen',
    () async {
      final gate = Completer<void>();
      final gateway = _FakeSpeechGateway()
        ..startGate = gate
        ..emitResult = false;
      final useCases = SpeechPracticeUseCases(gateway);
      final events = <SpeechRecognitionEvent>[];
      final expectation = expectLater(
        _start(useCases, onEvent: events.add),
        throwsA(_failure(SpeechFailureCode.cancelled)),
      );
      await gateway.startEntered.future;
      await useCases.cancel();
      gate.complete();
      await expectation;
      expect(gateway.isListening, isFalse);
      expect(gateway.cancelCalls, 2);
      gateway.emit('late');
      expect(events, isEmpty);
      await _start(useCases, onEvent: events.add);
      gateway.emit('apple');
      expect(events.single.transcript, 'apple');
    },
  );

  test(
    'new start waits for cancelled startup and cleanup without reviving old callbacks',
    () async {
      final initialize = Completer<void>();
      final cleanup = Completer<void>();
      final gateway = _FakeSpeechGateway()
        ..initializeGate = initialize
        ..cancelGate = cleanup
        ..emitResult = false;
      final useCases = SpeechPracticeUseCases(gateway);
      final first = _start(useCases);
      final expectation = expectLater(
        first,
        throwsA(_failure(SpeechFailureCode.cancelled)),
      );
      await gateway.initializeEntered.future;
      final cancel = useCases.cancel();
      final events = <SpeechRecognitionEvent>[];
      final next = _start(useCases, onEvent: events.add);
      initialize.complete();
      await expectation;
      expect(gateway.startCalls, 0);
      cleanup.complete();
      await cancel;
      await next;
      gateway.emit('banana');
      expect(gateway.startCalls, 1);
      expect(events.single.transcript, 'banana');
    },
  );
}

Matcher _failure(SpeechFailureCode code) =>
    isA<SpeechPracticeException>().having((e) => e.code, 'code', code);

Future<void> _start(
  SpeechPracticeUseCases useCases, {
  SpeechEventCallback? onEvent,
}) => useCases.start(
  locale: 'en-US',
  onEvent: onEvent ?? (_) {},
  onFailure: (_) {},
  onStatus: (_) {},
);

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  MediaPermissionState permission = MediaPermissionState.granted;
  int permissionRequests = 0;
  int initializeCalls = 0;
  int startCalls = 0;
  int cancelCalls = 0;
  bool emitResult = true;
  bool emitOnStop = false;
  bool cancelFailure = false;
  bool duplicateResult = false;
  bool leaveListeningAfterFinal = false;
  Completer<void>? permissionGate;
  Completer<void>? initializeGate;
  Completer<void>? cancelGate;
  Completer<void>? startGate;
  final permissionEntered = Completer<void>();
  final initializeEntered = Completer<void>();
  final startEntered = Completer<void>();
  SpeechEventCallback? onEvent;
  SpeechFailureCallback? onFailure;
  void Function(String)? onStatus;
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    await cancelGate?.future;
    if (cancelFailure) {
      throw const SpeechPracticeException(SpeechFailureCode.engine);
    }
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {
    initializeCalls += 1;
    this.onFailure = onFailure;
    this.onStatus = onStatus;
    if (!initializeEntered.isCompleted) initializeEntered.complete();
    await initializeGate?.future;
  }

  @override
  Future<MediaPermissionState> requestPermission() async {
    permissionRequests += 1;
    if (!permissionEntered.isCompleted) permissionEntered.complete();
    await permissionGate?.future;
    return permission;
  }

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
    startCalls += 1;
    this.onEvent = onEvent;
    if (!startEntered.isCompleted) startEntered.complete();
    await startGate?.future;
    isListening = true;
    if (!emitResult) return;
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
    if (duplicateResult) emit('apple');
    if (!leaveListeningAfterFinal) isListening = false;
  }

  @override
  Future<void> stop() async {
    if (emitOnStop) emit('apple');
    isListening = false;
  }

  void emit(String transcript, {bool isFinal = true}) {
    onEvent!(
      SpeechRecognitionEvent(
        transcript: transcript,
        isFinal: isFinal,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'fake-device-stt',
        locale: 'en-US',
      ),
    );
  }
}
