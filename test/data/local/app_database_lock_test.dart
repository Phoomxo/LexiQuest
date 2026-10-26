import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as domain;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory databaseDirectory;

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'lexiquest-database-lock-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (_) async => databaseDirectory.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'production waits for an independent writer and configures contention policy',
    () async {
      final first = AppDatabase.production();
      AppDatabase? second;
      final releaseWriter = Completer<void>();
      Future<void>? heldWrite;

      try {
        final seededOwner = await DriftLocalOwnerRepository(
          first,
          generateId: () => 'retained-owner',
          nowUtc: () => DateTime.utc(2026, 10, 23, 5),
        ).getOrCreateActiveOwner();

        final writerStarted = Completer<void>();
        heldWrite = first.transaction(() async {
          await first.customUpdate(
            'UPDATE local_owners SET account_state = account_state WHERE id = ?',
            variables: [drift.Variable<String>(seededOwner.id)],
          );
          writerStarted.complete();
          await releaseWriter.future;
        });
        await writerStarted.future;

        second = AppDatabase.production();
        domain.LocalOwner? restoredOwner;
        Object? readError;
        final readCompleted = Completer<void>();
        DriftLocalOwnerRepository(
          second,
          generateId: () => 'unexpected-owner',
          nowUtc: () => DateTime.utc(2026, 10, 23, 5, 0, 1),
        ).getOrCreateActiveOwner().then(
          (owner) {
            restoredOwner = owner;
            readCompleted.complete();
          },
          onError: (Object error, StackTrace _) {
            readError = error;
            readCompleted.complete();
          },
        );

        final completedBeforeRelease = await Future.any([
          readCompleted.future.then((_) => true),
          Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
        ]);

        expect(
          readError,
          isNull,
          reason: 'connection B failed instead of waiting: $readError',
        );
        expect(
          completedBeforeRelease,
          isFalse,
          reason: 'connection B must wait while connection A owns the writer',
        );

        releaseWriter.complete();
        await heldWrite;
        await readCompleted.future;

        expect(readError, isNull);
        expect(restoredOwner?.id, seededOwner.id);
        expect(await _pragmaValue<String>(second, 'journal_mode'), 'wal');
        expect(await _pragmaValue<int>(second, 'busy_timeout'), 5000);
      } finally {
        if (!releaseWriter.isCompleted) {
          releaseWriter.complete();
        }
        await heldWrite;
        await second?.close();
        await first.close();
      }
    },
  );
}

Future<T> _pragmaValue<T>(AppDatabase database, String pragma) async {
  final row = await database.customSelect('PRAGMA $pragma').getSingle();
  return row.data.values.single as T;
}
