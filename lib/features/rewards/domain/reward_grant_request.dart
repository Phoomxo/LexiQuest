/// Reward grant request — the command that flows from an eligibility decision
/// to the reward repository.
///
/// [RewardGrantRequest] is immutable.  Build one using
/// [RewardGrantRequest.fromDecision] to ensure all fields are consistent with
/// the source event.
library;

import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'reward_eligibility.dart';

/// A request to persist a coin grant derived from one [EventEnvelopeV2].
final class RewardGrantRequest {
  const RewardGrantRequest({
    required this.requestId,
    required this.ownerId,
    required this.coinAmount,
    required this.sourceEventId,
    required this.reason,
    required this.policyVersion,
    required this.idempotencyKey,
    required this.requestedAtUtc,
  });

  /// Builds a [RewardGrantRequest] from a pre-computed [decision] and its
  /// [sourceEvent].
  ///
  /// The [idempotencyKey] is inherited from [sourceEvent] so that replaying
  /// the same event never produces a second grant.
  factory RewardGrantRequest.fromDecision(
    RewardEligibilityDecision decision,
    EventEnvelopeV2 sourceEvent, {
    required DateTime requestedAtUtc,
    required String requestId,
  }) {
    return RewardGrantRequest(
      requestId: requestId,
      ownerId: sourceEvent.ownerIdentity,
      coinAmount: decision.coinAmount,
      sourceEventId: sourceEvent.eventId,
      reason: decision.reason,
      policyVersion: decision.policyVersion,
      idempotencyKey: sourceEvent.idempotencyKey,
      requestedAtUtc: requestedAtUtc,
    );
  }

  /// Unique request ID (UUID).
  final String requestId;

  /// Learner receiving the coins.
  final String ownerId;

  /// Number of coins to grant.
  final int coinAmount;

  /// ID of the [EventEnvelopeV2] that triggered this grant.
  final String sourceEventId;

  /// Machine-readable reason code from the eligibility policy.
  final String reason;

  /// Policy version that decided the grant.
  final String policyVersion;

  /// Inherited from the source event — prevents double grants on replay.
  final String idempotencyKey;

  final DateTime requestedAtUtc;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'ownerId': ownerId,
    'coinAmount': coinAmount,
    'sourceEventId': sourceEventId,
    'reason': reason,
    'policyVersion': policyVersion,
    'idempotencyKey': idempotencyKey,
    'requestedAtUtc': requestedAtUtc.toIso8601String(),
  };
}
