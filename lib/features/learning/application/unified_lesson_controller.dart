import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../../time_tracking/application/active_learning_time_controller.dart';
import '../../time_tracking/application/focus_timer_controller.dart';
import '../../time_tracking/domain/focus_timer.dart';
import '../../time_tracking/domain/learning_time_segment.dart';
import '../../../runtime/registries/feature.dart';
import '../domain/answer_feedback.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_models.dart';
import '../domain/lesson_mode.dart';
import '../domain/lesson_session_state.dart';
import '../domain/session_configuration.dart';
import 'hint_use_cases.dart';
import 'learning_use_cases.dart';

typedef UnifiedLessonControllerFactory =
    UnifiedLessonController Function(LessonModeAdapter adapter);
typedef SessionConfigurationRevalidator =
    Future<SessionConfiguration> Function(SessionConfiguration configuration);
typedef SessionConfigurationMonotonicMicros = int Function();

/// Route-owned terminal occurrence captured when operation acceptance closes.
/// Its private authority prevents a later wall/monotonic observation or a
/// different lesson controller from extending the trusted cutoff.
final class LessonTerminalCutoff {
  LessonTerminalCutoff._({
    required this.authority,
    required this.occurredAtUtc,
    required this.timeOccurrence,
    required this.configurationMonotonicMicros,
    required this.configurationSessionAttached,
  });

  final Object authority;
  final DateTime occurredAtUtc;
  final LearningTimeObservation? timeOccurrence;
  final int? configurationMonotonicMicros;
  final bool configurationSessionAttached;
  int? configurationEffortTargetMicros;
  Future<void>? configurationClose;
}

final class UnifiedLessonController extends ChangeNotifier {
  factory UnifiedLessonController({
    required LearningUseCases learning,
    required LessonModeAdapter adapter,
    HintUseCases? hints,
    ActiveLearningTimeController? activeLearningTime,
    FocusTimerController? focusTimer,
    Feature? focusTimerFeature,
    SessionConfigurationMonotonicMicros? configurationMonotonicMicros,
    Duration configurationIdleTimeout = const Duration(minutes: 5),
  }) {
    final hintAdapter = adapter is HintSupportingLessonModeAdapter
        ? adapter
        : null;
    if (hintAdapter == null && hints != null) {
      throw ArgumentError.value(
        hints,
        'hints',
        'requires a hint-supporting lesson mode adapter',
      );
    }
    if (hintAdapter != null &&
        hints != null &&
        hints.policy != hintAdapter.hintPolicy) {
      throw ArgumentError.value(
        hints.policy,
        'hints',
        'must use the policy declared by the lesson mode adapter',
      );
    }
    final resolvedHints = hintAdapter == null
        ? null
        : hints ?? HintUseCases(policy: hintAdapter.hintPolicy);
    if (activeLearningTime != null &&
        adapter is! TrustworthyActiveEffortLessonModeAdapter) {
      throw ArgumentError.value(
        adapter,
        'adapter',
        'active learning time requires a trustworthy-effort adapter',
      );
    }
    if ((focusTimer == null) != (focusTimerFeature == null)) {
      throw ArgumentError(
        'focusTimer and focusTimerFeature must be composed together',
      );
    }
    if (configurationIdleTimeout <= Duration.zero ||
        configurationIdleTimeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        configurationIdleTimeout,
        'configurationIdleTimeout',
        'must be positive and no longer than five minutes',
      );
    }
    if (focusTimer != null &&
        (adapter is! FocusTimerSupportingLessonModeAdapter ||
            activeLearningTime == null ||
            !identical(focusTimer.timeAuthority, activeLearningTime))) {
      throw ArgumentError.value(
        focusTimer,
        'focusTimer',
        'requires a capable adapter and the exact lesson time authority',
      );
    }
    return UnifiedLessonController._(
      learning,
      adapter,
      resolvedHints,
      activeLearningTime,
      focusTimer,
      focusTimerFeature,
      configurationMonotonicMicros ?? _SystemSessionMonotonicClock().read,
      configurationIdleTimeout,
    );
  }

  UnifiedLessonController._(
    this._learning,
    this._adapter,
    this._hints,
    this._activeLearningTime,
    this._focusTimer,
    this._focusTimerFeature,
    this._configurationMonotonicMicros,
    this._configurationIdleTimeout,
  ) : _state = LessonSessionState.planned(_adapter.mode);

  final LearningUseCases _learning;
  final LessonModeAdapter _adapter;
  final HintUseCases? _hints;
  final ActiveLearningTimeController? _activeLearningTime;
  final FocusTimerController? _focusTimer;
  final Feature? _focusTimerFeature;
  final SessionConfigurationMonotonicMicros _configurationMonotonicMicros;
  final Duration _configurationIdleTimeout;
  LessonSessionState _state;
  AnswerFeedback? _feedback;
  final Map<String, _PendingSubmission> _submissions =
      <String, _PendingSubmission>{};
  PendingLearningSessionClose? _pendingClose;
  Future<void>? _pauseInFlight;
  Future<void>? _completionInFlight;
  Future<LearningSessionSummary>? _capturedCompletionInFlight;
  Future<void>? _abandonInFlight;
  PendingLearningSessionClose? _terminalClosePending;
  Future<void> _mutationTail = Future<void>.value();
  bool _disposed = false;
  bool _focusTimerGateEnabled = true;
  Object? _lastActiveLearningTimeFailure;
  final Object _terminalCutoffAuthority = Object();
  SessionConfiguration? _sessionConfiguration;
  SessionConfigurationRevalidator? _configurationRevalidator;
  SessionConfigurationResetRequired? _configurationResetRequired;
  Timer? _configurationLimitTimer;
  int _configurationLimitTimerGeneration = 0;
  int _configurationEffortGeneration = 0;
  int _configurationConsumedMicros = 0;
  int? _configurationActiveAnchorMicros;
  Future<void>? _configurationTerminalClose;
  bool _configurationLimitReached = false;
  bool _configurationIdle = false;

  LessonSessionState get state => _state;
  SessionConfiguration? get sessionConfiguration => _sessionConfiguration;
  SessionConfigurationResetRequired? get configurationResetRequired =>
      _configurationResetRequired;
  bool get configurationLimitReached => _configurationLimitReached;
  Duration get configurationActiveEffort =>
      Duration(microseconds: _configurationConsumedMicros);
  bool get configurationIsIdle => _configurationIdle;
  bool get configurationAcceptsOperations =>
      !_disposed && !_configurationLimitReached;
  AnswerFeedback? get feedback => _feedback;
  HintState? get hintState => _hints?.state;
  HintUsageSnapshot snapshotHintUsageForAcceptedEvidence() {
    _requireNotDisposed();
    return _hints?.snapshot() ?? const HintUsageSnapshot.unknown();
  }

  void resetHintsAfterAcceptedEvidence() {
    _requireNotDisposed();
    final hints = _hints;
    if (hints == null) return;
    hints.resetAfterCommittedEvidence();
    if (!_disposed) notifyListeners();
  }

  ActiveLearningTimeController? get activeLearningTime => _activeLearningTime;
  FocusTimerController? get focusTimer => _focusTimer;
  Feature? get focusTimerFeature => _focusTimerFeature;
  Object? get lastActiveLearningTimeFailure => _lastActiveLearningTimeFailure;
  bool get sessionCompletionRetryRequired => _terminalClosePending != null;
  bool get terminalMutationInFlight =>
      _completionInFlight != null ||
      _capturedCompletionInFlight != null ||
      _abandonInFlight != null ||
      _terminalClosePending != null;
  bool get canRevealHint {
    final hint = _hints?.state;
    final configuredBudget = _sessionConfiguration?.hintBudget;
    return !_disposed &&
        hint != null &&
        hint.availability == HintAvailability.available &&
        !hint.isExhausted &&
        (configuredBudget == null || hint.hintLevel < configuredBudget) &&
        _state.status == LessonSessionStatus.active &&
        _pauseInFlight == null &&
        _completionInFlight == null &&
        _capturedCompletionInFlight == null &&
        _abandonInFlight == null &&
        _terminalClosePending == null &&
        !_configurationLimitReached &&
        !_hasUncommittedSubmission;
  }

  HintRevealResult revealNextHint() {
    _requireNotDisposed();
    _requireConfigurationEffortAvailable();
    if (_pauseInFlight != null) {
      throw StateError('Cannot reveal a hint while pause is pending.');
    }
    _requireNoTerminalMutation('reveal a hint');
    _requireStatus(LessonSessionStatus.active, 'reveal a hint');
    _requireNoUncommittedSubmission('reveal a hint');
    final hints = _hints;
    if (hints == null) {
      throw StateError('Hints are unavailable for this lesson mode.');
    }
    final configuredBudget = _sessionConfiguration?.hintBudget;
    if (configuredBudget != null && hints.state.hintLevel >= configuredBudget) {
      throw StateError('The validated session hint budget is exhausted.');
    }
    final result = hints.revealNext();
    if (result.changed && !_disposed) notifyListeners();
    return result;
  }

  void bindSessionConfiguration(
    SessionConfiguration configuration, {
    required SessionConfigurationRevalidator revalidate,
  }) {
    _requireNotDisposed();
    _requireStatus(LessonSessionStatus.planned, 'bind session configuration');
    if (configuration.mode != _adapter.mode) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.modeDrift,
      );
    }
    final existing = _sessionConfiguration;
    if (existing != null && existing != configuration) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    _sessionConfiguration = configuration;
    _configurationRevalidator = revalidate;
    _configurationResetRequired = null;
  }

  Future<void> start(LessonStartCommand command) {
    if (_disposed) return _disposedError<void>();
    return _serialize<void>(() async {
      _requireStatus(LessonSessionStatus.planned, 'start');
      if (command.mode != _adapter.mode) {
        throw StateError('Lesson mode does not match the resolved adapter.');
      }
      await _revalidateStartConfiguration(command.configuration);
      final sessionId = _required(command.sessionId, 'sessionId');
      final startedAtUtc = _requiredUtc(command.startedAtUtc, 'startedAtUtc');
      if (command.itemCount < 0) {
        throw ArgumentError.value(
          command.itemCount,
          'itemCount',
          'must be nonnegative',
        );
      }
      final configuration = _sessionConfiguration;
      if (configuration != null &&
          command.itemCount != configuration.itemCount) {
        final error = const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
          'loaded item count differs from the validated configuration',
        );
        _configurationResetRequired = error;
        _notifyAvailabilityChanged();
        throw error;
      }
      var restoredConfigurationEffort = Duration.zero;
      var completedConfigurationRecovery = false;
      if (configuration != null) {
        try {
          final durable = await _learning.loadSessionConfigurationState(
            sessionId,
          );
          if (durable == null ||
              durable.sessionConfiguration != configuration) {
            throw const SessionConfigurationResetRequired(
              SessionConfigurationResetReason.tampered,
              'durable learning session has a different configuration',
            );
          }
          restoredConfigurationEffort = durable.configurationActiveEffort;
          if (restoredConfigurationEffort.isNegative) {
            throw const SessionConfigurationResetRequired(
              SessionConfigurationResetReason.tampered,
              'durable active effort is invalid',
            );
          }
          switch (durable.state) {
            case 'active':
              if (durable.endedAtUtc != null) {
                throw const SessionConfigurationResetRequired(
                  SessionConfigurationResetReason.tampered,
                  'active durable session has a terminal occurrence',
                );
              }
              break;
            case 'completed':
              if (durable.endedAtUtc == null) {
                throw const SessionConfigurationResetRequired(
                  SessionConfigurationResetReason.tampered,
                  'completed durable session has no terminal occurrence',
                );
              }
              completedConfigurationRecovery = true;
              break;
            default:
              throw const SessionConfigurationResetRequired(
                SessionConfigurationResetReason.tampered,
                'durable session is not startable',
              );
          }
        } on SessionConfigurationResetRequired catch (error) {
          _configurationResetRequired = error;
          _notifyAvailabilityChanged();
          rethrow;
        } catch (_) {
          final error = const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.tampered,
            'durable session configuration authority is unavailable',
          );
          _configurationResetRequired = error;
          _notifyAvailabilityChanged();
          throw error;
        }
      }
      final activeTime = _activeLearningTime;
      if (activeTime != null) {
        try {
          await activeTime.start(
            sessionId: sessionId,
            occurredAtUtc: startedAtUtc,
          );
          _focusTimer?.attachSession(sessionId);
          _lastActiveLearningTimeFailure = null;
        } catch (error) {
          // Time capture is an isolated measurement projection. A local time
          // failure must fail closed without orphaning the durable lesson.
          _lastActiveLearningTimeFailure = error;
        }
      }
      _setState(
        LessonSessionState(
          mode: _adapter.mode,
          status: LessonSessionStatus.active,
          sessionId: sessionId,
          startedAtUtc: startedAtUtc,
          lastTransitionAtUtc: startedAtUtc,
          itemCount: command.itemCount,
        ),
      );
      if (completedConfigurationRecovery) {
        _restoreConfigurationEffortForTerminalReconciliation(
          restoredConfigurationEffort,
        );
      } else {
        _beginConfigurationEffort(restoredConfigurationEffort);
      }
    });
  }

  Future<void> _revalidateStartConfiguration(
    SessionConfiguration? commandConfiguration,
  ) async {
    final bound = _sessionConfiguration;
    final revalidate = _configurationRevalidator;
    if (bound == null && commandConfiguration == null) return;
    if (bound == null ||
        revalidate == null ||
        commandConfiguration == null ||
        commandConfiguration != bound) {
      final error = const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
      _configurationResetRequired = error;
      _notifyAvailabilityChanged();
      throw error;
    }
    try {
      final refreshed = await revalidate(bound);
      if (refreshed != bound) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
        );
      }
      _configurationResetRequired = null;
    } on SessionConfigurationResetRequired catch (error) {
      _configurationResetRequired = error;
      _notifyAvailabilityChanged();
      rethrow;
    }
  }

  Future<void> pause(DateTime occurredAtUtc, {bool processBackground = false}) {
    try {
      _requireNotDisposed();
      final occurredAt = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
      final inFlight = _pauseInFlight;
      if (inFlight != null) return inFlight;
      _requireNoTerminalMutation('pause');
      final activeTime = _activeLearningTime;
      final timeOccurrence =
          activeTime != null &&
              activeTime.state != ActiveLearningTimeState.inactive
          ? activeTime.observe(occurredAt)
          : null;
      late final Future<void> future;
      future =
          _serialize<void>(() async {
            _requireStatus(LessonSessionStatus.active, 'pause');
            if (activeTime != null && timeOccurrence != null) {
              final focusTimer = _focusTimer;
              if (focusTimer != null) {
                await focusTimer.supersedeFailedEntryObserved(
                  timeOccurrence,
                  pauseReason: processBackground
                      ? FocusTimerPauseReason.processBackground
                      : FocusTimerPauseReason.explicit,
                );
                if (focusTimer.snapshot.status == FocusTimerStatus.running) {
                  if (processBackground) {
                    await focusTimer.pauseForBackgroundObserved(timeOccurrence);
                  } else {
                    await focusTimer.pauseObserved(timeOccurrence);
                  }
                }
              }
              await activeTime.pauseObserved(timeOccurrence);
            }
            await _pauseConfigurationEffort();
            _transition(LessonSessionStatus.paused, occurredAt);
          }).whenComplete(() {
            if (identical(_pauseInFlight, future)) {
              _pauseInFlight = null;
              _notifyAvailabilityChanged();
            }
          });
      _pauseInFlight = future;
      _notifyAvailabilityChanged();
      return future;
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> resume(DateTime occurredAtUtc) {
    try {
      _requireNotDisposed();
      final occurredAt = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
      _requireNoTerminalMutation('resume');
      final activeTime = _activeLearningTime;
      final timeOccurrence =
          activeTime != null &&
              activeTime.state != ActiveLearningTimeState.inactive
          ? activeTime.observe(occurredAt)
          : null;
      return _serialize<void>(() async {
        _requireStatus(LessonSessionStatus.paused, 'resume');
        if (activeTime != null && timeOccurrence != null) {
          await activeTime.resumeObserved(timeOccurrence);
        }
        _transition(LessonSessionStatus.active, occurredAt);
        _resumeConfigurationEffort();
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<AnswerRecordResult> submit(LessonSubmission submission) {
    try {
      _requireNotDisposed();
      _requireNoTerminalMutation('submit');
      final response = submission.response;
      final evidenceId = _required(
        response.sourceEvidenceId,
        'sourceEvidenceId',
      );
      _required(response.wordId, 'wordId');
      _required(response.promptMode, 'promptMode');
      _requiredUtc(response.occurredAtUtc, 'occurredAtUtc');
      if (response.attemptNumber < 1) {
        throw ArgumentError.value(
          response.attemptNumber,
          'attemptNumber',
          'must be positive',
        );
      }
      final responseTimeMs = response.responseTimeMs;
      if (responseTimeMs != null && responseTimeMs < 0) {
        throw ArgumentError.value(
          responseTimeMs,
          'responseTimeMs',
          'must be nonnegative',
        );
      }
      submission.support.evidenceContext.validate();
      final feedbackContext = submission.response.feedbackContext.normalized();
      final bookmarkIdentity = feedbackContext.bookmarkIdentity;
      if (bookmarkIdentity != null &&
          (bookmarkIdentity.type != ContentType.lexicalMetadata ||
              bookmarkIdentity.id != response.wordId)) {
        throw ArgumentError.value(
          bookmarkIdentity,
          'feedbackContext.bookmarkIdentity',
          'must be the submitted lexical content identity',
        );
      }
      final intentFingerprint = _SubmissionIntentFingerprint.from(
        submission,
        feedbackContext: feedbackContext,
      );
      final existing = _submissions[evidenceId];
      if (existing != null) {
        if (existing.intentFingerprint != intentFingerprint ||
            existing.fingerprint !=
                _SubmissionFingerprint.from(
                  submission,
                  feedbackContext: feedbackContext,
                  evidenceContext: existing.evidenceContext,
                )) {
          throw StateError(
            'Evidence identity $evidenceId was reused with different semantics.',
          );
        }
        final result = existing.result;
        if (result != null) return Future<AnswerRecordResult>.value(result);
        final inFlight = existing.inFlight;
        if (inFlight != null) return inFlight;
        return _startSubmission(existing, submission.response);
      }
      _requireConfigurationEffortAvailable();
      _requireNoUncommittedSubmission('submit new evidence');
      final classifiedEvidence = _adapter.classify(
        submission.response,
        submission.support,
      );
      classifiedEvidence.validate();
      if (_activeLearningTime != null &&
          !EvidenceProjectionDecision.resolve(
            context: classifiedEvidence,
            projection: LearningProjection.activeLearningEffort,
          ).isEligible) {
        throw StateError(
          'Trustworthy active-effort adapter produced ineligible evidence.',
        );
      }
      final hints = _hints;
      final evidenceContext =
          _adapter is HintSupportingLessonModeAdapter && hints != null
          ? HintPolicy.applyToEvidence(classifiedEvidence, hints.snapshot())
          : classifiedEvidence;
      final pending = _PendingSubmission(
        intentFingerprint: intentFingerprint,
        fingerprint: _SubmissionFingerprint.from(
          submission,
          feedbackContext: feedbackContext,
          evidenceContext: evidenceContext,
        ),
        evidenceContext: evidenceContext,
        feedbackContext: feedbackContext,
      );
      pending.evidenceContext.validate();
      _submissions[evidenceId] = pending;
      final future = _startSubmission(pending, submission.response);
      _notifyAvailabilityChanged();
      return future;
    } catch (error, stackTrace) {
      return Future<AnswerRecordResult>.error(error, stackTrace);
    }
  }

  Future<void> complete(DateTime occurredAtUtc) {
    try {
      _requireNotDisposed();
      final occurredAt = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
      final inFlight = _completionInFlight;
      if (inFlight != null) return inFlight;
      if (_abandonInFlight != null) {
        throw StateError('Cannot complete while abandon is pending.');
      }
      if (_capturedCompletionInFlight != null) {
        throw StateError(
          'Cannot complete while captured completion is pending.',
        );
      }
      final activeTime = _activeLearningTime;
      final timeOccurrence =
          activeTime != null &&
              activeTime.state != ActiveLearningTimeState.inactive
          ? activeTime.observe(occurredAt)
          : null;
      late final Future<void> future;
      future =
          _serialize<void>(() async {
            if (_state.status == LessonSessionStatus.completed) return;
            _requireStatus(LessonSessionStatus.active, 'complete');
            _requireNoUncommittedSubmission('complete');
            final terminalClose = _terminalClosePending;
            final close =
                terminalClose ??
                (_pendingClose ??= _learning.captureSessionClose(
                  sessionId: _state.sessionId!,
                ));
            _pendingClose ??= close;
            await _finish(close, occurredAt, timeOccurrence);
          }).whenComplete(() {
            if (identical(_completionInFlight, future)) {
              _completionInFlight = null;
              _notifyAvailabilityChanged();
            }
          });
      _completionInFlight = future;
      _notifyAvailabilityChanged();
      return future;
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<LearningSessionSummary> completeCapturedSession(
    PendingLearningSessionClose close,
    DateTime occurredAtUtc,
  ) {
    try {
      return completeCapturedSessionAtCutoff(
        close,
        captureTerminalCutoff(occurredAtUtc),
      );
    } catch (error, stackTrace) {
      return Future<LearningSessionSummary>.error(error, stackTrace);
    }
  }

  Future<LearningSessionSummary> completeCapturedSessionAtCutoff(
    PendingLearningSessionClose close,
    LessonTerminalCutoff cutoff,
  ) {
    try {
      _requireNotDisposed();
      _requireTerminalCutoff(cutoff);
      final occurredAt = cutoff.occurredAtUtc;
      final inFlight = _capturedCompletionInFlight;
      if (inFlight != null) return inFlight;
      if (_completionInFlight != null || _abandonInFlight != null) {
        throw StateError('Cannot complete while a terminal action is pending.');
      }
      if (close.sessionId != _state.sessionId) {
        throw StateError(
          'Captured close does not belong to the active session.',
        );
      }
      final timeOccurrence = cutoff.timeOccurrence;
      late final Future<LearningSessionSummary> future;
      future =
          _serialize<LearningSessionSummary>(() async {
            if (_state.status != LessonSessionStatus.active &&
                _state.status != LessonSessionStatus.paused) {
              throw StateError('Cannot complete from ${_state.status.name}.');
            }
            _requireNoUncommittedSubmission('complete');
            return _finish(close, occurredAt, timeOccurrence);
          }).whenComplete(() {
            if (identical(_capturedCompletionInFlight, future)) {
              _capturedCompletionInFlight = null;
              _notifyAvailabilityChanged();
            }
          });
      _capturedCompletionInFlight = future;
      _notifyAvailabilityChanged();
      return future;
    } catch (error, stackTrace) {
      return Future<LearningSessionSummary>.error(error, stackTrace);
    }
  }

  Future<void> abandon(DateTime occurredAtUtc) {
    try {
      return abandonAtCutoff(captureTerminalCutoff(occurredAtUtc));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> abandonAtCutoff(LessonTerminalCutoff cutoff) {
    try {
      _requireNotDisposed();
      _requireTerminalCutoff(cutoff);
      final occurredAt = cutoff.occurredAtUtc;
      if (_state.status == LessonSessionStatus.abandoned) {
        return Future<void>.value();
      }
      final inFlight = _abandonInFlight;
      if (inFlight != null) return inFlight;
      _requireNoTerminalMutation('abandon');
      final timeOccurrence = cutoff.timeOccurrence;
      late final Future<void> future;
      future =
          _serialize<void>(() async {
            if (_state.status == LessonSessionStatus.abandoned) return;
            if (_state.status == LessonSessionStatus.completed) {
              throw StateError('Cannot abandon a completed lesson.');
            }
            if (_state.status == LessonSessionStatus.planned) {
              _transition(LessonSessionStatus.abandoned, occurredAt);
              return;
            }
            if (_state.status != LessonSessionStatus.active &&
                _state.status != LessonSessionStatus.paused) {
              throw StateError(
                'Cannot abandon lesson from ${_state.status.name}.',
              );
            }
            _requireNoUncommittedSubmission('abandon');
            await _abandon(occurredAt, timeOccurrence);
          }).whenComplete(() {
            if (identical(_abandonInFlight, future)) {
              _abandonInFlight = null;
              _notifyAvailabilityChanged();
            }
          });
      _abandonInFlight = future;
      _notifyAvailabilityChanged();
      return future;
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<AnswerRecordResult> _startSubmission(
    _PendingSubmission pending,
    LessonResponse response,
  ) {
    late final Future<AnswerRecordResult> future;
    future =
        _serialize<AnswerRecordResult>(() {
          _requireStatus(LessonSessionStatus.active, 'submit');
          _requireConfigurationEffortAvailable();
          if (response.sessionId != _state.sessionId) {
            throw StateError(
              'Submission does not belong to the active session.',
            );
          }
          pending.writeAttempted = true;
          return _record(pending, response);
        }).whenComplete(() {
          if (identical(pending.inFlight, future)) pending.inFlight = null;
          if (!pending.writeAttempted &&
              pending.result == null &&
              identical(_submissions[response.sourceEvidenceId], pending)) {
            _submissions.remove(response.sourceEvidenceId);
            _notifyAvailabilityChanged();
          }
        });
    pending.inFlight = future;
    return future;
  }

  Future<AnswerRecordResult> _record(
    _PendingSubmission pending,
    LessonResponse response,
  ) async {
    final result = await _learning.recordEvidence(
      sourceEvidenceId: response.sourceEvidenceId,
      occurredAtUtc: response.occurredAtUtc,
      sessionId: response.sessionId,
      wordId: response.wordId,
      promptMode: response.promptMode,
      isCorrect: response.isCorrect,
      responseTimeMs: response.responseTimeMs,
      attemptNumber: response.attemptNumber,
      evidenceContext: pending.evidenceContext,
      providerProvenance: response.providerProvenance,
    );
    pending.result = result;
    _hints?.resetAfterCommittedEvidence();
    _feedback = AnswerFeedback.fromCommittedResult(
      result: result,
      context: pending.feedbackContext,
    );
    _setState(
      _state.copyWith(
        committedResponseCount: _state.committedResponseCount + 1,
      ),
    );
    return result;
  }

  Future<LearningSessionSummary> _finish(
    PendingLearningSessionClose close,
    DateTime occurredAtUtc,
    LearningTimeObservation? timeOccurrence,
  ) async {
    final terminalClose = _terminalClosePending;
    if (terminalClose != null && !identical(terminalClose, close)) {
      throw StateError(
        'The exact failed session close must be retried before another close.',
      );
    }
    _terminalClosePending = close;
    final activeTime = _activeLearningTime;
    if (activeTime != null &&
        timeOccurrence != null &&
        activeTime.state != ActiveLearningTimeState.inactive) {
      try {
        await _focusTimer?.finishObserved(timeOccurrence);
        await activeTime.finishObserved(timeOccurrence);
        _lastActiveLearningTimeFailure = null;
      } catch (error) {
        _lastActiveLearningTimeFailure = error;
        rethrow;
      }
    }
    await _finishConfigurationEffort();
    final LearningSessionSummary summary;
    if (close.requiresRetry) {
      summary = await close.retry();
    } else {
      summary = await close.finish();
    }
    _transition(LessonSessionStatus.completed, occurredAtUtc);
    if (identical(_terminalClosePending, close)) {
      _terminalClosePending = null;
    }
    return summary;
  }

  Future<void> _abandon(
    DateTime occurredAtUtc,
    LearningTimeObservation? timeOccurrence,
  ) async {
    final activeTime = _activeLearningTime;
    final previousTimeState = activeTime?.state;
    var timeFinished = false;
    if (activeTime != null &&
        timeOccurrence != null &&
        activeTime.state != ActiveLearningTimeState.inactive) {
      try {
        await _focusTimer?.finishObserved(timeOccurrence);
        await activeTime.finishObserved(timeOccurrence);
        _lastActiveLearningTimeFailure = null;
        timeFinished = previousTimeState != ActiveLearningTimeState.finished;
      } catch (error) {
        _lastActiveLearningTimeFailure = error;
        rethrow;
      }
    }
    try {
      await _finishConfigurationEffort();
      await _learning.abandonSession(
        sessionId: _state.sessionId!,
        abandonedAtUtc: occurredAtUtc,
      );
    } catch (_) {
      if (activeTime != null &&
          timeFinished &&
          previousTimeState != null &&
          previousTimeState != ActiveLearningTimeState.inactive) {
        await activeTime.restoreAfterFailedTerminal(
          previousState: previousTimeState,
          occurredAtUtc: occurredAtUtc,
        );
      }
      rethrow;
    }
    _transition(LessonSessionStatus.abandoned, occurredAtUtc);
  }

  Future<T> _serialize<T>(FutureOr<T> Function() operation) {
    final result = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  LessonTerminalCutoff captureTerminalCutoff(DateTime occurredAtUtc) {
    _requireNotDisposed();
    final occurredAt = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
    return LessonTerminalCutoff._(
      authority: _terminalCutoffAuthority,
      occurredAtUtc: occurredAt,
      timeOccurrence: _activeLearningTime?.observe(occurredAt),
      configurationMonotonicMicros: _configurationActiveAnchorMicros == null
          ? null
          : _readConfigurationMonotonic(),
      configurationSessionAttached: _state.sessionId != null,
    );
  }

  Future<void> closeConfigurationEffortAtCutoff(LessonTerminalCutoff cutoff) {
    try {
      _requireNotDisposed();
      _requireTerminalCutoff(cutoff);
      final existing = cutoff.configurationClose;
      if (existing != null) return existing;
      final terminalClose = _configurationTerminalClose;
      if (terminalClose != null) {
        cutoff.configurationClose = terminalClose;
        return terminalClose;
      }
      final anchor = _configurationActiveAnchorMicros;
      final observed = cutoff.configurationMonotonicMicros;
      var targetMicros = _configurationConsumedMicros;
      if (anchor != null) {
        if (observed == null || observed < anchor) {
          _failConfigurationEffortClosed();
          return Future<void>.error(
            StateError('Configuration cutoff clock is invalid.'),
          );
        }
        final elapsedMicros = observed - anchor;
        final countedMicros = _configurationExcludesIdle
            ? math.min(elapsedMicros, _configurationIdleTimeout.inMicroseconds)
            : elapsedMicros;
        final limitMicros = _configurationEffortLimit?.inMicroseconds;
        targetMicros = limitMicros == null
            ? targetMicros + countedMicros
            : math.min(limitMicros, targetMicros + countedMicros);
      }
      cutoff.configurationEffortTargetMicros = targetMicros;
      _configurationActiveAnchorMicros = null;
      _configurationIdle = false;
      _configurationEffortGeneration += 1;
      _invalidateConfigurationLimitTimer();
      late final Future<void> operation;
      operation = _serialize<void>(() async {
        var target = cutoff.configurationEffortTargetMicros!;
        if (_configurationConsumedMicros > target) {
          if (!cutoff.configurationSessionAttached) {
            target = _configurationConsumedMicros;
            cutoff.configurationEffortTargetMicros = target;
          } else {
            _failConfigurationEffortClosed();
            throw StateError(
              'Configuration effort crossed its terminal cutoff.',
            );
          }
        }
        await _persistConfigurationEffort(
          target - _configurationConsumedMicros,
        );
        if (_configurationConsumedMicros != target) {
          _failConfigurationEffortClosed();
          throw StateError('Configuration cutoff effort was not durable.');
        }
        final limit = _configurationEffortLimit;
        if (limit != null && target >= limit.inMicroseconds) {
          _reachConfigurationLimit();
        }
      });
      cutoff.configurationClose = operation;
      _configurationTerminalClose = operation;
      return operation;
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> closeTimeAtCutoff(LessonTerminalCutoff cutoff) {
    try {
      _requireNotDisposed();
      _requireTerminalCutoff(cutoff);
      return _serialize<void>(() async {
        final activeTime = _activeLearningTime;
        if (activeTime == null ||
            activeTime.state == ActiveLearningTimeState.inactive) {
          return;
        }
        try {
          await _focusTimer?.finishObserved(cutoff.timeOccurrence!);
          await activeTime.finishObserved(cutoff.timeOccurrence!);
          _lastActiveLearningTimeFailure = null;
        } catch (error) {
          _lastActiveLearningTimeFailure = error;
          rethrow;
        }
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  void _requireTerminalCutoff(LessonTerminalCutoff cutoff) {
    if (!identical(cutoff.authority, _terminalCutoffAuthority)) {
      throw ArgumentError.value(
        cutoff,
        'cutoff',
        'must be captured by this lesson controller',
      );
    }
  }

  Future<void> recordActiveLearningInteraction(DateTime occurredAtUtc) {
    try {
      _requireNotDisposed();
      _requireConfigurationEffortAvailable();
      final occurredAt = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
      final controller = _activeLearningTime;
      final occurrence = controller?.observe(occurredAt);
      return _serialize<void>(() async {
        await _recordConfigurationInteraction();
        _requireConfigurationEffortAvailable();
        if (controller == null || occurrence == null) return;
        final focusTimer = _focusTimer;
        if (focusTimer?.snapshot.status == FocusTimerStatus.running) {
          await focusTimer!.recordInteractionObserved(occurrence);
          return;
        }
        if (_state.status != LessonSessionStatus.active) {
          await controller.recordInteractionObserved(occurrence);
          return;
        }
        final supersedeFailedEntry = focusTimer?.hasFailedEntryIntent ?? false;
        await controller.recordAutomaticInteractionObserved(occurrence);
        if (supersedeFailedEntry) {
          await focusTimer!.supersedeFailedEntryObserved(occurrence);
        }
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> startFocusTimer(DateTime occurredAtUtc) =>
      _transitionFocusTimer(_FocusTimerAction.start, occurredAtUtc);

  Future<void> pauseFocusTimer(DateTime occurredAtUtc) =>
      _transitionFocusTimer(_FocusTimerAction.pause, occurredAtUtc);

  Future<void> resumeFocusTimer(DateTime occurredAtUtc) =>
      _transitionFocusTimer(_FocusTimerAction.resume, occurredAtUtc);

  Future<void> finishFocusTimer(DateTime occurredAtUtc) =>
      _transitionFocusTimer(_FocusTimerAction.finish, occurredAtUtc);

  Future<void> _transitionFocusTimer(
    _FocusTimerAction action,
    DateTime occurredAtUtc,
  ) {
    try {
      _requireNotDisposed();
      _requireConfigurationEffortAvailable();
      if (!_focusTimerGateEnabled) {
        throw StateError('Focus timer is disabled by its live feature gate.');
      }
      if (_pauseInFlight != null) {
        throw StateError(
          'Cannot ${action.label} while lesson pause is pending.',
        );
      }
      _requireNoTerminalMutation(action.label);
      _requireStatus(LessonSessionStatus.active, action.label);
      final focusTimer = _focusTimer;
      final activeTime = _activeLearningTime;
      if (focusTimer == null || activeTime == null) {
        throw StateError('Focus timer is unavailable for this lesson mode.');
      }
      if (activeTime.state == ActiveLearningTimeState.inactive ||
          activeTime.state == ActiveLearningTimeState.finished) {
        throw StateError('Lesson time authority is unavailable.');
      }
      final occurrence = activeTime.observe(
        _requiredUtc(occurredAtUtc, 'occurredAtUtc'),
      );
      return _serialize<void>(() async {
        _requireStatus(LessonSessionStatus.active, action.label);
        try {
          switch (action) {
            case _FocusTimerAction.start:
              await focusTimer.startObserved(occurrence);
              break;
            case _FocusTimerAction.pause:
              await focusTimer.pauseObserved(occurrence);
              break;
            case _FocusTimerAction.resume:
              await focusTimer.resumeObserved(occurrence);
              break;
            case _FocusTimerAction.finish:
              await focusTimer.finishObserved(occurrence);
              break;
          }
          _lastActiveLearningTimeFailure = null;
        } catch (error) {
          _lastActiveLearningTimeFailure = error;
          rethrow;
        }
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> disableFocusTimer(DateTime occurredAtUtc) {
    try {
      _requireNotDisposed();
      _focusTimerGateEnabled = false;
      final focusTimer = _focusTimer;
      final activeTime = _activeLearningTime;
      if (focusTimer == null ||
          activeTime == null ||
          activeTime.state == ActiveLearningTimeState.inactive ||
          activeTime.state == ActiveLearningTimeState.finished) {
        return Future<void>.value();
      }
      final occurrence = activeTime.observe(
        _requiredUtc(occurredAtUtc, 'occurredAtUtc'),
      );
      return _serialize<void>(() async {
        final failedEntry = focusTimer.hasFailedEntryIntent;
        Future<void> settleBoundary() async {
          if (failedEntry) {
            await activeTime.settleCaptureSourceWithoutInteraction(
              LearningTimeCaptureSource.automaticLesson,
            );
          } else if (focusTimer.snapshot.status == FocusTimerStatus.running) {
            await focusTimer.pauseForFeatureDisabledObserved(occurrence);
          }
        }

        try {
          await settleBoundary();
          _lastActiveLearningTimeFailure = null;
        } catch (error) {
          _lastActiveLearningTimeFailure = error;
          // Retry exactly once with the same boundary and canonical segment.
          await settleBoundary();
          _lastActiveLearningTimeFailure = null;
        }
        if (failedEntry) {
          await focusTimer.supersedeFailedEntryObserved(
            occurrence,
            pauseReason: FocusTimerPauseReason.featureDisabled,
          );
        }
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  void setFocusTimerGateEnabled(bool enabled) {
    if (_disposed) return;
    _focusTimerGateEnabled = enabled;
  }

  void noteActiveLearningInteraction(DateTime occurredAtUtc) {
    final controller = _activeLearningTime;
    if (_disposed || _configurationLimitReached) return;
    unawaited(
      recordActiveLearningInteraction(occurredAtUtc).then<void>(
        (_) {
          if (controller != null &&
              controller.state != ActiveLearningTimeState.inactive) {
            _lastActiveLearningTimeFailure = null;
          }
        },
        onError: (Object error, StackTrace _) {
          if (controller != null) _lastActiveLearningTimeFailure = error;
        },
      ),
    );
  }

  void _requireNoTerminalMutation(String action) {
    if (_completionInFlight != null) {
      throw StateError('Cannot $action while completion is pending.');
    }
    if (_capturedCompletionInFlight != null) {
      throw StateError('Cannot $action while captured completion is pending.');
    }
    if (_abandonInFlight != null) {
      throw StateError('Cannot $action while abandon is pending.');
    }
    if (_terminalClosePending != null) {
      throw StateError(
        'Cannot $action while session completion requires an exact retry.',
      );
    }
  }

  void _requireNoUncommittedSubmission(String action) {
    if (_hasUncommittedSubmission) {
      throw StateError(
        'Cannot $action while accepted evidence requires a successful retry.',
      );
    }
  }

  bool get _hasUncommittedSubmission =>
      _submissions.values.any((submission) => submission.result == null);

  void _notifyAvailabilityChanged() {
    if (!_disposed) notifyListeners();
  }

  void _requireStatus(LessonSessionStatus required, String action) {
    if (_state.status != required) {
      throw StateError(
        'Cannot $action lesson from ${_state.status.name}; '
        '${required.name} is required.',
      );
    }
  }

  void _transition(LessonSessionStatus status, DateTime occurredAtUtc) {
    _setState(
      _state.copyWith(status: status, lastTransitionAtUtc: occurredAtUtc),
    );
  }

  void _setState(LessonSessionState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  void _requireNotDisposed() {
    if (_disposed) {
      throw StateError('UnifiedLessonController is disposed.');
    }
  }

  Duration? get _configurationEffortLimit {
    final timing = _sessionConfiguration?.timing;
    if (timing == null) return null;
    return switch (timing.kind) {
      SessionTimingKind.timed => timing.timedLimit,
      SessionTimingKind.untimedAlternative => timing.maximumActiveEffort,
    };
  }

  bool get _configurationExcludesIdle =>
      _sessionConfiguration?.timing.kind ==
      SessionTimingKind.untimedAlternative;

  void _beginConfigurationEffort(Duration restored) {
    _invalidateConfigurationLimitTimer();
    _configurationEffortGeneration += 1;
    _configurationConsumedMicros = restored.inMicroseconds;
    _configurationLimitReached = false;
    _configurationIdle = false;
    if (_configurationTerminalClose != null) {
      _configurationActiveAnchorMicros = null;
      return;
    }
    final limit = _configurationEffortLimit;
    if (limit == null) {
      _configurationActiveAnchorMicros = null;
      return;
    }
    if (_configurationConsumedMicros < 0 ||
        _configurationConsumedMicros >= limit.inMicroseconds) {
      _reachConfigurationLimit();
      return;
    }
    _configurationActiveAnchorMicros = _readConfigurationMonotonic();
    _scheduleConfigurationLimit();
  }

  void _restoreConfigurationEffortForTerminalReconciliation(Duration restored) {
    _invalidateConfigurationLimitTimer();
    _configurationEffortGeneration += 1;
    _configurationConsumedMicros = restored.inMicroseconds;
    _configurationActiveAnchorMicros = null;
    _configurationLimitReached = false;
    _configurationIdle = false;
  }

  Future<void> _pauseConfigurationEffort() async {
    await _captureConfigurationEffort(stop: true);
    _configurationActiveAnchorMicros = null;
    _configurationIdle = false;
    _invalidateConfigurationLimitTimer();
  }

  void _resumeConfigurationEffort() {
    if (_configurationLimitReached ||
        _configurationEffortLimit == null ||
        _configurationTerminalClose != null) {
      return;
    }
    _configurationIdle = false;
    _configurationActiveAnchorMicros = _readConfigurationMonotonic();
    _scheduleConfigurationLimit();
  }

  Future<void> _finishConfigurationEffort() async {
    await _captureConfigurationEffort(stop: true);
    _configurationActiveAnchorMicros = null;
    _configurationIdle = false;
    _invalidateConfigurationLimitTimer();
  }

  Future<void> _recordConfigurationInteraction() async {
    if (_configurationEffortLimit == null ||
        _state.status != LessonSessionStatus.active ||
        _configurationTerminalClose != null) {
      return;
    }
    final effortGeneration = _configurationEffortGeneration;
    await _captureConfigurationEffort(stop: false);
    if (_configurationLimitReached ||
        _configurationTerminalClose != null ||
        effortGeneration != _configurationEffortGeneration) {
      return;
    }
    _configurationIdle = false;
    _configurationActiveAnchorMicros = _readConfigurationMonotonic();
    _scheduleConfigurationLimit();
  }

  Future<void> _captureConfigurationEffort({required bool stop}) async {
    final anchor = _configurationActiveAnchorMicros;
    if (anchor == null) return;
    final effortGeneration = _configurationEffortGeneration;
    final now = _readConfigurationMonotonic();
    if (now < anchor) {
      _failConfigurationEffortClosed();
      return;
    }
    final elapsedMicros = now - anchor;
    final countedMicros = _configurationExcludesIdle
        ? math.min(elapsedMicros, _configurationIdleTimeout.inMicroseconds)
        : elapsedMicros;
    await _persistConfigurationEffort(countedMicros);
    if (_configurationTerminalClose != null ||
        effortGeneration != _configurationEffortGeneration) {
      return;
    }
    final limit = _configurationEffortLimit;
    if (limit != null && _configurationConsumedMicros >= limit.inMicroseconds) {
      _reachConfigurationLimit();
      return;
    }
    final wentIdle =
        _configurationExcludesIdle &&
        elapsedMicros >= _configurationIdleTimeout.inMicroseconds;
    _configurationIdle = wentIdle;
    _configurationActiveAnchorMicros = stop || wentIdle ? null : now;
  }

  void _scheduleConfigurationLimit() {
    final limit = _configurationEffortLimit;
    if (limit == null ||
        _configurationLimitReached ||
        _configurationTerminalClose != null) {
      return;
    }
    final remainingMicros = limit.inMicroseconds - _configurationConsumedMicros;
    if (remainingMicros <= 0) {
      _reachConfigurationLimit();
      return;
    }
    _invalidateConfigurationLimitTimer();
    final timerGeneration = _configurationLimitTimerGeneration;
    final effortGeneration = _configurationEffortGeneration;
    final scheduledMicros = math.min(
      remainingMicros,
      _configurationIdleTimeout.inMicroseconds,
    );
    final reachesLimit = scheduledMicros == remainingMicros;
    _configurationLimitTimer = Timer(
      Duration(microseconds: scheduledMicros),
      () {
        unawaited(
          _serialize<void>(() async {
            if (timerGeneration != _configurationLimitTimerGeneration ||
                _configurationActiveAnchorMicros == null ||
                _configurationLimitReached) {
              return;
            }
            try {
              await _persistConfigurationEffort(scheduledMicros);
              if (timerGeneration != _configurationLimitTimerGeneration ||
                  effortGeneration != _configurationEffortGeneration ||
                  _configurationTerminalClose != null) {
                return;
              }
              _configurationActiveAnchorMicros = null;
              if (reachesLimit) {
                _reachConfigurationLimit();
              } else if (_configurationExcludesIdle) {
                _configurationIdle = true;
                _configurationLimitTimer = null;
                _notifyAvailabilityChanged();
              } else {
                _configurationActiveAnchorMicros =
                    _readConfigurationMonotonic();
                _scheduleConfigurationLimit();
              }
            } catch (_) {
              _failConfigurationEffortClosed();
            }
          }),
        );
      },
    );
  }

  Future<void> _persistConfigurationEffort(int deltaMicros) async {
    if (deltaMicros <= 0) return;
    final configuration = _sessionConfiguration;
    final sessionId = _state.sessionId;
    if (configuration == null || sessionId == null) {
      _failConfigurationEffortClosed();
      return;
    }
    final limitMicros = _configurationEffortLimit?.inMicroseconds;
    var remainingMicros = limitMicros == null
        ? deltaMicros
        : math.min(
            deltaMicros,
            math.max(0, limitMicros - _configurationConsumedMicros),
          );
    while (remainingMicros > 0) {
      final chunkMicros = math.min(
        remainingMicros,
        const Duration(minutes: 5).inMicroseconds,
      );
      final restored = await _learning.addSessionConfigurationActiveEffort(
        sessionId: sessionId,
        configurationIdentity: configuration.contentIdentity,
        delta: Duration(microseconds: chunkMicros),
      );
      if (restored.isNegative ||
          restored.inMicroseconds < _configurationConsumedMicros ||
          (limitMicros != null && restored.inMicroseconds > limitMicros)) {
        _failConfigurationEffortClosed();
        return;
      }
      _configurationConsumedMicros = restored.inMicroseconds;
      remainingMicros -= chunkMicros;
    }
  }

  void _failConfigurationEffortClosed() {
    _configurationResetRequired = const SessionConfigurationResetRequired(
      SessionConfigurationResetReason.tampered,
      'durable active-effort authority is unavailable',
    );
    _reachConfigurationLimit();
  }

  void _reachConfigurationLimit() {
    if (_disposed || _configurationLimitReached) return;
    _configurationLimitReached = true;
    _configurationEffortGeneration += 1;
    final limit = _configurationEffortLimit;
    if (limit != null) {
      _configurationConsumedMicros = limit.inMicroseconds;
    }
    _configurationActiveAnchorMicros = null;
    _configurationIdle = false;
    _invalidateConfigurationLimitTimer();
    notifyListeners();
    if (_state.status == LessonSessionStatus.active) {
      unawaited(
        pause(
          DateTime.now().toUtc(),
        ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  int _readConfigurationMonotonic() {
    final value = _configurationMonotonicMicros();
    if (value < 0) {
      _reachConfigurationLimit();
      return 0;
    }
    return value;
  }

  void _invalidateConfigurationLimitTimer() {
    _configurationLimitTimerGeneration += 1;
    _configurationLimitTimer?.cancel();
    _configurationLimitTimer = null;
  }

  void _requireConfigurationEffortAvailable() {
    if (_configurationLimitReached) {
      throw const SessionConfigurationLimitReached();
    }
  }

  Future<T> _disposedError<T>() =>
      Future<T>.error(StateError('UnifiedLessonController is disposed.'));

  String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, field, 'must not be blank');
    }
    return normalized;
  }

  DateTime _requiredUtc(DateTime value, String field) {
    if (!value.isUtc) {
      throw ArgumentError.value(value, field, 'must be UTC');
    }
    return value;
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateConfigurationLimitTimer();
    _focusTimer?.dispose();
    _activeLearningTime?.dispose();
    super.dispose();
  }
}

final class _SystemSessionMonotonicClock {
  _SystemSessionMonotonicClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;

  int read() => _stopwatch.elapsedMicroseconds;
}

enum _FocusTimerAction {
  start('start focus'),
  pause('pause focus'),
  resume('resume focus'),
  finish('finish focus');

  const _FocusTimerAction(this.label);

  final String label;
}

final class _PendingSubmission {
  _PendingSubmission({
    required this.intentFingerprint,
    required this.fingerprint,
    required this.evidenceContext,
    required this.feedbackContext,
  });

  final _SubmissionIntentFingerprint intentFingerprint;
  final _SubmissionFingerprint fingerprint;
  final EvidenceContext evidenceContext;
  final AnswerFeedbackContext feedbackContext;
  Future<AnswerRecordResult>? inFlight;
  AnswerRecordResult? result;
  bool writeAttempted = false;
}

final class _SubmissionFingerprint {
  const _SubmissionFingerprint(this.value);

  factory _SubmissionFingerprint.from(
    LessonSubmission submission, {
    required AnswerFeedbackContext feedbackContext,
    required EvidenceContext evidenceContext,
  }) {
    final response = submission.response;
    return _SubmissionFingerprint(
      jsonEncode(<String, Object?>{
        'sourceEvidenceId': response.sourceEvidenceId,
        'occurredAtUtc': response.occurredAtUtc.toIso8601String(),
        'sessionId': response.sessionId,
        'wordId': response.wordId,
        'promptMode': response.promptMode,
        'isCorrect': response.isCorrect,
        'responseTimeMs': response.responseTimeMs,
        'attemptNumber': response.attemptNumber,
        'providerProvenance': response.providerProvenance,
        'canonicalCorrectAnswer': feedbackContext.canonicalCorrectAnswer,
        'bookmarkIdentity': _bookmarkIdentityJson(
          feedbackContext.bookmarkIdentity,
        ),
        'evidenceContext': evidenceContext.toJson(),
      }),
    );
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is _SubmissionFingerprint && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class _SubmissionIntentFingerprint {
  const _SubmissionIntentFingerprint(this.value);

  factory _SubmissionIntentFingerprint.from(
    LessonSubmission submission, {
    required AnswerFeedbackContext feedbackContext,
  }) {
    final response = submission.response;
    return _SubmissionIntentFingerprint(
      jsonEncode(<String, Object?>{
        'sourceEvidenceId': response.sourceEvidenceId,
        'occurredAtUtc': response.occurredAtUtc.toIso8601String(),
        'sessionId': response.sessionId,
        'wordId': response.wordId,
        'promptMode': response.promptMode,
        'isCorrect': response.isCorrect,
        'responseTimeMs': response.responseTimeMs,
        'attemptNumber': response.attemptNumber,
        'providerProvenance': response.providerProvenance,
        'canonicalCorrectAnswer': feedbackContext.canonicalCorrectAnswer,
        'bookmarkIdentity': _bookmarkIdentityJson(
          feedbackContext.bookmarkIdentity,
        ),
        'declaredEvidenceContext': submission.support.evidenceContext.toJson(),
      }),
    );
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is _SubmissionIntentFingerprint && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

Map<String, Object?>? _bookmarkIdentityJson(ContentIdentity? identity) =>
    identity == null
    ? null
    : <String, Object?>{
        'type': identity.type.name,
        'id': identity.id,
        'revision': identity.revision,
      };
