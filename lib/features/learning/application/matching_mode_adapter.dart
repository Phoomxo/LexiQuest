import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../vocabulary/application/vocabulary_use_cases.dart';
import '../domain/answer_feedback.dart';
import '../domain/evidence_context.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_models.dart';
import '../domain/learning_event_context.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';
import 'current_activity_evidence.dart';
import 'learning_use_cases.dart';

typedef MatchingSessionCompleter =
    Future<LearningSessionSummary> Function(PendingLearningSessionClose close);
typedef MatchingCloseOwner =
    void Function(
      PendingLearningSessionClose close,
      Future<void> Function() ensureDurable,
    );
typedef MatchingAdmittedOperation =
    Future<T> Function<T>(Future<T> Function() operation);
typedef MatchingRecoveryOperation =
    Future<T> Function<T>(Future<T> Function() operation);
typedef MatchingOperationAcceptance = bool Function();
typedef MatchingHintUsage = HintUsageSnapshot Function();
typedef MatchingHintReset = void Function();
typedef _MatchingPendingPersister =
    Future<void> Function({
      required PendingCurrentActivityEvidence pending,
      required String selectedMeaningWordId,
      required HintEvidenceClassification classification,
      required String contentRevision,
      required String canonicalCorrectAnswer,
      required ResolvedLearningEvidenceContexts contexts,
    });
typedef _MatchingClosePersister =
    Future<void> Function({
      required PendingLearningSessionClose close,
      required bool timeoutRequested,
    });
typedef _MatchingCloseAcknowledger =
    Future<void> Function(LearningSessionSummary summary);

Future<void> _noopPendingPersist({
  required PendingCurrentActivityEvidence pending,
  required String selectedMeaningWordId,
  required HintEvidenceClassification classification,
  required String contentRevision,
  required String canonicalCorrectAnswer,
  required ResolvedLearningEvidenceContexts contexts,
}) async {}

Future<void> _noopCheckpoint() async {}

Future<void> _noopClosePersist({
  required PendingLearningSessionClose close,
  required bool timeoutRequested,
}) async {}

Future<void> _noopCloseAcknowledge(LearningSessionSummary summary) async {}

final class MatchingPair {
  const MatchingPair({
    required this.word,
    required this.wordLabel,
    required this.meaningLabel,
  });

  final QuizWord word;
  final String wordLabel;
  final String meaningLabel;
}

final class MatchingPairSet {
  const MatchingPairSet._({
    required this.pairs,
    required this.wordOrder,
    required this.meaningOrder,
  });

  final List<MatchingPair> pairs;
  final List<MatchingPair> wordOrder;
  final List<MatchingPair> meaningOrder;

  bool get isEmpty => pairs.isEmpty;
}

final class MatchingPreparedSession {
  MatchingPreparedSession._({
    required this.session,
    required Set<String> matchedWordIds,
    required this.attemptNumber,
    required this._checkpoint,
    required this.learning,
    required Map<String, Object?> state,
    this.timeoutAnchorUtc,
    this.timeoutDuration,
    this.timeoutDeadlineUtc,
    required this.needsTimeoutUpgrade,
    this.needsPendingClear = false,
    this.summaryPresented = false,
    this.pendingEvidence,
    this.pendingFeedbackContext,
    this.pendingWordId,
    this.pendingCorrect = false,
    this.pendingClose,
    this.completedSummary,
    this.timeoutRequested = false,
  }) : matchedWordIds = Set<String>.unmodifiable(matchedWordIds),
       _state = Map<String, Object?>.of(state);

  final QuizSession session;
  final Set<String> matchedWordIds;
  final int attemptNumber;
  final LearningUseCases learning;
  final PendingCurrentActivityEvidence? pendingEvidence;
  final FrozenAnswerFeedbackContext? pendingFeedbackContext;
  final String? pendingWordId;
  final bool pendingCorrect;
  final PendingLearningSessionClose? pendingClose;
  final LearningSessionSummary? completedSummary;
  final bool timeoutRequested;
  final DateTime? timeoutAnchorUtc;
  final Duration? timeoutDuration;
  final DateTime? timeoutDeadlineUtc;
  final bool needsTimeoutUpgrade;
  final bool needsPendingClear;
  final bool summaryPresented;
  LearningActivityCheckpoint _checkpoint;
  Map<String, Object?> _state;
  LearningActivityCheckpoint? _pendingAppend;
  LearningSessionSummary? _acknowledgedSummary;

  int get maximumAttemptNumber {
    final pendingClearReservation = pendingEvidence == null ? 0 : 1;
    final remainingCheckpointPairs =
        (MatchingModeAdapter.maximumCheckpoints -
            _checkpoint.revision -
            MatchingModeAdapter.terminalCheckpointReservation -
            pendingClearReservation) ~/
        2;
    final bounded =
        attemptNumber +
        (remainingCheckpointPairs < 0 ? 0 : remainingCheckpointPairs);
    return bounded > MatchingModeAdapter.maximumAttempts
        ? MatchingModeAdapter.maximumAttempts
        : bounded;
  }

  bool get hasWallClockTimeout => timeoutDeadlineUtc != null;

  bool get requiresRecovery =>
      pendingEvidence != null ||
      pendingClose != null ||
      completedSummary != null ||
      needsPendingClear ||
      timeoutRequested;

  Duration? remainingTime(DateTime nowUtc) {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    final anchor = timeoutAnchorUtc;
    final duration = timeoutDuration;
    final deadline = timeoutDeadlineUtc;
    if (anchor == null || duration == null || deadline == null) return null;
    if (nowUtc.isBefore(anchor)) {
      throw StateError('Matching clock moved behind the timeout anchor.');
    }
    final remaining = deadline.difference(nowUtc);
    if (remaining.isNegative) return Duration.zero;
    return remaining > duration ? duration : remaining;
  }

  Future<void> persistTimeoutContract() {
    if (!needsTimeoutUpgrade) return Future<void>.value();
    return _appendState(<String, Object?>{
      ..._state,
      'schemaVersion': 5,
      'timingKind': hasWallClockTimeout ? 'timed' : 'activeEffort',
      'timeoutAnchorUtc': timeoutAnchorUtc?.toIso8601String(),
      'timeoutDurationMs': timeoutDuration?.inMilliseconds,
      'timeoutDeadlineUtc': timeoutDeadlineUtc?.toIso8601String(),
      'summaryPresented': summaryPresented,
    });
  }

  Future<void> persistPending({
    required PendingCurrentActivityEvidence pending,
    required String selectedMeaningWordId,
    required HintEvidenceClassification classification,
    required String contentRevision,
    required String canonicalCorrectAnswer,
    required ResolvedLearningEvidenceContexts contexts,
  }) => _appendState(<String, Object?>{
    ..._state,
    'pendingEvidence': <String, Object?>{
      'schemaVersion': 3,
      'actorIdentity':
          pending.actorIdentity ??
          (throw StateError('Matching pending actor is unavailable.')),
      'providerProvenance': 'pinned-lexical-matching',
      'sourceEvidenceId': pending.sourceEvidenceId,
      'occurredAtUtc': pending.occurredAtUtc.toIso8601String(),
      'wordId': pending.wordId,
      'selectedMeaningWordId': selectedMeaningWordId,
      'isCorrect': pending.isCorrect,
      'responseTimeMs': pending.responseTimeMs,
      'attemptNumber': pending.attemptNumber,
      'evidenceClass': classification.evidenceClass.name,
      'hintLevel': classification.hintLevel,
      'contentRevision': contentRevision,
      'canonicalCorrectAnswer': canonicalCorrectAnswer,
      'evidenceContext': contexts.evidenceContext.toJson(),
      'eventContext': contexts.eventContext.toJson(),
    },
  });

  Future<void> clearPending() =>
      _appendState(<String, Object?>{..._state, 'pendingEvidence': null});

  Future<void> persistClose({
    required PendingLearningSessionClose close,
    required bool timeoutRequested,
  }) => _appendState(
    <String, Object?>{
      ..._state,
      'pendingCloseAtUtc': close.completedAtUtc.toIso8601String(),
      'timeoutRequested': timeoutRequested,
    },
    terminalAtUtc: close.completedAtUtc,
    terminalAcknowledged: false,
  );

  Future<void> acknowledgeClose(LearningSessionSummary summary) {
    final terminalAtUtc = summary.endedAtUtc;
    if (summary.id != session.id || terminalAtUtc == null) {
      throw StateError('Matching completion identity is invalid.');
    }
    return _appendState(
      <String, Object?>{
        ..._state,
        'schemaVersion': 5,
        'pendingCloseAtUtc': null,
        'summaryPresented': false,
      },
      terminalAtUtc: terminalAtUtc,
      terminalAcknowledged: true,
    ).then((_) => _acknowledgedSummary = summary);
  }

  Future<LearningSessionSummary> reconcileCompleted({
    required MatchingSessionCompleter completeSession,
  }) async {
    final summary = completedSummary;
    final terminalAtUtc = _checkpoint.terminalAtUtc;
    if (summary == null ||
        terminalAtUtc == null ||
        summary.id != session.id ||
        summary.endedAtUtc != terminalAtUtc) {
      throw StateError('Matching completed recovery identity is invalid.');
    }
    final close = learning.restoreSessionClose(
      sessionId: session.id,
      completedAtUtc: terminalAtUtc,
    );
    final reconciled = await completeSession(close);
    if (reconciled.id != summary.id ||
        reconciled.ownerId != summary.ownerId ||
        reconciled.activityType != summary.activityType ||
        reconciled.state != summary.state ||
        reconciled.startedAtUtc != summary.startedAtUtc ||
        reconciled.endedAtUtc != summary.endedAtUtc ||
        reconciled.correctCount != summary.correctCount ||
        reconciled.wrongCount != summary.wrongCount ||
        reconciled.score != summary.score) {
      throw StateError('Matching completed summary identity changed.');
    }
    if (!_checkpoint.terminalAcknowledged) {
      try {
        await acknowledgeClose(summary);
      } on Object {
        await acknowledgeClose(summary);
      }
    }
    return summary;
  }

  Future<void> markSummaryPresented(LearningSessionSummary summary) {
    final acknowledged = _acknowledgedSummary ?? completedSummary;
    if (!_checkpoint.terminalAcknowledged) {
      return Future<void>.value();
    }
    if (acknowledged == null || !_sameSummary(acknowledged, summary)) {
      throw StateError('Matching presented summary identity is invalid.');
    }
    if (_state['summaryPresented'] == true) return Future<void>.value();
    return _appendState(
      <String, Object?>{
        ..._state,
        'schemaVersion': 5,
        'summaryPresented': true,
      },
      terminalAtUtc: _checkpoint.terminalAtUtc,
      terminalAcknowledged: true,
    );
  }

  Future<void> _appendState(
    Map<String, Object?> nextState, {
    DateTime? terminalAtUtc,
    bool? terminalAcknowledged,
  }) async {
    final requestedTerminalAtUtc = terminalAtUtc ?? _checkpoint.terminalAtUtc;
    final requestedAcknowledged =
        terminalAcknowledged ?? _checkpoint.terminalAcknowledged;
    final retained = _pendingAppend;
    if (retained != null &&
        (jsonEncode(retained.state) != jsonEncode(nextState) ||
            retained.terminalAtUtc != requestedTerminalAtUtc ||
            retained.terminalAcknowledged != requestedAcknowledged)) {
      throw StateError(
        'A different Matching checkpoint cannot replace a pending write.',
      );
    }
    if (retained == null &&
        _checkpoint.revision >= MatchingModeAdapter.maximumCheckpoints) {
      throw StateError('Matching checkpoint budget is exhausted.');
    }
    final checkpoint =
        retained ??
        LearningActivityCheckpoint(
          sessionId: session.id,
          activityType: MatchingModeAdapter.activityType,
          revision: _checkpoint.revision + 1,
          occurredAtUtc: learning.nowUtc(),
          state: nextState,
          terminalAtUtc: requestedTerminalAtUtc,
          terminalAcknowledged: requestedAcknowledged,
        );
    _pendingAppend = checkpoint;
    await learning.appendActivityCheckpoint(checkpoint);
    _checkpoint = checkpoint;
    _state = Map<String, Object?>.of(nextState);
    _pendingAppend = null;
  }

  bool _sameSummary(
    LearningSessionSummary left,
    LearningSessionSummary right,
  ) =>
      left.id == right.id &&
      left.ownerId == right.ownerId &&
      left.activityType == right.activityType &&
      left.state == right.state &&
      left.startedAtUtc == right.startedAtUtc &&
      left.endedAtUtc == right.endedAtUtc &&
      left.correctCount == right.correctCount &&
      left.wrongCount == right.wrongCount &&
      left.score == right.score &&
      left.appVersion == right.appVersion &&
      left.buildId == right.buildId;
}

enum MatchingReviewPhase {
  awaitingSelection,
  savingEvidence,
  evidenceRetryRequired,
  completing,
  completionRetryRequired,
  completed,
}

final class _MatchingTimeoutContract {
  const _MatchingTimeoutContract({
    required this.anchorUtc,
    required this.duration,
    required this.deadlineUtc,
    required this.needsUpgrade,
  });

  final DateTime? anchorUtc;
  final Duration? duration;
  final DateTime? deadlineUtc;
  final bool needsUpgrade;
}

final class _MatchingPendingRecovery {
  const _MatchingPendingRecovery({
    required this.pending,
    required this.feedbackContext,
  }) : requiresClear = false;

  const _MatchingPendingRecovery.committed()
    : pending = null,
      feedbackContext = null,
      requiresClear = true;

  final PendingCurrentActivityEvidence? pending;
  final FrozenAnswerFeedbackContext? feedbackContext;
  final bool requiresClear;
}

/// Typed boundary for fluent word/meaning recognition. It owns deterministic
/// pair construction and response classification, while the shared evidence
/// gateway remains the sole AnswerAttempts writer.
final class MatchingModeAdapter
    implements
        FocusTimerSupportingLessonModeAdapter,
        HintSupportingLessonModeAdapter,
        SessionConfigurableLessonModeAdapter {
  const MatchingModeAdapter({this.maximumPairs = 6});

  final int maximumPairs;

  static const String activityType = 'matching';
  static const Duration legacyV1CompatibilityTimeLimit = Duration(minutes: 2);
  static const int maximumCheckpoints = 64;
  static const int maximumAttempts = 30;
  static const int terminalCheckpointReservation = 3;

  @override
  LessonMode get mode => LessonMode.matching;

  @override
  SessionConfigurationCapabilities get sessionConfigurationCapabilities =>
      const SessionConfigurationCapabilities(
        minimumItemCount: 2,
        maximumItemCount: 6,
        defaultItemCount: 6,
        directions: <SessionDirection>{SessionDirection.forward},
        difficulties: <SessionDifficulty>{SessionDifficulty.standard},
        maximumHintBudget: 2,
        supportsTimed: true,
        supportsUntimedAlternative: true,
        supportsPackSelection: false,
      );

  @override
  HintPolicy get hintPolicy => HintPolicy.staged(
    strategy: 'Match one word to the meaning that expresses the same idea.',
    context:
        'Compare the remaining pairs and eliminate meanings that conflict.',
  );

  HintEvidenceClassification classifyResponse({
    required HintUsageSnapshot hint,
    required bool supportUsed,
  }) {
    final observedLevel = switch (hint.availability) {
      HintAvailability.available => hint.hintLevel ?? 2,
      HintAvailability.unavailable => 0,
      HintAvailability.unknown => 2,
    };
    final level = supportUsed && observedLevel == 0 ? 1 : observedLevel;
    return HintEvidenceClassification(
      evidenceClass: level == 0
          ? EvidenceClass.recognition
          : EvidenceClass.guidedPractice,
      hintLevel: level,
    );
  }

  MatchingPairSet pinPairs(QuizSession session) {
    if (maximumPairs < 1 || maximumPairs > 20) {
      throw RangeError.range(maximumPairs, 1, 20, 'maximumPairs');
    }
    final words = session.questions.map((question) => question.word).toList();
    final idCounts = <String, int>{};
    final spellingCounts = <String, int>{};
    final meaningCounts = <String, int>{};
    for (final word in words) {
      idCounts.update(word.id, (count) => count + 1, ifAbsent: () => 1);
      final spelling = _spellingKey(word);
      final meaning = _meaningKey(word);
      if (spelling.isEmpty || meaning.isEmpty) continue;
      spellingCounts.update(spelling, (count) => count + 1, ifAbsent: () => 1);
      meaningCounts.update(meaning, (count) => count + 1, ifAbsent: () => 1);
    }
    final safe =
        words
            .where(
              (word) =>
                  idCounts[word.id] == 1 &&
                  spellingCounts[_spellingKey(word)] == 1 &&
                  meaningCounts[_meaningKey(word)] == 1,
            )
            .map(
              (word) => MatchingPair(
                word: word,
                wordLabel: _canonicalDisplay(word.spelling),
                meaningLabel: _canonicalDisplay(word.meaning),
              ),
            )
            .toList(growable: false)
          ..sort(
            (left, right) => _stableCompare(
              '${session.id}:pair:${left.word.id}',
              '${session.id}:pair:${right.word.id}',
            ),
          );
    final pairs = List<MatchingPair>.unmodifiable(safe.take(maximumPairs));
    if (pairs.length < 2) {
      return const MatchingPairSet._(
        pairs: <MatchingPair>[],
        wordOrder: <MatchingPair>[],
        meaningOrder: <MatchingPair>[],
      );
    }
    final wordOrder = List<MatchingPair>.of(pairs)
      ..sort(
        (left, right) => _stableCompare(
          '${session.id}:word:${left.word.id}',
          '${session.id}:word:${right.word.id}',
        ),
      );
    final meaningOrder = List<MatchingPair>.of(pairs)
      ..sort(
        (left, right) => _stableCompare(
          '${session.id}:meaning:${left.word.id}',
          '${session.id}:meaning:${right.word.id}',
        ),
      );
    return MatchingPairSet._(
      pairs: pairs,
      wordOrder: List<MatchingPair>.unmodifiable(wordOrder),
      meaningOrder: List<MatchingPair>.unmodifiable(meaningOrder),
    );
  }

  /// Reconstructs the newest canonical Matching session, or atomically starts
  /// a new checkpointed session. Vocabulary is snapshotted in the checkpoint
  /// so later edits cannot change an interrupted board.
  Future<MatchingPreparedSession> prepareSession({
    required LearningUseCases learning,
    required CurrentActivityEvidenceAdapter evidence,
    String? categoryId,
    Duration? timeLimit = const Duration(minutes: 2),
    int itemCount = 6,
    SessionConfiguration? sessionConfiguration,
  }) async {
    if (!identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Matching evidence must use the session LearningUseCases authority.',
      );
    }
    if (timeLimit != null &&
        (timeLimit <= Duration.zero ||
            timeLimit > const Duration(minutes: 30))) {
      throw RangeError.range(
        timeLimit.inMilliseconds,
        1,
        const Duration(minutes: 30).inMilliseconds,
        'timeLimit',
      );
    }
    if (itemCount < 2 || itemCount > maximumPairs) {
      throw RangeError.range(itemCount, 2, maximumPairs, 'itemCount');
    }
    var recovery = await learning.loadActivityRecovery(
      activityType: activityType,
    );
    if (recovery != null &&
        recovery.session.sessionConfiguration != sessionConfiguration) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    if (recovery?.session.state == 'completed' &&
        recovery?.checkpoint?.terminalAcknowledged == true &&
        recovery?.checkpoint?.state['summaryPresented'] == true) {
      recovery = null;
    }
    if (recovery != null && recovery.checkpoint == null) {
      await learning.abandonSession(
        sessionId: recovery.session.id,
        abandonedAtUtc: learning.nowUtc(),
      );
      recovery = null;
    }
    if (recovery == null) {
      final session = await learning.startCheckpointedQuiz(
        activityType: activityType,
        categoryId: categoryId,
        limit: itemCount,
        sessionConfiguration: sessionConfiguration,
        initialState: (candidate) {
          final pairSet = pinPairs(candidate);
          if (pairSet.isEmpty) {
            throw ArgumentError.value(
              candidate,
              'session',
              'must contain at least two ambiguity-safe pairs',
            );
          }
          return _encodeCheckpointState(
            QuizSession(
              id: candidate.id,
              startedAtUtc: candidate.startedAtUtc,
              questions: pairSet.pairs
                  .map(
                    (pair) => QuizQuestion(
                      word: pair.word,
                      options: const <String>[],
                    ),
                  )
                  .toList(growable: false),
            ),
            timeoutDeadlineUtc: timeLimit == null
                ? null
                : candidate.startedAtUtc!.add(timeLimit),
          );
        },
      );
      if (session.isEmpty) {
        return MatchingPreparedSession._(
          session: session,
          matchedWordIds: const <String>{},
          attemptNumber: 0,
          checkpoint: LearningActivityCheckpoint(
            sessionId: '',
            activityType: activityType,
            revision: 0,
            occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            state: const <String, Object?>{},
          ),
          learning: learning,
          state: const <String, Object?>{},
          timeoutAnchorUtc: null,
          timeoutDuration: null,
          timeoutDeadlineUtc: null,
          needsTimeoutUpgrade: false,
          needsPendingClear: false,
          summaryPresented: false,
        );
      }
      recovery = await learning.loadActivityRecovery(
        activityType: activityType,
      );
      if (recovery == null || recovery.session.id != session.id) {
        throw StateError('checkpointed Matching session could not be read');
      }
    }
    final prepared = _restorePreparedSession(recovery, learning, evidence);
    if (prepared.needsPendingClear) {
      try {
        await prepared.clearPending();
      } on Object {
        // Retry the exact retained append to reconcile a committed write whose
        // acknowledgement was lost without permitting a later state to pass it.
        await prepared.clearPending();
      }
    }
    if (prepared.needsTimeoutUpgrade) {
      await prepared.persistTimeoutContract();
    }
    return prepared;
  }

  MatchingPreparedSession _restorePreparedSession(
    LearningActivityRecovery recovery,
    LearningUseCases learning,
    CurrentActivityEvidenceAdapter evidence,
  ) {
    final checkpoint = recovery.checkpoint;
    if (checkpoint == null) {
      throw StateError('Matching recovery checkpoint is missing');
    }
    final session = _decodeCheckpointSession(
      checkpoint,
      recovery.session.startedAtUtc,
      recovery.session.sessionConfiguration,
    );
    final timeout = _decodeTimeoutContract(
      checkpoint: checkpoint,
      startedAtUtc: recovery.session.startedAtUtc,
    );
    final configuredTiming = recovery.session.sessionConfiguration?.timing;
    if (configuredTiming != null &&
        ((configuredTiming.kind == SessionTimingKind.timed) !=
            (timeout.deadlineUtc != null))) {
      throw StateError(
        'Matching timing does not match its pinned configuration',
      );
    }
    final pairSet = pinPairs(session);
    if (pairSet.isEmpty || pairSet.pairs.length != session.questions.length) {
      throw StateError('Matching checkpoint contains an unsafe pair set');
    }
    final pairIds = pairSet.pairs.map((pair) => pair.word.id).toSet();
    final matched = <String>{};
    var attemptNumber = 0;
    for (final attempt in recovery.attempts) {
      final validMatchingEvidence =
          (attempt.evidenceContext.evidenceClass == EvidenceClass.recognition &&
              attempt.evidenceContext.hintLevel == 0) ||
          (attempt.evidenceContext.evidenceClass ==
                  EvidenceClass.guidedPractice &&
              attempt.evidenceContext.hintLevel > 0);
      if (attempt.sessionId != session.id ||
          attempt.promptMode != 'matchingPair' ||
          !pairIds.contains(attempt.wordId) ||
          attempt.attemptNumber != attemptNumber + 1 ||
          attempt.attemptNumber > maximumAttempts ||
          attempt.providerProvenance != 'pinned-lexical-matching' ||
          attempt.evidenceContext.skillId != 'matching-recognition' ||
          !validMatchingEvidence) {
        throw StateError('Matching attempt cannot be reconstructed safely');
      }
      final pair = pairSet.pairs.singleWhere(
        (candidate) => candidate.word.id == attempt.wordId,
      );
      if (attempt.evidenceContext.contentRevision !=
          evidenceContentRevision(pair.word)) {
        throw StateError('Matching attempt content identity is corrupt');
      }
      attemptNumber = attempt.attemptNumber;
      if (attempt.isCorrect) matched.add(attempt.wordId);
    }
    final pending = _decodePendingEvidence(
      state: checkpoint.state,
      session: session,
      pairSet: pairSet,
      evidence: evidence,
      attempts: recovery.attempts,
      lastAttemptNumber: attemptNumber,
    );
    if ((pending?.pending?.attemptNumber ?? attemptNumber) > maximumAttempts) {
      throw StateError('Matching attempt budget is corrupt');
    }
    final logicalAttemptNumber =
        pending?.pending?.attemptNumber ?? attemptNumber;
    final minimumCheckpointRevision = pending?.requiresClear == true
        ? logicalAttemptNumber * 2
        : pending?.pending != null
        ? logicalAttemptNumber * 2
        : logicalAttemptNumber * 2 + 1;
    if (checkpoint.revision < minimumCheckpointRevision) {
      throw StateError('Matching attempt checkpoint history is incomplete');
    }
    final pendingCloseAtUtc = _optionalUtc(
      checkpoint.state['pendingCloseAtUtc'],
      'pendingCloseAtUtc',
    );
    final timeoutRequested = checkpoint.state['timeoutRequested'];
    final summaryPresented = checkpoint.state['summaryPresented'] == true;
    final completed = recovery.session.state == 'completed';
    final activeTerminalValid =
        !completed &&
        recovery.session.state == 'active' &&
        pendingCloseAtUtc == checkpoint.terminalAtUtc &&
        !checkpoint.terminalAcknowledged &&
        !summaryPresented;
    final completedTerminalValid =
        completed &&
        checkpoint.terminalAtUtc == recovery.session.endedAtUtc &&
        pending == null &&
        (checkpoint.terminalAcknowledged
            ? pendingCloseAtUtc == null
            : pendingCloseAtUtc == recovery.session.endedAtUtc) &&
        (!summaryPresented || checkpoint.terminalAcknowledged);
    if (!activeTerminalValid && !completedTerminalValid) {
      throw StateError('Matching terminal recovery identity is corrupt');
    }
    return MatchingPreparedSession._(
      session: session,
      matchedWordIds: matched,
      attemptNumber: pending?.pending?.attemptNumber ?? attemptNumber,
      checkpoint: checkpoint,
      learning: learning,
      state: checkpoint.state,
      timeoutAnchorUtc: timeout.anchorUtc,
      timeoutDuration: timeout.duration,
      timeoutDeadlineUtc: timeout.deadlineUtc,
      needsTimeoutUpgrade: timeout.needsUpgrade,
      needsPendingClear: pending?.requiresClear ?? false,
      summaryPresented: summaryPresented,
      pendingEvidence: pending?.pending,
      pendingFeedbackContext: pending?.feedbackContext,
      pendingWordId: pending?.pending?.wordId,
      pendingCorrect: pending?.pending?.isCorrect ?? false,
      pendingClose: pendingCloseAtUtc == null
          ? null
          : completed
          ? null
          : learning.restoreSessionClose(
              sessionId: session.id,
              completedAtUtc: pendingCloseAtUtc,
            ),
      completedSummary: completed ? recovery.session : null,
      timeoutRequested: timeoutRequested is bool && timeoutRequested,
    );
  }

  _MatchingPendingRecovery? _decodePendingEvidence({
    required Map<String, Object?> state,
    required QuizSession session,
    required MatchingPairSet pairSet,
    required CurrentActivityEvidenceAdapter evidence,
    required List<RecordAnswerCandidate> attempts,
    required int lastAttemptNumber,
  }) {
    final encoded = state['pendingEvidence'];
    if (encoded == null) return null;
    if (encoded is! Map<String, Object?>) {
      throw StateError('Matching pending evidence schema is invalid');
    }
    const v1Keys = <String>{
      'sourceEvidenceId',
      'occurredAtUtc',
      'wordId',
      'selectedMeaningWordId',
      'isCorrect',
      'responseTimeMs',
      'attemptNumber',
      'evidenceClass',
      'hintLevel',
      'contentRevision',
      'canonicalCorrectAnswer',
      'evidenceContext',
      'eventContext',
    };
    const v2Keys = <String>{...v1Keys, 'schemaVersion', 'actorIdentity'};
    const v3Keys = <String>{...v2Keys, 'providerProvenance'};
    final pendingSchemaVersion = encoded['schemaVersion'];
    final keys = switch (pendingSchemaVersion) {
      2 => v2Keys,
      3 => v3Keys,
      _ => v1Keys,
    };
    if ((pendingSchemaVersion != null &&
            pendingSchemaVersion != 2 &&
            pendingSchemaVersion != 3) ||
        encoded.length != keys.length ||
        !encoded.keys.every(keys.contains)) {
      throw StateError('Matching pending evidence schema is invalid');
    }
    T requiredValue<T>(String key) {
      final value = encoded[key];
      if (value is! T) {
        throw StateError('Matching pending evidence field $key is invalid');
      }
      return value;
    }

    final sourceEvidenceId = requiredValue<String>('sourceEvidenceId');
    final actorIdentity = pendingSchemaVersion == 2 || pendingSchemaVersion == 3
        ? requiredValue<String>('actorIdentity')
        : null;
    final providerProvenance = pendingSchemaVersion == 3
        ? requiredValue<String>('providerProvenance')
        : 'pinned-lexical-matching';
    if (actorIdentity != null &&
        (actorIdentity.isEmpty ||
            actorIdentity != actorIdentity.trim() ||
            actorIdentity.length > 256)) {
      throw StateError('Matching pending actor is invalid');
    }
    final occurredAtEncoded = requiredValue<String>('occurredAtUtc');
    final occurredAtUtc = occurredAtEncoded.endsWith('Z')
        ? DateTime.tryParse(occurredAtEncoded)
        : null;
    if (occurredAtUtc == null || !occurredAtUtc.isUtc) {
      throw StateError('Matching pending evidence occurrence is invalid');
    }
    final wordId = requiredValue<String>('wordId');
    final selectedMeaningWordId = requiredValue<String>(
      'selectedMeaningWordId',
    );
    final isCorrect = requiredValue<bool>('isCorrect');
    final responseTimeMs = requiredValue<int>('responseTimeMs');
    final pendingAttemptNumber = requiredValue<int>('attemptNumber');
    final hintLevel = requiredValue<int>('hintLevel');
    final contentRevision = requiredValue<String>('contentRevision');
    final canonicalCorrectAnswer = requiredValue<String>(
      'canonicalCorrectAnswer',
    );
    final evidenceContextJson = requiredValue<Map<String, Object?>>(
      'evidenceContext',
    );
    final eventContextJson = requiredValue<Map<String, Object?>>(
      'eventContext',
    );
    late final EvidenceContext frozenEvidenceContext;
    late final LearningEventContext frozenEventContext;
    try {
      frozenEvidenceContext = EvidenceContext.fromJson(evidenceContextJson);
      frozenEventContext = LearningEventContext.fromJson(eventContextJson);
      frozenEventContext.validateAgainst(
        evidenceContext: frozenEvidenceContext,
        occurredAtUtc: occurredAtUtc,
      );
    } on Object catch (error) {
      throw StateError('Matching pending contexts are corrupt: $error');
    }
    final committed = attempts
        .where((attempt) => attempt.id == sourceEvidenceId)
        .toList(growable: false);
    if (committed.length > 1 ||
        pendingAttemptNumber !=
            (committed.isEmpty ? lastAttemptNumber + 1 : lastAttemptNumber) ||
        !pairSet.pairs.any((pair) => pair.word.id == wordId) ||
        !pairSet.pairs.any((pair) => pair.word.id == selectedMeaningWordId) ||
        isCorrect != (wordId == selectedMeaningWordId)) {
      throw StateError('Matching pending evidence cannot be reconstructed');
    }
    final word = pairSet.pairs.singleWhere((pair) => pair.word.id == wordId);
    if (contentRevision != evidenceContentRevision(word.word) ||
        canonicalCorrectAnswer != word.meaningLabel) {
      throw StateError('Matching pending content identity is corrupt');
    }
    final evidenceClass = EvidenceClass.values.byName(
      requiredValue<String>('evidenceClass'),
    );
    final classification = HintEvidenceClassification(
      evidenceClass: evidenceClass,
      hintLevel: hintLevel,
    );
    final validUnassisted =
        evidenceClass == EvidenceClass.recognition && hintLevel == 0;
    final validAssisted =
        evidenceClass == EvidenceClass.guidedPractice && hintLevel > 0;
    if (providerProvenance != 'pinned-lexical-matching' ||
        (!validUnassisted && !validAssisted)) {
      throw StateError('Matching pending evidence classification is invalid');
    }
    if (frozenEvidenceContext.evidenceClass != evidenceClass ||
        frozenEvidenceContext.hintLevel != hintLevel ||
        frozenEvidenceContext.skillId != 'matching-recognition' ||
        frozenEvidenceContext.contentRevision != contentRevision) {
      throw StateError(
        'Matching pending contexts conflict with their classification',
      );
    }
    if (committed.isNotEmpty) {
      final attempt = committed.single;
      if (attempt.wordId != wordId ||
          attempt.actorIdentity != (actorIdentity ?? attempt.ownerId) ||
          attempt.providerProvenance != providerProvenance ||
          attempt.occurredAtUtc != occurredAtUtc ||
          attempt.isCorrect != isCorrect ||
          attempt.responseTimeMs != responseTimeMs ||
          attempt.attemptNumber != pendingAttemptNumber ||
          attempt.evidenceContext.evidenceClass != evidenceClass ||
          attempt.evidenceContext.hintLevel != hintLevel ||
          attempt.evidenceContext.contentRevision != contentRevision ||
          jsonEncode(attempt.evidenceContext.toJson()) !=
              jsonEncode(frozenEvidenceContext.toJson()) ||
          attempt.eventContext == null ||
          jsonEncode(attempt.eventContext!.toJson()) !=
              jsonEncode(frozenEventContext.toJson())) {
        throw StateError(
          'Matching pending identity conflicts with its attempt',
        );
      }
      return const _MatchingPendingRecovery.committed();
    }
    final pending = evidence.restoreMatching(
      sourceEvidenceId: sourceEvidenceId,
      occurredAtUtc: occurredAtUtc,
      sessionId: session.id,
      wordId: wordId,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      attemptNumber: pendingAttemptNumber,
      contentRevision: contentRevision,
      classification: classification,
      contexts: ResolvedLearningEvidenceContexts(
        evidenceContext: frozenEvidenceContext,
        eventContext: frozenEventContext,
      ),
      actorIdentity: actorIdentity,
    );
    return _MatchingPendingRecovery(
      pending: pending,
      feedbackContext: AnswerFeedbackContext(
        canonicalCorrectAnswer: canonicalCorrectAnswer,
      ).freeze(),
    );
  }

  DateTime? _optionalUtc(Object? value, String field) {
    if (value == null) return null;
    if (value is! String || !value.endsWith('Z')) {
      throw StateError('Matching checkpoint field $field is invalid');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || !parsed.isUtc) {
      throw StateError('Matching checkpoint field $field is invalid');
    }
    return parsed;
  }

  Map<String, Object?> _encodeCheckpointState(
    QuizSession session, {
    required DateTime? timeoutDeadlineUtc,
  }) => <String, Object?>{
    'schemaVersion': 5,
    'pairs': session.questions
        .map((question) => _encodeWord(question.word))
        .toList(growable: false),
    'pendingEvidence': null,
    'pendingCloseAtUtc': null,
    'timeoutRequested': false,
    'timingKind': timeoutDeadlineUtc == null ? 'activeEffort' : 'timed',
    'timeoutAnchorUtc': timeoutDeadlineUtc == null
        ? null
        : session.startedAtUtc!.toIso8601String(),
    'timeoutDurationMs': timeoutDeadlineUtc
        ?.difference(session.startedAtUtc!)
        .inMilliseconds,
    'timeoutDeadlineUtc': timeoutDeadlineUtc?.toIso8601String(),
    'summaryPresented': false,
  };

  _MatchingTimeoutContract _decodeTimeoutContract({
    required LearningActivityCheckpoint checkpoint,
    required DateTime startedAtUtc,
  }) {
    final schemaVersion = checkpoint.state['schemaVersion'];
    if (schemaVersion == 5 &&
        checkpoint.state['timingKind'] == 'activeEffort') {
      if (checkpoint.state['timeoutAnchorUtc'] != null ||
          checkpoint.state['timeoutDurationMs'] != null ||
          checkpoint.state['timeoutDeadlineUtc'] != null) {
        throw StateError('Matching active-effort timing is invalid');
      }
      return const _MatchingTimeoutContract(
        anchorUtc: null,
        duration: null,
        deadlineUtc: null,
        needsUpgrade: false,
      );
    }
    final hasPersistedDuration =
        schemaVersion == 3 || schemaVersion == 4 || schemaVersion == 5;
    final anchor = hasPersistedDuration
        ? _optionalUtc(checkpoint.state['timeoutAnchorUtc'], 'timeoutAnchorUtc')
        : startedAtUtc;
    final duration = schemaVersion == 1
        ? legacyV1CompatibilityTimeLimit
        : schemaVersion == 2
        ? (_optionalUtc(
                    checkpoint.state['timeoutDeadlineUtc'],
                    'timeoutDeadlineUtc',
                  ) ??
                  startedAtUtc)
              .difference(startedAtUtc)
        : hasPersistedDuration
        ? Duration(
            milliseconds: checkpoint.state['timeoutDurationMs'] is int
                ? checkpoint.state['timeoutDurationMs']! as int
                : -1,
          )
        : Duration.zero;
    final deadline = schemaVersion == 1
        ? startedAtUtc.add(duration)
        : _optionalUtc(
            checkpoint.state['timeoutDeadlineUtc'],
            'timeoutDeadlineUtc',
          );
    if (anchor == null ||
        anchor != startedAtUtc ||
        duration <= Duration.zero ||
        duration > const Duration(minutes: 30) ||
        deadline == null ||
        deadline != anchor.add(duration)) {
      throw StateError('Matching timeout deadline is invalid');
    }
    return _MatchingTimeoutContract(
      anchorUtc: anchor,
      duration: duration,
      deadlineUtc: deadline,
      needsUpgrade: schemaVersion != 5,
    );
  }

  QuizSession _decodeCheckpointSession(
    LearningActivityCheckpoint checkpoint,
    DateTime startedAtUtc,
    SessionConfiguration? sessionConfiguration,
  ) {
    final state = checkpoint.state;
    const v1Keys = <String>{
      'schemaVersion',
      'pairs',
      'pendingEvidence',
      'pendingCloseAtUtc',
      'timeoutRequested',
    };
    const v2Keys = <String>{...v1Keys, 'timeoutDeadlineUtc'};
    const v3Keys = <String>{...v2Keys, 'timeoutAnchorUtc', 'timeoutDurationMs'};
    const v4Keys = <String>{...v3Keys, 'summaryPresented'};
    const v5Keys = <String>{...v4Keys, 'timingKind'};
    final schemaVersion = state['schemaVersion'];
    final keys = schemaVersion == 1
        ? v1Keys
        : schemaVersion == 2
        ? v2Keys
        : schemaVersion == 3
        ? v3Keys
        : schemaVersion == 4
        ? v4Keys
        : v5Keys;
    if (checkpoint.activityType != activityType ||
        state.length != keys.length ||
        !state.keys.every(keys.contains) ||
        (schemaVersion != 1 &&
            schemaVersion != 2 &&
            schemaVersion != 3 &&
            schemaVersion != 4 &&
            schemaVersion != 5) ||
        state['pairs'] is! List<Object?> ||
        state['timeoutRequested'] is! bool ||
        ((schemaVersion == 4 || schemaVersion == 5) &&
            state['summaryPresented'] is! bool) ||
        (schemaVersion == 5 &&
            state['timingKind'] != 'timed' &&
            state['timingKind'] != 'activeEffort')) {
      throw StateError('Matching checkpoint schema is invalid');
    }
    final words = (state['pairs']! as List<Object?>).map(_decodeWord).toList();
    if (words.length < 2 || words.length > maximumPairs) {
      throw StateError('Matching checkpoint pair count is invalid');
    }
    return QuizSession(
      id: checkpoint.sessionId,
      startedAtUtc: startedAtUtc,
      sessionConfiguration: sessionConfiguration,
      questions: words
          .map((word) => QuizQuestion(word: word, options: const <String>[]))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeWord(QuizWord word) => <String, Object?>{
    'id': word.id,
    'categoryId': word.categoryId,
    'spelling': word.spelling,
    'meaning': word.meaning,
    'partOfSpeech': word.partOfSpeech,
    'normalizedSpelling': word.normalizedSpelling,
    'normalizedMeaning': word.normalizedMeaning,
    'contentRevision': word.contentRevision,
    'contentChecksumSha256': word.contentChecksumSha256,
  };

  QuizWord _decodeWord(Object? encoded) {
    if (encoded is! Map<String, Object?> || encoded.length != 9) {
      throw StateError('Matching checkpoint word schema is invalid');
    }
    T? optional<T>(String key) {
      final value = encoded[key];
      if (value == null) return null;
      if (value is! T) {
        throw StateError('Matching checkpoint word field $key is invalid');
      }
      return value as T;
    }

    String requiredString(String key) {
      final value = optional<String>(key);
      if (value == null || value.trim().isEmpty || value.runes.length > 512) {
        throw StateError('Matching checkpoint word field $key is invalid');
      }
      return value;
    }

    return QuizWord(
      id: requiredString('id'),
      categoryId: requiredString('categoryId'),
      spelling: requiredString('spelling'),
      meaning: requiredString('meaning'),
      partOfSpeech: requiredString('partOfSpeech'),
      normalizedSpelling: optional<String>('normalizedSpelling'),
      normalizedMeaning: optional<String>('normalizedMeaning'),
      contentRevision: optional<int>('contentRevision'),
      contentChecksumSha256: optional<String>('contentChecksumSha256'),
    );
  }

  String evidenceContentRevision(QuizWord word) {
    final revision = word.contentRevision;
    final checksum = word.contentChecksumSha256;
    if (revision != null &&
        revision > 0 &&
        checksum != null &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      return 'lexical-matching:v$revision:$checksum';
    }
    final snapshot = jsonEncode(_encodeWord(word));
    return 'lexical-matching:snapshot:${sha256.convert(utf8.encode(snapshot))}';
  }

  MatchingReviewController createReview({
    required QuizSession session,
    required LearningUseCases learning,
    required CurrentActivityEvidenceAdapter evidence,
    MatchingPreparedSession? recovery,
    MatchingSessionCompleter? completeSession,
    MatchingCloseOwner? ownClose,
    MatchingAdmittedOperation? runAdmittedOperation,
    MatchingRecoveryOperation? runRecoveryOperation,
    MatchingOperationAcceptance? acceptsOperation,
    MatchingHintUsage? hintUsage,
    MatchingHintReset? resetHintsAfterCommit,
  }) {
    if (session.isEmpty) {
      throw ArgumentError.value(session, 'session', 'must contain vocabulary');
    }
    if (!identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Matching evidence must use the session LearningUseCases authority.',
      );
    }
    final pairSet = pinPairs(session);
    if (pairSet.isEmpty) {
      throw ArgumentError.value(
        session,
        'session',
        'must contain at least two ambiguity-safe pairs',
      );
    }
    if (recovery != null &&
        (!identical(recovery.learning, learning) ||
            recovery.session.id != session.id)) {
      throw ArgumentError.value(
        recovery,
        'recovery',
        'must be prepared by this learning authority for the same session',
      );
    }
    return MatchingReviewController._(
      session: session,
      pairSet: pairSet,
      learning: learning,
      evidence: evidence,
      restoredMatchedWordIds: recovery?.matchedWordIds ?? const <String>{},
      initialAttemptNumber: recovery?.attemptNumber ?? 0,
      maximumAttemptNumber: recovery?.maximumAttemptNumber ?? maximumAttempts,
      contentRevisionFor: evidenceContentRevision,
      pendingEvidence: recovery?.pendingEvidence,
      pendingFeedbackContext: recovery?.pendingFeedbackContext,
      pendingWordId: recovery?.pendingWordId,
      pendingCorrect: recovery?.pendingCorrect ?? false,
      pendingClose: recovery?.pendingClose,
      completedSummary: recovery?.completedSummary,
      timeoutRequested: recovery?.timeoutRequested ?? false,
      persistPending: recovery == null
          ? null
          : ({
              required pending,
              required selectedMeaningWordId,
              required classification,
              required contentRevision,
              required canonicalCorrectAnswer,
              required contexts,
            }) => recovery.persistPending(
              pending: pending,
              selectedMeaningWordId: selectedMeaningWordId,
              classification: classification,
              contentRevision: contentRevision,
              canonicalCorrectAnswer: canonicalCorrectAnswer,
              contexts: contexts,
            ),
      clearPending: recovery?.clearPending,
      persistClose: recovery == null
          ? null
          : ({required close, required timeoutRequested}) => recovery
                .persistClose(close: close, timeoutRequested: timeoutRequested),
      acknowledgeClose: recovery?.acknowledgeClose,
      classifyResponse: classifyResponse,
      completeSession:
          completeSession ??
          (close) => close.requiresRetry ? close.retry() : close.finish(),
      ownClose: ownClose ?? (_, _) {},
      runAdmittedOperation:
          runAdmittedOperation ?? <T>(operation) => operation(),
      runRecoveryOperation:
          runRecoveryOperation ?? <T>(operation) => operation(),
      acceptsOperation: acceptsOperation ?? () => true,
      hintUsage: hintUsage ?? () => const HintUsageSnapshot.unknown(),
      resetHintsAfterCommit: resetHintsAfterCommit ?? () {},
    );
  }

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) {
    final context = support.evidenceContext;
    final valid =
        response.promptMode == 'matchingPair' &&
        context.skillId == 'matching-recognition' &&
        ((context.hintLevel == 0 &&
                context.evidenceClass == EvidenceClass.recognition) ||
            (context.hintLevel > 0 &&
                context.evidenceClass == EvidenceClass.guidedPractice));
    if (!valid) {
      throw StateError(
        'Matching must remain recognition or assisted guided practice.',
      );
    }
    return context;
  }

  @override
  Future<LessonItem> next(LessonCursor cursor) => Future<LessonItem>.error(
    StateError('MatchingReviewController owns the pinned pair set.'),
  );
}

final class MatchingReviewController extends ChangeNotifier {
  MatchingReviewController._({
    required this.session,
    required this.pairSet,
    required this._learning,
    required this._evidence,
    required Set<String> restoredMatchedWordIds,
    required int initialAttemptNumber,
    required this._maximumAttemptNumber,
    required this._contentRevisionFor,
    required PendingCurrentActivityEvidence? pendingEvidence,
    required this._pendingFeedbackContext,
    required this._pendingWordId,
    required this._pendingCorrect,
    required PendingLearningSessionClose? pendingClose,
    required LearningSessionSummary? completedSummary,
    required this._timeoutRequested,
    required _MatchingPendingPersister? persistPending,
    required Future<void> Function()? clearPending,
    required _MatchingClosePersister? persistClose,
    required _MatchingCloseAcknowledger? acknowledgeClose,
    required this._classifyResponse,
    required this._completeSession,
    required this._ownClose,
    required this._runAdmittedOperation,
    required this._runRecoveryOperation,
    required this._acceptsOperation,
    required this._hintUsage,
    required this._resetHintsAfterCommit,
  }) : _matchedWordIds = Set<String>.of(restoredMatchedWordIds),
       _attemptNumber = initialAttemptNumber,
       _pendingEvidence = pendingEvidence,
       _pendingCheckpointPersisted = pendingEvidence != null,
       _pendingClose = pendingClose,
       _completedSummary = completedSummary,
       _persistPending = persistPending ?? _noopPendingPersist,
       _clearPendingCheckpoint = clearPending ?? _noopCheckpoint,
       _persistClose = persistClose ?? _noopClosePersist,
       _acknowledgeClose = acknowledgeClose ?? _noopCloseAcknowledge {
    if (completedSummary != null) {
      _phase = MatchingReviewPhase.completed;
      _acceptingSelections = false;
      _closeCheckpointed = true;
    } else if (pendingEvidence != null) {
      _phase = MatchingReviewPhase.evidenceRetryRequired;
    } else if (pendingClose != null) {
      _phase = MatchingReviewPhase.completionRetryRequired;
      _acceptingSelections = false;
      _closeCheckpointed = true;
      _ownClose(pendingClose, _ensureCloseCheckpoint);
    } else if (_attemptNumber >= _maximumAttemptNumber && !allMatched) {
      _timeoutRequested = true;
      _acceptingSelections = false;
    }
  }

  final QuizSession session;
  final MatchingPairSet pairSet;
  final LearningUseCases _learning;
  final CurrentActivityEvidenceAdapter _evidence;
  final HintEvidenceClassification Function({
    required HintUsageSnapshot hint,
    required bool supportUsed,
  })
  _classifyResponse;
  final MatchingSessionCompleter _completeSession;
  final MatchingCloseOwner _ownClose;
  final MatchingAdmittedOperation _runAdmittedOperation;
  final MatchingRecoveryOperation _runRecoveryOperation;
  final MatchingOperationAcceptance _acceptsOperation;
  final MatchingHintUsage _hintUsage;
  final MatchingHintReset _resetHintsAfterCommit;
  final String Function(QuizWord word) _contentRevisionFor;
  final _MatchingPendingPersister _persistPending;
  final Future<void> Function() _clearPendingCheckpoint;
  final _MatchingClosePersister _persistClose;
  final _MatchingCloseAcknowledger _acknowledgeClose;
  final Set<String> _matchedWordIds;

  MatchingReviewPhase _phase = MatchingReviewPhase.awaitingSelection;
  String? _selectedWordId;
  String? _selectedMeaningWordId;
  bool _supportUsed = false;
  bool _acceptingSelections = true;
  bool _disposed = false;
  int _attemptNumber;
  final int _maximumAttemptNumber;
  PendingCurrentActivityEvidence? _pendingEvidence;
  FrozenAnswerFeedbackContext? _pendingFeedbackContext;
  String? _pendingWordId;
  bool _pendingCorrect;
  bool _pendingCheckpointPersisted;
  String? _pendingSelectedMeaningWordId;
  HintEvidenceClassification? _pendingClassification;
  String? _pendingContentRevision;
  Future<AnswerRecordResult?>? _resolutionInFlight;
  PendingLearningSessionClose? _pendingClose;
  LearningSessionSummary? _completedSummary;
  bool _closeCheckpointed = false;
  Future<LearningSessionSummary>? _terminalInFlight;
  AnswerFeedback? _feedback;
  bool _timeoutRequested;

  MatchingReviewPhase get phase => _phase;
  Set<String> get matchedWordIds => Set<String>.unmodifiable(_matchedWordIds);
  int get remainingPairCount => pairSet.pairs.length - _matchedWordIds.length;
  String? get selectedWordId => _selectedWordId;
  String? get selectedMeaningWordId => _selectedMeaningWordId;
  AnswerFeedback? get feedback => _feedback;
  bool get allMatched => remainingPairCount == 0;
  bool get timeoutRequested => _timeoutRequested;
  LearningSessionSummary? get completedSummary => _completedSummary;
  int get nextAttemptNumber => _attemptNumber + 1;
  bool get persistenceLocked =>
      _resolutionInFlight != null ||
      _pendingEvidence != null ||
      _pendingClose != null ||
      _phase == MatchingReviewPhase.savingEvidence ||
      _phase == MatchingReviewPhase.evidenceRetryRequired ||
      _phase == MatchingReviewPhase.completing ||
      _phase == MatchingReviewPhase.completionRetryRequired;
  bool get actionLocked =>
      !_acceptingSelections ||
      !_acceptsOperation() ||
      _phase != MatchingReviewPhase.awaitingSelection;

  void markSupportUsed() {
    _requireSelectionAccepted();
    if (_supportUsed) return;
    _supportUsed = true;
    notifyListeners();
  }

  Future<AnswerRecordResult?> selectWord(
    String wordId, {
    required int responseTimeMs,
  }) =>
      _select(wordId: wordId, isWordSide: true, responseTimeMs: responseTimeMs);

  Future<AnswerRecordResult?> selectMeaning(
    String wordId, {
    required int responseTimeMs,
  }) => _select(
    wordId: wordId,
    isWordSide: false,
    responseTimeMs: responseTimeMs,
  );

  Future<AnswerRecordResult?> _select({
    required String wordId,
    required bool isWordSide,
    required int responseTimeMs,
  }) {
    final inFlight = _resolutionInFlight;
    if (inFlight != null &&
        ((isWordSide && _selectedWordId == wordId) ||
            (!isWordSide && _selectedMeaningWordId == wordId))) {
      return Future<AnswerRecordResult?>.value(inFlight);
    }
    _requireSelectionAccepted();
    if (responseTimeMs < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must not be negative',
      );
    }
    if (!pairSet.pairs.any((pair) => pair.word.id == wordId)) {
      throw ArgumentError.value(wordId, 'wordId', 'is not a pinned pair');
    }
    if (_matchedWordIds.contains(wordId)) {
      return Future<AnswerRecordResult?>.value();
    }
    final selected = isWordSide ? _selectedWordId : _selectedMeaningWordId;
    if (selected == wordId) return Future<AnswerRecordResult?>.value();
    return _runAdmittedOperation(
      () => _selectAdmitted(
        wordId: wordId,
        isWordSide: isWordSide,
        responseTimeMs: responseTimeMs,
      ),
    );
  }

  Future<AnswerRecordResult?> _selectAdmitted({
    required String wordId,
    required bool isWordSide,
    required int responseTimeMs,
  }) {
    final admittedInFlight = _resolutionInFlight;
    if (admittedInFlight != null &&
        ((isWordSide && _selectedWordId == wordId) ||
            (!isWordSide && _selectedMeaningWordId == wordId))) {
      return admittedInFlight;
    }
    _requireAcceptedSelectionState();
    if (_matchedWordIds.contains(wordId)) {
      return Future<AnswerRecordResult?>.value();
    }
    final admittedSelection = isWordSide
        ? _selectedWordId
        : _selectedMeaningWordId;
    if (admittedSelection == wordId) {
      return Future<AnswerRecordResult?>.value();
    }
    if (isWordSide) {
      _selectedWordId = wordId;
    } else {
      _selectedMeaningWordId = wordId;
    }
    notifyListeners();
    final selectedWordId = _selectedWordId;
    final selectedMeaningWordId = _selectedMeaningWordId;
    if (selectedWordId == null || selectedMeaningWordId == null) {
      return Future<AnswerRecordResult?>.value();
    }
    return _beginResolution(
      selectedWordId: selectedWordId,
      selectedMeaningWordId: selectedMeaningWordId,
      responseTimeMs: responseTimeMs,
    );
  }

  Future<AnswerRecordResult?> _beginResolution({
    required String selectedWordId,
    required String selectedMeaningWordId,
    required int responseTimeMs,
  }) {
    if (_attemptNumber >= _maximumAttemptNumber) {
      _timeoutRequested = true;
      _acceptingSelections = false;
      notifyListeners();
      return Future<AnswerRecordResult?>.error(
        StateError('Matching attempt budget is exhausted.'),
      );
    }
    final correct = selectedWordId == selectedMeaningWordId;
    final pair = pairSet.pairs.singleWhere(
      (candidate) => candidate.word.id == selectedWordId,
    );
    final feedbackContext = AnswerFeedbackContext(
      canonicalCorrectAnswer: pair.meaningLabel,
    ).freeze();
    final classification = _classifyResponse(
      hint: _hintUsage(),
      supportUsed: _supportUsed,
    );
    final nextAttempt = _attemptNumber + 1;
    final contentRevision = _contentRevisionFor(pair.word);
    final pending = _evidence.captureMatching(
      sessionId: session.id,
      wordId: selectedWordId,
      isCorrect: correct,
      responseTimeMs: responseTimeMs,
      attemptNumber: nextAttempt,
      contentRevision: contentRevision,
      classification: classification,
    );
    _attemptNumber = nextAttempt;
    _pendingEvidence = pending;
    _pendingFeedbackContext = feedbackContext;
    _pendingWordId = selectedWordId;
    _pendingCorrect = correct;
    _pendingCheckpointPersisted = false;
    _pendingSelectedMeaningWordId = selectedMeaningWordId;
    _pendingClassification = classification;
    _pendingContentRevision = contentRevision;
    _setPhase(MatchingReviewPhase.savingEvidence);
    final operation = _persistAndCommitEvidence(
      pending: pending,
      feedbackContext: feedbackContext,
      selectedMeaningWordId: selectedMeaningWordId,
      classification: classification,
      contentRevision: contentRevision,
    );
    _resolutionInFlight = operation;
    unawaited(
      operation.then<void>(
        (_) => _clearResolution(operation),
        onError: (Object _, StackTrace _) => _clearResolution(operation),
      ),
    );
    return operation;
  }

  Future<AnswerRecordResult?> _persistAndCommitEvidence({
    required PendingCurrentActivityEvidence pending,
    required FrozenAnswerFeedbackContext feedbackContext,
    required String selectedMeaningWordId,
    required HintEvidenceClassification classification,
    required String contentRevision,
  }) async {
    try {
      final contexts = await pending.freezeContexts();
      await _persistPending(
        pending: pending,
        selectedMeaningWordId: selectedMeaningWordId,
        classification: classification,
        contentRevision: contentRevision,
        canonicalCorrectAnswer: feedbackContext.canonicalCorrectAnswer,
        contexts: contexts,
      );
      _pendingCheckpointPersisted = true;
    } catch (_) {
      _setPhase(MatchingReviewPhase.evidenceRetryRequired);
      rethrow;
    }
    return _commitEvidence(pending, feedbackContext, retry: false);
  }

  void _clearResolution(Future<AnswerRecordResult?> operation) {
    if (identical(_resolutionInFlight, operation)) {
      _resolutionInFlight = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<AnswerRecordResult?> retryEvidence() {
    _requireNotDisposed();
    if (_phase != MatchingReviewPhase.evidenceRetryRequired) {
      return Future<AnswerRecordResult?>.error(
        StateError('Exact matching evidence retry is unavailable.'),
      );
    }
    final pending = _pendingEvidence;
    final feedbackContext = _pendingFeedbackContext;
    if (pending == null || feedbackContext == null) {
      return Future<AnswerRecordResult?>.error(
        StateError('Exact matching evidence retry is unavailable.'),
      );
    }
    final operation = _runRecoveryOperation(() {
      _setPhase(MatchingReviewPhase.savingEvidence);
      if (_pendingCheckpointPersisted) {
        return _commitEvidence(
          pending,
          feedbackContext,
          retry: pending.requiresRetry,
        );
      }
      final selectedMeaningWordId = _pendingSelectedMeaningWordId;
      final classification = _pendingClassification;
      final contentRevision = _pendingContentRevision;
      if (selectedMeaningWordId == null ||
          classification == null ||
          contentRevision == null) {
        return Future<AnswerRecordResult?>.error(
          StateError('Exact matching checkpoint retry is unavailable.'),
        );
      }
      return _persistAndCommitEvidence(
        pending: pending,
        feedbackContext: feedbackContext,
        selectedMeaningWordId: selectedMeaningWordId,
        classification: classification,
        contentRevision: contentRevision,
      );
    });
    _resolutionInFlight = operation;
    unawaited(
      operation.then<void>(
        (_) => _clearResolution(operation),
        onError: (Object _, StackTrace _) => _clearResolution(operation),
      ),
    );
    return operation;
  }

  Future<AnswerRecordResult?> _commitEvidence(
    PendingCurrentActivityEvidence pending,
    FrozenAnswerFeedbackContext feedbackContext, {
    required bool retry,
  }) async {
    try {
      final result = await (retry ? pending.retry() : pending.record());
      final feedback = AnswerFeedback.fromFrozenCommittedResult(
        result: result,
        context: feedbackContext,
      );
      await _clearPendingCheckpoint();
      if (_pendingCorrect) _matchedWordIds.add(_pendingWordId!);
      _feedback = feedback;
      _pendingEvidence = null;
      _pendingFeedbackContext = null;
      _pendingWordId = null;
      _pendingCorrect = false;
      _pendingCheckpointPersisted = false;
      _pendingSelectedMeaningWordId = null;
      _pendingClassification = null;
      _pendingContentRevision = null;
      _selectedWordId = null;
      _selectedMeaningWordId = null;
      _supportUsed = false;
      try {
        _resetHintsAfterCommit();
      } on Object {
        // Durable evidence and presentation state are already committed.
      }
      if (_attemptNumber >= _maximumAttemptNumber && !allMatched) {
        _timeoutRequested = true;
        _acceptingSelections = false;
      }
      _setPhase(MatchingReviewPhase.awaitingSelection);
      return result;
    } catch (_) {
      _setPhase(MatchingReviewPhase.evidenceRetryRequired);
      rethrow;
    }
  }

  Future<LearningSessionSummary> finish() {
    final completed = _completedSummary;
    if (completed != null) {
      return Future<LearningSessionSummary>.value(completed);
    }
    final existing = _terminalInFlight;
    if (existing != null) return existing;
    _requireSelectionAccepted();
    if (!allMatched) {
      return Future<LearningSessionSummary>.error(
        StateError('All matching pairs must be resolved before finish.'),
      );
    }
    _acceptingSelections = false;
    return _terminalInFlight = _complete();
  }

  Future<LearningSessionSummary> timeout() {
    _requireNotDisposed();
    final completed = _completedSummary;
    if (completed != null) {
      return Future<LearningSessionSummary>.value(completed);
    }
    final existing = _terminalInFlight;
    if (existing != null) return existing;
    final terminal = _runRecoveryOperation(_timeoutRecovery);
    _terminalInFlight = terminal;
    unawaited(
      terminal.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_terminalInFlight, terminal)) {
            _terminalInFlight = null;
          }
        },
      ),
    );
    return terminal;
  }

  Future<LearningSessionSummary> _timeoutRecovery() {
    _timeoutRequested = true;
    _acceptingSelections = false;
    final resolution = _resolutionInFlight;
    if (resolution != null) {
      return resolution.then<LearningSessionSummary>(
        (_) => _completeRecovery(),
      );
    }
    if (_pendingEvidence != null) {
      return Future<LearningSessionSummary>.error(
        StateError('Retry the exact accepted match before timeout closes.'),
      );
    }
    return _completeRecovery();
  }

  Future<LearningSessionSummary> retryCompletion() {
    _requireNotDisposed();
    if (_phase != MatchingReviewPhase.completionRetryRequired) {
      return Future<LearningSessionSummary>.error(
        StateError('Exact matching completion retry is unavailable.'),
      );
    }
    return _terminalInFlight = _complete();
  }

  Future<LearningSessionSummary> _complete() =>
      _runRecoveryOperation(_completeRecovery);

  Future<LearningSessionSummary> _completeRecovery() async {
    final close = _pendingClose ??= _learning.captureSessionClose(
      sessionId: session.id,
    );
    _ownClose(close, _ensureCloseCheckpoint);
    _setPhase(MatchingReviewPhase.completing);
    try {
      await _ensureCloseCheckpoint();
      final summary = await _completeSession(close);
      await _acknowledgeClose(summary);
      _completedSummary = summary;
      _pendingClose = null;
      _setPhase(MatchingReviewPhase.completed);
      return summary;
    } catch (_) {
      _terminalInFlight = null;
      _setPhase(MatchingReviewPhase.completionRetryRequired);
      rethrow;
    }
  }

  Future<void> _ensureCloseCheckpoint() async {
    if (_closeCheckpointed) return;
    final close = _pendingClose;
    if (close == null) {
      throw StateError('Matching terminal close identity is unavailable.');
    }
    await _persistClose(close: close, timeoutRequested: _timeoutRequested);
    _closeCheckpointed = true;
  }

  void _requireSelectionAccepted() {
    _requireNotDisposed();
    if (!_acceptingSelections || !_acceptsOperation()) {
      throw StateError('The matching route is no longer accepting actions.');
    }
    if (_phase != MatchingReviewPhase.awaitingSelection) {
      throw StateError('Matching selection is unavailable in ${_phase.name}.');
    }
  }

  void _requireAcceptedSelectionState() {
    if (!_acceptingSelections ||
        _phase != MatchingReviewPhase.awaitingSelection) {
      throw StateError('Matching selection is no longer available.');
    }
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('Matching review is disposed.');
  }

  void _setPhase(MatchingReviewPhase next) {
    _phase = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _spellingKey(QuizWord word) =>
    normalizeVocabularyText(word.normalizedSpelling ?? word.spelling);

String _meaningKey(QuizWord word) =>
    normalizeVocabularyText(word.normalizedMeaning ?? word.meaning);

String _canonicalDisplay(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

int _stableCompare(String left, String right) {
  final byHash = _stableSeed(left).compareTo(_stableSeed(right));
  return byHash == 0 ? left.compareTo(right) : byHash;
}

int _stableSeed(String value) => value.codeUnits.fold<int>(
  17,
  (hash, unit) => ((hash * 31) + unit) & 0x7fffffff,
);
