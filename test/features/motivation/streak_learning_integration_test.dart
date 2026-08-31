import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
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
  late LearningReconciliationScheduler learningReconciliation;
  late LocalOwner owner;
  var sequence = 0;

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

    await DriftStreakRepository(database).establishCutover(
      ownerId: owner.id,
      establishedAtUtc: DateTime.utc(2026, 8, 4, 9),
    );

    streakUseCases = StreakUseCases(
      repository: DriftStreakRepository(database),
      owners: _FakeOwners(owner),
      nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
      timezoneId: 'Asia/Bangkok',
    );
    const rolloutModeProvider = ContextEvidencePolicyRolloutModeProvider();
    learningReconciliation = LearningReconciliationScheduler(
      LearningSideEffectReconciler(
        database,
        rolloutModeProvider: rolloutModeProvider,
        streakSink: (event) async {
          final projection = await streakUseCases.projectEvent(event);
          return switch (projection.disposition) {
            StreakProjectionDisposition.applied =>
              LearningProjectionResult.applied(payload: projection.payload),
            StreakProjectionDisposition.notApplicable =>
              LearningProjectionResult.notApplicable(
                payload: <String, dynamic>{'reasonCode': projection.reasonCode},
              ),
            StreakProjectionDisposition.blocked =>
              LearningProjectionResult.blocked(
                reasonCode: projection.reasonCode!,
              ),
          };
        },
      ),
    );

    learningUseCases = LearningUseCases(
      owners: _FakeOwners(owner),
      repository: DriftLearningRepository(
        database,
        rolloutModeProvider: rolloutModeProvider,
      ),
      generateId: () => 'id-${++sequence}',
      nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
      buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha-test'),
      onSideEffectsPending: learningReconciliation.request,
    );
  });

  tearDown(() async {
    await learningReconciliation.dispose();
    await database.close();
  });

  group('Durable Streak reconciliation — D8.1 integration', () {
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
      await learningReconciliation.drain();

      final state = await streakUseCases.getCurrentStreak();
      expect(
        state.currentStreakDays,
        1,
        reason: 'first recordAnswer must start streak at 1',
      );
    });

    test('no scheduler persists without inline Streak execution', () async {
      final noStreakUseCases = LearningUseCases(
        owners: _FakeOwners(owner),
        repository: DriftLearningRepository(database),
        generateId: () => 'ns-${DateTime.now().microsecondsSinceEpoch}',
        nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
        buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha'),
        // Durable startup replay intentionally owns later projection.
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

      final progress = await DriftProgressQueries(
        database,
      ).load(ownerId: owner.id, nowUtc: DateTime.utc(2026, 8, 4, 10, 1));
      expect(progress.sampleSize, 1);
      expect(
        progress.streakDays,
        0,
        reason: 'Progress reads StreakStates and never attempt dates',
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
      await learningReconciliation.drain();

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
      await learningReconciliation.drain();
      // Second answer same UTC day — must be idempotent.
      await learningUseCases.recordAnswer(
        sessionId: session.id,
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 400,
        attemptNumber: 2,
      );
      await learningReconciliation.drain();

      final state = await streakUseCases.getCurrentStreak();
      expect(
        state.currentStreakDays,
        1,
        reason: 'same-day answer must not extend streak',
      );
    });

    test(
      'canonical eligible evidence advances with an exact v2 receipt',
      () async {
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'eligible-streak',
          evidenceContext: _researchEvidence(
            evidenceClass: EvidenceClass.independentRecall,
            rolloutMode: EvidencePolicyRolloutMode.enforced,
            engagementAllowed: true,
          ),
          onSideEffectsPending: learningReconciliation.request,
        );
        await learningReconciliation.drain();

        final state = await streakUseCases.getCurrentStreak();
        expect(state.currentStreakDays, 1);
        const sourceEventId = 'learning-event:eligible-streak';
        const receiptId = 'learning-projection:streak:$sourceEventId:v2';
        final receipt = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(receiptId))).getSingle();
        final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
        final result = payload['result'] as Map<String, dynamic>;
        expect(receipt.eventType, 'LearningProjectionApplied');
        expect(receipt.ownerId, owner.id);
        expect(receipt.aggregateId, sourceEventId);
        expect(receipt.causationId, sourceEventId);
        expect(receipt.idempotencyKey, receiptId);
        expect(payload['sourceEventId'], sourceEventId);
        expect(payload['projection'], 'streak');
        expect(payload['appliedVersion'], 2);
        expect(payload['outcome'], 'applied');
        expect(result, containsPair('ownerId', owner.id));
        expect(result, containsPair('learningDay', '2026-08-04'));
        expect(result, containsPair('policyVersion', 2));
        expect(
          result,
          containsPair('receiptId', 'gentle-streak:${owner.id}:2026-08-04:v2'),
        );
        expect(payload['decision'], <String, dynamic>{
          'projection': 'streak',
          'rolloutMode': 'enforced',
          'effectiveDecision': 'protocolControlled',
          'candidateV1Decision': null,
          'policyVersion': EvidenceContext.currentPolicyVersion,
          'divergence': false,
        });
      },
    );

    test(
      'assessment guided exposure recreational and denied evidence do not advance',
      () async {
        final denied = <EvidenceContext>[
          _researchEvidence(
            evidenceClass: EvidenceClass.assessment,
            rolloutMode: EvidencePolicyRolloutMode.enforced,
            engagementAllowed: false,
          ),
          _legacyDeclaredEvidence(EvidenceClass.guidedPractice),
          _legacyDeclaredEvidence(EvidenceClass.exposure),
          _legacyDeclaredEvidence(EvidenceClass.recreational),
          _researchEvidence(
            evidenceClass: EvidenceClass.independentRecall,
            rolloutMode: EvidencePolicyRolloutMode.enforced,
            engagementAllowed: false,
          ),
        ];

        for (var index = 0; index < denied.length; index++) {
          await _recordEvidence(
            database: database,
            owner: owner,
            sourceEvidenceId: 'denied-streak-$index',
            evidenceContext: denied[index],
            onSideEffectsPending: learningReconciliation.request,
          );
        }
        await learningReconciliation.drain();

        expect((await streakUseCases.getCurrentStreak()).currentStreakDays, 0);
        expect(
          await DriftStreakRepository(database).getLearningDays(owner.id),
          isEmpty,
        );
        for (var index = 0; index < denied.length; index++) {
          final receipt =
              await (database.select(database.eventsV2)..where(
                    (row) => row.eventId.equals(
                      'learning-projection:streak:'
                      'learning-event:denied-streak-$index:v2',
                    ),
                  ))
                  .getSingle();
          expect(receipt.eventType, 'LearningProjectionSkipped');
        }
      },
    );

    test('shadow divergence is diagnostic and does not advance', () async {
      await _recordEvidence(
        database: database,
        owner: owner,
        sourceEvidenceId: 'shadow-streak',
        evidenceContext: _researchEvidence(
          evidenceClass: EvidenceClass.independentRecall,
          rolloutMode: EvidencePolicyRolloutMode.shadow,
          engagementAllowed: false,
        ),
        onSideEffectsPending: learningReconciliation.request,
      );
      await learningReconciliation.drain();

      expect((await streakUseCases.getCurrentStreak()).currentStreakDays, 0);
      const receiptId =
          'learning-projection:streak:learning-event:shadow-streak:v2';
      final receipt = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(receiptId))).getSingle();
      final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
      expect(receipt.eventType, 'LearningProjectionSkipped');
      expect(payload['result'], <String, dynamic>{
        'reasonCode': 'shadowDivergence',
      });
      expect(payload['decision'], <String, dynamic>{
        'projection': 'streak',
        'rolloutMode': 'shadow',
        'effectiveDecision': 'allow',
        'candidateV1Decision': 'protocolControlled',
        'policyVersion': EvidenceContext.currentPolicyVersion,
        'divergence': true,
      });
    });

    test(
      'restart and concurrent replay recover one receipt without duplicate day',
      () async {
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'restart-streak',
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        await database.customStatement('''
          CREATE TEMP TRIGGER fail_streak_receipt
          BEFORE INSERT ON events_v2
          WHEN NEW.event_type = 'LearningProjectionApplied'
            AND json_extract(NEW.payload_json, '\$.projection') = 'streak'
          BEGIN SELECT RAISE(ABORT, 'injected streak receipt crash'); END
        ''');
        final first = _reconciler(database, streakUseCases);
        await first.reconcileOwner(owner.id);

        expect((await streakUseCases.getCurrentStreak()).currentStreakDays, 1);
        const receiptId =
            'learning-projection:streak:learning-event:restart-streak:v2';
        expect(
          await (database.select(
            database.eventsV2,
          )..where((row) => row.eventId.equals(receiptId))).getSingleOrNull(),
          isNull,
        );

        await database.customStatement('DROP TRIGGER fail_streak_receipt');
        final restarted = _reconciler(database, streakUseCases);
        await Future.wait<void>([
          restarted.reconcileOwner(owner.id),
          restarted.reconcileOwner(owner.id),
        ]);

        expect((await streakUseCases.getCurrentStreak()).currentStreakDays, 1);
        expect(
          await DriftStreakRepository(database).getLearningDays(owner.id),
          ['2026-08-04'],
        );
        expect(
          await (database.select(
            database.eventsV2,
          )..where((row) => row.eventId.equals(receiptId))).get(),
          hasLength(1),
        );
      },
    );

    test(
      'same-day receipt crash replays stored Bangkok result after timezone change',
      () async {
        final firstAt = DateTime.utc(2026, 8, 4, 0, 30);
        final secondAt = DateTime.utc(2026, 8, 4, 16, 30);
        final bangkokStreak = StreakUseCases(
          repository: DriftStreakRepository(database),
          owners: _FakeOwners(owner),
          nowUtc: () => secondAt,
          timezoneId: 'Asia/Bangkok',
        );
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'timezone-crash-a',
          occurredAtUtc: firstAt,
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        await _reconciler(database, bangkokStreak).reconcileOwner(owner.id);

        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'timezone-crash-b',
          occurredAtUtc: secondAt,
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        await database.customStatement('''
          CREATE TEMP TRIGGER fail_second_streak_receipt
          BEFORE INSERT ON events_v2
          WHEN NEW.event_type = 'LearningProjectionApplied'
            AND NEW.aggregate_id = 'learning-event:timezone-crash-b'
          BEGIN SELECT RAISE(ABORT, 'injected second streak receipt crash'); END
        ''');
        await _reconciler(database, bangkokStreak).reconcileOwner(owner.id);

        const applicationId =
            'streak-application:learning-event:timezone-crash-b';
        final application = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(applicationId))).getSingle();
        final applicationPayload =
            jsonDecode(application.payloadJson) as Map<String, dynamic>;
        expect(application.eventType, 'StreakPolicyApplied');
        expect(application.ownerId, owner.id);
        expect(applicationPayload, <String, dynamic>{
          'sourceEventId': 'learning-event:timezone-crash-b',
          'sourceOccurredAtUtcMs': secondAt.millisecondsSinceEpoch,
          'timezoneId': 'Asia/Bangkok',
          'outcome': 'sameDay',
          'result': <String, dynamic>{
            'receiptId': 'gentle-streak:${owner.id}:2026-08-04:v2',
            'ownerId': owner.id,
            'learningDay': '2026-08-04',
            'policyVersion': StreakPolicy.version,
            'currentStreakDays': 1,
            'longestStreakDays': 1,
            'freezeCount': 0,
          },
        });
        const receiptId =
            'learning-projection:streak:learning-event:timezone-crash-b:v2';
        expect(
          await (database.select(
            database.eventsV2,
          )..where((row) => row.eventId.equals(receiptId))).getSingleOrNull(),
          isNull,
        );

        await database.customStatement(
          'DROP TRIGGER fail_second_streak_receipt',
        );
        final pagoPagoStreak = StreakUseCases(
          repository: DriftStreakRepository(database),
          owners: _FakeOwners(owner),
          nowUtc: () => secondAt,
          timezoneId: 'Pacific/Pago_Pago',
        );
        final restarted = _reconciler(database, pagoPagoStreak);
        await Future.wait<void>([
          restarted.reconcileOwner(owner.id),
          restarted.reconcileOwner(owner.id),
        ]);

        expect((await pagoPagoStreak.getCurrentStreak()).currentStreakDays, 1);
        expect(
          await DriftStreakRepository(database).getLearningDays(owner.id),
          ['2026-08-04'],
        );
        final receipt = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(receiptId))).getSingle();
        final receiptPayload =
            jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
        expect(receiptPayload['result'], applicationPayload['result']);
        expect(
          await (database.select(
            database.eventsV2,
          )..where((row) => row.eventId.equals(applicationId))).get(),
          hasLength(1),
        );
      },
    );

    test(
      'empty startup reconcile preserves first post-startup event on retry',
      () async {
        await _reconciler(database, streakUseCases).reconcileOwner(owner.id);
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'first-after-empty-startup',
          occurredAtUtc: DateTime.utc(2026, 8, 4, 10),
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        final restarted = StreakUseCases(
          repository: DriftStreakRepository(database),
          owners: _FakeOwners(owner),
          nowUtc: () => DateTime.utc(2026, 8, 4, 10),
          timezoneId: 'Asia/Bangkok',
        );

        await Future.wait<void>([
          _reconciler(database, restarted).reconcileOwner(owner.id),
          _reconciler(database, restarted).reconcileOwner(owner.id),
        ]);

        expect((await restarted.getCurrentStreak()).currentStreakDays, 1);
        expect(
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'streak-application:'
                  'learning-event:first-after-empty-startup',
                ),
              ))
              .get(),
          hasLength(1),
        );
      },
    );

    test(
      'startup horizon blocks ambiguous history then permits newer evidence',
      () async {
        final firstAt = DateTime.utc(2026, 8, 4, 0, 30);
        final secondAt = DateTime.utc(2026, 8, 4, 16, 30);
        final afterBoundaryAt = DateTime.utc(2026, 8, 4, 17, 30);
        await (database.delete(
          database.eventsV2,
        )..where((row) => row.eventType.equals('StreakPolicyCutover'))).go();
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'cutover-a',
          occurredAtUtc: firstAt,
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'cutover-b',
          occurredAtUtc: secondAt,
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        final eventStore = DriftLearningEventStore(
          database,
          rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
        );
        final firstSource = await eventStore.readBySourceEvidenceId(
          'cutover-a',
        );
        await eventStore.markProjectionOutcome(
          source: firstSource!,
          projection: 'streak',
          appliedVersion: LearningSideEffectReconciler.appliedVersion,
          outcome: LearningProjectionOutcome.applied,
          result: <String, dynamic>{
            'receiptId': 'gentle-streak:${owner.id}:2026-08-04:v2',
            'ownerId': owner.id,
            'learningDay': '2026-08-04',
            'policyVersion': StreakPolicy.version,
            'currentStreakDays': 1,
            'longestStreakDays': 1,
            'freezeCount': 0,
          },
        );
        final repository = DriftStreakRepository(database);
        await repository.save(
          StreakState(
            ownerId: owner.id,
            currentStreakDays: 1,
            longestStreakDays: 1,
            freezeCount: 0,
            lastLearnedAtUtcMs: firstAt.millisecondsSinceEpoch,
            updatedAtUtcMs: firstAt.millisecondsSinceEpoch,
          ),
        );
        await repository.recordLearningDay(
          ownerId: owner.id,
          learningDay: '2026-08-04',
          firstSessionAtUtcMs: firstAt.millisecondsSinceEpoch,
        );
        await repository.establishCutover(
          ownerId: owner.id,
          establishedAtUtc: DateTime.utc(2026, 8, 4, 17),
        );
        final restarted = StreakUseCases(
          repository: repository,
          owners: _FakeOwners(owner),
          nowUtc: () => afterBoundaryAt,
          timezoneId: 'Pacific/Pago_Pago',
        );

        await _reconciler(database, restarted).reconcileOwner(owner.id);

        final state = await restarted.getCurrentStreak();
        expect(state.currentStreakDays, 1);
        expect(state.lastLearnedAtUtcMs, firstAt.millisecondsSinceEpoch);
        expect(await repository.getLearningDays(owner.id), ['2026-08-04']);
        const receiptId =
            'learning-projection:streak:learning-event:cutover-b:v2';
        final receipt = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(receiptId))).getSingle();
        final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
        expect(receipt.eventType, 'LearningProjectionBlocked');
        expect(payload['reasonCode'], 'preMarkerCutover');
        expect(payload['result'], isEmpty);

        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'cutover-c',
          occurredAtUtc: afterBoundaryAt,
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        expect(
          await (database.select(
                database.eventsV2,
              )..where((row) => row.eventId.equals('learning-event:cutover-c')))
              .get(),
          hasLength(1),
        );
        final pendingAfterBoundary = await DriftLearningEventStore(database)
            .listPendingProjectionEvents(
              ownerId: owner.id,
              projection: 'streak',
              appliedVersion: LearningSideEffectReconciler.appliedVersion,
              limit: 32,
            );
        expect(
          pendingAfterBoundary.map((value) => value.event.eventId),
          contains('learning-event:cutover-c'),
        );
        final postBoundaryReconciler = _reconciler(database, restarted);
        await postBoundaryReconciler.reconcileOwner(owner.id);
        await postBoundaryReconciler.reconcileOwner(owner.id);

        final postBoundaryReceipt =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    'learning-projection:streak:learning-event:cutover-c:v2',
                  ),
                ))
                .getSingle();
        expect(postBoundaryReceipt.eventType, 'LearningProjectionApplied');
        final postBoundaryPayload =
            jsonDecode(postBoundaryReceipt.payloadJson) as Map<String, dynamic>;
        expect(
          (postBoundaryPayload['result'] as Map)['currentStreakDays'],
          (await restarted.getCurrentStreak()).currentStreakDays,
        );
      },
    );

    test(
      'version-scoped v2 marker replays under a later active policy',
      () async {
        final occurredAt = DateTime.utc(2026, 8, 4, 16, 30);
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'historical-marker-v2',
          occurredAtUtc: occurredAt,
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        final eventStore = DriftLearningEventStore(
          database,
          rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
        );
        final source = await eventStore.readBySourceEvidenceId(
          'historical-marker-v2',
        );
        final repository = DriftStreakRepository(database);
        final original = await repository.applyProjection(
          source: source!,
          timezoneId: 'Asia/Bangkok',
        );
        const stableId =
            'streak-application:learning-event:historical-marker-v2';
        const legacyId = '$stableId:v2';
        await database.customUpdate(
          'UPDATE events_v2 SET event_id = ?, idempotency_key = ? '
          'WHERE event_id = ?',
          variables: const [
            Variable<String>(legacyId),
            Variable<String>(legacyId),
            Variable<String>(stableId),
          ],
          updates: {database.eventsV2},
        );

        final replayed = await repository.applyProjection(
          source: source,
          timezoneId: 'Pacific/Pago_Pago',
          activePolicyVersion: 3,
        );

        expect(replayed.receipt!.toJson(), original.receipt!.toJson());
        expect(replayed.receipt!.policyVersion, 2);
        expect(replayed.receipt!.learningDay, '2026-08-04');
        expect(
          await (database.select(
            database.eventsV2,
          )..where((row) => row.eventId.equals(stableId))).get(),
          hasLength(1),
        );
        expect(
          await (database.select(
            database.eventsV2,
          )..where((row) => row.eventId.equals(legacyId))).get(),
          isEmpty,
        );
        expect(
          (await repository.getOrCreate(owner.id, 0)).currentStreakDays,
          1,
        );
      },
    );

    test(
      'canonical projection accepts grandfathered freeze inventory',
      () async {
        final occurredAt = DateTime.utc(2026, 8, 4, 10);
        await DriftStreakRepository(database).save(
          StreakState(
            ownerId: owner.id,
            currentStreakDays: 2,
            longestStreakDays: 4,
            freezeCount: 5,
            lastLearnedAtUtcMs: DateTime.utc(
              2026,
              8,
              3,
              10,
            ).millisecondsSinceEpoch,
            updatedAtUtcMs: DateTime.utc(2026, 8, 3, 10).millisecondsSinceEpoch,
          ),
        );
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'grandfathered-freeze',
          occurredAtUtc: occurredAt,
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );

        await _reconciler(database, streakUseCases).reconcileOwner(owner.id);

        final state = await streakUseCases.getCurrentStreak();
        expect(state.currentStreakDays, 3);
        expect(state.longestStreakDays, 4);
        expect(state.freezeCount, 5);
      },
    );
  });
}

LearningSideEffectReconciler _reconciler(
  db.AppDatabase database,
  StreakUseCases streak,
) => LearningSideEffectReconciler(
  database,
  rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
  streakSink: (event) async {
    final projection = await streak.projectEvent(event);
    return switch (projection.disposition) {
      StreakProjectionDisposition.applied => LearningProjectionResult.applied(
        payload: projection.payload,
      ),
      StreakProjectionDisposition.notApplicable =>
        LearningProjectionResult.notApplicable(
          payload: <String, dynamic>{'reasonCode': projection.reasonCode},
        ),
      StreakProjectionDisposition.blocked => LearningProjectionResult.blocked(
        reasonCode: projection.reasonCode!,
      ),
    };
  },
);

Future<void> _recordEvidence({
  required db.AppDatabase database,
  required LocalOwner owner,
  required String sourceEvidenceId,
  required EvidenceContext evidenceContext,
  DateTime? occurredAtUtc,
  void Function(String ownerId)? onSideEffectsPending,
}) async {
  final occurredAt = occurredAtUtc ?? DateTime.utc(2026, 8, 4, 10);
  final learning = LearningUseCases(
    owners: _FakeOwners(owner),
    repository: DriftLearningRepository(
      database,
      rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
    ),
    generateId: () => 'session-$sourceEvidenceId',
    nowUtc: () => occurredAt,
    buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha-test'),
    eventAdapter: EventV1ToV2Adapter(appVersion: '1.0', buildId: 'sha-test'),
    eventContextProvider: const _EvidenceEventContextProvider(),
    onSideEffectsPending: onSideEffectsPending,
  );
  final session = await learning.startQuiz(limit: 10);
  await learning.recordEvidence(
    sourceEvidenceId: sourceEvidenceId,
    occurredAtUtc: occurredAt,
    sessionId: session.id,
    wordId: 'word-1',
    promptMode: evidenceContext.evidenceClass == EvidenceClass.assessment
        ? 'assessmentResponse'
        : 'meaningChoice',
    isCorrect: true,
    responseTimeMs: 300,
    attemptNumber: 1,
    evidenceContext: evidenceContext,
  );
}

EvidenceContext _legacyDeclaredEvidence(
  EvidenceClass evidenceClass, {
  bool engagementAllowed = false,
}) => EvidenceContext.forNewEvidence(
  evidenceClass: evidenceClass,
  skillId: 'streak-skill',
  hintLevel: 0,
  contentRevision: 'streak-content-v1',
  rolloutMode: EvidencePolicyRolloutMode.legacy,
  engagementAllowed: engagementAllowed,
);

EvidenceContext _researchEvidence({
  required EvidenceClass evidenceClass,
  required EvidencePolicyRolloutMode rolloutMode,
  required bool engagementAllowed,
}) => EvidenceContext.forNewEvidence(
  evidenceClass: evidenceClass,
  skillId: 'streak-skill',
  hintLevel: 0,
  contentRevision: 'streak-content-v1',
  rolloutMode: rolloutMode,
  protocolId: 'streak-protocol',
  protocolVersion: 'streak-protocol-v1',
  experimentId: 'streak-experiment',
  experimentVersion: 1,
  assignmentId: 'streak-assignment',
  cohort: 'streak-cohort',
  researchConsentVersion: 1,
  instrumentId: evidenceClass == EvidenceClass.assessment
      ? 'streak-instrument'
      : null,
  instrumentVersion: evidenceClass == EvidenceClass.assessment
      ? 'streak-instrument-v1'
      : null,
  formId: evidenceClass == EvidenceClass.assessment ? 'streak-form' : null,
  formVersion: evidenceClass == EvidenceClass.assessment
      ? 'streak-form-v1'
      : null,
  assessmentItemId: evidenceClass == EvidenceClass.assessment
      ? 'streak-item'
      : null,
  assessmentResponseCode: evidenceClass == EvidenceClass.assessment
      ? 'correct'
      : null,
  scoringRuleVersion: evidenceClass == EvidenceClass.assessment
      ? 'streak-score-v1'
      : null,
  engagementAllowed: engagementAllowed,
);

final class _EvidenceEventContextProvider
    implements LearningEventContextProvider {
  const _EvidenceEventContextProvider();

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async {
    if (evidenceContext.rolloutMode == EvidencePolicyRolloutMode.legacy &&
        evidenceContext.evidenceClass != EvidenceClass.assessment) {
      return LearningEventContext.noResearch(evidenceContext);
    }
    return LearningEventContext(
      consentContext: const ConsentContext(
        researchConsentVersion: 1,
        aiConsentGranted: false,
        voiceConsentGranted: false,
        socialConsentGranted: false,
      ),
      experimentContext: ExperimentContext(
        experimentId: 'streak-experiment',
        variantId: 'streak-cohort',
        assignedAtUtc: DateTime.utc(2026, 8, 1),
      ),
      protocolId: 'streak-protocol',
      protocolVersion: 'streak-protocol-v1',
      experimentVersion: 1,
      assignmentId: 'streak-assignment',
      featureContractIdentity: FeatureContractIdentity(
        revision: evidenceContext.featureContractRevision,
        semanticHash: evidenceContext.featureContractHash,
      ),
    );
  }
}
