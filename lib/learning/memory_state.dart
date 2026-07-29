import 'learning_record_validation.dart';

final class MemoryState {
  MemoryState({
    required this.ownerId,
    required this.wordKey,
    required this.strength,
    required this.cueDependency,
    required this.stability,
    required this.difficulty,
    required this.lapseCount,
    DateTime? lastReviewedAtUtc,
    required DateTime nextDueAtUtc,
    this.lastErrorType,
    required this.algorithmVersion,
    required DateTime updatedAtUtc,
    this.schemaVersion = 1,
  }) : lastReviewedAtUtc = lastReviewedAtUtc == null
           ? null
           : LearningRecordValidation.utc(lastReviewedAtUtc),
       nextDueAtUtc = LearningRecordValidation.utc(nextDueAtUtc),
       updatedAtUtc = LearningRecordValidation.utc(updatedAtUtc) {
    LearningRecordValidation.identifier(ownerId, 'ownerId');
    LearningRecordValidation.identifier(wordKey, 'wordKey');
    LearningRecordValidation.identifier(algorithmVersion, 'algorithmVersion');
    LearningRecordValidation.schemaVersion(schemaVersion);
    if (lastErrorType != null) {
      LearningRecordValidation.identifier(lastErrorType!, 'lastErrorType');
    }
    LearningRecordValidation.finiteAtLeast(strength, 'strength', 0);
    LearningRecordValidation.finiteRange(cueDependency, 'cueDependency', 0, 1);
    LearningRecordValidation.finiteAtLeast(stability, 'stability', 0);
    LearningRecordValidation.finiteRange(difficulty, 'difficulty', 0, 10);
    if (lapseCount < 0) {
      throw ArgumentError.value(
        lapseCount,
        'lapseCount',
        'must be non-negative',
      );
    }
  }

  final String ownerId;
  final String wordKey;
  final double strength;
  final double cueDependency;
  final double stability;
  final double difficulty;
  final int lapseCount;
  final DateTime? lastReviewedAtUtc;
  final DateTime nextDueAtUtc;
  final String? lastErrorType;
  final String algorithmVersion;
  final DateTime updatedAtUtc;
  final int schemaVersion;
}
