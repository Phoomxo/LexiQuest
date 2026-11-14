import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_motivation_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

final _at = DateTime.utc(2027, 1, 5, 12);

void main() {
  setUpAll(tz.initializeTimeZones);
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late DriftRewardRepository repository;
  late String instanceId;
  var notifications = 0;

  RewardUseCases useCases({LocalOwnerRepository? authority}) => RewardUseCases(
    owners: authority ?? owners,
    repository: repository,
    generateId: () => 'unused-claim-id',
    nowUtc: () => _at.add(const Duration(seconds: 1)),
    onLocalMutation: () => notifications++,
  );

  setUp(() async {
    notifications = 0;
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'unused-owner',
      nowUtc: () => _at,
    );
    for (final owner in ['owner-a', 'owner-b']) {
      await database.customStatement(
        'INSERT INTO local_owners(id,account_state,created_at_utc_ms,is_active) VALUES (?,?,1,?)',
        [owner, 'localGuest', owner == 'owner-a' ? 1 : 0],
      );
    }
    await database.customStatement(
      "INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('category','owner-a','Synthetic','synthetic',1,1)",
    );
    await database.customStatement(
      "INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,source,created_at_utc_ms,updated_at_utc_ms) VALUES ('word','owner-a','category','station','station','สถานี','สถานี','noun','manual',1,1)",
    );
    final catalog = await DriftQuestRepository(database).installAnswerCatalog();
    final learning = DriftLearningRepository(
      database,
      questCatalog: catalog,
      questVisible: () => true,
    );
    await learning.startSession(
      LearningSessionDraft(
        id: 'session',
        ownerId: 'owner-a',
        activityType: 'quiz',
        startedAtUtc: _at,
        appVersion: 'test',
        buildId: 'synthetic',
      ),
    );
    for (var i = 0; i < 5; i++) {
      await learning.recordAnswer(
        RecordAnswerCommand(
          id: 'answer-$i',
          ownerId: 'owner-a',
          sessionId: 'session',
          wordId: 'word',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 10,
          attemptNumber: i + 1,
          occurredAtUtc: _at.add(Duration(milliseconds: i)),
        ),
      );
    }
    final answer = await (database.select(
      database.answerAttempts,
    )..where((row) => row.id.equals('answer-0'))).getSingle();
    instanceId = (decodeQuestIntent(answer.questIntent!) as CapturedQuestIntent)
        .dailyPeriodId;
    repository = DriftRewardRepository(
      database,
      questCatalog: catalog,
      questVisible: () => true,
      nowUtc: () => _at.add(const Duration(seconds: 1)),
    );
  });
  tearDown(() => database.close());

  test(
    'claim use case fences stale owner before granting or notifying',
    () async {
      await expectLater(
        useCases().claimQuest(
          expectedOwnerId: 'owner-b',
          instanceId: instanceId,
        ),
        throwsA(
          isA<RewardException>().having(
            (e) => e.code,
            'code',
            RewardFailureCode.ownerChanged,
          ),
        ),
      );
      expect(await database.select(database.questClaimReceipts).get(), isEmpty);
      expect(await database.select(database.questInstances).get(), isEmpty);
      expect(notifications, 0);
    },
  );

  test(
    'claim use case returns original receipt and notifies only a new grant',
    () async {
      final first = await useCases().claimQuest(
        expectedOwnerId: 'owner-a',
        instanceId: instanceId,
      );
      expect(
        (first.ownerId, first.xpAmount, first.replayed),
        ('owner-a', 50, false),
      );
      final replay = await useCases().claimQuest(
        expectedOwnerId: 'owner-a',
        instanceId: instanceId,
      );
      expect(
        (
          replay.receiptId,
          replay.issuedAtUtc,
          replay.xpAmount,
          replay.replayed,
        ),
        (first.receiptId, first.issuedAtUtc, 50, true),
      );
      expect(notifications, 1);
      expect(
        await database.select(database.questClaimReceipts).get(),
        hasLength(1),
      );
      expect((await repository.load('owner-a')).balance, 5);
      final xp = await database
          .customSelect(
            "SELECT SUM(amount) AS n FROM points_ledger_entries WHERE owner_id='owner-a'",
          )
          .getSingle();
      expect(xp.read<int>('n'), 55);
      expect(await database.select(database.eventsV2).get(), isEmpty);
    },
  );

  test(
    'owner change after committed claim hides old result without duplicating grant',
    () async {
      final authority = _SwitchAfterClaim(database, owners);
      await expectLater(
        useCases(
          authority: authority,
        ).claimQuest(expectedOwnerId: 'owner-a', instanceId: instanceId),
        throwsA(
          isA<RewardException>().having(
            (e) => e.code,
            'code',
            RewardFailureCode.ownerChanged,
          ),
        ),
      );
      final receipt = await database
          .select(database.questClaimReceipts)
          .getSingle();
      expect(receipt.ownerId, 'owner-a');
      expect((await owners.getOrCreateActiveOwner()).id, 'owner-b');
      expect((await repository.load('owner-b')).balance, 0);
      expect(
        await database.select(database.questClaimReceipts).get(),
        hasLength(1),
      );
    },
  );
}

final class _SwitchAfterClaim extends Fake implements LocalOwnerRepository {
  _SwitchAfterClaim(this.database, this.delegate);
  final AppDatabase database;
  final LocalOwnerRepository delegate;
  var reads = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    if (++reads == 2) {
      await database.customStatement(
        "UPDATE local_owners SET is_active=CASE WHEN id='owner-b' THEN 1 ELSE 0 END",
      );
    }
    return delegate.getOrCreateActiveOwner();
  }
}
