import 'learning_record_validation.dart';

enum RecallMode { unaided, cued, cloze, multipleChoice, transfer }

enum RecallCueLevel { none, highlight, associationHint, fullDefinition }

final class RecallAttempt {
  RecallAttempt({
    required this.attemptId,
    required this.ownerId,
    required this.sessionId,
    required this.wordKey,
    required this.recallMode,
    required this.cueLevel,
    required this.correctness,
    required this.responseTimeMs,
    required this.confidence,
    this.contextId,
    required this.algorithmVersion,
    required DateTime occurredAtUtc,
    this.schemaVersion = 1,
  }) : occurredAtUtc = LearningRecordValidation.utc(occurredAtUtc) {
    LearningRecordValidation.identifier(attemptId, 'attemptId');
    LearningRecordValidation.identifier(ownerId, 'ownerId');
    LearningRecordValidation.identifier(sessionId, 'sessionId');
    LearningRecordValidation.identifier(wordKey, 'wordKey');
    LearningRecordValidation.identifier(algorithmVersion, 'algorithmVersion');
    LearningRecordValidation.schemaVersion(schemaVersion);
    if (contextId != null) {
      LearningRecordValidation.identifier(contextId!, 'contextId');
    }
    if (responseTimeMs < 0) {
      throw ArgumentError.value(
        responseTimeMs,
        'responseTimeMs',
        'must be non-negative',
      );
    }
    if (confidence < 1 || confidence > 5) {
      throw ArgumentError.value(confidence, 'confidence', 'must be 1 to 5');
    }
  }

  final String attemptId;
  final String ownerId;
  final String sessionId;
  final String wordKey;
  final RecallMode recallMode;
  final RecallCueLevel cueLevel;
  final bool correctness;
  final int responseTimeMs;
  final int confidence;
  final String? contextId;
  final String algorithmVersion;
  final DateTime occurredAtUtc;
  final int schemaVersion;
}
