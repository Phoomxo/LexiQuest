import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/progress/application/learning_calendar_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_calendar_reader.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  late AppDatabase database;
  late DriftLearningCalendarReader reader;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    reader = DriftLearningCalendarReader(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
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
            id: 'word-1',
            ownerId: 'owner-1',
            categoryId: 'category-1',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  });

  tearDown(() => database.close());

  test(
    'uses the learner-local Monday boundary for daily and weekly buckets',
    () async {
      await _insertSession(database, id: 'session-week-boundary');
      await _insertAttempt(
        database,
        id: 'attempt-prior-week',
        sessionId: 'session-week-boundary',
        occurredAtUtc: DateTime.utc(2026, 8, 23, 16, 59),
        isCorrect: false,
        evidence: _practiceEvidence(skillId: 'listening'),
      );
      await _insertAttempt(
        database,
        id: 'attempt-current-week',
        sessionId: 'session-week-boundary',
        occurredAtUtc: DateTime.utc(2026, 8, 23, 17, 1),
        isCorrect: true,
        evidence: _practiceEvidence(skillId: 'listening'),
      );
      await _insertSegment(
        database,
        id: 'segment-current-week',
        sessionId: 'session-week-boundary',
        startedAtUtc: DateTime.utc(2026, 8, 23, 17, 1),
        activeDurationMs: 90000,
      );

      final calendar = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 8, 23, 17, 1),
        timezoneId: 'Asia/Bangkok',
      );

      expect(calendar.weekStart, DateTime(2026, 8, 24));
      expect(calendar.days, hasLength(7));
      final monday = calendar.days.first;
      expect(monday.day, DateTime(2026, 8, 24));
      expect(monday.effort.activeDuration, const Duration(seconds: 90));
      expect(monday.accuracy.sampleSize, 1);
      expect(monday.accuracy.correctCount, 1);
      expect(calendar.weekly.accuracy.sampleSize, 1);
    },
  );

  test(
    'allocates a Sunday 23:59:30 segment across both Monday weeks',
    () async {
      await _insertSession(database, id: 'session-cross-week');
      await _insertSegment(
        database,
        id: 'segment-cross-week',
        sessionId: 'session-cross-week',
        // Sunday 23:59:30 in Bangkok; the next local day starts at 17:00 UTC.
        startedAtUtc: DateTime.utc(2026, 8, 23, 16, 59, 30),
        activeDurationMs: 90000,
      );

      final previousWeek = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 8, 23, 16, 59, 30),
        timezoneId: 'Asia/Bangkok',
      );
      final currentWeek = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 8, 23, 17),
        timezoneId: 'Asia/Bangkok',
      );

      expect(
        previousWeek.days.last.effort.activeDuration,
        const Duration(seconds: 30),
      );
      expect(
        currentWeek.days.first.effort.activeDuration,
        const Duration(seconds: 60),
      );
      expect(
        previousWeek.weekly.effort.activeDuration +
            currentWeek.weekly.effort.activeDuration,
        const Duration(seconds: 90),
      );
    },
  );

  test(
    'keeps canonical effort intact through the spring DST transition',
    () async {
      await _insertSession(database, id: 'session-spring-dst');
      await _insertSegment(
        database,
        id: 'segment-spring-dst',
        sessionId: 'session-spring-dst',
        // 01:59:30 EST becomes 03:01:00 EDT after 90 seconds.
        startedAtUtc: DateTime.utc(2026, 3, 8, 6, 59, 30),
        activeDurationMs: 90000,
      );

      final calendar = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 3, 8, 12),
        timezoneId: 'America/New_York',
      );

      expect(calendar.days.last.day, DateTime(2026, 3, 8));
      expect(
        calendar.days.last.effort.activeDuration,
        const Duration(seconds: 90),
      );
    },
  );

  test(
    'allocates the exact millisecond remainder across a DST fall-back Monday boundary',
    () async {
      await _insertSession(database, id: 'session-fall-dst');
      await _insertSegment(
        database,
        id: 'segment-fall-dst',
        sessionId: 'session-fall-dst',
        // Sunday 23:59:59.500 EST after the fall-back transition.
        startedAtUtc: DateTime.utc(2026, 11, 2, 4, 59, 59, 500),
        activeDurationMs: 1501,
      );

      final previousWeek = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 11, 2, 4, 59, 59, 500),
        timezoneId: 'America/New_York',
      );
      final currentWeek = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 11, 2, 5),
        timezoneId: 'America/New_York',
      );

      expect(
        previousWeek.days.last.effort.activeDuration,
        const Duration(milliseconds: 500),
      );
      expect(
        currentWeek.days.first.effort.activeDuration,
        const Duration(milliseconds: 1001),
      );
      expect(
        previousWeek.weekly.effort.activeDuration +
            currentWeek.weekly.effort.activeDuration,
        const Duration(milliseconds: 1501),
      );
    },
  );

  test(
    'keeps canonical effort exact through the repeated fall-back hour',
    () async {
      await _insertSession(database, id: 'session-fall-hour');
      await _insertSegment(
        database,
        id: 'segment-fall-hour',
        sessionId: 'session-fall-hour',
        // 01:59:30 EDT becomes 01:01:00 EST after 90 canonical seconds.
        startedAtUtc: DateTime.utc(2026, 11, 1, 5, 59, 30),
        activeDurationMs: 90000,
      );

      final calendar = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 11, 1, 12),
        timezoneId: 'America/New_York',
      );

      expect(calendar.days.last.day, DateTime(2026, 11, 1));
      expect(
        calendar.days.last.effort.activeDuration,
        const Duration(seconds: 90),
      );
    },
  );

  test(
    'returns immutable zero-valued effort and null accuracy for an empty week',
    () async {
      final calendar = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 8, 26, 12),
        timezoneId: 'Asia/Bangkok',
      );

      expect(calendar.days, hasLength(7));
      expect(
        calendar.days.every(
          (bucket) =>
              bucket.effort.activeDuration == Duration.zero &&
              bucket.accuracy.sampleSize == 0 &&
              bucket.accuracy.accuracy == null &&
              bucket.skillDistribution.isEmpty,
        ),
        isTrue,
      );
      expect(calendar.weekly.accuracy.accuracy, isNull);
      expect(calendar.weekly.accuracyTrend, hasLength(7));
      expect(
        () => calendar.days.add(calendar.days.first),
        throwsUnsupportedError,
      );
      expect(
        () => calendar.weekly.accuracyTrend.add(
          calendar.weekly.accuracyTrend.first,
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('includes assessment active time only on the effort axis', () async {
    await _insertSession(database, id: 'session-practice');
    await _insertSession(database, id: 'session-assessment');
    await _insertAttempt(
      database,
      id: 'attempt-practice',
      sessionId: 'session-practice',
      occurredAtUtc: DateTime.utc(2026, 8, 25, 3),
      isCorrect: true,
      evidence: _practiceEvidence(skillId: 'listening'),
    );
    await _insertAttempt(
      database,
      id: 'attempt-assessment',
      sessionId: 'session-assessment',
      occurredAtUtc: DateTime.utc(2026, 8, 25, 3, 1),
      isCorrect: false,
      evidence: _assessmentEvidence(),
    );
    await _insertSegment(
      database,
      id: 'segment-practice',
      sessionId: 'session-practice',
      startedAtUtc: DateTime.utc(2026, 8, 25, 3),
      activeDurationMs: 30000,
    );
    await _insertSegment(
      database,
      id: 'segment-assessment',
      sessionId: 'session-assessment',
      startedAtUtc: DateTime.utc(2026, 8, 25, 3, 1),
      activeDurationMs: 45000,
    );

    final calendar = await reader.loadWeek(
      ownerId: 'owner-1',
      referenceUtc: DateTime.utc(2026, 8, 26, 12),
      timezoneId: 'Asia/Bangkok',
    );
    final tuesday = calendar.days[1];

    expect(calendar.weekly.effort.activeDuration, const Duration(seconds: 75));
    expect(tuesday.effort.activeDuration, const Duration(seconds: 75));
    expect(calendar.weekly.accuracy.sampleSize, 1);
    expect(calendar.weekly.accuracy.correctCount, 1);
    expect(calendar.weekly.skillDistribution, hasLength(1));
    expect(calendar.weekly.skillDistribution.single.skillId, 'listening');
    expect(calendar.weekly.accuracyTrend[1].accuracy.sampleSize, 1);
    expect(
      await database.select(database.answerAttempts).get(),
      hasLength(2),
      reason: 'the read model must not create or rewrite response evidence',
    );
  });

  test(
    'orders skill distribution deterministically without combining axes',
    () async {
      await _insertSession(database, id: 'session-skills');
      await _insertAttempt(
        database,
        id: 'attempt-zulu',
        sessionId: 'session-skills',
        occurredAtUtc: DateTime.utc(2026, 8, 26, 3),
        isCorrect: false,
        evidence: _practiceEvidence(skillId: 'zulu'),
      );
      await _insertAttempt(
        database,
        id: 'attempt-alpha',
        sessionId: 'session-skills',
        occurredAtUtc: DateTime.utc(2026, 8, 26, 3, 1),
        isCorrect: true,
        evidence: _practiceEvidence(skillId: 'alpha'),
      );

      final first = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 8, 26, 12),
        timezoneId: 'Asia/Bangkok',
      );
      final second = await reader.loadWeek(
        ownerId: 'owner-1',
        referenceUtc: DateTime.utc(2026, 8, 26, 12),
        timezoneId: 'Asia/Bangkok',
      );

      expect(first.weekly.skillDistribution.map((skill) => skill.skillId), [
        'alpha',
        'zulu',
      ]);
      expect(second.weekly.skillDistribution.map((skill) => skill.skillId), [
        'alpha',
        'zulu',
      ]);
      expect(first.weekly.effort.activeDuration, Duration.zero);
      expect(first.weekly.accuracy.accuracy, 0.5);
      expect(first.weekly.accuracyTrend[2].accuracy.accuracy, 0.5);
    },
  );

  test(
    'use cases resolve the active owner and current UTC week locally',
    () async {
      final useCases = LearningCalendarUseCases(
        owners: const _Owners(),
        reader: reader,
        nowUtc: () => DateTime.utc(2026, 8, 26, 12),
        timezoneId: 'Asia/Bangkok',
      );

      final calendar = await useCases.loadCurrentWeek();

      expect(calendar.weekStart, DateTime(2026, 8, 24));
      expect(calendar.days, hasLength(7));
    },
  );

  test('use cases reject a non-UTC week reference', () async {
    final useCases = LearningCalendarUseCases(
      owners: const _Owners(),
      reader: reader,
      nowUtc: () => DateTime.utc(2026, 8, 26, 12),
      timezoneId: 'Asia/Bangkok',
    );

    await expectLater(
      useCases.loadWeek(DateTime(2026, 8, 26, 12)),
      throwsArgumentError,
    );
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

Future<void> _insertSession(AppDatabase database, {required String id}) =>
    database
        .into(database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: id,
            ownerId: 'owner-1',
            activityType: 'quiz',
            state: 'completed',
            startedAtUtcMs: DateTime.utc(2026, 8, 23).millisecondsSinceEpoch,
            appVersion: 'test',
            buildId: 'test',
          ),
        );

Future<void> _insertAttempt(
  AppDatabase database, {
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
        ownerId: 'owner-1',
        sessionId: sessionId,
        wordId: 'word-1',
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
  required String id,
  required String sessionId,
  required DateTime startedAtUtc,
  required int activeDurationMs,
}) => database
    .into(database.learningTimeSegments)
    .insert(
      LearningTimeSegmentsCompanion.insert(
        id: id,
        ownerId: 'owner-1',
        sessionId: sessionId,
        activeStartOffsetMs: 0,
        activeDurationMs: activeDurationMs,
        startedAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
        endedAtUtcMs: startedAtUtc
            .add(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
        timezoneId: 'Asia/Bangkok',
        timezoneOffsetMinutes: 420,
        captureSource: 'automaticLesson',
      ),
    );

EvidenceContext _practiceEvidence({required String skillId}) =>
    EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: skillId,
      hintLevel: 0,
      contentRevision: 'content-v1',
      engagementAllowed: false,
    );

EvidenceContext _assessmentEvidence() => EvidenceContext.legacyCompatibility(
  evidenceClass: EvidenceClass.assessment,
  skillId: 'assessment-skill',
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
