import 'learning_record_validation.dart';

enum AssociationCueType {
  personalStory,
  keyword,
  collocation,
  synonym,
  antonym,
  sensory,
  context,
}

enum AssociationOrigin { userCreated, generatedSuggestionAccepted }

final class AssociationRecord {
  AssociationRecord({
    required this.associationId,
    required this.ownerId,
    required this.wordKey,
    required this.cueType,
    required this.cueText,
    required this.origin,
    this.strength = 1,
    this.successCount = 0,
    this.failureCount = 0,
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
    this.schemaVersion = 1,
  }) : createdAtUtc = LearningRecordValidation.utc(createdAtUtc),
       updatedAtUtc = LearningRecordValidation.utc(updatedAtUtc) {
    LearningRecordValidation.identifier(associationId, 'associationId');
    LearningRecordValidation.identifier(ownerId, 'ownerId');
    LearningRecordValidation.identifier(wordKey, 'wordKey');
    LearningRecordValidation.schemaVersion(schemaVersion);
    if (cueText.trim().isEmpty || cueText.length > 500) {
      throw ArgumentError.value(
        cueText,
        'cueText',
        'must be non-empty and at most 500 characters',
      );
    }
    LearningRecordValidation.finiteAtLeast(strength, 'strength', 0);
    if (successCount < 0 || failureCount < 0) {
      throw ArgumentError('association counts must be non-negative');
    }
    if (this.updatedAtUtc.isBefore(this.createdAtUtc)) {
      throw ArgumentError('updatedAtUtc must not precede createdAtUtc');
    }
  }

  final String associationId;
  final String ownerId;
  final String wordKey;
  final AssociationCueType cueType;
  final String cueText;
  final AssociationOrigin origin;
  final double strength;
  final int successCount;
  final int failureCount;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int schemaVersion;
}
