import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_personal_learning_profile_reader.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  late AppDatabase database;
  late DriftPersonalLearningProfileReader reader;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    reader = DriftPersonalLearningProfileReader(database);
    await _seedOwner(database, ownerId: 'owner-1', active: true);
    await _seedOwner(database, ownerId: 'owner-2', active: false);
  });

  tearDown(() => database.close());

  test('composes six typed axes from their canonical authorities', () async {
    await _seedPracticeAndAssessment(database, ownerId: 'owner-1');
    await _seedEngagement(database, ownerId: 'owner-1');
    await _seedForeignOwnerNoise(database);
    final changesBefore = await _totalChanges(database);

    final profile = await reader.load(
      ownerId: 'owner-1',
      nowUtc: DateTime.utc(2026, 8, 26, 12),
      timezoneId: 'Asia/Bangkok',
    );

    expect(profile.mastery.availability, ProfileAxisAvailability.available);
    expect(profile.mastery.masteredWordCount, 1);
    expect(profile.mastery.observedPracticeCount, 1);
    expect(profile.mastery.sources, {
      PersonalLearningProfileSource.driftProgress,
      PersonalLearningProfileSource.srsProjection,
    });
    expect(profile.srs.trackedWordCount, 1);
    expect(profile.srs.dueReviewCount, 1);
    expect(profile.srs.sources, {PersonalLearningProfileSource.srsProjection});
    expect(profile.effort.activeDuration, const Duration(seconds: 75));
    expect(profile.effort.sources, {
      PersonalLearningProfileSource.learningCalendar,
    });
    expect(profile.accuracy.sampleSize, 1);
    expect(profile.accuracy.correctCount, 1);
    expect(profile.accuracy.value, 1);
    expect(profile.accuracy.sources, {
      PersonalLearningProfileSource.learningCalendar,
    });
    expect(profile.weakness.items, isEmpty);
    expect(profile.weakness.availability, ProfileAxisAvailability.available);
    expect(profile.weakness.sources, {
      PersonalLearningProfileSource.driftProgress,
    });
    expect(profile.engagement.currentStreakDays, 3);
    expect(profile.engagement.longestStreakDays, 5);
    expect(profile.engagement.totalXp, 20);
    expect(profile.engagement.activeQuestCount, 1);
    expect(profile.engagement.completedQuestCount, 1);
    expect(profile.engagement.achievementCount, 1);
    expect(profile.engagement.ownedRewardItemCount, 1);
    expect(profile.engagement.sources, {
      PersonalLearningProfileSource.driftProgress,
      PersonalLearningProfileSource.questProjection,
      PersonalLearningProfileSource.streakProjection,
      PersonalLearningProfileSource.rewardProjection,
    });
    expect(profile.calendar.weekly.accuracy.sampleSize, 1);
    expect(profile.isEmpty, isFalse);
    expect(await _totalChanges(database), changesBefore);
    final profileTables = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND lower(name) LIKE '%personal%profile%'",
        )
        .get();
    expect(profileTables, isEmpty);
    final dynamic dynamicProfile = profile;
    expect(() => dynamicProfile.score, throwsNoSuchMethodError);
    expect(() => dynamicProfile.totalScore, throwsNoSuchMethodError);
  });

  test('assessment affects effort only and never learning axes', () async {
    await _seedPracticeAndAssessment(database, ownerId: 'owner-1');

    final profile = await reader.load(
      ownerId: 'owner-1',
      nowUtc: DateTime.utc(2026, 8, 26, 12),
      timezoneId: 'Asia/Bangkok',
    );

    expect(profile.effort.activeDuration, const Duration(seconds: 75));
    expect(profile.accuracy.sampleSize, 1);
    expect(profile.accuracy.correctCount, 1);
    expect(profile.mastery.observedPracticeCount, 1);
    expect(profile.weakness.items, isEmpty);
    expect(profile.engagement.totalXp, 0);
  });

  test(
    'empty owner is typed as no evidence rather than zero proficiency',
    () async {
      final profile = await reader.load(
        ownerId: 'owner-2',
        nowUtc: DateTime.utc(2026, 8, 26, 12),
        timezoneId: 'Asia/Bangkok',
      );

      expect(profile.isEmpty, isTrue);
      expect(profile.mastery.availability, ProfileAxisAvailability.noEvidence);
      expect(profile.srs.availability, ProfileAxisAvailability.noEvidence);
      expect(profile.effort.availability, ProfileAxisAvailability.noEvidence);
      expect(profile.accuracy.availability, ProfileAxisAvailability.noEvidence);
      expect(profile.accuracy.value, isNull);
      expect(profile.weakness.availability, ProfileAxisAvailability.noEvidence);
      expect(
        profile.engagement.availability,
        ProfileAxisAvailability.noEvidence,
      );
    },
  );

  test(
    'seeded active quest without objective evidence preserves empty profile',
    () async {
      await _seedQuest(
        database,
        ownerId: 'owner-2',
        state: 'active',
        currentCount: 0,
        sourceEventIds: const [],
      );

      final profile = await reader.load(
        ownerId: 'owner-2',
        nowUtc: DateTime.utc(2026, 8, 26, 12),
        timezoneId: 'Asia/Bangkok',
      );

      expect(profile.engagement.activeQuestCount, 1);
      expect(
        profile.engagement.availability,
        ProfileAxisAvailability.noEvidence,
      );
      expect(profile.isEmpty, isTrue);
    },
  );

  test('active quest progress is engagement evidence', () async {
    await _seedQuest(
      database,
      ownerId: 'owner-2',
      state: 'active',
      currentCount: 1,
      sourceEventIds: const ['event:quest-progress:owner-2'],
    );

    final profile = await reader.load(
      ownerId: 'owner-2',
      nowUtc: DateTime.utc(2026, 8, 26, 12),
      timezoneId: 'Asia/Bangkok',
    );

    expect(profile.engagement.activeQuestCount, 1);
    expect(profile.engagement.availability, ProfileAxisAvailability.available);
    expect(profile.isEmpty, isFalse);
  });

  test('completed quest remains engagement evidence', () async {
    await _seedQuest(
      database,
      ownerId: 'owner-2',
      state: 'completed',
      currentCount: 1,
      sourceEventIds: const ['event:quest-complete:owner-2'],
    );

    final profile = await reader.load(
      ownerId: 'owner-2',
      nowUtc: DateTime.utc(2026, 8, 26, 12),
      timezoneId: 'Asia/Bangkok',
    );

    expect(profile.engagement.activeQuestCount, 0);
    expect(profile.engagement.completedQuestCount, 1);
    expect(profile.engagement.availability, ProfileAxisAvailability.available);
    expect(profile.isEmpty, isFalse);
  });

  test('active-owner use case survives file reopen without writes', () async {
    final directory = await Directory.systemTemp.createTemp('f36-profile-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}profile.sqlite',
    );
    AppDatabase? persisted;
    AppDatabase? reopened;
    try {
      persisted = AppDatabase(NativeDatabase(file));
      await _seedOwner(persisted, ownerId: 'owner-1', active: true);
      await _seedPracticeOnly(persisted, ownerId: 'owner-1');
      await persisted.close();
      persisted = null;

      reopened = AppDatabase(NativeDatabase(file));
      final changesBefore = await _totalChanges(reopened);
      final useCases = ProgressUseCases(
        owners: const _Owners(),
        queries: DriftProgressQueries(reopened),
        nowUtc: () => DateTime.utc(2026, 8, 26, 12),
        learningTimezoneId: 'Asia/Bangkok',
      );

      final profile = await useCases.loadPersonalLearningProfile();

      expect(profile.ownerId, 'owner-1');
      expect(profile.accuracy.sampleSize, 1);
      expect(profile.accuracy.correctCount, 1);
      expect(await _totalChanges(reopened), changesBefore);
    } finally {
      await persisted?.close();
      await reopened?.close();
      await directory.delete(recursive: true);
    }
  });
}

final class _Owners implements LocalOwnerRepository {
  const _Owners();

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner-1',
        createdAtUtc: DateTime.utc(2026, 8, 24),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

Future<void> _seedOwner(
  AppDatabase database, {
  required String ownerId,
  required bool active,
}) async {
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: ownerId,
          createdAtUtcMs: 1,
          isActive: Value(active),
        ),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:$ownerId',
          ownerId: ownerId,
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word:$ownerId',
          ownerId: ownerId,
          categoryId: 'category:$ownerId',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _seedPracticeOnly(
  AppDatabase database, {
  required String ownerId,
}) async {
  await _insertSession(database, ownerId: ownerId, id: 'practice:$ownerId');
  await _insertAttempt(
    database,
    ownerId: ownerId,
    id: 'practice-attempt:$ownerId',
    sessionId: 'practice:$ownerId',
    occurredAtUtc: DateTime.utc(2026, 8, 25, 3),
    isCorrect: true,
    evidence: _practiceEvidence(),
  );
}

Future<void> _seedPracticeAndAssessment(
  AppDatabase database, {
  required String ownerId,
}) async {
  await _seedPracticeOnly(database, ownerId: ownerId);
  await _insertSession(database, ownerId: ownerId, id: 'assessment:$ownerId');
  await _insertAttempt(
    database,
    ownerId: ownerId,
    id: 'assessment-attempt:$ownerId',
    sessionId: 'assessment:$ownerId',
    occurredAtUtc: DateTime.utc(2026, 8, 25, 3, 1),
    isCorrect: false,
    evidence: _assessmentEvidence(),
  );
  await _insertSegment(
    database,
    ownerId: ownerId,
    id: 'practice-segment:$ownerId',
    sessionId: 'practice:$ownerId',
    startedAtUtc: DateTime.utc(2026, 8, 25, 3),
    activeDurationMs: 30000,
  );
  await _insertSegment(
    database,
    ownerId: ownerId,
    id: 'assessment-segment:$ownerId',
    sessionId: 'assessment:$ownerId',
    startedAtUtc: DateTime.utc(2026, 8, 25, 3, 1),
    activeDurationMs: 45000,
  );
  await database
      .into(database.srsStates)
      .insert(
        SrsStatesCompanion.insert(
          id: 'srs:$ownerId',
          ownerId: ownerId,
          wordId: 'word:$ownerId',
          intervalDays: const Value(14),
          repetitions: const Value(4),
          dueAtUtcMs: DateTime.utc(2026, 8, 26).millisecondsSinceEpoch,
          algorithmVersion: 1,
        ),
      );
}

Future<void> _seedEngagement(
  AppDatabase database, {
  required String ownerId,
}) async {
  await database
      .into(database.streakStates)
      .insert(
        StreakStatesCompanion.insert(
          ownerId: ownerId,
          currentStreakDays: const Value(3),
          longestStreakDays: const Value(5),
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.pointsLedgerEntries)
      .insert(
        PointsLedgerEntriesCompanion.insert(
          id: 'xp:$ownerId',
          ownerId: ownerId,
          idempotencyKey: 'xp:$ownerId',
          entryType: 'questCompletion',
          amount: 20,
          occurredAtUtcMs: 1,
        ),
      );
  await database
      .into(database.achievementUnlocks)
      .insert(
        AchievementUnlocksCompanion.insert(
          id: 'achievement:$ownerId',
          ownerId: ownerId,
          achievementId: 'first_answer',
          definitionVersion: 1,
          sourceEventId: 'event:$ownerId',
          unlockedAtUtcMs: 1,
        ),
      );
  for (final quest in const [('active', 'active'), ('complete', 'completed')]) {
    await database.customInsert(
      'INSERT INTO quest_definitions '
      '(quest_id, catalog_version, title, description, type, objectives_json, '
      'reward_json, tags_json) VALUES (?, 1, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>('quest:${quest.$1}'),
        Variable<String>(quest.$1),
        Variable<String>('description'),
        Variable<String>('daily'),
        Variable<String>('[]'),
        Variable<String>('{}'),
        Variable<String>('[]'),
      ],
    );
    final completedAt = quest.$2 == 'completed' ? '2' : 'NULL';
    await database.customInsert(
      'INSERT INTO quest_instances '
      '(instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms, '
      'state, completed_at_utc_ms, expired_at_utc_ms) '
      'VALUES (?, ?, ?, 1, 1, ?, $completedAt, NULL)',
      variables: [
        Variable<String>('quest-instance:${quest.$1}:$ownerId'),
        Variable<String>('quest:${quest.$1}'),
        Variable<String>(ownerId),
        Variable<String>(quest.$2),
      ],
    );
  }
  await database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: 'reward:$ownerId',
          ownerId: ownerId,
          idempotencyKey: 'reward:$ownerId',
          transactionType: 'purchase',
          amount: -80,
          itemId: const Value('theme_ocean'),
          catalogVersion: 2,
          occurredAtUtcMs: 1,
        ),
      );
  await database
      .into(database.ownedRewardItems)
      .insert(
        OwnedRewardItemsCompanion.insert(
          id: 'owned:$ownerId',
          ownerId: ownerId,
          itemId: 'theme_ocean',
          catalogVersion: 2,
          acquiredByTransactionId: 'reward:$ownerId',
          acquiredAtUtcMs: 1,
        ),
      );
}

Future<void> _seedForeignOwnerNoise(AppDatabase database) async {
  await database
      .into(database.pointsLedgerEntries)
      .insert(
        PointsLedgerEntriesCompanion.insert(
          id: 'xp:owner-2',
          ownerId: 'owner-2',
          idempotencyKey: 'xp:owner-2',
          entryType: 'questCompletion',
          amount: 999,
          occurredAtUtcMs: 1,
        ),
      );
}

Future<void> _seedQuest(
  AppDatabase database, {
  required String ownerId,
  required String state,
  required int currentCount,
  required List<String> sourceEventIds,
}) async {
  final questId = 'quest:$state:$ownerId';
  final instanceId = 'quest-instance:$state:$ownerId';
  await database
      .into(database.questDefinitions)
      .insert(
        QuestDefinitionsCompanion.insert(
          questId: questId,
          catalogVersion: 1,
          title: 'Practice quest',
          description: 'Practice once',
          type: 'daily',
          objectivesJson: jsonEncode([
            {
              'objectiveId': 'practice',
              'description': 'Practice once',
              'targetCount': 1,
              'eventType': 'AnswerRecorded',
              'filters': null,
            },
          ]),
          rewardJson: jsonEncode({'xpAmount': 0, 'rewardItemId': null}),
        ),
      );
  await database
      .into(database.questInstances)
      .insert(
        QuestInstancesCompanion.insert(
          instanceId: instanceId,
          questId: questId,
          ownerId: ownerId,
          catalogVersion: 1,
          assignedAtUtcMs: 1,
          state: state,
          completedAtUtcMs: Value(state == 'completed' ? 2 : null),
        ),
      );
  await database
      .into(database.questObjectiveProgress)
      .insert(
        QuestObjectiveProgressCompanion.insert(
          id: '$instanceId:practice',
          instanceId: instanceId,
          objectiveId: 'practice',
          currentCount: Value(currentCount),
          targetCount: 1,
          sourceEventIdsJson: Value(jsonEncode(sourceEventIds)),
        ),
      );
}

Future<void> _insertSession(
  AppDatabase database, {
  required String ownerId,
  required String id,
}) => database
    .into(database.learningSessions)
    .insert(
      LearningSessionsCompanion.insert(
        id: id,
        ownerId: ownerId,
        activityType: 'quiz',
        state: 'completed',
        startedAtUtcMs: DateTime.utc(2026, 8, 25, 3).millisecondsSinceEpoch,
        appVersion: 'test',
        buildId: 'test',
      ),
    );

Future<void> _insertAttempt(
  AppDatabase database, {
  required String ownerId,
  required String id,
  required String sessionId,
  required DateTime occurredAtUtc,
  required bool isCorrect,
  required EvidenceContext evidence,
}) => database
    .into(database.answerAttempts)
    .insert(
      AnswerAttemptsCompanion.insert(
        id: id,
        ownerId: ownerId,
        sessionId: sessionId,
        wordId: 'word:$ownerId',
        promptMode: 'meaningChoice',
        isCorrect: isCorrect,
        attemptNumber: 1,
        occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
        evidenceClass: Value(evidence.evidenceClass.name),
        evidenceContextJson: Value(jsonEncode(evidence.toJson())),
      ),
    );

Future<void> _insertSegment(
  AppDatabase database, {
  required String ownerId,
  required String id,
  required String sessionId,
  required DateTime startedAtUtc,
  required int activeDurationMs,
}) => database
    .into(database.learningTimeSegments)
    .insert(
      LearningTimeSegmentsCompanion.insert(
        id: id,
        ownerId: ownerId,
        sessionId: sessionId,
        activeStartOffsetMs: 0,
        activeDurationMs: activeDurationMs,
        startedAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
        endedAtUtcMs: startedAtUtc
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        timezoneId: 'Asia/Bangkok',
        timezoneOffsetMinutes: 420,
        captureSource: 'automaticLesson',
      ),
    );

EvidenceContext _practiceEvidence() => EvidenceContext.legacyCompatibility(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'retention',
  hintLevel: 0,
  contentRevision: 'content-v1',
  engagementAllowed: false,
);

EvidenceContext _assessmentEvidence() => EvidenceContext.legacyCompatibility(
  evidenceClass: EvidenceClass.assessment,
  skillId: 'assessment',
  hintLevel: 0,
  contentRevision: 'assessment-v1',
  engagementAllowed: false,
  instrumentId: 'instrument-v1',
  instrumentVersion: '1',
  formId: 'form-v1',
  formVersion: '1',
  assessmentItemId: 'item-v1',
  assessmentResponseCode: 'incorrect',
  scoringRuleVersion: 'score-v1',
);

Future<int> _totalChanges(AppDatabase database) async =>
    (await database.customSelect('SELECT total_changes() AS value').getSingle())
        .read<int>('value');
