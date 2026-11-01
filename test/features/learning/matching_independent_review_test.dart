import 'package:drift/drift.dart'
    show QueryExecutor, QueryInterceptor, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/matching_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/matching_exercise.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness harness;
  late MatchingUseCases matching;
  var ids = 0;

  setUp(() async {
    harness = await ConfiguredQuizHarness.open();
    ids = 0;
    matching = MatchingUseCases(
      repository: DriftMatchingRepository(
        DriftLearningRepository(
          harness.database,
          ownerWrites: harness.ownerWrites,
        ),
      ),
      generateId: () => 'synthetic-independent-matching-${++ids}',
      nowUtc: () => harness.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic-independent',
        buildId: 'synthetic-independent-matching',
      ),
    );
  });
  tearDown(() => harness.close());

  Future<MatchingState> start() async {
    final plan = await matching.prepare(
      expectedOwnerId: configuredOwnerId,
      categoryId: configuredCategoryId,
      stillCurrent: () => true,
    );
    return matching.start(plan!, stillCurrent: () => true);
  }

  Future<MatchingState> pending(MatchingState state, int index) async {
    final selected = await matching.saveSelection(
      state,
      wordIndex: index,
      meaningIndex: index,
      stillCurrent: () => true,
    );
    return matching.save(
      selected,
      matching.preparePair(
        selected,
        responseTime: const Duration(milliseconds: 300),
      ),
      stillCurrent: () => true,
    );
  }

  Future<MatchingState> complete() async {
    var state = await start();
    for (var index = 0; index < state.plan.words.length; index++) {
      state = await matching.commit(
        await pending(state, index),
        stillCurrent: () => true,
      );
      if (index + 1 < state.plan.words.length) {
        state = await matching.next(state, stillCurrent: () => true);
      }
    }
    final closing = await matching.save(
      state,
      matching.prepareFinish(state),
      stillCurrent: () => true,
    );
    return matching.finish(closing, stillCurrent: () => true);
  }

  test(
    'independent completed board cannot turn a missing score into zero',
    () async {
      final completed = await complete();
      expect(completed.completedSummary!.score, 100);
      await harness.database.customUpdate(
        'UPDATE learning_sessions SET score = NULL WHERE id = ?',
        variables: [Variable<String>(completed.plan.session.id)],
        updates: {harness.database.learningSessions},
      );
      final before = await harness.snapshot();
      await expectLater(
        matching.resume(
          sessionId: completed.plan.session.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await harness.snapshot(), before);
    },
  );

  test(
    'independent owner change after pair INSERT rolls back every table',
    () async {
      final staged = await pending(await start(), 0);
      final before = await harness.snapshot();
      final interference = _ChangeOwnerAfterPairInsert();
      await expectLater(
        harness.database.runWithInterceptor(
          () => matching.commit(staged, stillCurrent: () => true),
          interceptor: interference,
        ),
        throwsA(anything),
      );
      expect(interference.fired, isTrue);
      expect(await harness.snapshot(), before);
    },
  );

  test(
    'independent completed history survives later vocabulary removal as a pure read',
    () async {
      final completed = await complete();
      await harness.database.customUpdate(
        'UPDATE vocabulary_words SET is_deleted = 1 WHERE owner_id = ?',
        variables: [const Variable<String>(configuredOwnerId)],
        updates: {harness.database.vocabularyWords},
      );
      final before = await harness.snapshot();
      final historical = await matching.resume(
        sessionId: completed.plan.session.id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(historical.completedSummary!.score, 100);
      expect(historical.completedSummary!.correctCount, 4);
      expect(historical.checkpoint.matched, [0, 1, 2, 3]);
      expect(await harness.snapshot(), before);
    },
  );
}

final class _ChangeOwnerAfterPairInsert extends QueryInterceptor {
  bool fired = false;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    if (!fired &&
        RegExp(
          r'^INSERT INTO\s+"?answer_attempts"?\s',
          caseSensitive: false,
        ).hasMatch(statement)) {
      fired = true;
      await executor.runCustom('UPDATE local_owners SET is_active = (id = ?)', [
        configuredOtherOwnerId,
      ]);
    }
    return result;
  }
}
