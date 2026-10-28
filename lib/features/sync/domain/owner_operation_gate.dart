abstract interface class OwnerOperationGate {
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  });

  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  });

  Future<bool> isOwned({required String token, required DateTime nowUtc});

  Future<void> release({required String token});
}
