import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/content_reports/data/drift_content_report_queue.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_button.dart';
import 'package:vocab_learning_app/features/progress/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_review_center_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';
import 'package:vocab_learning_app/screens/saved_words_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/word_reports_screen.dart';
import 'package:vocab_learning_app/widgets/word_report_sheet.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/content_report_ui_io.dart';
import '../support/motivation_presentation_io.dart';
import '../support/review_center_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final foreignCover in [false, true]) {
    testWidgets(
      'Review Center owned word report ${foreignCover ? 'burns a foreign covered return' : 'keeps its draft and ordinary return'}',
      (tester) async {
        final h = await _fixture(tester);
        await tester.runAsync(() => h.save(configuredWordIds.first));
        await tester.pumpWidget(_reviewReportApp(h, _screen(h)));
        await _ready(tester);
        await _tap(tester, 'review-center-saved-practice');
        final answer = find.widgetWithText(FilledButton, 'สถานี');
        await reportUiWait(
          tester,
          'review-report-answer',
          () => answer.evaluate().isNotEmpty,
        );
        await reportUiTap(tester, answer, 'review-report-answer');
        final practice = ModalRoute.of(
          tester.element(find.byType(QuizScreen)),
        )!;
        final before = await motivationPresentationIo(
          tester,
          h.snapshotAllTables,
        );
        final report = find.descendant(
          of: find.byType(ContentReportButton),
          matching: find.byType(TextButton),
        );
        await reportUiReveal(
          tester,
          report,
          'review-report-open',
          scrollable: find.byType(SingleChildScrollView),
        );
        await reportUiTap(tester, report, 'review-report-open');
        await reportUiWait(
          tester,
          'review-report-sheet',
          () => find.byType(WordReportSheet).evaluate().isNotEmpty,
        );
        await reportUiTapKey(tester, 'word-report-reason:spelling');
        final comment = find.byKey(const ValueKey('word-report-comment'));
        const draft = 'Synthetic Review Center report draft';
        await tester.ensureVisible(comment);
        await tester.enterText(comment, draft);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        final sheet = ModalRoute.of(
          tester.element(find.byType(WordReportSheet)),
        )!;
        sheet.changedExternalState();
        practice.changedExternalState();
        await tester.pump();
        expect(tester.widget<TextField>(comment).controller!.text, draft);
        expect(
          find.text('รายงานนี้ไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่'),
          findsNothing,
        );
        expect(
          await motivationPresentationIo(tester, h.snapshotAllTables),
          before,
        );
        if (foreignCover) {
          final navigator = Navigator.of(tester.element(comment));
          final foreign = MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('Synthetic Review report cover')),
          );
          unawaited(navigator.push<void>(foreign));
          await reportUiWait(
            tester,
            'review-report-covered',
            () => foreign.isCurrent,
          );
          practice.changedExternalState();
          await tester.pump();
          navigator.removeRoute(sheet);
          navigator.removeRoute(practice);
          await tester.pump();
          expect(foreign.isCurrent, isTrue);
          expect(find.text('Synthetic Review report cover'), findsOneWidget);
          navigator.pop();
          await _unavailable(tester);
          expect(find.byType(QuizScreen, skipOffstage: false), findsNothing);
          expect(
            await motivationPresentationIo(tester, h.snapshotAllTables),
            before,
          );
          return;
        }
        Navigator.of(tester.element(comment)).pop();
        await reportUiWait(
          tester,
          'review-report-dismissed',
          () => find.byType(WordReportSheet).evaluate().isEmpty,
        );
        expect(find.byType(QuizScreen), findsOneWidget);
        expect(find.text('ถูกต้อง'), findsOneWidget);
        expect(
          await motivationPresentationIo(tester, h.snapshotAllTables),
          before,
        );
        await reportUiTap(
          tester,
          find.text('ดูผลการเรียน'),
          'review-report-score',
        );
        await reportUiWait(
          tester,
          'review-report-score',
          () => find.byType(ScoreScreen).evaluate().isNotEmpty,
        );
        final finished = await motivationPresentationIo(
          tester,
          h.snapshotAllTables,
        );
        await reportUiTap(
          tester,
          find.text('ย้อนกลับ'),
          'review-report-return',
        );
        await reportUiWait(
          tester,
          'review-report-returned',
          () =>
              find.byType(QuizScreen, skipOffstage: false).evaluate().isEmpty &&
              find.byType(ScoreScreen, skipOffstage: false).evaluate().isEmpty,
        );
        await _ready(tester);
        expect(_count(tester, 'saved'), 'Saved: 1');
        expect(find.text('Review Center unavailable'), findsNothing);
        expect(
          await motivationPresentationIo(tester, h.snapshotAllTables),
          finished,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'all reasons, unavailable intents and two original report receipts survive read/filter/refresh without writes',
    (tester) async {
      final h = await _fixture(tester);
      final reports = await _mixed(tester, h);
      final before = await tester.runAsync(h.snapshotAllTables);
      await _open(tester, h);
      await _ready(tester);
      expect(_count(tester, 'due'), 'Due: 1');
      expect(_count(tester, 'incorrect'), 'Incorrect history: 2');
      expect(_count(tester, 'saved'), 'Saved: 2');
      expect(_count(tester, 'reported'), 'Local reports: 2');
      expect(find.text('Words in ready queues: 3'), findsOneWidget);
      await _reveal(tester, _word(configuredWordIds.first));
      for (final queue in ['due', 'incorrect', 'saved']) {
        expect(
          find.byKey(
            ValueKey('review-center-reason:$queue:${configuredWordIds.first}'),
          ),
          findsOneWidget,
        );
      }
      await _tap(tester, 'review-center-filter-saved');
      await _reveal(
        tester,
        find.byKey(
          ValueKey('review-center-unavailable:${configuredWordIds[1]}'),
        ),
      );
      expect(find.text('ticket'), findsNothing);
      await _tap(tester, 'review-center-filter-due');
      expect(
        find.byKey(
          ValueKey('review-center-unavailable:${configuredWordIds[1]}'),
        ),
        findsNothing,
      );
      await _tap(tester, 'review-center-filter-reported');
      for (final report in reports) {
        final row = find.byKey(ValueKey('review-center-report:${report.id}'));
        await _reveal(tester, row);
        await tester.tap(row);
        await tester.pumpAndSettle();
        final details = find.byWidgetPredicate(
          (widget) =>
              widget is WordReportDetails && widget.report.id == report.id,
        );
        await _reveal(
          tester,
          find.descendant(
            of: details,
            matching: find.text('Receipt: ${report.id}'),
          ),
        );
        expect(
          tester.widget<WordReportDetails>(details).report.sameFacts(report),
          isTrue,
        );
        expect(
          tester.widget<WordReportDetails>(details).showLocalOnlyNotice,
          isFalse,
        );
        expect(find.textContaining('Not sent.'), findsNothing);
      }
      h.now = h.now.add(const Duration(minutes: 1));
      await _tap(tester, 'review-center-refresh');
      await _ready(tester);
      expect(find.textContaining(h.now.toIso8601String()), findsOneWidget);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the complete lazy saved list retains more than20 rows and labels the actual20-target practice batch',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() async {
        for (var i = 0; i < 25; i++) {
          final id = 'synthetic-review-ui-${i.toString().padLeft(2, '0')}';
          await h.addWord(
            id: id,
            spelling: 'syntheticword$i',
            meaning: 'synthetic meaning $i',
          );
          await h.save(id);
        }
      });
      final before = await tester.runAsync(h.snapshotAllTables);
      await _open(tester, h);
      await _ready(tester);
      expect(_count(tester, 'saved'), 'Saved: 25');
      await _tap(tester, 'review-center-filter-saved');
      await _reveal(tester, _word('synthetic-review-ui-24'));
      expect(find.text('syntheticword24'), findsOneWidget);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      await _tap(tester, 'review-center-saved-practice');
      await _until(tester, () => find.byType(QuizScreen).evaluate().isNotEmpty);
      final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
      expect(quiz.expectedOwnerId, configuredOwnerId);
      expect(identical(quiz.ownerChanges, h.ownerChanges), isTrue);
      expect(identical(quiz.learning, h.learning), isTrue);
      expect(quiz.selectionMode, QuizWordSelectionMode.sourcePractice);
      expect(quiz.wordIds, hasLength(20));
      expect(
        () => quiz.wordIds!.add('synthetic-extra'),
        throwsUnsupportedError,
      );
      await _untilAsync(
        tester,
        () async => await _tableCount(h, 'learning_sessions') == 1,
      );
      expect(await tester.runAsync(() => _tableCount(h, 'answer_attempts')), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an owned due child survives cleared parent reads and finishes through canonical ACK before a fresh read',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.seedDue(configuredWordIds.first));
      await _open(tester, h);
      await _ready(tester);
      await _tap(tester, 'review-center-due-practice');
      await _srsReady(tester);
      final srs = tester.widget<SrsFlashcardsScreen>(
        find.byType(SrsFlashcardsScreen),
      );
      expect(srs.expectedOwnerId, configuredOwnerId);
      expect(identical(srs.ownerChanges, h.ownerChanges), isTrue);
      expect(identical(srs.learning, h.learning), isTrue);
      expect(srs.sourceWordIds, isNull);
      expect(
        find.byKey(
          ValueKey('review-center-word:${configuredWordIds.first}'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      await _tapIn(
        tester,
        SrsFlashcardsScreen,
        find.byKey(const ValueKey('srs-flip')),
      );
      await tester.pumpAndSettle();
      await _tapIn(
        tester,
        SrsFlashcardsScreen,
        find.byKey(const ValueKey('srs-again')),
      );
      await _until(
        tester,
        () => find.byKey(const ValueKey('srs-next')).evaluate().isNotEmpty,
      );
      expect(await tester.runAsync(() => _tableCount(h, 'answer_attempts')), 1);
      await _tapIn(
        tester,
        SrsFlashcardsScreen,
        find.byKey(const ValueKey('srs-next')),
      );
      await _until(
        tester,
        () => find.byType(SrsFlashcardsScreen).evaluate().isEmpty,
      );
      await _ready(tester);
      final session = (await tester.runAsync(
        () => h.database.select(h.database.learningSessions).getSingle(),
      ))!;
      expect(session.state, 'completed');
      expect(session.correctCount, 0);
      expect(session.wrongCount, 1);
      expect(await tester.runAsync(() => _tableCount(h, 'answer_attempts')), 1);
      expect(
        await tester.runAsync(() => _tableCount(h, 'reward_transactions')),
        0,
      );
      final facts = (await tester.runAsync(
        () => h.queries
            .watchOwner(
              expectedOwnerId: configuredOwnerId,
              evaluatedAtUtc: h.now,
              stillCurrent: () => true,
            )
            .first,
      ))!;
      expect(
        _count(tester, 'due'),
        'Due: ${facts.wordRows.where((row) => row.queues.contains(ReviewQueue.due)).length}',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved recognition reaches its exact owned Score and returns without the parent cover canceling its accepted session',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.save(configuredWordIds.first));
      await _open(tester, h);
      await _ready(tester);
      await _finishSavedQuiz(tester, h);
      expect(
        find.byKey(
          ValueKey('review-center-word:${configuredWordIds.first}'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      await _tapIn(
        tester,
        ScoreScreen,
        find.widgetWithText(OutlinedButton, 'ย้อนกลับ'),
      );
      await _until(tester, () => find.byType(QuizScreen).evaluate().isEmpty);
      await _ready(tester);
      expect(_count(tester, 'saved'), 'Saved: 1');
      expect(
        await tester.runAsync(() => _tableCount(h, 'learning_sessions')),
        1,
      );
      expect(await tester.runAsync(() => _tableCount(h, 'answer_attempts')), 1);
      final session = (await tester.runAsync(
        () => h.database.select(h.database.learningSessions).getSingle(),
      ))!;
      expect(session.activityType, 'sourcePractice');
      expect(session.state, 'completed');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'incorrect practice keeps its distinct canonical selection and forwards the exact owner and learning binding',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(
        () => h.seedWrong(
          wordId: configuredWordIds.first,
          evidenceClass: 'recreational',
        ),
      );
      await _open(tester, h);
      await _ready(tester);
      await _tap(tester, 'review-center-incorrect-practice');
      await _until(tester, () => find.byType(QuizScreen).evaluate().isNotEmpty);
      final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
      expect(quiz.selectionMode, QuizWordSelectionMode.weakness);
      expect(quiz.wordIds, [configuredWordIds.first]);
      expect(quiz.expectedOwnerId, configuredOwnerId);
      expect(identical(quiz.ownerChanges, h.ownerChanges), isTrue);
      expect(identical(quiz.learning, h.learning), isTrue);
    },
  );

  testWidgets(
    'a foreign cover above an owned due child burns the return without popping the foreign route',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.seedDue(configuredWordIds.first));
      final nav = GlobalKey<NavigatorState>();
      await _open(tester, h, navigatorKey: nav);
      await _ready(tester);
      await _tap(tester, 'review-center-due-practice');
      await _srsReady(tester);
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('synthetic foreign route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('synthetic foreign route'), findsOneWidget);
      expect(nav.currentState!.canPop(), isTrue);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Activity unavailable'), findsOneWidget);
      nav.currentState!.pop();
      await _unavailable(tester);
      expect(
        find.byKey(ValueKey('review-center-word:${configuredWordIds.first}')),
        findsNothing,
      );
      expect(await tester.runAsync(() => _tableCount(h, 'answer_attempts')), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removing the exact owned Score while a foreign route is top never pops that route or revives the hub return',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.save(configuredWordIds.first));
      final nav = GlobalKey<NavigatorState>();
      await _open(tester, h, navigatorKey: nav);
      await _ready(tester);
      await _finishSavedQuiz(tester, h);
      final scoreRoute = ModalRoute.of(
        tester.element(find.byType(ScoreScreen)),
      )!;
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('synthetic foreign Score cover')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.removeRoute(scoreRoute);
      await tester.pumpAndSettle();
      expect(find.text('synthetic foreign Score cover'), findsOneWidget);
      expect(nav.currentState!.canPop(), isTrue);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await _unavailable(tester);
      expect(await tester.runAsync(() => _tableCount(h, 'answer_attempts')), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual coalesced owner A to B to A hides all rows and rejects an old row callback',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.save(configuredWordIds.first));
      await _open(tester, h);
      await _ready(tester);
      final target = find.byKey(
        ValueKey('review-center-practice-saved:${configuredWordIds.first}'),
      );
      await _reveal(tester, target);
      final retained = tester.widget<ButtonStyleButton>(target).onPressed!;
      final before = await tester.runAsync(h.snapshotAllTables);
      await tester.runAsync(
        () => h.database.transaction(() async {
          await h.switchOwner(configuredOtherOwnerId);
          await h.switchOwner(configuredOwnerId);
        }),
      );
      await _unavailable(tester);
      retained();
      await _drain(tester);
      expect(find.text('station'), findsNothing);
      expect(find.byType(QuizScreen), findsNothing);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final event in ['null-to-same', 'error', 'done']) {
    testWidgets(
      'synchronous owner $event blocks captured actions before any redraw',
      (tester) async {
        final h = await _fixture(tester);
        await tester.runAsync(() => h.save(configuredWordIds.first));
        final owners = _owners();
        await _open(tester, h, ownerChanges: owners.stream);
        owners.add(configuredOwnerId);
        await _ready(tester);
        final target = find.byKey(
          ValueKey('review-center-practice-saved:${configuredWordIds.first}'),
        );
        await _reveal(tester, target);
        final retained = tester.widget<ButtonStyleButton>(target).onPressed!;
        final before = await tester.runAsync(h.snapshotAllTables);
        switch (event) {
          case 'null-to-same':
            owners
              ..add(null)
              ..add(configuredOwnerId);
          case 'error':
            owners.addError(StateError('synthetic owner read failure'));
          case 'done':
            await owners.close();
        }
        retained();
        await _unavailable(tester);
        expect(find.byType(QuizScreen), findsNothing);
        expect(await tester.runAsync(h.snapshotAllTables), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'owner invalidation from a sibling build clears rows safely and an old callback cannot launch',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.save(configuredWordIds.first));
      final owners = _owners();
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);
      var emit = false;
      final hub = _screen(h, ownerChanges: owners.stream);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (_, value, child) => Column(
              children: [
                Expanded(child: hub),
                Builder(
                  builder: (_) {
                    if (emit) {
                      emit = false;
                      owners
                        ..add(null)
                        ..add(configuredOwnerId);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      owners.add(configuredOwnerId);
      await _ready(tester);
      final target = find.byKey(
        ValueKey('review-center-practice-saved:${configuredWordIds.first}'),
      );
      await _reveal(tester, target);
      final retained = tester.widget<ButtonStyleButton>(target).onPressed!;
      emit = true;
      rebuild.value++;
      await tester.pump();
      retained();
      await _unavailable(tester);
      expect(find.byType(QuizScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final reason in ['hidden', 'inactive', 'dependency-replaced']) {
    testWidgets(
      'a $reason hub cannot deliver its retained row action or old private counts',
      (tester) async {
        final h = await _fixture(tester);
        await tester.runAsync(() => h.save(configuredWordIds.first));
        final changed = ValueNotifier<bool>(false);
        addTearDown(changed.dispose);
        final replacement = h.compose();
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: changed,
              builder: (_, value, child) => Visibility(
                visible: !(value && reason == 'hidden'),
                maintainState: true,
                child: _screen(
                  h,
                  reviewCenter: value && reason == 'dependency-replaced'
                      ? replacement
                      : h.reviewCenter,
                ),
              ),
            ),
          ),
        );
        await _ready(tester);
        final target = find.byKey(
          ValueKey('review-center-practice-saved:${configuredWordIds.first}'),
        );
        await _reveal(tester, target);
        final retained = tester.widget<ButtonStyleButton>(target).onPressed!;
        final before = await tester.runAsync(h.snapshotAllTables);
        if (reason == 'inactive') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        } else {
          changed.value = true;
        }
        await tester.pump();
        retained();
        if (reason == 'inactive') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        if (reason == 'hidden') changed.value = false;
        await _unavailable(tester);
        expect(find.text('station'), findsNothing);
        expect(find.byType(QuizScreen), findsNothing);
        expect(await tester.runAsync(h.snapshotAllTables), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ordinary source failure stays unavailable while real saved and report sections remain usable, then explicit refresh recovers',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() async {
        await h.seedDue(configuredWordIds.first);
        await h.save(configuredWordIds.first);
        await h.report(configuredWordIds.first);
      });
      final queries = _FailQueries(h.database);
      final reviewCenter = h.compose(queries: queries);
      final before = await tester.runAsync(h.snapshotAllTables);
      await _open(tester, h, reviewCenter: reviewCenter);
      await _ready(tester, partial: true);
      expect(_count(tester, 'due'), 'Due: Unavailable');
      expect(_count(tester, 'incorrect'), 'Incorrect history: Unavailable');
      expect(_count(tester, 'saved'), 'Saved: 1');
      expect(_count(tester, 'reported'), 'Local reports: 1');
      queries.fail = false;
      await _tap(tester, 'review-center-refresh');
      await _ready(tester);
      expect(_count(tester, 'due'), 'Due: 1');
      expect(await tester.runAsync(h.snapshotAllTables), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a terminal composer error retires its real snapshot until an explicit fresh read',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.save(configuredWordIds.first));
      final composer = _InterruptedComposer(h.reviewCenter);
      await _open(tester, h, reviewCenter: composer);
      await _ready(tester);
      final target = find.byKey(
        ValueKey('review-center-practice-saved:${configuredWordIds.first}'),
      );
      await _reveal(tester, target);
      final retained = tester.widget<ButtonStyleButton>(target).onPressed!;
      final before = await tester.runAsync(h.snapshotAllTables);
      composer.interrupt();
      await _until(
        tester,
        () => find.text('Could not load review queues.').evaluate().isNotEmpty,
      );
      composer.releasePreviousRealSnapshot();
      await _drain(tester);
      expect(find.text('Could not load review queues.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('review-center-count-saved')),
        findsNothing,
      );
      expect(find.text('station'), findsNothing);
      retained();
      await _drain(tester);
      expect(find.byType(QuizScreen), findsNothing);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      await tester.tap(find.byKey(const ValueKey('review-center-refresh')));
      await tester.pump();
      await _ready(tester);
      expect(_count(tester, 'saved'), 'Saved: 1');
      expect(await tester.runAsync(h.snapshotAllTables), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late real read facts after owner loss cannot resurrect any queue',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.seedDue(configuredWordIds.first));
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final queries = _HeldQueries(h.database, gate.future);
      final owners = _owners();
      await _open(
        tester,
        h,
        ownerChanges: owners.stream,
        reviewCenter: h.compose(queries: queries),
      );
      owners.add(configuredOwnerId);
      await _until(tester, () => queries.reads > 0);
      owners
        ..add(null)
        ..add(configuredOwnerId);
      gate.complete();
      await _unavailable(tester);
      await _drain(tester);
      expect(find.text('station'), findsNothing);
      expect(
        await tester.runAsync(() => _tableCount(h, 'learning_sessions')),
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing owner and runtime dependencies create no local owner or queue facts',
    (tester) async {
      final h = await _fixture(tester, seed: false);
      final before = await tester.runAsync(h.snapshotAllTables);
      await _open(tester, h);
      await _unavailable(tester);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      await tester.pumpWidget(
        const MaterialApp(
          home: ReviewCenterScreen(
            expectedOwnerId: configuredOwnerId,
            languageCode: 'en',
          ),
        ),
      );
      await _unavailable(tester);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved management, report history and History use existing owner-bound routes without hub writes',
    (tester) async {
      final h = await _fixture(tester);
      await _mixed(tester, h);
      final before = await tester.runAsync(h.snapshotAllTables);
      final nav = GlobalKey<NavigatorState>();
      await _open(tester, h, navigatorKey: nav);
      for (final (key, type) in [
        ('review-center-manage-saved', SavedWordsScreen),
        ('review-center-reports', WordReportsScreen),
        ('review-center-history', LearningHistoryScreen),
      ]) {
        await _ready(tester);
        await _tap(tester, key);
        await _until(tester, () {
          final child = find.byType(type);
          if (child.evaluate().isEmpty) {
            return false;
          }
          return ModalRoute.of(tester.element(child))?.animation?.status ==
                  AnimationStatus.completed &&
              find
                  .descendant(
                    of: child,
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .isEmpty;
        });
        if (type == LearningHistoryScreen) {
          final history = tester.widget<LearningHistoryScreen>(
            find.byType(type),
          );
          expect(history.loader, isNotNull);
          expect(identical(history.ownerChanges, h.ownerChanges), isTrue);
        }
        nav.currentState!.pop();
        await _ready(tester);
        await tester.pumpAndSettle();
      }
      await _ready(tester);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a captured History loader rejects a foreign cover while the parent remains covered',
    (tester) async {
      final h = await _fixture(tester);
      await tester.runAsync(() => h.seedWrong(wordId: configuredWordIds.first));
      final before = await tester.runAsync(h.snapshotAllTables);
      final nav = GlobalKey<NavigatorState>();
      await _open(tester, h, navigatorKey: nav);
      await _ready(tester);
      await _tap(tester, 'review-center-history');
      final historyFinder = find.byType(LearningHistoryScreen);
      await _until(tester, () {
        if (historyFinder.evaluate().isEmpty) {
          return false;
        }
        return ModalRoute.of(
                  tester.element(historyFinder),
                )?.animation?.status ==
                AnimationStatus.completed &&
            find
                .descendant(
                  of: historyFinder,
                  matching: find.byType(CircularProgressIndicator),
                )
                .evaluate()
                .isEmpty;
      });
      final loader = tester
          .widget<LearningHistoryScreen>(historyFinder)
          .loader!;
      final initial = await tester.runAsync(() => loader());
      expect(initial!.ownerId, configuredOwnerId);
      expect(initial.entries, isNotEmpty);
      unawaited(
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('synthetic foreign History cover')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Object? rejected;
      await tester.runAsync(() async {
        try {
          await loader();
        } catch (error) {
          rejected = error;
        }
      });
      expect(
        rejected,
        isA<ReviewCenterReadException>().having(
          (error) => error.code,
          'owner-scoped read code',
          ReviewReadFailureCode.ownerInvalidated,
        ),
      );
      expect(find.text('synthetic foreign History cover'), findsOneWidget);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await _unavailable(tester);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      '${language}320px200percent IME and keyboard keep filters, unavailable rows and report details reachable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final h = await _fixture(tester);
        await _mixed(tester, h);
        final before = await tester.runAsync(h.snapshotAllTables);
        await _open(
          tester,
          h,
          language: language,
          scale: 2,
          reducedMotion: true,
        );
        await _ready(tester);
        final filter = find.byKey(const ValueKey('review-center-filter-saved'));
        await _reveal(tester, filter);
        Focus.of(
          tester.element(
            find.descendant(of: filter, matching: find.byType(Text)).first,
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(tester.widget<ChoiceChip>(filter).selected, isTrue);
        await _reveal(
          tester,
          find.byKey(
            ValueKey('review-center-unavailable:${configuredWordIds[1]}'),
          ),
        );
        await _tap(tester, 'review-center-filter-reported');
        expect(await tester.runAsync(h.snapshotAllTables), before);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<ReviewCenterHarness> _fixture(
  WidgetTester tester, {
  bool seed = true,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final h = (await tester.runAsync(
    () => ReviewCenterHarness.open(seed: seed),
  ))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(h.close);
  });
  return h;
}

Widget _reviewReportApp(ReviewCenterHarness h, Widget screen) {
  final queue = DriftContentReportQueue(
    database: h.database,
    ownerWrites: h.ownerWrites,
  );
  return AppDependenciesScope(
    dependencies: AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _ReviewReportGuest(),
      database: h.database,
      progress: h.progress,
      learning: h.learning,
      wordReports: h.wordReports,
      vocabulary: VocabularyUseCases(
        owners: h.owners,
        vocabulary: DriftVocabularyRepository(h.database),
        generateId: () => 'synthetic-review-vocabulary',
        nowUtc: () => h.now,
      ),
      contentReports: ContentReportUseCases(
        queue: queue,
        generateId: () => 'synthetic-review-report',
        nowUtc: () => h.now,
        ordinarySessionGuard: queue.requireOrdinarySession,
      ),
    ),
    child: MaterialApp(home: screen),
  );
}

final class _ReviewReportGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('The report cannot create a guest');
}

Future<List<StoredWordReport>> _mixed(
  WidgetTester tester,
  ReviewCenterHarness h,
) async => (await tester.runAsync(() async {
  await h.seedDue(configuredWordIds.first);
  await h.seedWrong(wordId: configuredWordIds.first);
  await h.addWord(
    id: 'synthetic-review-missing-word',
    spelling: 'synthetic historical unavailable word',
    meaning: 'synthetic historical meaning',
  );
  await h.seedWrong(wordId: 'synthetic-review-missing-word');
  await h.database.customStatement(
    'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
    ['synthetic-review-missing-word'],
  );
  await h.save(configuredWordIds.first);
  await h.save(configuredWordIds[1]);
  final first = await h.report(
    configuredWordIds.first,
    comment: 'synthetic original report',
  );
  await h.database.customStatement(
    'UPDATE vocabulary_words SET meaning = ?, normalized_meaning = ?, local_revision = 2 WHERE id = ?',
    [
      'synthetic current meaning',
      'synthetic current meaning',
      configuredWordIds.first,
    ],
  );
  final second = await h.report(
    configuredWordIds.first,
    comment: 'synthetic revised report',
  );
  await h.database.customStatement(
    'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
    [configuredWordIds[1]],
  );
  return [first, second];
}))!;

Widget _screen(
  ReviewCenterHarness h, {
  ReviewCenterUseCases? reviewCenter,
  Stream<String?>? ownerChanges,
  String language = 'en',
}) => ReviewCenterScreen(
  expectedOwnerId: configuredOwnerId,
  reviewCenter: reviewCenter ?? h.reviewCenter,
  ownerChanges: ownerChanges ?? h.ownerChanges,
  learning: h.learning,
  savedWords: h.savedWords,
  wordReports: h.wordReports,
  languageCode: language,
);

Future<void> _open(
  WidgetTester tester,
  ReviewCenterHarness h, {
  ReviewCenterUseCases? reviewCenter,
  Stream<String?>? ownerChanges,
  GlobalKey<NavigatorState>? navigatorKey,
  String language = 'en',
  double scale = 1,
  bool reducedMotion = false,
}) => tester.pumpWidget(
  MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reducedMotion,
      ),
      child: child!,
    ),
    home: _screen(
      h,
      reviewCenter: reviewCenter,
      ownerChanges: ownerChanges,
      language: language,
    ),
  ),
);

StreamController<String?> _owners() {
  final controller = StreamController<String?>.broadcast(sync: true);
  addTearDown(() async {
    if (!controller.isClosed) await controller.close();
  });
  return controller;
}

Finder _word(String id) => find.byKey(ValueKey('review-center-word:$id'));
String _count(WidgetTester tester, String queue) => tester
    .widget<Text>(find.byKey(ValueKey('review-center-count-$queue')))
    .data!;

Future<void> _ready(WidgetTester tester, {bool partial = false}) =>
    _until(tester, () {
      for (final queue in ReviewQueue.values) {
        final key = find.byKey(ValueKey('review-center-count-${queue.name}'));
        if (key.evaluate().isEmpty) return false;
        final data = tester.widget<Text>(key).data ?? '';
        if (!RegExp(r': \d+$').hasMatch(data) &&
            !(partial && data.endsWith('Unavailable'))) {
          return false;
        }
      }
      return true;
    });

Future<void> _unavailable(WidgetTester tester) => _until(
  tester,
  () => find.text('Review Center unavailable').evaluate().isNotEmpty,
);

Future<void> _srsReady(WidgetTester tester) => _until(tester, () {
  final card = find.byKey(const ValueKey('srs-card'));
  if (card.evaluate().isEmpty) return false;
  return ModalRoute.of(tester.element(card))?.animation?.status ==
      AnimationStatus.completed;
});

Future<void> _finishSavedQuiz(
  WidgetTester tester,
  ReviewCenterHarness h,
) async {
  await _tap(tester, 'review-center-saved-practice');
  final meaning = (await tester.runAsync(
    () => h.word(configuredWordIds.first),
  ))!.meaning;
  final answer = find.widgetWithText(FilledButton, meaning);
  await _until(tester, () => answer.evaluate().isNotEmpty);
  await _tapIn(tester, QuizScreen, answer);
  await _until(tester, () => find.text('ดูผลการเรียน').evaluate().isNotEmpty);
  await _tapIn(tester, QuizScreen, find.text('ดูผลการเรียน'));
  await _until(tester, () => find.byType(ScoreScreen).evaluate().isNotEmpty);
  expect(await tester.runAsync(() => _tableCount(h, 'answer_attempts')), 1);
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  fail('Review Center observable condition did not become true');
}

Future<void> _untilAsync(
  WidgetTester tester,
  Future<bool> Function() ready,
) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if ((await tester.runAsync(ready))!) return;
  }
  fail('Review Center database condition did not become true');
}

Future<void> _reveal(WidgetTester tester, Finder target) =>
    _revealIn(tester, ReviewCenterScreen, target);
Future<void> _revealIn(WidgetTester tester, Type host, Finder target) async {
  await tester.pump();
  final outer = find
      .descendant(of: find.byType(host), matching: find.byType(Scrollable))
      .first;
  if (target.evaluate().isEmpty) {
    tester.state<ScrollableState>(outer).position.jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(
    target,
    140,
    scrollable: outer,
    maxScrolls: 100,
  );
  await tester.ensureVisible(target);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, String key) =>
    _tapIn(tester, ReviewCenterScreen, find.byKey(ValueKey(key)));
Future<void> _tapIn(WidgetTester tester, Type host, Finder target) async {
  await _revealIn(tester, host, target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<int> _tableCount(ReviewCenterHarness h, String table) async =>
    (await h.database
            .customSelect('SELECT COUNT(*) AS count FROM $table')
            .getSingle())
        .read<int>('count');

final class _FailQueries extends DriftReviewCenterQueries {
  _FailQueries(super.database);
  bool fail = true;
  @override
  Stream<ReviewReadFacts> watchOwner({
    required String expectedOwnerId,
    required DateTime evaluatedAtUtc,
    required bool Function() stillCurrent,
  }) => fail
      ? Stream<ReviewReadFacts>.error(
          const ReviewCenterReadException(ReviewReadFailureCode.readFailed),
        )
      : super.watchOwner(
          expectedOwnerId: expectedOwnerId,
          evaluatedAtUtc: evaluatedAtUtc,
          stillCurrent: stillCurrent,
        );
}

final class _HeldQueries extends DriftReviewCenterQueries {
  _HeldQueries(super.database, this.gate);
  final Future<void> gate;
  int reads = 0;
  @override
  Stream<ReviewReadFacts> watchOwner({
    required String expectedOwnerId,
    required DateTime evaluatedAtUtc,
    required bool Function() stillCurrent,
  }) => super
      .watchOwner(
        expectedOwnerId: expectedOwnerId,
        evaluatedAtUtc: evaluatedAtUtc,
        stillCurrent: stillCurrent,
      )
      .asyncMap((facts) async {
        reads++;
        await gate;
        return facts;
      });
}

/// Exercises the UI stream boundary with a delayed, unchanged snapshot obtained
/// from the actual composer. It never fabricates rows or learning operations.
final class _InterruptedComposer extends ReviewCenterUseCases {
  _InterruptedComposer(this.source)
    : super(
        queries: source.queries,
        progress: source.progress,
        savedWords: source.savedWords,
        wordReports: source.wordReports,
        nowUtc: source.nowUtc,
      );

  final ReviewCenterUseCases source;
  MultiStreamController<ReviewCenterSnapshot>? _events;
  ReviewCenterSnapshot? _previous;

  void interrupt() => _events!.addErrorSync(
    const ReviewCenterReadException(ReviewReadFailureCode.readFailed),
  );

  void releasePreviousRealSnapshot() => _events?.addSync(_previous!);

  @override
  Stream<ReviewCenterSnapshot> watchOwner({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => Stream<ReviewCenterSnapshot>.multi((events) {
    _events = events;
    final subscription = source
        .watchOwner(
          expectedOwnerId: expectedOwnerId,
          stillCurrent: stillCurrent,
        )
        .listen(
          (snapshot) {
            _previous = snapshot;
            events.addSync(snapshot);
          },
          onError: events.addErrorSync,
          onDone: events.close,
        );
    events.onCancel = () async {
      if (identical(_events, events)) {
        _events = null;
      }
      await subscription.cancel();
    };
  });
}
