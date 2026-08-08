import 'dart:async';

/// Simple circuit breaker for protecting downstream providers.
///
/// Tracks consecutive failures. After [threshold] consecutive failures the
/// circuit opens and short-circuits all calls for [resetDelay]. After the
/// delay it enters half-open: one call is allowed through; if it succeeds
/// the circuit closes, if it fails it re-opens.
///
/// Usage:
/// ```dart
/// final breaker = CircuitBreaker(threshold: 5, resetDelay: Duration(minutes: 1));
/// final result = await breaker.call(() => provider.fetch());
/// ```
class CircuitBreaker {
  CircuitBreaker({
    this.threshold = 5,
    this.resetDelay = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int threshold;
  final Duration resetDelay;
  final DateTime Function() _now;

  int _consecutiveFailures = 0;
  DateTime? _openedAt;

  /// Returns true when the circuit is open (calls should be short-circuited).
  bool get isOpen {
    final openedAt = _openedAt;
    if (openedAt == null) return false;
    if (_now().difference(openedAt) >= resetDelay) {
      // Half-open: allow the next call through.
      return false;
    }
    return true;
  }

  bool get isClosed => !isOpen;

  /// Executes [operation]. Throws [CircuitBreakerOpenException] when the
  /// circuit is open. On success, resets the failure counter. On failure,
  /// increments the counter and opens the circuit if the threshold is reached.
  Future<T> call<T>(Future<T> Function() operation) async {
    if (isOpen) {
      throw const CircuitBreakerOpenException();
    }
    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (e) {
      _onFailure();
      rethrow;
    }
  }

  void _onSuccess() {
    _consecutiveFailures = 0;
    _openedAt = null;
  }

  void _onFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= threshold) {
      _openedAt = _now();
    }
  }
}

/// Thrown when the circuit breaker is open and the call is short-circuited.
class CircuitBreakerOpenException implements Exception {
  const CircuitBreakerOpenException();

  @override
  String toString() => 'CircuitBreakerOpenException: circuit is open';
}
