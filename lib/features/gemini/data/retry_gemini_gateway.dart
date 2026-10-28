import 'dart:async';
import 'dart:math';

import '../../../runtime/circuit_breaker.dart';
import '../domain/gemini_contracts.dart';

typedef GeminiRetryDelay =
    Future<void> Function(Duration duration, GeminiCancellation? cancellation);

/// Provider retry protection with at most three attempts inside one absolute
/// request budget. Cancellation interrupts both HTTP and retry delay.
final class RetryGeminiGateway implements GeminiGateway {
  RetryGeminiGateway(
    this._inner, {
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.totalTimeout = const Duration(seconds: 20),
    this.random,
    GeminiRetryDelay? delay,
    CircuitBreaker? breaker,
  }) : _delay = delay ?? _cancellableDelay,
       _breaker =
           breaker ??
           CircuitBreaker(
             shouldCountFailure: isTransientFailure,
             shouldKeepHalfOpen: _isCancellationFailure,
           ) {
    if (maxAttempts < 1 ||
        maxAttempts > 3 ||
        baseDelay < Duration.zero ||
        totalTimeout <= Duration.zero) {
      throw ArgumentError('Invalid Gemini retry configuration.');
    }
  }

  final GeminiGateway _inner;
  final int maxAttempts;
  final Duration baseDelay;
  final Duration totalTimeout;
  final Random? random;
  final GeminiRetryDelay _delay;
  final CircuitBreaker _breaker;

  static const Set<GeminiFailureCode> _retryableCodes = <GeminiFailureCode>{
    GeminiFailureCode.timeout,
    GeminiFailureCode.quota,
    GeminiFailureCode.rateLimited,
    GeminiFailureCode.providerUnavailable,
    GeminiFailureCode.offline,
  };

  @override
  String get model => _inner.model;

  CircuitState get circuitState => _breaker.state;

  @override
  Future<void> validateKey(String key, {GeminiCancellation? cancellation}) {
    return _throughBreaker(
      (linked) => _inner.validateKey(key, cancellation: linked),
      cancellation,
    );
  }

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) {
    return _withRetry(
      (linked) => _inner.generateTutorReply(
        key: key,
        scenario: scenario,
        learnerMessage: learnerMessage,
        learningSummary: learningSummary,
        cancellation: linked,
      ),
      cancellation,
    );
  }

  @override
  Future<List<String>> listModels(
    String key, {
    GeminiCancellation? cancellation,
  }) {
    return _withRetry(
      (linked) => _inner.listModels(key, cancellation: linked),
      cancellation,
    );
  }

  Future<T> _withRetry<T>(
    Future<T> Function(GeminiCancellation cancellation) operation,
    GeminiCancellation? cancellation,
  ) => _throughBreaker(
    (linked) => _retry(() => operation(linked), linked),
    cancellation,
  );

  Future<T> _throughBreaker<T>(
    Future<T> Function(GeminiCancellation cancellation) operation,
    GeminiCancellation? cancellation,
  ) async {
    // A pre-cancelled request wins even when the provider circuit is open.
    if (cancellation?.isCancelled ?? false) {
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
    try {
      // The hard deadline is inside the breaker call so a timeout is counted
      // and a cancelled half-open probe releases its in-flight slot promptly.
      return await _breaker.call(() => _withBudget(operation, cancellation));
    } on CircuitBreakerOpenException {
      throw const GeminiException(GeminiFailureCode.circuitOpen);
    }
  }

  Future<T> _withBudget<T>(
    Future<T> Function(GeminiCancellation cancellation) operation,
    GeminiCancellation? cancellation,
  ) {
    if (cancellation?.isCancelled ?? false) {
      return Future<T>.error(
        const GeminiException(GeminiFailureCode.cancelled),
      );
    }
    final linked = GeminiCancellation();
    final terminal = Completer<T>();
    _GeminiBudgetAbortCause? abortCause;
    Timer? callerSettlement;
    void abort(_GeminiBudgetAbortCause cause) {
      if (abortCause != null) return;
      abortCause = cause;
      linked.cancel();
      if (cause == _GeminiBudgetAbortCause.caller) {
        // Give an already-drained provider response one microtask turn to
        // finish parsing before cancellation wins. This preserves a completed
        // paid response while still bounding a non-cooperative provider.
        callerSettlement = Timer(Duration.zero, () {
          if (!terminal.isCompleted) {
            terminal.completeError(
              const GeminiException(GeminiFailureCode.cancelled),
              StackTrace.current,
            );
          }
        });
      }
    }

    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then(
          (_) => abort(_GeminiBudgetAbortCause.caller),
        ),
      );
    }
    final timeoutTimer = Timer(totalTimeout, () {
      abort(_GeminiBudgetAbortCause.timeout);
      if (!terminal.isCompleted) {
        terminal.completeError(
          GeminiException(
            abortCause == _GeminiBudgetAbortCause.caller
                ? GeminiFailureCode.cancelled
                : GeminiFailureCode.timeout,
          ),
          StackTrace.current,
        );
      }
    });
    final providerOperation = Future<T>.sync(() => operation(linked));
    unawaited(
      providerOperation.then<void>(
        (value) {
          if (!terminal.isCompleted) terminal.complete(value);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (terminal.isCompleted) return;
          final mapped = switch (abortCause) {
            _GeminiBudgetAbortCause.caller => const GeminiException(
              GeminiFailureCode.cancelled,
            ),
            _GeminiBudgetAbortCause.timeout => const GeminiException(
              GeminiFailureCode.timeout,
            ),
            null => error,
          };
          terminal.completeError(mapped, stackTrace);
        },
      ),
    );
    return terminal.future.whenComplete(() {
      timeoutTimer.cancel();
      callerSettlement?.cancel();
    });
  }

  Future<T> _retry<T>(
    Future<T> Function() operation,
    GeminiCancellation cancellation,
  ) async {
    for (var attempt = 1; ; attempt++) {
      if (cancellation.isCancelled) {
        throw const GeminiException(GeminiFailureCode.cancelled);
      }
      try {
        return await operation();
      } on GeminiException catch (error) {
        if (attempt >= maxAttempts || !_retryableCodes.contains(error.code)) {
          rethrow;
        }
        if (cancellation.isCancelled) {
          throw const GeminiException(GeminiFailureCode.cancelled);
        }
        await _delay(_backoffDelay(attempt), cancellation);
      }
    }
  }

  static bool isTransientFailure(Object error) =>
      error is GeminiException && _retryableCodes.contains(error.code);

  static bool _isCancellationFailure(Object error) =>
      error is GeminiException && error.code == GeminiFailureCode.cancelled;

  Duration _backoffDelay(int attempt) {
    final exponential = baseDelay * (1 << (attempt - 1));
    final jitter = random?.nextDouble() ?? 0.5;
    return Duration(
      milliseconds: (exponential.inMilliseconds * (0.5 + jitter * 0.5)).round(),
    );
  }
}

enum _GeminiBudgetAbortCause { caller, timeout }

Future<void> _cancellableDelay(
  Duration duration,
  GeminiCancellation? cancellation,
) {
  if (cancellation?.isCancelled ?? false) {
    return Future<void>.error(
      const GeminiException(GeminiFailureCode.cancelled),
    );
  }
  final completer = Completer<void>();
  final timer = Timer(duration, completer.complete);
  if (cancellation != null) {
    unawaited(
      cancellation.whenCancelled.then((_) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            const GeminiException(GeminiFailureCode.cancelled),
          );
        }
      }),
    );
  }
  return completer.future;
}
