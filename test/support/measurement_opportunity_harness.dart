import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/learning_session_lifecycle_observer.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_timing_reader.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import 'research_participation_harness.dart';

export 'research_participation_harness.dart'
    show participationStart, participationPermit, participationOperation;

const opportunityEntryId = '00000000-0000-4000-8000-000000000001';
const opportunityCategoryId = 'synthetic-opportunity-category';
const opportunityWordId = 'synthetic-opportunity-word';

final class OpportunityFixture {
  OpportunityFixture(this.participation);
  final ParticipationFixture participation;
  late final DriftMotivationMeasurementTimingReader timing;
  late final DriftMotivationMeasurementRepository measurements;
  late final DriftMeasurementOpportunityRepository repository;
  late final DriftLearningRepository learning;
  DateTime privacyNow = participationStart;
  bool visible = true;
  int visibilityGeneration = 0;

  AppDatabase get database => participation.database;
  String get runId {
    final study = participation.assignments.binding.study;
    return motivationMeasurementRunId(
      ownerId: 'owner-a',
      permitId: participation.current.id,
      protocolId: study.protocolId,
      protocolVersion: study.protocolVersion,
      instrumentChecksumSha256: study.instrument.checksumSha256,
    );
  }

  String get opportunityId => measurementOpportunityId(
    ownerId: 'owner-a',
    measurementRunId: runId,
    permitId: participation.current.id,
    entryAttemptId: opportunityEntryId,
  );

  static Future<OpportunityFixture> open({
    AppDatabase? database,
    OpportunityQueries? queries,
    bool seed = true,
    bool longLived = false,
    bool admitParticipant = true,
    TodayExperiencePresentation treatment =
        TodayExperiencePresentation.standard,
  }) async {
    final native = database == null ? NativeDatabase.memory() : null;
    final participant = await ParticipationFixture.open(
      database:
          database ??
          AppDatabase(
            queries == null ? native! : native!.interceptWith(queries),
          ),
      seed: seed,
    );
    if (longLived) {
      participant.use(
        participationPermit(
          treatment: treatment,
          expiresAtUtc: participationStart.add(const Duration(days: 2)),
        ),
      );
      participant.operations.current = participationOperation(
        expiresAtUtc: participationStart.add(const Duration(days: 2)),
      );
    }
    if (!longLived && treatment != TodayExperiencePresentation.standard) {
      participant.use(participationPermit(treatment: treatment));
    }
    if (seed) {
      await participant.database.customStatement(
        'INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, 1, 1)',
        [
          opportunityCategoryId,
          'owner-a',
          'Synthetic opportunity vocabulary',
          'synthetic opportunity vocabulary',
        ],
      );
      await participant.database.customStatement(
        'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
        [
          opportunityWordId,
          'owner-a',
          opportunityCategoryId,
          'station',
          'station',
          'สถานี',
          'สถานี',
          'noun',
        ],
      );
    }
    if (!admitParticipant) {
      await participant.database.customStatement(
        'DELETE FROM research_consents',
      );
    } else if (!await participant.importCurrent()) {
      throw StateError('Synthetic signed participant was not admitted');
    }
    final result = OpportunityFixture(participant);
    result.timing = DriftMotivationMeasurementTimingReader(result.database);
    result.measurements = DriftMotivationMeasurementRepository(
      result.database,
      participation: participant.repository,
      timing: result.timing,
      consentNowUtc: () => result.privacyNow,
    );
    result.repository = result.newRepository();
    result.learning = DriftLearningRepository(
      result.database,
      lifecycleObserver: result.repository,
    );
    return result;
  }

  DriftMeasurementOpportunityRepository newRepository() =>
      DriftMeasurementOpportunityRepository(
        database,
        measurements: measurements,
        timing: timing,
      );

  Future<MotivationMeasurementRun> startRun() async => measurements.start(
    MotivationMeasurementStart(
      ownerId: 'owner-a',
      permitId: participation.current.id,
    ),
  );
  Future<MotivationMeasurementRun> baseline() async {
    await startRun();
    return measurements.record(
      MotivationResponse(
        ownerId: 'owner-a',
        runId: runId,
        itemId: 'synthetic-baseline',
        responseCode: 'high',
      ),
    );
  }

  Future<MeasurementOpportunity> openOpportunity({
    String entryId = opportunityEntryId,
    TodayExperiencePresentation? presentation,
  }) async => repository.open(
    ownerId: 'owner-a',
    measurementRunId: runId,
    entryAttemptId: entryId,
    effectivePresentation:
        presentation ?? participation.current.assignedTreatment,
  );
  Future<MeasurementOpportunity> present() {
    final generation = visibilityGeneration;
    return repository.recordPresented(
      'owner-a',
      opportunityId,
      stillVisible: () => visible && generation == visibilityGeneration,
    );
  }

  Future<MeasurementOpportunity> ready({DateTime? at}) async {
    await baseline();
    if (at != null) participation.clock.now = at;
    await openOpportunity();
    return present();
  }

  Future<MotivationTimingFacts?> facts() => timing.read(
    ownerId: 'owner-a',
    runId: runId,
    permitId: participation.current.id,
    assignmentId: participation.current.assignmentId,
  );

  LearningSessionDraft session({
    String id = 'first-session',
    DateTime? at,
    String ownerId = 'owner-a',
    String activityType = 'quiz',
  }) {
    final study = participation.assignments.binding.study;
    return LearningSessionDraft(
      id: id,
      ownerId: ownerId,
      activityType: activityType,
      startedAtUtc: at ?? participation.clock.now,
      appVersion: study.appVersion,
      buildId: study.buildId,
    );
  }

  Future<AcceptedQuizPlan> quizPlan() async {
    final words = await learning.listQuizWords(
      ownerId: 'owner-a',
      categoryId: opportunityCategoryId,
      wordIds: [opportunityWordId],
      limit: 1,
    );
    return AcceptedQuizPlan.create(
      configuration: QuizConfiguration.category(
        categoryId: opportunityCategoryId,
        limit: 1,
      ),
      questions: words.map(
        (word) => QuizQuestion(
          word: word,
          options: [word.meaning, 'synthetic wrong option'],
        ),
      ),
    );
  }

  Future<ConfiguredQuizState> accept({
    String id = 'first-session',
    DateTime? at,
  }) async {
    final started = at ?? participationStart.add(const Duration(minutes: 2));
    participation.clock.now = started;
    return learning.startConfiguredQuiz(
      session: session(id: id, at: started),
      plan: await quizPlan(),
    );
  }

  Future<void> acceptLegacy({
    String id = 'first-session',
    DateTime? at,
    String activityType = 'quiz',
  }) async {
    final started = at ?? participationStart.add(const Duration(minutes: 2));
    participation.clock.now = started;
    await learning.startSession(
      session(id: id, at: started, activityType: activityType),
    );
  }

  Future<void> finish({String id = 'first-session', DateTime? at}) async {
    final ended = at ?? participationStart.add(const Duration(minutes: 3));
    participation.clock.now = ended;
    var saved = await learning.resumeQuiz(
      sessionId: id,
      expectedOwnerId: 'owner-a',
    );
    if (saved.checkpoint is AwaitingQuizAnswer) {
      final answer = QuizAnswerReceipt.capture(
        plan: saved.plan,
        ownerId: 'owner-a',
        attemptId: 'attempt:$id:1',
        questionOrdinal: 0,
        selectedOptionOrdinal: 1,
        revealed: false,
        assistance: saved.checkpoint.assistance,
        occurredAtUtcMs: ended
            .subtract(const Duration(milliseconds: 1))
            .millisecondsSinceEpoch,
        responseTimeMs: null,
      );
      saved = await learning.saveQuizCheckpoint(
        sessionId: id,
        expectedOwnerId: 'owner-a',
        expectedRevision: saved.checkpointRevision,
        checkpoint: PendingQuizAnswer(
          planId: saved.plan.id,
          questionOrdinal: 0,
          assistance: saved.checkpoint.assistance,
          answer: answer,
        ),
      );
    }
    if (saved.checkpoint is PendingQuizAnswer) {
      saved = (await learning.commitQuizAnswer(
        sessionId: id,
        expectedOwnerId: 'owner-a',
        expectedRevision: saved.checkpointRevision,
      )).state;
    }
    if (saved.checkpoint is AnsweredQuizQuestion) {
      saved = await learning.saveQuizCheckpoint(
        sessionId: id,
        expectedOwnerId: 'owner-a',
        expectedRevision: saved.checkpointRevision,
        checkpoint: ClosingQuizSession(
          planId: saved.plan.id,
          questionOrdinal: 0,
          assistance: saved.checkpoint.assistance,
          close: QuizCloseReceipt(
            capturedOwnerId: 'owner-a',
            endedAtUtcMs: ended.millisecondsSinceEpoch,
          ),
        ),
      );
    }
    await learning.finishConfiguredQuiz(
      sessionId: id,
      expectedOwnerId: 'owner-a',
      expectedRevision: saved.checkpointRevision,
    );
  }

  Future<void> observeAccepted([String id = 'first-session']) async {
    final row = await (database.select(
      database.learningSessions,
    )..where((r) => r.id.equals(id))).getSingle();
    await repository.accepted(LearningSessionLifecycleFact.fromRow(row));
  }

  Future<void> observeCompleted([String id = 'first-session']) async {
    final row = await (database.select(
      database.learningSessions,
    )..where((r) => r.id.equals(id))).getSingle();
    await repository.completed(LearningSessionLifecycleFact.fromRow(row));
  }

  Future<void> rawSession({
    required String id,
    required DateTime at,
    String ownerId = 'owner-a',
    String state = 'active',
    String activity = 'quiz',
    DateTime? end,
  }) => database.customStatement(
    'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) VALUES (?,?,?,?,?,?,?,?)',
    [
      id,
      ownerId,
      activity,
      state,
      at.millisecondsSinceEpoch,
      end?.millisecondsSinceEpoch,
      participation.assignments.binding.study.appVersion,
      participation.assignments.binding.study.buildId,
    ],
  );

  Future<Map<String, Object?>> storedOpportunity() async =>
      (await database
              .customSelect(
                'SELECT * FROM measurement_opportunities WHERE id = ?',
                variables: [drift.Variable<String>(opportunityId)],
              )
              .getSingle())
          .data;
  Future<List<Map<String, Object?>>> events() async =>
      (await database
              .customSelect('SELECT * FROM events_v2 ORDER BY event_id')
              .get())
          .map((row) => row.data)
          .toList();
  Future<Map<String, Object?>> storedSession([
    String id = 'first-session',
  ]) async =>
      (await database
              .customSelect(
                'SELECT * FROM learning_sessions WHERE id = ?',
                variables: [drift.Variable<String>(id)],
              )
              .getSingle())
          .data;

  Future<void> expectArtifacts({
    required int opportunities,
    required int events,
    int? sessions,
    String? ordinaryAchievementSessionId,
  }) async {
    for (final entry in {
      'measurement_opportunities': opportunities,
      'events_v2': events,
      'outbox_operations': ordinaryAchievementSessionId == null ? 0 : 3,
      'learning_sessions': ?sessions,
    }.entries) {
      final count =
          (await database
                  .customSelect('SELECT COUNT(*) AS n FROM ${entry.key}')
                  .getSingle())
              .read<int>('n');
      if (count != entry.value) {
        throw StateError('${entry.key}: $count != ${entry.value}');
      }
    }
    if (ordinaryAchievementSessionId != null) {
      const achievementId = 'achievement:owner-a:first_session:1';
      const firstAnswerId = 'achievement:owner-a:first_answer:1';
      final operations = await database
          .customSelect('SELECT * FROM outbox_operations')
          .get();
      final operation = operations
          .singleWhere((row) => row.data['entity_type'] == 'achievementUnlock')
          .data;
      final attempts = await database
          .customSelect('SELECT * FROM answer_attempts')
          .get();
      final attempt = attempts.single.data;
      final achievements = await database
          .customSelect('SELECT * FROM achievement_unlocks')
          .get();
      final achievement = achievements
          .singleWhere((row) => row.data['id'] == achievementId)
          .data;
      final firstAnswer = achievements
          .singleWhere((row) => row.data['id'] == firstAnswerId)
          .data;
      final canonicalSession = await storedSession(
        ordinaryAchievementSessionId,
      );
      final endedAt = canonicalSession['ended_at_utc_ms'];
      if (canonicalSession['owner_id'] != 'owner-a' ||
          canonicalSession['state'] != 'completed' ||
          canonicalSession['correct_count'] != 0 ||
          canonicalSession['wrong_count'] != 1 ||
          canonicalSession['score'] != 0 ||
          achievements.length != 2 ||
          endedAt == null ||
          attempt['id'] != 'attempt:$ordinaryAchievementSessionId:1' ||
          attempt['owner_id'] != 'owner-a' ||
          attempt['session_id'] != ordinaryAchievementSessionId ||
          attempt['word_id'] != opportunityWordId ||
          attempt['is_correct'] != 0 ||
          firstAnswer['source_event_id'] != attempt['id'] ||
          firstAnswer['unlocked_at_utc_ms'] != attempt['occurred_at_utc_ms'] ||
          achievement['id'] != achievementId ||
          achievement['owner_id'] != 'owner-a' ||
          achievement['achievement_id'] != 'first_session' ||
          achievement['definition_version'] != 1 ||
          achievement['source_event_id'] != ordinaryAchievementSessionId ||
          achievement['unlocked_at_utc_ms'] != endedAt ||
          operation['operation_id'] != 'achievementUnlock:$achievementId:1' ||
          operation['owner_id'] != 'owner-a' ||
          operation['entity_id'] != achievementId ||
          operation['operation_kind'] != 'upsert' ||
          operation['payload_version'] != 1 ||
          operation['base_revision'] != 0 ||
          operation['created_at_utc_ms'] != endedAt) {
        throw StateError(
          'Configured ordinary answer or first-session achievement changed',
        );
      }
      final types = operations.map((row) => row.data['entity_type']).toSet();
      if (types.length != 3 ||
          !types.containsAll({'attempt', 'srsState', 'achievementUnlock'})) {
        throw StateError(
          'Expected exactly the canonical attempt, SRS and first-session outbox operations',
        );
      }
      for (final type in ['attempt', 'srsState']) {
        final row = operations
            .singleWhere((row) => row.data['entity_type'] == type)
            .data;
        final id = type == 'attempt' ? attempt['id'] : opportunityWordId;
        if (row['owner_id'] != 'owner-a' ||
            row['entity_id'] != id ||
            row['operation_id'] != '$type:$id:1' ||
            row['operation_kind'] != 'upsert' ||
            row['payload_version'] != (type == 'attempt' ? 2 : 1) ||
            row['base_revision'] != 0 ||
            row['created_at_utc_ms'] != attempt['occurred_at_utc_ms']) {
          throw StateError('Ordinary $type outbox changed');
        }
      }
      for (final table in ['points_ledger_entries', 'reward_transactions']) {
        final count =
            (await database
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n');
        if (count != 0) {
          throw StateError(
            'A wrong ordinary answer unexpectedly earned $table',
          );
        }
      }
      final srs = await database.customSelect('SELECT * FROM srs_states').get();
      if (srs.length != 1 ||
          srs.single.data['owner_id'] != 'owner-a' ||
          srs.single.data['word_id'] != opportunityWordId) {
        throw StateError('Canonical SRS row changed');
      }
    }
    final unsupported = await database
        .customSelect(
          "SELECT COUNT(*) AS n FROM events_v2 WHERE event_type NOT IN "
          "('TodayExperiencePresented', 'TodayExperienceMissionStarted', 'TodayExperienceMissionCompleted')",
        )
        .getSingle();
    if (unsupported.read<int>('n') != 0) {
      throw StateError('Unsupported research event written');
    }
  }
}

final class OpportunityQueries extends drift.QueryInterceptor {
  Future<void> Function()? afterOpportunityWrite;
  Future<void> Function()? afterEventWrite;
  Future<void> Function()? afterArmedRead;
  bool readArmed = false;
  bool didOpportunityWrite = false;
  bool didEventWrite = false;
  bool didRead = false;

  Future<void> _written(String statement) async {
    final sql = _normalize(statement);
    if (RegExp(
      r'^(insert into|update) measurement_opportunities\b',
    ).hasMatch(sql)) {
      didOpportunityWrite = true;
      final callback = afterOpportunityWrite;
      afterOpportunityWrite = null;
      await callback?.call();
    }
    if (RegExp(r'^insert into events_v2\b').hasMatch(sql)) {
      didEventWrite = true;
      final callback = afterEventWrite;
      afterEventWrite = null;
      await callback?.call();
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    final sql = _normalize(statement);
    if (readArmed &&
        !didRead &&
        afterArmedRead != null &&
        sql.contains(' from motivation_measurement_runs ')) {
      readArmed = false;
      didRead = true;
      await afterArmedRead!();
    }
    return result;
  }

  @override
  Future<void> runCustom(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    await _written(statement);
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    await _written(statement);
    return result;
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runUpdate(statement, args);
    await _written(statement);
    return result;
  }

  static String _normalize(String sql) => sql
      .replaceAll('"', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}
