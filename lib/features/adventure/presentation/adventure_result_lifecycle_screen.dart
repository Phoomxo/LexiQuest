import 'dart:async';

import 'package:flutter/material.dart';

import '../../learning/domain/learning_models.dart';
import '../../rewards/domain/reward_models.dart';
import '../application/adventure_diagnostics.dart';
import '../application/adventure_motivation_projection_reader.dart';
import '../application/adventure_reaction_selector.dart';
import '../application/adventure_result_next_action_reader.dart';
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
    required this.nextActionReader,
    required this.rewardOwnership,
    required this.onNextAction,
    this.catalogVersion = AdventureReactionCatalog.v1Version,
    this.diagnostics,
  });

  final LearningSessionSummary summary;
  final AdventureMotivationProjectionReader motivation;
  final AdventureProjectionReceiptBarrier receiptBarrier;
  final AdventureResultNextActionReader nextActionReader;
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
  var _receiptGeneration = 0;
  var _nextActionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _result = _fromSummary(
      widget.summary,
      motivation: _pendingMotivation,
      reward: const AdventureRewardReceiptView(
        state: AdventureCanonicalRewardState.pending,
      ),
      nextAction: AdventureNextAction.none,
    );
    _reaction = _select(AdventureReactionTrigger.rewardPending);
    _startReceiptRefresh();
    _startNextActionRefresh();
  }

  @override
  void didUpdateWidget(AdventureResultLifecycleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final summaryChanged =
        oldWidget.summary.id != widget.summary.id ||
        oldWidget.summary.ownerId != widget.summary.ownerId;
    final receiptSourceChanged =
        summaryChanged ||
        !identical(oldWidget.motivation, widget.motivation) ||
        !identical(oldWidget.receiptBarrier, widget.receiptBarrier);
    final nextActionSourceChanged =
        summaryChanged ||
        !identical(oldWidget.nextActionReader, widget.nextActionReader);
    if (summaryChanged) {
      _result = _fromSummary(
        widget.summary,
        motivation: _pendingMotivation,
        reward: const AdventureRewardReceiptView(
          state: AdventureCanonicalRewardState.pending,
        ),
        nextAction: AdventureNextAction.none,
      );
      _reaction = _select(AdventureReactionTrigger.rewardPending);
    } else {
      if (receiptSourceChanged) {
        _result = _copyResult(
          _result,
          motivation: _pendingMotivation,
          reward: const AdventureRewardReceiptView(
            state: AdventureCanonicalRewardState.pending,
          ),
          technicalMessage: null,
        );
        _reaction = _select(AdventureReactionTrigger.rewardPending);
      }
      if (nextActionSourceChanged) {
        _result = _copyResult(_result, nextAction: AdventureNextAction.none);
      }
    }
    if (receiptSourceChanged) _startReceiptRefresh();
    if (nextActionSourceChanged) _startNextActionRefresh();
  }

  void _startReceiptRefresh() {
    final generation = ++_receiptGeneration;
    final summary = widget.summary;
    final motivation = widget.motivation;
    final receiptBarrier = widget.receiptBarrier;
    unawaited(
      _refreshReceipts(
        generation: generation,
        summary: summary,
        motivation: motivation,
        receiptBarrier: receiptBarrier,
      ),
    );
  }

  Future<void> _refreshReceipts({
    required int generation,
    required LearningSessionSummary summary,
    required AdventureMotivationProjectionReader motivation,
    required AdventureProjectionReceiptBarrier receiptBarrier,
  }) async {
    var recovered = false;
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      try {
        await receiptBarrier.waitForCanonicalProjection(summary.ownerId);
        if (!_isReceiptCurrent(
          generation,
          summary,
          motivation,
          receiptBarrier,
        )) {
          return;
        }
        final snapshots = await motivation.readForSession(
          ownerId: summary.ownerId,
          sessionId: summary.id,
        );
        if (!_isReceiptCurrent(
          generation,
          summary,
          motivation,
          receiptBarrier,
        )) {
          return;
        }
        final reward = _canonicalReward(snapshots);
        final motivationView = _canonicalMotivation(snapshots);
        setState(() {
          _result = _copyResult(
            _result,
            motivation: motivationView,
            reward: reward,
            technicalMessage: null,
          );
          _reaction = _select(
            recovered
                ? AdventureReactionTrigger.recovered
                : AdventureReactionTrigger.completed,
          );
        });
        return;
      } catch (_) {
        if (!_isReceiptCurrent(
          generation,
          summary,
          motivation,
          receiptBarrier,
        )) {
          return;
        }
        if (attempt == 1) {
          recovered = true;
          widget.diagnostics?.recordProjectionRetry();
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        widget.diagnostics?.recordProjectionRetry(exhausted: true);
        setState(() {
          _result = _copyResult(
            _result,
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

  void _startNextActionRefresh() {
    final generation = ++_nextActionGeneration;
    final summary = widget.summary;
    final reader = widget.nextActionReader;
    unawaited(
      _refreshNextAction(
        generation: generation,
        summary: summary,
        reader: reader,
      ),
    );
  }

  Future<void> _refreshNextAction({
    required int generation,
    required LearningSessionSummary summary,
    required AdventureResultNextActionReader reader,
  }) async {
    try {
      final nextAction = await reader.read(ownerId: summary.ownerId);
      if (!_isNextActionCurrent(generation, summary, reader)) return;
      setState(() {
        _result = _copyResult(_result, nextAction: nextAction);
      });
    } catch (_) {
      if (!_isNextActionCurrent(generation, summary, reader)) return;
      setState(() {
        _result = _copyResult(_result, nextAction: AdventureNextAction.none);
      });
    }
  }

  bool _isReceiptCurrent(
    int generation,
    LearningSessionSummary summary,
    AdventureMotivationProjectionReader motivation,
    AdventureProjectionReceiptBarrier receiptBarrier,
  ) =>
      mounted &&
      generation == _receiptGeneration &&
      _isCurrentSummary(summary) &&
      identical(widget.motivation, motivation) &&
      identical(widget.receiptBarrier, receiptBarrier);

  bool _isNextActionCurrent(
    int generation,
    LearningSessionSummary summary,
    AdventureResultNextActionReader reader,
  ) =>
      mounted &&
      generation == _nextActionGeneration &&
      _isCurrentSummary(summary) &&
      identical(widget.nextActionReader, reader);

  bool _isCurrentSummary(LearningSessionSummary summary) =>
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
  required AdventureNextAction nextAction,
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
  nextAction: nextAction,
  technicalMessage: technicalMessage,
);

AdventureResult _copyResult(
  AdventureResult result, {
  AdventureMotivationReceiptView? motivation,
  AdventureRewardReceiptView? reward,
  AdventureNextAction? nextAction,
  Object? technicalMessage = _preserveTechnicalMessage,
}) => AdventureResult(
  ownerId: result.ownerId,
  sessionId: result.sessionId,
  learning: result.learning,
  effort: result.effort,
  engagement: result.engagement,
  motivation: motivation ?? result.motivation,
  reward: reward ?? result.reward,
  nextAction: nextAction ?? result.nextAction,
  technicalMessage: identical(technicalMessage, _preserveTechnicalMessage)
      ? result.technicalMessage
      : technicalMessage as String?,
);

const Object _preserveTechnicalMessage = Object();

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
