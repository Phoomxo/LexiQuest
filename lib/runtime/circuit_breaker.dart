/// Bounded protection for downstream providers.
///
/// The breaker has three states: closed, open, and half-open. Once the
/// configured failure threshold is reached, calls are rejected until the
/// cooldown expires. Exactly one probe is admitted in half-open state; all
/// concurrent callers remain fail-closed until that probe succeeds or fails.
enum CircuitState { closed, open, halfOpen }

final class CircuitBreaker {
  CircuitBreaker({
    this.threshold = 5,
    this.resetDelay = const Duration(seconds: 30),
    DateTime Function()? now,
    bool Function(Object error)? shouldCountFailure,
  }) : _now = now ?? DateTime.now,
       _shouldCountFailure = shouldCountFailure ?? _alwaysCountFailure {
    if (threshold <= 0) {
      throw ArgumentError.value(threshold, 'threshold', 'must be positive');
    }
    if (resetDelay.isNegative) {
      throw ArgumentError.value(
        resetDelay,
        'resetDelay',
        'must not be negative',
      );
    }
  }

  final int threshold;
  final Duration resetDelay;
  final DateTime Function() _now;
  final bool Function(Object error) _shouldCountFailure;

  CircuitState _state = CircuitState.closed;
  int _consecutiveFailures = 0;
  DateTime? _openedAt;
  bool _halfOpenProbeInFlight = false;

  CircuitState get state {
    _refreshState();
    return _state;
  }

  bool get isOpen => state == CircuitState.open;

  bool get isClosed => state == CircuitState.closed;

  bool get isHalfOpen => state == CircuitState.halfOpen;

  int get consecutiveFailures => _consecutiveFailures;

  DateTime? get openedAt => _openedAt;

  Future<T> call<T>(Future<T> Function() operation) async {
    _refreshState();
    if (_state == CircuitState.open ||
        (_state == CircuitState.halfOpen && _halfOpenProbeInFlight)) {
      throw const CircuitBreakerOpenException();
    }

    final isProbe = _state == CircuitState.halfOpen;
    if (isProbe) {
      _halfOpenProbeInFlight = true;
    }

    try {
      final result = await operation();
      _onSuccess();
      return result;
    } catch (error) {
      if (_shouldCountFailure(error)) {
        _onFailure();
      } else if (isProbe) {
        // A non-transient probe failure (for example auth or validation)
        // does not indicate a provider outage. Leave outage protection
        // closed so the next request is not forced through an immediate
        // half-open probe.
        _onSuccess();
      }
      rethrow;
    } finally {
      if (isProbe) {
        _halfOpenProbeInFlight = false;
      }
    }
  }

  void reset() {
    _state = CircuitState.closed;
    _consecutiveFailures = 0;
    _openedAt = null;
    _halfOpenProbeInFlight = false;
  }

  void _refreshState() {
    if (_state != CircuitState.open || _openedAt == null) return;
    if (_now().difference(_openedAt!) >= resetDelay) {
      _state = CircuitState.halfOpen;
    }
  }

  void _onSuccess() {
    _consecutiveFailures = 0;
    _openedAt = null;
    _state = CircuitState.closed;
  }

  void _onFailure() {
    if (_state == CircuitState.halfOpen ||
        ++_consecutiveFailures >= threshold) {
      _openedAt = _now();
      _state = CircuitState.open;
    }
  }

  static bool _alwaysCountFailure(Object error) => true;
}

final class CircuitBreakerOpenException implements Exception {
  const CircuitBreakerOpenException();

  @override
  String toString() => 'CircuitBreakerOpenException: circuit is open';
}
