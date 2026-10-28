enum CloudSyncPolicySource { build, cache, remote }

final class CloudSyncPolicy {
  CloudSyncPolicy({
    required this.enabled,
    required this.source,
    required this.fetchedAtUtc,
    required this.expiresAtUtc,
  }) {
    _requireUtc(fetchedAtUtc, 'fetchedAtUtc');
    _requireUtc(expiresAtUtc, 'expiresAtUtc');
    if (expiresAtUtc.isBefore(fetchedAtUtc)) {
      throw ArgumentError.value(
        expiresAtUtc,
        'expiresAtUtc',
        'must not be before fetchedAtUtc',
      );
    }
  }

  final bool enabled;
  final CloudSyncPolicySource source;
  final DateTime fetchedAtUtc;
  final DateTime expiresAtUtc;

  bool isExpiredAt(DateTime nowUtc) {
    _requireUtc(nowUtc, 'nowUtc');
    return !nowUtc.isBefore(expiresAtUtc);
  }
}

void _requireUtc(DateTime value, String field) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, field, 'must be UTC');
  }
}
