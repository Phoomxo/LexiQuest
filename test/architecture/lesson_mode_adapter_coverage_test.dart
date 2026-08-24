import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  test('canonical mode registry is an exact typed delivery and route join', () {
    final registrations = buildLegacyLessonModeRegistry().registrations.toList(
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
      hasLength(expected.length),
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
    }
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

      for (final registration
          in buildLegacyLessonModeRegistry().registrations) {
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
