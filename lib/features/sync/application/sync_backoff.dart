import '../domain/sync_failure.dart';

final class SyncBackoff {
  const SyncBackoff({
    this.maximumDelay = const Duration(hours: 1),
    this.jitterFraction = 0.2,
  }) : assert(jitterFraction >= 0 && jitterFraction <= 1);

  final Duration maximumDelay;
  final double jitterFraction;

  DateTime nextAttemptAt({
    required DateTime nowUtc,
    required int attemptCount,
    required SyncFailure failure,
    double jitterUnit = 0,
  }) {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    if (attemptCount < 1) {
      throw RangeError.range(attemptCount, 1, null, 'attemptCount');
    }
    if (!failure.retryable) {
      throw ArgumentError.value(failure, 'failure', 'must be retryable');
    }
    if (jitterUnit < 0 || jitterUnit > 1) {
      throw RangeError.range(jitterUnit, 0, 1, 'jitterUnit');
    }

    final baseSeconds = failure is QuotaSyncFailure ? 60 : 2;
    final exponent = (attemptCount - 1).clamp(0, 20);
    final rawSeconds = baseSeconds * (1 << exponent);
    final cappedMilliseconds = (rawSeconds * 1000).clamp(
      0,
      maximumDelay.inMilliseconds,
    );
    final jitterMilliseconds =
        (cappedMilliseconds * jitterFraction * jitterUnit).round();
    final totalMilliseconds = (cappedMilliseconds + jitterMilliseconds).clamp(
      0,
      maximumDelay.inMilliseconds,
    );
    return nowUtc.add(Duration(milliseconds: totalMilliseconds));
  }
}
