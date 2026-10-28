import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/contrastive_explanation.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning/presentation/contrastive_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
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

  testWidgets('report action carries only the committed content revision', (
    tester,
  ) async {
    ContentIdentity? reportedIdentity;
    ContentReportReason? reportedReason;
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
        reportIdentity: _bookmarkIdentity,
        onReport: ({required identity, required reason, comment}) async {
          reportedIdentity = identity;
          reportedReason = reason;
        },
      ),
    );

    await tester.tap(find.bySemanticsLabel('Report content'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Answer problem'));
    await tester.pump();
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(reportedIdentity, _bookmarkIdentity);
    expect(reportedReason, ContentReportReason.answer);
  });

  testWidgets('report action is hidden without a committed content identity', (
    tester,
  ) async {
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
        onReport: ({required identity, required reason, comment}) async {},
      ),
    );

    expect(find.bySemanticsLabel('Report content'), findsNothing);
  });

  testWidgets(
    'renders reviewed contrastive feedback with non-color semantics and no motion',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(2),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: ContrastiveFeedbackPanel(
                explanation: ContrastiveExplanation.reviewed(
                  manifestIdentity: _contrastiveIdentity,
                  correctOptionId: 'option:station',
                  selectedDistractorId: 'option:terminal',
                  correctRationale: 'A station is where trains stop.',
                  distractorRationale:
                      'A terminal is broader than the requested train stop.',
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ContrastiveFeedbackPanel), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
      expect(find.byIcon(Icons.compare_arrows), findsOneWidget);
      expect(find.byType(AnimatedSwitcher), findsNothing);
      final semantics = tester.getSemantics(
        find.byKey(const ValueKey<String>('contrastive-feedback-panel')),
      );
      expect(semantics.label, 'Contrastive feedback');
      expect(
        find.bySemanticsLabel('Why the correct answer works'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('A station is where trains stop.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Why your choice differs'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'A terminal is broader than the requested train stop.',
        ),
        findsOneWidget,
      );
      semanticsHandle.dispose();
    },
  );

  testWidgets(
    'hides contrastive feedback when no reviewed rationale resolved',
    (tester) async {
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
        ),
      );

      expect(find.byType(ContrastiveFeedbackPanel), findsNothing);
    },
  );
}

const _bookmarkIdentity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:station',
  revision: 4,
);

const _contrastiveIdentity = ContentIdentity(
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
    this.reportIdentity,
    this.onReport,
  });

  final AnswerFeedback feedback;
  final VoidCallback? onRetry;
  final VoidCallback? onNext;
  final ContentIdentity? bookmarkIdentity;
  final BookmarkLearningItemAction? onBookmark;
  final ContentIdentity? reportIdentity;
  final ReportContentAction? onReport;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: AnswerFeedbackPanel(
        feedback: feedback,
        onRetry: onRetry,
        onNext: onNext,
        bookmarkIdentity: bookmarkIdentity,
        onBookmark: onBookmark,
        reportIdentity: reportIdentity,
        onReport: onReport,
      ),
    ),
  );
}
