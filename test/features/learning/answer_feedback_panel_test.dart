import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent.dart';

void main() {
  testWidgets(
    'announces a correct committed answer with a non-color cue and next action',
    (tester) async {
      var nextPressed = false;
      final semanticsHandle = tester.ensureSemantics();

      await tester.pumpWidget(
        _FeedbackHarness(
          feedback: AnswerFeedback.fromCommittedResult(
            result: const AnswerRecordResult(
              inserted: true,
              isCorrect: true,
              srs: null,
            ),
            context: const AnswerFeedbackContext(
              canonicalCorrectAnswer: 'station',
            ),
          ),
          onNext: () => nextPressed = true,
        ),
      );

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Correct answer: station'), findsOneWidget);
      expect(find.text('Next question'), findsOneWidget);
      final semantics = tester.getSemantics(
        find.byKey(const ValueKey<String>('answer-feedback-panel')),
      );
      expect(
        semantics.label,
        'Correct. Correct answer: station. Next question.',
      );
      expect(semantics.flagsCollection.isLiveRegion, isTrue);

      await tester.tap(find.text('Next question'));
      expect(nextPressed, isTrue);
      semanticsHandle.dispose();
    },
  );

  testWidgets(
    'announces an incorrect committed answer with a non-color cue and retry action',
    (tester) async {
      var retryPressed = false;

      await tester.pumpWidget(
        _FeedbackHarness(
          feedback: AnswerFeedback.fromCommittedResult(
            result: const AnswerRecordResult(
              inserted: true,
              isCorrect: false,
              srs: null,
            ),
            context: const AnswerFeedbackContext(
              canonicalCorrectAnswer: 'station',
            ),
          ),
          onRetry: () => retryPressed = true,
        ),
      );

      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.text('Not quite'), findsOneWidget);
      expect(find.text('Correct answer: station'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      expect(retryPressed, isTrue);
    },
  );

  testWidgets('uses the same static feedback panel when motion is reduced', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _FeedbackHarness(
          feedback: AnswerFeedback.fromCommittedResult(
            result: const AnswerRecordResult(
              inserted: true,
              isCorrect: false,
              srs: null,
            ),
            context: const AnswerFeedbackContext(
              canonicalCorrectAnswer: 'station',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AnswerFeedbackPanel), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.text('Not quite'), findsOneWidget);
  });

  testWidgets('bookmark action carries the answered content revision', (
    tester,
  ) async {
    ContentIdentity? bookmarked;
    await tester.pumpWidget(
      _FeedbackHarness(
        feedback: AnswerFeedback.fromCommittedResult(
          result: const AnswerRecordResult(
            inserted: true,
            isCorrect: false,
            srs: null,
          ),
          context: const AnswerFeedbackContext(
            canonicalCorrectAnswer: 'station',
          ),
        ),
        bookmarkIdentity: _bookmarkIdentity,
        onBookmark: (identity) async => bookmarked = identity,
      ),
    );

    await tester.tap(find.bySemanticsLabel('Save for review'));
    await tester.pump();
    expect(bookmarked, _bookmarkIdentity);
  });
}

const _bookmarkIdentity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:station',
  revision: 4,
);

final class _FeedbackHarness extends StatelessWidget {
  const _FeedbackHarness({
    required this.feedback,
    this.onRetry,
    this.onNext,
    this.bookmarkIdentity,
    this.onBookmark,
  });

  final AnswerFeedback feedback;
  final VoidCallback? onRetry;
  final VoidCallback? onNext;
  final ContentIdentity? bookmarkIdentity;
  final BookmarkLearningItemAction? onBookmark;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: AnswerFeedbackPanel(
        feedback: feedback,
        onRetry: onRetry,
        onNext: onNext,
        bookmarkIdentity: bookmarkIdentity,
        onBookmark: onBookmark,
      ),
    ),
  );
}
