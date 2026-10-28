import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';

void main() {
  late AppDatabase database;
  late DriftExperimentAssignmentRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftExperimentAssignmentRepository(database);
    await _insertOwner(database, 'owner-a');
    await _insertOwner(database, 'owner-b');
  });

  tearDown(() => database.close());

  test('assignIfAbsent persists one valid immutable assignment', () async {
    final assignedAtUtc = DateTime.utc(2026, 8, 14, 9, 30);

    final assignment = await repository.assignIfAbsent(
      ownerId: 'owner-a',
      experimentId: 'retrieval-policy',
      experimentVersion: 1,
      cohort: 'intervention-a',
      protocolVersion: 'protocol-2026.1',
      assignedAtUtc: assignedAtUtc,
    );

    expect(assignment.id, isNotEmpty);
    expect(assignment.ownerId, 'owner-a');
    expect(assignment.experimentId, 'retrieval-policy');
    expect(assignment.experimentVersion, 1);
    expect(assignment.cohort, 'intervention-a');
    expect(assignment.protocolVersion, 'protocol-2026.1');
    expect(assignment.assignedAtUtc, assignedAtUtc);

    final rows = await database
        .customSelect('SELECT * FROM experiment_assignments')
        .get();
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.read<String>('id'), assignment.id);
    expect(row.read<String>('owner_id'), 'owner-a');
    expect(row.read<String>('experiment_id'), 'retrieval-policy');
    expect(row.read<int>('experiment_version'), 1);
    expect(row.read<String>('cohort'), 'intervention-a');
    expect(row.read<String>('protocol_version'), 'protocol-2026.1');
    expect(
      row.read<int>('assigned_at_utc_ms'),
      assignedAtUtc.millisecondsSinceEpoch,
    );
  });

  test('getAssignment round-trips after a file-backed reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-experiment-assignment-',
    );
    final path = '${directory.path}${Platform.pathSeparator}assignment.sqlite';
    final assignedAtUtc = DateTime.utc(2026, 8, 14, 10);
    AppDatabase? fileDatabase;

    try {
      fileDatabase = AppDatabase(NativeDatabase(File(path)));
      await _insertOwner(fileDatabase, 'owner-reopen');
      final firstRepository = DriftExperimentAssignmentRepository(fileDatabase);
      final created = await firstRepository.assignIfAbsent(
        ownerId: 'owner-reopen',
        experimentId: 'durable-assignment',
        experimentVersion: 2,
        cohort: 'control',
        protocolVersion: 'protocol-2',
        assignedAtUtc: assignedAtUtc,
      );
      await fileDatabase.close();
      fileDatabase = null;

      fileDatabase = AppDatabase(NativeDatabase(File(path)));
      final reopenedRepository = DriftExperimentAssignmentRepository(
        fileDatabase,
      );
      final reopened = await reopenedRepository.getAssignment(
        ownerId: 'owner-reopen',
        experimentId: 'durable-assignment',
        experimentVersion: 2,
      );

      expect(reopened.id, created.id);
      expect(reopened.ownerId, created.ownerId);
      expect(reopened.experimentId, created.experimentId);
      expect(reopened.experimentVersion, created.experimentVersion);
      expect(reopened.cohort, created.cohort);
      expect(reopened.protocolVersion, created.protocolVersion);
      expect(reopened.assignedAtUtc, assignedAtUtc);
      expect(await _assignmentCount(fileDatabase), 1);
    } finally {
      await fileDatabase?.close();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  test(
    'byte-equivalent replay returns the same row without duplicate',
    () async {
      final assignedAtUtc = DateTime.utc(2026, 8, 14, 11);
      final first = await repository.assignIfAbsent(
        ownerId: 'owner-a',
        experimentId: 'replay-safe',
        experimentVersion: 3,
        cohort: 'control',
        protocolVersion: 'protocol-3',
        assignedAtUtc: assignedAtUtc,
      );

      final replayed = await repository.assignIfAbsent(
        ownerId: 'owner-a',
        experimentId: 'replay-safe',
        experimentVersion: 3,
        cohort: 'control',
        protocolVersion: 'protocol-3',
        assignedAtUtc: assignedAtUtc,
      );

      expect(replayed.id, first.id);
      expect(replayed.ownerId, first.ownerId);
      expect(replayed.experimentId, first.experimentId);
      expect(replayed.experimentVersion, first.experimentVersion);
      expect(replayed.cohort, first.cohort);
      expect(replayed.protocolVersion, first.protocolVersion);
      expect(replayed.assignedAtUtc, first.assignedAtUtc);
      expect(await _assignmentCount(database), 1);
    },
  );

  test('different cohort conflicts and preserves the original row', () async {
    await _expectConflictPreservesOriginal(
      repository: repository,
      database: database,
      conflictingCohort: 'intervention-b',
      conflictingProtocolVersion: 'protocol-4',
    );
  });

  test('different protocol conflicts and preserves the original row', () async {
    await _expectConflictPreservesOriginal(
      repository: repository,
      database: database,
      conflictingCohort: 'control',
      conflictingProtocolVersion: 'protocol-4-revised',
    );
  });

  test('different owners and experiment versions remain isolated', () async {
    final at = DateTime.utc(2026, 8, 14, 13);
    final ownerAVersion1 = await repository.assignIfAbsent(
      ownerId: 'owner-a',
      experimentId: 'isolation',
      experimentVersion: 1,
      cohort: 'control',
      protocolVersion: 'protocol-1',
      assignedAtUtc: at,
    );
    final ownerBVersion1 = await repository.assignIfAbsent(
      ownerId: 'owner-b',
      experimentId: 'isolation',
      experimentVersion: 1,
      cohort: 'intervention',
      protocolVersion: 'protocol-1',
      assignedAtUtc: at.add(const Duration(minutes: 1)),
    );
    final ownerAVersion2 = await repository.assignIfAbsent(
      ownerId: 'owner-a',
      experimentId: 'isolation',
      experimentVersion: 2,
      cohort: 'follow-up',
      protocolVersion: 'protocol-2',
      assignedAtUtc: at.add(const Duration(minutes: 2)),
    );

    expect(ownerAVersion1.id, isNot(ownerBVersion1.id));
    expect(ownerAVersion1.id, isNot(ownerAVersion2.id));
    expect(ownerBVersion1.cohort, 'intervention');
    expect(ownerAVersion2.cohort, 'follow-up');
    expect(await _assignmentCount(database), 3);
    expect(
      await repository.getAssignment(
        ownerId: 'owner-a',
        experimentId: 'isolation',
        experimentVersion: 1,
      ),
      sameAssignmentAs(ownerAVersion1),
    );
    expect(
      await repository.getAssignment(
        ownerId: 'owner-b',
        experimentId: 'isolation',
        experimentVersion: 1,
      ),
      sameAssignmentAs(ownerBVersion1),
    );
    expect(
      await repository.getAssignment(
        ownerId: 'owner-a',
        experimentId: 'isolation',
        experimentVersion: 2,
      ),
      sameAssignmentAs(ownerAVersion2),
    );
  });

  test('invalid assignment inputs fail before any mutation', () async {
    final overlong = List<String>.filled(257, 'x').join();
    final validAt = DateTime.utc(2026, 8, 14, 14);
    final cases =
        <
          ({
            String name,
            String ownerId,
            String experimentId,
            int experimentVersion,
            String cohort,
            String protocolVersion,
            DateTime assignedAtUtc,
          })
        >[
          (
            name: 'blank owner id',
            ownerId: '',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'untrimmed owner id',
            ownerId: ' owner-a ',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'overlong owner id',
            ownerId: overlong,
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'blank experiment id',
            ownerId: 'owner-a',
            experimentId: '',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'untrimmed experiment id',
            ownerId: 'owner-a',
            experimentId: ' experiment ',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'overlong experiment id',
            ownerId: 'owner-a',
            experimentId: overlong,
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'non-positive experiment version',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 0,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'blank cohort',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: '',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'untrimmed cohort',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: ' control ',
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'overlong cohort',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: overlong,
            protocolVersion: 'protocol',
            assignedAtUtc: validAt,
          ),
          (
            name: 'blank protocol version',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: '',
            assignedAtUtc: validAt,
          ),
          (
            name: 'untrimmed protocol version',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: ' protocol ',
            assignedAtUtc: validAt,
          ),
          (
            name: 'overlong protocol version',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: overlong,
            assignedAtUtc: validAt,
          ),
          (
            name: 'non-UTC assignment time',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: DateTime(2026, 8, 14, 14),
          ),
          (
            name: 'pre-epoch assignment time',
            ownerId: 'owner-a',
            experimentId: 'experiment',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol',
            assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
          ),
        ];

    for (final invalid in cases) {
      await expectLater(
        repository.assignIfAbsent(
          ownerId: invalid.ownerId,
          experimentId: invalid.experimentId,
          experimentVersion: invalid.experimentVersion,
          cohort: invalid.cohort,
          protocolVersion: invalid.protocolVersion,
          assignedAtUtc: invalid.assignedAtUtc,
        ),
        throwsArgumentError,
        reason: invalid.name,
      );
      expect(
        await _assignmentCount(database),
        0,
        reason: '${invalid.name} mutated assignment state',
      );
    }
  });

  test(
    'feature flags and kill switches never create or mutate assignment',
    () async {
      final mutableFeatures = MutableFeatureRegistry();
      final runtimeFeatures = RuntimeFeatureRegistry(mutableFeatures);
      addTearDown(runtimeFeatures.dispose);

      mutableFeatures.enable(Feature.shadowRewardV2);
      runtimeFeatures.emergencyOff(Feature.shadowRewardV2);
      runtimeFeatures.clearOverride(Feature.shadowRewardV2);
      expect(await _assignmentCount(database), 0);

      final original = await repository.assignIfAbsent(
        ownerId: 'owner-a',
        experimentId: 'explicit-only',
        experimentVersion: 1,
        cohort: 'control',
        protocolVersion: 'protocol-explicit',
        assignedAtUtc: DateTime.utc(2026, 8, 14, 15),
      );
      mutableFeatures.disable(Feature.shadowRewardV2);
      runtimeFeatures.emergencyOff(Feature.shadowRewardV2);

      expect(await _assignmentCount(database), 1);
      expect(
        await repository.getAssignment(
          ownerId: 'owner-a',
          experimentId: 'explicit-only',
          experimentVersion: 1,
        ),
        sameAssignmentAs(original),
      );
    },
  );
}

Matcher sameAssignmentAs(ExperimentAssignment expected) =>
    isA<ExperimentAssignment>()
        .having((value) => value.id, 'id', expected.id)
        .having((value) => value.ownerId, 'ownerId', expected.ownerId)
        .having(
          (value) => value.experimentId,
          'experimentId',
          expected.experimentId,
        )
        .having(
          (value) => value.experimentVersion,
          'experimentVersion',
          expected.experimentVersion,
        )
        .having((value) => value.cohort, 'cohort', expected.cohort)
        .having(
          (value) => value.protocolVersion,
          'protocolVersion',
          expected.protocolVersion,
        )
        .having(
          (value) => value.assignedAtUtc,
          'assignedAtUtc',
          expected.assignedAtUtc,
        );

Future<void> _expectConflictPreservesOriginal({
  required DriftExperimentAssignmentRepository repository,
  required AppDatabase database,
  required String conflictingCohort,
  required String conflictingProtocolVersion,
}) async {
  final assignedAtUtc = DateTime.utc(2026, 8, 14, 12);
  final original = await repository.assignIfAbsent(
    ownerId: 'owner-a',
    experimentId: 'conflict-safe',
    experimentVersion: 4,
    cohort: 'control',
    protocolVersion: 'protocol-4',
    assignedAtUtc: assignedAtUtc,
  );

  await expectLater(
    repository.assignIfAbsent(
      ownerId: 'owner-a',
      experimentId: 'conflict-safe',
      experimentVersion: 4,
      cohort: conflictingCohort,
      protocolVersion: conflictingProtocolVersion,
      assignedAtUtc: assignedAtUtc,
    ),
    throwsA(isA<ExperimentAssignmentConflict>()),
  );

  expect(await _assignmentCount(database), 1);
  expect(
    await repository.getAssignment(
      ownerId: 'owner-a',
      experimentId: 'conflict-safe',
      experimentVersion: 4,
    ),
    sameAssignmentAs(original),
  );
}

Future<void> _insertOwner(AppDatabase database, String ownerId) {
  return database.customInsert(
    'INSERT INTO local_owners(id, account_state, created_at_utc_ms) '
    'VALUES (?, ?, ?)',
    variables: [
      Variable<String>(ownerId),
      const Variable<String>('localGuest'),
      const Variable<int>(1),
    ],
  );
}

Future<int> _assignmentCount(AppDatabase database) {
  return database
      .customSelect('SELECT COUNT(*) AS count FROM experiment_assignments')
      .map((row) => row.read<int>('count'))
      .getSingle();
}
