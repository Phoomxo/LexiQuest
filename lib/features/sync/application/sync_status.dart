final class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.ownerId,
    this.pending = 0,
    this.retryWaiting = 0,
    this.inFlight = 0,
    this.blockedAuth = 0,
    this.permanentFailure = 0,
    this.handledConflicts = 0,
  });

  final String ownerId;
  final int pending;
  final int retryWaiting;
  final int inFlight;
  final int blockedAuth;
  final int permanentFailure;
  final int handledConflicts;

  @override
  bool operator ==(Object other) =>
      other is SyncStatusSnapshot &&
      ownerId == other.ownerId &&
      pending == other.pending &&
      retryWaiting == other.retryWaiting &&
      inFlight == other.inFlight &&
      blockedAuth == other.blockedAuth &&
      permanentFailure == other.permanentFailure &&
      handledConflicts == other.handledConflicts;

  @override
  int get hashCode => Object.hash(
    ownerId,
    pending,
    retryWaiting,
    inFlight,
    blockedAuth,
    permanentFailure,
    handledConflicts,
  );
}

abstract interface class SyncStatusSource {
  Stream<SyncStatusSnapshot?> watchCurrentOwnerSyncStatus();
}
