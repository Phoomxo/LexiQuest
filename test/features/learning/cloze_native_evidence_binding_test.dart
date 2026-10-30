import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/cloze_session_harness.dart';

void main() {
  late ClozeSessionHarness h;
  setUp(() async => h = await ClozeSessionHarness.open());
  tearDown(() => h.close());

  for (final variant in ClozeVariant.values) {
    test(
      '$variant final awaited owner read cannot return a stale visible generation',
      () async {
        final before = await h.storage.snapshot();
        final interference = _FinalOwnerRead(h);
        await expectLater(
          h.database.runWithInterceptor(
            () => h.prepare(variant),
            interceptor: interference,
          ),
          throwsStateError,
        );
        expect(interference.fired, isTrue);
        expect(h.provider.requests, hasLength(1));
        expect(await h.storage.snapshot(), before);
      },
    );

    for (final mutation in ['SQL pin', 'provider', 'prompt', 'word', 'skill']) {
      test(
        '$variant rejects substituted $mutation in first answer before any fact is saved',
        () async {
          final exercise = await h.ready(variant);
          final original = h.answer(exercise);
          final contextJson = Map<String, Object?>.from(
            original.evidenceContext.toJson(),
          );
          if (mutation == 'SQL pin') {
            contextJson['contentRevision'] = exercise.wordContentRevision;
          }
          if (mutation == 'skill') contextJson['skillId'] = 'foreign-skill';
          final forged = RecordAnswerCommand(
            id: original.id,
            ownerId: original.ownerId,
            sessionId: original.sessionId,
            wordId: mutation == 'word'
                ? configuredWordIds.last
                : original.wordId,
            promptMode: mutation == 'prompt'
                ? 'dictation'
                : original.promptMode,
            isCorrect: original.isCorrect,
            responseTimeMs: original.responseTimeMs,
            attemptNumber: original.attemptNumber,
            occurredAtUtc: original.occurredAtUtc,
            providerProvenance: mutation == 'provider'
                ? 'synthetic-other-model'
                : original.providerProvenance,
            evidenceContext: EvidenceContext.fromJson(contextJson),
          );
          final before = await h.storage.snapshot();
          await expectLater(
            h.learning.commitNativeAnswer(
              exercise,
              forged,
              stillCurrent: () => true,
            ),
            throwsArgumentError,
          );
          expect(await h.storage.snapshot(), before);
          final saved = await h.learning.commitNativeAnswer(
            exercise,
            original,
            stillCurrent: () => true,
          );
          expect(saved.inserted, isTrue);
          expect(saved.srs, isNull);
        },
      );
    }
  }

  test(
    'typed raw response is neither persisted nor included in its evidence pin',
    () async {
      final exercise = await h.ready(ClozeVariant.typed) as TypedClozeSession;
      const response = 'synthetic raw response must stay transient 3f62';
      final command = h.learning.prepareNativeAnswer(
        TypedClozeAnswerInput(
          exercise: exercise,
          response: response,
          responseTime: const Duration(milliseconds: 542),
        ),
      );
      expect(command.isCorrect, isFalse);
      await h.learning.commitNativeAnswer(
        exercise,
        command,
        stillCurrent: () => true,
      );
      await h.learning.finishNativeExercise(
        h.learning.prepareNativeFinish(exercise, command),
        stillCurrent: () => true,
      );
      expect(jsonEncode(await h.storage.snapshot()), isNot(contains(response)));
      expect(
        command.evidenceContext.contentRevision,
        exercise.evidenceContentRevision,
      );
      final stored = await h.database
          .select(h.database.answerAttempts)
          .getSingle();
      expect((stored.isCorrect, stored.responseTimeMs), (false, 542));
    },
  );
}

final class _FinalOwnerRead extends drift.QueryInterceptor {
  _FinalOwnerRead(this.harness);
  final ClozeSessionHarness harness;
  bool fired = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (!fired &&
        harness.provider.requests.isNotEmpty &&
        statement.toLowerCase().contains('from "local_owners"')) {
      fired = true;
      harness.current = false;
    }
    return result;
  }
}
