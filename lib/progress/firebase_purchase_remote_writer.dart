import 'firebase_progress_remote_writer.dart';
import 'purchase_remote_writer.dart';

final class FirebasePurchaseRemoteWriter implements PurchaseRemoteWriter {
  FirebasePurchaseRemoteWriter({ProgressCallableClient? client})
    : _client = client ?? FirebaseProgressCallableClient();

  final ProgressCallableClient _client;

  @override
  Future<PurchaseRemoteResult> purchaseItem(String productId) async {
    try {
      final response = await _client.call('purchaseItem', {
        'productId': productId,
      });
      if (response is! Map) {
        return const PurchaseRemoteRejected(PurchaseRemoteFailure.unknown);
      }
      final status = response['status'];
      final remainingPoints = response['remainingPoints'];
      if ((status != 'purchased' && status != 'already-owned') ||
          remainingPoints is! int ||
          remainingPoints < 0) {
        return const PurchaseRemoteRejected(PurchaseRemoteFailure.unknown);
      }
      return PurchaseRemoteAccepted(
        alreadyOwned: status == 'already-owned',
        remainingPoints: remainingPoints,
      );
    } on ProgressCallableFailure catch (failure) {
      return PurchaseRemoteRejected(_purchaseFailureFor(failure.code));
    } on Object {
      return const PurchaseRemoteRejected(PurchaseRemoteFailure.unknown);
    }
  }
}

PurchaseRemoteFailure _purchaseFailureFor(String code) {
  return switch (code) {
    'unauthenticated' => PurchaseRemoteFailure.unauthenticated,
    'invalid-argument' => PurchaseRemoteFailure.invalidRequest,
    'not-found' => PurchaseRemoteFailure.productUnavailable,
    'failed-precondition' => PurchaseRemoteFailure.preconditionFailed,
    'unavailable' || 'deadline-exceeded' => PurchaseRemoteFailure.unavailable,
    _ => PurchaseRemoteFailure.unknown,
  };
}
