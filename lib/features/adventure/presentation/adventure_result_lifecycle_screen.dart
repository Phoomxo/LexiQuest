import 'dart:async';

import 'package:flutter/material.dart';

import '../../learning/domain/learning_models.dart';
import '../../rewards/domain/reward_models.dart';
import '../application/adventure_motivation_projection_reader.dart';
import '../application/adventure_diagnostics.dart';
import '../application/adventure_reaction_selector.dart';
import '../domain/adventure_reaction.dart';
import '../domain/adventure_result.dart';
import 'adventure_result_screen.dart';
import 'widgets/adventure_companion_panel.dart';

/// Presents the already-committed learning summary immediately, then observes
/// canonical projection receipts after the existing reconciler has drained.
/// This screen has no reward or learning mutation authority.
final class AdventureResultLifecycleScreen extends StatefulWidget {
  const AdventureResultLifecycleScreen({
    super.key,
    required this.summary,
    required this.motivation,
    required this.receiptBarrier,
    required this.rewardOwnership,
    required this.onNextAction,
    this.catalogVersion = AdventureReactionCatalog.v1Version,
    this.diagnostics,
  });

  final LearningSessionSummary summary;
  final AdventureMotivationProjectionReader motivation;
  final AdventureProjectionReceiptBarrier receiptBarrier;
  final RewardAccount rewardOwnership;
  final VoidCallback? onNextAction;
  final String catalogVersion;
  final AdventureDiagnostics? diagnostics;

  @override
  State<AdventureResultLifecycleScreen> createState() =>
      _AdventureResultLifecycleScreenState();
}

final class _AdventureResultLifecycleScreenState
    extends State<AdventureResultLifecycleScreen> {
  static const AdventureReactionSelector _reactions =
      AdventureReactionSelector();

  late AdventureResult _result;
  late AdventureReaction? _reaction;
  var _refreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _result = _fromSummary(
      widget.summary,
      motivation: _pendingMotivation,
      reward: const AdventureRewardReceiptView(
        state: AdventureCanonicalRewardState.pending,
      ),
    );
    _reaction = _select(AdventureReactionTrigger.rewardPending);
    unawaited(_refreshReceipts());
  }

  @override
  void didUpdateWidget(AdventureResultLifecycleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.id != widget.summary.id ||
        oldWidget.summary.ownerId != widget.summary.ownerId ||
        !identical(oldWidget.motivation, widget.motivation) ||
        !identical(oldWidget.receiptBarrier, widget.receiptBarrier)) {
      _refreshGeneration += 1;
      _result = _fromSummary(
        widget.summary,
        motivation: _pendingMotivation,
        reward: const AdventureRewardReceiptView(
          state: AdventureCanonicalRewardState.pending,
        ),
      );
      _reaction = _select(AdventureReactionTrigger.rewardPending);
      unawaited(_refreshReceipts());
    }
  }

  Future<void> _refreshReceipts() async {
    final generation = ++_refreshGeneration;
    final summary = widget.summary;
    var recovered = false;
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        await widget.receiptBarrier.waitForCanonicalProjection(summary.ownerId);
        if (!_isCurrent(generation, summary)) return;
        final snapshots = await widget.motivation.readForSession(
          ownerId: summary.ownerId,
          sessionId: summary.id,
        );
        if (!_isCurrent(generation, summary)) return;
        final reward = _canonicalReward(snapshots);
        final motivation = _canonicalMotivation(snapshots);
        setState(() {
          _result = _fromSummary(
            summary,
            motivation: motivation,
            reward: reward,
          );
          _reaction = _select(
            recovered
                ? AdventureReactionTrigger.recovered
                : AdventureReactionTrigger.completed,
          );
        });
        return;
      } catch (_) {
        if (!_isCurrent(generation, summary)) return;
        if (attempt == 1) {
          recovered = true;
          widget.diagnostics?.recordProjectionRetry();
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        widget.diagnostics?.recordProjectionRetry(exhausted: true);
        setState(() {
          _result = _fromSummary(
            summary,
            motivation: _pendingMotivation,
            reward: const AdventureRewardReceiptView(
              state: AdventureCanonicalRewardState.pending,
            ),
            technicalMessage: 'ซิงก์รางวัลยังไม่สำเร็จ ลองใหม่ภายหลังได้',
          );
          _reaction = _select(AdventureReactionTrigger.rewardPending);
        });
        return;
      }
    }
  }

  bool _isCurrent(int generation, LearningSessionSummary summary) =>
      mounted &&
      generation == _refreshGeneration &&
      widget.summary.id == summary.id &&
      widget.summary.ownerId == summary.ownerId;

  AdventureRewardReceiptView _canonicalReward(
    List<AdventureMotivationSnapshot> snapshots,
  ) {
    if (snapshots.any(
      (snapshot) =>
          snapshot.rewardOutcome.state ==
          AdventureProjectionReceiptState.pending,
    )) {
      return const AdventureRewardReceiptView(
        state: AdventureCanonicalRewardState.pending,
      );
    }
    for (final snapshot in snapshots) {
      final outcome = snapshot.rewardOutcome;
      if (outcome.state == AdventureProjectionReceiptState.committed &&
          outcome.receiptId != null) {
        return AdventureRewardReceiptView(
          state: AdventureCanonicalRewardState.accepted,
          receiptId: outcome.receiptId,
        );
      }
    }
    if (snapshots.isEmpty) {
      return const AdventureRewardReceiptView(
        state: AdventureCanonicalRewardState.unavailable,
      );
    }
    final terminal =
        snapshots.isNotEmpty &&
        snapshots.every(
          (snapshot) =>
              snapshot.rewardOutcome.state ==
              AdventureProjectionReceiptState.notEligible,
        );
    return AdventureRewardReceiptView(
      state: terminal
          ? AdventureCanonicalRewardState.unavailable
          : AdventureCanonicalRewardState.pending,
    );
  }

  AdventureMotivationReceiptView _canonicalMotivation(
    List<AdventureMotivationSnapshot> snapshots,
  ) {
    if (snapshots.isEmpty) {
      return _unavailableMotivation;
    }
    final quest = snapshots.map((snapshot) => snapshot.questOutcome).toList();
    final streak = snapshots.map((snapshot) => snapshot.streakOutcome).toList();
    final achievements =
        snapshots
            .expand((snapshot) => snapshot.achievementOutcomes)
            .where(
              (outcome) =>
                  outcome.state == AdventureProjectionReceiptState.committed,
            )
            .map((outcome) => outcome.displayCode)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    return AdventureMotivationReceiptView(
      questState: _receiptState(quest),
      streakState: _receiptState(streak),
      achievementState: achievements.isNotEmpty
          ? AdventureCanonicalReceiptState.committed
          : snapshots.any((snapshot) => snapshot.pendingProjection)
          ? AdventureCanonicalReceiptState.pending
          : AdventureCanonicalReceiptState.notEligible,
      questCodes: quest
          .where(
            (outcome) =>
                outcome.state == AdventureProjectionReceiptState.committed,
          )
          .map((outcome) => outcome.displayCode)
          .whereType<String>()
          .toSet(),
      streakCodes: streak
          .where(
            (outcome) =>
                outcome.state == AdventureProjectionReceiptState.committed,
          )
          .map((outcome) => outcome.displayCode)
          .whereType<String>()
          .toSet(),
      achievementCodes: achievements,
    );
  }

  AdventureCanonicalReceiptState _receiptState(
    List<AdventureProjectionOutcome> outcomes,
  ) {
    if (outcomes.any(
      (outcome) => outcome.state == AdventureProjectionReceiptState.pending,
    )) {
      return AdventureCanonicalReceiptState.pending;
    }
    if (outcomes.any(
      (outcome) => outcome.state == AdventureProjectionReceiptState.committed,
    )) {
      return AdventureCanonicalReceiptState.committed;
    }
    return AdventureCanonicalReceiptState.notEligible;
  }

  AdventureReaction? _select(AdventureReactionTrigger trigger) =>
      _reactions.select(
        catalogVersion: widget.catalogVersion,
        trigger: trigger,
        variantSeed: 0,
      );

  @override
  Widget build(BuildContext context) => AdventureResultScreen(
    result: _result,
    onNextAction: widget.onNextAction,
    header: AdventureCompanionPanel(
      reaction: _reaction,
      rewardOwnership: widget.rewardOwnership,
      language: AdventureReactionLanguage.th,
    ),
  );
}

AdventureResult _fromSummary(
  LearningSessionSummary summary, {
  required AdventureMotivationReceiptView motivation,
  required AdventureRewardReceiptView reward,
  String? technicalMessage,
}) => AdventureResult(
  ownerId: summary.ownerId,
  sessionId: summary.id,
  learning: AdventureLearningResult(
    correctCount: summary.correctCount,
    incorrectCount: summary.wrongCount,
    reviewDueCount: summary.wrongCount,
  ),
  effort: AdventureEffortResult(
    activeDuration: summary.configurationActiveEffort,
    completedItems: summary.correctCount + summary.wrongCount,
  ),
  engagement: AdventureEngagementResult(
    completedMission: summary.state == 'completed',
    returnedAfterBreak: false,
  ),
  motivation: motivation,
  reward: reward,
  nextAction: AdventureNextAction.reviewCenter,
  technicalMessage: technicalMessage,
);

final AdventureMotivationReceiptView _pendingMotivation =
    AdventureMotivationReceiptView(
      questState: AdventureCanonicalReceiptState.pending,
      streakState: AdventureCanonicalReceiptState.pending,
      achievementState: AdventureCanonicalReceiptState.pending,
    );

final AdventureMotivationReceiptView _unavailableMotivation =
    AdventureMotivationReceiptView(
      questState: AdventureCanonicalReceiptState.unavailable,
      streakState: AdventureCanonicalReceiptState.unavailable,
      achievementState: AdventureCanonicalReceiptState.unavailable,
    );
