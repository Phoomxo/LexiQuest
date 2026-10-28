enum SyncFailureCode {
  invalidCursor,
  unsupportedSchema,
  offline,
  unauthenticated,
  permissionDenied,
  invalidPayload,
  quota,
  providerUnavailable,
}

sealed class SyncFailure implements Exception {
  const SyncFailure(this.code, {required this.retryable});

  final SyncFailureCode code;
  final bool retryable;

  @override
  String toString() => 'SyncFailure(${code.name})';
}

final class InvalidSyncCursorFailure extends SyncFailure {
  const InvalidSyncCursorFailure()
    : super(SyncFailureCode.invalidCursor, retryable: false);
}

final class UnsupportedSyncSchemaFailure extends SyncFailure {
  const UnsupportedSyncSchemaFailure()
    : super(SyncFailureCode.unsupportedSchema, retryable: false);
}

final class OfflineSyncFailure extends SyncFailure {
  const OfflineSyncFailure() : super(SyncFailureCode.offline, retryable: true);
}

final class UnauthenticatedSyncFailure extends SyncFailure {
  const UnauthenticatedSyncFailure()
    : super(SyncFailureCode.unauthenticated, retryable: false);
}

final class PermissionDeniedSyncFailure extends SyncFailure {
  const PermissionDeniedSyncFailure()
    : super(SyncFailureCode.permissionDenied, retryable: false);
}

/// A report upload was revoked at the final provider boundary.
///
/// This is distinct from a provider permission failure: the local report and
/// its pending outbox work remain durable and must not consume an attempt.
final class ContentReportConsentWithdrawnSyncFailure extends SyncFailure {
  const ContentReportConsentWithdrawnSyncFailure()
    : super(SyncFailureCode.permissionDenied, retryable: false);
}

final class InvalidSyncPayloadFailure extends SyncFailure {
  const InvalidSyncPayloadFailure()
    : super(SyncFailureCode.invalidPayload, retryable: false);
}

final class QuotaSyncFailure extends SyncFailure {
  const QuotaSyncFailure() : super(SyncFailureCode.quota, retryable: true);
}

final class ProviderUnavailableSyncFailure extends SyncFailure {
  const ProviderUnavailableSyncFailure()
    : super(SyncFailureCode.providerUnavailable, retryable: true);
}
