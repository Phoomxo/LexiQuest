import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_button.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';

import '../support/configured_quiz_harness.dart';
import '../support/content_report_caller_harness.dart';
import '../support/content_report_ui_io.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  for (final study in [false, true]) {
    testWidgets(
      'actual ${study ? 'Study' : 'ordinary'} Tutor only offers the acknowledged assistant reply',
      (tester) async {
        final h = await motivationPresentationIo(
          tester,
          ContentReportCallerHarness.open,
          stage: 'tutor-fixture',
        );
        final tutor = ReportCallerTutor();
        try {
          await _mount(tester, h, tutor, study: study);
          await _reply(tester, tutor);
          if (study) {
            expect(find.byType(ContentReportButton), findsNothing);
            expect(
              await motivationPresentationIo(
                tester,
                () => h.queue.watchOwner(configuredOwnerId).first,
              ),
              isEmpty,
            );
            return;
          }
          await _open(tester);
          await reportUiTapKey(tester, 'content-report-selection-review');
          await reportUiTapKey(tester, 'content-report-reason:spelling');
          await reportUiTapKey(tester, 'content-report-review');
          await reportUiTapKey(tester, 'content-report-save');
          final rows = await motivationPresentationIo(
            tester,
            () => h.queue.watchOwner(configuredOwnerId).first,
            stage: 'tutor-stored',
          );
          final row = rows.single;
          expect(row.payload.target.text, tutor.replyText);
          expect(
            row.payload.reportJson,
            isNot(contains('PRIVATE learner prompt')),
          );
          final target =
              jsonDecode(row.payload.target.snapshotJson)
                  as Map<String, dynamic>;
          final source = target['source'] as Map<String, dynamic>;
          expect(source['replyId'], startsWith('tutor-reply:'));
          expect(source['modelVersion'], 'synthetic-tutor-model');
          expect(
            source['generatedAtUtcMs'],
            DateTime.utc(2026, 11, 1).millisecondsSinceEpoch,
          );
          expect(tutor.calls, 1);
        } finally {
          await closeMotivationPresentation(tester, h.close);
          await tutor.dispose();
        }
      },
    );
  }

  testWidgets(
    'actual Tutor dependency replacement retires a retained report button',
    (tester) async {
      final h = await motivationPresentationIo(
        tester,
        ContentReportCallerHarness.open,
        stage: 'tutor-retained-fixture',
      );
      final tutor = ReportCallerTutor();
      final dependencies = ValueNotifier(h.dependencies(tutor: tutor));
      try {
        await _mount(tester, h, tutor, dependencies: dependencies);
        await _reply(tester, tutor);
        final button = _button();
        await reportUiWait(
          tester,
          'tutor-report-ready',
          () =>
              button.evaluate().length == 1 &&
              tester.widget<TextButton>(button).onPressed != null,
        );
        final retained = tester.widget<TextButton>(button).onPressed!;
        dependencies.value = h.dependencies(tutor: tutor);
        await tester.pump();
        retained();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.byKey(const ValueKey('content-report-selection')),
          findsNothing,
        );
        expect(
          await motivationPresentationIo(
            tester,
            () => h.queue.watchOwner(configuredOwnerId).first,
          ),
          isEmpty,
        );
      } finally {
        await closeMotivationPresentation(tester, h.close);
        dependencies.dispose();
        await tutor.dispose();
      }
    },
  );
}

Future<void> _mount(
  WidgetTester tester,
  ContentReportCallerHarness h,
  ReportCallerTutor tutor, {
  bool study = false,
  ValueNotifier<AppDependencies>? dependencies,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    h.app(
      AiTutorScreen(
        geminiTutor: tutor,
        voice: VoiceUseCases(h.voice),
        timeCallerContext: study
            ? LearningTimeCallerContext.researchControlled
            : LearningTimeCallerContext.ordinary,
      ),
      tutor: tutor,
      dependencies: dependencies,
    ),
  );
  await reportUiWait(
    tester,
    'tutor-input',
    () => find.byKey(const ValueKey('ai-tutor-input')).evaluate().isNotEmpty,
  );
}

Future<void> _reply(WidgetTester tester, ReportCallerTutor tutor) async {
  await tester.enterText(
    find.byKey(const ValueKey('ai-tutor-input')),
    'PRIVATE learner prompt',
  );
  await reportUiWait(
    tester,
    'tutor-ready',
    () => tester
        .widget<Text>(find.byKey(const ValueKey('ai-tutor-key-status')))
        .data!
        .startsWith('ระบบจะส่ง'),
  );
  await reportUiTapKey(tester, 'ai-tutor-send');
  await reportUiWait(
    tester,
    'tutor-reply',
    () => find.text(tutor.replyText).evaluate().isNotEmpty,
  );
}

Finder _button() => find.descendant(
  of: find.byType(ContentReportButton),
  matching: find.byType(TextButton),
);
Future<void> _open(WidgetTester tester) =>
    reportUiTap(tester, _button(), 'tutor-report');
