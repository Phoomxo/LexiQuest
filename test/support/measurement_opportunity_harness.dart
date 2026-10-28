import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
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

final class OpportunityFixture {
  OpportunityFixture(this.participation);
  final ParticipationFixture participation;
  late final DriftMotivationMeasurementTimingReader timing;
  late final DriftMotivationMeasurementRepository measurements;
  late final DriftMeasurementOpportunityRepository repository;
  late final DriftLearningRepository learning;
  DateTime privacyNow = participationStart;

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
          expiresAtUtc: participationStart.add(const Duration(days: 2)),
        ),
      );
      participant.operations.current = participationOperation(
        expiresAtUtc: participationStart.add(const Duration(days: 2)),
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
    TodayExperiencePresentation presentation =
        TodayExperiencePresentation.standard,
  }) async => repository.open(
    ownerId: 'owner-a',
    measurementRunId: runId,
    entryAttemptId: entryId,
    effectivePresentation: presentation,
  );
  Future<MeasurementOpportunity> present() async =>
      repository.recordPresented('owner-a', opportunityId);
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

  Future<void> accept({String id = 'first-session', DateTime? at}) async {
    final started = at ?? participationStart.add(const Duration(minutes: 2));
    participation.clock.now = started;
    await learning.startSession(session(id: id, at: started));
  }

  Future<void> finish({String id = 'first-session', DateTime? at}) async {
    final ended = at ?? participationStart.add(const Duration(minutes: 3));
    participation.clock.now = ended;
    await learning.finishSession(
      ownerId: 'owner-a',
      sessionId: id,
      endedAtUtc: ended,
    );
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
      'outbox_operations': ordinaryAchievementSessionId == null ? 0 : 1,
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
      final operations = await database
          .customSelect('SELECT * FROM outbox_operations')
          .get();
      final operation = operations.single.data;
      final achievements = await database
          .customSelect('SELECT * FROM achievement_unlocks')
          .get();
      final achievement = achievements.single.data;
      final canonicalSession = await storedSession(
        ordinaryAchievementSessionId,
      );
      final endedAt = canonicalSession['ended_at_utc_ms'];
      if (canonicalSession['owner_id'] != 'owner-a' ||
          canonicalSession['state'] != 'completed' ||
          endedAt == null ||
          achievement['id'] != achievementId ||
          achievement['owner_id'] != 'owner-a' ||
          achievement['achievement_id'] != 'first_session' ||
          achievement['definition_version'] != 1 ||
          achievement['source_event_id'] != ordinaryAchievementSessionId ||
          achievement['unlocked_at_utc_ms'] != endedAt ||
          operation['operation_id'] != 'achievementUnlock:$achievementId:1' ||
          operation['owner_id'] != 'owner-a' ||
          operation['entity_type'] != 'achievementUnlock' ||
          operation['entity_id'] != achievementId ||
          operation['operation_kind'] != 'upsert' ||
          operation['payload_version'] != 1 ||
          operation['base_revision'] != 0 ||
          operation['created_at_utc_ms'] != endedAt) {
        throw StateError(
          'Expected only the canonical ordinary first-session achievement outbox operation',
        );
      }
    }
    final unsupported = await database
        .customSelect(
          "SELECT COUNT(*) AS n FROM events_v2 WHERE event_type <> 'TodayExperiencePresented'",
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
