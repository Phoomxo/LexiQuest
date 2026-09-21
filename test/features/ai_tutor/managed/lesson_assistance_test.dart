import 'dart:convert';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/lesson_assistance_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';

void main() {
  testWidgets(
    'visible native feedback is available even when shell feedback is absent',
    (tester) async {
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      final feedback = AnswerFeedback.fromCommittedResult(
        result: const AnswerRecordResult(
          inserted: true,
          isCorrect: true,
          srs: null,
        ),
        context: const AnswerFeedbackContext(canonicalCorrectAnswer: 'กระเป๋า'),
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: Scaffold(
              body: LessonAssistanceContext(
                ownerId: 'a',
                state: const LessonSessionState(
                  mode: LessonMode.meaningQuiz,
                  status: LessonSessionStatus.active,
                  committedResponseCount: 1,
                  itemCount: 1,
                ),
                child: AnswerFeedbackPanel(feedback: feedback),
              ),
            ),
          ),
        ),
      );
      final contexts = registry.snapshot()['context'] as List;
      final visible = contexts.singleWhere(
        (row) => row['id'] == 'lesson/committed-feedback',
      );
      final data = jsonDecode(visible['value'] as String) as Map;
      expect(
        (data['lastCommittedFeedback'] as Map)['correctAnswer'],
        'กระเป๋า',
      );
      expect((data['lastCommittedFeedback'] as Map)['isCorrect'], isTrue);
      expect(registry.snapshot()['actions'], isEmpty);
      expect(find.text('คำตอบที่ถูก: กระเป๋า'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(registry.snapshot()['context'], isEmpty);
    },
  );

  testWidgets('long committed answers remain bounded valid context JSON', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => 'a');
    final answer = List.filled(500, '"\n🧠').join();
    final feedback = AnswerFeedback.fromCommittedResult(
      result: const AnswerRecordResult(
        inserted: true,
        isCorrect: false,
        srs: null,
      ),
      context: AnswerFeedbackContext(canonicalCorrectAnswer: answer),
    );
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: MaterialApp(
          home: LessonAssistanceContext(
            ownerId: 'a',
            state: const LessonSessionState(
              mode: LessonMode.dictation,
              status: LessonSessionStatus.active,
              committedResponseCount: 1,
              itemCount: 4,
            ),
            feedback: feedback,
            child: const Text('Original'),
          ),
        ),
      ),
    );
    final value =
        (registry.snapshot()['context'] as List).single['value'] as String;
    expect(value.length, lessThanOrEqualTo(1000));
    final context = jsonDecode(value) as Map;
    expect(
      (context['lastCommittedFeedback'] as Map)['correctAnswerTruncated'],
      isTrue,
    );
    expect(context['committedResponses'], 1);
  });

  testWidgets('attaching lesson owner preserves the learner draft', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => 'a');
    Widget app(String? owner) => MenuActionScope(
      registry: registry,
      child: MaterialApp(
        home: Scaffold(
          body: LessonAssistanceContext(
            ownerId: owner,
            state: const LessonSessionState.planned(LessonMode.typedRecall),
            child: const TextField(),
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(null));
    await tester.enterText(find.byType(TextField), 'my unfinished answer');
    await tester.pumpWidget(app('a'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text ??
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
      'my unfinished answer',
    );
  });

  testWidgets(
    'all mode assistance is read-only, bilingual and preserves manual controls',
    (tester) async {
      final registry = MenuActionRegistry(currentOwner: () => 'owner-a');
      var manualAnswers = 0;
      for (final mode in LessonMode.values) {
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: MaterialApp(
              home: LessonAssistanceContext(
                ownerId: 'owner-a',
                state: LessonSessionState(
                  mode: mode,
                  status: LessonSessionStatus.active,
                  itemCount: 4,
                  committedResponseCount: 1,
                ),
                direction: SessionDirection.reverse,
                child: TextButton(
                  onPressed: () => manualAnswers++,
                  child: const Text('Manual answer'),
                ),
              ),
            ),
          ),
        );
        final snapshot = registry.snapshot();
        expect(
          snapshot['actions'],
          isEmpty,
          reason: 'Assistance cannot answer or score',
        );
        final data =
            jsonDecode((snapshot['context'] as List).single['value'] as String)
                as Map;
        expect(data['mode'], mode.id);
        expect(data['direction'], 'reverse');
        expect(data['languages'], ['en', 'th']);
        expect(data['committedResponses'], 1);
        expect(data['guidance'], isNotEmpty);
        expect(data.containsKey('answer'), isFalse);
        await tester.tap(find.text('Manual answer'));
      }
      expect(manualAnswers, LessonMode.values.length);
      await tester.pumpWidget(
        MaterialApp(
          home: LessonAssistanceContext(
            ownerId: 'owner-a',
            state: const LessonSessionState.planned(LessonMode.meaningQuiz),
            child: TextButton(
              onPressed: () => manualAnswers++,
              child: const Text('Manual answer'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Manual answer'));
      expect(manualAnswers, LessonMode.values.length + 1);
    },
  );
  testWidgets(
    'old owner and covered lesson cannot leak context; current changes refresh',
    (tester) async {
      var owner = 'owner-a';
      final registry = MenuActionRegistry(currentOwner: () => owner);
      final navigator = GlobalKey<NavigatorState>();
      Widget app(int count) => MenuActionScope(
        registry: registry,
        child: MaterialApp(
          navigatorKey: navigator,
          home: LessonAssistanceContext(
            ownerId: 'owner-a',
            state: LessonSessionState(
              mode: LessonMode.cloze,
              status: LessonSessionStatus.active,
              itemCount: 4,
              committedResponseCount: count,
            ),
            child: const Text('Lesson'),
          ),
        ),
      );
      await tester.pumpWidget(app(1));
      expect(registry.snapshot()['context'], hasLength(1));
      await tester.pumpWidget(app(2));
      expect(
        (registry.snapshot()['context'] as List).single['value'],
        contains('"committedResponses":2'),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('Covered')),
      );
      await tester.pumpAndSettle();
      expect(registry.snapshot()['context'], isEmpty);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(registry.snapshot()['context'], hasLength(1));
      owner = 'owner-b';
      expect(registry.snapshot()['context'], isEmpty);
      await tester.pumpWidget(app(2));
      expect(registry.snapshot()['context'], isEmpty);
    },
  );
}
