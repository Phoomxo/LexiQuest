import 'dart:async';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';

void main() {
  for (final table in [
    'vocabulary_words',
    'outbox_operations',
    'vocabulary_imports',
    'vocabulary_import_rows',
  ]) {
    test('AZ retirement after $table rolls back complete import', () async {
      final pause = WritePause(table);
      final db = AppDatabase(NativeDatabase.memory().interceptWith(pause));
      addTearDown(db.close);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'owner',
        nowUtc: () => DateTime.utc(2026),
      );
      var id = 0;
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(db),
        generateId: () => 'id-${id++}',
        nowUtc: () => DateTime.utc(2026),
      );
      final c = await vocabulary.createCategory('Private');
      final importer = ImportVocabulary(
        owners: owners,
        repository: DriftVocabularyImportRepository(db),
        generateId: () => 'id-${id++}',
        nowUtc: () => DateTime.utc(2026),
      );
      final before = await db.select(db.outboxOperations).get();
      var cancelled = false;
      Object? failure;
      pause.armed = true;
      final pending =
          importer(
            categoryId: c.id,
            rows: const [
              {'word': 'book', 'meaning': 'หนังสือ', 'partOfSpeech': 'noun'},
            ],
            sourceName: 'manual-import',
            expectedOwnerId: c.ownerId,
            isCancelled: () => cancelled,
          ).then<void>(
            (_) {},
            onError: (Object e) {
              failure = e;
            },
          );
      await pause.entered.future.timeout(const Duration(seconds: 10));
      cancelled = true;
      pause.release.complete();
      await pending;
      expect(await db.select(db.vocabularyWords).get(), isEmpty);
      expect(await db.select(db.vocabularyImports).get(), isEmpty);
      expect(await db.select(db.vocabularyImportRows).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), before);
      expect(failure, isNotNull);
      cancelled = false;
      final result = await importer(
        categoryId: c.id,
        rows: const [
          {'word': 'book', 'meaning': 'หนังสือ', 'partOfSpeech': 'noun'},
        ],
        sourceName: 'manual-import',
        expectedOwnerId: c.ownerId,
        isCancelled: () => cancelled,
      );
      expect(result.accepted, 1);
      expect(await db.select(db.vocabularyImportRows).get(), hasLength(1));
      expect(
        await db.select(db.outboxOperations).get(),
        hasLength(before.length + 1),
      );
    });
  }
}

class WritePause extends drift.QueryInterceptor {
  WritePause(this.table);
  final String table;
  bool armed = false;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runUpdate(executor, statement, args);
    if (armed && statement.contains('"$table"')) {
      armed = false;
      entered.complete();
      await release.future;
    }
    return result;
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await super.runInsert(executor, statement, args);
    if (armed && statement.contains('"$table"')) {
      armed = false;
      entered.complete();
      await release.future;
    }
    return result;
  }
}
