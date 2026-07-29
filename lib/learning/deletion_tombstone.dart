import 'learning_record_validation.dart';

enum TombstoneEntityType { association }

final class DeletionTombstone {
  DeletionTombstone({
    required this.tombstoneId,
    required this.ownerId,
    required this.entityType,
    required this.entityId,
    required DateTime deletedAtUtc,
    this.schemaVersion = 1,
  }) : deletedAtUtc = LearningRecordValidation.utc(deletedAtUtc) {
    LearningRecordValidation.identifier(tombstoneId, 'tombstoneId');
    LearningRecordValidation.identifier(ownerId, 'ownerId');
    LearningRecordValidation.opaqueIdentifier(entityId, 'entityId');
    LearningRecordValidation.schemaVersion(schemaVersion);
  }

  final String tombstoneId;
  final String ownerId;
  final TombstoneEntityType entityType;
  final String entityId;
  final DateTime deletedAtUtc;
  final int schemaVersion;
}
