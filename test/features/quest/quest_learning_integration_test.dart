import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeOwners implements LocalOwnerRepository {
  final LocalOwner _owner;
  _FakeOwners(this._owner);
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => _owner;
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async =>
      _owner;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _ownerId = 'owner-qi';
int _seq = 0;

QuestDefinition _quizDef({int targetCount = 1}) => QuestDefinition(
  questId: 'q-quiz-correct',
  catalogVersion: 1,
  title: 'Answer Correctly',
  description: 'Answer $targetCount question(s) correctly',
  type: QuestType.daily,
  objectives: [
    QuestObjective(
      objectiveId: 'obj-correct',
      description: 'Correct answers',
      targetCount: targetCount,
      criteria: const ObjectiveCriteria(
        eventType: 'QuizCompleted',
        filters: {'correct': true},
      ),
    ),
  ],
  reward: const RewardSpec(xpAmount: 50),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late db.AppDatabase database;
  late LearningUseCases learningUseCases;
  late QuestUseCases questUseCases;
  late DriftQuestRepository questRepo;
  late LearningReconciliationScheduler learningReconciliation;
  late LocalOwner owner;
  late List<QuestDefinition> catalog;
  int idCount = 0;

  setUp(() async {
    _seq = 0;
    idCount = 0;
    database = db.AppDatabase(NativeDatabase.memory());
    owner = LocalOwner(id: _ownerId, createdAtUtc: DateTime.utc(2026, 8, 4));

    // Seed owner + category + word.
    await database.customInsert(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
      "VALUES ('$_ownerId', 'localGuest', 1722758400000)",
    );
    await database.customInsert(
      "INSERT INTO vocabulary_categories "
      "(id, owner_id, name, normalized_name, sort_order, local_revision, "
      "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
      "VALUES ('cat-1', '$_ownerId', 'Test', 'test', 0, 1, 0, 0, 10, 10)",
    );
    await database.customInsert(
      "INSERT INTO vocabulary_words "
      "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
      "normalized_meaning, part_of_speech, source, is_global, local_revision, "
      "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
      "VALUES ('word-1', '$_ownerId', 'cat-1', 'hello', 'hello', "
      "'สวัสดี', 'สวัสดี', 'interjection', 'manual', 0, 1, 0, 0, 10, 10)",
    );

    questRepo = DriftQuestRepository(database);
    questUseCases = QuestUseCases(
      repository: questRepo,
      owners: _FakeOwners(owner),
      generateId: () => 'qid-${++idCount}',
      nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
      timezoneId: 'Asia/Bangkok',
    );

    final adapter = EventV1ToV2Adapter(appVersion: '1.0', buildId: 'sha-test');

    catalog = [_quizDef()];
    const rolloutModeProvider = ContextEvidencePolicyRolloutModeProvider();
    learningReconciliation = LearningReconciliationScheduler(
      LearningSideEffectReconciler(
        database,
        rolloutModeProvider: rolloutModeProvider,
        questSink: (EventEnvelopeV2 event) async {
          final projection = await questUseCases.projectEvent(event, catalog);
          final payload = questUseCases.projectionPayload(projection, catalog);
          return projection.eligible
              ? LearningProjectionResult.applied(payload: payload)
              : LearningProjectionResult.notApplicable(payload: payload);
        },
      ),
    );
    learningUseCases = LearningUseCases(
      owners: _FakeOwners(owner),
      repository: DriftLearningRepository(
        database,
        rolloutModeProvider: rolloutModeProvider,
      ),
      generateId: () => 'lid-${++_seq}',
      nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
      buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha-test'),
      eventAdapter: adapter,
      onSideEffectsPending: learningReconciliation.request,
    );

    // Start learning session.
    await learningUseCases.startQuiz(limit: 10);
  });

  tearDown(() async {
    await learningReconciliation.dispose();
    await database.close();
  });

  group('Durable Quest reconciliation — D7.1 integration', () {
    test('correct answer advances matching quest objective', () async {
      // targetCount: 2 so quest advances but does not complete after 1 answer.
      final definition = _quizDef(targetCount: 2);
      catalog = [definition];
      await questUseCases.startQuest(definition);
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

      // Quest still active; counter advanced to 1/2.
      final active = await questUseCases.getActiveInstances();
      expect(active, hasLength(1));
      expect(
        active.first.progress.first.currentCount,
        1,
        reason: 'correct answer must advance quest counter',
      );
    });

    test('incorrect answer does NOT advance quest', () async {
      final definition = _quizDef();
      catalog = [definition];
      await questUseCases.startQuest(definition);
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

      final active = await questUseCases.getActiveInstances();
      expect(active, hasLength(1));
      expect(
        active.first.progress.first.currentCount,
        0,
        reason: 'incorrect answer must not advance quest counter',
      );
    });

    test('quest completes when target count reached', () async {
      final definition = _quizDef(targetCount: 1);
      catalog = [definition];
      await questUseCases.startQuest(definition);
      final session = await learningUseCases.startQuiz(limit: 10);

      await learningUseCases.recordAnswer(
        sessionId: session.id,
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 300,
        attemptNumber: 1,
      );
      await learningReconciliation.drain();

      final active = await questUseCases.getActiveInstances();
      expect(active, isEmpty, reason: 'completed quest must leave active list');
    });

    test('no scheduler persists without inline Quest execution', () async {
      // Rebuild LearningUseCases without a reconciliation scheduler.
      final useCasesNoQuest = LearningUseCases(
        owners: _FakeOwners(owner),
        repository: DriftLearningRepository(database),
        generateId: () => 'nq-${++_seq}',
        nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
        buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha-test'),
        // Durable startup replay intentionally owns later projection.
      );
      final session = await useCasesNoQuest.startQuiz(limit: 10);
      // Persistence must not depend on an inline Quest callback.
      await expectLater(
        useCasesNoQuest.recordAnswer(
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

    test(
      'only canonical eligible evidence advances and writes an exact v2 receipt',
      () async {
        final definition = _quizDef(targetCount: 3);
        catalog = [definition];
        await questUseCases.startQuest(definition);
        final evidence = _researchEvidence(
          evidenceClass: EvidenceClass.independentRecall,
          rolloutMode: EvidencePolicyRolloutMode.enforced,
          engagementAllowed: true,
        );

        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'eligible-evidence',
          evidenceContext: evidence,
          onSideEffectsPending: learningReconciliation.request,
        );
        await learningReconciliation.drain();

        final progress =
            (await questUseCases.getActiveInstances()).single.progress.single;
        expect(progress.currentCount, 1);
        expect(progress.sourceEventIds, ['learning-event:eligible-evidence']);

        const sourceEventId = 'learning-event:eligible-evidence';
        const receiptId = 'learning-projection:quest:$sourceEventId:v2';
        final receipt = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(receiptId))).getSingle();
        final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
        final decision = payload['decision'] as Map<String, dynamic>;
        expect(receipt.eventType, 'LearningProjectionApplied');
        expect(receipt.ownerId, _ownerId);
        expect(receipt.aggregateId, sourceEventId);
        expect(receipt.causationId, sourceEventId);
        expect(receipt.idempotencyKey, receiptId);
        expect(payload['sourceEventId'], sourceEventId);
        expect(payload['projection'], 'quest');
        expect(payload['appliedVersion'], 2);
        expect(payload['outcome'], 'applied');
        expect(decision, <String, dynamic>{
          'projection': 'quest',
          'rolloutMode': 'enforced',
          'effectiveDecision': 'protocolControlled',
          'candidateV1Decision': null,
          'policyVersion': EvidenceContext.currentPolicyVersion,
          'divergence': false,
        });
      },
    );

    test(
      'assessment guided exposure recreational and denied evidence never advance',
      () async {
        final definition = _quizDef(targetCount: 10);
        catalog = [definition];
        await questUseCases.startQuest(definition);
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
            sourceEvidenceId: 'denied-evidence-$index',
            evidenceContext: denied[index],
            onSideEffectsPending: learningReconciliation.request,
          );
        }
        await learningReconciliation.drain();

        final progress =
            (await questUseCases.getActiveInstances()).single.progress.single;
        expect(progress.currentCount, 0);
        expect(progress.sourceEventIds, isEmpty);
        for (var index = 0; index < denied.length; index++) {
          final receipt =
              await (database.select(database.eventsV2)..where(
                    (row) => row.eventId.equals(
                      'learning-projection:quest:'
                      'learning-event:denied-evidence-$index:v2',
                    ),
                  ))
                  .getSingle();
          expect(receipt.eventType, 'LearningProjectionSkipped');
        }
      },
    );

    test(
      'shadow divergence is diagnostic and keeps compatibility progress',
      () async {
        final definition = _quizDef(targetCount: 3);
        catalog = [definition];
        await questUseCases.startQuest(definition);

        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'shadow-evidence',
          evidenceContext: _researchEvidence(
            evidenceClass: EvidenceClass.independentRecall,
            rolloutMode: EvidencePolicyRolloutMode.shadow,
            engagementAllowed: false,
          ),
          onSideEffectsPending: learningReconciliation.request,
        );
        await learningReconciliation.drain();

        final progress =
            (await questUseCases.getActiveInstances()).single.progress.single;
        expect(progress.currentCount, 1);
        expect(progress.sourceEventIds, ['learning-event:shadow-evidence']);
        final receipt =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    'learning-projection:quest:'
                    'learning-event:shadow-evidence:v2',
                  ),
                ))
                .getSingle();
        final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
        expect(payload['decision'], <String, dynamic>{
          'projection': 'quest',
          'rolloutMode': 'shadow',
          'effectiveDecision': 'allow',
          'candidateV1Decision': 'protocolControlled',
          'policyVersion': EvidenceContext.currentPolicyVersion,
          'divergence': true,
        });
      },
    );

    test(
      'restart replay recovers a missing receipt without duplicate progress',
      () async {
        final definition = _quizDef(targetCount: 3);
        catalog = [definition];
        await questUseCases.startQuest(definition);
        await _recordEvidence(
          database: database,
          owner: owner,
          sourceEvidenceId: 'receipt-crash-evidence',
          evidenceContext: _legacyDeclaredEvidence(
            EvidenceClass.independentRecall,
            engagementAllowed: true,
          ),
        );
        await database.customStatement('''
          CREATE TEMP TRIGGER fail_quest_receipt
          BEFORE INSERT ON events_v2
          WHEN NEW.event_type = 'LearningProjectionApplied'
            AND json_extract(NEW.payload_json, '\$.projection') = 'quest'
          BEGIN SELECT RAISE(ABORT, 'injected quest receipt crash'); END
        ''');
        final first = _reconciler(database, questUseCases, () => catalog);
        await first.reconcileOwner(_ownerId);
        expect(
          (await questUseCases.getActiveInstances())
              .single
              .progress
              .single
              .currentCount,
          1,
        );
        const receiptId =
            'learning-projection:quest:'
            'learning-event:receipt-crash-evidence:v2';
        expect(
          await (database.select(
            database.eventsV2,
          )..where((row) => row.eventId.equals(receiptId))).getSingleOrNull(),
          isNull,
        );

        await database.customStatement('DROP TRIGGER fail_quest_receipt');
        final restarted = _reconciler(database, questUseCases, () => catalog);
        await Future.wait<void>([
          restarted.reconcileOwner(_ownerId),
          restarted.reconcileOwner(_ownerId),
        ]);

        final progress =
            (await questUseCases.getActiveInstances()).single.progress.single;
        expect(progress.currentCount, 1);
        expect(progress.sourceEventIds, [
          'learning-event:receipt-crash-evidence',
        ]);
        expect(
          await (database.select(
            database.eventsV2,
          )..where((row) => row.eventId.equals(receiptId))).get(),
          hasLength(1),
        );
      },
    );

    test('corrupted v2 receipt fails closed before replay mutation', () async {
      final definition = _quizDef(targetCount: 3);
      catalog = [definition];
      await questUseCases.startQuest(definition);
      await _recordEvidence(
        database: database,
        owner: owner,
        sourceEvidenceId: 'corrupt-receipt-evidence',
        evidenceContext: _legacyDeclaredEvidence(
          EvidenceClass.independentRecall,
          engagementAllowed: true,
        ),
        onSideEffectsPending: learningReconciliation.request,
      );
      await learningReconciliation.drain();
      const receiptId =
          'learning-projection:quest:'
          'learning-event:corrupt-receipt-evidence:v2';
      final row = await (database.select(
        database.eventsV2,
      )..where((candidate) => candidate.eventId.equals(receiptId))).getSingle();
      final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>
        ..['sourceEventId'] = 'learning-event:other-evidence';
      await database.customUpdate(
        'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
        variables: <Variable<Object>>[
          Variable<String>(jsonEncode(payload)),
          const Variable<String>(receiptId),
        ],
        updates: {database.eventsV2},
      );
      await database.customUpdate(
        'DELETE FROM events_v2 WHERE event_id = ?',
        variables: const <Variable<Object>>[
          Variable<String>('learning-projection-cursor:owner-qi:quest:v2'),
        ],
        updates: {database.eventsV2},
      );

      await _reconciler(
        database,
        questUseCases,
        () => catalog,
      ).reconcileOwner(_ownerId);

      final progress =
          (await questUseCases.getActiveInstances()).single.progress.single;
      expect(progress.currentCount, 1);
      expect(progress.sourceEventIds, [
        'learning-event:corrupt-receipt-evidence',
      ]);
    });
  });
}

LearningSideEffectReconciler _reconciler(
  db.AppDatabase database,
  QuestUseCases quest,
  List<QuestDefinition> Function() catalog,
) {
  return LearningSideEffectReconciler(
    database,
    rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
    questSink: (event) async {
      final definitions = catalog();
      final projection = await quest.projectEvent(event, definitions);
      final payload = quest.projectionPayload(projection, definitions);
      return projection.eligible
          ? LearningProjectionResult.applied(payload: payload)
          : LearningProjectionResult.notApplicable(payload: payload);
    },
  );
}

Future<void> _recordEvidence({
  required db.AppDatabase database,
  required LocalOwner owner,
  required String sourceEvidenceId,
  required EvidenceContext evidenceContext,
  void Function(String ownerId)? onSideEffectsPending,
}) async {
  final learning = LearningUseCases(
    owners: _FakeOwners(owner),
    repository: DriftLearningRepository(
      database,
      rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
    ),
    generateId: () => 'session-$sourceEvidenceId',
    nowUtc: () => DateTime.utc(2026, 8, 4, 10),
    buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha-test'),
    eventAdapter: EventV1ToV2Adapter(appVersion: '1.0', buildId: 'sha-test'),
    eventContextProvider: const _EvidenceEventContextProvider(),
    onSideEffectsPending: onSideEffectsPending,
  );
  final session = await learning.startQuiz(limit: 10);
  await learning.recordEvidence(
    sourceEvidenceId: sourceEvidenceId,
    occurredAtUtc: DateTime.utc(2026, 8, 4, 10),
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
  skillId: 'quest-skill',
  hintLevel: 0,
  contentRevision: 'quest-content-v1',
  rolloutMode: EvidencePolicyRolloutMode.legacy,
  engagementAllowed: engagementAllowed,
);

EvidenceContext _researchEvidence({
  required EvidenceClass evidenceClass,
  required EvidencePolicyRolloutMode rolloutMode,
  required bool engagementAllowed,
}) => EvidenceContext.forNewEvidence(
  evidenceClass: evidenceClass,
  skillId: 'quest-skill',
  hintLevel: 0,
  contentRevision: 'quest-content-v1',
  rolloutMode: rolloutMode,
  protocolId: 'quest-protocol',
  protocolVersion: 'quest-protocol-v1',
  experimentId: 'quest-experiment',
  experimentVersion: 1,
  assignmentId: 'quest-assignment',
  cohort: 'quest-cohort',
  researchConsentVersion: 1,
  instrumentId: evidenceClass == EvidenceClass.assessment
      ? 'quest-instrument'
      : null,
  instrumentVersion: evidenceClass == EvidenceClass.assessment
      ? 'quest-instrument-v1'
      : null,
  formId: evidenceClass == EvidenceClass.assessment ? 'quest-form' : null,
  formVersion: evidenceClass == EvidenceClass.assessment
      ? 'quest-form-v1'
      : null,
  assessmentItemId: evidenceClass == EvidenceClass.assessment
      ? 'quest-item'
      : null,
  assessmentResponseCode: evidenceClass == EvidenceClass.assessment
      ? 'correct'
      : null,
  scoringRuleVersion: evidenceClass == EvidenceClass.assessment
      ? 'quest-score-v1'
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
        experimentId: 'quest-experiment',
        variantId: 'quest-cohort',
        assignedAtUtc: DateTime.utc(2026, 8, 1),
      ),
      protocolId: 'quest-protocol',
      protocolVersion: 'quest-protocol-v1',
      experimentVersion: 1,
      assignmentId: 'quest-assignment',
      featureContractIdentity: FeatureContractIdentity(
        revision: evidenceContext.featureContractRevision,
        semanticHash: evidenceContext.featureContractHash,
      ),
    );
  }
}
