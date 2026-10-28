import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import 'research_participation_harness.dart';

export 'research_participation_harness.dart'
    show participationStart, participationPermit, participationOperation;

final class MeasurementFixture {
  MeasurementFixture(this.participation);

  final ParticipationFixture participation;
  final timing = MeasurementTimingReader();
  DateTime privacyNow = participationStart;
  late final DriftMotivationMeasurementRepository repository;

  AppDatabase get database => participation.database;
  String get permitId => participation.current.id;
  String get assignmentId => participation.current.assignmentId;
  String get runId {
    final study = participation.assignments.binding.study;
    return motivationMeasurementRunId(
      ownerId: 'owner-a',
      permitId: permitId,
      protocolId: study.protocolId,
      protocolVersion: study.protocolVersion,
      instrumentChecksumSha256: study.instrument.checksumSha256,
    );
  }

  static Future<MeasurementFixture> open({
    MeasurementQueries? queries,
    bool longLived = false,
  }) async {
    final underlying = NativeDatabase.memory();
    final participation = await ParticipationFixture.open(
      database: AppDatabase(
        queries == null ? underlying : underlying.interceptWith(queries),
      ),
    );
    if (longLived) {
      participation.use(
        participationPermit(
          expiresAtUtc: participationStart.add(const Duration(days: 2)),
        ),
      );
      participation.operations.current = participationOperation(
        expiresAtUtc: participationStart.add(const Duration(days: 2)),
      );
    }
    if (!await participation.importCurrent()) {
      throw StateError('Synthetic signed participation was not admitted');
    }
    final result = MeasurementFixture(participation);
    result.repository = result.newRepository();
    return result;
  }

  DriftMotivationMeasurementRepository newRepository() =>
      DriftMotivationMeasurementRepository(
        database,
        participation: participation.repository,
        timing: timing,
        consentNowUtc: () => privacyNow,
      );

  void before() {
    timing.facts = MotivationBeforeExposure(
      ownerId: 'owner-a',
      runId: runId,
      permitId: permitId,
      assignmentId: assignmentId,
    );
  }

  void exposed({
    MotivationIndexSessionState? state = MotivationIndexSessionState.completed,
    DateTime? exposure,
    DateTime? sessionStart,
    DateTime? completion,
    String sessionId = 'synthetic-index',
  }) {
    final first =
        exposure ?? participationStart.add(const Duration(minutes: 1));
    timing.facts = MotivationAfterExposure(
      ownerId: 'owner-a',
      runId: runId,
      permitId: permitId,
      assignmentId: assignmentId,
      firstExposureEventId: 'synthetic-first-exposure',
      firstExposureAtUtc: first,
      indexSession: state == null
          ? null
          : MotivationIndexSession(
              id: sessionId,
              startedAtUtc:
                  sessionStart ?? first.add(const Duration(minutes: 1)),
              state: state,
              completedAtUtc: state == MotivationIndexSessionState.completed
                  ? completion ?? first.add(const Duration(minutes: 2))
                  : completion,
            ),
    );
  }

  Future<MotivationMeasurementRun> start({String ownerId = 'owner-a'}) =>
      repository.start(
        MotivationMeasurementStart(ownerId: ownerId, permitId: permitId),
      );

  Future<MotivationMeasurementRun> answer({
    String item = 'synthetic-baseline',
    String code = 'high',
    String ownerId = 'owner-a',
  }) => repository.record(
    MotivationResponse(
      ownerId: ownerId,
      runId: runId,
      itemId: item,
      responseCode: code,
    ),
  );

  Future<MotivationMeasurementRun> close(MotivationMeasurementRunState state) =>
      repository.close(
        MotivationMeasurementClose(
          ownerId: 'owner-a',
          runId: runId,
          state: state,
        ),
      );

  Future<MotivationMeasurementRun> baseline() async {
    await start();
    before();
    return answer();
  }

  Future<MotivationMeasurementRun> complete() async {
    await baseline();
    exposed();
    participation.clock.now = participationStart.add(
      const Duration(minutes: 3),
    );
    return answer(item: 'synthetic-post', code: 'low');
  }

  Future<Map<String, Object?>> storedRun() async =>
      (await database
              .customSelect(
                'SELECT * FROM motivation_measurement_runs WHERE id = ?',
                variables: [drift.Variable<String>(runId)],
              )
              .getSingle())
          .data;

  Future<List<Map<String, Object?>>> storedResponses() async =>
      (await database
              .customSelect(
                'SELECT * FROM motivation_responses ORDER BY item_id',
              )
              .get())
          .map((row) => row.data)
          .toList();

  Future<void> expectArtifacts({
    required int runs,
    required int responses,
  }) async {
    for (final expected in {
      'motivation_measurement_runs': runs,
      'motivation_responses': responses,
      'events_v2': 0,
      'outbox_operations': 0,
    }.entries) {
      final row = await database
          .customSelect('SELECT COUNT(*) AS n FROM ${expected.key}')
          .getSingle();
      if (row.read<int>('n') != expected.value) {
        throw StateError(
          '${expected.key} count ${row.read<int>('n')} != ${expected.value}',
        );
      }
    }
  }
}

final class MeasurementTimingReader
    implements MotivationMeasurementTimingReader {
  MotivationTimingFacts? facts;
  Future<void> Function()? afterNextRead;
  var didFire = false;

  @override
  Future<MotivationTimingFacts?> read({
    required String ownerId,
    required String runId,
    required String permitId,
    required String assignmentId,
  }) async {
    final result = facts;
    final callback = afterNextRead;
    afterNextRead = null;
    if (callback != null) {
      didFire = true;
      await callback();
    }
    return result;
  }
}

final class MeasurementQueries extends drift.QueryInterceptor {
  Future<void> Function()? afterResponseWrite;
  Future<void> Function()? afterRunWrite;
  Future<void> Function()? afterArmedRead;
  var readArmed = false;
  var didResponseWrite = false;
  var didRunWrite = false;
  var didRead = false;

  Future<void> _afterWrite(String statement) async {
    final sql = _normalize(statement);
    if (RegExp(r'^(insert into|update) motivation_responses\b').hasMatch(sql)) {
      didResponseWrite = true;
      final callback = afterResponseWrite;
      afterResponseWrite = null;
      await callback?.call();
    }
    if (RegExp(
      r'^(insert into|update) motivation_measurement_runs\b',
    ).hasMatch(sql)) {
      didRunWrite = true;
      final callback = afterRunWrite;
      afterRunWrite = null;
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
        (sql.contains(' from motivation_measurement_runs ') ||
            sql.contains(' from motivation_responses '))) {
      didRead = true;
      readArmed = false;
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
    await _afterWrite(statement);
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    await _afterWrite(statement);
    return result;
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runUpdate(statement, args);
    await _afterWrite(statement);
    return result;
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}
