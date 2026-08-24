import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../../time_tracking/application/active_learning_time_controller.dart';
import '../domain/answer_feedback.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/hint_policy.dart';
import '../domain/learning_models.dart';
import '../domain/lesson_mode.dart';
import '../domain/lesson_session_state.dart';
import 'hint_use_cases.dart';
import 'learning_use_cases.dart';

typedef UnifiedLessonControllerFactory =
    UnifiedLessonController Function(LessonModeAdapter adapter);

final class UnifiedLessonController extends ChangeNotifier {
  factory UnifiedLessonController({
    required LearningUseCases learning,
    required LessonModeAdapter adapter,
    HintUseCases? hints,
    ActiveLearningTimeController? activeLearningTime,
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
    return UnifiedLessonController._(
      learning,
      adapter,
      resolvedHints,
      activeLearningTime,
    );
  }

  UnifiedLessonController._(
    this._learning,
    this._adapter,
    this._hints,
    this._activeLearningTime,
  ) : _state = LessonSessionState.planned(_adapter.mode);

  final LearningUseCases _learning;
  final LessonModeAdapter _adapter;
  final HintUseCases? _hints;
  final ActiveLearningTimeController? _activeLearningTime;
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
  Object? _lastActiveLearningTimeFailure;

  LessonSessionState get state => _state;
  AnswerFeedback? get feedback => _feedback;
  HintState? get hintState => _hints?.state;
  ActiveLearningTimeController? get activeLearningTime => _activeLearningTime;
  Object? get lastActiveLearningTimeFailure => _lastActiveLearningTimeFailure;
  bool get terminalMutationInFlight =>
      _completionInFlight != null ||
      _capturedCompletionInFlight != null ||
      _abandonInFlight != null ||
      _terminalClosePending != null;
  bool get canRevealHint {
    final hint = _hints?.state;
    return !_disposed &&
        hint != null &&
        hint.availability == HintAvailability.available &&
        !hint.isExhausted &&
        _state.status == LessonSessionStatus.active &&
        _pauseInFlight == null &&
        _completionInFlight == null &&
        _capturedCompletionInFlight == null &&
        _abandonInFlight == null &&
        _terminalClosePending == null &&
        !_hasUncommittedSubmission;
  }

  HintRevealResult revealNextHint() {
    _requireNotDisposed();
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
    final result = hints.revealNext();
    if (result.changed && !_disposed) notifyListeners();
    return result;
  }

  Future<void> start(LessonStartCommand command) {
    if (_disposed) return _disposedError<void>();
    return _serialize<void>(() async {
      _requireStatus(LessonSessionStatus.planned, 'start');
      if (command.mode != _adapter.mode) {
        throw StateError('Lesson mode does not match the resolved adapter.');
      }
      final sessionId = _required(command.sessionId, 'sessionId');
      final startedAtUtc = _requiredUtc(command.startedAtUtc, 'startedAtUtc');
      if (command.itemCount < 0) {
        throw ArgumentError.value(
          command.itemCount,
          'itemCount',
          'must be nonnegative',
        );
      }
      final activeTime = _activeLearningTime;
      if (activeTime != null) {
        try {
          await activeTime.start(
            sessionId: sessionId,
            occurredAtUtc: startedAtUtc,
          );
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
    });
  }

  Future<void> pause(DateTime occurredAtUtc) {
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
              await activeTime.pauseObserved(timeOccurrence);
            }
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
      _requireNotDisposed();
      final occurredAt = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
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
      final activeTime = _activeLearningTime;
      final timeOccurrence =
          activeTime != null &&
              activeTime.state != ActiveLearningTimeState.inactive
          ? activeTime.observe(occurredAt)
          : null;
      late final Future<LearningSessionSummary> future;
      future =
          _serialize<LearningSessionSummary>(() async {
            _requireStatus(LessonSessionStatus.active, 'complete');
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
      _requireNotDisposed();
      final occurredAt = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
      if (_state.status == LessonSessionStatus.abandoned) {
        return Future<void>.value();
      }
      final inFlight = _abandonInFlight;
      if (inFlight != null) return inFlight;
      _requireNoTerminalMutation('abandon');
      final activeTime = _activeLearningTime;
      final timeOccurrence =
          activeTime != null &&
              activeTime.state != ActiveLearningTimeState.inactive
          ? activeTime.observe(occurredAt)
          : null;
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
    if (activeTime != null && timeOccurrence != null) {
      try {
        await activeTime.finishObserved(timeOccurrence);
        _lastActiveLearningTimeFailure = null;
      } catch (error) {
        _lastActiveLearningTimeFailure = error;
        rethrow;
      }
    }
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
    if (activeTime != null && timeOccurrence != null) {
      try {
        await activeTime.finishObserved(timeOccurrence);
        _lastActiveLearningTimeFailure = null;
        timeFinished = true;
      } catch (error) {
        _lastActiveLearningTimeFailure = error;
        rethrow;
      }
    }
    try {
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

  Future<void> recordActiveLearningInteraction(DateTime occurredAtUtc) {
    if (_disposed) return _disposedError<void>();
    final controller = _activeLearningTime;
    if (controller == null) return Future<void>.value();
    return controller.recordInteraction(occurredAtUtc: occurredAtUtc);
  }

  void noteActiveLearningInteraction(DateTime occurredAtUtc) {
    final controller = _activeLearningTime;
    if (_disposed || controller == null) return;
    unawaited(
      recordActiveLearningInteraction(occurredAtUtc).then<void>(
        (_) {
          if (controller.state != ActiveLearningTimeState.inactive) {
            _lastActiveLearningTimeFailure = null;
          }
        },
        onError: (Object error, StackTrace _) {
          _lastActiveLearningTimeFailure = error;
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
    _activeLearningTime?.dispose();
    super.dispose();
  }
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
