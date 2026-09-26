import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
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
      'AX delete retirement after $table write rolls back word and outbox',
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
            .deleteWord(
              w.id,
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
        await useCases.deleteWord(
          w.id,
          expectedOwnerId: c.ownerId,
          mutationAllowed: () => allowed,
        );
        expect(
          (await (db.select(
            db.vocabularyWords,
          )..where((r) => r.id.equals(w.id))).getSingle()).isDeleted,
          isTrue,
        );
        expect(
          (await db.select(db.outboxOperations).get()).length,
          before.length + 1,
        );
      },
    );
  }
  test(
    'AX canonical owner replacement during owner read rejects old deletion',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var id = 0;
      var ownerId = 0;
      final canonical = DriftLocalOwnerRepository(
        db,
        generateId: () => 'owner-${ownerId++}',
        nowUtc: () => DateTime.utc(2026),
      );
      final owners = _DelayedOwner(canonical, db);
      final useCases = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(db),
        generateId: () => 'item-${id++}',
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
      owners.replaceOnRead = true;
      Object? failure;
      try {
        await useCases.deleteWord(
          w.id,
          expectedOwnerId: c.ownerId,
          mutationAllowed: () => true,
        );
      } catch (e) {
        failure = e;
      }
      expect((await canonical.getOrCreateActiveOwner()).id, isNot(c.ownerId));
      expect(
        (await (db.select(
          db.vocabularyWords,
        )..where((r) => r.id.equals(w.id))).getSingle()).isDeleted,
        isFalse,
      );
      expect(await db.select(db.outboxOperations).get(), before);
      expect(failure, isNotNull);
    },
  );
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

class _DelayedOwner implements LocalOwnerRepository {
  _DelayedOwner(this.delegate, this.db);
  final DriftLocalOwnerRepository delegate;
  final AppDatabase db;
  bool replaceOnRead = false;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    final owner = await delegate.getOrCreateActiveOwner();
    if (replaceOnRead) {
      replaceOnRead = false;
      await db.transaction(() async {
        await db.customUpdate(
          'UPDATE local_owners SET is_active = 0',
          updates: {db.localOwners},
        );
        await delegate.getOrCreateActiveOwner();
      });
    }
    return owner;
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      delegate.bindFirebaseUid(ownerId, firebaseUid);
}
