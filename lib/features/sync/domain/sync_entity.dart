import 'dart:convert';

import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import 'sync_failure.dart';

const int currentSyncPayloadVersion = 1;

enum SyncCollection {
  categories,
  words,
  attempts,
  readingEvents,
  rewardTransactions,

  /// Mutable FSRS algorithm state per (owner, word).
  /// Pull retains merged answer evidence and otherwise imports server state.
  /// Phase 0 Week 12-13.
  srsStates,

  /// Immutable append-only achievement unlock records.
  /// Pull semantics: insertOrIgnore (once unlocked, never revoked).
  /// Phase 0 Week 12-13.
  achievementUnlocks,
}

bool supportsSyncPayloadVersion(SyncCollection collection, int version) =>
    version == currentSyncPayloadVersion ||
    (collection == SyncCollection.attempts && version == 2);

abstract final class AnswerAttemptSyncPayloadContract {
  static const _v1Keys = <String>{
    'sessionId',
    'wordId',
    'promptMode',
    'isCorrect',
    'responseTimeMs',
    'attemptNumber',
    'occurredAtUtcMs',
    'providerProvenance',
  };
  static const _v2Keys = <String>{
    ..._v1Keys,
    'evidenceClass',
    'evidenceContext',
  };

  static EvidenceContext requireEvidenceContext({
    required int payloadVersion,
    required Map<String, Object?> payload,
  }) {
    try {
      final keys = switch (payloadVersion) {
        1 => _v1Keys,
        2 => _v2Keys,
        _ => throw const UnsupportedSyncSchemaFailure(),
      };
      if (payload.length != keys.length || !payload.keys.every(keys.contains)) {
        throw const InvalidSyncPayloadFailure();
      }
      final responseTimeMs = payload['responseTimeMs'];
      final provenance = payload['providerProvenance'];
      final sessionId = payload['sessionId'];
      final wordId = payload['wordId'];
      final promptMode = payload['promptMode'];
      final attemptNumber = payload['attemptNumber'];
      final occurredAtUtcMs = payload['occurredAtUtcMs'];
      if (sessionId is! String ||
          !LearningEvidenceContract.validIdentifier(sessionId) ||
          wordId is! String ||
          !LearningEvidenceContract.validIdentifier(wordId) ||
          promptMode is! String ||
          !LearningEvidenceContract.validText(
            promptMode,
            maxLength: LearningEvidenceContract.maxPromptModeLength,
          ) ||
          payload['isCorrect'] is! bool ||
          (responseTimeMs != null &&
              (responseTimeMs is! int ||
                  responseTimeMs < 0 ||
                  responseTimeMs >
                      LearningEvidenceContract.maxResponseTimeMs)) ||
          attemptNumber is! int ||
          attemptNumber <= 0 ||
          attemptNumber > LearningEvidenceContract.maxAttemptNumber ||
          occurredAtUtcMs is! int ||
          occurredAtUtcMs < 0 ||
          (provenance != null &&
              (provenance is! String ||
                  provenance.runes.length >
                      LearningEvidenceContract.maxProviderProvenanceLength))) {
        throw const InvalidSyncPayloadFailure();
      }
      final context = payloadVersion == 1
          ? LearningEvidenceContract.frozenV13LegacyEvidenceContext()
          : EvidenceContext.fromJson(
              (payload['evidenceContext'] as Map).cast<String, Object?>(),
            );
      if ((payloadVersion == 2 &&
              (context.classificationSource !=
                      EvidenceClassificationSource.declared ||
                  payload['evidenceClass'] != context.evidenceClass.name)) ||
          !LearningEvidenceContract.isOrdinaryEvidence(context)) {
        throw const InvalidSyncPayloadFailure();
      }
      return context;
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }
}

extension SyncCollectionWireName on SyncCollection {
  String get wireName => switch (this) {
    SyncCollection.categories => 'categories',
    SyncCollection.words => 'words',
    SyncCollection.attempts => 'attempts',
    SyncCollection.readingEvents => 'reading_events',
    SyncCollection.rewardTransactions => 'reward_transactions',
    SyncCollection.srsStates => 'srs_states',
    SyncCollection.achievementUnlocks => 'achievement_unlocks',
  };

  String get entityType => switch (this) {
    SyncCollection.categories => 'category',
    SyncCollection.words => 'word',
    SyncCollection.attempts => 'attempt',
    SyncCollection.readingEvents => 'readingEvent',
    SyncCollection.rewardTransactions => 'rewardTransaction',
    SyncCollection.srsStates => 'srsState',
    SyncCollection.achievementUnlocks => 'achievementUnlock',
  };
}

enum SyncOperationKind { upsert, delete }

final class SyncCursor {
  SyncCursor({required this.serverUpdatedAtUtc, required String documentId})
    : documentId = _requiredId(documentId, 'documentId') {
    _requireUtc(serverUpdatedAtUtc, 'serverUpdatedAtUtc');
  }

  factory SyncCursor.parse(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?> ||
          decoded.length != 2 ||
          decoded['serverUpdatedAtUtcMicros'] is! int ||
          decoded['documentId'] is! String) {
        throw const InvalidSyncCursorFailure();
      }
      return SyncCursor(
        serverUpdatedAtUtc: DateTime.fromMicrosecondsSinceEpoch(
          decoded['serverUpdatedAtUtcMicros']! as int,
          isUtc: true,
        ),
        documentId: decoded['documentId']! as String,
      );
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncCursorFailure();
    }
  }

  final DateTime serverUpdatedAtUtc;
  final String documentId;

  String toJsonString() => jsonEncode(<String, Object?>{
    'serverUpdatedAtUtcMicros': serverUpdatedAtUtc.microsecondsSinceEpoch,
    'documentId': documentId,
  });

  @override
  bool operator ==(Object other) =>
      other is SyncCursor &&
      other.serverUpdatedAtUtc == serverUpdatedAtUtc &&
      other.documentId == documentId;

  @override
  int get hashCode => Object.hash(serverUpdatedAtUtc, documentId);
}

final class PushMutation {
  PushMutation({
    required String operationId,
    required String firebaseUid,
    required this.collection,
    required String entityId,
    required this.operationKind,
    required this.payloadVersion,
    required this.baseRevision,
    required this.localRevision,
    required this.clientUpdatedAtUtc,
    required Map<String, Object?> payload,
  }) : operationId = _requiredId(operationId, 'operationId'),
       firebaseUid = _requiredId(firebaseUid, 'firebaseUid'),
       entityId = _requiredId(entityId, 'entityId'),
       payload = Map<String, Object?>.unmodifiable(payload) {
    _requirePayloadVersion(payloadVersion, collection);
    _requireRevision(baseRevision, 'baseRevision', allowZero: true);
    _requireRevision(localRevision, 'localRevision');
    if (localRevision <= baseRevision) {
      throw ArgumentError.value(
        localRevision,
        'localRevision',
        'must be greater than baseRevision',
      );
    }
    _requireUtc(clientUpdatedAtUtc, 'clientUpdatedAtUtc');
    _requireJsonSafe(payload);
  }

  final String operationId;
  final String firebaseUid;
  final SyncCollection collection;
  final String entityId;
  final SyncOperationKind operationKind;
  final int payloadVersion;
  final int baseRevision;
  final int localRevision;
  final DateTime clientUpdatedAtUtc;
  final Map<String, Object?> payload;
}

final class SyncEntity {
  SyncEntity({
    required this.collection,
    required String entityId,
    required this.revision,
    required this.isDeleted,
    required this.payloadVersion,
    required this.clientUpdatedAtUtc,
    required this.serverUpdatedAtUtc,
    required Map<String, Object?> payload,
  }) : entityId = _requiredId(entityId, 'entityId'),
       payload = Map<String, Object?>.unmodifiable(payload) {
    _requirePayloadVersion(payloadVersion, collection);
    _requireRevision(revision, 'revision');
    _requireUtc(clientUpdatedAtUtc, 'clientUpdatedAtUtc');
    _requireUtc(serverUpdatedAtUtc, 'serverUpdatedAtUtc');
    _requireJsonSafe(payload);
  }

  final SyncCollection collection;
  final String entityId;
  final int revision;
  final bool isDeleted;
  final int payloadVersion;
  final DateTime clientUpdatedAtUtc;
  final DateTime serverUpdatedAtUtc;
  final Map<String, Object?> payload;
}

void _requirePayloadVersion(int value, SyncCollection collection) {
  if (!supportsSyncPayloadVersion(collection, value)) {
    throw const UnsupportedSyncSchemaFailure();
  }
}

void _requireRevision(int value, String field, {bool allowZero = false}) {
  final minimum = allowZero ? 0 : 1;
  if (value < minimum) {
    throw ArgumentError.value(value, field, 'must be at least $minimum');
  }
}

void _requireUtc(DateTime value, String field) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, field, 'must be UTC');
  }
}

String _requiredId(String value, String field) {
  final canonical = value.trim();
  if (canonical.isEmpty || canonical.length > 256) {
    throw ArgumentError.value(value, field, 'must contain 1-256 characters');
  }
  return canonical;
}

void _requireJsonSafe(Map<String, Object?> payload) {
  if (!_isJsonSafe(payload)) {
    throw const InvalidSyncPayloadFailure();
  }
}

bool _isJsonSafe(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return true;
  }
  if (value is double) return value.isFinite;
  if (value is List<Object?>) return value.every(_isJsonSafe);
  if (value is Map<Object?, Object?>) {
    return value.entries.every(
      (entry) => entry.key is String && _isJsonSafe(entry.value),
    );
  }
  return false;
}
