import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_button.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_sheet.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning/presentation/native_exercise_checkpoint_binding.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'package:vocab_learning_app/widgets/word_report_sheet.dart';

import '../support/configured_quiz_harness.dart';
import '../support/content_report_caller_harness.dart';
import '../support/content_report_ui_io.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  for (final mode in [
    'dictation',
    'wordScramble',
    'cloze',
    'sentenceScramble',
  ]) {
    testWidgets(
      'actual $mode ACK reports its pinned source without learner response or new learning',
      (tester) async {
        final h = await motivationPresentationIo(
          tester,
          ContentReportCallerHarness.open,
          stage: '$mode-fixture',
        );
        try {
          final state = await _answered(tester, h, mode);
          final before = await motivationPresentationIo(
            tester,
            h.storage.snapshot,
            stage: '$mode-before',
          );
          await _mount(tester, h, state);
          final legacy = mode == 'dictation' || mode == 'wordScramble';
          final button = find.descendant(
            of: find.byType(ContentReportButton),
            matching: find.byType(TextButton),
          );
          await reportUiReveal(
            tester,
            button,
            '$mode-report',
            scrollable: find.byType(ListView),
          );
          await reportUiTap(tester, button, '$mode-report');
          if (legacy) {
            await reportUiTapKey(tester, 'word-report-reason:spelling');
            await reportUiTapKey(tester, 'word-report-review');
            await reportUiTapKey(tester, 'word-report-confirm');
          } else {
            await reportUiTapKey(tester, 'content-report-selection-review');
            await reportUiTapKey(tester, 'content-report-reason:spelling');
            await reportUiTapKey(tester, 'content-report-review');
            await reportUiTapKey(tester, 'content-report-save');
          }
          await reportUiWait(
            tester,
            '$mode-local-receipt',
            () => legacy
                ? find
                      .byKey(const ValueKey('word-report-queued'))
                      .evaluate()
                      .isNotEmpty
                : find
                      .text('บันทึกในเครื่อง ยังไม่มีใบรับเรื่องจากเซิร์ฟเวอร์')
                      .evaluate()
                      .isNotEmpty,
          );
          final rows = await motivationPresentationIo(
            tester,
            () => h.queue.watchOwner(configuredOwnerId).first,
            stage: '$mode-report-row',
          );
          final report = rows.single;
          expect(report.delivery, ContentReportDelivery.queued);
          expect(
            report.payload.reportJson,
            isNot(contains('privatelearnertext')),
          );
          final target =
              jsonDecode(report.payload.target.snapshotJson)
                  as Map<String, dynamic>;
          if (legacy) {
            expect(target.length, 9);
            expect(target['version'], 'owned-word-report-v1');
            expect(target['wordId'], state.exercise.word.id);
          } else {
            expect(target['kind'], 'aiOutput');
            final source = target['source'] as Map<String, dynamic>;
            expect(source['acceptedPlanId'], state.plan.id);
            expect(source['sessionId'], state.exercise.id);
            expect(source['modelVersion'], 'synthetic-accepted-model');
            expect(source['cached'], isTrue);
            expect(source['origin'], 'unrecorded');
            expect(target['text'], switch (state.exercise) {
              ClozeSession(:final content) => content.sentence,
              SentenceScrambleSession(:final content) => content.sentence,
              _ => throw StateError('Expected admitted AI content'),
            });
          }
          final after = await motivationPresentationIo(
            tester,
            h.storage.snapshot,
            stage: '$mode-after',
          );
          expect(_withoutReports(after), _withoutReports(before));
          final sheet = legacy
              ? find.byType(WordReportSheet)
              : find.byType(ContentReportSheet);
          Navigator.of(tester.element(sheet)).pop();
          await tester.pump(const Duration(milliseconds: 350));
          expect(find.textContaining('no longer available'), findsNothing);
          expect(find.byType(ContentReportButton), findsOneWidget);
        } finally {
          await closeMotivationPresentation(tester, h.close);
        }
      },
    );
  }
  for (final mode in ['dictation', 'cloze']) {
    testWidgets(
      'actual $mode Study context exposes no report action after ACK',
      (tester) async {
        final h = await motivationPresentationIo(
          tester,
          ContentReportCallerHarness.open,
          stage: '$mode-study-fixture',
        );
        try {
          final state = await _answered(tester, h, mode);
          await _mount(tester, h, state, study: true);
          expect(find.byType(ContentReportButton), findsNothing);
          expect(
            await motivationPresentationIo(
              tester,
              () => h.queue.watchOwner(configuredOwnerId).first,
            ),
            isEmpty,
          );
        } finally {
          await closeMotivationPresentation(tester, h.close);
        }
      },
    );
  }
}

Future<NativeExerciseState> _answered(
  WidgetTester tester,
  ContentReportCallerHarness h,
  String mode,
) => motivationPresentationIo(tester, () async {
  final exercise = switch (mode) {
    'dictation' => await h.learning.prepareDictation(stillCurrent: () => true),
    'wordScramble' => await h.learning.prepareWordScramble(
      stillCurrent: () => true,
    ),
    'cloze' => await h.learning.prepareCloze(
      variant: ClozeVariant.typed,
      stillCurrent: () => true,
    ),
    _ => await h.learning.prepareSentenceScramble(stillCurrent: () => true),
  };
  final binding = NativeExerciseCheckpointBinding(
    learning: h.learning,
    display: exercise!,
    stillCurrent: () => true,
  );
  await binding.initialize();
  return binding.saveAnswer(
    NativeExerciseDraft(text: 'privatelearnertext', responseTimeMs: 1000),
  );
}, stage: '$mode-actual-ACK');

Future<void> _mount(
  WidgetTester tester,
  ContentReportCallerHarness h,
  NativeExerciseState state, {
  bool study = false,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final screen = switch (state.exercise) {
    DictationSession exercise => DictationQuizScreen(
      session: exercise,
      learning: h.learning,
      resumeState: state,
      voice: VoiceUseCases(h.voice),
      learningTimeCallerContext: study
          ? LearningTimeCallerContext.researchControlled
          : LearningTimeCallerContext.ordinary,
    ),
    WordScrambleSession exercise => WordScrambleScreen(
      session: exercise,
      learning: h.learning,
      resumeState: state,
    ),
    ClozeSession exercise => FillInTheBlanksScreen(
      session: exercise,
      learning: h.learning,
      resumeState: state,
      learningTimeCallerContext: study
          ? LearningTimeCallerContext.researchControlled
          : LearningTimeCallerContext.ordinary,
    ),
    SentenceScrambleSession exercise => SentenceScrambleScreen(
      session: exercise,
      learning: h.learning,
      resumeState: state,
      voice: VoiceUseCases(h.voice),
    ),
  };
  await tester.pumpWidget(h.app(screen));
  final feedback = find.byKey(
    ValueKey(switch (state.exercise) {
      DictationSession() => 'dictation-feedback',
      WordScrambleSession() => 'scramble-feedback',
      ClozeSession() => 'cloze-feedback',
      _ => 'sentence-feedback',
    }),
  );
  for (var step = 0; step < 24 && feedback.evaluate().isEmpty; step++) {
    await motivationPresentationIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
      stage: 'native-restore-io',
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (feedback.evaluate().isNotEmpty) break;
    final list = find.byType(ListView);
    if (list.evaluate().isNotEmpty) {
      await tester.drag(list.first, const Offset(0, -180));
    }
    await tester.pump(const Duration(milliseconds: 80));
  }
  expect(
    feedback,
    findsOneWidget,
    reason: 'The real acknowledged feedback must be reached by user scrolling',
  );
}

Map<String, List<String>> _withoutReports(Map<String, List<String>> rows) => {
  for (final entry in rows.entries)
    if (!['word_reports', 'content_reports'].contains(entry.key))
      entry.key: entry.value,
};
