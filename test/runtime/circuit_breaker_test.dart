import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/circuit_breaker.dart';

void main() {
  test(
    'opens after the bounded failure threshold and short-circuits calls',
    () async {
      var now = DateTime.utc(2026, 8, 8, 12);
      var calls = 0;
      final breaker = CircuitBreaker(
        threshold: 2,
        resetDelay: const Duration(minutes: 1),
        now: () => now,
      );

      Future<void> fail() async {
        calls++;
        throw StateError('provider unavailable');
      }

      await expectLater(breaker.call<void>(fail), throwsStateError);
      await expectLater(breaker.call<void>(fail), throwsStateError);

      expect(breaker.state, CircuitState.open);
      await expectLater(
        breaker.call<void>(fail),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
      expect(calls, 2);

      now = now.add(const Duration(minutes: 1));
      expect(breaker.state, CircuitState.halfOpen);
      await breaker.call<void>(() async {});
      expect(breaker.state, CircuitState.closed);
    },
  );

  test('allows only one half-open probe at a time', () async {
    var now = DateTime.utc(2026, 8, 8, 12);
    final breaker = CircuitBreaker(
      threshold: 1,
      resetDelay: const Duration(minutes: 1),
      now: () => now,
    );

    await expectLater(
      breaker.call<void>(() async => throw StateError('first failure')),
      throwsStateError,
    );
    now = now.add(const Duration(minutes: 1));

    final releaseProbe = Completer<void>();
    final probe = breaker.call<void>(() => releaseProbe.future);
    expect(breaker.state, CircuitState.halfOpen);
    await expectLater(
      breaker.call<void>(() async {}),
      throwsA(isA<CircuitBreakerOpenException>()),
    );

    releaseProbe.complete();
    await probe;
    expect(breaker.state, CircuitState.closed);
  });

  test('reopens after a failed half-open probe', () async {
    var now = DateTime.utc(2026, 8, 8, 12);
    final breaker = CircuitBreaker(
      threshold: 1,
      resetDelay: const Duration(minutes: 1),
      now: () => now,
    );

    await expectLater(
      breaker.call<void>(() async => throw StateError('first failure')),
      throwsStateError,
    );
    now = now.add(const Duration(minutes: 1));
    await expectLater(
      breaker.call<void>(() async => throw StateError('probe failure')),
      throwsStateError,
    );

    expect(breaker.state, CircuitState.open);
  });

  test('does not count failures rejected by the predicate', () async {
    final breaker = CircuitBreaker(
      threshold: 1,
      shouldCountFailure: (error) => error is StateError,
    );

    await expectLater(
      breaker.call<void>(() async => throw ArgumentError('bad input')),
      throwsArgumentError,
    );
    expect(breaker.state, CircuitState.closed);

    await expectLater(
      breaker.call<void>(() async => throw StateError('provider failure')),
      throwsStateError,
    );
    expect(breaker.state, CircuitState.open);
  });

  test('closes after a non-counted half-open probe failure', () async {
    var now = DateTime.utc(2026, 8, 8, 12);
    final breaker = CircuitBreaker(
      threshold: 1,
      resetDelay: const Duration(minutes: 1),
      now: () => now,
      shouldCountFailure: (error) => error is StateError,
    );

    await expectLater(
      breaker.call<void>(() async => throw StateError('provider failure')),
      throwsStateError,
    );
    now = now.add(const Duration(minutes: 1));

    await expectLater(
      breaker.call<void>(() async => throw ArgumentError('invalid key')),
      throwsArgumentError,
    );

    expect(breaker.state, CircuitState.closed);
    expect(breaker.consecutiveFailures, 0);
  });

  test('rejects invalid construction thresholds', () {
    expect(() => CircuitBreaker(threshold: 0), throwsA(isA<ArgumentError>()));
    expect(
      () => CircuitBreaker(resetDelay: const Duration(seconds: -1)),
      throwsA(isA<ArgumentError>()),
    );
  });
}
