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
  for (final table in ['vocabulary_categories', 'outbox_operations']) {
    test(
      'AW create retirement after $table write rolls back category and outbox',
      () async {
        final pause = WritePause(table);
        final db = AppDatabase(NativeDatabase.memory().interceptWith(pause));
        addTearDown(db.close);
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'owner',
          nowUtc: () => DateTime.utc(2026),
        );
        final useCases = VocabularyUseCases(
          owners: owners,
          vocabulary: DriftVocabularyRepository(db),
          generateId: () => 'category',
          nowUtc: () => DateTime.utc(2026),
        );
        final owner = await owners.getOrCreateActiveOwner();
        var allowed = true;
        pause.armed = true;
        Object? failure;
        final pending = useCases
            .createCategory(
              'Draft',
              expectedOwnerId: owner.id,
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
        expect(await db.select(db.vocabularyCategories).get(), isEmpty);
        expect(await db.select(db.outboxOperations).get(), isEmpty);
        expect(failure, isNotNull);
        allowed = true;
        await useCases.createCategory(
          'Draft',
          expectedOwnerId: owner.id,
          mutationAllowed: () => allowed,
        );
        expect(await db.select(db.vocabularyCategories).get(), hasLength(1));
        expect(await db.select(db.outboxOperations).get(), hasLength(1));
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
