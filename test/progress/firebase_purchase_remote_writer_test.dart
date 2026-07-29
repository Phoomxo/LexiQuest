import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/progress/firebase_progress_remote_writer.dart';
import 'package:vocab_learning_app/progress/purchase_remote_writer.dart';
import 'package:vocab_learning_app/progress/firebase_purchase_remote_writer.dart';

void main() {
  test('sends only the product identifier to the trusted callable', () async {
    final client = _StubCallableClient({
      'status': 'purchased',
      'remainingPoints': 40,
    });
    final writer = FirebasePurchaseRemoteWriter(client: client);

    final result = await writer.purchaseItem('wallpaper_neon');

    expect(client.functionName, 'purchaseItem');
    expect(client.data, {'productId': 'wallpaper_neon'});
    expect(
      result,
      const PurchaseRemoteAccepted(alreadyOwned: false, remainingPoints: 40),
    );
  });

  test('maps an existing purchase without requesting another debit', () async {
    final client = _StubCallableClient({
      'status': 'already-owned',
      'remainingPoints': 90,
    });
    final writer = FirebasePurchaseRemoteWriter(client: client);

    final result = await writer.purchaseItem('wallpaper_neon');

    expect(
      result,
      const PurchaseRemoteAccepted(alreadyOwned: true, remainingPoints: 90),
    );
  });

  test('invalid response shape fails closed', () async {
    final writer = FirebasePurchaseRemoteWriter(
      client: _StubCallableClient({
        'status': 'purchased',
        'remainingPoints': -1,
      }),
    );

    expect(
      await writer.purchaseItem('wallpaper_neon'),
      const PurchaseRemoteRejected(PurchaseRemoteFailure.unknown),
    );
  });

  test('callable failures are returned as typed purchase failures', () async {
    final cases = <String, PurchaseRemoteFailure>{
      'unauthenticated': PurchaseRemoteFailure.unauthenticated,
      'invalid-argument': PurchaseRemoteFailure.invalidRequest,
      'not-found': PurchaseRemoteFailure.productUnavailable,
      'failed-precondition': PurchaseRemoteFailure.preconditionFailed,
      'unavailable': PurchaseRemoteFailure.unavailable,
      'deadline-exceeded': PurchaseRemoteFailure.unavailable,
      'internal': PurchaseRemoteFailure.unknown,
    };

    for (final entry in cases.entries) {
      final writer = FirebasePurchaseRemoteWriter(
        client: _StubCallableClient.failure(entry.key),
      );

      expect(
        await writer.purchaseItem('wallpaper_neon'),
        PurchaseRemoteRejected(entry.value),
      );
    }
  });
}

final class _StubCallableClient implements ProgressCallableClient {
  _StubCallableClient(this.response) : failureCode = null;

  _StubCallableClient.failure(this.failureCode) : response = null;

  final Object? response;
  final String? failureCode;
  String? functionName;
  Map<String, Object?>? data;

  @override
  Future<Object?> call(String functionName, Map<String, Object?> data) async {
    this.functionName = functionName;
    this.data = data;
    final code = failureCode;
    if (code != null) throw ProgressCallableFailure(code);
    return response;
  }
}
