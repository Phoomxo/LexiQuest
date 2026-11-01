enum BillingFailureCode {
  accountRequired,
  ownerChanged,
  unavailable,
  cancelled,
  pending,
  invalidResponse,
  purchaseDenied,
  verificationRequired,
  quota,
  retryLater,
}

final class BillingException implements Exception {
  const BillingException(this.code, {this.retryAfter});
  final BillingFailureCode code;
  final Duration? retryAfter;
  @override
  String toString() => 'BillingException(${code.name})';
}

final class BillingAccount {
  const BillingAccount({
    required this.ownerId,
    required this.firebaseUid,
    required this.isAnonymous,
  });
  final String ownerId;
  final String firebaseUid;
  final bool isAnonymous;
  @override
  bool operator ==(Object other) =>
      other is BillingAccount &&
      ownerId == other.ownerId &&
      firebaseUid == other.firebaseUid &&
      isAnonymous == other.isAnonymous;
  @override
  int get hashCode => Object.hash(ownerId, firebaseUid, isAnonymous);
}

final class BillingProduct {
  BillingProduct({
    required this.productId,
    required this.basePlanId,
    required Set<String> entitlements,
  }) : entitlements = Set.unmodifiable(entitlements);
  final String productId;
  final String basePlanId;
  final Set<String> entitlements;
}

final class BillingCatalog {
  BillingCatalog({
    required this.packageName,
    required this.policyRevision,
    required this.accountIdentifier,
    required List<BillingProduct> products,
  }) : products = List.unmodifiable(products);
  final String packageName;
  final String policyRevision;
  final String accountIdentifier;
  final List<BillingProduct> products;
}

final class BillingOffer {
  const BillingOffer({
    required this.offerKey,
    required this.productId,
    required this.basePlanId,
    required this.title,
    required this.localizedPrice,
    required this.billingPeriod,
  });
  final String offerKey;
  final String productId;
  final String basePlanId;
  final String title;
  final String localizedPrice;
  final String billingPeriod;
}

final class BillingGrant {
  const BillingGrant({
    required this.entitlement,
    required this.expiresAtUtc,
    required this.checkedAtUtc,
    required this.dailyManagedUnits,
  });
  final String entitlement;
  final DateTime expiresAtUtc;
  final DateTime checkedAtUtc;
  final int dailyManagedUnits;
}

final class BillingSnapshot {
  BillingSnapshot({
    required this.serverTimeUtc,
    required this.acknowledgementPending,
    required this.refreshRequired,
    required List<BillingGrant> grants,
  }) : grants = List.unmodifiable(grants);
  final DateTime serverTimeUtc;
  final bool acknowledgementPending;
  final bool refreshRequired;
  final List<BillingGrant> grants;
}

final class BillingVerification {
  const BillingVerification({
    required this.purchaseToken,
    required this.requestId,
  });
  final String purchaseToken;
  final String requestId;
  @override
  String toString() => 'BillingVerification(redacted)';
}

enum BillingPurchaseStatus { pending, purchased, restored, cancelled, failed }

final class BillingPurchase {
  const BillingPurchase({
    required this.productId,
    required this.status,
    required this.purchaseToken,
    required this.accountIdentifier,
    required this.pendingCompletion,
    required this.storeIdentity,
  });
  final String productId;
  final BillingPurchaseStatus status;
  final String? purchaseToken;
  final String? accountIdentifier;
  final bool pendingCompletion;
  final String storeIdentity;
  @override
  String toString() => 'BillingPurchase(${status.name}, redacted)';
}

abstract interface class BillingRepository {
  Future<BillingCatalog> loadCatalog(
    BillingAccount account, {
    required bool Function() stillCurrent,
  });
  Future<BillingSnapshot> loadEntitlements(
    BillingAccount account, {
    required bool Function() stillCurrent,
  });
  Future<BillingSnapshot> verify(
    BillingAccount account,
    BillingVerification command, {
    required bool Function() stillCurrent,
  });
}

abstract interface class BillingStoreGateway {
  Stream<List<BillingPurchase>> get purchases;
  Future<bool> isAvailable();
  Future<List<BillingOffer>> loadOffers(BillingCatalog catalog);
  Future<bool> buy(BillingOffer offer, {required String accountIdentifier});
  Future<void> restore({required String accountIdentifier});
  Future<void> complete(BillingPurchase purchase);
  Future<void> dispose();
}

enum BillingPhase {
  unavailable,
  loading,
  ready,
  launching,
  pending,
  verifying,
  active,
  restoring,
  failed,
}

final class BillingView {
  BillingView({
    required this.phase,
    this.account,
    this.catalog,
    List<BillingOffer> offers = const [],
    this.snapshot,
    this.failure,
    this.verificationPending = false,
  }) : offers = List.unmodifiable(offers);
  final BillingPhase phase;
  final BillingAccount? account;
  final BillingCatalog? catalog;
  final List<BillingOffer> offers;
  final BillingSnapshot? snapshot;
  final BillingFailureCode? failure;
  final bool verificationPending;
  bool get busy => const {
    BillingPhase.loading,
    BillingPhase.launching,
    BillingPhase.verifying,
    BillingPhase.restoring,
  }.contains(phase);
}
