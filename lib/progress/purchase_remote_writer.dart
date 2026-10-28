enum PurchaseRemoteFailure {
  unauthenticated,
  invalidRequest,
  productUnavailable,
  preconditionFailed,
  unavailable,
  unknown,
}

sealed class PurchaseRemoteResult {
  const PurchaseRemoteResult();
}

final class PurchaseRemoteAccepted extends PurchaseRemoteResult {
  const PurchaseRemoteAccepted({
    required this.alreadyOwned,
    required this.remainingPoints,
  });

  final bool alreadyOwned;
  final int remainingPoints;

  @override
  bool operator ==(Object other) {
    return other is PurchaseRemoteAccepted &&
        other.alreadyOwned == alreadyOwned &&
        other.remainingPoints == remainingPoints;
  }

  @override
  int get hashCode => Object.hash(alreadyOwned, remainingPoints);
}

final class PurchaseRemoteRejected extends PurchaseRemoteResult {
  const PurchaseRemoteRejected(this.failure);

  final PurchaseRemoteFailure failure;

  @override
  bool operator ==(Object other) {
    return other is PurchaseRemoteRejected && other.failure == failure;
  }

  @override
  int get hashCode => failure.hashCode;
}

abstract interface class PurchaseRemoteWriter {
  Future<PurchaseRemoteResult> purchaseItem(String productId);
}
