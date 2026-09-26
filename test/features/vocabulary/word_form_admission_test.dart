import 'dart:async';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

void main() {
  for (final table in ['vocabulary_words', 'outbox_operations']) {
    test(
      'AY update retirement after $table write rolls back word and outbox',
      () async {
        final pause = WritePause(table);
        final db = AppDatabase(NativeDatabase.memory().interceptWith(pause));
        addTearDown(db.close);
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'owner',
          nowUtc: () => DateTime.utc(2026),
        );
        var id = 0;
        final useCases = VocabularyUseCases(
          owners: owners,
          vocabulary: DriftVocabularyRepository(db),
          generateId: () => 'id-${id++}',
          nowUtc: () => DateTime.utc(2026),
        );
        final c = await useCases.createCategory('Private');
        final w = await useCases.createWord(
          CreateWordCommand(
            categoryId: c.id,
            spelling: 'book',
            meaning: 'หนังสือ',
            partOfSpeech: 'noun',
          ),
        );
        final before = await db.select(db.outboxOperations).get();
        var allowed = true;
        Object? failure;
        pause.armed = true;
        final pending = useCases
            .updateWord(
              UpdateWordCommand(
                id: w.id,
                categoryId: c.id,
                spelling: w.spelling,
                meaning: "changed",
                partOfSpeech: "noun",
              ),
              expectedOwnerId: c.ownerId,
              mutationAllowed: () => allowed,
            )
            .then<void>(
              (_) {},
              onError: (Object e) {
                failure = e;
              },
            );
        await pause.entered.future.timeout(const Duration(seconds: 10));
        allowed = false;
        pause.release.complete();
        await pending;
        final row = await (db.select(
          db.vocabularyWords,
        )..where((r) => r.id.equals(w.id))).getSingle();
        expect(row.isDeleted, isFalse);
        expect(row.localRevision, w.localRevision);
        expect(await db.select(db.outboxOperations).get(), before);
        expect(failure, isNotNull);
        allowed = true;
        await useCases.updateWord(
          UpdateWordCommand(
            id: w.id,
            categoryId: c.id,
            spelling: w.spelling,
            meaning: "changed",
            partOfSpeech: "noun",
          ),
          expectedOwnerId: c.ownerId,
          mutationAllowed: () => allowed,
        );
        expect(
          (await (db.select(
            db.vocabularyWords,
          )..where((r) => r.id.equals(w.id))).getSingle()).meaning,
          "changed",
        );
        expect(
          (await db.select(db.outboxOperations).get()).length,
          before.length + 1,
        );
      },
    );
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
