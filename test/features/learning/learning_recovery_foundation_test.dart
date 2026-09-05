import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  test(
    'file-backed exact recovery restores one pending answer through two retries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-learning-recovery-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}learning.db',
      );
      AppDatabase? database;
      try {
        database = AppDatabase(NativeDatabase(file));
        var firstId = 0;
        final firstOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'recovery-owner',
          nowUtc: () => DateTime.utc(2026, 8, 30, 12),
        );
        final owner = await firstOwners.getOrCreateActiveOwner();
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'category:recovery',
                ownerId: owner.id,
                name: 'Recovery',
                normalizedName: 'recovery',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        for (final word in const <(String, String, String)>[
          ('word:recover', 'recover', 'กู้คืน'),
          ('word:resume', 'resume', 'ทำต่อ'),
        ]) {
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: word.$1,
                  ownerId: owner.id,
                  categoryId: 'category:recovery',
                  spelling: word.$2,
                  normalizedSpelling: word.$2,
                  meaning: word.$3,
                  normalizedMeaning: word.$3,
                  partOfSpeech: 'verb',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
        }
        final firstLearning = LearningUseCases(
          owners: firstOwners,
          repository: DriftLearningRepository(database),
          generateId: () => 'first-${++firstId}',
          nowUtc: () => DateTime.utc(2026, 8, 30, 12, 0, firstId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'recovery-test',
          ),
        );
        final session = await firstLearning.startCheckpointedQuiz(
          activityType: 'adventureRepair',
          pinnedContent: <PinnedQuizContent>[
            _recoveryPin('word:recover', 'recover', 'กู้คืน'),
          ],
          limit: 1,
          initialState: (_) => const <String, Object?>{
            'schemaVersion': 1,
            'pendingEvidence': null,
          },
        );
        final captured = CurrentActivityEvidenceAdapter(learning: firstLearning)
            .capture(
              ownerId: owner.id,
              input: CurrentActivityInput.typedRecall,
              sessionId: session.id,
              wordId: 'word:recover',
              isCorrect: true,
              responseTimeMs: 842,
              attemptNumber: 1,
              providerProvenance: 'keyboard|local|v1',
            );
        final frozen = await captured.freezeForRecovery();
        await firstLearning.appendActivityCheckpoint(
          LearningActivityCheckpoint(
            sessionId: session.id,
            activityType: 'adventureRepair',
            revision: 2,
            occurredAtUtc: DateTime.utc(2026, 8, 30, 12, 1),
            state: <String, Object?>{
              'schemaVersion': 1,
              'pendingEvidence': frozen.toJson(),
            },
          ),
          ownerId: owner.id,
        );
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        await database.close();
        database = null;

        database = AppDatabase(NativeDatabase(file));
        var reopenedId = 0;
        final reopenedOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => DateTime.utc(2026, 8, 30, 13),
        );
        final durableRepository = DriftLearningRepository(database);
        final recoveryReader = LearningUseCases(
          owners: reopenedOwners,
          repository: durableRepository,
          generateId: () => 'reader-${++reopenedId}',
          nowUtc: () => DateTime.utc(2026, 8, 30, 13, 0, reopenedId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'recovery-test',
          ),
        );
        final recovery = await recoveryReader.loadExactActivityRecovery(
          ownerId: owner.id,
          sessionId: session.id,
          activityType: 'adventureRepair',
        );
        expect(recovery, isNotNull);
        expect(recovery!.session.id, session.id);
        expect(recovery.attempts, isEmpty);
        final checkpointState = recovery.checkpoint!.state;
        final frozenJson = (checkpointState['pendingEvidence']! as Map)
            .cast<String, Object?>();
        final decoded = FrozenPendingCurrentActivityEvidence.fromJson(
          (jsonDecode(jsonEncode(frozenJson)) as Map).cast<String, Object?>(),
        );
        expect(decoded.toJson(), frozen.toJson());

        final lostAcknowledgement = _LoseFirstRecordAcknowledgement(
          durableRepository,
        );
        final reopenedLearning = LearningUseCases(
          owners: reopenedOwners,
          repository: lostAcknowledgement,
          generateId: () => 'retry-${++reopenedId}',
          nowUtc: () => DateTime.utc(2026, 8, 30, 13, 1, reopenedId),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'recovery-test',
          ),
        );
        final restored = CurrentActivityEvidenceAdapter(
          learning: reopenedLearning,
        ).restore(decoded);

        await expectLater(restored.record(), throwsStateError);
        await expectLater(restored.retry(), throwsStateError);
        expect(restored.requiresRetry, isTrue);
        await database.close();
        database = null;

        database = AppDatabase(NativeDatabase(file));
        final finalRepository = DriftLearningRepository(database);
        final finalOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-final-owner',
          nowUtc: () => DateTime.utc(2026, 8, 30, 14),
        );
        final finalLearning = LearningUseCases(
          owners: finalOwners,
          repository: finalRepository,
          generateId: () => 'unexpected-final-id',
          nowUtc: () => DateTime.utc(2026, 8, 30, 14, 1),
          buildInfo: const AppBuildInfo(
            version: 'test',
            buildId: 'recovery-test',
          ),
        );
        final finalRecovery = await finalLearning.loadExactActivityRecovery(
          ownerId: owner.id,
          sessionId: session.id,
          activityType: 'adventureRepair',
        );
        expect(finalRecovery!.attempts, hasLength(1));
        final afterTermination = CurrentActivityEvidenceAdapter(
          learning: finalLearning,
        ).restore(decoded);
        await expectLater(afterTermination.record(), throwsStateError);
        final replay = await afterTermination.retry();
        expect(replay.isCorrect, isTrue);
        expect(replay.inserted, isFalse);
        expect(afterTermination.isCommitted, isTrue);

        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(1));
        expect(attempts.single.id, frozen.sourceEvidenceId);
        final expectedEventId = LearningEvidenceContract.learningEventId(
          frozen.sourceEvidenceId,
        );
        final sourceEvents = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(expectedEventId))).get();
        expect(sourceEvents, hasLength(1));
        expect(sourceEvents.single.eventId, expectedEventId);
        expect(
          attempts.map((attempt) => attempt.id).toSet().length,
          attempts.length,
        );
        expect(
          sourceEvents.map((event) => event.eventId).toSet().length,
          sourceEvents.length,
        );
        expect(
          (await database.select(database.eventsV2).get()).where(
            (event) => event.eventType == 'LearningEvidenceDecisionSet',
          ),
          hasLength(1),
        );
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          hasLength(1),
        );
        expect(
          await database.select(database.achievementUnlocks).get(),
          hasLength(2),
        );
        expect(
          (await database.select(database.outboxOperations).get()).where(
            (operation) =>
                operation.entityType == 'attempt' &&
                operation.entityId == frozen.sourceEvidenceId,
          ),
          hasLength(1),
        );
        expect(await database.select(database.srsStates).get(), hasLength(1));
        expect(
          await database.select(database.rewardTransactions).get(),
          isEmpty,
        );
      } finally {
        await database?.close();
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test(
    'generic frozen pre-write retry uses the upgraded session owner',
    () => _expectGenericOwnerUpgrade(writeBeforeUpgrade: false),
  );

  test(
    'generic frozen post-write replay preserves the historical actor',
    () => _expectGenericOwnerUpgrade(writeBeforeUpgrade: true),
  );
}

Future<void> _expectGenericOwnerUpgrade({
  required bool writeBeforeUpgrade,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  try {
    final suffix = writeBeforeUpgrade ? 'post' : 'pre';
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'upgrade-guest-$suffix',
      nowUtc: () => DateTime.utc(2026, 8, 30, 14),
    );
    final guest = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category:upgrade-$suffix',
            ownerId: guest.id,
            name: 'Upgrade',
            normalizedName: 'upgrade',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word:upgrade-$suffix',
            ownerId: guest.id,
            categoryId: 'category:upgrade-$suffix',
            spelling: 'upgrade',
            normalizedSpelling: 'upgrade',
            meaning: 'อัปเกรด',
            normalizedMeaning: 'อัปเกรด',
            partOfSpeech: 'verb',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    final firstLearning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'upgrade-$suffix',
      nowUtc: () => DateTime.utc(2026, 8, 30, 14, 1),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'upgrade-test'),
    );
    final session = await firstLearning.startQuiz(
      categoryId: 'category:upgrade-$suffix',
      limit: 1,
    );
    final pending = CurrentActivityEvidenceAdapter(learning: firstLearning)
        .capture(
          ownerId: guest.id,
          input: CurrentActivityInput.typedRecall,
          sessionId: session.id,
          wordId: 'word:upgrade-$suffix',
          isCorrect: true,
          responseTimeMs: 420,
          attemptNumber: 1,
        );
    final frozen = await pending.freezeForRecovery();
    if (writeBeforeUpgrade) await pending.record();

    final accountId = 'upgrade-account-$suffix';
    final firebaseUid = 'firebase-upgrade-$suffix';
    await database.customInsert(
      'INSERT INTO local_owners '
      '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
      "VALUES ('$accountId', '$firebaseUid', 'firebaseBound', 2, 0)",
    );
    var upgradeId = 0;
    await DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 8, 30, 14, 2),
      generateConflictId: () => 'upgrade-conflict-${++upgradeId}',
      generateOwnerId: () => 'unexpected-upgrade-owner',
      generateOwnerOperationToken: () => 'upgrade-operation-$suffix',
      deleteOwnerSecrets: (_) async {},
    ).upgrade(activeOwnerId: guest.id, firebaseUid: firebaseUid);

    final reopenedLearning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'unused-$suffix',
      nowUtc: () => DateTime.utc(2026, 8, 30, 14, 3),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'upgrade-test'),
    );
    final restored = CurrentActivityEvidenceAdapter(
      learning: reopenedLearning,
    ).restore(frozen, ownerId: accountId);
    await expectLater(restored.record(), throwsStateError);
    final result = await restored.retry();

    expect(result.inserted, !writeBeforeUpgrade);
    final attempt = await database.select(database.answerAttempts).getSingle();
    expect(attempt.ownerId, accountId);
    final event =
        await (database.select(database.eventsV2)..where(
              (row) => row.eventId.equals(
                LearningEvidenceContract.learningEventId(
                  frozen.sourceEvidenceId,
                ),
              ),
            ))
            .getSingle();
    expect(event.ownerId, accountId);
    expect(event.actorIdentity, writeBeforeUpgrade ? guest.id : accountId);
  } finally {
    await database.close();
  }
}

PinnedQuizContent _recoveryPin(String id, String spelling, String meaning) =>
    PinnedQuizContent(
      identity: ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: id,
        revision: 1,
      ),
      checksumSha256: ContentQualityPolicy.vocabularyChecksumSha256(
        categoryId: 'category:recovery',
        spelling: spelling,
        normalizedSpelling: spelling,
        meaning: meaning,
        normalizedMeaning: meaning,
        partOfSpeech: 'verb',
        cefrLevel: null,
        source: 'manual',
        isGlobal: false,
      ),
    );

final class _LoseFirstRecordAcknowledgement
    implements LearningRepository, LearningEvidenceReplayRepository {
  _LoseFirstRecordAcknowledgement(this.delegate);

  final DriftLearningRepository delegate;
  bool _loseAcknowledgement = true;

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) => delegate.replayCommittedAnswer(candidate);

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    final result = await delegate.recordAnswer(command);
    if (_loseAcknowledgement) {
      _loseAcknowledgement = false;
      throw StateError('simulated lost acknowledgement');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
