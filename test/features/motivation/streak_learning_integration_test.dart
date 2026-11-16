import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

class _Owners implements LocalOwnerRepository {
  _Owners(this.owner);
  final LocalOwner owner;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async => owner;
}

void main() {
  setUpAll(tz.initializeTimeZones);
  late AppDatabase db;
  late _Owners owners;
  late DateTime now;
  late DriftStreakRepository repository;
  late StreakUseCases streak;
  late LearningUseCases learning;
  var sequence = 0;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 8, 4, 10);
    sequence = 0;
    owners = _Owners(
      LocalOwner(
        id: 'a',
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
      ),
    );
    await db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES ('a',1,1)",
    );
    await db.customStatement(
      "INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('cat','a','Test','test',1,1)",
    );
    await db.customStatement(
      "INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES ('word','a','cat','hello','hello','hi','hi','noun',1,1)",
    );
    repository = DriftStreakRepository(db);
    streak = StreakUseCases(
      repository: repository,
      owners: owners,
      nowUtc: () => now,
    );
    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(db),
      generateId: () => '${++sequence}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'synthetic', buildId: 'synthetic'),
      onAnswerCommitted: streak.afterAnswerCommitted,
    );
  });
  tearDown(() => db.close());

  test('real correct and incorrect answers settle one studied day', () async {
    final session = await learning.startQuiz();
    Future<void> answer(String id, bool correct, int number) async => learning
        .recordAnswer(
          sessionId: session.id,
          wordId: 'word',
          promptMode: 'meaningChoice',
          isCorrect: correct,
          responseTimeMs: 100,
          attemptNumber: number,
          attemptId: id,
          occurredAtUtc: now,
        )
        .then((_) {});
    await answer('first', true, 1);
    await answer('second', false, 2);
    await answer('first', true, 1);
    final view = await repository.loadLearningDays(ownerId: 'a', asOfUtc: now);
    expect(view.status, StreakFoldStatus.ready);
    expect(view.currentStreakDays, 1);
    expect(view.days.where((day) => day.studied), hasLength(1));
    expect(await db.select(db.learningDayLog).get(), hasLength(1));
    expect(await db.select(db.eventsV2).get(), isEmpty);
    expect(await db.select(db.researchConsents).get(), isEmpty);
  });

  test(
    'optional callback failure leaves an answer for explicit recovery',
    () async {
      final failing = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(db),
        generateId: () => '${++sequence}',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(
          version: 'synthetic',
          buildId: 'synthetic',
        ),
        onAnswerCommitted:
            ({
              required ownerId,
              required attemptId,
              required occurredAtUtcMs,
            }) async {
              throw StateError('synthetic settlement failure');
            },
      );
      final session = await failing.startQuiz();
      await failing.recordAnswer(
        sessionId: session.id,
        wordId: 'word',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
      expect(
        (await repository.loadLearningDays(ownerId: 'a', asOfUtc: now)).status,
        StreakFoldStatus.pending,
      );
      final recovered = await streak.settle(expectedOwnerId: 'a');
      expect(
        (recovered.status, recovered.currentStreakDays),
        (StreakFoldStatus.ready, 1),
      );
      expect(await db.select(db.eventsV2).get(), isEmpty);
    },
  );
}
