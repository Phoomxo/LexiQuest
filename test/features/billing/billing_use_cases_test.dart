import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/billing/application/billing_use_cases.dart';
import 'package:vocab_learning_app/features/billing/domain/billing_contracts.dart';

const _offer = BillingOffer(
  offerKey: 'synthetic-offer',
  productId: 'synthetic.monthly',
  basePlanId: 'monthly',
  title: 'Synthetic subscription',
  localizedPrice: '฿99.00',
  billingPeriod: 'P1M',
);

void main() {
  test(
    'anonymous learner cannot launch a purchase or send a verification',
    () async {
      final accounts = StreamController<BillingAccount?>.broadcast();
      final repository = _Repository();
      final store = _Store();
      final billing = BillingUseCases(
        repository: repository,
        store: store,
        currentAccount: () => const BillingAccount(
          ownerId: 'synthetic-owner',
          firebaseUid: 'synthetic-uid',
          isAnonymous: true,
        ),
        accountChanges: accounts.stream,
        generateRequestId: () => 'synthetic-request',
        elapsed: () => Duration.zero,
      );
      addTearDown(() async {
        await billing.dispose();
        await accounts.close();
        await store.dispose();
      });
      await expectLater(
        () => billing.buy(_offer),
        throwsA(
          isA<BillingException>().having(
            (e) => e.code,
            'code',
            BillingFailureCode.accountRequired,
          ),
        ),
      );
      expect(store.launches, 0);
      expect(repository.verifications, 0);
    },
  );
}

class _Repository implements BillingRepository {
  int verifications = 0;
  @override
  Future<BillingCatalog> loadCatalog(
    BillingAccount account, {
    required bool Function() stillCurrent,
  }) async => BillingCatalog(
    packageName: 'com.lexiquest.app',
    policyRevision: 'synthetic-v1',
    accountIdentifier: 'a' * 64,
    products: [
      BillingProduct(
        productId: _offer.productId,
        basePlanId: _offer.basePlanId,
        entitlements: {'managedContent'},
        dailyManagedUnits: 10,
      ),
    ],
  );
  @override
  Future<BillingSnapshot> loadEntitlements(
    BillingAccount account, {
    required bool Function() stillCurrent,
  }) async => BillingSnapshot(
    serverTimeUtc: DateTime.utc(2026, 11, 1),
    acknowledgementPending: false,
    refreshRequired: false,
    grants: const [],
  );
  @override
  Future<BillingSnapshot> verify(
    BillingAccount account,
    BillingVerification command, {
    required bool Function() stillCurrent,
  }) async {
    verifications++;
    return loadEntitlements(account, stillCurrent: stillCurrent);
  }
}

class _Store implements BillingStoreGateway {
  final events = StreamController<List<BillingPurchase>>.broadcast();
  int launches = 0;
  @override
  Stream<List<BillingPurchase>> get purchases => events.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<List<BillingOffer>> loadOffers(BillingCatalog catalog) async => [
    _offer,
  ];
  @override
  Future<bool> buy(
    BillingOffer offer, {
    required String accountIdentifier,
  }) async {
    launches++;
    return true;
  }

  @override
  Future<void> restore({required String accountIdentifier}) async {}
  @override
  Future<void> complete(BillingPurchase purchase) async {}
  @override
  Future<void> dispose() => events.close();
}
