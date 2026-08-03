/// Reward eligibility policy v1 — decides whether an [EventEnvelopeV2]
/// should trigger a coin grant.
///
/// This is a pure function: given an event, it returns a decision.  No I/O,
/// no side effects.  The decision may be logged, dry-run-checked, or
/// committed, but the policy itself is stateless.
///
/// **Contract freeze:** Policy v1 rules are frozen here.  New rules require
/// incrementing [policyVersion] and updating the schema ledger.
library;

import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';

// ─── Result enum ─────────────────────────────────────────────────────────────

enum EligibilityResult {
  /// The event qualifies for a coin grant.
  eligible,

  /// The event does not meet any grant rule.
  notEligible,

  /// The idempotency key has already been used — grant was already made.
  alreadyGranted,
}

// ─── Decision ────────────────────────────────────────────────────────────────

/// The outcome of evaluating one [EventEnvelopeV2] against the reward policy.
final class RewardEligibilityDecision {
  const RewardEligibilityDecision({
    required this.result,
    required this.coinAmount,
    required this.reason,
    required this.policyVersion,
  });

  final EligibilityResult result;

  /// Number of coins to grant; 0 when [result] != [EligibilityResult.eligible].
  final int coinAmount;

  /// Machine-readable reason code (snake_case).
  final String reason;

  /// Policy version that produced this decision.
  final String policyVersion;

  /// Evaluates [event] against the v1 eligibility rules.
  ///
  /// Rules (policy v1):
  /// - `QuizCompleted` with `payload['correct'] == true` → 10 coins
  /// - `QuestCompleted` with `payload['questType']`:
  ///     daily → 50 coins, weekly → 200 coins, milestone → 500 coins
  /// - All other events → not eligible
  static RewardEligibilityDecision evaluate(EventEnvelopeV2 event) {
    const version = 'v1';

    if (event.eventType == 'QuizCompleted') {
      final correct = event.payload['correct'] as bool?;
      if (correct == true) {
        return const RewardEligibilityDecision(
          result: EligibilityResult.eligible,
          coinAmount: 10,
          reason: 'quiz_completed_correctly',
          policyVersion: version,
        );
      }
      return const RewardEligibilityDecision(
        result: EligibilityResult.notEligible,
        coinAmount: 0,
        reason: 'quiz_answered_incorrectly',
        policyVersion: version,
      );
    }

    if (event.eventType == 'QuestCompleted') {
      final questType = event.payload['questType'] as String?;
      final amount = switch (questType) {
        'daily' => 50,
        'weekly' => 200,
        'milestone' => 500,
        _ => 0,
      };
      if (amount > 0) {
        return RewardEligibilityDecision(
          result: EligibilityResult.eligible,
          coinAmount: amount,
          reason: 'quest_completed_$questType',
          policyVersion: version,
        );
      }
    }

    return const RewardEligibilityDecision(
      result: EligibilityResult.notEligible,
      coinAmount: 0,
      reason: 'no_matching_rule',
      policyVersion: version,
    );
  }

  Map<String, dynamic> toJson() => {
    'result': result.name,
    'coinAmount': coinAmount,
    'reason': reason,
    'policyVersion': policyVersion,
  };
}
