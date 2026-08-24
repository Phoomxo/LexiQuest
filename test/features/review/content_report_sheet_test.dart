import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/presentation/content_report_sheet.dart';

void main() {
  testWidgets(
    'requires one exact reason and submits a trimmed optional comment',
    (tester) async {
      ContentReportReason? submittedReason;
      String? submittedComment;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentReportSheet(
              identity: _identity,
              onSubmit: ({required reason, comment}) async {
                submittedReason = reason;
                submittedComment = comment;
              },
            ),
          ),
        ),
      );

      expect(find.text('Report content'), findsOneWidget);
      expect(find.text('Revision 4'), findsOneWidget);
      expect(find.text('Text problem'), findsOneWidget);
      expect(find.text('Audio problem'), findsOneWidget);
      expect(find.text('Answer problem'), findsOneWidget);
      expect(find.text('Explanation problem'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Submit report'),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Audio problem'));
      await tester.enterText(
        find.byType(TextField),
        '  Pronunciation is unclear  ',
      );
      await tester.tap(find.text('Submit report'));
      await tester.pump();

      expect(submittedReason, ContentReportReason.audio);
      expect(submittedComment, 'Pronunciation is unclear');
    },
  );

  testWidgets('empty comment becomes null and submission is single-flight', (
    tester,
  ) async {
    var calls = 0;
    final release = Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentReportSheet(
            identity: _identity,
            onSubmit: ({required reason, comment}) async {
              calls += 1;
              expect(reason, ContentReportReason.answer);
              expect(comment, isNull);
              await release;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Answer problem'));
    await tester.pump();
    await tester.tap(find.text('Submit report'));
    await tester.tap(find.text('Submit report'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 25));

    expect(calls, 1);
  });

  testWidgets('overlong Unicode comment fails closed without invoking submit', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentReportSheet(
            identity: _identity,
            onSubmit: ({required reason, comment}) async => calls += 1,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Explanation problem'));
    await tester.enterText(
      find.byType(TextField),
      List<String>.filled(ContentQualityReport.maxCommentRunes + 1, 'ก').join(),
    );
    await tester.tap(find.text('Submit report'));
    await tester.pump();

    expect(find.text('Comment is too long'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('exposes an accessible close action without submitting', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContentReportSheet(
            identity: _identity,
            onSubmit: ({required reason, comment}) async => calls += 1,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Close content report'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close content report'));
    await tester.pump();
    expect(calls, 0);
  });
}

const _identity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:station',
  revision: 4,
);
