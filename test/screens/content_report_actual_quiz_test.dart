import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_button.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';

import '../support/authored_lexical_pack.dart';
import '../support/configured_quiz_harness.dart';
import '../support/content_report_caller_harness.dart';
import '../support/content_report_ui_io.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  for (final lexical in [false, true]) {
    testWidgets(
      'actual ${lexical ? 'authored definition' : 'meaning'} Quiz reports only source after answer ACK',
      (tester) async {
        final h = await motivationPresentationIo(
          tester,
          ContentReportCallerHarness.open,
          stage: 'quiz-report-fixture',
        );
        try {
          final initial = await motivationPresentationIo(
            tester,
            () => _start(h, lexical),
            stage: 'quiz-report-start',
          );
          final question = initial.plan.questions.first;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpWidget(
            h.app(
              QuizScreen(
                learning: h.learning,
                expectedOwnerId: configuredOwnerId,
                resumeSessionId: initial.sessionId,
              ),
            ),
          );
          await reportUiWait(
            tester,
            'quiz-question',
            () => find.text(question.prompt).evaluate().isNotEmpty,
          );
          expect(find.byType(ContentReportButton), findsNothing);
          expect(
            question.options.where(
              (option) => option != question.correctAnswer,
            ),
            isNotEmpty,
          );
          final wrong = question.options.firstWhere(
            (option) => option != question.correctAnswer,
          );
          await reportUiTap(
            tester,
            find.widgetWithText(FilledButton, wrong).first,
            'quiz-answer',
          );
          await reportUiReveal(
            tester,
            find.byType(ContentReportButton),
            'quiz-report-after-ACK',
            scrollable: find.byType(SingleChildScrollView),
          );
          await reportUiWait(
            tester,
            'quiz-answer-ACK',
            () => find.byType(ContentReportButton).evaluate().isNotEmpty,
          );
          expect(
            await motivationPresentationIo(
              tester,
              () => h.storage.count('answer_attempts'),
            ),
            1,
          );
          final before = await motivationPresentationIo(
            tester,
            h.storage.snapshot,
          );
          final button = find.descendant(
            of: find.byType(ContentReportButton),
            matching: find.byType(TextButton),
          );
          await reportUiTap(tester, button, 'quiz-report');
          if (lexical) {
            await reportUiTapKey(tester, 'content-report-selection-review');
            await reportUiTapKey(tester, 'content-report-reason:spelling');
            await reportUiTapKey(tester, 'content-report-review');
            await reportUiTapKey(tester, 'content-report-save');
          } else {
            await reportUiTapKey(tester, 'word-report-reason:spelling');
            await reportUiTapKey(tester, 'word-report-review');
            await reportUiTapKey(tester, 'word-report-confirm');
          }
          await reportUiWait(
            tester,
            'quiz-local-receipt',
            () => lexical
                ? find
                      .text('บันทึกในเครื่อง ยังไม่มีใบรับเรื่องจากเซิร์ฟเวอร์')
                      .evaluate()
                      .isNotEmpty
                : find
                      .byKey(const ValueKey('word-report-queued'))
                      .evaluate()
                      .isNotEmpty,
          );
          final rows = await motivationPresentationIo(
            tester,
            () => h.queue.watchOwner(configuredOwnerId).first,
          );
          final report = rows.single;
          expect(report.payload.target.text, isNot(contains(wrong)));
          expect(
            report.payload.reportJson,
            isNot(contains('selectedOptionOrdinal')),
          );
          expect(report.payload.reportJson, isNot(contains('evidenceContext')));
          final target =
              jsonDecode(report.payload.target.snapshotJson)
                  as Map<String, dynamic>;
          if (lexical) {
            final source = question.lexical!.source;
            expect(target['source'], {
              'packId': source.packId,
              'packVersion': source.version,
              'packageSha256': source.packageSha256,
              'entryCode': question.lexical!.target.entry.code,
              'entrySha256': question.lexical!.target.entry.contentSha256,
            });
          } else {
            expect(target.length, 9);
            expect(target['version'], 'owned-word-report-v1');
            expect(target['wordId'], question.word.id);
          }
          final after = await motivationPresentationIo(
            tester,
            h.storage.snapshot,
          );
          expect(_withoutReports(after), _withoutReports(before));
        } finally {
          await closeMotivationPresentation(tester, h.close);
        }
      },
    );
  }
}

Future<ConfiguredQuizState> _start(
  ContentReportCallerHarness h,
  bool lexical,
) async {
  final ConfiguredQuizLaunch launch;
  if (lexical) {
    final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
    await h.packs.importPack(
      h.packs.prepareImport(scope: scope, pack: authoredLexicalPack()),
    );
    final current = (await h.packs.captureOwner(stillCurrent: () => true))!;
    final pack = (await h.packs.list(current)).single;
    launch = await h.learning.prepareLexicalQuiz(
      expectedOwnerId: configuredOwnerId,
      packVersionId: pack.id,
      entryCodes: const ['cat', 'dog'],
      input: LexicalQuizInput.definitionChoice,
      limit: 1,
      stillCurrent: () => true,
    );
  } else {
    launch = await h.learning.prepareConfiguredQuiz(
      configuration: QuizConfiguration.category(
        categoryId: configuredCategoryId,
        limit: 4,
      ),
      expectedOwnerId: configuredOwnerId,
    );
  }
  return h.learning.startConfiguredQuiz(launch);
}

Map<String, List<String>> _withoutReports(Map<String, List<String>> rows) => {
  for (final entry in rows.entries)
    if (!['word_reports', 'content_reports'].contains(entry.key))
      entry.key: entry.value,
};
