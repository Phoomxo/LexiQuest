/// V2 Entitlement Registry — access rights tied to subscription or purchase.
///
/// Entitlements represent durable access rights granted by a purchase or
/// subscription, and are distinct from:
/// - [FeatureRegistry]: build-time feature flags (no ownership required)
/// - [ExperimentRegistry]: A/B cohort assignment
/// - [ConsentRegistry]: explicit learner consent
library;

import '../../features/billing/application/billing_use_cases.dart';

/// Durable access rights that may require a purchase or subscription.
enum Entitlement {
  /// Full offline mode with unlimited vocabulary packs.
  offlinePremium,

  /// Unlimited AI tutor conversations per day.
  aiTutorUnlimited,

  /// Access to advanced export formats (PDF, Anki deck).
  advancedExport,
  managedContent,
}

/// Read-only contract for querying learner entitlements.
abstract interface class EntitlementRegistry {
  /// Returns `true` when [ownerId] has active access to [entitlement].
  bool hasAccess(Entitlement entitlement, String ownerId);
}

/// No-op [EntitlementRegistry] that denies all entitlements.
final class NoOpEntitlementRegistry implements EntitlementRegistry {
  const NoOpEntitlementRegistry();

  @override
  bool hasAccess(Entitlement entitlement, String ownerId) => false;
}

final class BillingEntitlementRegistry implements EntitlementRegistry {
  const BillingEntitlementRegistry(this.billing);
  final BillingUseCases billing;

  @override
  bool hasAccess(Entitlement entitlement, String ownerId) =>
      billing.hasAccess(entitlement.name, ownerId: ownerId);
}
