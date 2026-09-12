import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/presentation/content_report_sheet.dart';

void main() {
  testWidgets(
    'Task5 report close semantics dismisses only when submission is idle',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final pending = Completer<void>();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ContentReportSheet(
                      identity: _identity,
                      onSubmit: ({required reason, comment}) => pending.future,
                    ),
                  ),
                  child: const Text('open report'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open report'));
        await tester.pumpAndSettle();
        var close = tester.getSemantics(
          find.bySemanticsLabel('ปิดการรายงานเนื้อหา'),
        );
        expect(close.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        close.owner!.performAction(close.id, SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(find.byType(ContentReportSheet), findsNothing);
        await tester.tap(find.text('open report'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ปัญหาคำตอบ'));
        await tester.pump();
        await tester.tap(find.text('ส่งรายงาน'));
        await tester.pump();
        close = tester.getSemantics(
          find.bySemanticsLabel('ปิดการรายงานเนื้อหา'),
        );
        expect(
          close.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
        );
        close.owner!.performAction(close.id, SemanticsAction.tap);
        await tester.pump();
        expect(find.byType(ContentReportSheet), findsOneWidget);
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.byType(ContentReportSheet), findsNothing);
      } finally {
        if (!pending.isCompleted) pending.complete();
        semantics.dispose();
      }
    },
  );
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

      expect(find.text('รายงานเนื้อหา'), findsOneWidget);
      expect(find.text('รุ่น 4'), findsOneWidget);
      expect(find.text('ปัญหาข้อความ'), findsOneWidget);
      expect(find.text('ปัญหาเสียง'), findsOneWidget);
      expect(find.text('ปัญหาคำตอบ'), findsOneWidget);
      expect(find.text('ปัญหาคำอธิบาย'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'ส่งรายงาน'),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('ปัญหาเสียง'));
      await tester.enterText(
        find.byType(TextField),
        '  Pronunciation is unclear  ',
      );
      await tester.tap(find.text('ส่งรายงาน'));
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

    await tester.tap(find.text('ปัญหาคำตอบ'));
    await tester.pump();
    await tester.tap(find.text('ส่งรายงาน'));
    await tester.tap(find.text('ส่งรายงาน'), warnIfMissed: false);
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
    await tester.tap(find.text('ปัญหาคำอธิบาย'));
    await tester.enterText(
      find.byType(TextField),
      List<String>.filled(ContentQualityReport.maxCommentRunes + 1, 'ก').join(),
    );
    await tester.tap(find.text('ส่งรายงาน'));
    await tester.pump();

    expect(find.text('ความคิดเห็นยาวเกินกำหนด'), findsOneWidget);
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

    expect(find.bySemanticsLabel('ปิดการรายงานเนื้อหา'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('ปิดการรายงานเนื้อหา'));
    await tester.pump();
    expect(calls, 0);
  });
}

const _identity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:station',
  revision: 4,
);
