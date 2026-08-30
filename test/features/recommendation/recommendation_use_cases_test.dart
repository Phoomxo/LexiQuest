import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/recommendation/data/drift_recommendation_reader.dart';
import 'package:vocab_learning_app/features/recommendation/domain/active_recall_ladder.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  final now = DateTime.utc(2026, 8, 30, 12);
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await _seedOwnerAndWord(
      database,
      ownerId: 'owner-1',
      wordId: 'word-1',
      spelling: 'station',
      active: true,
    );
    await _seedOwnerAndWord(
      database,
      ownerId: 'owner-2',
      wordId: 'word-2',
      spelling: 'airport',
      active: false,
    );
  });

  tearDown(() => database.close());

  RecommendationUseCases useCases({
    String? activeOwnerId = 'owner-1',
    Set<LessonMode> availableModes = const {
      LessonMode.flashcard,
      LessonMode.meaningQuiz,
      LessonMode.typedRecall,
      LessonMode.cefrReading,
    },
  }) => RecommendationUseCases(
    activeOwnerId: () async => activeOwnerId,
    reader: DriftRecommendationReader(database),
    nowUtc: () => now,
    timezoneId: 'Asia/Bangkok',
    modeAvailability: <LessonMode, RecallLadderModeAvailability>{
      for (final mode in LessonMode.values)
        mode: availableModes.contains(mode)
            ? RecallLadderModeAvailability.available
            : RecallLadderModeAvailability.liveOff,
    },
  );

  test('explains a current canonical weakness recommendation', () async {
    await _recordAttempt(
      database,
      ownerId: 'owner-1',
      wordId: 'word-1',
      occurredAtUtc: now.subtract(const Duration(minutes: 5)),
      isCorrect: false,
    );

    final result = await useCases().load();

    expect(result.availability, RecommendationResultAvailability.recommended);
    expect(result.reason, RecommendationPanelReason.weakEvidence);
    expect(result.freshness, RecommendationEvidenceFreshness.current);
    expect(result.protocolConstraint, RecommendationProtocolConstraint.open);
    expect(result.recommendedMode, LessonMode.flashcard);
    expect(result.contentId, 'word-1');
    expect(result.learnerOverrideApplied, isFalse);
    expect(result.alternatives, contains(LessonMode.meaningQuiz));
  });

  test('stale evidence fails closed to an explained neutral list', () async {
    await _recordAttempt(
      database,
      ownerId: 'owner-1',
      wordId: 'word-1',
      occurredAtUtc: now.subtract(const Duration(days: 31)),
      isCorrect: false,
    );

    final result = await useCases().load();

    expect(
      result.availability,
      RecommendationResultAvailability.neutralAlternatives,
    );
    expect(result.reason, RecommendationPanelReason.staleEvidence);
    expect(result.freshness, RecommendationEvidenceFreshness.stale);
    expect(result.recommendedMode, isNull);
    expect(result.alternatives, isNotEmpty);
  });

  test(
    'empty evidence uses preferences only to order neutral choices',
    () async {
      await _seedPreferences(
        database,
        ownerId: 'owner-1',
        activityPreference: LearnerActivityPreference.reading,
      );
      final changesBefore = await _totalChanges(database);

      final result = await useCases().load();

      expect(
        result.availability,
        RecommendationResultAvailability.neutralAlternatives,
      );
      expect(result.reason, RecommendationPanelReason.missingEvidence);
      expect(result.freshness, RecommendationEvidenceFreshness.missing);
      expect(result.alternatives.first, LessonMode.cefrReading);
      expect(await _totalChanges(database), changesBefore);
    },
  );

  test('corrupt canonical evidence fails closed without a write', () async {
    await _insertCorruptAttempt(database, now: now);
    final changesBefore = await _totalChanges(database);

    final result = await useCases().load();

    expect(
      result.availability,
      RecommendationResultAvailability.neutralAlternatives,
    );
    expect(result.reason, RecommendationPanelReason.corruptEvidence);
    expect(result.freshness, RecommendationEvidenceFreshness.corrupt);
    expect(result.recommendedMode, isNull);
    expect(await _totalChanges(database), changesBefore);
  });

  test('an unavailable mode is never recommended', () async {
    await _recordAttempt(
      database,
      ownerId: 'owner-1',
      wordId: 'word-1',
      occurredAtUtc: now.subtract(const Duration(minutes: 5)),
      isCorrect: false,
    );

    final result = await useCases(
      availableModes: const {LessonMode.meaningQuiz, LessonMode.typedRecall},
    ).load();

    expect(result.recommendedMode, isNull);
    expect(result.reason, RecommendationPanelReason.modeUnavailable);
    expect(result.alternatives, isNot(contains(LessonMode.flashcard)));
    expect(result.alternatives, [
      LessonMode.meaningQuiz,
      LessonMode.typedRecall,
    ]);
  });

  test(
    'ordinary learner override is explicit reversible and read only',
    () async {
      await _recordAttempt(
        database,
        ownerId: 'owner-1',
        wordId: 'word-1',
        occurredAtUtc: now.subtract(const Duration(minutes: 5)),
        isCorrect: false,
      );
      await _seedPreferences(
        database,
        ownerId: 'owner-1',
        activityPreference: LearnerActivityPreference.vocabulary,
      );
      final changesBefore = await _totalChanges(database);

      final overridden = await useCases().load(
        learnerOverride: LessonMode.meaningQuiz,
      );
      final restored = await useCases().load();

      expect(overridden.recommendedMode, LessonMode.meaningQuiz);
      expect(overridden.reason, RecommendationPanelReason.learnerOverride);
      expect(overridden.learnerOverrideApplied, isTrue);
      expect(restored.recommendedMode, LessonMode.flashcard);
      expect(restored.learnerOverrideApplied, isFalse);
      expect(await _totalChanges(database), changesBefore);
    },
  );

  test('protocol lock denies an out-of-protocol override', () async {
    await _recordAttempt(
      database,
      ownerId: 'owner-1',
      wordId: 'word-1',
      occurredAtUtc: now.subtract(const Duration(minutes: 5)),
      isCorrect: false,
    );
    final protocol = RecallLadderProtocolLimits(
      ownerId: 'owner-1',
      assignmentId: 'assignment-1',
      version: RecallLadderProtocolLimits.currentVersion,
      capturedAtUtc: now.subtract(const Duration(minutes: 1)),
      lockedModes: LessonMode.values
          .where((mode) => mode != LessonMode.typedRecall)
          .toSet(),
    );

    final result = await useCases().load(
      protocol: protocol,
      learnerOverride: LessonMode.speaking,
    );

    expect(result.recommendedMode, isNull);
    expect(result.reason, RecommendationPanelReason.protocolLocked);
    expect(
      result.protocolConstraint,
      RecommendationProtocolConstraint.overrideDenied,
    );
    expect(result.learnerOverrideApplied, isFalse);
    expect(result.alternatives, [LessonMode.typedRecall]);
  });

  test('owner isolation and equal-rank ordering are deterministic', () async {
    await _seedOwnerAndWord(
      database,
      ownerId: 'owner-1',
      wordId: 'word-a',
      spelling: 'alpha',
      active: true,
    );
    final occurredAt = now.subtract(const Duration(minutes: 5));
    await _recordAttempt(
      database,
      ownerId: 'owner-1',
      wordId: 'word-1',
      occurredAtUtc: occurredAt,
      isCorrect: false,
    );
    await _recordAttempt(
      database,
      ownerId: 'owner-1',
      wordId: 'word-a',
      occurredAtUtc: occurredAt,
      isCorrect: false,
    );
    await _recordAttempt(
      database,
      ownerId: 'owner-2',
      wordId: 'word-2',
      occurredAtUtc: occurredAt,
      isCorrect: false,
    );
    final changesBefore = await _totalChanges(database);

    final first = await useCases().load();
    final second = await useCases().load();

    expect(first.contentId, 'word-a');
    expect(second.contentId, first.contentId);
    expect(first.ownerId, 'owner-1');
    expect(await _totalChanges(database), changesBefore);
  });

  test('no eligible activity returns a typed unavailable result', () async {
    final result = await useCases(availableModes: const {}).load();

    expect(result.availability, RecommendationResultAvailability.unavailable);
    expect(result.reason, RecommendationPanelReason.noEligibleActivity);
    expect(result.recommendedMode, isNull);
    expect(result.alternatives, isEmpty);
  });

  test('empty production database stays unchanged and unavailable', () async {
    final emptyDatabase = AppDatabase(NativeDatabase.memory());
    addTearDown(emptyDatabase.close);
    final changesBefore = await _totalChanges(emptyDatabase);
    final subject = RecommendationUseCases(
      activeOwnerId: () async => 'missing-owner',
      reader: DriftRecommendationReader(emptyDatabase),
      nowUtc: () => now,
      timezoneId: 'Asia/Bangkok',
      modeAvailability: {
        for (final mode in LessonMode.values)
          mode: RecallLadderModeAvailability.available,
      },
    );

    final result = await subject.load();

    expect(result.availability, RecommendationResultAvailability.unavailable);
    expect(
      result.reason,
      RecommendationPanelReason.canonicalAuthorityUnavailable,
    );
    expect(
      await emptyDatabase.select(emptyDatabase.localOwners).get(),
      isEmpty,
    );
    expect(
      await emptyDatabase.select(emptyDatabase.streakStates).get(),
      isEmpty,
    );
    expect(await _totalChanges(emptyDatabase), changesBefore);
  });

  test('cross-owner session reference fails closed as corrupt', () async {
    await _insertCrossOwnerAttempt(
      database,
      now: now,
      crossSessionOwner: true,
      crossWordOwner: false,
    );

    final result = await useCases().load();

    expect(
      result.availability,
      RecommendationResultAvailability.neutralAlternatives,
    );
    expect(result.reason, RecommendationPanelReason.corruptEvidence);
    expect(result.freshness, RecommendationEvidenceFreshness.corrupt);
    expect(result.recommendedMode, isNull);
  });

  test('cross-owner word reference fails closed as corrupt', () async {
    await _insertCrossOwnerAttempt(
      database,
      now: now,
      crossSessionOwner: false,
      crossWordOwner: true,
    );

    final result = await useCases().load();

    expect(
      result.availability,
      RecommendationResultAvailability.neutralAlternatives,
    );
    expect(result.reason, RecommendationPanelReason.corruptEvidence);
    expect(result.freshness, RecommendationEvidenceFreshness.corrupt);
    expect(result.recommendedMode, isNull);
  });

  test('equal-ranked duplicate spellings use word id across reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-recommendation-order-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}app.sqlite');
    AppDatabase? openDatabase;
    try {
      final first = AppDatabase(NativeDatabase(file));
      openDatabase = first;
      await _seedOwnerAndWord(
        first,
        ownerId: 'owner-order',
        wordId: 'word-b',
        spelling: 'same',
        active: true,
      );
      await _seedOwnerAndWord(
        first,
        ownerId: 'owner-order',
        wordId: 'word-a',
        spelling: 'same',
        active: true,
      );
      final occurredAt = now.subtract(const Duration(minutes: 5));
      await _recordAttempt(
        first,
        ownerId: 'owner-order',
        wordId: 'word-b',
        occurredAtUtc: occurredAt,
        isCorrect: false,
      );
      await _recordAttempt(
        first,
        ownerId: 'owner-order',
        wordId: 'word-a',
        occurredAtUtc: occurredAt,
        isCorrect: false,
      );
      final beforeReopen = await _recommendForOwner(
        first,
        ownerId: 'owner-order',
        now: now,
      );
      await first.close();
      openDatabase = null;

      final reopened = AppDatabase(NativeDatabase(file));
      openDatabase = reopened;
      final afterReopen = await _recommendForOwner(
        reopened,
        ownerId: 'owner-order',
        now: now,
      );

      expect(beforeReopen.contentId, 'word-a');
      expect(afterReopen.contentId, 'word-a');
    } finally {
      await openDatabase?.close();
      await directory.delete(recursive: true);
    }
  });
}

Future<void> _seedOwnerAndWord(
  AppDatabase database, {
  required String ownerId,
  required String wordId,
  required String spelling,
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
        mode: InsertMode.insertOrIgnore,
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
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: wordId,
          ownerId: ownerId,
          categoryId: 'category:$ownerId',
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: 'meaning:$wordId',
          normalizedMeaning: 'meaning:$wordId',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
        mode: InsertMode.insertOrIgnore,
      );
}

Future<void> _recordAttempt(
  AppDatabase database, {
  required String ownerId,
  required String wordId,
  required DateTime occurredAtUtc,
  required bool isCorrect,
}) async {
  final learning = DriftLearningRepository(database);
  final sessionId = 'session:$wordId:${occurredAtUtc.millisecondsSinceEpoch}';
  await learning.startSession(
    LearningSessionDraft(
      id: sessionId,
      ownerId: ownerId,
      activityType: 'quiz',
      startedAtUtc: occurredAtUtc,
      appVersion: 'test',
      buildId: 'test',
    ),
  );
  await learning.recordAnswer(
    RecordAnswerCommand.frozenV13LegacyIngress(
      id: 'attempt:$wordId:${occurredAtUtc.millisecondsSinceEpoch}',
      ownerId: ownerId,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: 'meaningChoice',
      isCorrect: isCorrect,
      responseTimeMs: 100,
      attemptNumber: 1,
      occurredAtUtc: occurredAtUtc,
      evidenceContext:
          LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
    ),
  );
}

Future<void> _seedPreferences(
  AppDatabase database, {
  required String ownerId,
  required LearnerActivityPreference activityPreference,
}) => database
    .into(database.learnerPreferences)
    .insert(
      LearnerPreferencesCompanion.insert(
        ownerId: ownerId,
        preferenceVersion: 1,
        goal: LearnerPreferenceGoal.balancedGrowth.name,
        availableMinutesPerDay: 20,
        activityPreference: activityPreference.name,
        updatedAtUtcMs: 1,
      ),
    );

Future<void> _insertCorruptAttempt(
  AppDatabase database, {
  required DateTime now,
}) async {
  final occurredAt = now.subtract(const Duration(minutes: 1));
  final sessionId = 'session:corrupt';
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: 'owner-1',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: occurredAt.millisecondsSinceEpoch,
          appVersion: 'test',
          buildId: 'test',
        ),
      );
  final canonical = jsonEncode(
    LearningEvidenceContract.frozenV13LegacyEvidenceContext().toJson(),
  );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt:corrupt',
          ownerId: 'owner-1',
          sessionId: sessionId,
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: false,
          attemptNumber: 1,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          evidenceClass: const Value('independentRecall'),
          evidenceContextJson: Value(' $canonical'),
        ),
      );
}

Future<void> _insertCrossOwnerAttempt(
  AppDatabase database, {
  required DateTime now,
  required bool crossSessionOwner,
  required bool crossWordOwner,
}) async {
  final occurredAt = now.subtract(const Duration(minutes: 1));
  final suffix = '${crossSessionOwner ? 'session' : 'word'}-mismatch';
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session:$suffix',
          ownerId: crossSessionOwner ? 'owner-2' : 'owner-1',
          activityType: 'quiz',
          state: 'active',
          startedAtUtcMs: occurredAt.millisecondsSinceEpoch,
          appVersion: 'test',
          buildId: 'test',
        ),
      );
  final context = LearningEvidenceContract.frozenV13LegacyEvidenceContext();
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt:$suffix',
          ownerId: 'owner-1',
          sessionId: 'session:$suffix',
          wordId: crossWordOwner ? 'word-2' : 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: false,
          attemptNumber: 1,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          evidenceClass: Value(context.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(context.toJson())),
        ),
      );
}

Future<RecommendationPanelResult> _recommendForOwner(
  AppDatabase database, {
  required String ownerId,
  required DateTime now,
}) => RecommendationUseCases(
  activeOwnerId: () async => ownerId,
  reader: DriftRecommendationReader(database),
  nowUtc: () => now,
  timezoneId: 'Asia/Bangkok',
  modeAvailability: {
    for (final mode in LessonMode.values)
      mode: RecallLadderModeAvailability.available,
  },
).load();

Future<int> _totalChanges(AppDatabase database) async =>
    (await database.customSelect('SELECT total_changes() AS value').getSingle())
        .read<int>('value');
