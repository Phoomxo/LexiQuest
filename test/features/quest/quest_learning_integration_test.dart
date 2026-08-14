import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
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

    final catalog = [_quizDef()];
    learningReconciliation = LearningReconciliationScheduler(
      LearningSideEffectReconciler(
        database,
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
      repository: DriftLearningRepository(database),
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

  group('QuestEventSink — D7.1 Quest-Learning integration', () {
    test('correct answer advances matching quest objective', () async {
      // targetCount: 2 so quest advances but does not complete after 1 answer.
      await questUseCases.startQuest(_quizDef(targetCount: 2));
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
      await questUseCases.startQuest(_quizDef());
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
      await questUseCases.startQuest(_quizDef(targetCount: 1));
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

    test('questEventSink null = no crash (feature flag off)', () async {
      // Rebuild LearningUseCases without questEventSink.
      final useCasesNoQuest = LearningUseCases(
        owners: _FakeOwners(owner),
        repository: DriftLearningRepository(database),
        generateId: () => 'nq-${++_seq}',
        nowUtc: () => DateTime.utc(2026, 8, 4, 10, 0),
        buildInfo: const AppBuildInfo(version: '1.0', buildId: 'sha-test'),
        // questEventSink intentionally absent
      );
      final session = await useCasesNoQuest.startQuiz(limit: 10);
      // Must not throw even without questEventSink (feature flag off).
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
  });
}
