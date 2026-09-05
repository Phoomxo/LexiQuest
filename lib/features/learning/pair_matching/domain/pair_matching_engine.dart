import 'dart:convert';
import 'pair_matching_plan.dart';
import 'pair_repair_policy.dart';
import 'pair_support_policy.dart';
import '../../domain/hint_policy.dart';
import '../../domain/learning_activity_recovery_limits.dart';

enum PairTileSide { prompt, target }

enum PairAttemptRole {
  firstOpportunity,
  independentRetry,
  delayedRepair,
  guidedCompletion,
}

final class PairTile {
  const PairTile(this.side, this.wordId);
  final PairTileSide side;
  final String wordId;
  Map<String, Object?> toJson() => {'side': side.name, 'wordId': wordId};
  static PairTile fromJson(Object? value) {
    final j = pairJson(value, {'side', 'wordId'});
    return PairTile(
      PairTileSide.values.byName(j['side'] as String),
      j['wordId'] as String,
    );
  }
}

sealed class PairMatchingCommand {
  PairMatchingCommand({
    required this.operationId,
    required this.ownerId,
    required this.sessionId,
    required this.roundOrdinal,
    required this.expectedRevision,
  }) {
    if (!operationId.startsWith('$expectedRevision:') ||
        operationId.length > 128 ||
        operationId.length <= '$expectedRevision:'.length ||
        expectedRevision < 0 ||
        roundOrdinal < 0) {
      throw ArgumentError('Pair operation must bind its revision');
    }
  }
  final String operationId, ownerId, sessionId;
  final int roundOrdinal, expectedRevision;
  Map<String, Object?> get payload;
  String get fingerprint => pairHash(
    jsonEncode({
      'operationId': operationId,
      'ownerId': ownerId,
      'sessionId': sessionId,
      'roundOrdinal': roundOrdinal,
      'expectedRevision': expectedRevision,
      ...payload,
    }),
  );
}

final class PairSelectTile extends PairMatchingCommand {
  PairSelectTile({
    required super.operationId,
    required super.ownerId,
    required super.sessionId,
    required super.roundOrdinal,
    required super.expectedRevision,
    required this.tile,
    required this.responseTimeMs,
  });
  final PairTile tile;
  final int responseTimeMs;
  @override
  Map<String, Object?> get payload => {
    'kind': 'select',
    'tile': tile.toJson(),
    'responseTimeMs': responseTimeMs,
  };
}

/// Only answer-revealing support belongs here. Pronunciation/visible text is
/// modality, so hosts do not dispatch this command for narration.
final class PairRevealMapping extends PairMatchingCommand {
  PairRevealMapping({
    required super.operationId,
    required super.ownerId,
    required super.sessionId,
    required super.roundOrdinal,
    required super.expectedRevision,
    required this.wordId,
  });
  final String wordId;
  @override
  Map<String, Object?> get payload => {
    'kind': 'revealMapping',
    'wordId': wordId,
  };
}

final class PairAttemptRequested {
  const PairAttemptRequested({
    required this.operationId,
    required this.fingerprint,
    required this.promptWordId,
    required this.targetWordId,
    required this.roundOrdinal,
    required this.role,
    required this.responseTimeMs,
  });
  final String operationId, fingerprint, promptWordId, targetWordId;
  final int roundOrdinal, responseTimeMs;
  final PairAttemptRole role;
  bool get isCorrect => promptWordId == targetWordId;
  String get resolutionFingerprint => pairHash(
    jsonEncode([
      operationId,
      fingerprint,
      promptWordId,
      targetWordId,
      roundOrdinal,
      role.name,
      responseTimeMs,
    ]),
  );
  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'fingerprint': fingerprint,
    'promptWordId': promptWordId,
    'targetWordId': targetWordId,
    'roundOrdinal': roundOrdinal,
    'role': role.name,
    'responseTimeMs': responseTimeMs,
    'resolutionFingerprint': resolutionFingerprint,
  };
  static PairAttemptRequested fromJson(Object? value) {
    final j = pairJson(value, {
      'operationId',
      'fingerprint',
      'promptWordId',
      'targetWordId',
      'roundOrdinal',
      'role',
      'responseTimeMs',
      'resolutionFingerprint',
    });
    final attempt = PairAttemptRequested(
      operationId: j['operationId'] as String,
      fingerprint: j['fingerprint'] as String,
      promptWordId: j['promptWordId'] as String,
      targetWordId: j['targetWordId'] as String,
      roundOrdinal: j['roundOrdinal'] as int,
      role: PairAttemptRole.values.byName(j['role'] as String),
      responseTimeMs: j['responseTimeMs'] as int,
    );
    if (j['resolutionFingerprint'] != attempt.resolutionFingerprint) {
      throw const FormatException('Pair resolution fingerprint changed');
    }
    return attempt;
  }
}

/// Learner confirms the exact mapping already exposed by the guided state.
/// This is not a guessed distractor answer or an automatic success on failure.
final class PairConfirmGuidedMapping extends PairMatchingCommand {
  PairConfirmGuidedMapping({
    required super.operationId,
    required super.ownerId,
    required super.sessionId,
    required super.roundOrdinal,
    required super.expectedRevision,
    required this.wordId,
    required this.shownSupportRevision,
    required this.responseTimeMs,
  });
  final String wordId;
  final int shownSupportRevision, responseTimeMs;
  @override
  Map<String, Object?> get payload => {
    'kind': 'confirmGuidedMapping',
    'wordId': wordId,
    'shownSupportRevision': shownSupportRevision,
    'responseTimeMs': responseTimeMs,
  };
}

final class PairMatchingState {
  PairMatchingState._({
    required this.plan,
    required this.roundOrdinal,
    required this.operationRevision,
    required this.selected,
    required Iterable<String> matchedWordIds,
    required Iterable<String> supportedWordIds,
    Map<String, int> supportAtRevision = const {},
    required Iterable<PairAttemptRequested> attempts,
    required this.pending,
    required this.lastOperationId,
    required this.lastFingerprint,
  }) : matchedWordIds = Set.unmodifiable(matchedWordIds),
       supportedWordIds = Set.unmodifiable(supportedWordIds),
       supportAtRevision = Map.unmodifiable(supportAtRevision),
       attempts = List.unmodifiable(attempts);
  factory PairMatchingState.initial(PairMatchingPlanV1 plan) =>
      PairMatchingState._(
        plan: plan,
        roundOrdinal: 0,
        operationRevision: 0,
        selected: null,
        matchedWordIds: const {},
        supportedWordIds: const {},
        attempts: const [],
        pending: null,
        lastOperationId: null,
        lastFingerprint: null,
      );
  final PairMatchingPlanV1 plan;
  final int roundOrdinal, operationRevision;
  final PairTile? selected;
  final Set<String> matchedWordIds, supportedWordIds;
  final Map<String, int> supportAtRevision;
  final List<PairAttemptRequested> attempts;
  final PairAttemptRequested? pending;
  final String? lastOperationId, lastFingerprint;
  List<PairRepairTicket> get repairTickets => PairRepairPolicy.project(
    plan.orderedLexicalItems.map((i) => i.wordId).toList(),
    attempts.map(
      (a) => PairRepairAnswer(a.operationId, a.promptWordId, a.isCorrect),
    ),
  );
  PairRepairTicket? repairFor(String wordId) {
    for (final t in repairTickets) {
      if (t.wordId == wordId) return t;
    }
    return null;
  }

  HintEvidenceClassification classificationFor(PairAttemptRequested a) =>
      PairSupportPolicy.classify(
        supportRevision: supportAtRevision[a.promptWordId],
        attemptRevision: int.parse(a.operationId.split(':').first),
      );
  int get remainingRepairAttemptBound {
    var count = 0;
    int? firstRepairDelay;
    var guided = 0;
    for (final item in plan.orderedLexicalItems) {
      if (matchedWordIds.contains(item.wordId)) continue;
      final ticket = repairFor(item.wordId);
      count += ticket == null
          ? 3
          : ticket.status == PairRepairStatus.guidedRequired
          ? 1
          : 2;
      if (ticket?.status == PairRepairStatus.guidedRequired) {
        guided++;
      } else {
        final delay = ticket == null
            ? plan.orderedLexicalItems.length ~/ 2
            : ticket.status == PairRepairStatus.available
            ? 0
            : ticket.dueOrdinal - matchedWordIds.length;
        if (firstRepairDelay == null || delay < firstRepairDelay) {
          firstRepairDelay = delay;
        }
      }
    }
    // Before any further scheduled failure, distinct other pairs must finish.
    // Each costs at least one theoretical third attempt; already-forced
    // confirmations can supply that spacing without another deduction.
    final delay = firstRepairDelay ?? 0;
    final deduction = delay > guided ? delay - guided : 0;
    return count == 0 ? 0 : count - (deduction < count ? deduction : count - 1);
  }

  Set<String> get firstOpportunityWordIds =>
      Set.unmodifiable(attempts.map((a) => a.promptWordId));
  bool get complete => matchedWordIds.length == plan.orderedLexicalItems.length;
  Map<String, Object?> toJson() => {
    'roundOrdinal': roundOrdinal,
    'operationRevision': operationRevision,
    'selected': selected?.toJson(),
    'matchedWordIds': matchedWordIds.toList()..sort(),
    'supportedWordIds': supportedWordIds.toList()..sort(),
    'supportAtRevision': {
      for (final id in supportedWordIds.toList()..sort())
        id: supportAtRevision[id],
    },
    'attempts': attempts.map((a) => a.toJson()).toList(),
    'pending': pending?.toJson(),
    'lastOperationId': lastOperationId,
    'lastFingerprint': lastFingerprint,
  };
  static PairMatchingState fromJson(PairMatchingPlanV1 plan, Object? value) {
    final j = pairJson(value, {
      'roundOrdinal',
      'operationRevision',
      'selected',
      'matchedWordIds',
      'supportedWordIds',
      'supportAtRevision',
      'attempts',
      'pending',
      'lastOperationId',
      'lastFingerprint',
    });
    final state = PairMatchingState._(
      plan: plan,
      roundOrdinal: j['roundOrdinal'] as int,
      operationRevision: j['operationRevision'] as int,
      selected: j['selected'] == null ? null : PairTile.fromJson(j['selected']),
      matchedWordIds: (j['matchedWordIds'] as List).cast<String>(),
      supportedWordIds: (j['supportedWordIds'] as List).cast<String>(),
      supportAtRevision: (j['supportAtRevision'] as Map).cast<String, int>(),
      attempts: (j['attempts'] as List).map(PairAttemptRequested.fromJson),
      pending: j['pending'] == null
          ? null
          : PairAttemptRequested.fromJson(j['pending']),
      lastOperationId: j['lastOperationId'] as String?,
      lastFingerprint: j['lastFingerprint'] as String?,
    );
    final ids = plan.orderedLexicalItems.map((i) => i.wordId).toSet();
    final seen = <String>{}, operations = <String>{}, matched = <String>{};
    var previousRevision = -1;
    final repairHistory = <PairRepairAnswer>[];
    for (final a in [
      ...state.attempts,
      if (state.pending != null) state.pending!,
    ]) {
      final revision = int.tryParse(a.operationId.split(':').first);
      final supportRevision = state.supportAtRevision[a.promptWordId];
      final tickets = PairRepairPolicy.project(ids.toList(), repairHistory);
      final priorTickets = tickets.where((t) => t.wordId == a.promptWordId);
      final ticket = priorTickets.isEmpty ? null : priorTickets.single;
      final hiddenTarget = tickets.any(
        (t) =>
            t.wordId == a.targetWordId &&
            (t.status == PairRepairStatus.waiting ||
                (t.status == PairRepairStatus.guidedRequired &&
                    a.role != PairAttemptRole.guidedCompletion)),
      );
      if ((a.role == PairAttemptRole.delayedRepair &&
              ticket?.status != PairRepairStatus.available) ||
          (ticket?.status == PairRepairStatus.guidedRequired &&
              a.role != PairAttemptRole.independentRetry &&
              (a.role != PairAttemptRole.guidedCompletion || !a.isCorrect)) ||
          (identical(a, state.pending) &&
              (hiddenTarget ||
                  ticket?.status == PairRepairStatus.waiting ||
                  (a.role == PairAttemptRole.independentRetry &&
                      ticket != null)))) {
        throw const FormatException('Pair repair chronology changed');
      }
      if ((a.role == PairAttemptRole.guidedCompletion &&
              !(supportRevision != null &&
                  revision != null &&
                  supportRevision < revision)) ||
          (a.role != PairAttemptRole.guidedCompletion &&
              a.role != PairAttemptRole.delayedRepair &&
              supportRevision != null &&
              revision != null &&
              supportRevision < revision)) {
        throw const FormatException('Pair support chronology changed');
      }
      if (!ids.contains(a.promptWordId) ||
          !ids.contains(a.targetWordId) ||
          a.roundOrdinal != state.roundOrdinal ||
          a.responseTimeMs < 0 ||
          a.operationId.length > 128 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(a.fingerprint) ||
          !operations.add(a.operationId) ||
          revision == null ||
          revision <= previousRevision ||
          revision >= state.operationRevision ||
          matched.contains(a.promptWordId) ||
          matched.contains(a.targetWordId) ||
          (a.role == PairAttemptRole.firstOpportunity &&
              seen.contains(a.promptWordId)) ||
          (a.role == PairAttemptRole.independentRetry &&
              !seen.contains(a.promptWordId)) ||
          (a.role == PairAttemptRole.delayedRepair &&
              !seen.contains(a.promptWordId)) ||
          (a.role == PairAttemptRole.guidedCompletion &&
              !state.supportedWordIds.contains(a.promptWordId))) {
        throw const FormatException('Invalid Pair attempt ledger');
      }
      previousRevision = revision;
      repairHistory.add(
        PairRepairAnswer(a.operationId, a.promptWordId, a.isCorrect),
      );
      seen.add(a.promptWordId);
      if (!identical(a, state.pending) && a.isCorrect) {
        matched.add(a.promptWordId);
      }
    }
    if (state.supportAtRevision.length != state.supportedWordIds.length ||
        !state.supportedWordIds.containsAll(state.supportAtRevision.keys) ||
        state.supportAtRevision.values.any(
          (r) => r < 0 || r >= state.operationRevision,
        )) {
      throw const FormatException('Invalid Pair support ledger');
    }
    if (state.roundOrdinal != 0 ||
        state.operationRevision < 0 ||
        !ids.containsAll(state.supportedWordIds) ||
        !ids.containsAll(state.matchedWordIds) ||
        (state.selected != null &&
            (!ids.contains(state.selected!.wordId) ||
                matched.contains(state.selected!.wordId))) ||
        jsonEncode(matched.toList()..sort()) !=
            jsonEncode(state.matchedWordIds.toList()..sort()) ||
        (state.pending != null && state.selected != null) ||
        (state.operationRevision == 0) !=
            (state.lastOperationId == null && state.lastFingerprint == null) ||
        (state.lastOperationId != null &&
            (!state.lastOperationId!.startsWith(
                  '${state.operationRevision - 1}:',
                ) ||
                !RegExp(
                  r'^[0-9a-f]{64}$',
                ).hasMatch(state.lastFingerprint ?? ''))) ||
        state.attempts.length >
            LearningActivityRecoveryLimits.maximumAttempts ||
        jsonEncode(state.toJson()) != jsonEncode(j)) {
      throw const FormatException('Invalid Pair state');
    }
    return state;
  }
}

final class PairMatchingTransition {
  const PairMatchingTransition(this.state, [this.attempt]);
  final PairMatchingState state;
  final PairAttemptRequested? attempt;
}

abstract final class PairMatchingEngine {
  static PairMatchingTransition reduce(
    PairMatchingState state,
    PairMatchingCommand command,
  ) {
    if (command.ownerId != state.plan.ownerId ||
        command.sessionId != state.plan.learningSessionId ||
        command.roundOrdinal != state.roundOrdinal) {
      throw StateError('Stale Pair owner/session/round');
    }
    String? previous = state.lastOperationId == command.operationId
        ? state.lastFingerprint
        : null;
    for (final a in [
      ...state.attempts,
      if (state.pending != null) state.pending!,
    ]) {
      if (a.operationId == command.operationId) previous = a.fingerprint;
    }
    if (previous != null) {
      if (previous != command.fingerprint) {
        throw StateError('Pair operation payload conflict');
      }
      return PairMatchingTransition(state);
    }
    if (command.expectedRevision != state.operationRevision ||
        state.pending != null ||
        state.complete) {
      throw StateError('Stale or busy Pair operation');
    }
    final ids = state.plan.orderedLexicalItems.map((i) => i.wordId).toSet();
    var selected = state.selected;
    final supported = {...state.supportedWordIds};
    final supportRevisions = {...state.supportAtRevision};
    PairAttemptRequested? pending;
    switch (command) {
      case PairConfirmGuidedMapping(
        :final wordId,
        :final shownSupportRevision,
        :final responseTimeMs,
      ):
        if (!ids.contains(wordId) ||
            state.matchedWordIds.contains(wordId) ||
            state.supportAtRevision[wordId] != shownSupportRevision ||
            shownSupportRevision >= command.expectedRevision ||
            responseTimeMs < 0 ||
            (state.repairFor(wordId) != null &&
                state.repairFor(wordId)?.status !=
                    PairRepairStatus.guidedRequired)) {
          throw StateError('Invalid Pair guided confirmation');
        }
        pending = PairAttemptRequested(
          operationId: command.operationId,
          fingerprint: command.fingerprint,
          promptWordId: wordId,
          targetWordId: wordId,
          roundOrdinal: state.roundOrdinal,
          role: PairAttemptRole.guidedCompletion,
          responseTimeMs: responseTimeMs,
        );
        selected = null;
      case PairRevealMapping(:final wordId):
        if (!ids.contains(wordId) || state.matchedWordIds.contains(wordId)) {
          throw StateError('Invalid Pair reveal');
        }
        supported.add(wordId);
        supportRevisions.putIfAbsent(wordId, () => command.expectedRevision);
      case PairSelectTile(:final tile, :final responseTimeMs):
        if (!ids.contains(tile.wordId) ||
            state.matchedWordIds.contains(tile.wordId) ||
            state.repairFor(tile.wordId)?.status == PairRepairStatus.waiting ||
            state.repairFor(tile.wordId)?.status ==
                PairRepairStatus.guidedRequired ||
            responseTimeMs < 0) {
          throw StateError('Invalid Pair tile/response');
        }
        if (selected == null) {
          selected = tile;
        } else if (selected.side == tile.side) {
          selected = selected.wordId == tile.wordId ? null : tile;
        } else {
          final prompt = tile.side == PairTileSide.prompt
              ? tile.wordId
              : selected.wordId;
          final target = tile.side == PairTileSide.target
              ? tile.wordId
              : selected.wordId;
          pending = PairAttemptRequested(
            operationId: command.operationId,
            fingerprint: command.fingerprint,
            promptWordId: prompt,
            targetWordId: target,
            roundOrdinal: state.roundOrdinal,
            role: state.repairFor(prompt)?.status == PairRepairStatus.available
                ? PairAttemptRole.delayedRepair
                : supported.contains(prompt)
                ? PairAttemptRole.guidedCompletion
                : state.firstOpportunityWordIds.contains(prompt)
                ? PairAttemptRole.independentRetry
                : PairAttemptRole.firstOpportunity,
            responseTimeMs: responseTimeMs,
          );
          selected = null;
        }
    }
    return PairMatchingTransition(
      PairMatchingState._(
        plan: state.plan,
        roundOrdinal: state.roundOrdinal,
        operationRevision: state.operationRevision + 1,
        selected: selected,
        matchedWordIds: state.matchedWordIds,
        supportedWordIds: supported,
        supportAtRevision: supportRevisions,
        attempts: state.attempts,
        pending: pending,
        lastOperationId: command.operationId,
        lastFingerprint: command.fingerprint,
      ),
      pending,
    );
  }

  static PairMatchingState acknowledge(
    PairMatchingState state,
    String operationId,
  ) {
    final pending = state.pending;
    if (pending == null || pending.operationId != operationId) {
      throw StateError('Stale Pair acknowledgement');
    }
    final attempts = [...state.attempts, pending];
    final supported = {...state.supportedWordIds};
    final supportRevisions = {...state.supportAtRevision};
    final tickets = PairRepairPolicy.project(
      state.plan.orderedLexicalItems.map((i) => i.wordId).toList(),
      attempts.map(
        (a) => PairRepairAnswer(a.operationId, a.promptWordId, a.isCorrect),
      ),
    );
    for (final t in tickets) {
      if (t.status == PairRepairStatus.guidedRequired) {
        supported.add(t.wordId);
        // Equal to this attempted revision: it cannot reclassify that answer.
        supportRevisions.putIfAbsent(
          t.wordId,
          () => state.operationRevision - 1,
        );
      }
    }
    return PairMatchingState._(
      plan: state.plan,
      roundOrdinal: state.roundOrdinal,
      operationRevision: state.operationRevision,
      selected: null,
      matchedWordIds: {
        ...state.matchedWordIds,
        if (pending.isCorrect) pending.promptWordId,
      },
      supportedWordIds: supported,
      supportAtRevision: supportRevisions,
      attempts: attempts,
      pending: null,
      lastOperationId: state.lastOperationId,
      lastFingerprint: state.lastFingerprint,
    );
  }
}
