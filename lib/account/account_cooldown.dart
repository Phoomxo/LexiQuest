final class AccountCooldown {
  AccountCooldown({
    this.duration = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration duration;
  final DateTime Function() _now;
  DateTime? _expiresAt;

  bool get canSubmit => remaining == Duration.zero;

  Duration get remaining {
    final expiry = _expiresAt;
    if (expiry == null) return Duration.zero;
    final value = expiry.difference(_now());
    return value.isNegative ? Duration.zero : value;
  }

  void start() {
    _expiresAt = _now().add(duration);
  }
}
