import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  for (final switchOwner in [false, true]) {
    test(
      switchOwner
          ? 'summary rejects A when the same owner provider switches during its query'
          : 'summary returns A when its owner remains active during the query',
      () async {
        final gate = _HeldProgressQuery();
        final database = AppDatabase(
          NativeDatabase.memory().interceptWith(gate),
        );
        final owners = _MutableOwners('owner-a');
        try {
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1),
              );
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'owner-b',
                  createdAtUtcMs: 2,
                  isActive: const Value(false),
                ),
              );
          await database
              .into(database.vocabularyCategories)
              .insert(
                VocabularyCategoriesCompanion.insert(
                  id: 'category-a',
                  ownerId: 'owner-a',
                  name: 'Private A',
                  normalizedName: 'private a',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: 'word-a',
                  ownerId: 'owner-a',
                  categoryId: 'category-a',
                  spelling: 'mug',
                  normalizedSpelling: 'mug',
                  meaning: 'แก้ว',
                  normalizedMeaning: 'แก้ว',
                  partOfSpeech: 'noun',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
          final wordsBefore = await database
              .select(database.vocabularyWords)
              .get();
          final outboxBefore = await database
              .select(database.outboxOperations)
              .get();
          final progress = ProgressUseCases(
            owners: owners,
            queries: DriftProgressQueries(database),
            nowUtc: () => DateTime.utc(2026, 11, 14),
          );
          gate.armed = true;
          final pending = progress.load();
          await gate.started.future;
          if (switchOwner) owners.id = 'owner-b';
          final checked = switchOwner
              ? expectLater(pending, throwsStateError)
              : expectLater(
                  pending,
                  completion(
                    isA<ProgressSnapshot>().having(
                      (snapshot) => snapshot.vocabularyWordCount,
                      'A vocabulary count',
                      1,
                    ),
                  ),
                );
          gate.release.complete();
          await checked;
          if (switchOwner) {
            expect((await progress.load()).vocabularyWordCount, 0);
          }
          expect(
            await database.select(database.vocabularyWords).get(),
            wordsBefore,
          );
          expect(
            await database.select(database.outboxOperations).get(),
            outboxBefore,
          );
        } finally {
          if (!gate.release.isCompleted) gate.release.complete();
          await database.close();
        }
      },
    );
  }
}

final class _HeldProgressQuery extends QueryInterceptor {
  bool armed = false;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (armed &&
        statement.contains('answer_attempts') &&
        args.contains('owner-a')) {
      armed = false;
      started.complete();
      await release.future;
    }
    return executor.runSelect(statement, args);
  }
}

final class _MutableOwners implements LocalOwnerRepository {
  _MutableOwners(this.id);

  String id;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 11, 14));

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}
