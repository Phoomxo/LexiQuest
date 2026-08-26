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
        LessonMode.typedRecall,
        LessonMode.definitionQuiz,
        LessonMode.cloze,
        LessonMode.matching,
        LessonMode.flashcard,
        LessonMode.handwritingScratchpad,
      });
      expect(registrations, hasLength(8));
      expect(
        <LessonMode, Feature>{
          for (final entry in registrations) entry.mode: entry.feature,
        },
        <LessonMode, Feature>{
          LessonMode.associativeReading: Feature.reading,
          LessonMode.meaningQuiz: Feature.quiz,
          LessonMode.typedRecall: Feature.quiz,
          LessonMode.definitionQuiz: Feature.quiz,
          LessonMode.cloze: Feature.quiz,
          LessonMode.matching: Feature.quiz,
          LessonMode.flashcard: Feature.srs,
          LessonMode.handwritingScratchpad: Feature.quiz,
        },
      );
      expect(
        registry.find(LessonMode.flashcard)!.adapter,
        isA<FlashcardModeAdapter>(),
      );
      expect(
        registry.find(LessonMode.meaningQuiz)!.adapter,
        isA<MeaningQuizModeAdapter>(),
      );
      expect(
        registry.find(LessonMode.definitionQuiz)!.adapter,
        isA<DefinitionQuizModeAdapter>(),
      );
      expect(registry.find(LessonMode.cloze)!.adapter, isA<ClozeModeAdapter>());
      expect(
        registry.find(LessonMode.matching)!.adapter,
        isA<MatchingModeAdapter>(),
      );
      expect(
        registry.find(LessonMode.handwritingScratchpad)!.adapter,
        isA<HandwritingSelfCheckAdapter>(),
      );
      expect(
        registry.find(LessonMode.associativeReading)!.adapter,
        isNot(isA<TypedRecallModeAdapter>()),
      );
      expect(registry.typedRecall, isNotNull);
      expect(registry.typedRecall!.feature, Feature.quiz);
      expect(registry.typedRecall!.productionEntryId, 'home/learn/quiz');
      expect(registry.typedRecall!.routeName, 'learning/typed-recall');
      expect(registry.typedRecall!.mode, LessonMode.typedRecall);
      expect(registry.typedRecall!.adapter, isA<TypedRecallModeAdapter>());
      expect(registry.resolveTypedRecall(), same(registry.typedRecall));
      expect(
        registry.find(LessonMode.matching)!.deliveryState,
        LessonModeDeliveryState.implementedOff,
      );
      expect(registry.resolve(LessonMode.matching), isNull);
      expect(
        registry.find(LessonMode.handwritingScratchpad)!.deliveryState,
        LessonModeDeliveryState.implementedOff,
      );
      expect(registry.resolve(LessonMode.handwritingScratchpad), isNull);
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
          LessonMode.typedRecall: 'learning/typed-recall',
          LessonMode.definitionQuiz: 'learning/definition-quiz',
          LessonMode.cloze: 'learning/cloze',
          LessonMode.matching: 'learning/matching',
          LessonMode.flashcard: 'learning/srs',
          LessonMode.handwritingScratchpad: 'learning/handwriting-scratchpad',
        },
      );
    },
  );

  test('matching delivery requires an explicit typed enable', () {
    final registry = buildLessonModeRegistry(
      matchingDeliveryState: LessonModeDeliveryState.enabled,
    );

    expect(registry.resolve(LessonMode.matching), isNotNull);
    expect(
      registry.resolve(LessonMode.matching)!.deliveryState,
      LessonModeDeliveryState.enabled,
    );
  });

  test('handwriting delivery requires an explicit typed enable', () {
    final registry = buildLessonModeRegistry(
      handwritingDeliveryState: LessonModeDeliveryState.enabled,
    );

    expect(registry.resolve(LessonMode.handwritingScratchpad), isNotNull);
    expect(
      registry.resolve(LessonMode.handwritingScratchpad)!.deliveryState,
      LessonModeDeliveryState.enabled,
    );
    expect(
      LessonMode.handwritingScratchpad.defaultDelivery,
      LessonModeDefaultDelivery.implementedOff,
    );
    expect(
      LessonMode.matching.defaultDelivery,
      LessonModeDefaultDelivery.enabled,
    );
  });

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
