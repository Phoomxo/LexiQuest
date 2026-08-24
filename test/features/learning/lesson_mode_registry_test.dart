import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/flashcard_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/registries/feature.dart';

void main() {
  test(
    'production registry has one adapter for each canonical learning entry',
    () {
      final registry = buildLessonModeRegistry();
      final registrations = registry.registrations.toList(growable: false);

      expect(registrations.map((entry) => entry.mode).toSet(), <LessonMode>{
        LessonMode.associativeReading,
        LessonMode.meaningQuiz,
        LessonMode.flashcard,
      });
      expect(registrations, hasLength(3));
      expect(
        <LessonMode, Feature>{
          for (final entry in registrations) entry.mode: entry.feature,
        },
        <LessonMode, Feature>{
          LessonMode.associativeReading: Feature.reading,
          LessonMode.meaningQuiz: Feature.quiz,
          LessonMode.flashcard: Feature.srs,
        },
      );
      expect(
        registry.find(LessonMode.flashcard)!.adapter,
        isA<FlashcardModeAdapter>(),
      );
      expect(
        registry.find(LessonMode.meaningQuiz)!.adapter,
        isA<LegacyLessonModeAdapter>(),
      );
      for (final entry in registrations) {
        expect(
          entry.productionEntryId,
          productionFeatureContract[entry.feature]!.productionEntryId,
        );
        expect(registry.find(entry.mode), same(entry));
      }
      expect(
        <LessonMode, String>{
          for (final entry in registrations) entry.mode: entry.routeName,
        },
        <LessonMode, String>{
          LessonMode.associativeReading: 'learning/associative-reading',
          LessonMode.meaningQuiz: 'learning/quiz',
          LessonMode.flashcard: 'learning/srs',
        },
      );
    },
  );

  test('registry rejects duplicate adapters for one mode', () {
    expect(
      () => LessonModeRegistry(<LessonModeRegistration>[
        const LessonModeRegistration(
          adapter: LegacyLessonModeAdapter(LessonMode.meaningQuiz),
          feature: Feature.quiz,
          productionEntryId: 'home/learn/quiz',
          routeName: 'learning/quiz',
        ),
        const LessonModeRegistration(
          adapter: LegacyLessonModeAdapter(LessonMode.meaningQuiz),
          feature: Feature.quiz,
          productionEntryId: 'duplicate',
          routeName: 'learning/quiz-duplicate',
        ),
      ]),
      throwsArgumentError,
    );
  });
}
