import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
    'R15 long reviewed text has a bounded excerpt and complete details',
    (tester) async {
      final long = List.filled(60, 'reviewed ').join().trim();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContrastiveFeedbackPanel(
              explanation: ContrastiveExplanation.reviewed(
                manifestIdentity: _contrastiveIdentity,
                correctOptionId: 'station',
                selectedDistractorId: 'terminal',
                correctRationale: long,
                distractorRationale: 'An endpoint.',
              ),
            ),
          ),
        ),
      );
      expect(find.text(long), findsNothing);
      expect(find.text('${long.substring(0, 180)}…'), findsOneWidget);
      await tester.ensureVisible(find.text('ดูรายละเอียด'));
      await tester.tap(find.text('ดูรายละเอียด'));
      await tester.pump();
      expect(find.text(long), findsOneWidget);
    },
  );

  testWidgets('R15 explanation starts short and expands pinned details', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                const SizedBox(height: 100),
                ContrastiveFeedbackPanel(
                  explanation: ContrastiveExplanation.reviewed(
                    manifestIdentity: _contrastiveIdentity,
                    correctOptionId: 'option:station',
                    selectedDistractorId: 'option:terminal',
                    correctRationale:
                        'Trains stop here. Example: meet at the station.',
                    distractorRationale:
                        'Terminal means an endpoint. It is broader.',
                  ),
                ),
                const SizedBox(height: 800),
              ],
            ),
          ),
        ),
      ),
    );
    scroll.jumpTo(40);
    await tester.pump();
    expect(find.text('Trains stop here.'), findsOneWidget);
    expect(find.textContaining('Example:'), findsNothing);
    await tester.tap(find.text('ดูรายละเอียด'));
    await tester.pumpAndSettle();
    expect(
      find.text('Trains stop here. Example: meet at the station.'),
      findsOneWidget,
    );
    expect(scroll.offset, 40);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContrastiveFeedbackPanel(
            explanation: ContrastiveExplanation.reviewed(
              manifestIdentity: _contrastiveIdentity,
              correctOptionId: 'option:market',
              selectedDistractorId: 'option:terminal',
              correctRationale: 'Buy food here. New example.',
              distractorRationale: 'A terminal is an endpoint. Another detail.',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Buy food here.'), findsOneWidget);
    expect(find.textContaining('New example.'), findsNothing);
    expect(find.text('ดูรายละเอียด'), findsOneWidget);
  });

  testWidgets('R15 missing explanation remains explicit after commit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnswerFeedbackPanel(
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
      ),
    );
    expect(find.text('คำอธิบายยังไม่พร้อมสำหรับเนื้อหานี้'), findsOneWidget);
    expect(find.text('คำตอบที่ถูก: station'), findsOneWidget);
  });

  testWidgets(
    'Task5 feedback semantic bookmark and report retain committed identity',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        ContentIdentity? bookmarked;
        ContentIdentity? reported;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnswerFeedbackPanel(
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
                reportIdentity: _bookmarkIdentity,
                onReport:
                    ({required identity, required reason, comment}) async =>
                        reported = identity,
              ),
            ),
          ),
        );
        for (final label in ['บันทึกไว้ทบทวน', 'รายงานเนื้อหา']) {
          final node = tester.getSemantics(find.bySemanticsLabel(label));
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
          );
          node.owner!.performAction(node.id, SemanticsAction.tap);
          await tester.pumpAndSettle();
        }
        expect(bookmarked, _bookmarkIdentity);
        await tester.tap(find.text('ปัญหาคำตอบ'));
        await tester.pump();
        await tester.tap(find.text('ส่งรายงาน'));
        await tester.pumpAndSettle();
        expect(reported, _bookmarkIdentity);
      } finally {
        semantics.dispose();
      }
    },
  );
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
      expect(find.text('ถูกต้อง'), findsOneWidget);
      expect(find.text('คำตอบที่ถูก: station'), findsOneWidget);
      expect(find.text('ข้อถัดไป'), findsOneWidget);
      final semantics = tester.getSemantics(
        find.byKey(const ValueKey<String>('answer-feedback-panel')),
      );
      expect(semantics.label, 'ถูกต้อง คำตอบที่ถูก: station ข้อถัดไป');
      expect(semantics.flagsCollection.isLiveRegion, isTrue);

      await tester.tap(find.text('ข้อถัดไป'));
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
      expect(find.text('ยังไม่ถูก'), findsOneWidget);
      expect(find.text('คำตอบที่ถูก: station'), findsOneWidget);
      expect(find.text('ลองอีกครั้ง'), findsOneWidget);

      await tester.tap(find.text('ลองอีกครั้ง'));
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
    expect(find.text('ยังไม่ถูก'), findsOneWidget);
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

    await tester.tap(find.bySemanticsLabel('บันทึกไว้ทบทวน'));
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

    await tester.tap(find.bySemanticsLabel('รายงานเนื้อหา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปัญหาคำตอบ'));
    await tester.pump();
    await tester.tap(find.text('ส่งรายงาน'));
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

    expect(find.bySemanticsLabel('รายงานเนื้อหา'), findsNothing);
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
      expect(semantics.label, 'คำอธิบายเปรียบเทียบคำตอบ');
      expect(find.bySemanticsLabel('เหตุผลของคำตอบที่ถูก'), findsOneWidget);
      expect(
        find.bySemanticsLabel('A station is where trains stop.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('คำตอบที่เลือกต่างกันอย่างไร'),
        findsOneWidget,
      );
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
