import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/circuit_breaker.dart';

void main() {
  test(
    'F01 a failed probe permits exactly one probe after the next cooldown',
    () async {
      var now = DateTime.utc(2026);
      final breaker = CircuitBreaker(threshold: 1, now: () => now);
      await expectLater(
        breaker.call(() async => throw StateError('outage')),
        throwsStateError,
      );
      now = now.add(const Duration(seconds: 30));
      await expectLater(
        breaker.call(() async => throw StateError('probe outage')),
        throwsStateError,
      );
      now = now.add(const Duration(seconds: 30));
      expect(await breaker.call(() async => 42), 42);
    },
  );
  for (final lateFailure in [false, true]) {
    test(
      'F01 stale closed request cannot alter a new probe ($lateFailure)',
      () async {
        var now = DateTime.utc(2026);
        final breaker = CircuitBreaker(threshold: 1, now: () => now);
        final old = Completer<int>();
        final pending = breaker.call(() => old.future);
        final checked = lateFailure
            ? expectLater(pending, throwsStateError)
            : expectLater(pending, completion(7));
        await expectLater(
          breaker.call(() async => throw StateError('outage')),
          throwsStateError,
        );
        now = now.add(const Duration(seconds: 30));
        final release = Completer<int>();
        final probe = breaker.call(() => release.future);
        if (lateFailure) {
          old.completeError(StateError('old outage'));
        } else {
          old.complete(7);
        }
        await checked;
        expect(breaker.state, CircuitState.halfOpen);
        await expectLater(
          breaker.call(() async => 8),
          throwsA(isA<CircuitBreakerOpenException>()),
        );
        release.complete(9);
        expect(await probe, 9);
        expect(breaker.state, CircuitState.closed);
      },
    );
  }

  test(
    'F01 reset invalidates an old probe and its completion cannot release the new probe',
    () async {
      final breaker = CircuitBreaker(threshold: 1, resetDelay: Duration.zero);
      await expectLater(
        breaker.call(() async => throw StateError('outage')),
        throwsStateError,
      );
      final old = Completer<void>();
      final oldProbe = breaker.call(() => old.future);
      breaker.reset();
      await expectLater(
        breaker.call(() async => throw StateError('new outage')),
        throwsStateError,
      );
      final current = Completer<void>();
      final newProbe = breaker.call(() => current.future);
      old.complete();
      await oldProbe;
      await expectLater(
        breaker.call(() async {}),
        throwsA(isA<CircuitBreakerOpenException>()),
      );
      current.complete();
      await newProbe;
      expect(breaker.state, CircuitState.closed);
    },
  );

  test('opens at threshold and closes after a successful probe', () async {
    var now = DateTime.utc(2026, 8, 9, 12);
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
  });

  test('admits only one half-open probe', () async {
    var now = DateTime.utc(2026, 8, 9, 12);
    final breaker = CircuitBreaker(
      threshold: 1,
      resetDelay: const Duration(minutes: 1),
      now: () => now,
    );
    await expectLater(
      breaker.call<void>(() async => throw StateError('outage')),
      throwsStateError,
    );
    now = now.add(const Duration(minutes: 1));

    final release = Completer<void>();
    final probe = breaker.call<void>(() => release.future);
    await expectLater(
      breaker.call<void>(() async {}),
      throwsA(isA<CircuitBreakerOpenException>()),
    );
    release.complete();
    await probe;
  });

  test('counts only failures accepted by the predicate', () async {
    final breaker = CircuitBreaker(
      threshold: 1,
      shouldCountFailure: (error) => error is StateError,
    );

    await expectLater(
      breaker.call<void>(() async => throw ArgumentError('bad request')),
      throwsArgumentError,
    );
    expect(breaker.state, CircuitState.closed);

    await expectLater(
      breaker.call<void>(() async => throw StateError('outage')),
      throwsStateError,
    );
    expect(breaker.state, CircuitState.open);
  });

  test('non-transient half-open failure closes the outage breaker', () async {
    var now = DateTime.utc(2026, 8, 9, 12);
    final breaker = CircuitBreaker(
      threshold: 1,
      resetDelay: const Duration(minutes: 1),
      now: () => now,
      shouldCountFailure: (error) => error is StateError,
    );
    await expectLater(
      breaker.call<void>(() async => throw StateError('outage')),
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

  test('rejects invalid construction values', () {
    expect(() => CircuitBreaker(threshold: 0), throwsArgumentError);
    expect(
      () => CircuitBreaker(resetDelay: const Duration(seconds: -1)),
      throwsArgumentError,
    );
  });
}
