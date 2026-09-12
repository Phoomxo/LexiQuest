import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/contrastive_explanation.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/answer_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning/presentation/contrastive_feedback_panel.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';

import '../../support/r15_visual_capture.dart';

void main() {
  testWidgets('R15 actual feedback summary details and unavailable surfaces', (
    tester,
  ) async {
    await loadR15Fonts();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> pump(Widget child, {double scale = 1}) => tester.pumpWidget(
      MaterialApp(
        theme: M3Theme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('synthetic-r15-surface'),
          child: Scaffold(
            appBar: AppBar(title: const Text('ฝึกความหมาย')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('station', style: TextStyle(fontSize: 28)),
                const Text('เลือกคำที่หมายถึงสถานีรถไฟ'),
                const SizedBox(height: 16),
                child,
                const SizedBox(height: 16),
                FilledButton(onPressed: () {}, child: const Text('ข้อถัดไป')),
              ],
            ),
          ),
        ),
      ),
    );
    await pump(
      ContrastiveFeedbackPanel(
        explanation: ContrastiveExplanation.reviewed(
          manifestIdentity: const ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: 'synthetic-station',
            revision: 1,
          ),
          correctOptionId: 'station',
          selectedDistractorId: 'terminal',
          correctRationale:
              'A station is where trains stop. Example: meet at the station.',
          distractorRationale:
              'A terminal is an endpoint. It can refer to other transport too.',
        ),
      ),
    );
    await captureR15Surface(tester, 'r15-4-feedback-summary');
    await tester.tap(find.text('ดูรายละเอียด'));
    await captureR15Surface(tester, 'r15-4-feedback-details');
    await pump(
      AnswerFeedbackPanel(
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
      scale: 2,
    );
    await captureR15Surface(tester, 'r15-4-feedback-unavailable-200');
    await tester.ensureVisible(find.text('ข้อถัดไป'));
    expect(find.text('ข้อถัดไป').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
