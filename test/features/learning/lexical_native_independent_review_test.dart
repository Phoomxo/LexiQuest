import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/authored_lexical_pack.dart';
import '../../support/configured_quiz_harness.dart';

void main() {
  for (final purchase in [true, false]) {
    test(
      'independent deletion fence rejects cosmetic ${purchase ? 'purchase' : 'equip'} without ledger or outbox changes',
      () async {
        final h = await ConfiguredQuizHarness.open();
        addTearDown(h.close);
        await h.database.customInsert(
          'INSERT INTO points_ledger_entries (id, owner_id, idempotency_key, entry_type, amount, occurred_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
          variables: [
            const Variable<String>('synthetic-independent-points'),
            const Variable<String>(configuredOwnerId),
            const Variable<String>('synthetic-independent-points'),
            const Variable<String>('learning'),
            const Variable<int>(200),
            const Variable<int>(1),
          ],
        );
        final rewards = RewardUseCases(
          owners: h.owners,
          repository: DriftRewardRepository(h.database),
          generateId: () => 'synthetic-independent-cosmetic',
          nowUtc: () => h.now,
        );
        await h.ownerWrites.beginDeletion(
          ownerId: configuredOwnerId,
          firebaseUid: configuredFirebaseUid,
          idempotencyKey: 'synthetic-independent-delete',
        );
        final before = await h.snapshot();
        final denied = anyOf(
          isA<AccountDeletionException>(),
          isA<RewardException>().having(
            (error) => error.code,
            'code',
            RewardFailureCode.ownerChanged,
          ),
        );
        if (purchase) {
          await expectLater(
            rewards.purchase(
              expectedOwnerId: configuredOwnerId,
              itemId: 'theme_ocean',
              catalogVersion: RewardCatalog.version,
              idempotencyKey: 'synthetic-independent-fenced-purchase',
            ),
            throwsA(denied),
          );
        } else {
          await expectLater(
            rewards.equip(
              expectedOwnerId: configuredOwnerId,
              itemId: 'theme_default',
              idempotencyKey: 'synthetic-independent-fenced-equip',
            ),
            throwsA(denied),
          );
        }
        expect(await h.snapshot(), before);
      },
    );
  }

  for (final ownerAba in [false, true]) {
    test(
      'independent typed draft held read ${ownerAba ? 'rejects actual owner ABA' : 'accepts unchanged owner'}',
      () async {
        final fixture = await _Fixture.open();
        addTearDown(fixture.close);
        final state = await fixture.start();
        fixture.repository.holdNextResume = true;
        final pending = fixture.learning.saveQuizTypedDraft(
          sessionId: state.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: state.checkpointRevision,
          text: 'synthetic-independent-held-draft',
        );
        await fixture.repository.readCompleted.future;
        if (ownerAba) {
          var ids = 0;
          final upgrades = DriftOwnerUpgradeRepository(
            fixture.h.database,
            nowUtc: () => fixture.h.now,
            generateOwnerId: () => 'synthetic-independent-aba-${++ids}',
            generateConflictId: () => 'synthetic-independent-conflict-${++ids}',
          );
          final guest = await upgrades.createLocalGuestAfterLogout();
          await upgrades.rollbackLocalGuestLogout(
            previousOwnerId: configuredOwnerId,
            guestOwnerId: guest.targetOwnerId,
          );
          await Future<void>.delayed(Duration.zero);
        }
        final before = await fixture.h.snapshot();
        fixture.repository.release.complete();
        if (ownerAba) {
          await expectLater(pending, throwsStateError);
          expect(await fixture.h.snapshot(), before);
        } else {
          final saved = await pending;
          expect(
            (saved.checkpoint.lexical! as LexicalTypedLocalData).draft,
            'synthetic-independent-held-draft',
          );
          expect(saved.checkpointRevision, state.checkpointRevision + 1);
        }
        expect(await fixture.h.count('answer_attempts'), 0);
        expect((await fixture.h.researchCounts()).values, everyElement(0));
      },
    );
  }
}

final class _Fixture {
  _Fixture(this.h);
  final ConfiguredQuizHarness h;
  late final LearningPackUseCases packs;
  late final _HeldResumeRepository repository;
  late final LearningUseCases learning;
  late String packVersionId;
  int ids = 0;

  static Future<_Fixture> open() async {
    final fixture = _Fixture(await ConfiguredQuizHarness.open());
    final reader = DriftLearningPackRepository(
      database: fixture.h.database,
      ownerWrites: fixture.h.ownerWrites,
    );
    fixture.packs = LearningPackUseCases(
      repository: reader,
      nowUtc: () => fixture.h.now,
      generateId: () => 'synthetic-independent-pack-${++fixture.ids}',
    );
    final owner = await fixture.packs.captureOwner(stillCurrent: () => true);
    final pack = await fixture.packs.importPack(
      fixture.packs.prepareImport(scope: owner!, pack: authoredLexicalPack()),
    );
    fixture.packVersionId = pack.id;
    fixture.repository = _HeldResumeRepository(
      DriftLearningRepository(
        fixture.h.database,
        ownerWrites: fixture.h.ownerWrites,
        lexicalContent: reader,
      ),
    );
    fixture.learning = LearningUseCases(
      owners: fixture.h.owners,
      repository: fixture.repository,
      generateId: () => 'synthetic-independent-quiz-${++fixture.ids}',
      nowUtc: () => fixture.h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic-independent',
        buildId: 'synthetic-independent',
      ),
    );
    return fixture;
  }

  Future<ConfiguredQuizState> start() async => learning.startConfiguredQuiz(
    await learning.prepareLexicalQuiz(
      expectedOwnerId: configuredOwnerId,
      packVersionId: packVersionId,
      entryCodes: const ['cat'],
      input: LexicalQuizInput.definitionTyped,
      limit: 1,
      stillCurrent: () => true,
    ),
  );

  Future<void> close() async {
    if (!repository.release.isCompleted) repository.release.complete();
    await packs.dispose();
    await h.close();
  }
}

final class _HeldResumeRepository
    implements
        LearningRepository,
        ConfiguredQuizRepository,
        LexicalQuizRepository {
  _HeldResumeRepository(this.actual);
  final DriftLearningRepository actual;
  bool holdNextResume = false;
  final readCompleted = Completer<void>();
  final release = Completer<void>();

  @override
  Future<AcceptedQuizPlan> prepareLexicalQuizPlan({
    required LearningSessionDraft session,
    required LexicalQuizConfiguration configuration,
    required bool Function() stillCurrent,
  }) => actual.prepareLexicalQuizPlan(
    session: session,
    configuration: configuration,
    stillCurrent: stillCurrent,
  );

  @override
  Future<ConfiguredQuizState?> findConfiguredQuizStart(
    ConfiguredQuizLaunch launch,
  ) => actual.findConfiguredQuizStart(launch);

  @override
  Future<ConfiguredQuizState> startConfiguredQuiz({
    required LearningSessionDraft session,
    required AcceptedQuizPlan plan,
  }) => actual.startConfiguredQuiz(session: session, plan: plan);

  @override
  Future<ConfiguredQuizState> resumeQuiz({
    required String sessionId,
    required String expectedOwnerId,
  }) async {
    final state = await actual.resumeQuiz(
      sessionId: sessionId,
      expectedOwnerId: expectedOwnerId,
    );
    if (holdNextResume) {
      holdNextResume = false;
      readCompleted.complete();
      await release.future;
    }
    return state;
  }

  @override
  Future<ConfiguredQuizState> saveQuizCheckpoint({
    required String sessionId,
    required String expectedOwnerId,
    required int expectedRevision,
    required QuizCheckpoint checkpoint,
  }) => actual.saveQuizCheckpoint(
    sessionId: sessionId,
    expectedOwnerId: expectedOwnerId,
    expectedRevision: expectedRevision,
    checkpoint: checkpoint,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
