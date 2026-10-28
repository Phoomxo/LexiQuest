import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late AppDatabase db;
  late DriftLearningRepository repository;
  final start = DateTime.utc(2026, 9, 19, 12);
  LearningSessionDraft draft({String owner = 'a', DateTime? at}) =>
      LearningSessionDraft(
        id: 'session:test',
        ownerId: owner,
        activityType: 'quiz',
        startedAtUtc: at ?? start,
        appVersion: 'test',
        buildId: 'test',
      );
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftLearningRepository(db);
    await db
        .into(db.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'a', createdAtUtcMs: 0));
    await db
        .into(db.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'b',
            createdAtUtcMs: 0,
            isActive: const Value(false),
          ),
        );
  });
  tearDown(() => db.close());
  for (final abandon in [false, true]) {
    test(
      'F02 rejects backward ${abandon ? "abandon" : "finish"} atomically',
      () async {
        await repository.startSession(draft());
        final before = (await db.select(db.learningSessions).getSingle())
            .toJson();
        final at = start.subtract(const Duration(milliseconds: 1));
        await expectLater(
          abandon
              ? repository.abandonSession(
                  ownerId: 'a',
                  sessionId: 'session:test',
                  abandonedAtUtc: at,
                )
              : repository.finishSession(
                  ownerId: 'a',
                  sessionId: 'session:test',
                  endedAtUtc: at,
                ),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          (await db.select(db.learningSessions).getSingle()).toJson(),
          before,
        );
        expect(await db.select(db.rewardTransactions).get(), isEmpty);
        expect(await db.select(db.outboxOperations).get(), isEmpty);
        final result = abandon
            ? await repository.abandonSession(
                ownerId: 'a',
                sessionId: 'session:test',
                abandonedAtUtc: start,
              )
            : await repository.finishSession(
                ownerId: 'a',
                sessionId: 'session:test',
                endedAtUtc: start,
              );
        expect(result.endedAtUtc, start);
        expect(
          await repository.listSessionHistory(ownerId: 'a', limit: 10),
          hasLength(abandon ? 0 : 1),
        );
      },
    );
  }
  test(
    'F02 generic admission rejects an owner switched during dispatch',
    () async {
      final held = _HeldRepository(db);
      await db
          .into(db.vocabularyCategories)
          .insert(
            VocabularyCategoriesCompanion.insert(
              id: 'cat',
              ownerId: 'a',
              name: 'Test',
              normalizedName: 'test',
              createdAtUtcMs: 0,
              updatedAtUtcMs: 0,
            ),
          );
      await db
          .into(db.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'word',
              ownerId: 'a',
              categoryId: 'cat',
              spelling: 'word',
              normalizedSpelling: 'word',
              meaning: 'meaning',
              normalizedMeaning: 'meaning',
              partOfSpeech: 'noun',
              createdAtUtcMs: 0,
              updatedAtUtcMs: 0,
            ),
          );
      final learning = LearningUseCases(
        owners: DriftLocalOwnerRepository(
          db,
          generateId: () => 'unused',
          nowUtc: () => start,
        ),
        repository: held,
        generateId: () => 'test',
        nowUtc: () => start,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final pending = learning.startQuiz(limit: 1);
      final rejected = expectLater(pending, throwsA(isA<StateError>()));
      await held.entered.future;
      await db.transaction(() async {
        await db.customStatement('UPDATE local_owners SET is_active = 0');
        await db.customStatement(
          "UPDATE local_owners SET is_active = 1 WHERE id = 'b'",
        );
      });
      held.release.complete();
      await rejected;
      expect(await db.select(db.learningSessions).get(), isEmpty);
    },
  );
  test(
    'F02 generic ID replay is exact and rejects owner or timestamp collision',
    () async {
      await repository.startSession(draft());
      await repository.startSession(draft());
      await expectLater(
        repository.startSession(draft(owner: 'b')),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        repository.startSession(
          draft(at: start.add(const Duration(seconds: 1))),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await db.select(db.learningSessions).get(), hasLength(1));
    },
  );
}

class _HeldRepository implements LearningRepository {
  _HeldRepository(AppDatabase database)
    : delegate = DriftLearningRepository(database);
  final DriftLearningRepository delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> startSession(LearningSessionDraft session) async {
    entered.complete();
    await release.future;
    await delegate.startSession(session);
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    limit: limit,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
