import 'dart:async';
import 'dart:math';

import '../../../runtime/circuit_breaker.dart';
import '../domain/gemini_contracts.dart';

/// Wraps a [GeminiGateway] with bounded retry + exponential backoff for
/// transient failures (timeout, quota, providerUnavailable, offline).
///
/// Non-retryable failures (invalidKey, blocked, cancelled, validation,
/// malformedResponse, missingKey, consentRequired) propagate immediately.
///
/// The retry budget is capped at [maxAttempts] total tries with jittered
/// exponential backoff between [baseDelay] and [baseDelay * 2^maxAttempts].
class RetryGeminiGateway implements GeminiGateway {
  RetryGeminiGateway(
    this._inner, {
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.random,
    CircuitBreaker? breaker,
  }) : _breaker =
           breaker ?? CircuitBreaker(shouldCountFailure: isTransientFailure);

  final GeminiGateway _inner;
  final int maxAttempts;
  final Duration baseDelay;
  final Random? random;
  final CircuitBreaker _breaker;

  static const _retryableCodes = {
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
    // Key validation: no retry — fail fast on auth issues.
    return _inner.validateKey(key, cancellation: cancellation);
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
      () => _inner.generateTutorReply(
        key: key,
        scenario: scenario,
        learnerMessage: learnerMessage,
        learningSummary: learningSummary,
        cancellation: cancellation,
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
      () => _inner.listModels(key, cancellation: cancellation),
      cancellation,
    );
  }

  Future<T> _withRetry<T>(
    Future<T> Function() op,
    GeminiCancellation? cancellation,
  ) async {
    try {
      return await _breaker.call(() => _retry(op, cancellation));
    } on CircuitBreakerOpenException {
      throw const GeminiException(GeminiFailureCode.providerUnavailable);
    }
  }

  Future<T> _retry<T>(
    Future<T> Function() op,
    GeminiCancellation? cancellation,
  ) async {
    var attempt = 0;
    for (;;) {
      attempt++;
      try {
        if (cancellation?.isCancelled ?? false) {
          throw const GeminiException(GeminiFailureCode.cancelled);
        }
        return await op();
      } on GeminiException catch (e) {
        if (attempt >= maxAttempts || !_retryableCodes.contains(e.code)) {
          rethrow;
        }
        if (cancellation?.isCancelled ?? false) {
          throw const GeminiException(GeminiFailureCode.cancelled);
        }
        final delay = _backoffDelay(attempt);
        await Future<void>.delayed(delay);
      }
    }
  }

  static bool isTransientFailure(Object error) {
    return error is GeminiException && _retryableCodes.contains(error.code);
  }

  Duration _backoffDelay(int attempt) {
    final exp = baseDelay * (1 << (attempt - 1));
    final jitter = random?.nextDouble() ?? 0.5;
    return Duration(
      milliseconds: (exp.inMilliseconds * (0.5 + jitter * 0.5)).round(),
    );
  }
}
