import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

class _FakeOwners implements LocalOwnerRepository {
  final LocalOwner _owner;
  _FakeOwners(this._owner);
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => _owner;
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async =>
      _owner;
}

void main() {
  setUpAll(tz.initializeTimeZones);

  late db.AppDatabase database;
  late StreakUseCases streakUseCases;
  late LearningUseCases learningUseCases;
  late LocalOwner owner;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    owner = LocalOwner(id: 'owner-sli', createdAtUtc: DateTime.utc(2026, 8, 4));

    await database.customInsert(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
      "VALUES ('owner-sli', 'localGuest', 1722758400000)",
    );
    await database.customInsert(
      "INSERT INTO vocabulary_categories "
      "(id, owner_id, name, normalized_name, sort_order, local_revision, "
      "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
      "VALUES ('cat-1', 'owner-sli', 'Test', 'test', 0, 1, 0, 0, 10, 10)",
    );
    await database.customInsert(
      "INSERT INTO vocabulary_words "
      "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
      "normalized_meaning, part_of_speech, source, is_global, local_revision, "
      "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
      "VALUES ('word-1', 'owner-sli', 'cat-1', 'hello', 'hello', "
      "'สวัสดี', 'สวัสดี', 'interjection', 'manual', 0, 1, 0, 0, 10, 10)",
    );

    streakUseCases = StreakUseCases(
      repository: DriftStreakRepository(database),
      owners: _FakeOwners(owner),
      nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
      timezoneId: 'Asia/Bangkok',
    );

    learningUseCases = LearningUseCases(
      owners: _FakeOwners(owner),
      repository: DriftLearningRepository(database),
      generateId: () => 'id-${DateTime.now().microsecondsSinceEpoch}',
      nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
      buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha-test'),
      streakEventSink: () => streakUseCases.recordLearningDay().then((_) {}),
    );
  });

  tearDown(() async => database.close());

  group('StreakEventSink — D8.1 Streak-Learning integration', () {
    test('recordAnswer triggers streak start on first session', () async {
      final session = await learningUseCases.startQuiz(limit: 10);
      expect(session.questions, isNotEmpty);

      await learningUseCases.recordAnswer(
        sessionId: session.id,
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 300,
        attemptNumber: 1,
      );

      final state = await streakUseCases.getCurrentStreak();
      expect(
        state.currentStreakDays,
        1,
        reason: 'first recordAnswer must start streak at 1',
      );
    });

    test('streakEventSink null = no crash (streak not wired)', () async {
      final noStreakUseCases = LearningUseCases(
        owners: _FakeOwners(owner),
        repository: DriftLearningRepository(database),
        generateId: () => 'ns-${DateTime.now().microsecondsSinceEpoch}',
        nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
        buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha'),
        // streakEventSink intentionally absent
      );
      final session = await noStreakUseCases.startQuiz(limit: 10);
      await expectLater(
        noStreakUseCases.recordAnswer(
          sessionId: session.id,
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 300,
          attemptNumber: 1,
        ),
        completes,
      );
    });

    test('learning day log records entry on first answer', () async {
      final session = await learningUseCases.startQuiz(limit: 10);
      await learningUseCases.recordAnswer(
        sessionId: session.id,
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 500,
        attemptNumber: 1,
      );

      final days = await DriftStreakRepository(
        database,
      ).getLearningDays('owner-sli');
      expect(days, hasLength(1));
      expect(
        days.first,
        '2026-08-04',
        reason: 'learning day log must record Bangkok date',
      );
    });

    test('streak outcome is sameDay on second answer same session', () async {
      final session = await learningUseCases.startQuiz(limit: 10);
      // First answer — starts streak.
      await learningUseCases.recordAnswer(
        sessionId: session.id,
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 300,
        attemptNumber: 1,
      );
      // Second answer same UTC day — must be idempotent.
      await learningUseCases.recordAnswer(
        sessionId: session.id,
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 400,
        attemptNumber: 2,
      );

      final state = await streakUseCases.getCurrentStreak();
      expect(
        state.currentStreakDays,
        1,
        reason: 'same-day answer must not extend streak',
      );
    });
  });
}
