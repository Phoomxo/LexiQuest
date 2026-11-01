import 'dart:async';

import 'package:vocab_learning_app/features/billing/application/billing_use_cases.dart';
import 'package:vocab_learning_app/features/billing/domain/billing_contracts.dart';

const syntheticOffer = BillingOffer(
  offerKey: 'synthetic-offer',
  productId: 'synthetic.monthly',
  basePlanId: 'monthly',
  title: 'Synthetic subscription',
  localizedPrice: '฿99.00',
  billingPeriod: 'P1M',
);
const syntheticAccount = BillingAccount(
  ownerId: 'synthetic-owner',
  firebaseUid: 'synthetic-uid',
  isAnonymous: false,
);

BillingSnapshot syntheticSnapshot({
  bool active = false,
  bool acknowledgementPending = false,
  DateTime? now,
}) {
  final at = now ?? DateTime.utc(2026, 11, 1);
  return BillingSnapshot(
    serverTimeUtc: at,
    acknowledgementPending: acknowledgementPending,
    refreshRequired: false,
    grants: [
      if (active)
        BillingGrant(
          entitlement: 'managedContent',
          expiresAtUtc: at.add(const Duration(days: 30)),
          checkedAtUtc: at,
          dailyManagedUnits: 10,
        ),
    ],
  );
}

BillingPurchase syntheticPurchase({
  BillingPurchaseStatus status = BillingPurchaseStatus.purchased,
  String? accountIdentifier,
  String token = 'synthetic-token',
  String identity = 'synthetic-store-receipt',
}) => BillingPurchase(
  productId: syntheticOffer.productId,
  status: status,
  purchaseToken: token,
  accountIdentifier: accountIdentifier ?? 'a' * 64,
  pendingCompletion: true,
  storeIdentity: identity,
);

class BillingFixture {
  BillingFixture({BillingAccount? initialAccount = syntheticAccount})
    : account = initialAccount {
    billing = BillingUseCases(
      repository: repository,
      store: store,
      currentAccount: () => account,
      accountChanges: accounts.stream,
      generateRequestId: () => 'synthetic-request-${++requestCount}',
      elapsed: () => elapsed,
    );
  }
  final accounts = StreamController<BillingAccount?>.broadcast(sync: true);
  final repository = SyntheticBillingRepository();
  final store = SyntheticBillingStore();
  BillingAccount? account;
  late final BillingUseCases billing;
  Duration elapsed = Duration.zero;
  int requestCount = 0;
  void changeAccount(BillingAccount? value) {
    account = value;
    accounts.add(value);
  }

  Future<void> flush() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    await billing.dispose();
    final pending = repository.verification;
    if (pending != null && !pending.isCompleted) {
      pending.complete(syntheticSnapshot());
    }
    await accounts.close();
  }
}

class SyntheticBillingRepository implements BillingRepository {
  int catalogLoads = 0;
  int entitlementLoads = 0;
  final commands = <BillingVerification>[];
  BillingSnapshot snapshot = syntheticSnapshot();
  bool failVerification = false;
  bool unavailable = false;
  Completer<BillingSnapshot>? verification;
  @override
  Future<BillingCatalog> loadCatalog(
    BillingAccount account, {
    required bool Function() stillCurrent,
  }) async {
    catalogLoads++;
    if (unavailable) {
      throw const BillingException(BillingFailureCode.unavailable);
    }
    return BillingCatalog(
      packageName: 'com.lexiquest.app',
      policyRevision: 'synthetic-v1',
      accountIdentifier: 'a' * 64,
      products: [
        BillingProduct(
          productId: syntheticOffer.productId,
          basePlanId: syntheticOffer.basePlanId,
          entitlements: {'managedContent'},
        ),
      ],
    );
  }

  @override
  Future<BillingSnapshot> loadEntitlements(
    BillingAccount account, {
    required bool Function() stillCurrent,
  }) async {
    entitlementLoads++;
    return snapshot;
  }

  @override
  Future<BillingSnapshot> verify(
    BillingAccount account,
    BillingVerification command, {
    required bool Function() stillCurrent,
  }) async {
    commands.add(command);
    if (failVerification) {
      throw const BillingException(BillingFailureCode.unavailable);
    }
    return verification == null ? snapshot : verification!.future;
  }
}

class SyntheticBillingStore implements BillingStoreGateway {
  final events = StreamController<List<BillingPurchase>>.broadcast(sync: true);
  bool available = true;
  bool launched = true;
  int launches = 0;
  int restores = 0;
  int completions = 0;
  String? launchedAccount;
  @override
  Stream<List<BillingPurchase>> get purchases => events.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<List<BillingOffer>> loadOffers(BillingCatalog catalog) async => [
    syntheticOffer,
  ];
  @override
  Future<bool> buy(
    BillingOffer offer, {
    required String accountIdentifier,
  }) async {
    launches++;
    launchedAccount = accountIdentifier;
    return launched;
  }

  @override
  Future<void> restore({required String accountIdentifier}) async {
    restores++;
  }

  @override
  Future<void> complete(BillingPurchase purchase) async {
    completions++;
  }

  @override
  Future<void> dispose() => events.close();
}
