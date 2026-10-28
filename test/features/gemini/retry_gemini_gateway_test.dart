import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/data/retry_gemini_gateway.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/runtime/circuit_breaker.dart';

void main() {
  test('opens after transient retry budgets and later probes', () async {
    var now = DateTime.utc(2026, 8, 9, 12);
    final inner = _FakeGateway(
      error: const GeminiException(GeminiFailureCode.providerUnavailable),
    );
    final breaker = CircuitBreaker(
      threshold: 2,
      resetDelay: const Duration(minutes: 1),
      now: () => now,
      shouldCountFailure: (error) =>
          error is GeminiException &&
          error.code == GeminiFailureCode.providerUnavailable,
    );
    final gateway = RetryGeminiGateway(
      inner,
      maxAttempts: 1,
      baseDelay: Duration.zero,
      breaker: breaker,
    );

    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
    expect(gateway.circuitState, CircuitState.open);
    await expectLater(
      _generate(gateway),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.circuitOpen,
        ),
      ),
    );
    expect(inner.calls, 2);

    now = now.add(const Duration(minutes: 1));
    inner.error = null;
    await expectLater(_generate(gateway), completion('reply'));
    expect(gateway.circuitState, CircuitState.closed);
  });

  test('invalid credentials do not trip the provider breaker', () async {
    final inner = _FakeGateway(
      error: const GeminiException(GeminiFailureCode.invalidKey),
    );
    final gateway = RetryGeminiGateway(
      inner,
      maxAttempts: 1,
      breaker: CircuitBreaker(
        threshold: 1,
        shouldCountFailure: (error) =>
            error is GeminiException &&
            error.code == GeminiFailureCode.providerUnavailable,
      ),
    );

    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
    expect(gateway.circuitState, CircuitState.closed);
    expect(inner.calls, 2);
  });

  test('cancellation interrupts retry backoff after one attempt', () async {
    final inner = _FakeGateway(
      error: const GeminiException(GeminiFailureCode.offline),
    );
    final gateway = RetryGeminiGateway(
      inner,
      baseDelay: const Duration(minutes: 1),
    );
    final cancellation = GeminiCancellation();
    final running = gateway.generateTutorReply(
      key: 'key',
      scenario: 'practice',
      learnerMessage: 'hello',
      cancellation: cancellation,
    );
    await Future<void>.delayed(Duration.zero);

    cancellation.cancel();

    await expectLater(
      running,
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.cancelled,
        ),
      ),
    );
    expect(inner.calls, 1);
  });

  test('all transient failures stop at exactly three total attempts', () async {
    final inner = _FakeGateway(
      error: const GeminiException(GeminiFailureCode.providerUnavailable),
    );
    final gateway = RetryGeminiGateway(
      inner,
      baseDelay: Duration.zero,
      maxAttempts: 3,
    );

    await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));

    expect(inner.calls, 3);
  });

  test(
    'caller cancellation remains first cause after the timeout deadline',
    () async {
      final inner = _FakeGateway(
        error: const GeminiException(GeminiFailureCode.providerUnavailable),
      );
      final breaker = CircuitBreaker(
        threshold: 1,
        resetDelay: Duration.zero,
        shouldCountFailure: RetryGeminiGateway.isTransientFailure,
        shouldKeepHalfOpen: (error) =>
            error is GeminiException &&
            error.code == GeminiFailureCode.cancelled,
      );
      final gateway = RetryGeminiGateway(
        inner,
        maxAttempts: 1,
        totalTimeout: const Duration(milliseconds: 20),
        breaker: breaker,
      );
      await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
      expect(gateway.circuitState, CircuitState.halfOpen);

      inner
        ..error = null
        ..entered = Completer<void>()
        ..cancellationCompletionDelay = const Duration(milliseconds: 50);
      final cancellation = GeminiCancellation();
      final operation = gateway.generateTutorReply(
        key: 'key',
        scenario: 'practice',
        learnerMessage: 'hello',
        cancellation: cancellation,
      );
      await inner.entered!.future;
      cancellation.cancel();

      await expectLater(
        operation,
        throwsA(
          isA<GeminiException>().having(
            (error) => error.code,
            'code',
            GeminiFailureCode.cancelled,
          ),
        ),
      );
      expect(gateway.circuitState, CircuitState.halfOpen);
    },
  );

  test(
    'absolute budget terminates a non-cooperative provider and counts it',
    () async {
      final lateReply = Completer<String>();
      final inner = _FakeGateway()..pendingReply = lateReply;
      final gateway = RetryGeminiGateway(
        inner,
        maxAttempts: 1,
        totalTimeout: const Duration(milliseconds: 20),
        breaker: CircuitBreaker(
          threshold: 1,
          shouldCountFailure: RetryGeminiGateway.isTransientFailure,
        ),
      );

      await expectLater(
        _generate(gateway).timeout(const Duration(seconds: 1)),
        throwsA(
          isA<GeminiException>().having(
            (error) => error.code,
            'code',
            GeminiFailureCode.timeout,
          ),
        ),
      );
      expect(gateway.circuitState, CircuitState.open);

      lateReply.complete('late reply');
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'caller cancellation releases a non-cooperative half-open probe',
    () async {
      final inner = _FakeGateway(
        error: const GeminiException(GeminiFailureCode.providerUnavailable),
      );
      final breaker = CircuitBreaker(
        threshold: 1,
        resetDelay: Duration.zero,
        shouldCountFailure: RetryGeminiGateway.isTransientFailure,
        shouldKeepHalfOpen: (error) =>
            error is GeminiException &&
            error.code == GeminiFailureCode.cancelled,
      );
      final gateway = RetryGeminiGateway(
        inner,
        maxAttempts: 1,
        totalTimeout: const Duration(seconds: 1),
        breaker: breaker,
      );
      await expectLater(_generate(gateway), throwsA(isA<GeminiException>()));
      expect(gateway.circuitState, CircuitState.halfOpen);

      final lateReply = Completer<String>();
      inner
        ..error = null
        ..pendingReply = lateReply
        ..entered = Completer<void>();
      final cancellation = GeminiCancellation();
      final cancelledProbe = gateway.generateTutorReply(
        key: 'key',
        scenario: 'practice',
        learnerMessage: 'hello',
        cancellation: cancellation,
      );
      await inner.entered!.future;
      cancellation.cancel();
      await expectLater(
        cancelledProbe.timeout(const Duration(seconds: 1)),
        throwsA(
          isA<GeminiException>().having(
            (error) => error.code,
            'code',
            GeminiFailureCode.cancelled,
          ),
        ),
      );
      expect(gateway.circuitState, CircuitState.halfOpen);

      inner
        ..pendingReply = null
        ..entered = null;
      expect(await _generate(gateway), 'reply');
      expect(gateway.circuitState, CircuitState.closed);
      lateReply.complete('late reply');
    },
  );
}

Future<String> _generate(RetryGeminiGateway gateway) {
  return gateway.generateTutorReply(
    key: 'key',
    scenario: 'practice',
    learnerMessage: 'hello',
  );
}

final class _FakeGateway implements GeminiGateway {
  _FakeGateway({this.error});

  GeminiException? error;
  Completer<void>? entered;
  Completer<String>? pendingReply;
  Duration? cancellationCompletionDelay;
  int calls = 0;

  @override
  String get model => 'fake';

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    calls++;
    entered?.complete();
    final pending = pendingReply;
    if (pending != null) return pending.future;
    final delayedCancellation = cancellationCompletionDelay;
    if (delayedCancellation != null) {
      await cancellation!.whenCancelled;
      await Future<void>.delayed(delayedCancellation);
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
    if (error case final failure?) throw failure;
    return 'reply';
  }

  @override
  Future<List<String>> listModels(
    String key, {
    GeminiCancellation? cancellation,
  }) async => const ['fake'];

  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {}
}
