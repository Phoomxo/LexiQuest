import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/data/drift_offline_content_repository.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_repository.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

void main() {
  test('corrupt repeated opens remain quarantined after restart', () async {
    final store = _DurableCatalogStore(_state(OfflineContentStatus.verified));
    final firstManager = _ScenarioManager(
      store,
      verifyError: const OfflineContentFailure(
        OfflineContentFailureCode.checksumMismatch,
      ),
    );
    final first = AdventureCatalogRecoveryOperations(
      manager: firstManager,
      diagnostics: AdventureDiagnostics(),
      delay: (_) async {},
    );

    expect(
      (await first.verify(_identity)).status,
      AdventureCatalogRecoveryStatus.quarantined,
    );
    expect(
      (await first.verify(_identity)).status,
      AdventureCatalogRecoveryStatus.quarantined,
    );
    expect(firstManager.verifyCalls, 1);
    await first.dispose();

    final restartedManager = _ScenarioManager(store);
    final restarted = AdventureCatalogRecoveryOperations(
      manager: restartedManager,
      diagnostics: AdventureDiagnostics(),
      delay: (_) async {},
    );
    final reopened = await restarted.verify(_identity);

    expect(reopened.status, AdventureCatalogRecoveryStatus.quarantined);
    expect(reopened.attempts, 0);
    expect(restartedManager.verifyCalls, 0);
    await restarted.dispose();
  });

  test('network flap repair has a bounded three-attempt backoff', () async {
    final store = _DurableCatalogStore(
      _state(
        OfflineContentStatus.interrupted,
        failureCode: OfflineContentFailureCode.interrupted,
      ),
    );
    final manager = _ScenarioManager(
      store,
      repairOutcomes: <Object?>[
        TimeoutException('offline'),
        const OfflineContentFailure(OfflineContentFailureCode.interrupted),
        null,
      ],
    );
    final delays = <Duration>[];
    final operations = AdventureCatalogRecoveryOperations(
      manager: manager,
      diagnostics: AdventureDiagnostics(),
      maxAttempts: 3,
      baseBackoff: const Duration(milliseconds: 25),
      delay: (duration) async => delays.add(duration),
    );

    final result = await operations.repair(_identity);

    expect(result.status, AdventureCatalogRecoveryStatus.repaired);
    expect(result.attempts, 3);
    expect(manager.repairCalls, 3);
    expect(delays, const <Duration>[
      Duration(milliseconds: 25),
      Duration(milliseconds: 50),
    ]);
    await operations.dispose();
  });

  test(
    'asset removal preserves canonical learning evidence and progress',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-adventure-recovery-',
      );
      try {
        final bytes = Uint8List.fromList(<int>[7, 8, 9, 10]);
        final identity = await _seedLearningState(database, bytes);
        final repository = DriftOfflineContentRepository(database);
        final manager = VerifiedOfflineContentManager(
          repository: repository,
          adapters: <OfflineContentDownloadAdapter>[_BytesAdapter(bytes)],
          removalAuthority: const UnpinnedOfflineContentRemovalAuthority(),
          rootDirectory: () async => directory,
          nowUtc: () => DateTime.utc(2026, 9, 4, 9),
        );
        final operations = AdventureCatalogRecoveryOperations(
          manager: manager,
          diagnostics: AdventureDiagnostics(),
          managerOwnership: AdventureCatalogManagerOwnership.owned,
          delay: (_) async {},
        );
        expect(
          (await operations.repair(identity)).status,
          AdventureCatalogRecoveryStatus.repaired,
        );
        final rewards = DriftRewardRepository(database);
        final rewardAccountBefore = await rewards.load('owner:adventure');
        final before = <String, int>{
          'learning_sessions': await _tableCount(database, 'learning_sessions'),
          'answer_attempts': await _tableCount(database, 'answer_attempts'),
          'events_v2': await _tableCount(database, 'events_v2'),
          'srs_states': await _tableCount(database, 'srs_states'),
          'reading_progress_entries': await _tableCount(
            database,
            'reading_progress_entries',
          ),
          'points_ledger_entries': await _tableCount(
            database,
            'points_ledger_entries',
          ),
          'reward_transactions': await _tableCount(
            database,
            'reward_transactions',
          ),
        };

        final removal = await operations.remove(identity);

        expect(removal.status, AdventureCatalogRecoveryStatus.removed);
        expect(removal.removedBytes, bytes.length);
        expect(<String, int>{
          'learning_sessions': await _tableCount(database, 'learning_sessions'),
          'answer_attempts': await _tableCount(database, 'answer_attempts'),
          'events_v2': await _tableCount(database, 'events_v2'),
          'srs_states': await _tableCount(database, 'srs_states'),
          'reading_progress_entries': await _tableCount(
            database,
            'reading_progress_entries',
          ),
          'points_ledger_entries': await _tableCount(
            database,
            'points_ledger_entries',
          ),
          'reward_transactions': await _tableCount(
            database,
            'reward_transactions',
          ),
        }, before);
        final rewardAccountAfter = await rewards.load('owner:adventure');
        expect(rewardAccountAfter.coinBalance, rewardAccountBefore.coinBalance);
        expect(
          rewardAccountAfter.transactionCount,
          rewardAccountBefore.transactionCount,
        );
        expect(
          rewardAccountAfter.ownedItemIds,
          rewardAccountBefore.ownedItemIds,
        );
        expect(
          rewardAccountAfter.equippedBySlot,
          rewardAccountBefore.equippedBySlot,
        );
        expect(
          (await repository.state(identity)).status,
          OfflineContentStatus.notDownloaded,
        );
        await operations.dispose();
      } finally {
        await database.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
  );

  test(
    'owned dispose drains active recovery and closes the manager once',
    () async {
      final store = _DurableCatalogStore(
        _state(
          OfflineContentStatus.interrupted,
          failureCode: OfflineContentFailureCode.interrupted,
        ),
      );
      final started = Completer<void>();
      final release = Completer<void>();
      final manager = _ScenarioManager(
        store,
        repairStarted: started,
        repairRelease: release,
      );
      final operations = AdventureCatalogRecoveryOperations(
        manager: manager,
        diagnostics: AdventureDiagnostics(),
        managerOwnership: AdventureCatalogManagerOwnership.owned,
        delay: (_) async {},
      );
      final repair = operations.repair(_identity);
      await started.future;
      final disposal = operations.dispose();
      expect(() => operations.verify(_identity), throwsStateError);
      var disposalCompleted = false;
      disposal.whenComplete(() => disposalCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposalCompleted, isFalse);
      release.complete();
      expect((await repair).status, AdventureCatalogRecoveryStatus.unavailable);
      await disposal;
      await operations.dispose();
      expect(manager.disposeCalls, 1);
    },
  );
}

const _identity = ContentIdentity(
  type: ContentType.offlineArtifact,
  id: 'lexiquest.adventure.world-v1',
  revision: 1,
);

OfflineContentState _state(
  OfflineContentStatus status, {
  OfflineContentFailureCode? failureCode,
}) => OfflineContentState(
  manifestId: 'manifest:lexiquest.adventure.world-v1',
  identity: _identity,
  status: status,
  localPath: status == OfflineContentStatus.verified
      ? '${'a' * 64}.content'
      : null,
  downloadedBytes: status == OfflineContentStatus.verified ? 4 : 0,
  verifiedChecksumSha256: status == OfflineContentStatus.verified
      ? 'b' * 64
      : null,
  failureCode: failureCode,
  updatedAtUtc: DateTime.utc(2026, 9, 4, 9),
);

final class _DurableCatalogStore {
  _DurableCatalogStore(this.state);

  OfflineContentState state;
}

final class _ScenarioManager
    implements OfflineContentManager, OfflineContentStateInspector {
  _ScenarioManager(
    this.store, {
    this.verifyError,
    List<Object?> repairOutcomes = const <Object?>[],
    this.repairStarted,
    this.repairRelease,
  }) : repairOutcomes = List<Object?>.of(repairOutcomes);

  final _DurableCatalogStore store;
  final Object? verifyError;
  final List<Object?> repairOutcomes;
  final Completer<void>? repairStarted;
  final Completer<void>? repairRelease;
  int verifyCalls = 0;
  int repairCalls = 0;
  int disposeCalls = 0;

  @override
  Future<List<OfflineContentState>> catalog() async => <OfflineContentState>[
    store.state,
  ];

  @override
  Future<OfflineContentState> inspect(ContentIdentity identity) async =>
      store.state;

  @override
  Future<OfflineContentState> verify(ContentIdentity identity) async {
    verifyCalls += 1;
    final error = verifyError;
    if (error != null) {
      if (error is OfflineContentFailure) {
        store.state = _state(
          OfflineContentStatus.quarantined,
          failureCode: error.code,
        );
      }
      throw error;
    }
    return store.state;
  }

  @override
  Future<OfflineContentState> repair(ContentIdentity identity) async {
    repairCalls += 1;
    if (!(repairStarted?.isCompleted ?? true)) repairStarted!.complete();
    await repairRelease?.future;
    final outcome = repairOutcomes.isEmpty ? null : repairOutcomes.removeAt(0);
    if (outcome != null) throw outcome;
    store.state = _state(OfflineContentStatus.verified);
    return store.state;
  }

  @override
  Future<OfflineContentState> download(ContentIdentity identity) async =>
      store.state;

  @override
  Future<bool> canRemove(ContentIdentity identity) async => true;

  @override
  Future<int> removeBytes(ContentIdentity identity) async {
    store.state = _state(OfflineContentStatus.notDownloaded);
    return 4;
  }

  @override
  Future<int> cleanupForDiskPressure({required int bytesToFree}) async => 0;

  @override
  Future<void> reconcile() async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await repairRelease?.future;
  }
}

final class _BytesAdapter implements OfflineContentDownloadAdapter {
  _BytesAdapter(this.bytes);

  final Uint8List bytes;

  @override
  bool supports(ContentManifest manifest) => true;

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) =>
      temporaryFile.writeAsBytes(bytes, flush: true);

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {}

  @override
  Future<int> installedBytes(ContentManifest manifest) async => 0;

  @override
  Future<int> removeInstalled(ContentManifest manifest) async => 0;
}

Future<ContentIdentity> _seedLearningState(
  AppDatabase database,
  Uint8List bytes,
) async {
  const identity = ContentIdentity(
    type: ContentType.offlineArtifact,
    id: 'lexiquest.adventure.world-v1',
    revision: 1,
  );
  await database.customInsert(
    "INSERT INTO local_owners "
    "(id, account_state, created_at_utc_ms, is_active) "
    "VALUES ('owner:adventure', 'localGuest', 1, 1)",
  );
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: 'manifest:lexiquest.adventure.world-v1',
          contentType: identity.type.name,
          contentId: identity.id,
          revision: identity.revision,
          checksumSha256: sha256.convert(bytes).toString(),
          byteLength: bytes.length,
          provenance: ContentProvenance.packaged.name,
          sourceUri: 'https://example.invalid/adventure-world-v1.bin',
          reviewState: ContentReviewState.approved.name,
          publicationState: ContentPublicationState.published.name,
          createdAtUtcMs: 1,
          reviewedAtUtcMs: const Value<int>(2),
          publishedAtUtcMs: const Value<int>(3),
        ),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:adventure',
          ownerId: 'owner:adventure',
          name: 'Adventure',
          normalizedName: 'adventure',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word:adventure',
          ownerId: 'owner:adventure',
          categoryId: 'category:adventure',
          spelling: 'journey',
          normalizedSpelling: 'journey',
          meaning: 'การเดินทาง',
          normalizedMeaning: 'การเดินทาง',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: 'owner:adventure',
    mode: LessonMode.meaningQuiz,
    itemCount: 1,
    direction: SessionDirection.forward,
    difficulty: SessionDifficulty.standard,
    hintBudget: 0,
    timing: const SessionTiming.untimedAlternative(
      maximumActiveEffort: Duration(minutes: 5),
    ),
    packIdentity: null,
    protocolId: 'protocol:adventure',
    protocolVersion: '1',
    protocolLimitsIdentity: 'limits:adventure',
  );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session:adventure',
          ownerId: 'owner:adventure',
          activityType: 'meaningQuiz',
          state: 'completed',
          startedAtUtcMs: 10,
          appVersion: '1.0.0',
          buildId: 'task-6.1',
          sessionConfigurationIdentity: Value(configuration.contentIdentity),
          sessionConfigurationJson: Value(configuration.stableSerialization),
        ),
      );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt:adventure',
          ownerId: 'owner:adventure',
          sessionId: 'session:adventure',
          wordId: 'word:adventure',
          promptMode: 'meaningChoice',
          isCorrect: true,
          attemptNumber: 1,
          occurredAtUtcMs: 20,
        ),
      );
  await database
      .into(database.srsStates)
      .insert(
        SrsStatesCompanion.insert(
          id: 'srs:adventure',
          ownerId: 'owner:adventure',
          wordId: 'word:adventure',
          stability: const Value<double>(2),
          difficulty: const Value<double>(4),
          intervalDays: const Value<int>(3),
          repetitions: const Value<int>(1),
          lapses: const Value<int>(0),
          lastReviewAtUtcMs: const Value<int>(20),
          dueAtUtcMs: 30,
          algorithmVersion: 1,
        ),
      );
  await database
      .into(database.readingProgressEntries)
      .insert(
        ReadingProgressEntriesCompanion.insert(
          id: 'reading-progress:adventure',
          ownerId: 'owner:adventure',
          documentId: 'document:adventure',
          documentRevision: const Value<int>(1),
          lastPosition: const Value<int>(7),
          isCompleted: const Value<bool>(false),
          updatedAtUtcMs: 20,
        ),
      );
  await DriftRewardRepository(database).grantQuestXpAndCoins(
    ownerId: 'owner:adventure',
    sourceEventId: 'learning-event:adventure',
    xpAmount: 10,
    occurredAtUtc: DateTime.utc(2026, 9, 4, 9),
  );
  await database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: 'learning-projection:reward:learning-event:adventure:v2',
          eventType: 'LearningProjectionApplied',
          eventVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 9, 4, 9),
          recordedAtUtc: DateTime.utc(2026, 9, 4, 9),
          actorIdentity: 'owner:adventure',
          ownerId: 'owner:adventure',
          aggregateType: 'LearningProjection',
          aggregateId: 'learning-event:adventure',
          causationId: const Value<String>('learning-event:adventure'),
          idempotencyKey:
              'learning-projection:reward:learning-event:adventure:v2',
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'task-6.1',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode(<String, Object>{
            'sourceEventId': 'learning-event:adventure',
            'projection': 'reward',
            'appliedVersion': 2,
            'outcome': 'applied',
            'result': <String, Object>{},
          }),
        ),
      );
  return identity;
}

Future<int> _tableCount(AppDatabase database, String table) async {
  final row = await database
      .customSelect('SELECT COUNT(*) AS count FROM $table')
      .getSingle();
  return row.read<int>('count');
}
