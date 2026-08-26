import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/flashcard_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/handwriting_self_check_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

const _typedChecksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test(
    'handwriting implementation cannot import capture or transport clients',
    () {
      final source = File(
        'lib/features/learning/presentation/handwriting_scratchpad.dart',
      ).readAsStringSync();

      expect(
        RegExp(
          r"^import .*?(?:camera|ocr|image|file|cache|database|outbox|analytics|network)",
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(source),
        isFalse,
      );
      expect(source, isNot(contains('toJson(')));
    },
  );

  test('canonical mode registry is an exact typed delivery and route join', () {
    final registrations = buildLessonModeRegistry().registrations.toList(
      growable: false,
    );
    const expected =
        <LessonMode, ({Feature feature, String entryId, String routeName})>{
          LessonMode.associativeReading: (
            feature: Feature.reading,
            entryId: 'home/learn/associative-reading',
            routeName: 'learning/associative-reading',
          ),
          LessonMode.meaningQuiz: (
            feature: Feature.quiz,
            entryId: 'home/learn/quiz',
            routeName: 'learning/quiz',
          ),
          LessonMode.typedRecall: (
            feature: Feature.quiz,
            entryId: 'home/learn/quiz',
            routeName: 'learning/typed-recall',
          ),
          LessonMode.definitionQuiz: (
            feature: Feature.quiz,
            entryId: 'home/learn/quiz',
            routeName: 'learning/definition-quiz',
          ),
          LessonMode.cloze: (
            feature: Feature.quiz,
            entryId: 'home/learn/quiz',
            routeName: 'learning/cloze',
          ),
          LessonMode.matching: (
            feature: Feature.quiz,
            entryId: 'home/learn/quiz',
            routeName: 'learning/matching',
          ),
          LessonMode.flashcard: (
            feature: Feature.srs,
            entryId: 'home/learn/srs',
            routeName: 'learning/srs',
          ),
          LessonMode.handwritingScratchpad: (
            feature: Feature.quiz,
            entryId: 'home/learn/quiz',
            routeName: 'learning/handwriting-scratchpad',
          ),
        };

    expect(registrations, hasLength(expected.length));
    expect(
      registrations.map((registration) => registration.mode).toSet(),
      expected.keys.toSet(),
    );
    expect(
      registrations.map((registration) => registration.adapter).toSet(),
      hasLength(expected.length),
    );
    expect(
      registrations
          .map((registration) => registration.productionEntryId)
          .toSet(),
      hasLength(expected.values.map((value) => value.feature).toSet().length),
      reason: 'sibling quiz modes share the one broad Feature.quiz delivery',
    );
    expect(
      registrations.map((registration) => registration.routeName).toSet(),
      hasLength(expected.length),
    );

    for (final registration in registrations) {
      final contract = expected[registration.mode]!;
      expect(registration.feature, contract.feature);
      expect(registration.productionEntryId, contract.entryId);
      expect(registration.routeName, contract.routeName);
      expect(
        productionFeatureContract[registration.feature]!.productionEntryId,
        registration.productionEntryId,
      );
      if (registration.mode == LessonMode.associativeReading ||
          registration.mode == LessonMode.typedRecall ||
          registration.mode == LessonMode.definitionQuiz ||
          registration.mode == LessonMode.cloze ||
          registration.mode == LessonMode.matching) {
        expect(registration.adapter, isA<HintSupportingLessonModeAdapter>());
      } else {
        expect(
          registration.adapter,
          isNot(isA<HintSupportingLessonModeAdapter>()),
          reason:
              'non-hint modes cannot silently become their own hint authority',
        );
      }
    }
    expect(
      registrations
          .singleWhere((entry) => entry.mode == LessonMode.flashcard)
          .adapter,
      isA<FlashcardModeAdapter>(),
    );
    expect(
      registrations
          .singleWhere((entry) => entry.mode == LessonMode.meaningQuiz)
          .adapter,
      isA<MeaningQuizModeAdapter>(),
    );
    expect(
      registrations
          .singleWhere((entry) => entry.mode == LessonMode.definitionQuiz)
          .adapter,
      isA<DefinitionQuizModeAdapter>(),
    );
    expect(
      registrations
          .singleWhere((entry) => entry.mode == LessonMode.cloze)
          .adapter,
      isA<ClozeModeAdapter>(),
    );
    expect(
      registrations
          .singleWhere((entry) => entry.mode == LessonMode.matching)
          .adapter,
      isA<MatchingModeAdapter>(),
    );
    expect(
      registrations
          .singleWhere(
            (entry) => entry.mode == LessonMode.handwritingScratchpad,
          )
          .adapter,
      isA<HandwritingSelfCheckAdapter>(),
    );
    expect(
      registrations
          .singleWhere((entry) => entry.mode == LessonMode.associativeReading)
          .adapter,
      isNot(isA<TypedRecallModeAdapter>()),
    );
    final registry = buildLessonModeRegistry();
    final typedRecall = registry.typedRecall;
    expect(typedRecall, isNotNull);
    expect(typedRecall!.feature, Feature.quiz);
    expect(typedRecall.productionEntryId, 'home/learn/quiz');
    expect(typedRecall.routeName, 'learning/typed-recall');
    expect(typedRecall.mode, LessonMode.typedRecall);
    expect(typedRecall.adapter, isA<TypedRecallModeAdapter>());
    expect(registry.resolveTypedRecall(), same(typedRecall));
    expect(
      registrations
          .singleWhere((entry) => entry.mode == LessonMode.matching)
          .deliveryState,
      LessonModeDeliveryState.implementedOff,
    );
    expect(
      registrations
          .singleWhere(
            (entry) => entry.mode == LessonMode.handwritingScratchpad,
          )
          .deliveryState,
      LessonModeDeliveryState.implementedOff,
    );
  });

  test(
    'hint capability is typed without adding a production delivery path',
    () {
      final registrations = buildLessonModeRegistry().registrations;
      final hintRegistrations = registrations
          .where(
            (registration) =>
                registration.adapter is HintSupportingLessonModeAdapter,
          )
          .toList(growable: false);
      final adapter = _HintBoundaryAdapter();

      expect(hintRegistrations, hasLength(5));
      expect(hintRegistrations.map((entry) => entry.mode).toSet(), <LessonMode>{
        LessonMode.associativeReading,
        LessonMode.typedRecall,
        LessonMode.definitionQuiz,
        LessonMode.cloze,
        LessonMode.matching,
      });
      expect(adapter, isA<LessonModeAdapter>());
      expect(adapter.hintPolicy.maximumHintLevel, 2);
      expect(registrations, hasLength(LessonMode.values.length));
    },
  );

  test(
    'typed recall owns versioned normalization correctness and assistance',
    () {
      const adapter = TypedRecallModeAdapter();
      final prompt = TypedRecallPrompt(
        wordId: 'typed-word',
        canonicalAnswer: 'Rail station',
        acceptedVariants: <String>['train stop'],
        acceptedVariantsRevision: 3,
        acceptedVariantsChecksumSha256: _typedChecksum,
        promptKind: TypedRecallPromptKind.meaning,
        normalizationRevision: typedRecallNormalizationRevisionV1,
        contentRevision: 3,
        contentChecksumSha256: _typedChecksum,
      );

      final exact = adapter.evaluate(
        prompt: prompt,
        response: '  RAIL   STATION ',
        support: const TypedRecallSupport.unassisted(),
      );
      final variant = adapter.evaluate(
        prompt: prompt,
        response: ' Train   Stop ',
        support: const TypedRecallSupport.unassisted(),
      );
      final hinted = adapter.evaluate(
        prompt: prompt,
        response: 'Rail station',
        support: const TypedRecallSupport(hint: HintUsageSnapshot.known(1)),
      );
      final supported = adapter.evaluate(
        prompt: prompt,
        response: 'not the answer',
        support: const TypedRecallSupport(
          hint: HintUsageSnapshot.unavailable(),
          additionalSupportUsed: true,
        ),
      );

      expect(exact.isCorrect, isTrue);
      expect(exact.responseCode, TypedRecallResponseCode.exact);
      expect(exact.evidenceClass, EvidenceClass.independentRecall);
      expect(exact.hintLevel, 0);
      expect(variant.isCorrect, isTrue);
      expect(variant.responseCode, TypedRecallResponseCode.acceptedVariant);
      expect(variant.evidenceClass, EvidenceClass.independentRecall);
      expect(hinted.evidenceClass, EvidenceClass.guidedPractice);
      expect(hinted.hintLevel, 1);
      expect(supported.isCorrect, isFalse);
      expect(supported.responseCode, TypedRecallResponseCode.incorrect);
      expect(supported.evidenceClass, EvidenceClass.guidedPractice);
      expect(supported.hintLevel, 1);
      for (final outcome in <TypedRecallEvaluation>[
        exact,
        variant,
        hinted,
        supported,
      ]) {
        expect(outcome.controlledResponseCode.length, lessThanOrEqualTo(32));
        expect(
          outcome.controlledResponseCode,
          matches(RegExp(r'^[a-z][a-z-]{0,31}$')),
        );
        expect(outcome.providerProvenance, isNot(contains('Rail station')));
        expect(outcome.providerProvenance.length, lessThanOrEqualTo(96));
      }
    },
  );

  test('typed recall fails closed for an unknown normalization revision', () {
    const adapter = TypedRecallModeAdapter();

    expect(
      () => adapter.evaluate(
        prompt: TypedRecallPrompt(
          wordId: 'typed-word',
          canonicalAnswer: 'station',
          promptKind: TypedRecallPromptKind.context,
          normalizationRevision: 'vocabulary-text-v999',
          contentRevision: 1,
          contentChecksumSha256: _typedChecksum,
        ),
        response: 'station',
        support: const TypedRecallSupport.unassisted(),
      ),
      throwsStateError,
    );
  });

  test('typed recall v1 canonicalizes Unicode without locale drift', () {
    const adapter = TypedRecallModeAdapter();
    final composed = TypedRecallPrompt(
      wordId: 'typed-cafe',
      canonicalAnswer: 'caf\u00e9',
      promptKind: TypedRecallPromptKind.meaning,
      normalizationRevision: typedRecallNormalizationRevisionV1,
      contentRevision: 4,
      contentChecksumSha256: _typedChecksum,
    );
    final turkishAsciiI = TypedRecallPrompt(
      wordId: 'typed-i',
      canonicalAnswer: 'I',
      promptKind: TypedRecallPromptKind.audio,
      normalizationRevision: typedRecallNormalizationRevisionV1,
      contentRevision: 2,
      contentChecksumSha256: _typedChecksum,
    );
    final turkishDottedI = TypedRecallPrompt(
      wordId: 'typed-dotted-i',
      canonicalAnswer: '\u0130',
      promptKind: TypedRecallPromptKind.audio,
      normalizationRevision: typedRecallNormalizationRevisionV1,
      contentRevision: 2,
      contentChecksumSha256: _typedChecksum,
    );

    expect(
      adapter
          .evaluate(
            prompt: composed,
            response: 'CAFE\u0301',
            support: const TypedRecallSupport.unassisted(),
          )
          .responseCode,
      TypedRecallResponseCode.exact,
    );
    expect(
      adapter
          .evaluate(
            prompt: turkishAsciiI,
            response: 'i',
            support: const TypedRecallSupport.unassisted(),
          )
          .responseCode,
      TypedRecallResponseCode.exact,
    );
    expect(
      adapter
          .evaluate(
            prompt: turkishDottedI,
            response: 'i',
            support: const TypedRecallSupport.unassisted(),
          )
          .responseCode,
      TypedRecallResponseCode.incorrect,
    );
  });

  test('typed recall validates scalar and pinned content bounds', () {
    const adapter = TypedRecallModeAdapter();
    TypedRecallPrompt prompt({
      int contentRevision = 1,
      String checksum = _typedChecksum,
    }) => TypedRecallPrompt(
      wordId: 'typed-bounds',
      canonicalAnswer: 'answer',
      promptKind: TypedRecallPromptKind.context,
      normalizationRevision: typedRecallNormalizationRevisionV1,
      contentRevision: contentRevision,
      contentChecksumSha256: checksum,
    );

    expect(
      adapter.evaluate(
        prompt: prompt(),
        response: 'a' * TypedRecallModeAdapter.maxAnswerScalars,
        support: const TypedRecallSupport.unassisted(),
      ),
      isA<TypedRecallEvaluation>(),
    );
    expect(
      () => adapter.evaluate(
        prompt: prompt(),
        response: 'a' * (TypedRecallModeAdapter.maxAnswerScalars + 1),
        support: const TypedRecallSupport.unassisted(),
      ),
      throwsArgumentError,
    );
    expect(
      () => adapter.evaluate(
        prompt: prompt(contentRevision: 0),
        response: 'answer',
        support: const TypedRecallSupport.unassisted(),
      ),
      throwsStateError,
    );
    expect(
      () => adapter.evaluate(
        prompt: prompt(checksum: 'unknown'),
        response: 'answer',
        support: const TypedRecallSupport.unassisted(),
      ),
      throwsStateError,
    );
  });

  test('flashcard adapter keeps reveal and independent recall disjoint', () {
    const adapter = FlashcardModeAdapter();
    final response = LessonResponse(
      sourceEvidenceId: 'flashcard-boundary',
      occurredAtUtc: DateTime.utc(2026, 8, 25),
      sessionId: 'flashcard-session',
      wordId: 'flashcard-word',
      promptMode: 'flashcardExposure',
      isCorrect: false,
      responseTimeMs: 250,
      attemptNumber: 1,
      feedbackContext: const AnswerFeedbackContext(
        canonicalCorrectAnswer: 'answer',
      ),
    );
    final exposure = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.exposure,
      skillId: 'srs-recall',
      hintLevel: 0,
      contentRevision: 'built-in-v1',
      engagementAllowed: true,
    );
    final assisted = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.guidedPractice,
      skillId: 'srs-recall',
      hintLevel: 1,
      contentRevision: 'built-in-v1',
      engagementAllowed: true,
    );

    expect(
      adapter.classify(response, LessonSupport(evidenceContext: exposure)),
      same(exposure),
    );
    expect(
      () => adapter.classify(
        LessonResponse(
          sourceEvidenceId: response.sourceEvidenceId,
          occurredAtUtc: response.occurredAtUtc,
          sessionId: response.sessionId,
          wordId: response.wordId,
          promptMode: 'srsRecall',
          isCorrect: true,
          responseTimeMs: response.responseTimeMs,
          attemptNumber: response.attemptNumber,
          feedbackContext: response.feedbackContext,
        ),
        LessonSupport(evidenceContext: assisted),
      ),
      throwsStateError,
    );
  });

  test('meaning quiz keeps both directions recognition-only', () {
    const adapter = MeaningQuizModeAdapter();
    final recognition = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.recognition,
      skillId: 'meaning-recall',
      hintLevel: 0,
      contentRevision: 'built-in-v1',
      engagementAllowed: true,
    );
    final independentRecall = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'meaning-recall',
      hintLevel: 0,
      contentRevision: 'built-in-v1',
      engagementAllowed: true,
    );
    LessonResponse response(String promptMode) => LessonResponse(
      sourceEvidenceId: 'meaning-boundary-$promptMode',
      occurredAtUtc: DateTime.utc(2026, 8, 26),
      sessionId: 'meaning-session',
      wordId: 'meaning-word',
      promptMode: promptMode,
      isCorrect: true,
      responseTimeMs: 250,
      attemptNumber: 1,
      feedbackContext: const AnswerFeedbackContext(
        canonicalCorrectAnswer: 'answer',
      ),
    );

    expect(
      adapter.classify(
        response('meaningChoice'),
        LessonSupport(evidenceContext: recognition),
      ),
      same(recognition),
    );
    expect(
      adapter.classify(
        response('wordChoice'),
        LessonSupport(evidenceContext: recognition),
      ),
      same(recognition),
    );
    expect(
      () => adapter.classify(
        response('wordChoice'),
        LessonSupport(evidenceContext: independentRecall),
      ),
      throwsStateError,
    );
  });

  test('cloze adapter owns input-specific pinned classification', () {
    const adapter = ClozeModeAdapter();
    LessonResponse response(String promptMode) => LessonResponse(
      sourceEvidenceId: 'cloze-boundary-$promptMode',
      occurredAtUtc: DateTime.utc(2026, 8, 26),
      sessionId: 'cloze-session',
      wordId: 'cloze-word',
      promptMode: promptMode,
      isCorrect: true,
      responseTimeMs: 250,
      attemptNumber: 1,
      feedbackContext: const AnswerFeedbackContext(
        canonicalCorrectAnswer: 'answer',
      ),
    );
    EvidenceContext context(
      EvidenceClass evidenceClass,
      int hintLevel,
    ) => EvidenceContext.legacyCompatibility(
      evidenceClass: evidenceClass,
      skillId: 'cloze-context',
      hintLevel: hintLevel,
      contentRevision:
          'lexical-cloze:cloze-word@1:'
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      engagementAllowed: true,
    );

    final selected = context(EvidenceClass.recognition, 0);
    final typed = context(EvidenceClass.independentRecall, 0);
    final guided = context(EvidenceClass.guidedPractice, 1);
    expect(
      adapter.classify(
        response('clozeSelected'),
        LessonSupport(evidenceContext: selected),
      ),
      same(selected),
    );
    expect(
      adapter.classify(
        response('clozeTyped'),
        LessonSupport(evidenceContext: typed),
      ),
      same(typed),
    );
    expect(
      adapter.classify(
        response('clozeTyped'),
        LessonSupport(evidenceContext: guided),
      ),
      same(guided),
    );
    expect(
      () => adapter.classify(
        response('clozeSelected'),
        LessonSupport(evidenceContext: typed),
      ),
      throwsStateError,
    );
  });

  test(
    'registry rejects alternate adapters competing for one delivery path',
    () {
      expect(
        () => LessonModeRegistry(<LessonModeRegistration>[
          const LessonModeRegistration(
            adapter: LegacyLessonModeAdapter(LessonMode.meaningQuiz),
            feature: Feature.quiz,
            productionEntryId: 'home/learn/quiz',
            routeName: 'learning/quiz',
          ),
          const LessonModeRegistration(
            adapter: LegacyLessonModeAdapter(LessonMode.flashcard),
            feature: Feature.srs,
            productionEntryId: 'home/learn/quiz',
            routeName: 'learning/quiz-alternate',
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => LessonModeRegistry(<LessonModeRegistration>[
          const LessonModeRegistration(
            adapter: LegacyLessonModeAdapter(LessonMode.meaningQuiz),
            feature: Feature.quiz,
            productionEntryId: 'home/learn/quiz',
            routeName: 'learning/quiz',
          ),
          const LessonModeRegistration(
            adapter: LegacyLessonModeAdapter(LessonMode.flashcard),
            feature: Feature.srs,
            productionEntryId: 'home/learn/srs',
            routeName: 'learning/quiz',
          ),
        ]),
        throwsArgumentError,
      );
    },
  );

  test(
    'bounded legacy adapters classify without becoming evidence authority',
    () async {
      final evidence = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'f05-boundary',
        hintLevel: 0,
        contentRevision: 'legacy-unknown',
        engagementAllowed: true,
      );
      final response = LessonResponse(
        sourceEvidenceId: 'boundary-evidence',
        occurredAtUtc: DateTime.utc(2026, 8, 24),
        sessionId: 'boundary-session',
        wordId: 'boundary-word',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
        feedbackContext: const AnswerFeedbackContext(
          canonicalCorrectAnswer: 'boundary answer',
        ),
      );

      for (final registration in buildLessonModeRegistry().registrations) {
        if (registration.mode == LessonMode.associativeReading ||
            registration.mode == LessonMode.typedRecall ||
            registration.mode == LessonMode.flashcard ||
            registration.mode == LessonMode.definitionQuiz ||
            registration.mode == LessonMode.cloze ||
            registration.mode == LessonMode.matching ||
            registration.mode == LessonMode.handwritingScratchpad) {
          continue;
        }
        expect(
          registration.adapter.classify(
            response,
            LessonSupport(evidenceContext: evidence),
          ),
          same(evidence),
        );
        await expectLater(
          registration.adapter.next(
            const LessonCursor(sessionId: 'boundary-session', index: 0),
          ),
          throwsStateError,
        );
      }
    },
  );
}

final class _HintBoundaryAdapter implements HintSupportingLessonModeAdapter {
  @override
  HintPolicy get hintPolicy => HintPolicy.staged(
    strategy: 'Use the word family.',
    context: 'Use the reviewed sentence.',
  );

  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      LessonItem(id: 'boundary-${cursor.index}');
}
