import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_progress_reader.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_progress_models.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
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
  test('real answers determine daily Quest and explicit claim once', () async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 8, 4, 10);
    final owners = _Owners(
      LocalOwner(id: 'owner-qi', createdAtUtc: DateTime.utc(2026)),
    );
    await _seed(database);
    final catalog = await DriftQuestRepository(database).installAnswerCatalog();
    var sequence = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        database,
        questCatalog: catalog,
        questVisible: () => true,
      ),
      generateId: () => '${++sequence}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'synthetic', buildId: 'synthetic'),
    );
    final reader = DriftQuestProgressReader(database, catalog: catalog);
    final rewardRepo = DriftRewardRepository(
      database,
      questCatalog: catalog,
      questVisible: () => true,
      nowUtc: () => now,
    );
    final rewards = RewardUseCases(
      owners: owners,
      repository: rewardRepo,
      generateId: () => 'unused',
      nowUtc: () => now,
    );
    final session = await learning.startQuiz();
    Future<void> answer(String id, bool correct, int number) async {
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: 'word',
        promptMode: 'meaningChoice',
        isCorrect: correct,
        responseTimeMs: 100,
        attemptNumber: number,
        attemptId: id,
        occurredAtUtc: now,
      );
    }

    Future<QuestProgressCard> daily() async => (await reader.load(
      ownerId: 'owner-qi',
      asOfUtc: now,
    )).current.singleWhere((card) => card.cadence == QuestType.daily);

    final empty = await daily();
    expect((empty.correctCount, empty.targetCount, empty.xpAmount), (0, 5, 50));
    expect((await daily()).instanceId, empty.instanceId);
    await answer('wrong', false, 1);
    expect((await daily()).correctCount, 0);
    for (var i = 0; i < 5; i++) {
      await answer('correct-$i', true, i + 1);
    }
    await answer('correct-0', true, 1);
    final complete = await daily();
    expect(
      (complete.correctCount, complete.state),
      (5, QuestProgressState.completedUnclaimed),
    );
    expect(await database.select(database.questClaimReceipts).get(), isEmpty);
    final receipt = await rewards.claimQuest(
      expectedOwnerId: 'owner-qi',
      instanceId: complete.instanceId,
    );
    expect((receipt.xpAmount, receipt.replayed), (50, false));
    final retry = await rewards.claimQuest(
      expectedOwnerId: 'owner-qi',
      instanceId: complete.instanceId,
    );
    expect((retry.receiptId, retry.replayed), (receipt.receiptId, true));
    expect(
      (await DriftProgressQueries(
        database,
      ).load(ownerId: 'owner-qi', nowUtc: now)).totalXp,
      55,
    );
    expect((await rewardRepo.load('owner-qi')).balance, 5);
    expect(await database.select(database.eventsV2).get(), isEmpty);
    expect(await database.select(database.researchConsents).get(), isEmpty);
  });

  test(
    'hidden Quest still records ordinary learning without Quest intent',
    () async {
      final database = db.AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 4, 10);
      final owners = _Owners(
        LocalOwner(id: 'owner-qi', createdAtUtc: DateTime.utc(2026)),
      );
      await _seed(database);
      var sequence = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => '${++sequence}',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(
          version: 'synthetic',
          buildId: 'synthetic',
        ),
      );
      final session = await learning.startQuiz();
      await learning.recordAnswer(
        sessionId: session.id,
        wordId: 'word',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
      );
      expect(
        (await database.select(database.answerAttempts).getSingle())
            .questIntent,
        isNull,
      );
      expect(
        await database.select(database.questDefinitionRevisions).get(),
        isEmpty,
      );
      expect(await database.select(database.questInstances).get(), isEmpty);
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.researchConsents).get(), isEmpty);
    },
  );
}

Future<void> _seed(db.AppDatabase database) async {
  await database.customStatement(
    "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES ('owner-qi',1,1)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('cat','owner-qi','Test','test',1,1)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES ('word','owner-qi','cat','hello','hello','hi','hi','noun',1,1)",
  );
}
