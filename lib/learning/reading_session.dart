import 'learning_record_validation.dart';

enum ReadingSessionStage {
  supportedReading,
  cueFading,
  recall,
  association,
  transfer,
  scheduling,
  completed,
  abandoned,
}

final class ReadingSession {
  ReadingSession({
    required this.sessionId,
    required this.ownerId,
    required this.cefrLevel,
    required List<String> targetWordKeys,
    required this.mixPolicyVersion,
    required this.contentId,
    required this.contentVersion,
    required this.currentStage,
    required DateTime startedAtUtc,
    required DateTime updatedAtUtc,
    DateTime? completedAtUtc,
    DateTime? abandonedAtUtc,
    this.schemaVersion = 1,
  }) : targetWordKeys = List<String>.unmodifiable(targetWordKeys),
       startedAtUtc = LearningRecordValidation.utc(startedAtUtc),
       updatedAtUtc = LearningRecordValidation.utc(updatedAtUtc),
       completedAtUtc = completedAtUtc == null
           ? null
           : LearningRecordValidation.utc(completedAtUtc),
       abandonedAtUtc = abandonedAtUtc == null
           ? null
           : LearningRecordValidation.utc(abandonedAtUtc) {
    LearningRecordValidation.identifier(sessionId, 'sessionId');
    LearningRecordValidation.identifier(ownerId, 'ownerId');
    LearningRecordValidation.identifier(mixPolicyVersion, 'mixPolicyVersion');
    LearningRecordValidation.identifier(contentId, 'contentId');
    LearningRecordValidation.identifier(contentVersion, 'contentVersion');
    LearningRecordValidation.schemaVersion(schemaVersion);
    if (!RegExp(r'^[ABC][12]$').hasMatch(cefrLevel)) {
      throw ArgumentError.value(
        cefrLevel,
        'cefrLevel',
        'must be A1 through C2',
      );
    }
    if (this.targetWordKeys.isEmpty || this.targetWordKeys.length > 8) {
      throw ArgumentError.value(
        targetWordKeys,
        'targetWordKeys',
        'must contain between 1 and 8 words',
      );
    }
    for (final wordKey in this.targetWordKeys) {
      LearningRecordValidation.identifier(wordKey, 'targetWordKeys');
    }
    if (this.targetWordKeys.toSet().length != this.targetWordKeys.length) {
      throw ArgumentError('targetWordKeys must not contain duplicates');
    }
    if (this.updatedAtUtc.isBefore(this.startedAtUtc)) {
      throw ArgumentError('updatedAtUtc must not precede startedAtUtc');
    }
    _validateTerminalState();
  }

  final String sessionId;
  final String ownerId;
  final String cefrLevel;
  final List<String> targetWordKeys;
  final String mixPolicyVersion;
  final String contentId;
  final String contentVersion;
  final ReadingSessionStage currentStage;
  final DateTime startedAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? completedAtUtc;
  final DateTime? abandonedAtUtc;
  final int schemaVersion;

  void _validateTerminalState() {
    switch (currentStage) {
      case ReadingSessionStage.completed:
        if (completedAtUtc == null || abandonedAtUtc != null) {
          throw ArgumentError('completed sessions require only completedAtUtc');
        }
      case ReadingSessionStage.abandoned:
        if (abandonedAtUtc == null || completedAtUtc != null) {
          throw ArgumentError('abandoned sessions require only abandonedAtUtc');
        }
      default:
        if (completedAtUtc != null || abandonedAtUtc != null) {
          throw ArgumentError(
            'non-terminal sessions cannot have terminal timestamps',
          );
        }
    }
  }
}
