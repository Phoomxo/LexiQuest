import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../product/feature_contract/feature_contract_digest.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import '../../research/domain/research_protocol_mode_catalog.dart';
import 'sync_failure.dart';

const int currentCloudSyncPolicySchemaVersion = 1;
const String answerAttemptV2RulesRevision = 'answer-attempt-v2-r1';
const String vocabularyWordV2RulesRevision = 'vocabulary-word-v2-r1';
const String experimentAssignmentV1RulesRevision =
    'experiment-assignment-v1-r1';
const String assessmentRunV1RulesRevision = 'assessment-run-v1-r1';
const String savedLearningItemV1RulesRevision = 'saved-learning-item-v1-r1';
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

  /// Revisioned assessment-run audit state. Controlled responses remain in
  /// canonical AnswerAttempts and are never duplicated in this collection.
  assessmentRuns,

  /// Mutable bookmark intent pinned to an immutable content revision.
  savedLearningItems,
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
    SyncCollection.assessmentRuns => 'assessment_runs',
    SyncCollection.savedLearningItems => 'saved_learning_items',
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
    SyncCollection.assessmentRuns => 'assessmentRun',
    SyncCollection.savedLearningItems => 'savedLearningItem',
  };

  Set<int> get supportedPayloadVersions => switch (this) {
    SyncCollection.words || SyncCollection.attempts => const <int>{1, 2},
    SyncCollection.categories ||
    SyncCollection.readingEvents ||
    SyncCollection.rewardTransactions ||
    SyncCollection.srsStates ||
    SyncCollection.achievementUnlocks ||
    SyncCollection.experimentAssignments ||
    SyncCollection.assessmentRuns => const <int>{1},
    SyncCollection.savedLearningItems => const <int>{1},
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
  const SyncPayloadRollout.productionDefault()
    : answerAttemptWriteVersion = 1,
      vocabularyWordRulesRevision = legacyFirestoreRulesRevision;

  const SyncPayloadRollout.answerAttemptV2()
    : answerAttemptWriteVersion = 2,
      vocabularyWordRulesRevision = legacyFirestoreRulesRevision;

  const SyncPayloadRollout.vocabularyWordV2({
    required this.vocabularyWordRulesRevision,
  }) : answerAttemptWriteVersion = 1;

  final int answerAttemptWriteVersion;
  final String vocabularyWordRulesRevision;

  int writeVersionFor(SyncCollection collection) => switch (collection) {
    SyncCollection.attempts => answerAttemptWriteVersion,
    SyncCollection.words =>
      vocabularyWordRulesRevision == vocabularyWordV2RulesRevision ? 2 : 1,
    SyncCollection.categories ||
    SyncCollection.readingEvents ||
    SyncCollection.rewardTransactions ||
    SyncCollection.srsStates ||
    SyncCollection.achievementUnlocks ||
    SyncCollection.experimentAssignments ||
    SyncCollection.assessmentRuns => collection.defaultWritePayloadVersion,
    SyncCollection.savedLearningItems => collection.defaultWritePayloadVersion,
  };
}

/// Deployment gate for the separately deployed saved-item rules contract.
final class SavedLearningItemSyncRollout {
  const SavedLearningItemSyncRollout.off()
    : enabled = false,
      deployedRulesRevision = '';

  const SavedLearningItemSyncRollout.v1({required this.deployedRulesRevision})
    : enabled = true;

  final bool enabled;
  final String deployedRulesRevision;

  bool get allowsClaims =>
      enabled && deployedRulesRevision == savedLearningItemV1RulesRevision;
}

abstract final class SavedLearningItemSyncPayloadContract {
  static const Set<String> keys = <String>{
    'contentType',
    'contentId',
    'contentRevision',
    'savedAtUtcMs',
    'updatedAtUtcMs',
    'isDeleted',
  };

  static const Set<String> contentTypes = <String>{
    'learningPack',
    'lexicalMetadata',
    'assessmentForm',
    'offlineArtifact',
  };

  static String canonicalEntityId({
    required String contentType,
    required String contentId,
    required int contentRevision,
  }) {
    final identityBytes = utf8.encode(
      '$contentType|$contentId|$contentRevision',
    );
    return 'saved-learning-item:${sha256.convert(identityBytes)}';
  }

  static String canonicalOperationId({
    required String localOperationId,
    required String contentType,
    required String contentId,
    required int contentRevision,
    required SyncOperationKind operationKind,
    required int baseRevision,
    required int localRevision,
    required int savedAtUtcMs,
    required int updatedAtUtcMs,
  }) {
    final canonicalLocalOperationId = localOperationId.trim();
    if (canonicalLocalOperationId.isEmpty ||
        baseRevision < 0 ||
        localRevision <= baseRevision ||
        savedAtUtcMs < 0 ||
        updatedAtUtcMs < savedAtUtcMs) {
      throw ArgumentError('saved operation identity must be canonical');
    }
    final exactMutationIdentity = jsonEncode(<Object?>[
      1,
      canonicalLocalOperationId,
      canonicalEntityId(
        contentType: contentType,
        contentId: contentId,
        contentRevision: contentRevision,
      ),
      operationKind.name,
      baseRevision,
      localRevision,
      savedAtUtcMs,
      updatedAtUtcMs,
    ]);
    return 'saved-learning-operation:'
        '${sha256.convert(utf8.encode(exactMutationIdentity))}';
  }

  static void requireCanonical({
    required Map<String, Object?> payload,
    required bool isDeleted,
    required int clientUpdatedAtUtcMs,
    String? expectedEntityId,
  }) {
    try {
      final contentType = payload['contentType'];
      final contentId = payload['contentId'];
      final contentRevision = payload['contentRevision'];
      final savedAtUtcMs = payload['savedAtUtcMs'];
      final updatedAtUtcMs = payload['updatedAtUtcMs'];
      final payloadIsDeleted = payload['isDeleted'];
      if (payload.length != keys.length ||
          !payload.keys.every(keys.contains) ||
          contentType is! String ||
          !contentTypes.contains(contentType) ||
          contentId is! String ||
          contentId.isEmpty ||
          contentId != contentId.trim() ||
          contentId.runes.length > 256 ||
          contentRevision is! int ||
          contentRevision <= 0 ||
          savedAtUtcMs is! int ||
          savedAtUtcMs < 0 ||
          updatedAtUtcMs is! int ||
          updatedAtUtcMs < savedAtUtcMs ||
          updatedAtUtcMs != clientUpdatedAtUtcMs ||
          payloadIsDeleted is! bool ||
          payloadIsDeleted != isDeleted) {
        throw const InvalidSyncPayloadFailure();
      }
      if (expectedEntityId != null &&
          expectedEntityId !=
              canonicalEntityId(
                contentType: contentType,
                contentId: contentId,
                contentRevision: contentRevision,
              )) {
        throw const InvalidSyncPayloadFailure();
      }
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }
}

abstract final class VocabularyWordSyncPayloadContract {
  static const Set<String> payloadV1Keys = <String>{
    'categoryId',
    'spelling',
    'normalizedSpelling',
    'meaning',
    'normalizedMeaning',
    'partOfSpeech',
    'cefrLevel',
    'source',
    'isGlobal',
    'isDeleted',
    'createdAtUtcMs',
    'updatedAtUtcMs',
  };

  static const Set<String> payloadV2Keys = <String>{
    ...payloadV1Keys,
    'contentRevision',
    'contentChecksumSha256',
    'contentProvenance',
    'contentReviewState',
    'contentPublicationState',
  };

  static void requireCanonical({
    required int payloadVersion,
    required Map<String, Object?> payload,
    required bool isDeleted,
    required int clientUpdatedAtUtcMs,
  }) {
    if (payloadVersion != 1 && payloadVersion != 2) {
      throw const UnsupportedSyncSchemaFailure();
    }
    try {
      final expectedKeys = payloadVersion == 1 ? payloadV1Keys : payloadV2Keys;
      if (payload.length != expectedKeys.length ||
          !payload.keys.every(expectedKeys.contains) ||
          clientUpdatedAtUtcMs < 0) {
        throw const InvalidSyncPayloadFailure();
      }
      _requireLegacyShape(payload, isDeleted: isDeleted);
      if (payloadVersion == 1) return;

      for (final field in const <String>[
        'categoryId',
        'spelling',
        'normalizedSpelling',
        'meaning',
        'normalizedMeaning',
        'partOfSpeech',
        'source',
      ]) {
        final value = payload[field]! as String;
        if (value.isEmpty || value != value.trim()) {
          throw const InvalidSyncPayloadFailure();
        }
      }
      final cefrLevel = payload['cefrLevel'];
      final updatedAtUtcMs = payload['updatedAtUtcMs'];
      if ((cefrLevel != null &&
              (cefrLevel is! String ||
                  cefrLevel.isEmpty ||
                  cefrLevel != cefrLevel.trim() ||
                  cefrLevel.runes.length > 20)) ||
          payload['isGlobal'] != false ||
          updatedAtUtcMs != clientUpdatedAtUtcMs) {
        throw const InvalidSyncPayloadFailure();
      }
      final contentRevision = payload['contentRevision'];
      final checksum = payload['contentChecksumSha256'];
      final expectedChecksum = ContentQualityPolicy.vocabularyChecksumSha256(
        categoryId: payload['categoryId']! as String,
        spelling: payload['spelling']! as String,
        normalizedSpelling: payload['normalizedSpelling']! as String,
        meaning: payload['meaning']! as String,
        normalizedMeaning: payload['normalizedMeaning']! as String,
        partOfSpeech: payload['partOfSpeech']! as String,
        cefrLevel: cefrLevel as String?,
        source: payload['source']! as String,
        isGlobal: payload['isGlobal']! as bool,
      );
      if (contentRevision is! int ||
          contentRevision <= 0 ||
          checksum is! String ||
          checksum != expectedChecksum ||
          payload['contentProvenance'] != 'userAuthored' ||
          payload['contentReviewState'] != 'unreviewed' ||
          payload['contentPublicationState'] != 'private') {
        throw const InvalidSyncPayloadFailure();
      }
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static void _requireLegacyShape(
    Map<String, Object?> payload, {
    required bool isDeleted,
  }) {
    void requireText(
      String field, {
      required int maximumLength,
      required bool allowEmpty,
    }) {
      final value = payload[field];
      if (value is! String ||
          (!allowEmpty && value.isEmpty) ||
          value.runes.length > maximumLength) {
        throw const InvalidSyncPayloadFailure();
      }
    }

    requireText('categoryId', maximumLength: 256, allowEmpty: false);
    requireText('spelling', maximumLength: 200, allowEmpty: false);
    requireText('normalizedSpelling', maximumLength: 200, allowEmpty: false);
    requireText('meaning', maximumLength: 1000, allowEmpty: false);
    requireText('normalizedMeaning', maximumLength: 1000, allowEmpty: false);
    requireText('partOfSpeech', maximumLength: 60, allowEmpty: true);
    requireText('source', maximumLength: 60, allowEmpty: false);
    final cefrLevel = payload['cefrLevel'];
    final payloadIsDeleted = payload['isDeleted'];
    final createdAtUtcMs = payload['createdAtUtcMs'];
    final updatedAtUtcMs = payload['updatedAtUtcMs'];
    if ((cefrLevel != null &&
            (cefrLevel is! String || cefrLevel.runes.length > 20)) ||
        payload['isGlobal'] is! bool ||
        payloadIsDeleted is! bool ||
        payloadIsDeleted != isDeleted ||
        createdAtUtcMs is! int ||
        createdAtUtcMs < 0 ||
        updatedAtUtcMs is! int ||
        updatedAtUtcMs < createdAtUtcMs) {
      throw const InvalidSyncPayloadFailure();
    }
  }
}

/// Delivery gate for immutable research collections.
///
/// This is deliberately independent from product visibility and assignment
/// creation. Local assignment persistence never enables cloud delivery.
final class ResearchCollectionSyncRollout {
  const ResearchCollectionSyncRollout.off()
    : enabled = false,
      deployedRulesRevision = '',
      _experimentAssignmentRulesRevision = '',
      _assessmentRunRulesRevision = '',
      protocolModeCatalog = null,
      _experimentAssignmentsEnabled = false,
      _assessmentRunsEnabled = false,
      _combinedRulesRequired = false;

  const ResearchCollectionSyncRollout.experimentAssignmentsV1({
    required this.deployedRulesRevision,
    this.protocolModeCatalog,
    @Deprecated('Ignored. A protocolModeCatalog is required for claims.')
    int? consentVersion,
  }) : enabled = true,
       _experimentAssignmentRulesRevision = deployedRulesRevision,
       _assessmentRunRulesRevision = '',
       _experimentAssignmentsEnabled = true,
       _assessmentRunsEnabled = false,
       _combinedRulesRequired = false;

  const ResearchCollectionSyncRollout.assessmentRunsV1({
    required this.deployedRulesRevision,
    required this.protocolModeCatalog,
  }) : enabled = true,
       _experimentAssignmentRulesRevision = '',
       _assessmentRunRulesRevision = deployedRulesRevision,
       _experimentAssignmentsEnabled = false,
       _assessmentRunsEnabled = true,
       _combinedRulesRequired = false;

  const ResearchCollectionSyncRollout.researchAssessmentV1({
    required String deployedExperimentAssignmentRulesRevision,
    required String deployedAssessmentRunRulesRevision,
    required this.protocolModeCatalog,
  }) : enabled = true,
       deployedRulesRevision = '',
       _experimentAssignmentRulesRevision =
           deployedExperimentAssignmentRulesRevision,
       _assessmentRunRulesRevision = deployedAssessmentRunRulesRevision,
       _experimentAssignmentsEnabled = true,
       _assessmentRunsEnabled = true,
       _combinedRulesRequired = true;

  final bool enabled;
  final String deployedRulesRevision;
  final ResearchProtocolModeCatalog? protocolModeCatalog;
  final String _experimentAssignmentRulesRevision;
  final String _assessmentRunRulesRevision;
  final bool _experimentAssignmentsEnabled;
  final bool _assessmentRunsEnabled;
  final bool _combinedRulesRequired;

  bool get _combinedRulesAreExact =>
      !_combinedRulesRequired ||
      (_experimentAssignmentRulesRevision ==
              experimentAssignmentV1RulesRevision &&
          _assessmentRunRulesRevision == assessmentRunV1RulesRevision);

  bool get allowsExperimentAssignmentClaims =>
      enabled &&
      _experimentAssignmentsEnabled &&
      _experimentAssignmentRulesRevision ==
          experimentAssignmentV1RulesRevision &&
      _combinedRulesAreExact &&
      protocolModeCatalog != null;

  bool get allowsAssessmentRunClaims =>
      enabled &&
      _combinedRulesRequired &&
      _experimentAssignmentsEnabled &&
      _assessmentRunsEnabled &&
      _assessmentRunRulesRevision == assessmentRunV1RulesRevision &&
      _combinedRulesAreExact &&
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

abstract final class AssessmentRunSyncPayloadContract {
  static const Set<String> keys = <String>{
    'runId',
    'ownerId',
    'learningSessionId',
    'studyCycleId',
    'phase',
    'state',
    'protocolId',
    'protocolVersion',
    'experimentId',
    'experimentVersion',
    'assignmentId',
    'cohort',
    'consentVersion',
    'consentDecidedAtUtcMs',
    'instrumentId',
    'instrumentVersion',
    'formId',
    'formVersion',
    'instrumentChecksumSha256',
    'formChecksumSha256',
    'appVersion',
    'buildId',
    'databaseSchemaVersion',
    'contentRevision',
    'evidencePolicyVersion',
    'featureContractRevision',
    'featureContractHash',
    'startedAtUtcMs',
    'completedAtUtcMs',
    'abandonedAtUtcMs',
  };

  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  static void requireCanonical({
    required Map<String, Object?> payload,
    required String expectedEntityId,
    String? expectedOwnerId,
    required int revision,
    required bool isDeleted,
    required int clientUpdatedAtUtcMs,
  }) {
    try {
      if (payload.length != keys.length ||
          !payload.keys.every(keys.contains) ||
          isDeleted ||
          clientUpdatedAtUtcMs < 0) {
        throw const InvalidSyncPayloadFailure();
      }
      final runId = _canonicalText(payload, 'runId');
      final ownerId = _canonicalText(payload, 'ownerId');
      final phase = _canonicalText(payload, 'phase');
      final state = _canonicalText(payload, 'state');
      final experimentVersion = _positiveInt(payload, 'experimentVersion');
      final consentVersion = _positiveInt(payload, 'consentVersion');
      final databaseSchemaVersion = _positiveInt(
        payload,
        'databaseSchemaVersion',
      );
      final evidencePolicyVersion = _canonicalText(
        payload,
        'evidencePolicyVersion',
      );
      final featureContractRevision = _canonicalText(
        payload,
        'featureContractRevision',
      );
      final featureContractHash = payload['featureContractHash'];
      final consentDecidedAtUtcMs = _nonNegativeInt(
        payload,
        'consentDecidedAtUtcMs',
      );
      final startedAtUtcMs = _nonNegativeInt(payload, 'startedAtUtcMs');
      final completedAtUtcMs = _optionalNonNegativeInt(
        payload,
        'completedAtUtcMs',
      );
      final abandonedAtUtcMs = _optionalNonNegativeInt(
        payload,
        'abandonedAtUtcMs',
      );
      for (final field in const <String>[
        'learningSessionId',
        'studyCycleId',
        'protocolId',
        'protocolVersion',
        'experimentId',
        'assignmentId',
        'cohort',
        'instrumentId',
        'instrumentVersion',
        'formId',
        'formVersion',
        'appVersion',
        'buildId',
        'contentRevision',
        'evidencePolicyVersion',
        'featureContractRevision',
      ]) {
        _canonicalText(payload, field);
      }
      for (final field in const <String>[
        'instrumentChecksumSha256',
        'formChecksumSha256',
        'featureContractHash',
      ]) {
        final digest = payload[field];
        if (digest is! String || !_sha256.hasMatch(digest)) {
          throw const InvalidSyncPayloadFailure();
        }
      }
      if (runId != expectedEntityId ||
          (expectedOwnerId != null && ownerId != expectedOwnerId) ||
          !const <String>{'pre', 'post'}.contains(phase) ||
          experimentVersion <= 0 ||
          consentVersion <= 0 ||
          !const <int>{15, 16, 17}.contains(databaseSchemaVersion) ||
          evidencePolicyVersion != EvidenceContext.currentPolicyVersion ||
          featureContractHash is! String ||
          !supportedFeatureContractIdentities.any(
            (identity) =>
                identity.revision == featureContractRevision &&
                identity.semanticHash == featureContractHash,
          ) ||
          consentDecidedAtUtcMs > startedAtUtcMs) {
        throw const InvalidSyncPayloadFailure();
      }
      switch (state) {
        case 'active':
          if (revision != 1 ||
              completedAtUtcMs != null ||
              abandonedAtUtcMs != null ||
              clientUpdatedAtUtcMs != startedAtUtcMs) {
            throw const InvalidSyncPayloadFailure();
          }
          return;
        case 'completed':
          if (revision != 2 ||
              completedAtUtcMs == null ||
              abandonedAtUtcMs != null ||
              completedAtUtcMs < startedAtUtcMs ||
              clientUpdatedAtUtcMs != completedAtUtcMs) {
            throw const InvalidSyncPayloadFailure();
          }
          return;
        case 'abandoned':
          if (revision != 2 ||
              abandonedAtUtcMs == null ||
              completedAtUtcMs != null ||
              abandonedAtUtcMs < startedAtUtcMs ||
              clientUpdatedAtUtcMs != abandonedAtUtcMs) {
            throw const InvalidSyncPayloadFailure();
          }
          return;
        default:
          throw const InvalidSyncPayloadFailure();
      }
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static String _canonicalText(Map<String, Object?> payload, String field) {
    final value = payload[field];
    if (value is! String || !_canonicalAssignmentText(value)) {
      throw const InvalidSyncPayloadFailure();
    }
    return value;
  }

  static int _positiveInt(Map<String, Object?> payload, String field) {
    final value = payload[field];
    if (value is! int || value <= 0) {
      throw const InvalidSyncPayloadFailure();
    }
    return value;
  }

  static int _nonNegativeInt(Map<String, Object?> payload, String field) {
    final value = payload[field];
    if (value is! int || value < 0) {
      throw const InvalidSyncPayloadFailure();
    }
    return value;
  }

  static int? _optionalNonNegativeInt(
    Map<String, Object?> payload,
    String field,
  ) {
    final value = payload[field];
    if (value == null) return null;
    if (value is! int || value < 0) {
      throw const InvalidSyncPayloadFailure();
    }
    return value;
  }
}

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
