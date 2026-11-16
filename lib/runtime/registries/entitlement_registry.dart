/// V2 Entitlement Registry — access rights tied to subscription or purchase.
///
/// Entitlements represent durable access rights granted by a purchase or
/// subscription, and are distinct from:
/// - [FeatureRegistry]: build-time feature flags (no ownership required)
/// - [ExperimentRegistry]: A/B cohort assignment
/// - [ConsentRegistry]: explicit learner consent
///
/// Entitlement checks are reserved for Phase 3+; this interface is defined
/// now so that call sites can be written against the contract without any
/// concrete billing back-end.
library;

/// Durable access rights that may require a purchase or subscription.
enum Entitlement {
  /// Full offline mode with unlimited vocabulary packs.
  offlinePremium,

  /// Unlimited AI tutor conversations per day.
  aiTutorUnlimited,

  /// Access to advanced export formats (PDF, Anki deck).
  advancedExport,
}

/// Read-only contract for querying learner entitlements.
abstract interface class EntitlementRegistry {
  /// Returns `true` when [ownerId] has active access to [entitlement].
  bool hasAccess(Entitlement entitlement, String ownerId);
}

/// No-op [EntitlementRegistry] that denies all entitlements.
///
/// Safe default for Phase -1 / Phase 0 before billing is integrated.
/// Production code that gates on an entitlement will fall back to the free
/// tier, which is the intended behaviour when no billing back-end is present.
final class NoOpEntitlementRegistry implements EntitlementRegistry {
  const NoOpEntitlementRegistry();

  @override
  bool hasAccess(Entitlement entitlement, String ownerId) => false;
}
