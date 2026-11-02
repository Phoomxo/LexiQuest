import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/learning_packs/data/http_learning_pack_source.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/lexical_quiz_setup_dialog.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/widgets/word_report_sheet.dart';

import '../support/motivation_presentation_io.dart';
import '../support/populated_owner_migration_fixture.dart';
import 'learning_pack_test_support.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'included starter previews without network or writes before explicit install',
    (tester) async {
      final h = (await tester.runAsync(LearningPackUiHarness.open))!;
      var requests = 0;
      final downloads = HttpLearningPackSource(
        client: MockClient((request) async {
          requests++;
          throw TestFailure('Included content must not request a network URL.');
        }),
        catalog: const [],
      );
      try {
        final before = await tester.runAsync(
          () => ownerMigrationRows(h.database),
        );
        await tester.pumpWidget(h.app(downloads: downloads));
        await packUiReady(tester);
        final starter = find.byKey(const ValueKey('pack-open-starter'));
        expect(starter, findsOneWidget);
        expect(
          await tester.runAsync(() => ownerMigrationRows(h.database)),
          before,
        );
        await tapPackUi(tester, 'pack-open-starter');
        await untilPackUi(
          tester,
          () => find
              .byKey(const ValueKey('pack-confirm-install'))
              .evaluate()
              .isNotEmpty,
        );
        expect(requests, 0);
        expect(
          await tester.runAsync(() => ownerMigrationRows(h.database)),
          before,
        );
        expect(find.textContaining('AI-assisted'), findsWidgets);
        await tapPackUi(tester, 'pack-confirm-install');
        await untilPackUi(
          tester,
          () => find.text('ติดตั้งแพ็กบทเรียนแล้ว').evaluate().isNotEmpty,
        );
        expect(
          await tester.runAsync(() => h.count('learning_pack_versions')),
          1,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 12);
        expect(
          await tester.runAsync(() => h.count('lexical_content_snapshots')),
          12,
        );
        expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
        expect(requests, 0);
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        downloads.dispose();
        await closePackUi(tester, h);
      }
    },
  );

  testWidgets(
    'included starter participates in search and declared-level filter purely',
    (tester) => _using(tester, (h) async {
      final before = await tester.runAsync(
        () => ownerMigrationRows(h.database),
      );
      await tester.pumpWidget(h.app());
      await packUiReady(tester);
      final search = find.byKey(const ValueKey('pack-search'));
      await tester.enterText(search, 'no starter matches this');
      await tester.pump();
      expect(find.byKey(const ValueKey('pack-open-starter')), findsNothing);
      await tester.enterText(search, 'LexiQuest');
      await tester.pump();
      await revealPackUi(tester, 'pack-open-starter');
      final filter = find.byKey(const ValueKey('pack-cefr'));
      await tester.ensureVisible(filter);
      await tester.tap(filter);
      await untilPackUi(
        tester,
        () => find.text('A2').hitTestable().evaluate().isNotEmpty,
      );
      await tester.tap(find.text('A2').last);
      await untilPackUi(
        tester,
        () =>
            find.text('A2').evaluate().length == 1 &&
            find.byKey(const ValueKey('pack-open-starter')).evaluate().isEmpty,
      );
      expect(find.byKey(const ValueKey('pack-open-starter')), findsNothing);
      await tester.tap(filter);
      await untilPackUi(
        tester,
        () => find.text('A1').hitTestable().evaluate().isNotEmpty,
      );
      await tester.tap(find.text('A1').last);
      await untilPackUi(
        tester,
        () =>
            find.text('A1').evaluate().length == 1 &&
            find
                .byKey(const ValueKey('pack-open-starter'))
                .evaluate()
                .isNotEmpty,
      );
      await revealPackUi(tester, 'pack-open-starter');
      expect(
        await motivationPresentationIo(
          tester,
          () => ownerMigrationRows(h.database),
          stage: 'starter-filter/final-snapshot',
        ),
        before,
      );
    }),
  );

  testWidgets(
    'opening the included starter without an owner creates no account or rows',
    (tester) => _using(tester, (h) async {
      await tester.runAsync(
        () => h.database.delete(h.database.localOwners).go(),
      );
      final before = await tester.runAsync(
        () => ownerMigrationRows(h.database),
      );
      await tester.pumpWidget(h.app());
      await packUiReady(tester);
      await tapPackUi(tester, 'pack-open-starter');
      await idlePackUi(tester);
      expect(find.byKey(const ValueKey('pack-confirm-install')), findsNothing);
      expect(
        await tester.runAsync(() => ownerMigrationRows(h.database)),
        before,
      );
      expect(await tester.runAsync(() => h.count('local_owners')), 0);
    }),
  );

  testWidgets(
    'included cache-only action adds no words before explicit installation',
    (tester) => _using(tester, (h) async {
      await tester.pumpWidget(h.app());
      await _openPreview(tester);
      await tapPackUi(tester, 'pack-cache-preview');
      await idlePackUi(tester);
      expect(await tester.runAsync(() => h.count('learning_pack_versions')), 1);
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
      expect(
        await tester.runAsync(() => h.count('lexical_content_snapshots')),
        0,
      );
      final cached = (await tester.runAsync(h.stored))!;
      expect(cached.source.kind, 'configuredCatalog');
      expect(cached.source.catalogId, 'lexiquest.starter.en-th.1');
      expect(cached.isInstalled, isFalse);
      await tapPackUi(tester, 'pack-install-cached');
      await idlePackUi(tester);
      final installed = (await tester.runAsync(h.stored))!;
      expect(installed.id, cached.id);
      expect(installed.isInstalled, isTrue);
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 12);
      expect(
        await tester.runAsync(() => h.count('lexical_content_snapshots')),
        12,
      );
      expect(await tester.runAsync(() => h.count('answer_attempts')), 0);
    }),
  );

  for (final invalidation in ['owner ABA', 'background', 'covered route']) {
    testWidgets(
      'included preview refuses retained installation after $invalidation',
      (tester) => _using(tester, (h) async {
        await tester.pumpWidget(h.app());
        await _openPreview(tester);
        final retained = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('pack-confirm-install')),
            )
            .onPressed!;
        final before = await tester.runAsync(
          () => ownerMigrationRows(h.database),
        );
        if (invalidation == 'owner ABA') {
          await tester.runAsync(() async {
            await h.switchOwner('synthetic-actions-other');
            await h.switchOwner('synthetic-actions-owner');
          });
          await packUiReady(tester);
        } else if (invalidation == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          retained();
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await packUiReady(tester);
        } else {
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          unawaited(
            navigator.push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Synthetic cover')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        retained();
        await tester.pump();
        expect(
          await tester.runAsync(() => ownerMigrationRows(h.database)),
          before,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
      }),
    );
  }

  for (final input in LexicalQuizInput.values) {
    testWidgets(
      'included pack launches actual ${input.name} and canonical Score',
      (tester) => _using(tester, (h) async {
        await tester.pumpWidget(h.app());
        await _installStarter(tester);
        await _finishDefinition(tester, h, input);
        expect(await tester.runAsync(() => h.count('answer_attempts')), 2);
        final installed = (await tester.runAsync(h.stored))!;
        final beforeReturn = await motivationPresentationIo(
          tester,
          () => ownerMigrationRows(h.database),
          stage: 'starter-${input.name}/before-score-return',
        );
        tester.view.physicalSize = const Size(820, 620);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pump();
        final quiz = find.byType(QuizScreen, skipOffstage: false);
        expect(quiz, findsOneWidget);
        final practiceRoute = ModalRoute.of(tester.element(quiz))!;
        expect(practiceRoute.isCurrent, isFalse);
        practiceRoute.changedExternalState();
        await tester.pump();
        final back = find.widgetWithText(OutlinedButton, 'กลับไปเลือกกิจกรรม');
        await tester.ensureVisible(back);
        await tester.pump();
        expect(back.hitTestable(), findsOneWidget);
        await tester.tap(back.hitTestable());
        await untilPackUi(
          tester,
          () => find.byTooltip('กลับไปยังรายการแพ็ก').evaluate().isNotEmpty,
        );
        await idlePackUi(tester);
        expect(find.text(installed.manifest.title), findsOneWidget);
        expect(find.byType(QuizScreen), findsNothing);
        expect(find.byType(ScoreScreen), findsNothing);
        expect(
          find.text('การฝึกไม่พร้อมใช้งาน โปรดเปิดแพ็กใหม่'),
          findsNothing,
        );
        await revealPackUi(tester, 'pack-definition-0');
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('pack-definition-0')),
              )
              .onPressed,
          isNotNull,
        );
        await revealPackUi(tester, 'pack-practice-0');
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('pack-practice-0')),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          await motivationPresentationIo(
            tester,
            () => ownerMigrationRows(h.database),
            stage: 'starter-${input.name}/after-score-return',
          ),
          beforeReturn,
        );
        expect((await tester.runAsync(h.stored))!.id, installed.id);
      }),
    );
  }

  for (final invalidation in ['foreign cover', 'owner ABA']) {
    testWidgets(
      'included Score cannot revive its old Quiz after $invalidation',
      (tester) => _using(tester, (h) async {
        await tester.pumpWidget(h.app());
        await _installStarter(tester);
        await _finishDefinition(tester, h, LexicalQuizInput.definitionChoice);
        final practiceRoute = ModalRoute.of(
          tester.element(find.byType(QuizScreen, skipOffstage: false)),
        )!;
        final scoreRoute = ModalRoute.of(
          tester.element(find.byType(ScoreScreen)),
        )!;
        Finder exit;
        if (invalidation == 'foreign cover') {
          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          final foreign = MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close synthetic Score cover'),
                ),
              ),
            ),
          );
          unawaited(navigator.push<void>(foreign));
          await untilPackUi(
            tester,
            () =>
                find.text('Close synthetic Score cover').evaluate().isNotEmpty,
          );
          practiceRoute.changedExternalState();
          await tester.pump();
          navigator.removeRoute(scoreRoute);
          await tester.pump();
          expect(foreign.isCurrent, isTrue);
          exit = find.text('Close synthetic Score cover');
        } else {
          await motivationPresentationIo(
            tester,
            () => h.switchOwner('synthetic-actions-other'),
            stage: 'starter-score/owner-B',
          );
          await untilPackUi(
            tester,
            () => find
                .text('บัญชีเปลี่ยนแล้ว กรุณากลับไปเลือกกิจกรรม')
                .evaluate()
                .isNotEmpty,
          );
          await motivationPresentationIo(
            tester,
            () => h.switchOwner('synthetic-actions-owner'),
            stage: 'starter-score/owner-A',
          );
          practiceRoute.changedExternalState();
          await tester.pump();
          exit = find.text('กลับไปเลือกกิจกรรม');
        }
        final beforeReturn = await motivationPresentationIo(
          tester,
          () => ownerMigrationRows(h.database),
          stage: 'starter-score/$invalidation/before-return',
        );
        expect(await tester.runAsync(() => h.count('answer_attempts')), 2);
        expect(await tester.runAsync(() => h.count('learning_sessions')), 1);
        await tester.ensureVisible(exit);
        await tester.pump();
        expect(exit.hitTestable(), findsOneWidget);
        await tester.tap(exit.hitTestable());
        await tester.pump();
        if (invalidation == 'foreign cover') {
          practiceRoute.changedExternalState();
          await tester.pump();
        }
        expect(find.byType(QuizScreen, skipOffstage: false), findsNothing);
        expect(find.byType(ScoreScreen, skipOffstage: false), findsNothing);
        expect(
          await motivationPresentationIo(
            tester,
            () => ownerMigrationRows(h.database),
            stage: 'starter-score/$invalidation/after-return',
          ),
          beforeReturn,
        );
      }),
    );
  }

  testWidgets(
    'included pack starts a real twelve-card SRS deck and saves its first rating',
    (tester) => _using(tester, (h) async {
      await tester.pumpWidget(h.app());
      await _installStarter(tester);
      await tapPackUi(tester, 'pack-practice-0');
      await untilPackUi(
        tester,
        () => find.byKey(const ValueKey('srs-card')).evaluate().isNotEmpty,
      );
      expect(find.byType(SnackBar), findsNothing);
      final screen = tester.widget<SrsFlashcardsScreen>(
        find.byType(SrsFlashcardsScreen),
      );
      expect(screen.sourceWordIds, hasLength(12));
      expect(screen.expectedOwnerId, 'synthetic-actions-owner');
      final practiceRoute = ModalRoute.of(
        tester.element(find.byType(SrsFlashcardsScreen)),
      )!;
      expect(practiceRoute.isCurrent, isTrue);
      practiceRoute.changedExternalState();
      await tester.pump();
      expect(find.text('กิจกรรมไม่พร้อมใช้งาน'), findsNothing);
      await tapPackUi(tester, 'srs-flip');
      await tester.pump(const Duration(milliseconds: 450));
      await tapPackUi(tester, 'srs-got');
      await untilPackUi(
        tester,
        () => find.byKey(const ValueKey('srs-next')).evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(() => h.count('answer_attempts')), 1);
      expect(await tester.runAsync(() => h.count('srs_states')), 1);
      final answer = (await tester.runAsync(h.canonicalAnswer))!;
      expect(answer.read<String>('prompt_mode'), 'srsRecall');
      expect(answer.read<String>('owner_id'), 'synthetic-actions-owner');
    }),
  );

  testWidgets(
    'catalog word report survives its owned sheet rebuild and saves exactly once',
    (tester) => _using(tester, (h) async {
      await tester.runAsync(() => h.seed(syntheticPackUiContent()));
      await tester.pumpWidget(h.app());
      await openPackUiDetail(tester);
      await tapPackUi(tester, 'pack-word-cat');
      await untilPackUi(
        tester,
        () => find.text('A small pet that meows.').evaluate().isNotEmpty,
      );
      final beforeReport = await motivationPresentationIo(
        tester,
        () => ownerMigrationRows(h.database),
        stage: 'catalog-report/before-open',
      );
      final word = beforeReport['vocabulary_words']!.single;
      await tapPackUi(tester, 'pack-word-report');
      await untilPackUi(
        tester,
        () => find
            .byKey(const ValueKey('word-report-reason:incorrectMeaning'))
            .evaluate()
            .isNotEmpty,
      );
      await tapPackUi(tester, 'word-report-reason:incorrectMeaning');
      const draft = 'Synthetic catalog report survives rebuild';
      final comment = find.byKey(const ValueKey('word-report-comment'));
      await tester.ensureVisible(comment);
      await tester.enterText(comment, draft);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final sheetRoute = ModalRoute.of(
        tester.element(find.byType(WordReportSheet)),
      )!;
      expect(sheetRoute.isCurrent, isTrue);
      sheetRoute.changedExternalState();
      await tester.pump();
      expect(
        find.text('รายงานนี้ไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่'),
        findsNothing,
      );
      expect(tester.widget<TextField>(comment).controller!.text, draft);
      await tapPackUi(tester, 'word-report-review');
      await untilPackUi(
        tester,
        () => find
            .byKey(const ValueKey('word-report-confirm'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text(draft), findsOneWidget);
      expect(
        await motivationPresentationIo(
          tester,
          () => ownerMigrationRows(h.database),
          stage: 'catalog-report/before-confirm',
        ),
        beforeReport,
      );
      await tapPackUi(tester, 'word-report-confirm');
      await untilPackUi(
        tester,
        () => find
            .byKey(const ValueKey('word-report-queued'))
            .evaluate()
            .isNotEmpty,
      );
      final afterReport = await motivationPresentationIo(
        tester,
        () => ownerMigrationRows(h.database),
        stage: 'catalog-report/after-confirm',
      );
      final report = StoredWordReport.fromStorage(
        afterReport['word_reports']!.single,
      );
      expect(report.ownerId, 'synthetic-actions-owner');
      expect(report.target.wordId, word['id']);
      expect(report.target.categoryId, word['category_id']);
      expect(report.target.wordRevision, word['local_revision']);
      expect(report.target.spelling, 'cat');
      expect(report.target.meaning, 'แมว');
      expect(report.reason, ReportReason.incorrectMeaning);
      expect(report.comment, draft);
      afterReport.remove('word_reports');
      beforeReport.remove('word_reports');
      expect(afterReport, beforeReport);
      expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
      expect(await tester.runAsync(() => h.count('answer_attempts')), 0);
    }),
  );

  testWidgets(
    'reopening included bytes repairs cache without replacing edited words or history',
    (tester) => _using(tester, (h) async {
      await tester.pumpWidget(h.app());
      await _installStarter(tester);
      await _finishDefinition(tester, h, LexicalQuizInput.definitionChoice);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => h.database.customUpdate(
          "UPDATE vocabulary_words SET meaning=?,local_revision=local_revision+1 "
          "WHERE owner_id=? AND spelling='cat'",
          variables: [
            const Variable<String>('คำแปลที่ผู้เรียนแก้เอง'),
            const Variable<String>('synthetic-actions-owner'),
          ],
          updates: {h.database.vocabularyWords},
        ),
      );
      final original = (await tester.runAsync(h.stored))!;
      final before = (await tester.runAsync(
        () => ownerMigrationRows(h.database),
      ))!..remove('learning_pack_versions');
      await tester.pumpWidget(h.app());
      await packUiReady(tester);
      await tapPackUi(tester, 'pack-row-${original.id}');
      await idlePackUi(tester);
      await tapPackUi(tester, 'pack-remove');
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบไฟล์แพ็ก'));
      await idlePackUi(tester);
      await tester.tap(find.byTooltip('กลับไปยังรายการแพ็ก'));
      await packUiReady(tester);
      await _openPreview(tester);
      await tapPackUi(tester, 'pack-confirm-install');
      await idlePackUi(tester);
      final repaired = (await tester.runAsync(h.stored))!;
      expect(repaired.id, original.id);
      expect(repaired.packageSha256, original.packageSha256);
      expect(repaired.categoryId, original.categoryId);
      expect(repaired.importId, original.importId);
      expect(repaired.installedAtUtc, original.installedAtUtc);
      expect(
        (await tester.runAsync(() => ownerMigrationRows(h.database)))!
          ..remove('learning_pack_versions'),
        before,
      );
      expect(await tester.runAsync(() => h.count('answer_attempts')), 2);
      expect(await tester.runAsync(() => h.count('vocabulary_words')), 12);
    }),
  );
}

Future<void> _using(
  WidgetTester tester,
  Future<void> Function(LearningPackUiHarness h) body,
) async {
  final h = (await tester.runAsync(LearningPackUiHarness.open))!;
  try {
    await body(h);
    expect(tester.takeException(), isNull);
  } catch (error, stack) {
    h.recordFailure(error, stack, tester);
    rethrow;
  } finally {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    await closePackUi(tester, h);
  }
}

Future<void> _openPreview(WidgetTester tester) async {
  await packUiReady(tester);
  await tapPackUi(tester, 'pack-open-starter');
  await untilPackUi(
    tester,
    () => find
        .byKey(const ValueKey('pack-confirm-install'))
        .evaluate()
        .isNotEmpty,
  );
}

Future<void> _installStarter(WidgetTester tester) async {
  await _openPreview(tester);
  await tapPackUi(tester, 'pack-confirm-install');
  await idlePackUi(tester);
  expect(
    find.descendant(
      of: find.byType(SnackBar),
      matching: find.text('ติดตั้งแพ็กบทเรียนแล้ว'),
    ),
    findsOneWidget,
  );
}

Future<void> _finishDefinition(
  WidgetTester tester,
  LearningPackUiHarness h,
  LexicalQuizInput input,
) async {
  await tapPackUi(tester, 'pack-definition-0');
  await untilPackUi(
    tester,
    () => find.byType(LexicalQuizSetupDialog).evaluate().isNotEmpty,
  );
  if (input == LexicalQuizInput.definitionTyped) {
    final mode = find.byKey(const ValueKey('definition-input-mode'));
    await tester.ensureVisible(mode);
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.text('พิมพ์คำศัพท์').last);
    await tester.pumpAndSettle();
  }
  final count = find.byKey(ValueKey(('definition-item-count', input)));
  await tester.ensureVisible(count);
  await tester.tap(count);
  await tester.pumpAndSettle();
  final twoWords = find.text('2 คำ').last;
  final dropdownScrollable = find
      .ancestor(of: twoWords, matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(
    twoWords.hitTestable(),
    -80,
    scrollable: dropdownScrollable,
    maxScrolls: 20,
  );
  expect(twoWords.hitTestable(), findsOneWidget);
  await tester.tap(twoWords.hitTestable());
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: count, matching: find.text('2 คำ')),
    findsOneWidget,
  );
  expect(tester.state<FormFieldState<int>>(count).value, 2);
  await tester.tap(find.byKey(const ValueKey('definition-start')));
  await untilPackUi(
    tester,
    () =>
        find.byType(QuizScreen).evaluate().isNotEmpty &&
        find
            .text(
              input == LexicalQuizInput.definitionChoice
                  ? 'อ่านนิยามแล้วเลือกคำศัพท์'
                  : 'อ่านนิยามแล้วพิมพ์คำศัพท์',
            )
            .evaluate()
            .isNotEmpty,
  );
  expect(find.byType(SnackBar), findsNothing);
  final screen = tester.widget<QuizScreen>(find.byType(QuizScreen));
  final questions = screen.preparedLaunch!.preparedPlan!.questions;
  expect(questions, hasLength(2));
  expect(screen.preparedLaunch!.configuration.lexical!.limit, 2);
  expect(screen.expectedOwnerId, 'synthetic-actions-owner');
  for (var index = 0; index < questions.length; index++) {
    final question = questions[index];
    await untilPackUi(
      tester,
      () => find.text(question.prompt).evaluate().isNotEmpty,
    );
    if (input == LexicalQuizInput.definitionTyped) {
      final field = find.byKey(const ValueKey('definition-response'));
      await tester.ensureVisible(field);
      await tester.enterText(field, question.correctAnswer);
      await tester.testTextInput.receiveAction(TextInputAction.done);
    } else {
      final answer = find.widgetWithText(FilledButton, question.correctAnswer);
      await tester.ensureVisible(answer);
      await tester.pump();
      await tester.tap(answer);
    }
    await untilPackUi(tester, () => find.text('ถูกต้อง').evaluate().isNotEmpty);
    expect(await tester.runAsync(() => h.count('answer_attempts')), index + 1);
    final next = find.text(
      index == questions.length - 1 ? 'ดูผลการเรียน' : 'คำถามถัดไป',
    );
    await tester.ensureVisible(next);
    await tester.pump();
    await tester.tap(next);
  }
  await untilPackUi(
    tester,
    () => find.byType(ScoreScreen).evaluate().isNotEmpty,
  );
  expect(
    tester.widget<ScoreScreen>(find.byType(ScoreScreen)).correctAnswers,
    2,
  );
  expect(tester.widget<ScoreScreen>(find.byType(ScoreScreen)).wrongAnswers, 0);
  final answers = (await tester.runAsync(
    () => h.database
        .customSelect(
          'SELECT a.prompt_mode,a.owner_id,s.state '
          'FROM answer_attempts a JOIN learning_sessions s ON s.id=a.session_id',
        )
        .get(),
  ))!;
  expect(answers, hasLength(2));
  for (final answer in answers) {
    expect(answer.read<String>('prompt_mode'), input.name);
    expect(answer.read<String>('owner_id'), 'synthetic-actions-owner');
    expect(answer.read<String>('state'), 'completed');
  }
  expect(await tester.runAsync(() => h.count('learning_sessions')), 1);
}
