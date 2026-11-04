import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_button.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_sheet.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/bundled_starter_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning/presentation/native_exercise_checkpoint_binding.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
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
  for (final mode in ['cloze', 'sentenceScramble']) {
    testWidgets('authored $mode reports its pack entry', (tester) async {
      final h = await motivationPresentationIo(
        tester,
        ContentReportCallerHarness.open,
        stage: 'authored-report-fixture',
      );
      try {
        final result = await motivationPresentationIo(tester, () async {
          final scope = (await h.packs.captureOwner(stillCurrent: () => true))!;
          final pack = await h.packs.importPack(
            h.packs.prepareImport(scope: scope, pack: bundledStarterPack),
          );
          final reader = DriftLearningPackRepository(
            database: h.storage.database,
            ownerWrites: h.storage.ownerWrites,
          );
          var sequence = 0;
          final learning = LearningUseCases(
            owners: h.storage.owners,
            repository: DriftLearningRepository(
              h.storage.database,
              ownerWrites: h.storage.ownerWrites,
              lexicalContent: reader,
            ),
            generateId: () => 'authored-report-${++sequence}',
            nowUtc: () => h.storage.now,
            buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
          );
          final exercise = mode == 'cloze'
              ? await learning.prepareCloze(
                  categoryId: pack.categoryId,
                  variant: ClozeVariant.typed,
                  stillCurrent: () => true,
                )
              : await learning.prepareSentenceScramble(
                  categoryId: pack.categoryId,
                  stillCurrent: () => true,
                );
          final binding = NativeExerciseCheckpointBinding(
            learning: learning,
            display: exercise!,
            stillCurrent: () => true,
          );
          await binding.initialize();
          final state = await binding.saveAnswer(
            NativeExerciseDraft(
              text: 'privatelearnertext',
              responseTimeMs: 1000,
            ),
          );
          return (learning, state);
        }, stage: 'authored-report-ack');
        await _mount(tester, h, result.$2, learning: result.$1);
        final button = find.descendant(
          of: find.byType(ContentReportButton),
          matching: find.byType(TextButton),
        );
        await reportUiReveal(
          tester,
          button,
          'authored-report-open',
          scrollable: find.byType(ListView),
        );
        await reportUiTap(tester, button, 'authored-report-open');
        await reportUiTapKey(tester, 'content-report-selection-review');
        await reportUiTapKey(tester, 'content-report-reason:spelling');
        await reportUiTapKey(tester, 'content-report-review');
        await reportUiTapKey(tester, 'content-report-save');
        await reportUiWait(
          tester,
          'authored-report-receipt',
          () => find
              .text('บันทึกในเครื่อง ยังไม่มีใบรับเรื่องจากเซิร์ฟเวอร์')
              .evaluate()
              .isNotEmpty,
        );
        final rows = await motivationPresentationIo(
          tester,
          () => h.queue.watchOwner(configuredOwnerId).first,
          stage: 'authored-report-row',
        );
        final target =
            jsonDecode(rows.single.payload.target.snapshotJson)
                as Map<String, dynamic>;
        expect(target['kind'], 'packEntry');
        expect(
          (target['source'] as Map<String, dynamic>)['packId'],
          bundledStarterPack.manifest.packId,
        );
        expect(
          rows.single.payload.reportJson,
          isNot(contains('privatelearnertext')),
        );
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    });
  }
  testWidgets(
    'actual owned-word report survives a harmless sheet route update',
    (tester) async {
      final h = await motivationPresentationIo(
        tester,
        ContentReportCallerHarness.open,
        stage: 'word-report-route-fixture',
      );
      try {
        final state = await _answered(tester, h, 'dictation');
        final before = await motivationPresentationIo(
          tester,
          h.storage.snapshot,
          stage: 'word-report-route-before',
        );
        expect(
          identical(
            h.progress.watchActiveOwnerId(),
            h.progress.watchActiveOwnerId(),
          ),
          isFalse,
        );
        await _mount(tester, h, state);
        final dependencies = tester
            .widget<AppDependenciesScope>(find.byType(AppDependenciesScope))
            .dependencies;
        final button = find.descendant(
          of: find.byType(ContentReportButton),
          matching: find.byType(TextButton),
        );
        await reportUiReveal(
          tester,
          button,
          'word-report-route-open',
          scrollable: find.byType(ListView),
        );
        await reportUiTap(tester, button, 'word-report-route-open');
        await reportUiTapKey(tester, 'word-report-reason:spelling');
        const comment = 'synthetic reviewed spelling issue after route update';
        await tester.enterText(
          find.byKey(const ValueKey('word-report-comment')),
          comment,
        );
        await motivationPresentationDeadline(
          tester,
          'report-comment-layout',
          () => tester.pumpAndSettle(),
        );
        await reportUiTapKey(tester, 'word-report-review');
        final sheet = find.byType(WordReportSheet);
        final target = tester.widget<WordReportSheet>(sheet).target;
        final beforeRouteUpdate = await motivationPresentationIo(
          tester,
          h.storage.snapshot,
          stage: 'word-report-route-reviewed',
        );
        expect(beforeRouteUpdate['word_reports'], isEmpty);
        expect(beforeRouteUpdate['content_reports'], isEmpty);
        final route = ModalRoute.of(tester.element(sheet))!;
        route.changedExternalState();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));

        expect(
          tester
              .widget<AppDependenciesScope>(find.byType(AppDependenciesScope))
              .dependencies,
          same(dependencies),
        );
        expect(
          tester.widget<WordReportSheet>(sheet).target.sameTarget(target),
          isTrue,
        );
        expect(
          await motivationPresentationIo(
            tester,
            () => h.progress.watchActiveOwnerId().first,
            stage: 'word-report-route-owner',
          ),
          configuredOwnerId,
        );
        expect(
          await motivationPresentationIo(
            tester,
            h.storage.snapshot,
            stage: 'word-report-route-no-write',
          ),
          beforeRouteUpdate,
        );
        expect(find.text(comment), findsOneWidget);
        expect(
          find.byKey(const ValueKey('word-report-confirm')),
          findsOneWidget,
        );
        expect(
          find.text('รายงานนี้ไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่'),
          findsNothing,
        );
        await reportUiTapKey(tester, 'word-report-confirm');
        await reportUiWait(
          tester,
          'word-report-route-receipt',
          () => find
              .byKey(const ValueKey('word-report-queued'))
              .evaluate()
              .isNotEmpty,
        );
        final rows = await motivationPresentationIo(
          tester,
          () => h.queue.watchOwner(configuredOwnerId).first,
          stage: 'word-report-route-row',
        );
        final report = rows.single;
        expect(report.ownerId, configuredOwnerId);
        expect(report.payload.target.snapshotJson, target.snapshotJson);
        expect(report.payload.comment, comment);
        expect(
          report.payload.reportJson,
          isNot(contains('privatelearnertext')),
        );
        final after = await motivationPresentationIo(
          tester,
          h.storage.snapshot,
          stage: 'word-report-route-after',
        );
        expect(after['word_reports'], hasLength(1));
        expect(after['content_reports'], hasLength(1));
        expect(_withoutReports(after), _withoutReports(before));
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );
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
  LearningUseCases? learning,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final screen = switch (state.exercise) {
    DictationSession exercise => DictationQuizScreen(
      session: exercise,
      learning: learning ?? h.learning,
      resumeState: state,
      voice: VoiceUseCases(h.voice),
      learningTimeCallerContext: study
          ? LearningTimeCallerContext.researchControlled
          : LearningTimeCallerContext.ordinary,
    ),
    WordScrambleSession exercise => WordScrambleScreen(
      session: exercise,
      learning: learning ?? h.learning,
      resumeState: state,
    ),
    ClozeSession exercise => FillInTheBlanksScreen(
      session: exercise,
      learning: learning ?? h.learning,
      resumeState: state,
      learningTimeCallerContext: study
          ? LearningTimeCallerContext.researchControlled
          : LearningTimeCallerContext.ordinary,
    ),
    SentenceScrambleSession exercise => SentenceScrambleScreen(
      session: exercise,
      learning: learning ?? h.learning,
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
