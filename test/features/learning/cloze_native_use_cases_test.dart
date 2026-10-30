import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/cloze_session_harness.dart';

void main() {
  late ClozeSessionHarness h;
  setUp(() async => h = await ClozeSessionHarness.open());
  tearDown(() => h.close());

  test(
    'missing provider is unavailable without generation or durable writes',
    () async {
      final before = await h.storage.snapshot();
      final result = await h
          .useCases(withProvider: false)
          .prepareCloze(variant: ClozeVariant.typed, stillCurrent: () => true);
      expect(result, isNull);
      expect(h.provider.requests, isEmpty);
      expect(await h.storage.snapshot(), before);
    },
  );

  for (final variant in ClozeVariant.values) {
    test(
      '$variant performs actual generation outside transaction and captures returned metadata',
      () async {
        final before = await h.storage.snapshot();
        final result = await h.prepare(variant);
        expect(result, isNotNull);
        expect(h.provider.requests, hasLength(1));
        expect(h.provider.transactionStates, [false]);
        final request = h.provider.requests.single;
        expect(request.text, result!.word.spelling);
        expect(request.kind, ContentKind.sentence);
        expect(request.language, 'en');
        expect(result.content.cefr, CefrLevel.unknown);
        expect(await h.storage.snapshot(), before);
      },
    );

    test(
      '$variant does not generate without supported owned vocabulary',
      () async {
        await h.database.customStatement(
          "UPDATE vocabulary_words SET spelling = 'two words' WHERE owner_id = ?",
          [configuredOwnerId],
        );
        final before = await h.storage.snapshot();
        expect(await h.prepare(variant), isNull);
        expect(h.provider.requests, isEmpty);
        expect(await h.storage.snapshot(), before);
      },
    );

    test(
      '$variant inherited transaction denies before provider generation',
      () async {
        await h.database.transaction(() async {
          await expectLater(h.prepare(variant), throwsStateError);
        });
        expect(h.provider.requests, isEmpty);
        expect(await h.storage.count('learning_sessions'), 0);
      },
    );

    for (final change in ['owner', 'current']) {
      test(
        '$variant refuses $change changed during generation without persistence',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          h.provider.beforeResponse = (_) async {
            entered.complete();
            await release.future;
          };
          final pending = h.prepare(variant);
          final rejected = expectLater(pending, throwsStateError);
          await entered.future;
          if (change == 'owner') {
            await h.storage.switchOwner(configuredOtherOwnerId);
          } else {
            h.current = false;
          }
          release.complete();
          await rejected;
          expect(await h.storage.count('learning_sessions'), 0);
          expect(await h.storage.count('answer_attempts'), 0);
        },
      );
    }

    test(
      '$variant malformed generated content stays unavailable with no session',
      () async {
        h.provider.response = (request) => ContentResponse(
          text: '${request.text} and ${request.text} are repeated.',
          kind: ContentKind.sentence,
          cefr: CefrLevel.a1,
          language: 'en',
          modelVersion: 'synthetic',
          cached: false,
        );
        expect(await h.prepare(variant), isNull);
        expect(h.provider.requests, hasLength(1));
        expect(await h.storage.count('learning_sessions'), 0);
      },
    );

    for (final correct in [false, true]) {
      test(
        '$variant derives correctness and declared nonparticipant evidence for $correct response',
        () async {
          final exercise = (await h.prepare(variant))!;
          final answer = h.answer(exercise, correct: correct);
          expect(answer.isCorrect, correct);
          expect(
            answer.promptMode,
            variant == ClozeVariant.typed ? 'clozeTyped' : 'clozeChoice',
          );
          expect(
            answer.evidenceContext.evidenceClass,
            variant == ClozeVariant.typed
                ? EvidenceClass.guidedPractice
                : EvidenceClass.recognition,
          );
          expect(
            answer.evidenceContext.hintLevel,
            variant == ClozeVariant.typed ? 1 : 0,
          );
          expect(answer.evidenceContext.skillId, 'cloze-context');
          expect(answer.evidenceContext.engagementAllowed, isFalse);
          expect(
            answer.evidenceContext.classificationSource,
            EvidenceClassificationSource.declared,
          );
          expect(
            answer.evidenceContext.contentRevision,
            exercise.evidenceContentRevision,
          );
          expect(answer.providerProvenance, exercise.providerProvenance);
          expect(answer.responseTimeMs, 1234);
          expect(await h.storage.count('answer_attempts'), 0);
        },
      );
    }
  }

  test(
    'choice needs three distinct same-category words before any generation',
    () async {
      await h.database.customStatement(
        'DELETE FROM vocabulary_words WHERE owner_id = ? AND id NOT IN (?, ?)',
        [configuredOwnerId, configuredWordIds[0], configuredWordIds[1]],
      );
      expect(await h.prepare(ClozeVariant.choice), isNull);
      expect(h.provider.requests, isEmpty);
      final typed = await h.prepare(ClozeVariant.typed);
      expect(typed, isA<TypedClozeSession>());
    },
  );

  test(
    'choice cannot substitute another category or duplicate spelling',
    () async {
      await h.database.customStatement(
        "UPDATE vocabulary_words SET spelling = 'STATION' WHERE owner_id = ?",
        [configuredOwnerId],
      );
      expect(await h.prepare(ClozeVariant.choice), isNull);
      expect(h.provider.requests, isEmpty);
    },
  );

  test(
    'unknown selected choice ID is rejected before an answer intent exists',
    () async {
      final exercise =
          (await h.prepare(ClozeVariant.choice))! as ChoiceClozeSession;
      expect(
        () => h.learning.prepareNativeAnswer(
          ChoiceClozeAnswerInput(
            exercise: exercise,
            optionId: 'foreign-option-id',
            responseTime: Duration.zero,
          ),
        ),
        throwsArgumentError,
      );
    },
  );
}
