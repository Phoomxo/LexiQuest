/// Identity mapping — unified model for all identity types used in LexiQuest.
///
/// [IdentityMapping] is the single source of truth for resolving which local,
/// Firebase, research-pseudonym, or tenant identity belongs to a learner.
/// It does NOT own authentication; it maps between the representations that
/// already exist in different subsystems.
///
/// **Contract freeze:** Frozen after Week 5-6.
library;

import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart'
    show ConsentContext;

// ─── Supporting types ─────────────────────────────────────────────────────────

/// The learner's current account lifecycle state.
enum IdentityState {
  /// No authentication — local device only.
  guest,

  /// Firebase account registered but email not yet verified.
  registered,

  /// Firebase account with verified email.
  verified,

  /// Temporarily blocked (e.g. abuse report under review).
  suspended,

  /// Soft-deleted; retained for the mandatory data-retention period.
  deleted,
}

/// Membership of a learner inside a tenant (school / organisation).
final class TenantMembership {
  const TenantMembership({
    required this.tenantId,
    required this.role,
    required this.joinedAtUtc,
    this.state = TenantMembershipState.active,
  });

  final String tenantId;

  /// Role string, e.g. `'student'`, `'teacher'`, `'admin'`.
  final String role;

  final DateTime joinedAtUtc;
  final TenantMembershipState state;
}

/// Lifecycle state of a tenant membership.
enum TenantMembershipState {
  /// Membership is current.
  active,

  /// Learner has left the tenant but data is retained.
  inactive,

  /// Membership was revoked by an administrator.
  revoked,
}

// ─── Core mapping ─────────────────────────────────────────────────────────────

/// Unified mapping across all identity namespaces for one learner.
///
/// Instances are immutable.  Use [IdentityMapping.guest] to create a guest
/// identity that has no external IDs.
final class IdentityMapping {
  const IdentityMapping({
    required this.localOwnerId,
    this.firebaseUid,
    this.learnerId,
    this.researchPseudonym,
    this.tenantMemberships = const [],
    this.creatorId,
    required this.createdAtUtc,
    required this.state,
  });

  /// Factory for guest (unauthenticated) identities.
  factory IdentityMapping.guest({
    required String localOwnerId,
    required DateTime createdAtUtc,
  }) => IdentityMapping(
    localOwnerId: localOwnerId,
    createdAtUtc: createdAtUtc,
    state: IdentityState.guest,
  );

  // ── Fields ─────────────────────────────────────────────────────────────────

  /// Primary key in the local Drift database (`local_owners.id`).
  final String localOwnerId;

  /// Firebase Auth UID; `null` for guest learners.
  final String? firebaseUid;

  /// Public learner identifier shown in the UI; `null` until account creation.
  final String? learnerId;

  /// Anonymised research pseudonym; separate from all authentication IDs.
  ///
  /// Must never equal [firebaseUid] or [learnerId].
  final String? researchPseudonym;

  /// Zero or more tenant memberships (school / class / organisation).
  final List<TenantMembership> tenantMemberships;

  /// Content creator ID for learners who also author content; usually `null`.
  final String? creatorId;

  final DateTime createdAtUtc;
  final IdentityState state;

  // ── Derived helpers ────────────────────────────────────────────────────────

  /// `true` when the learner has been authenticated via Firebase.
  bool get isAuthenticated => firebaseUid != null;

  /// Returns the [ConsentContext] derived from this identity for event
  /// envelopes.  Actual consent data lives in the consent repository; this
  /// returns a no-consent default when no grants are known.
  ///
  /// Production code should resolve consent from [ResearchConsentRepository]
  /// and pass it directly to [EventEnvelopeV2]; this helper exists for tests
  /// and Phase -1 scaffolding.
  ConsentContext defaultConsentContext() => const ConsentContext.none();

  @override
  String toString() =>
      'IdentityMapping(local=$localOwnerId, state=${state.name})';
}
