import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../product/feature_contract/feature_contract_digest.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import '../../goals/domain/learning_goal.dart';
import '../../research/domain/research_protocol_mode_catalog.dart';
import '../../review/domain/content_quality_report.dart';
import '../../time_tracking/domain/learning_time_segment.dart';
import 'sync_failure.dart';

const int currentCloudSyncPolicySchemaVersion = 1;
const String answerAttemptV2RulesRevision = 'answer-attempt-v2-r1';
const String vocabularyWordV2RulesRevision = 'vocabulary-word-v2-r1';
const String experimentAssignmentV1RulesRevision =
    'experiment-assignment-v1-r1';
const String assessmentRunV1RulesRevision = 'assessment-run-v1-r2';
const String savedLearningItemV1RulesRevision = 'saved-learning-item-v1-r1';
const String contentQualityReportV1RulesRevision =
    'content-quality-report-v1-r1';
const String learningTimeSegmentV1RulesRevision = 'learning-time-segment-v1-r1';
const String learningGoalV1RulesRevision = 'learning-goal-v1-r1';
const String learnerPreferenceV1RulesRevision = 'learner-preference-v1-r1';
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

  /// Immutable learner-submitted quality report pinned to content revision.
  contentQualityReports,

  /// Immutable monotonic active-effort segment with separate wall context.
  learningTimeSegments,

  /// Mutable owner-scoped language-learning deadline intent.
  learningGoals,

  /// Mutable owner-scoped editable learning defaults. This is deliberately
  /// separate from experiment assignment authority.
  learnerPreferences,
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
    SyncCollection.contentQualityReports => 'content_quality_reports',
    SyncCollection.learningTimeSegments => 'learning_time_segments',
    SyncCollection.learningGoals => 'learning_goals',
    SyncCollection.learnerPreferences => 'learner_preferences',
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
    SyncCollection.contentQualityReports => 'contentQualityReport',
    SyncCollection.learningTimeSegments => 'learningTimeSegment',
    SyncCollection.learningGoals => 'learningGoal',
    SyncCollection.learnerPreferences => 'learnerPreference',
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
    SyncCollection.contentQualityReports => const <int>{1},
    SyncCollection.learningTimeSegments => const <int>{1},
    SyncCollection.learningGoals => const <int>{1},
    SyncCollection.learnerPreferences => const <int>{1},
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
    SyncCollection.contentQualityReports =>
      collection.defaultWritePayloadVersion,
    SyncCollection.learningTimeSegments =>
      collection.defaultWritePayloadVersion,
    SyncCollection.learningGoals => collection.defaultWritePayloadVersion,
    SyncCollection.learnerPreferences => collection.defaultWritePayloadVersion,
  };
}

final class LearnerPreferenceSyncRollout {
  const LearnerPreferenceSyncRollout.off()
    : enabled = false,
      deployedRulesRevision = '';

  const LearnerPreferenceSyncRollout.v1({required this.deployedRulesRevision})
    : enabled = true;

  final bool enabled;
  final String deployedRulesRevision;

  bool get allowsClaims =>
      enabled && deployedRulesRevision == learnerPreferenceV1RulesRevision;
}

abstract final class LearnerPreferenceSyncPayloadContract {
  static const String canonicalEntityId = 'current';
  static const Set<String> keys = <String>{
    'ownerId',
    'preferenceVersion',
    'goal',
    'availableMinutesPerDay',
    'activityPreference',
    'updatedAtUtcMs',
  };
  static const Set<String> goals = <String>{
    'balancedGrowth',
    'examPreparation',
    'conversationConfidence',
    'vocabularyGrowth',
  };
  static const Set<String> activities = <String>{
    'mixedPractice',
    'quiz',
    'speaking',
    'reading',
    'vocabulary',
  };

  static String canonicalOperationId({
    required Map<String, Object?> payload,
    required int baseRevision,
    required int resultingRevision,
  }) {
    final preferenceVersion = payload['preferenceVersion'];
    final goal = payload['goal'];
    final availableMinutesPerDay = payload['availableMinutesPerDay'];
    final activityPreference = payload['activityPreference'];
    final updatedAtUtcMs = payload['updatedAtUtcMs'];
    if (preferenceVersion is! int ||
        preferenceVersion != 1 ||
        goal is! String ||
        !goals.contains(goal) ||
        availableMinutesPerDay is! int ||
        availableMinutesPerDay < 1 ||
        availableMinutesPerDay > 240 ||
        activityPreference is! String ||
        !activities.contains(activityPreference) ||
        updatedAtUtcMs is! int ||
        updatedAtUtcMs < 0 ||
        baseRevision < 0 ||
        resultingRevision != baseRevision + 1) {
      throw const InvalidSyncPayloadFailure();
    }
    final identity = <Object>[
      'v1',
      preferenceVersion,
      goal,
      availableMinutesPerDay,
      activityPreference,
      updatedAtUtcMs,
      baseRevision,
      resultingRevision,
    ].join('|');
    return 'learner-preference-operation:v1:'
        '${sha256.convert(utf8.encode(identity))}';
  }

  static void requireCanonical({
    required Map<String, Object?> payload,
    required String expectedEntityId,
    required String expectedOwnerId,
    required bool isDeleted,
    required int clientUpdatedAtUtcMs,
  }) {
    if (isDeleted ||
        expectedEntityId != canonicalEntityId ||
        payload.length != keys.length ||
        !payload.keys.every(keys.contains)) {
      throw const InvalidSyncPayloadFailure();
    }
    final ownerId = payload['ownerId'];
    final preferenceVersion = payload['preferenceVersion'];
    final goal = payload['goal'];
    final availableMinutesPerDay = payload['availableMinutesPerDay'];
    final activityPreference = payload['activityPreference'];
    final updatedAtUtcMs = payload['updatedAtUtcMs'];
    if (ownerId is! String ||
        ownerId != expectedOwnerId ||
        ownerId.isEmpty ||
        ownerId != ownerId.trim() ||
        preferenceVersion != 1 ||
        goal is! String ||
        !goals.contains(goal) ||
        availableMinutesPerDay is! int ||
        availableMinutesPerDay < 1 ||
        availableMinutesPerDay > 240 ||
        activityPreference is! String ||
        !activities.contains(activityPreference) ||
        updatedAtUtcMs is! int ||
        updatedAtUtcMs < 0 ||
        updatedAtUtcMs != clientUpdatedAtUtcMs) {
      throw const InvalidSyncPayloadFailure();
    }
  }
}

/// Canonical cloud identity for one immutable achievement-definition unlock.
///
/// Local unlock rows deliberately retain their owner-scoped physical ids so
/// owner lifecycle operations remain local. Cloud documents live below an
/// already owner-scoped Firebase UID, so their identity must not include the
/// device-local owner id. The operation identity includes the complete
/// immutable payload: equal evidence can replay one acknowledgement, while
/// competing offline evidence reaches the entity conflict path and converges
/// on the single durable cloud record.
abstract final class AchievementUnlockSyncPayloadContract {
  static const String _entityPrefix = 'achievement-unlock:v1:';
  static const String _operationPrefix = 'achievement-unlock-operation:v1:';

  static const Set<String> keys = <String>{
    'achievementId',
    'definitionVersion',
    'sourceEventId',
    'unlockedAtUtcMs',
  };

  static String canonicalEntityId({
    required String achievementId,
    required int definitionVersion,
  }) {
    _requireIdentifier(achievementId);
    if (definitionVersion < 0) throw const InvalidSyncPayloadFailure();
    return '$_entityPrefix${_digest(<Object?>[achievementId, definitionVersion])}';
  }

  static String canonicalOperationId({
    required String achievementId,
    required int definitionVersion,
    required String sourceEventId,
    required int unlockedAtUtcMs,
  }) {
    _requireIdentifier(achievementId);
    _requireIdentifier(sourceEventId);
    if (definitionVersion < 0 || unlockedAtUtcMs < 0) {
      throw const InvalidSyncPayloadFailure();
    }
    return '$_operationPrefix${_digest(<Object?>[achievementId, definitionVersion, sourceEventId, unlockedAtUtcMs])}';
  }

  /// Validates the exact immutable payload and canonical timestamp.
  ///
  /// A non-canonical entity id is accepted only as a frozen legacy physical
  /// id. Values claiming this contract's namespace must match the digest.
  static void requireCompatible({
    required Map<String, Object?> payload,
    required String entityId,
    required int clientUpdatedAtUtcMs,
  }) {
    if (payload.length != keys.length || !keys.every(payload.containsKey)) {
      throw const InvalidSyncPayloadFailure();
    }
    final achievementId = payload['achievementId'];
    final definitionVersion = payload['definitionVersion'];
    final sourceEventId = payload['sourceEventId'];
    final unlockedAtUtcMs = payload['unlockedAtUtcMs'];
    if (achievementId is! String ||
        definitionVersion is! int ||
        sourceEventId is! String ||
        unlockedAtUtcMs is! int) {
      throw const InvalidSyncPayloadFailure();
    }
    _requireIdentifier(achievementId);
    _requireIdentifier(sourceEventId);
    if (definitionVersion < 0 ||
        unlockedAtUtcMs < 0 ||
        unlockedAtUtcMs != clientUpdatedAtUtcMs) {
      throw const InvalidSyncPayloadFailure();
    }
    final canonical = canonicalEntityId(
      achievementId: achievementId,
      definitionVersion: definitionVersion,
    );
    if (entityId.startsWith(_entityPrefix) && entityId != canonical) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static bool isCanonicalEntityId({
    required String entityId,
    required String achievementId,
    required int definitionVersion,
  }) =>
      entityId ==
      canonicalEntityId(
        achievementId: achievementId,
        definitionVersion: definitionVersion,
      );

  static String _digest(List<Object?> components) =>
      sha256.convert(utf8.encode(jsonEncode(components))).toString();

  static void _requireIdentifier(String value) {
    if (value.isEmpty || value.trim() != value || value.runes.length > 256) {
      throw const InvalidSyncPayloadFailure();
    }
  }
}

/// Deploy-safe gate for learning-goal payload v1.
final class LearningGoalSyncRollout {
  const LearningGoalSyncRollout.off()
    : enabled = false,
      deployedRulesRevision = '';

  const LearningGoalSyncRollout.v1({required this.deployedRulesRevision})
    : enabled = true;

  final bool enabled;
  final String deployedRulesRevision;

  bool get allowsClaims =>
      enabled && deployedRulesRevision == learningGoalV1RulesRevision;
}

abstract final class LearningGoalSyncPayloadContract {
  static const Set<String> keys = <String>{
    'goalId',
    'kind',
    'title',
    'deadlineAtUtcMs',
    'timezoneId',
    'timezoneOffsetMinutes',
    'status',
    'createdAtUtcMs',
    'updatedAtUtcMs',
    'isDeleted',
  };

  static void requireCanonical({
    required Map<String, Object?> payload,
    required bool isDeleted,
    required int clientUpdatedAtUtcMs,
    String? expectedEntityId,
  }) {
    try {
      if (payload.length != keys.length || !payload.keys.every(keys.contains)) {
        throw const InvalidSyncPayloadFailure();
      }
      final goalId = payload['goalId'];
      final kind = payload['kind'];
      final title = payload['title'];
      final deadlineAtUtcMs = payload['deadlineAtUtcMs'];
      final timezoneId = payload['timezoneId'];
      final timezoneOffsetMinutes = payload['timezoneOffsetMinutes'];
      final status = payload['status'];
      final createdAtUtcMs = payload['createdAtUtcMs'];
      final updatedAtUtcMs = payload['updatedAtUtcMs'];
      final payloadIsDeleted = payload['isDeleted'];
      if (goalId is! String ||
          !_canonicalText(goalId, 256) ||
          expectedEntityId != null && expectedEntityId != goalId ||
          kind is! String ||
          !_goalKinds.contains(kind) ||
          title is! String ||
          !_canonicalText(title, 120) ||
          deadlineAtUtcMs is! int ||
          deadlineAtUtcMs < 0 ||
          timezoneId is! String ||
          timezoneOffsetMinutes is! int ||
          status is! String ||
          !_goalStatuses.contains(status) ||
          createdAtUtcMs is! int ||
          createdAtUtcMs < 0 ||
          updatedAtUtcMs is! int ||
          updatedAtUtcMs < createdAtUtcMs ||
          updatedAtUtcMs != clientUpdatedAtUtcMs ||
          payloadIsDeleted is! bool ||
          payloadIsDeleted != isDeleted) {
        throw const InvalidSyncPayloadFailure();
      }
      LearningGoal(
        id: goalId,
        kind: LearningGoalKindCodec.parse(kind),
        title: title,
        deadlineAtUtc: DateTime.fromMillisecondsSinceEpoch(
          deadlineAtUtcMs,
          isUtc: true,
        ),
        timezone: LearningGoalTimezoneContext(
          timezoneId: timezoneId,
          utcOffsetMinutes: timezoneOffsetMinutes,
        ),
        status: LearningGoalStatusCodec.parse(status),
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
          createdAtUtcMs,
          isUtc: true,
        ),
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          updatedAtUtcMs,
          isUtc: true,
        ),
      );
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static bool _canonicalText(String value, int maximumLength) =>
      value.isNotEmpty &&
      value == value.trim() &&
      value.runes.length <= maximumLength &&
      !value.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'));

  static const Set<String> _goalKinds = <String>{
    'languageTest',
    'course',
    'personal',
  };
  static const Set<String> _goalStatuses = <String>{
    'active',
    'completed',
    'cancelled',
  };
}

/// Deploy-safe gate for the immutable learning-time collection.
final class LearningTimeSegmentSyncRollout {
  const LearningTimeSegmentSyncRollout.off()
    : enabled = false,
      deployedRulesRevision = '';

  const LearningTimeSegmentSyncRollout.v1({required this.deployedRulesRevision})
    : enabled = true;

  final bool enabled;
  final String deployedRulesRevision;

  bool get allowsClaims =>
      enabled && deployedRulesRevision == learningTimeSegmentV1RulesRevision;
}

abstract final class LearningTimeSegmentSyncPayloadContract {
  static const int maximumActiveDurationMs = 300000;
  static const int maximumActiveOffsetMs = 315576000000;
  static const Set<String> keys = <String>{
    'segmentId',
    'sessionId',
    'activeStartOffsetMs',
    'activeDurationMs',
    'startedAtUtcMs',
    'endedAtUtcMs',
    'timezoneId',
    'timezoneOffsetMinutes',
    'captureSource',
  };
  static const Set<String> captureSources = <String>{
    'automaticLesson',
    'focusTimer',
  };

  static String canonicalEntityId({
    required String sessionId,
    required int activeStartOffsetMs,
    required String captureSource,
  }) {
    final source = LearningTimeCaptureSource.values
        .where((candidate) => candidate.name == captureSource)
        .firstOrNull;
    if (source == null) throw const InvalidSyncPayloadFailure();
    return LearningTimeSegment.canonicalId(
      sessionId: sessionId,
      activeStartOffsetMs: activeStartOffsetMs,
      captureSource: source,
    );
  }

  static String canonicalOperationId(String segmentId) =>
      LearningTimeSegment.canonicalOperationId(segmentId);

  static void requireCanonical({
    required Map<String, Object?> payload,
    required bool isDeleted,
    required int clientUpdatedAtUtcMs,
    String? expectedEntityId,
  }) {
    try {
      if (payload.length != keys.length ||
          !payload.keys.every(keys.contains) ||
          isDeleted) {
        throw const InvalidSyncPayloadFailure();
      }
      final segmentId = payload['segmentId'];
      final sessionId = payload['sessionId'];
      final activeStartOffsetMs = payload['activeStartOffsetMs'];
      final activeDurationMs = payload['activeDurationMs'];
      final startedAtUtcMs = payload['startedAtUtcMs'];
      final endedAtUtcMs = payload['endedAtUtcMs'];
      final timezoneId = payload['timezoneId'];
      final timezoneOffsetMinutes = payload['timezoneOffsetMinutes'];
      final captureSource = payload['captureSource'];
      if (segmentId is! String ||
          !_canonicalText(segmentId, maximumLength: 128) ||
          sessionId is! String ||
          !_canonicalText(sessionId, maximumLength: 256) ||
          activeStartOffsetMs is! int ||
          activeStartOffsetMs < 0 ||
          activeStartOffsetMs > maximumActiveOffsetMs ||
          activeDurationMs is! int ||
          activeDurationMs <= 0 ||
          activeDurationMs > maximumActiveDurationMs ||
          startedAtUtcMs is! int ||
          startedAtUtcMs < 0 ||
          endedAtUtcMs is! int ||
          endedAtUtcMs < 0 ||
          endedAtUtcMs != clientUpdatedAtUtcMs ||
          timezoneId is! String ||
          timezoneOffsetMinutes is! int ||
          timezoneOffsetMinutes < -840 ||
          timezoneOffsetMinutes > 840 ||
          captureSource is! String ||
          !captureSources.contains(captureSource)) {
        throw const InvalidSyncPayloadFailure();
      }
      LearningTimeSegment.requireCanonicalTimezoneContext(
        timezoneId: timezoneId,
        utcOffsetMinutes: timezoneOffsetMinutes,
        occurredAtUtcMs: startedAtUtcMs,
      );
      final canonicalId = canonicalEntityId(
        sessionId: sessionId,
        activeStartOffsetMs: activeStartOffsetMs,
        captureSource: captureSource,
      );
      if (segmentId != canonicalId ||
          (expectedEntityId != null && expectedEntityId != canonicalId)) {
        throw const InvalidSyncPayloadFailure();
      }
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static bool _canonicalText(String value, {required int maximumLength}) =>
      value.isNotEmpty &&
      value == value.trim() &&
      value.runes.length <= maximumLength;
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

/// Deployment and consent-version gate for report upload claims.
final class ContentQualityReportSyncRollout {
  const ContentQualityReportSyncRollout.off()
    : enabled = false,
      deployedRulesRevision = '',
      consentVersion = 0;

  const ContentQualityReportSyncRollout.v1({
    required this.deployedRulesRevision,
    required this.consentVersion,
  }) : enabled = true;

  final bool enabled;
  final String deployedRulesRevision;
  final int consentVersion;

  bool get allowsClaims =>
      enabled &&
      deployedRulesRevision == contentQualityReportV1RulesRevision &&
      consentVersion > 0;
}

abstract final class ContentQualityReportSyncPayloadContract {
  static const Set<String> keys = <String>{
    'reportId',
    'contentType',
    'contentId',
    'contentRevision',
    'reasonCode',
    'comment',
    'submittedAtUtcMs',
    'isDeleted',
  };

  static const Set<String> contentTypes = <String>{
    'learningPack',
    'lexicalMetadata',
    'assessmentForm',
    'offlineArtifact',
  };

  static const Set<String> reasonCodes = <String>{
    'text',
    'audio',
    'answer',
    'explanation',
  };

  static String canonicalEntityId({required String reportId}) {
    _requireCanonicalText(reportId);
    return 'content-quality-report:${sha256.convert(utf8.encode(reportId))}';
  }

  static String canonicalOperationId({
    required String localOperationId,
    required String reportId,
    required int submittedAtUtcMs,
  }) {
    final canonicalLocalOperationId = localOperationId.trim();
    if (canonicalLocalOperationId.isEmpty ||
        canonicalLocalOperationId.runes.length > 256 ||
        submittedAtUtcMs < 0) {
      throw ArgumentError('content report operation identity is invalid');
    }
    final identity =
        'v1|${canonicalEntityId(reportId: reportId)}|'
        '$submittedAtUtcMs';
    return 'content-quality-operation:'
        '${sha256.convert(utf8.encode(identity))}';
  }

  static void requireCanonical({
    required Map<String, Object?> payload,
    required bool isDeleted,
    required int clientUpdatedAtUtcMs,
    String? expectedEntityId,
  }) {
    try {
      final reportId = payload['reportId'];
      final contentType = payload['contentType'];
      final contentId = payload['contentId'];
      final contentRevision = payload['contentRevision'];
      final reasonCode = payload['reasonCode'];
      final comment = payload['comment'];
      final submittedAtUtcMs = payload['submittedAtUtcMs'];
      final payloadIsDeleted = payload['isDeleted'];
      if (payload.length != keys.length ||
          !payload.keys.every(keys.contains) ||
          reportId is! String ||
          !_isCanonicalText(reportId) ||
          contentType is! String ||
          !contentTypes.contains(contentType) ||
          contentId is! String ||
          !_isCanonicalText(contentId) ||
          contentRevision is! int ||
          contentRevision <= 0 ||
          reasonCode is! String ||
          !reasonCodes.contains(reasonCode) ||
          (comment != null && comment is! String) ||
          submittedAtUtcMs is! int ||
          submittedAtUtcMs < 0 ||
          submittedAtUtcMs != clientUpdatedAtUtcMs ||
          payloadIsDeleted is! bool ||
          payloadIsDeleted ||
          isDeleted ||
          payloadIsDeleted != isDeleted) {
        throw const InvalidSyncPayloadFailure();
      }
      if (comment case final String value) {
        if (canonicalContentReportComment(value) != value) {
          throw const InvalidSyncPayloadFailure();
        }
      }
      if (expectedEntityId != null &&
          expectedEntityId != canonicalEntityId(reportId: reportId)) {
        throw const InvalidSyncPayloadFailure();
      }
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static void _requireCanonicalText(String value) {
    if (!_isCanonicalText(value)) {
      throw ArgumentError.value(value, 'value', 'must be canonical text');
    }
  }

  static bool _isCanonicalText(String value) =>
      isCanonicalContentReportIdentityText(value);
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
          !const <int>{
            15,
            16,
            17,
            18,
            19,
            20,
            21,
          }.contains(databaseSchemaVersion) ||
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
