import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/learning/association_record.dart';
import 'package:vocab_learning_app/learning/learning_commit.dart';
import 'package:vocab_learning_app/learning/storage/drift_learning_repository.dart';
import 'package:vocab_learning_app/learning/storage/learning_database_factory_native.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'lexiquest-learning-',
    );
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('persists owner data after the background database restarts', () async {
    final factory = LearningDatabaseFactory.nativeForTesting(
      directoryProvider: () async => temporaryDirectory,
    );
    final firstDatabase = await factory.open();
    final firstRepository = DriftLearningRepository(firstDatabase);
    await firstRepository.commit(_associationCommit);
    await firstDatabase.close();

    final reopenedDatabase = await factory.open();
    final reopenedRepository = DriftLearningRepository(reopenedDatabase);
    final associations = await reopenedRepository.readAssociations(
      ownerId: 'owner-a',
      wordKey: 'word-a',
    );
    await reopenedDatabase.close();

    expect(associations, hasLength(1));
    expect(associations.single.cueText, 'private cue');
  });

  test('fails closed without replacing a corrupt database file', () async {
    final databaseFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}learning.sqlite',
    );
    const corruptBytes = <int>[0x4c, 0x51, 0x00, 0x7f, 0x20, 0x10];
    await databaseFile.writeAsBytes(corruptBytes, flush: true);
    final factory = LearningDatabaseFactory.nativeForTesting(
      directoryProvider: () async => temporaryDirectory,
    );

    await expectLater(
      factory.open(),
      throwsA(
        isA<LearningDatabaseOpenException>().having(
          (error) => error.code,
          'code',
          LearningDatabaseOpenErrorCode.corruptOrUnreadable,
        ),
      ),
    );

    expect(await databaseFile.readAsBytes(), corruptBytes);
  });

  test(
    'rejects unsupported schema versions without destructive migration',
    () async {
      final databaseFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}learning.sqlite',
      );
      final factory = LearningDatabaseFactory.nativeForTesting(
        directoryProvider: () async => temporaryDirectory,
      );
      final database = await factory.open();
      await database.customStatement('PRAGMA user_version = 99');
      await database.close();

      await expectLater(
        factory.open(),
        throwsA(
          isA<LearningDatabaseOpenException>().having(
            (error) => error.code,
            'code',
            LearningDatabaseOpenErrorCode.incompatibleSchema,
          ),
        ),
      );

      expect(databaseFile.existsSync(), isTrue);
      expect(databaseFile.lengthSync(), greaterThan(0));
    },
  );
}

final DateTime _now = DateTime.utc(2026, 7, 29, 12);

final LearningCommit _associationCommit = LearningCommit(
  commitId: 'commit-1',
  ownerId: 'owner-a',
  recordedAtUtc: _now,
  associations: [
    AssociationRecord(
      associationId: 'association-1',
      ownerId: 'owner-a',
      wordKey: 'word-a',
      cueType: AssociationCueType.keyword,
      cueText: 'private cue',
      origin: AssociationOrigin.userCreated,
      createdAtUtc: _now,
      updatedAtUtc: _now,
    ),
  ],
);
