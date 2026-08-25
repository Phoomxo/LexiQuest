import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/flashcard_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/cloze_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/definition_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
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
      if (registration.mode == LessonMode.definitionQuiz ||
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
          .singleWhere((entry) => entry.mode == LessonMode.matching)
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

      expect(hintRegistrations, hasLength(3));
      expect(hintRegistrations.map((entry) => entry.mode).toSet(), <LessonMode>{
        LessonMode.definitionQuiz,
        LessonMode.cloze,
        LessonMode.matching,
      });
      expect(adapter, isA<LessonModeAdapter>());
      expect(adapter.hintPolicy.maximumHintLevel, 2);
      expect(registrations, hasLength(LessonMode.values.length));
    },
  );

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
        if (registration.mode == LessonMode.flashcard ||
            registration.mode == LessonMode.definitionQuiz ||
            registration.mode == LessonMode.cloze ||
            registration.mode == LessonMode.matching) {
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
