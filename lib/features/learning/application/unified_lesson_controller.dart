import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../domain/answer_feedback.dart';
import '../domain/evidence_context.dart';
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
    return UnifiedLessonController._(learning, adapter, resolvedHints);
  }

  UnifiedLessonController._(this._learning, this._adapter, this._hints)
    : _state = LessonSessionState.planned(_adapter.mode);

  final LearningUseCases _learning;
  final LessonModeAdapter _adapter;
  final HintUseCases? _hints;
  LessonSessionState _state;
  AnswerFeedback? _feedback;
  final Map<String, _PendingSubmission> _submissions =
      <String, _PendingSubmission>{};
  PendingLearningSessionClose? _pendingClose;
  Future<void>? _pauseInFlight;
  Future<void>? _completionInFlight;
  Future<void>? _abandonInFlight;
  Future<void> _mutationTail = Future<void>.value();
  bool _disposed = false;

  LessonSessionState get state => _state;
  AnswerFeedback? get feedback => _feedback;
  HintState? get hintState => _hints?.state;
  bool get canRevealHint {
    final hint = _hints?.state;
    return !_disposed &&
        hint != null &&
        hint.availability == HintAvailability.available &&
        !hint.isExhausted &&
        _state.status == LessonSessionStatus.active &&
        _pauseInFlight == null &&
        _completionInFlight == null &&
        _abandonInFlight == null &&
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
    return _serialize<void>(() {
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
      late final Future<void> future;
      future =
          _serialize<void>(() {
            _requireStatus(LessonSessionStatus.active, 'pause');
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
      return _serialize<void>(() {
        _requireStatus(LessonSessionStatus.paused, 'resume');
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
      _requiredUtc(occurredAtUtc, 'occurredAtUtc');
      final inFlight = _completionInFlight;
      if (inFlight != null) return inFlight;
      if (_abandonInFlight != null) {
        throw StateError('Cannot complete while abandon is pending.');
      }
      late final Future<void> future;
      future =
          _serialize<void>(() async {
            if (_state.status == LessonSessionStatus.completed) return;
            _requireStatus(LessonSessionStatus.active, 'complete');
            _requireNoUncommittedSubmission('complete');
            final close = _pendingClose ??= _learning.captureSessionClose(
              sessionId: _state.sessionId!,
            );
            await _finish(close, occurredAtUtc);
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

  Future<void> abandon(DateTime occurredAtUtc) {
    try {
      _requireNotDisposed();
      final occurredAt = _requiredUtc(occurredAtUtc, 'occurredAtUtc');
      if (_state.status == LessonSessionStatus.abandoned) {
        return Future<void>.value();
      }
      final inFlight = _abandonInFlight;
      if (inFlight != null) return inFlight;
      if (_completionInFlight != null) {
        throw StateError('Cannot abandon while completion is pending.');
      }
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
            await _abandon(occurredAt);
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

  Future<void> _finish(
    PendingLearningSessionClose close,
    DateTime occurredAtUtc,
  ) async {
    if (close.requiresRetry) {
      await close.retry();
    } else {
      await close.finish();
    }
    _transition(LessonSessionStatus.completed, occurredAtUtc);
  }

  Future<void> _abandon(DateTime occurredAtUtc) async {
    await _learning.abandonSession(
      sessionId: _state.sessionId!,
      abandonedAtUtc: occurredAtUtc,
    );
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

  void _requireNoTerminalMutation(String action) {
    if (_completionInFlight != null) {
      throw StateError('Cannot $action while completion is pending.');
    }
    if (_abandonInFlight != null) {
      throw StateError('Cannot $action while abandon is pending.');
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
