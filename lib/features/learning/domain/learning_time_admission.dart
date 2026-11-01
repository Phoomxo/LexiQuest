import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'evidence_context.dart';
import 'learning_models.dart';
import 'matching_exercise.dart';

enum CanonicalLearningTimeSourceKind {
  configuredQuiz,
  matching,
  ownedSrs,
  dictation,
  cloze,
  voicePractice,
  reading,
  tutor,
}

/// Supplied by the actual Study/Assessment caller, never inferred from a
/// missing optional lifecycle-observer row.
enum LearningTimeCallerContext { ordinary, researchControlled, unavailable }

/// Data is readable, but only the issuing repository can validate authority.
/// Implementing or copying this interface does not mint a valid capability.
abstract interface class CanonicalLearningTimeSessionLinkReceipt {
  String get ownerId;
  String get sessionId;
  String get activityType;
  CanonicalLearningTimeSourceKind get sourceKind;
  String get sourceBindingJson;
}

abstract interface class CanonicalLearningTimeAdmission
    implements CanonicalLearningTimeSessionLinkReceipt {
  @override
  String get ownerId;
  @override
  String get sessionId;
  @override
  String get activityType;
  @override
  CanonicalLearningTimeSourceKind get sourceKind;
  @override
  String get sourceBindingJson;
  String get contextBindingJson;
  EvidenceContext get evidenceContext;
}

sealed class CanonicalLearningTimeAdmissionRequest {
  const CanonicalLearningTimeAdmissionRequest({required this.callerContext});
  final LearningTimeCallerContext callerContext;
}

final class ConfiguredQuizTimeAdmission
    extends CanonicalLearningTimeAdmissionRequest {
  const ConfiguredQuizTimeAdmission(this.state, {required super.callerContext});
  final ConfiguredQuizState state;
}

final class MatchingTimeAdmission
    extends CanonicalLearningTimeAdmissionRequest {
  const MatchingTimeAdmission(this.state, {required super.callerContext});
  final MatchingState state;
}

enum SrsTimePhase { front, revealed }

final class OwnedSrsTimeAdmission
    extends CanonicalLearningTimeAdmissionRequest {
  const OwnedSrsTimeAdmission(
    this.review, {
    required this.cardIndex,
    required this.phase,
    required super.callerContext,
  });
  final SrsReviewSession review;
  final int cardIndex;
  final SrsTimePhase phase;
}

final class NativeLearningTimeAdmission
    extends CanonicalLearningTimeAdmissionRequest {
  const NativeLearningTimeAdmission(
    this.exercise, {
    required this.hintLevel,
    required super.callerContext,
  });
  final AcceptedNativeExercise exercise;
  final int hintLevel;
}

/// This port never starts a session or writes a learning/time/reward row.
abstract interface class CanonicalLearningTimeAdmissionRepository {
  Future<CanonicalLearningTimeAdmission> admitCanonicalLearningTime(
    CanonicalLearningTimeAdmissionRequest request, {
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  });

  Future<void> requireLiveCanonicalLearningTimeAdmission(
    CanonicalLearningTimeAdmission admission, {
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  });

  /// Call inside the time writer's owner-fenced transaction. Its callback
  /// checks the captured owner/gate generation, not the retired route.
  Future<void> requireCanonicalLearningTimeAdmission(
    CanonicalLearningTimeAdmission admission, {
    required String expectedOwnerId,
    required bool Function() ownerStillCurrent,
  });

  Future<void> requireCanonicalLearningTimeSessionLinkReceipt(
    CanonicalLearningTimeSessionLinkReceipt receipt, {
    required String expectedOwnerId,
    required bool Function() ownerStillCurrent,
  });
}

sealed class VocabularyLearningTimeSourcePin {
  const VocabularyLearningTimeSourcePin();
  CanonicalLearningTimeSourceKind get sourceKind;
  String get activityType;
  String get targetPinsSha256;
  String get sourceBindingJson;
}

final class ReadingLearningTimeSourcePin
    extends VocabularyLearningTimeSourcePin {
  ReadingLearningTimeSourcePin({
    required this.documentId,
    required this.documentRevision,
    required this.snapshotSha256,
    required this.targetPinsSha256,
  }) {
    _timePinId(documentId);
    if (documentRevision < 1) throw ArgumentError.value(documentRevision);
    _timePinSha(snapshotSha256);
    _timePinSha(targetPinsSha256);
  }
  final String documentId;
  final int documentRevision;
  final String snapshotSha256;
  @override
  final String targetPinsSha256;
  @override
  CanonicalLearningTimeSourceKind get sourceKind =>
      CanonicalLearningTimeSourceKind.reading;
  @override
  String get activityType => 'associativeReading';
  @override
  String get sourceBindingJson => jsonEncode({
    'schemaVersion': 1,
    'kind': 'reading',
    'documentId': documentId,
    'documentRevision': documentRevision,
    'snapshotSha256': snapshotSha256,
    'targetPinsSha256': targetPinsSha256,
  });
}

enum VoiceLearningTimePracticeKind { shadowing, pronunciation }

final class VoiceLearningTimeSourcePin extends VocabularyLearningTimeSourcePin {
  VoiceLearningTimeSourcePin._({
    required this.sessionId,
    required this.practiceKind,
    required this.episodeId,
    required this.targetPinsSha256,
  });

  factory VoiceLearningTimeSourcePin.capture({
    required String sessionId,
    required VoiceLearningTimePracticeKind practiceKind,
    required List<QuizWord> words,
  }) {
    _timePinId(sessionId);
    if (words.isEmpty) {
      throw ArgumentError('Voice practice has no actual prompt');
    }
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              practiceKind.name,
              for (final word in words)
                [word.id, word.contentRevision, word.spelling],
            ]),
          ),
        )
        .toString();
    return VoiceLearningTimeSourcePin._(
      sessionId: sessionId,
      practiceKind: practiceKind,
      episodeId: 'voice-prompt:$digest',
      targetPinsSha256: learningTimeTargetPinsSha256(words),
    );
  }

  final String sessionId;
  final VoiceLearningTimePracticeKind practiceKind;
  final String episodeId;
  @override
  final String targetPinsSha256;
  @override
  CanonicalLearningTimeSourceKind get sourceKind =>
      CanonicalLearningTimeSourceKind.voicePractice;
  @override
  String get activityType => practiceKind.name;
  @override
  String get sourceBindingJson => jsonEncode({
    'schemaVersion': 1,
    'kind': 'voicePractice',
    'sessionId': sessionId,
    'episodeId': episodeId,
    'targetPinsSha256': targetPinsSha256,
  });
}

String learningTimeTargetPinsSha256(Iterable<QuizWord> words) => sha256
    .convert(
      utf8.encode(
        jsonEncode([
          for (final word in words) [word.id, word.contentRevision],
        ]),
      ),
    )
    .toString();

void _timePinId(String value) {
  if (value.isEmpty ||
      value.length > 128 ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw ArgumentError('Invalid source identifier');
  }
}

void _timePinSha(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError('Invalid source digest');
  }
}

/// Prepared only by the existing learning repository. It is not a time scope.
/// The original draft/presentation/source stays fixed across a lost start ACK.
abstract interface class PreparedSourceBoundVocabularyStart {
  String get ownerId;
  String get sessionId;
  QuizSession get presentation;
  VocabularyLearningTimeSourcePin get source;
  LearningTimeCallerContext get callerContext;
}

final class SourceBoundVocabularyTimeAdmission
    extends CanonicalLearningTimeAdmissionRequest {
  const SourceBoundVocabularyTimeAdmission(
    this.start, {
    required this.wordIndex,
    required super.callerContext,
  });
  final PreparedSourceBoundVocabularyStart start;
  final int wordIndex;
}

/// This is an ACK wrapper around the existing canonical _startSession operation.
/// Time use cases must never invoke this port to manufacture a session.
abstract interface class SourceBoundVocabularyStartRepository {
  Future<PreparedSourceBoundVocabularyStart> prepareSourceBoundVocabularyStart({
    required LearningSessionDraft session,
    required List<QuizWord> words,
    required QuizSession presentation,
    required VocabularyLearningTimeSourcePin source,
    required LearningTimeCallerContext callerContext,
    required bool Function() stillCurrent,
  });

  Future<QuizSession> startSourceBoundVocabularySession(
    PreparedSourceBoundVocabularyStart intent, {
    required bool Function() operationStillCurrent,
  });

  /// Reads the ACK of the original actual start. It does not admit collection
  /// and may finish after the old route ends while owner permission survives.
  Future<CanonicalLearningTimeSessionLinkReceipt>
  readSourceBoundVocabularyStartReceipt(
    PreparedSourceBoundVocabularyStart intent, {
    required String expectedOwnerId,
    required bool Function() ownerStillCurrent,
  });
}
