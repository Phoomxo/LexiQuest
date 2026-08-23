import 'dart:convert';

import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../research/domain/research_protocol_mode_catalog.dart';
import 'sync_failure.dart';

const int currentCloudSyncPolicySchemaVersion = 1;
const String answerAttemptV2RulesRevision = 'answer-attempt-v2-r1';
const String experimentAssignmentV1RulesRevision =
    'experiment-assignment-v1-r1';
const String legacyFirestoreRulesRevision = 'legacy-v1';

enum SyncCollection {
  categories,
  words,
  attempts,
  readingEvents,
  rewardTransactions,

  /// Mutable FSRS algorithm state per (owner, word).
  /// Pull semantics: last-write-wins (server state replaces local).
  /// Phase 0 Week 12-13.
  srsStates,

  /// Immutable append-only achievement unlock records.
  /// Pull semantics: insertOrIgnore (once unlocked, never revoked).
  /// Phase 0 Week 12-13.
  achievementUnlocks,

  /// Immutable, explicitly assigned research cohort audit evidence.
  experimentAssignments,
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
    SyncCollection.experimentAssignments => 'experiment_assignments',
  };

  String get entityType => switch (this) {
    SyncCollection.categories => 'category',
    SyncCollection.words => 'word',
    SyncCollection.attempts => 'attempt',
    SyncCollection.readingEvents => 'readingEvent',
    SyncCollection.rewardTransactions => 'rewardTransaction',
    SyncCollection.srsStates => 'srsState',
    SyncCollection.achievementUnlocks => 'achievementUnlock',
    SyncCollection.experimentAssignments => 'experimentAssignment',
  };

  Set<int> get supportedPayloadVersions => switch (this) {
    SyncCollection.attempts => const <int>{1, 2},
    SyncCollection.categories ||
    SyncCollection.words ||
    SyncCollection.readingEvents ||
    SyncCollection.rewardTransactions ||
    SyncCollection.srsStates ||
    SyncCollection.achievementUnlocks ||
    SyncCollection.experimentAssignments => const <int>{1},
  };

  int get defaultWritePayloadVersion => 1;

  bool supportsPayloadVersion(int value) =>
      supportedPayloadVersions.contains(value);

  void requireSupportedPayloadVersion(int value) {
    if (!supportsPayloadVersion(value)) {
      throw const UnsupportedSyncSchemaFailure();
    }
  }
}

final class SyncPayloadRollout {
  const SyncPayloadRollout.productionDefault() : answerAttemptWriteVersion = 1;

  const SyncPayloadRollout.answerAttemptV2() : answerAttemptWriteVersion = 2;

  final int answerAttemptWriteVersion;

  int writeVersionFor(SyncCollection collection) => switch (collection) {
    SyncCollection.attempts => answerAttemptWriteVersion,
    SyncCollection.categories ||
    SyncCollection.words ||
    SyncCollection.readingEvents ||
    SyncCollection.rewardTransactions ||
    SyncCollection.srsStates ||
    SyncCollection.achievementUnlocks ||
    SyncCollection.experimentAssignments =>
      collection.defaultWritePayloadVersion,
  };
}

/// Delivery gate for immutable research collections.
///
/// This is deliberately independent from product visibility and assignment
/// creation. Local assignment persistence never enables cloud delivery.
final class ResearchCollectionSyncRollout {
  const ResearchCollectionSyncRollout.off()
    : enabled = false,
      deployedRulesRevision = '',
      protocolModeCatalog = null;

  const ResearchCollectionSyncRollout.experimentAssignmentsV1({
    required this.deployedRulesRevision,
    this.protocolModeCatalog,
    @Deprecated('Ignored. A protocolModeCatalog is required for claims.')
    int? consentVersion,
  }) : enabled = true;

  final bool enabled;
  final String deployedRulesRevision;
  final ResearchProtocolModeCatalog? protocolModeCatalog;

  bool get allowsExperimentAssignmentClaims =>
      enabled &&
      deployedRulesRevision == experimentAssignmentV1RulesRevision &&
      protocolModeCatalog != null;
}

abstract final class ExperimentAssignmentSyncPayloadContract {
  static const Set<String> keys = <String>{
    'assignmentId',
    'ownerId',
    'experimentId',
    'experimentVersion',
    'cohort',
    'protocolVersion',
    'assignedAtUtcMs',
  };

  static void requireCanonical({
    required Map<String, Object?> payload,
    required String expectedEntityId,
    String? expectedOwnerId,
    int? expectedAssignedAtUtcMs,
  }) {
    final assignmentId = payload['assignmentId'];
    final ownerId = payload['ownerId'];
    final experimentId = payload['experimentId'];
    final experimentVersion = payload['experimentVersion'];
    final cohort = payload['cohort'];
    final protocolVersion = payload['protocolVersion'];
    final assignedAtUtcMs = payload['assignedAtUtcMs'];
    if (payload.length != keys.length ||
        !payload.keys.every(keys.contains) ||
        assignmentId is! String ||
        !_canonicalAssignmentText(assignmentId) ||
        assignmentId != expectedEntityId ||
        ownerId is! String ||
        !_canonicalAssignmentText(ownerId) ||
        (expectedOwnerId != null && ownerId != expectedOwnerId) ||
        experimentId is! String ||
        !_canonicalAssignmentText(experimentId) ||
        experimentVersion is! int ||
        experimentVersion <= 0 ||
        cohort is! String ||
        !_canonicalAssignmentText(cohort) ||
        protocolVersion is! String ||
        !_canonicalAssignmentText(protocolVersion) ||
        assignedAtUtcMs is! int ||
        assignedAtUtcMs < 0 ||
        (expectedAssignedAtUtcMs != null &&
            assignedAtUtcMs != expectedAssignedAtUtcMs)) {
      throw const InvalidSyncPayloadFailure();
    }
  }
}

bool _canonicalAssignmentText(String value) =>
    value.isNotEmpty && value == value.trim() && value.runes.length <= 256;

abstract final class AnswerAttemptSyncPayloadContract {
  static EvidenceContext requireEvidenceContext({
    required int payloadVersion,
    required Map<String, Object?> payload,
  }) {
    try {
      final expectedKeys = switch (payloadVersion) {
        1 => _payloadV1Keys,
        2 => _payloadV2Keys,
        _ => throw const UnsupportedSyncSchemaFailure(),
      };
      if (payload.length != expectedKeys.length ||
          !payload.keys.every(expectedKeys.contains) ||
          !_validCommonFields(payload)) {
        throw const InvalidSyncPayloadFailure();
      }
      if (payloadVersion == 1) {
        return LearningEvidenceContract.frozenV13LegacyEvidenceContext();
      }

      final topLevelClass = payload['evidenceClass'];
      final serializedContext = payload['evidenceContext'];
      if (topLevelClass is! String || serializedContext is! Map) {
        throw const InvalidSyncPayloadFailure();
      }
      final context = EvidenceContext.fromJson(
        serializedContext.cast<String, Object?>(),
      );
      if (context.classificationSource !=
              EvidenceClassificationSource.declared ||
          topLevelClass != context.evidenceClass.name) {
        throw const InvalidSyncPayloadFailure();
      }
      return context;
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static bool _validCommonFields(Map<String, Object?> payload) {
    final sessionId = payload['sessionId'];
    final wordId = payload['wordId'];
    final promptMode = payload['promptMode'];
    final isCorrect = payload['isCorrect'];
    final responseTimeMs = payload['responseTimeMs'];
    final attemptNumber = payload['attemptNumber'];
    final occurredAtUtcMs = payload['occurredAtUtcMs'];
    final providerProvenance = payload['providerProvenance'];
    return sessionId is String &&
        LearningEvidenceContract.validIdentifier(sessionId) &&
        wordId is String &&
        LearningEvidenceContract.validIdentifier(wordId) &&
        promptMode is String &&
        LearningEvidenceContract.validText(
          promptMode,
          maxLength: LearningEvidenceContract.maxPromptModeLength,
        ) &&
        isCorrect is bool &&
        (responseTimeMs == null ||
            (responseTimeMs is int &&
                responseTimeMs >= 0 &&
                responseTimeMs <=
                    LearningEvidenceContract.maxResponseTimeMs)) &&
        attemptNumber is int &&
        attemptNumber > 0 &&
        attemptNumber <= LearningEvidenceContract.maxAttemptNumber &&
        occurredAtUtcMs is int &&
        occurredAtUtcMs >= 0 &&
        (providerProvenance == null ||
            (providerProvenance is String &&
                providerProvenance.runes.length <=
                    LearningEvidenceContract.maxProviderProvenanceLength));
  }

  static const Set<String> _payloadV1Keys = <String>{
    'sessionId',
    'wordId',
    'promptMode',
    'isCorrect',
    'responseTimeMs',
    'attemptNumber',
    'occurredAtUtcMs',
    'providerProvenance',
  };

  static const Set<String> _payloadV2Keys = <String>{
    ..._payloadV1Keys,
    'evidenceClass',
    'evidenceContext',
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
    collection.requireSupportedPayloadVersion(payloadVersion);
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
    collection.requireSupportedPayloadVersion(payloadVersion);
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
