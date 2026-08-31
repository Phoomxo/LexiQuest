import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lexical_prompt_artifact_identity.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart'
    as quest_domain;
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/recommendation/data/drift_recommendation_reader.dart';
import 'package:vocab_learning_app/features/recommendation/domain/active_recall_ladder.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/data/drift_today_hub_reader.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  group('DriftTodayHubReader', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await _seedOwner(database, ownerId: _ownerId);
      await _seedOwner(database, ownerId: _otherOwnerId, active: false);
    });

    tearDown(() => database.close());

    test(
      'orders canonical sections and work independently of insertion order',
      () async {
        final other = AppDatabase(NativeDatabase.memory());
        try {
          await _seedOwner(other, ownerId: _ownerId);
          await _seedOwner(other, ownerId: _otherOwnerId, active: false);
          await _seedCompleteSources(database, reverseWordOrder: false);
          await _seedCompleteSources(other, reverseWordOrder: true);

          final first = await _reader(database).compose(_request());
          final second = await _reader(other).compose(_request());

          expect(first.sectionOrder, <TodayHubSectionKind>[
            TodayHubSectionKind.resume,
            TodayHubSectionKind.assigned,
            TodayHubSectionKind.review,
            TodayHubSectionKind.planning,
            TodayHubSectionKind.continuity,
          ]);
          expect(_stableShape(first), _stableShape(second));
          expect(first.reviewWork.map((item) => item.identity.id), <String>[
            'word:due',
            'word:incorrect',
          ]);
        } finally {
          await other.close();
        }
      },
    );

    test(
      'merges a fresh recommendation into exact review identity without losing reasons',
      () async {
        await _seedWord(database, id: 'word:station', spelling: 'station');
        await _recordAttempt(
          database,
          wordId: 'word:station',
          occurredAtUtc: _now.subtract(const Duration(minutes: 5)),
        );
        await _seedDue(database, wordId: 'word:station', dueAtUtc: _now);

        final snapshot = await _reader(database).compose(_request());

        expect(snapshot.reviewWork, hasLength(1));
        final work = snapshot.reviewWork.single;
        expect(
          work.identity,
          const ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: 'word:station',
            revision: 1,
          ),
        );
        expect(
          work.provenance.map((source) => source.reason),
          <ReviewQueueReason>[
            ReviewQueueReason.dueSrs,
            ReviewQueueReason.incorrectAnswer,
          ],
        );
        expect(
          work.recommendation?.reason,
          RecommendationPanelReason.weakEvidence,
        );
        expect(
          snapshot.recommendation.result.reason,
          RecommendationPanelReason.weakEvidence,
        );
        expect(
          snapshot.recommendation.result.freshness,
          RecommendationEvidenceFreshness.current,
        );
        expect(snapshot.recommendation.isAuthoritative, isTrue);
        expect(snapshot.recommendation.mergedInto, work.identity);
        expect(
          snapshot.authoritativeRecommendation?.result.reason,
          RecommendationPanelReason.weakEvidence,
        );
      },
    );

    test(
      'does not merge a recommendation into an ambiguous content revision',
      () async {
        await _seedWord(database, id: 'word:station', spelling: 'station');
        await _recordAttempt(
          database,
          wordId: 'word:station',
          occurredAtUtc: _now.subtract(const Duration(minutes: 5)),
        );
        final review = _FixedReviewReader(<ReviewQueueItem>[
          _reviewItem(id: 'word:station', revision: 1, sourceId: 'srs:one'),
          _reviewItem(id: 'word:station', revision: 2, sourceId: 'srs:two'),
        ]);

        final snapshot = await _reader(
          database,
          reviewReader: review,
        ).compose(_request());

        expect(snapshot.reviewWork.map((item) => item.identity.revision), <int>[
          1,
          2,
        ]);
        expect(
          snapshot.reviewWork.every((item) => item.recommendation == null),
          isTrue,
        );
        expect(snapshot.recommendation.isAuthoritative, isTrue);
        expect(snapshot.recommendation.mergedInto, isNull);
        expect(
          snapshot.dependencyStates[TodayHubDependency.review],
          TodayHubDependencyState.corrupt,
        );
      },
    );

    test(
      'keeps stale recommendation explained but excludes it as the next action',
      () async {
        await _seedWord(database, id: 'word:stale', spelling: 'stale');
        await _recordAttempt(
          database,
          wordId: 'word:stale',
          occurredAtUtc: _now.subtract(const Duration(days: 31)),
        );

        final snapshot = await _reader(database).compose(_request());

        expect(
          snapshot.recommendation.result.reason,
          RecommendationPanelReason.staleEvidence,
        );
        expect(
          snapshot.recommendation.result.freshness,
          RecommendationEvidenceFreshness.stale,
        );
        expect(snapshot.recommendation.isAuthoritative, isFalse);
        expect(snapshot.authoritativeRecommendation, isNull);
        expect(
          snapshot.dependencyStates[TodayHubDependency.recommendation],
          TodayHubDependencyState.stale,
        );
      },
    );

    test(
      'f42 signoff fixed request owns recommendation freshness and day boundary',
      () async {
        await _seedCompleteSources(database, reverseWordOrder: false);
        final request = _request();

        final canonical = await _reader(
          database,
          recommendationNowUtc: _now,
          recommendationTimezoneId: 'Asia/Bangkok',
        ).compose(request);
        final conflictingDependencyClock = await _reader(
          database,
          recommendationNowUtc: _now.add(const Duration(days: 40)),
          recommendationTimezoneId: 'Pacific/Auckland',
        ).compose(request);

        expect(
          conflictingDependencyClock.evaluatedAtUtc,
          request.evaluatedAtUtc,
        );
        expect(
          conflictingDependencyClock.recommendation.result.reason,
          canonical.recommendation.result.reason,
        );
        expect(
          conflictingDependencyClock.recommendation.result.freshness,
          canonical.recommendation.result.freshness,
        );
        expect(
          conflictingDependencyClock.recommendation.isAuthoritative,
          canonical.recommendation.isAuthoritative,
        );
        expect(
          conflictingDependencyClock.gentleStreak?.phase,
          canonical.gentleStreak?.phase,
        );
        expect(conflictingDependencyClock.sectionOrder, canonical.sectionOrder);
      },
    );

    test('fails closed for missing and corrupt dependencies', () async {
      await database
          .into(database.streakStates)
          .insert(
            StreakStatesCompanion.insert(
              ownerId: _ownerId,
              currentStreakDays: const Value(4),
              longestStreakDays: const Value(2),
              updatedAtUtcMs: _now.millisecondsSinceEpoch,
            ),
          );
      final snapshot = await _reader(
        database,
        reviewReader: const _ThrowingReviewReader(),
      ).compose(_request());

      expect(snapshot.resumableSession, isNull);
      expect(snapshot.reviewWork, isEmpty);
      expect(snapshot.assignedAssessment, isNull);
      expect(snapshot.goals, isEmpty);
      expect(snapshot.reminders, isEmpty);
      expect(snapshot.quests, isEmpty);
      expect(snapshot.gentleStreak, isNull);
      expect(snapshot.authoritativeRecommendation, isNull);
      expect(
        snapshot.dependencyStates,
        containsPair(
          TodayHubDependency.review,
          TodayHubDependencyState.unavailable,
        ),
      );
      expect(
        snapshot.dependencyStates,
        containsPair(
          TodayHubDependency.recommendation,
          TodayHubDependencyState.corrupt,
        ),
      );
      expect(
        snapshot.dependencyStates,
        containsPair(
          TodayHubDependency.gentleStreak,
          TodayHubDependencyState.corrupt,
        ),
      );

      final missingOwner = await _reader(
        database,
      ).compose(_request(ownerId: 'owner:missing'));
      expect(missingOwner.sectionOrder, isEmpty);
      expect(missingOwner.reviewWork, isEmpty);
      expect(missingOwner.authoritativeRecommendation, isNull);
      expect(
        missingOwner.dependencyStates[TodayHubDependency.identity],
        TodayHubDependencyState.unavailable,
      );
    });

    test(
      'f42 final signoff owner switch during composition publishes no stale owner work',
      () async {
        final switchingReview = _SwitchingActiveOwnerReviewReader(
          database,
          _reviewItem(
            id: 'word:owner-switch',
            revision: 1,
            sourceId: 'srs:owner-switch',
          ),
        );

        final snapshot = await _reader(
          database,
          reviewReader: switchingReview,
        ).compose(_request());

        expect(switchingReview.calls, 1);
        expect(
          await (database.select(database.localOwners)
                ..where((row) => row.isActive.equals(true)))
              .get()
              .then((rows) => rows.map((row) => row.id).toList()),
          <String>[_otherOwnerId],
        );
        expect(snapshot.sectionOrder, isEmpty);
        expect(snapshot.resumableSession, isNull);
        expect(snapshot.assignedAssessment, isNull);
        expect(snapshot.reviewWork, isEmpty);
        expect(snapshot.authoritativeRecommendation, isNull);
        expect(snapshot.goals, isEmpty);
        expect(snapshot.reminders, isEmpty);
        expect(snapshot.quests, isEmpty);
        expect(snapshot.gentleStreak, isNull);
        expect(
          snapshot.dependencyStates.values,
          everyElement(TodayHubDependencyState.unavailable),
        );
      },
    );

    test(
      'includes only an active assessment run with exact assignment lineage',
      () async {
        final run = await _seedAssessment(database);

        final exact = await _reader(database).compose(_request());

        expect(exact.assignedAssessment?.run, run);
        expect(exact.assignedAssessment?.assignmentId, run.assignmentId);
        expect(
          exact.assignedAssessment?.learningSessionId,
          run.learningSessionId,
        );
        expect(
          exact.dependencyStates[TodayHubDependency.assessment],
          TodayHubDependencyState.ready,
        );

        await database.customStatement(
          'UPDATE assessment_runs SET cohort = ? WHERE id = ?',
          <Object?>['mismatched-cohort', run.id],
        );
        final mismatch = await _reader(database).compose(_request());

        expect(mismatch.assignedAssessment, isNull);
        expect(
          mismatch.dependencyStates[TodayHubDependency.assessment],
          TodayHubDependencyState.corrupt,
        );
      },
    );

    test(
      'reads goal reminder quest and gentle streak projections without recomputing them',
      () async {
        await _seedPlanning(database);

        final snapshot = await _reader(database).compose(_request());

        expect(snapshot.goals.map((goal) => goal.id), <String>['goal:ielts']);
        expect(snapshot.reminders.map((reminder) => reminder.id), <String>[
          'reminder:ielts',
        ]);
        expect(snapshot.quests.map((quest) => quest.instanceId), <String>[
          'quest-instance:daily',
        ]);
        expect(snapshot.gentleStreak?.ownerId, _ownerId);
        expect(snapshot.gentleStreak?.currentStreakDays, 4);
        expect(snapshot.gentleStreak?.phase, GentleStreakPhase.grace);
      },
    );

    test(
      'recreational evidence never becomes review work or Active Effort',
      () async {
        await _seedWord(database, id: 'word:recreational', spelling: 'tiles');
        await _insertRecreationalAttempt(database, wordId: 'word:recreational');
        final beforeSegments = await database
            .select(database.learningTimeSegments)
            .get();

        final snapshot = await _reader(database).compose(_request());

        expect(snapshot.reviewWork, isEmpty);
        expect(
          await database.select(database.learningTimeSegments).get(),
          beforeSegments,
        );
        expect(
          snapshot.dependencyStates[TodayHubDependency.review],
          TodayHubDependencyState.empty,
        );
      },
    );

    test(
      'compose is byte-equivalent over every source table and owns no table or writer',
      () async {
        await _seedCompleteSources(database, reverseWordOrder: false);
        final before = await _databaseSnapshot(database);

        final first = await _reader(database).compose(_request());
        final second = await _reader(database).compose(_request());

        expect(_stableShape(second), _stableShape(first));
        expect(await _databaseSnapshot(database), before);
        final tableNames = await _tableNames(database);
        expect(
          tableNames.where(
            (name) =>
                RegExp('today[_-]?hub', caseSensitive: false).hasMatch(name),
          ),
          isEmpty,
        );
      },
    );
  });
}

const _ownerId = 'owner:today';
const _otherOwnerId = 'owner:other';
final _now = DateTime.utc(2026, 8, 31, 8);

TodayHubRequest _request({String ownerId = _ownerId}) => TodayHubRequest(
  ownerId: ownerId,
  evaluatedAtUtc: _now,
  timezoneId: 'Asia/Bangkok',
);

TodayHubReader _reader(
  AppDatabase database, {
  ReviewCenterReader? reviewReader,
  DateTime? recommendationNowUtc,
  String recommendationTimezoneId = 'Asia/Bangkok',
}) => DriftTodayHubReader(
  database,
  reviewReader: reviewReader ?? DriftReviewCenterReader(database),
  recommendationUseCases: RecommendationUseCases(
    activeOwnerId: () async => _ownerId,
    reader: DriftRecommendationReader(database),
    nowUtc: () => recommendationNowUtc ?? _now,
    timezoneId: recommendationTimezoneId,
    modeAvailability: <LessonMode, RecallLadderModeAvailability>{
      for (final mode in LessonMode.values)
        mode: RecallLadderModeAvailability.available,
    },
  ),
);

Map<String, Object?> _stableShape(
  TodayHubSnapshot snapshot,
) => <String, Object?>{
  'sections': snapshot.sectionOrder.map((value) => value.name).toList(),
  'resume': snapshot.resumableSession?.id,
  'assessment': snapshot.assignedAssessment?.run.id,
  'review': <Object?>[
    for (final item in snapshot.reviewWork)
      <String, Object?>{
        'id': item.identity.id,
        'revision': item.identity.revision,
        'reasons': item.provenance.map((source) => source.reason.name).toList(),
        'recommendation': item.recommendation?.reason.name,
      },
  ],
  'recommendation': snapshot.recommendation.result.reason.name,
  'recommendationIdentity': snapshot.recommendation.mergedInto?.id,
  'goals': snapshot.goals.map((goal) => goal.id).toList(),
  'reminders': snapshot.reminders.map((reminder) => reminder.id).toList(),
  'quests': snapshot.quests.map((quest) => quest.instanceId).toList(),
  'streak': snapshot.gentleStreak?.currentStreakDays,
};

Future<void> _seedCompleteSources(
  AppDatabase database, {
  required bool reverseWordOrder,
}) async {
  final words = <({String id, String spelling})>[
    (id: 'word:due', spelling: 'airport'),
    (id: 'word:incorrect', spelling: 'station'),
  ];
  for (final word in reverseWordOrder ? words.reversed : words) {
    await _seedWord(database, id: word.id, spelling: word.spelling);
  }
  await _seedDue(
    database,
    wordId: 'word:due',
    dueAtUtc: _now.subtract(const Duration(hours: 2)),
  );
  await _recordAttempt(
    database,
    wordId: 'word:incorrect',
    occurredAtUtc: _now.subtract(const Duration(minutes: 5)),
  );
  await _seedResumeSession(database);
  await _seedAssessment(database);
  await _seedPlanning(database);
}

Future<void> _seedOwner(
  AppDatabase database, {
  required String ownerId,
  bool active = true,
}) => database
    .into(database.localOwners)
    .insert(
      LocalOwnersCompanion.insert(
        id: ownerId,
        createdAtUtcMs: 1,
        isActive: Value(active),
      ),
      mode: InsertMode.insertOrIgnore,
    );

Future<void> _seedWord(
  AppDatabase database, {
  required String id,
  required String spelling,
}) async {
  const categoryId = 'category:today';
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: _ownerId,
          name: 'Today',
          normalizedName: 'today',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  final meaning = 'meaning:$id';
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: categoryId,
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'manual',
    isGlobal: false,
  );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: id,
          ownerId: _ownerId,
          categoryId: categoryId,
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: meaning,
          normalizedMeaning: meaning,
          partOfSpeech: 'noun',
          source: const Value('manual'),
          isGlobal: const Value(false),
          contentRevision: const Value(1),
          contentChecksumSha256: Value(checksum),
          contentProvenance: Value(ContentProvenance.userAuthored.name),
          contentReviewState: Value(ContentReviewState.unreviewed.name),
          contentPublicationState: Value(ContentPublicationState.private.name),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _seedDue(
  AppDatabase database, {
  required String wordId,
  required DateTime dueAtUtc,
}) async {
  final ownerRows = await (database.select(
    database.srsStates,
  )..where((row) => row.ownerId.equals(_ownerId))).get();
  final exactRows = ownerRows
      .where((row) => row.wordId == wordId)
      .toList(growable: false);
  final existing = exactRows.isEmpty ? null : exactRows.single;
  if (existing != null) {
    await (database.update(
      database.srsStates,
    )..where((row) => row.id.equals(existing.id))).write(
      SrsStatesCompanion(dueAtUtcMs: Value(dueAtUtc.millisecondsSinceEpoch)),
    );
    return;
  }
  await database
      .into(database.srsStates)
      .insert(
        SrsStatesCompanion.insert(
          id: 'srs:$wordId',
          ownerId: _ownerId,
          wordId: wordId,
          dueAtUtcMs: dueAtUtc.millisecondsSinceEpoch,
          algorithmVersion: 1,
        ),
      );
}

Future<void> _recordAttempt(
  AppDatabase database, {
  required String wordId,
  required DateTime occurredAtUtc,
}) async {
  final learning = DriftLearningRepository(database);
  final sessionId = 'session:$wordId:${occurredAtUtc.millisecondsSinceEpoch}';
  final attemptId = 'attempt:$wordId:${occurredAtUtc.millisecondsSinceEpoch}';
  const promptMode = 'typedRecall';
  final contentRevision = await _evidenceRevision(
    database,
    wordId: wordId,
    revision: 1,
    promptMode: promptMode,
  );
  final evidence = EvidenceContext.legacyCompatibility(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'typed-recall',
    hintLevel: 0,
    contentRevision: contentRevision,
    engagementAllowed: false,
  );
  final event = const EventV1ToV2Adapter(appVersion: 'test', buildId: 'f42')
      .adaptFromCommand(
        sourceEvidenceId: attemptId,
        ownerId: _ownerId,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: promptMode,
        isCorrect: false,
        attemptNumber: 1,
        occurredAtUtc: occurredAtUtc,
        evidenceContext: evidence,
        learningEventContext: LearningEventContext.noResearch(evidence),
      );
  await learning.startSession(
    LearningSessionDraft(
      id: sessionId,
      ownerId: _ownerId,
      activityType: 'quiz',
      startedAtUtc: occurredAtUtc,
      appVersion: 'test',
      buildId: 'f42',
    ),
  );
  await learning.recordAnswer(
    RecordAnswerCommand(
      id: attemptId,
      ownerId: _ownerId,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: promptMode,
      isCorrect: false,
      responseTimeMs: 120,
      attemptNumber: 1,
      occurredAtUtc: occurredAtUtc,
      evidenceContext: evidence,
      event: event,
    ),
  );
}

Future<String> _evidenceRevision(
  AppDatabase database, {
  required String wordId,
  required int revision,
  required String promptMode,
}) async {
  final word = await (database.select(
    database.vocabularyWords,
  )..where((row) => row.id.equals(wordId))).getSingle();
  final manifestRows = await (database.select(
    database.contentManifests,
  )..where((row) => row.contentId.equals(wordId))).get();
  final exactManifests = manifestRows
      .where(
        (row) =>
            row.contentType == ContentType.lexicalMetadata.name &&
            row.revision == revision,
      )
      .toList(growable: false);
  final manifest = exactManifests.length == 1 ? exactManifests.single : null;
  final candidates = LexicalPromptArtifactResolver.resolveReaderCandidates(
    promptMode: promptMode,
    wordId: wordId,
    coreRevision: revision,
    coreChecksumSha256: word.contentChecksumSha256,
    verifiedArtifactLoaded: false,
    usesAcceptedVariants: false,
    verifiedArtifactRevision: manifest?.revision,
    verifiedArtifactChecksumSha256: manifest?.checksumSha256,
  );
  if (candidates.length != 1) {
    throw StateError(
      'test evidence requires one exact prompt artifact identity',
    );
  }
  return candidates.single.evidenceContentRevision;
}

Future<void> _seedResumeSession(AppDatabase database) => database
    .into(database.learningSessions)
    .insert(
      LearningSessionsCompanion.insert(
        id: 'session:resume',
        ownerId: _ownerId,
        activityType: 'meaningQuiz',
        state: 'active',
        startedAtUtcMs: _now
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        appVersion: 'test',
        buildId: 'f42',
      ),
    );

Future<AssessmentRun> _seedAssessment(AppDatabase database) async {
  const sessionId = 'session:assessment';
  final assignedAt = _now.subtract(const Duration(days: 2));
  final startedAt = _now.subtract(const Duration(hours: 1));
  final assignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: _ownerId,
        experimentId: 'experiment:assessment',
        experimentVersion: 1,
      );
  await database
      .into(database.experimentAssignments)
      .insert(
        ExperimentAssignmentsCompanion.insert(
          id: assignmentId,
          ownerId: _ownerId,
          experimentId: 'experiment:assessment',
          experimentVersion: 1,
          cohort: 'enforced',
          protocolVersion: '1.0.0',
          assignedAtUtcMs: assignedAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  final run = AssessmentRun(
    id: 'assessment:today',
    ownerId: _ownerId,
    learningSessionId: sessionId,
    studyCycleId: 'cycle:today',
    phase: AssessmentPhase.pre,
    state: AssessmentRunState.active,
    protocolId: 'assessment-protocol',
    protocolVersion: '1.0.0',
    experimentId: 'experiment:assessment',
    experimentVersion: 1,
    assignmentId: assignmentId,
    cohort: 'enforced',
    consentVersion: 1,
    consentDecidedAtUtc: assignedAt.subtract(const Duration(days: 1)),
    instrumentId: 'instrument:today',
    instrumentVersion: '1.0.0',
    formId: 'form:today',
    formVersion: '1.0.0',
    instrumentChecksumSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    formChecksumSha256:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    appVersion: 'test',
    buildId: 'f42',
    databaseSchemaVersion: AppDatabase.currentSchemaVersion,
    contentRevision: 'content:today:1',
    evidencePolicyVersion: 'evidence-policy-v1',
    featureContractRevision: currentFeatureContractIdentity.revision,
    featureContractHash: currentFeatureContractIdentity.semanticHash,
    startedAtUtc: startedAt,
    completedAtUtc: null,
    abandonedAtUtc: null,
  );
  await DriftAssessmentRepository(database).persistRemote(run);
  return run;
}

Future<void> _seedPlanning(AppDatabase database) async {
  await database
      .into(database.learningGoals)
      .insert(
        LearningGoalsCompanion.insert(
          id: 'goal:ielts',
          ownerId: _ownerId,
          kind: 'languageTest',
          title: 'IELTS target',
          deadlineAtUtcMs: _now
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
          timezoneId: 'Asia/Bangkok',
          timezoneOffsetMinutes: 420,
          status: 'active',
          createdAtUtcMs: _now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
          updatedAtUtcMs: _now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.studyReminders)
      .insert(
        StudyRemindersCompanion.insert(
          id: 'reminder:ielts',
          ownerId: _ownerId,
          goalId: const Value('goal:ielts'),
          sourceKind: 'goalDeadline',
          scheduledAtUtcMs: _now
              .add(const Duration(hours: 2))
              .millisecondsSinceEpoch,
          timezoneId: 'Asia/Bangkok',
          timezoneOffsetMinutes: 420,
          isEnabled: const Value(true),
          createdAtUtcMs: _now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
          updatedAtUtcMs: _now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        ),
      );
  final quest = quest_domain.QuestDefinition(
    questId: 'quest:daily',
    catalogVersion: 1,
    title: 'Daily practice',
    description: 'Complete one learning activity.',
    type: quest_domain.QuestType.daily,
    objectives: const <quest_domain.QuestObjective>[
      quest_domain.QuestObjective(
        objectiveId: 'objective:learn',
        description: 'Learn once',
        targetCount: 1,
        criteria: quest_domain.ObjectiveCriteria(eventType: 'AnswerRecorded'),
      ),
    ],
    reward: const quest_domain.RewardSpec(xpAmount: 1),
  );
  final quests = DriftQuestRepository(database);
  await quests.upsertDefinition(quest);
  await quests.startInstance(
    quest_domain.QuestInstance(
      instanceId: 'quest-instance:daily',
      questId: quest.questId,
      ownerId: _ownerId,
      catalogVersion: quest.catalogVersion,
      assignedAtUtc: _now.subtract(const Duration(hours: 3)),
      state: quest_domain.QuestInstanceState.active,
      progress: const <quest_domain.ObjectiveProgress>[
        quest_domain.ObjectiveProgress(
          objectiveId: 'objective:learn',
          currentCount: 0,
          targetCount: 1,
        ),
      ],
    ),
  );
  await database
      .into(database.streakStates)
      .insert(
        StreakStatesCompanion.insert(
          ownerId: _ownerId,
          currentStreakDays: const Value(4),
          longestStreakDays: const Value(7),
          freezeCount: const Value(1),
          lastLearnedAtUtcMs: Value(
            _now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          ),
          updatedAtUtcMs: _now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
        ),
      );
}

Future<void> _insertRecreationalAttempt(
  AppDatabase database, {
  required String wordId,
}) async {
  const sessionId = 'session:recreational';
  const attemptId = 'attempt:recreational';
  final occurredAt = _now.subtract(const Duration(minutes: 2));
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: _ownerId,
          activityType: 'wordScramble',
          state: 'completed',
          startedAtUtcMs: occurredAt
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          endedAtUtcMs: Value(occurredAt.millisecondsSinceEpoch),
          appVersion: 'test',
          buildId: 'f42',
        ),
      );
  final evidence = EvidenceContext.legacyCompatibility(
    evidenceClass: EvidenceClass.recreational,
    skillId: 'word-scramble',
    hintLevel: 0,
    contentRevision: 'built-in-v1',
    engagementAllowed: true,
  );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: attemptId,
          ownerId: _ownerId,
          sessionId: sessionId,
          wordId: wordId,
          promptMode: 'wordScramble',
          isCorrect: false,
          responseTimeMs: const Value(100),
          attemptNumber: 1,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          evidenceClass: Value(EvidenceClass.recreational.name),
          evidenceContextJson: Value(jsonEncode(evidence.toJson())),
        ),
      );
  final event = const EventV1ToV2Adapter(appVersion: 'test', buildId: 'f42')
      .adaptFromCommand(
        sourceEvidenceId: attemptId,
        ownerId: _ownerId,
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'wordScramble',
        isCorrect: false,
        attemptNumber: 1,
        occurredAtUtc: occurredAt,
        evidenceContext: evidence,
        learningEventContext: LearningEventContext.noResearch(evidence),
      );
  await _insertSourceEvent(database, event);
}

Future<void> _insertSourceEvent(AppDatabase database, EventEnvelopeV2 event) =>
    database
        .into(database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: event.eventId,
            eventType: event.eventType,
            eventVersion: event.eventVersion,
            occurredAtUtc: event.occurredAtUtc,
            recordedAtUtc: event.recordedAtUtc,
            actorIdentity: event.actorIdentity,
            ownerId: event.ownerIdentity,
            tenantContextJson: Value(
              event.tenantContext == null
                  ? null
                  : jsonEncode(event.tenantContext!.toJson()),
            ),
            aggregateType: event.aggregateType,
            aggregateId: event.aggregateId,
            correlationId: Value(event.correlationId),
            causationId: Value(event.causationId),
            idempotencyKey: event.idempotencyKey,
            consentContextJson: jsonEncode(event.consentContext.toJson()),
            experimentContextJson: Value(
              event.experimentContext == null
                  ? null
                  : jsonEncode(event.experimentContext!.toJson()),
            ),
            contentRevision: Value(event.contentRevision),
            policyVersion: Value(event.policyVersion),
            appVersion: event.appVersion,
            buildId: event.buildId,
            providerProvenanceJson: Value(
              event.providerProvenance == null
                  ? null
                  : jsonEncode(event.providerProvenance!.toJson()),
            ),
            privacyClassification: event.privacyClassification.name,
            payloadJson: jsonEncode(event.payload),
          ),
        );

ReviewQueueItem _reviewItem({
  required String id,
  required int revision,
  required String sourceId,
}) => ReviewQueueItem(
  snapshot: ReviewedLexicalContentSnapshot(
    identity: ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: id,
      revision: revision,
    ),
    categoryId: 'category:today',
    spelling: 'station',
    normalizedSpelling: 'station',
    meaning: 'meaning:$id',
    normalizedMeaning: 'meaning:$id',
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'manual',
    isGlobal: false,
    coreChecksumSha256: ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: 'category:today',
      spelling: 'station',
      normalizedSpelling: 'station',
      meaning: 'meaning:$id',
      normalizedMeaning: 'meaning:$id',
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'manual',
      isGlobal: false,
    ),
    provenance: ContentProvenance.userAuthored,
    reviewState: ContentReviewState.unreviewed,
    publicationState: ContentPublicationState.private,
    artifact: null,
  ),
  provenance: <ReviewReasonProvenance>[
    ReviewReasonProvenance.due(sourceId: sourceId, dueAtUtc: _now),
  ],
);

Future<List<String>> _tableNames(AppDatabase database) async {
  final rows = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
      )
      .get();
  return rows.map((row) => row.read<String>('name')).toList(growable: false);
}

Future<Map<String, List<Map<String, Object?>>>> _databaseSnapshot(
  AppDatabase database,
) async {
  final result = <String, List<Map<String, Object?>>>{};
  for (final table
      in database.allTables.toList()..sort(
        (left, right) => left.actualTableName.compareTo(right.actualTableName),
      )) {
    final rows = await database
        .customSelect('SELECT * FROM "${table.actualTableName}" ORDER BY rowid')
        .get();
    result[table.actualTableName] = <Map<String, Object?>>[
      for (final row in rows)
        <String, Object?>{
          for (final entry in row.data.entries)
            entry.key: _stableDatabaseValue(entry.value),
        },
    ];
  }
  return result;
}

Object? _stableDatabaseValue(Object? value) => switch (value) {
  Uint8List bytes => base64Encode(bytes),
  DateTime time => time.toUtc().toIso8601String(),
  _ => value,
};

final class _FixedReviewReader implements ReviewCenterReader {
  const _FixedReviewReader(this.items);

  final List<ReviewQueueItem> items;

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async =>
      items;
}

final class _ThrowingReviewReader implements ReviewCenterReader {
  const _ThrowingReviewReader();

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) =>
      throw StateError('review authority unavailable');
}

final class _SwitchingActiveOwnerReviewReader implements ReviewCenterReader {
  _SwitchingActiveOwnerReviewReader(this.database, this.item);

  final AppDatabase database;
  final ReviewQueueItem item;
  int calls = 0;

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async {
    calls += 1;
    if (filter.ownerId != _ownerId) {
      throw StateError('unexpected Today Hub owner');
    }
    await database.transaction(() async {
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals(_ownerId)))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals(_otherOwnerId)))
          .write(const LocalOwnersCompanion(isActive: Value(true)));
    });
    return <ReviewQueueItem>[item];
  }
}
