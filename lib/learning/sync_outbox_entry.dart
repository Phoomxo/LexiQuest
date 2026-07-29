import 'dart:convert';

import 'learning_record_validation.dart';

enum OutboxOperation { recordProgressSession }

final class SyncOutboxEntry {
  SyncOutboxEntry({
    required this.outboxId,
    required this.ownerId,
    required this.eventId,
    required this.operation,
    required this.payloadJson,
    required DateTime createdAtUtc,
    DateTime? acknowledgedAtUtc,
    this.attemptCount = 0,
    this.schemaVersion = 1,
  }) : createdAtUtc = LearningRecordValidation.utc(createdAtUtc),
       acknowledgedAtUtc = acknowledgedAtUtc == null
           ? null
           : LearningRecordValidation.utc(acknowledgedAtUtc) {
    LearningRecordValidation.identifier(outboxId, 'outboxId');
    LearningRecordValidation.identifier(ownerId, 'ownerId');
    LearningRecordValidation.identifier(eventId, 'eventId');
    LearningRecordValidation.schemaVersion(schemaVersion);
    if (attemptCount < 0) {
      throw ArgumentError.value(
        attemptCount,
        'attemptCount',
        'must be non-negative',
      );
    }
    if (payloadJson.length > 8192) {
      throw ArgumentError.value(
        payloadJson.length,
        'payloadJson',
        'must be at most 8192 characters',
      );
    }
    _validatePayload();
  }

  final String outboxId;
  final String ownerId;
  final String eventId;
  final OutboxOperation operation;
  final String payloadJson;
  final DateTime createdAtUtc;
  final DateTime? acknowledgedAtUtc;
  final int attemptCount;
  final int schemaVersion;

  void _validatePayload() {
    final Object? decoded;
    try {
      decoded = jsonDecode(payloadJson);
    } on FormatException {
      throw ArgumentError.value(payloadJson, 'payloadJson', 'must be JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ArgumentError.value(
        payloadJson,
        'payloadJson',
        'must be a JSON object',
      );
    }
    const allowedKeys = <String>{
      'sessionId',
      'eventIds',
      'correctAnswers',
      'completedAt',
    };
    final unknownKeys = decoded.keys.toSet().difference(allowedKeys);
    if (unknownKeys.isNotEmpty) {
      throw ArgumentError.value(
        unknownKeys,
        'payloadJson',
        'contains unsupported fields',
      );
    }
    if (!decoded.containsKey('sessionId')) {
      throw ArgumentError.value(
        payloadJson,
        'payloadJson',
        'must contain sessionId',
      );
    }
  }
}
