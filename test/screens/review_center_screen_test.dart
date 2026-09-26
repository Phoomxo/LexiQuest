import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/meaning_quiz_mode_adapter.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/review/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/product/feature_contract/alltcas_idea_integration_catalog.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';

void main() {
  testWidgets(
    'AE saved queue cannot start for a different owner after display',
    (tester) async {
      var owner = 'owner-1';
      final launcher = _SessionLauncher();
      final cases = ReviewCenterUseCases(
        reader: _Reader(load: () async => [_item()]),
        ownerIdentities: _ReadReviewOwner(() async => owner),
        sessionLauncher: launcher,
        nowUtc: () => _now,
        timezoneId: 'Asia/Bangkok',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewCenterScreen(
            useCases: cases,
            lessonShellBuilder: _unusedDestination,
          ),
        ),
      );
      await tester.pumpAndSettle();
      owner = 'owner-2';
      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();
      expect(
        launcher._nextId,
        0,
        reason: 'the displayed queue belongs to owner-1',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final change in ['replace', 'pop', 'owner']) {
    testWidgets(
      'AE late lease attachment after $change retires original session',
      (tester) async {
        final fixture = await _durableFixture();
        addTearDown(fixture.database.close);
        final entered = Completer<void>();
        final release = Completer<void>();
        final timeRepository = _PendingTimeRepository(entered, release);
        final navigator = GlobalKey<NavigatorState>();
        final controller = UnifiedLessonController(
          learning: fixture.learning,
          adapter: const MeaningQuizModeAdapter(),
          activeLearningTime: ActiveLearningTimeController(
            repository: timeRepository,
            monotonicMicros: () => 0,
            nowUtc: () => _now,
            timezoneContext: (_) => const LearningTimeZoneContext(
              timezoneId: 'Asia/Bangkok',
              utcOffsetMinutes: 420,
            ),
          ),
        );
        final lease = UnifiedLessonShellLease(
          controller: controller,
          learning: fixture.learning,
          nowUtc: () => _now,
          builder: (_) => const Scaffold(body: Text('old lesson')),
        );
        final builder = (ReviewLessonLaunchRequest _) => lease;
        var cases = fixture.useCases;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('parent')),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return ReviewCenterScreen(
                  useCases: cases,
                  lessonShellBuilder: builder,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('เริ่มทบทวน'));
        await entered.future;
        if (change == 'pop') {
          navigator.currentState!.pop();
        } else if (change == 'owner') {
          await _switchToOwnerTwo(fixture.database);
        } else {
          update(() => cases = _useCases(result: []));
          await tester.pump();
        }
        release.complete();
        await tester.pumpAndSettle();
        expect(find.text('old lesson'), findsNothing);
        expect(await _activeSessions(fixture.database), isEmpty);
        expect(() => lease.shell, throwsStateError);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'AE old launch completion does not unlock or reload a newer pending launch',
    (tester) async {
      final fixture = await _durableFixture();
      addTearDown(fixture.database.close);
      final releases = [Completer<void>(), Completer<void>()];
      final persisted = [Completer<void>(), Completer<void>()];
      final reads = [0, 0];
      ReviewCenterUseCases cases(int index) => ReviewCenterUseCases(
        reader: _Reader(
          load: () async {
            reads[index]++;
            return [_item()];
          },
        ),
        ownerIdentities: fixture.useCases.ownerIdentities,
        sessionLauncher: _DelayedSessionLauncher(
          fixture.useCases.sessionLauncher,
          persisted: persisted[index],
          release: releases[index],
        ),
        nowUtc: () => _now,
        timezoneId: 'Asia/Bangkok',
      );
      final builder = (ReviewLessonLaunchRequest _) =>
          _lessonDestination(learning: fixture.learning);
      Widget app(ReviewCenterUseCases useCases) => MaterialApp(
        home: ReviewCenterScreen(
          useCases: useCases,
          lessonShellBuilder: builder,
        ),
      );
      await tester.pumpWidget(app(cases(0)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เริ่มทบทวน'));
      await persisted[0].future;
      await tester.pumpWidget(app(cases(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เริ่มทบทวน'));
      await persisted[1].future;
      releases[0].complete();
      // A spinner remains by design: use bounded pumps, not pumpAndSettle.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(reads, [1, 1]);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      final active = await _activeSessions(fixture.database);
      expect(active.map((session) => session.id), ['session:review-2']);
      releases[1].complete();
      await tester.pumpAndSettle();
      expect(find.byType(UnifiedLessonShell), findsOneWidget);
      Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
      await tester.pumpAndSettle();
      expect(await _activeSessions(fixture.database), isEmpty);
      expect(reads, [1, 2]);
    },
  );

  testWidgets(
    'AE owner-bound guidance clears during replacement read and cannot leak late old data',
    (tester) async {
      final pending = Completer<List<ReviewQueueItem>>();
      final replacement = ReviewCenterUseCases(
        reader: _Reader(load: () => pending.future),
        ownerIdentities: const _NamedReviewOwner('owner-2'),
        sessionLauncher: _SessionLauncher(),
        nowUtc: () => _now,
        timezoneId: 'Asia/Bangkok',
      );
      Widget app(ReviewCenterUseCases cases) => MaterialApp(
        home: ReviewCenterScreen(
          useCases: cases,
          lessonShellBuilder: _unusedDestination,
        ),
      );
      await tester.pumpWidget(app(_useCases(result: [_item()])));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<MenuActionBinding>(find.byType(MenuActionBinding))
            .map((b) => b.ownerId),
        everyElement('owner-1'),
      );
      await tester.pumpWidget(app(replacement));
      expect(find.byType(MenuActionBinding), findsNothing);
      expect(find.text('station'), findsNothing);
      pending.complete([]);
      await tester.pumpAndSettle();
      final binding = tester.widget<MenuActionBinding>(
        find.byType(MenuActionBinding),
      );
      expect(binding.ownerId, 'owner-2');
      expect(binding.onInvoke, isNull);
      expect(jsonDecode(binding.readValue!)['queueCount'], 0);
    },
  );

  testWidgets(
    'AE disposed pending read observes late failure without retry or context',
    (tester) async {
      final pending = Completer<List<ReviewQueueItem>>();
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewCenterScreen(
            useCases: _useCases(reader: _Reader(load: () => pending.future)),
            lessonShellBuilder: _unusedDestination,
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: Text('parent')));
      pending.completeError(StateError('private read failed'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(MenuActionBinding), findsNothing);
      expect(find.text('parent'), findsOneWidget);
    },
  );

  testWidgets(
    'AE repeated immediate failure stays bounded and retries to empty',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reads = 0;
      final useCases = _useCases(
        reader: _Reader(
          load: () async {
            reads++;
            if (reads < 3) throw StateError('private-owner /private/path');
            return [];
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ReviewCenterScreen(
            useCases: useCases,
            lessonShellBuilder: _unusedDestination,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        expect(find.text('ไม่สามารถโหลดรายการทบทวนได้'), findsOneWidget);
        expect(find.textContaining('private-owner'), findsNothing);
        await tester.tap(find.text('ลองอีกครั้ง'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(reads, 3);
      expect(find.text('ยังไม่มีรายการที่ต้องทบทวน'), findsOneWidget);
    },
  );

  testWidgets('AE duplicate retry callback starts only one pending read', (
    tester,
  ) async {
    var reads = 0;
    final pending = Completer<List<ReviewQueueItem>>();
    final useCases = _useCases(
      reader: _Reader(
        load: () {
          reads++;
          return reads == 1
              ? Future.error(StateError('read unavailable'))
              : pending.future;
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: useCases,
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    retry();
    retry();
    await tester.pump();
    final observedReads = reads;
    pending.complete([_item()]);
    await tester.pumpAndSettle();
    expect(observedReads, 2);
    expect(find.text('station'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final lateError in [false, true]) {
    testWidgets(
      'AE replacement read ignores late old completion error=$lateError',
      (tester) async {
        final pending = Completer<List<ReviewQueueItem>>();
        final original = _useCases(reader: _Reader(load: () => pending.future));
        final replacement = _useCases(result: []);
        Widget app(ReviewCenterUseCases useCases) => MaterialApp(
          home: ReviewCenterScreen(
            useCases: useCases,
            lessonShellBuilder: _unusedDestination,
          ),
        );
        await tester.pumpWidget(app(original));
        await tester.pumpWidget(app(replacement));
        await tester.pump();
        if (lateError) {
          pending.completeError(StateError('old private owner'));
        } else {
          pending.complete([_item()]);
        }
        await tester.pumpAndSettle();
        expect(find.text('ยังไม่มีรายการที่ต้องทบทวน'), findsOneWidget);
        expect(find.text('station'), findsNothing);
        expect(find.text('ไม่สามารถโหลดรายการทบทวนได้'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('AE retained launch callback cannot launch a replacement queue', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    final builder = (ReviewLessonLaunchRequest _) =>
        _lessonDestination(learning: fixture.learning);
    Widget app(ReviewCenterUseCases cases) => MaterialApp(
      home: ReviewCenterScreen(useCases: cases, lessonShellBuilder: builder),
    );
    await tester.pumpWidget(app(fixture.useCases));
    await tester.pumpAndSettle();
    final launch = tester
        .widget<FilledButton>(find.byType(FilledButton))
        .onPressed!;
    await tester.pumpWidget(
      app(
        ReviewCenterUseCases(
          reader: _Reader(load: () async => []),
          ownerIdentities: fixture.useCases.ownerIdentities,
          sessionLauncher: fixture.useCases.sessionLauncher,
          nowUtc: () => _now,
          timezoneId: 'Asia/Bangkok',
        ),
      ),
    );
    await tester.pumpAndSettle();
    launch();
    await tester.pumpAndSettle();
    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    if (find.byType(UnifiedLessonShell).evaluate().isNotEmpty) {
      Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
      await tester.pumpAndSettle();
    }
    expect(sessions, isEmpty);
    expect(find.text('ยังไม่มีรายการที่ต้องทบทวน'), findsOneWidget);
  });

  for (final change in ['useCases', 'builder', 'dispose', 'pop']) {
    testWidgets(
      'AE pending durable launch fences $change before building or attaching',
      (tester) async {
        final fixture = await _durableFixture();
        addTearDown(fixture.database.close);
        final release = Completer<void>();
        final persisted = Completer<void>();
        final delayed = _DelayedSessionLauncher(
          LearningUseCasesReviewSessionLauncher(fixture.learning),
          persisted: persisted,
          release: release,
        );
        final original = ReviewCenterUseCases(
          reader: fixture.useCases.reader,
          ownerIdentities: fixture.useCases.ownerIdentities,
          sessionLauncher: delayed,
          nowUtc: () => _now,
          timezoneId: 'Asia/Bangkok',
        );
        var builds = 0;
        UnifiedLessonShellLease builder(ReviewLessonLaunchRequest _) {
          builds++;
          return _lessonDestination(learning: fixture.learning);
        }

        var replacementBuilds = 0;
        UnifiedLessonShellLease replacementBuilder(
          ReviewLessonLaunchRequest _,
        ) {
          replacementBuilds++;
          throw StateError('replacement must not receive old launch');
        }

        final replacement = _useCases(result: []);
        final navigator = GlobalKey<NavigatorState>();
        Widget screen(
          ReviewCenterUseCases cases,
          ReviewLessonShellBuilder shell,
        ) => ReviewCenterScreen(useCases: cases, lessonShellBuilder: shell);
        Widget app(Widget home) =>
            MaterialApp(navigatorKey: navigator, home: home);
        if (change == 'pop') {
          await tester.pumpWidget(app(const Scaffold(body: Text('parent'))));
          navigator.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => screen(original, builder)),
          );
        } else {
          await tester.pumpWidget(app(screen(original, builder)));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('เริ่มทบทวน'));
        await persisted.future;
        expect(await _activeSessions(fixture.database), hasLength(1));
        if (change == 'pop') {
          navigator.currentState!.pop();
          // Return the start result before reverse transition disposal.
          expect(find.byType(ReviewCenterScreen), findsOneWidget);
        } else if (change == 'dispose') {
          await tester.pumpWidget(app(const Scaffold(body: Text('parent'))));
        } else {
          await tester.pumpWidget(
            app(
              screen(
                change == 'useCases' ? replacement : original,
                change == 'builder' ? replacementBuilder : builder,
              ),
            ),
          );
        }
        release.complete();
        await tester.pumpAndSettle();
        final active = await _activeSessions(fixture.database);
        final pushed = find.byType(UnifiedLessonShell).evaluate().isNotEmpty;
        if (pushed) {
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
        }
        expect(
          active,
          isEmpty,
          reason: 'old launch must be abandoned by its original authority',
        );
        expect(pushed, isFalse);
        expect(builds, 0);
        expect(replacementBuilds, 0);
        expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final connection in ['absent', 'connected', 'disconnected']) {
    for (final correct in [true, false]) {
      testWidgets(
        'review actual choice file reopen $connection correct=$correct',
        (tester) async {
          final directory = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('lexiquest-review-part13-'),
          ))!;
          final file = File('${directory.path}/review.sqlite');
          late _DurableFixture fixture;
          await tester.runAsync(() async {
            fixture = await _durableFixture(file: file);
            await fixture.database
                .into(fixture.database.vocabularyWords)
                .insert(
                  VocabularyWordsCompanion.insert(
                    id: 'word-alternative',
                    ownerId: 'owner-1',
                    categoryId: 'category-1',
                    spelling: 'river',
                    normalizedSpelling: 'river',
                    meaning: 'แม่น้ำ',
                    normalizedMeaning: 'แม่น้ำ',
                    partOfSpeech: 'noun',
                    createdAtUtcMs: 1,
                    updatedAtUtcMs: 1,
                  ),
                );
          });
          var closed = false;
          addTearDown(() async {
            if (!closed) await fixture.database.close();
            await directory.delete(recursive: true);
          });
          String? aiOwner = 'owner-1';
          final registry = MenuActionRegistry(currentOwner: () => aiOwner);
          final controllers = <UnifiedLessonController>[];
          final app = MaterialApp(
            home: ReviewCenterScreen(
              useCases: fixture.useCases,
              lessonShellBuilder: (request) {
                const adapter = MeaningQuizModeAdapter();
                final controller = UnifiedLessonController(
                  learning: fixture.learning,
                  adapter: adapter,
                );
                controllers.add(controller);
                return UnifiedLessonShellLease(
                  controller: controller,
                  learning: fixture.learning,
                  nowUtc: () => _now,
                  builder: (_) => QuizScreen(
                    learning: fixture.learning,
                    evidenceAdapter: CurrentActivityEvidenceAdapter(
                      learning: fixture.learning,
                    ),
                    modeAdapter: adapter,
                    attachedSession: request.session,
                  ),
                );
              },
            ),
          );
          await tester.pumpWidget(
            connection == 'absent'
                ? app
                : MenuActionScope(registry: registry, child: app),
          );
          await _pumpReviewUntil(tester, find.text('เริ่มทบทวน'));
          await tester.tap(find.text('เริ่มทบทวน'));
          final option = find.byKey(
            ValueKey(
              'meaning-quiz-option-word-1-${correct ? 'สถานี' : 'แม่น้ำ'}',
            ),
          );
          await _pumpReviewUntil(tester, option);
          final state = tester.state(find.byType(QuizScreen));
          expect(controllers, hasLength(1));
          expect(controllers.single.state.sessionId, 'session:review-1');
          if (connection != 'absent') {
            final contexts = registry.snapshot()['context'] as List;
            expect(
              contexts.where(
                (dynamic row) =>
                    (row['id'] as String).startsWith('review/queue'),
              ),
              isEmpty,
            );
            expect(
              contexts.any(
                (dynamic row) =>
                    row['id'] == 'quiz/current-question-assistance',
              ),
              isTrue,
            );
          }
          if (connection == 'disconnected') {
            aiOwner = null;
            registry.invalidateSession(preserveContext: true);
            await tester.pump();
            expect(registry.snapshot()['context'], isEmpty);
          }
          expect(tester.state(find.byType(QuizScreen)), same(state));
          expect(tester.widget<FilledButton>(option).onPressed, isNotNull);
          await tester.ensureVisible(option);
          await tester.tap(option);
          await _pumpReviewUntil(
            tester,
            find.byKey(const ValueKey('answer-feedback-panel')),
          );
          await tester.runAsync(() async {
            final attempts = await fixture.database
                .select(fixture.database.answerAttempts)
                .get();
            expect(attempts, hasLength(1));
            expect(attempts.single.ownerId, 'owner-1');
            expect(attempts.single.sessionId, 'session:review-1');
            expect(attempts.single.isCorrect, correct);
            expect(
              attempts.single.evidenceClass,
              EvidenceClass.recognition.name,
            );
            expect(
              await fixture.database.select(fixture.database.srsStates).get(),
              isEmpty,
            );
          });
          expect(controllers.single.state.committedResponseCount, 1);
          if (connection == 'connected') {
            final context =
                jsonDecode(
                      (registry.snapshot()['context'] as List).singleWhere(
                            (dynamic row) =>
                                row['id'] == 'quiz/current-question-assistance',
                          )['value']
                          as String,
                    )
                    as Map;
            expect(context['phase'], 'answered');
            expect(registry.snapshot()['actions'], isEmpty);
            aiOwner = 'foreign-owner';
            expect(registry.snapshot()['context'], isEmpty);
            aiOwner = 'owner-1';
          } else {
            expect(registry.snapshot()['context'], isEmpty);
          }

          final next = find.byKey(const ValueKey('meaning-quiz-next'));
          await tester.ensureVisible(next);
          await tester.tap(next);
          var completed = false;
          for (var i = 0; i < 100 && !completed; i++) {
            await tester.pump(const Duration(milliseconds: 30));
            await tester.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 5));
              final sessions = await fixture.database
                  .select(fixture.database.learningSessions)
                  .get();
              completed = sessions.single.state == 'completed';
            });
          }
          expect(completed, isTrue);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.runAsync(() async {
            final before = await _reviewTableSnapshot(fixture.database);
            await fixture.database.close();
            closed = true;
            final reopened = AppDatabase(NativeDatabase(file));
            try {
              expect(await _reviewTableSnapshot(reopened), before);
              final attempts = await reopened
                  .select(reopened.answerAttempts)
                  .get();
              expect(attempts, hasLength(1));
              expect(attempts.single.isCorrect, correct);
              expect(
                (await reopened.select(reopened.learningSessions).get())
                    .single
                    .state,
                'completed',
              );
            } finally {
              await reopened.close();
            }
          });
        },
      );
    }
  }

  for (final connection in ['absent', 'connected', 'disconnectBeforeAnswer']) {
    testWidgets('review durable answer and route context $connection', (
      tester,
    ) async {
      final fixture = await _durableFixture();
      addTearDown(fixture.database.close);
      String? aiOwner = 'owner-1';
      final registry = MenuActionRegistry(currentOwner: () => aiOwner);
      final controllers = <UnifiedLessonController>[];
      final app = MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) => _lessonDestination(
            learning: fixture.learning,
            controllers: controllers,
          ),
        ),
      );
      await tester.pumpWidget(
        connection == 'absent'
            ? app
            : MenuActionScope(registry: registry, child: app),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();
      final controller = controllers.single;
      if (connection != 'absent') {
        final contexts = registry.snapshot()['context'] as List;
        expect(
          contexts.where(
            (dynamic row) => (row['id'] as String).startsWith('review/queue'),
          ),
          isEmpty,
        );
        expect(
          contexts.any((dynamic row) => row['id'] == 'lesson/assistance'),
          isTrue,
        );
      }
      if (connection == 'disconnectBeforeAnswer') {
        aiOwner = null;
        expect(registry.snapshot()['context'], isEmpty);
      }
      final result = await controller.submit(
        LessonSubmission(
          response: LessonResponse(
            sourceEvidenceId: 'review-connection-answer',
            occurredAtUtc: _now.add(const Duration(seconds: 1)),
            sessionId: controller.state.sessionId!,
            wordId: 'word-1',
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: 1000,
            attemptNumber: 1,
            feedbackContext: const AnswerFeedbackContext(
              canonicalCorrectAnswer: 'สถานี',
            ),
          ),
          support: LessonSupport(
            evidenceContext: EvidenceContext.legacyCompatibility(
              evidenceClass: EvidenceClass.recognition,
              skillId: 'meaningRecognition',
              hintLevel: 0,
              contentRevision: '1',
              engagementAllowed: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(result.inserted, isTrue);
      expect(controller.state.committedResponseCount, 1);
      final attempts = await fixture.database
          .select(fixture.database.answerAttempts)
          .get();
      expect(attempts, hasLength(1));
      expect(attempts.single.isCorrect, isTrue);
      expect(
        await fixture.database.select(fixture.database.srsStates).get(),
        isEmpty,
      );
      if (connection != 'absent') {
        aiOwner = 'owner-1';
        final contexts = registry.snapshot()['context'] as List;
        final context = jsonDecode(
          contexts.singleWhere(
                (dynamic row) => row['id'] == 'lesson/assistance',
              )['value']
              as String,
        );
        expect(context['committedResponses'], 1);
        expect(context['lastCommittedFeedback']['correctAnswer'], 'สถานี');
        expect(context['lastCommittedFeedback']['isCorrect'], isTrue);
        expect(registry.snapshot()['actions'], isEmpty);
      }
      Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
      await tester.pumpAndSettle();
      expect(find.text('เริ่มทบทวน'), findsOneWidget);
      final contexts = registry.snapshot()['context'] as List;
      expect(
        contexts.where(
          (dynamic row) => (row['id'] as String).startsWith('lesson/'),
        ),
        isEmpty,
      );
      if (connection != 'absent') {
        expect(
          contexts.any((dynamic row) => row['id'] == 'review/queue-summary'),
          isTrue,
        );
      }
      expect(
        await fixture.database.select(fixture.database.answerAttempts).get(),
        hasLength(1),
      );
    });
  }
  for (final empty in [false, true]) {
    testWidgets(
      'optional review context preserves owner and reasons empty=$empty',
      (tester) async {
        String? owner = 'owner-1';
        final registry = MenuActionRegistry(currentOwner: () => owner);
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: MaterialApp(
              home: ReviewCenterScreen(
                useCases: _useCases(
                  result: empty ? [] : [_item(allReasons: true)],
                ),
                lessonShellBuilder: _unusedDestination,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final contexts = registry.snapshot()['context'] as List;
        final summary = jsonDecode(
          contexts.singleWhere(
                (dynamic x) => x['id'] == 'review/queue-summary',
              )['value']
              as String,
        );
        expect(summary['queueCount'], empty ? 0 : 1);
        expect(summary['dueSrsCount'], empty ? 0 : 1);
        if (!empty) {
          final item = jsonDecode(
            contexts.singleWhere(
                  (dynamic x) => x['id'] == 'review/queue/0',
                )['value']
                as String,
          );
          expect(item['spelling'], 'station');
          expect(
            item['reasons'],
            containsAll(['dueSrs', 'incorrectAnswer', 'reported', 'saved']),
          );
          expect(item['primaryReason'], 'dueSrs');
          expect(item.containsKey('sourceId'), false);
        }
        expect(registry.snapshot()['actions'], isEmpty);
        owner = 'owner-2';
        expect(registry.snapshot()['context'], isEmpty);
      },
    );
  }
  testWidgets('reloads canonical review queue after returning from practice', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    var loads = 0;
    final useCases = ReviewCenterUseCases(
      reader: _Reader(
        load: () async {
          loads += 1;
          return loads == 1 ? [_item()] : [];
        },
      ),
      ownerIdentities: fixture.useCases.ownerIdentities,
      sessionLauncher: fixture.useCases.sessionLauncher,
      nowUtc: fixture.useCases.nowUtc,
      timezoneId: fixture.useCases.timezoneId,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: fixture.learning, controllers: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedLessonShell), findsOneWidget);
    Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(find.text('ยังไม่มีรายการที่ต้องทบทวน'), findsOneWidget);
    expect(find.text('station'), findsNothing);
  });

  testWidgets('presents every typed reason and source detail', (tester) async {
    final item = _item(allReasons: true);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: _useCases(result: [item]),
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'ศูนย์ทบทวน'), findsOneWidget);
    expect(find.text('ถึงกำหนด SRS'), findsOneWidget);
    expect(find.text('เคยตอบผิด'), findsOneWidget);
    expect(find.text('รายงานไว้: คำตอบ'), findsOneWidget);
    expect(find.text('บันทึกไว้'), findsOneWidget);
    expect(find.text('station'), findsOneWidget);
    expect(find.text('สถานี'), findsOneWidget);
  });

  testWidgets('exposes labelled loading state', (tester) async {
    final pending = Completer<List<ReviewQueueItem>>();
    final reader = _Reader(load: () => pending.future);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: _useCases(reader: reader),
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('กำลังโหลดรายการทบทวน'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(const []);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('renders an accessible empty state', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: _useCases(result: const []),
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่มีรายการที่ต้องทบทวน'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('รายการทบทวนว่าง')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shows a bounded error and retries on explicit action', (
    tester,
  ) async {
    var calls = 0;
    final item = _item();
    final reader = _Reader(
      load: () async {
        calls += 1;
        if (calls == 1) throw StateError('offline');
        return [item];
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: _useCases(reader: reader),
          lessonShellBuilder: _unusedDestination,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถโหลดรายการทบทวนได้'), findsOneWidget);
    expect(find.text('ลองอีกครั้ง'), findsOneWidget);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('station'), findsOneWidget);
  });

  testWidgets('supports 200 percent text without overflow', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: ReviewCenterScreen(
            useCases: _useCases(result: [_item(allReasons: true)]),
            lessonShellBuilder: _unusedDestination,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('station'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('เริ่มทบทวน'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('เริ่มทบทวน'), findsOneWidget);
  });

  testWidgets(
    'launches one fresh deterministic session through Unified Lesson shell',
    (tester) async {
      final fixture = await _durableFixture();
      addTearDown(fixture.database.close);
      final controllers = <UnifiedLessonController>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewCenterScreen(
            useCases: fixture.useCases,
            lessonShellBuilder: (_) => _lessonDestination(
              learning: fixture.learning,
              controllers: controllers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.tap(find.text('เริ่มทบทวน'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(controllers, hasLength(1));
      expect(controllers.single.state.sessionId, 'session:review-1');
      expect(find.byType(UnifiedLessonShell), findsOneWidget);
      expect(find.text('session session:review-1'), findsOneWidget);

      Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
      await tester.pumpAndSettle();
      final retired = await fixture.database
          .select(fixture.database.learningSessions)
          .get();
      expect(retired.single.state, 'abandoned');
      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();

      expect(controllers, hasLength(2));
      expect(controllers.last.state.sessionId, 'session:review-2');
    },
  );

  testWidgets(
    'launch persists one exact pinned canonical session before learner action',
    (tester) async {
      final fixture = await _durableFixture();
      addTearDown(fixture.database.close);
      final controllers = <UnifiedLessonController>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewCenterScreen(
            useCases: fixture.useCases,
            lessonShellBuilder: (_) => _lessonDestination(
              learning: fixture.learning,
              controllers: controllers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();

      final sessions = await fixture.database
          .select(fixture.database.learningSessions)
          .get();
      expect(sessions, hasLength(1));
      expect(sessions.single.id, 'session:review-1');
      expect(sessions.single.ownerId, 'owner-1');
      expect(sessions.single.activityType, 'reviewCenter');
      expect(sessions.single.state, 'active');
      expect(controllers.single.state.sessionId, sessions.single.id);
      expect(controllers.single.state.itemCount, 1);
      expect(
        await fixture.database.select(fixture.database.answerAttempts).get(),
        isEmpty,
      );
      expect(
        await fixture.database.select(fixture.database.eventsV2).get(),
        isEmpty,
      );
      expect(
        await fixture.database.select(fixture.database.srsStates).get(),
        isEmpty,
      );
      expect(
        await fixture.database
            .select(fixture.database.pointsLedgerEntries)
            .get(),
        isEmpty,
      );
      expect(
        await fixture.database
            .select(fixture.database.rewardTransactions)
            .get(),
        isEmpty,
      );
    },
  );

  testWidgets(
    'successful launch builds the shell from a returned immutable queue item',
    (tester) async {
      final fixture = await _durableFixture();
      addTearDown(fixture.database.close);
      final item = _item();
      ReviewQueueItem? builderItem;
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewCenterScreen(
            useCases: ReviewCenterUseCases(
              reader: _Reader(load: () async => [item]),
              ownerIdentities: const _OwnerIdentities(),
              sessionLauncher: LearningUseCasesReviewSessionLauncher(
                fixture.learning,
              ),
              nowUtc: () => _now,
              timezoneId: 'Asia/Bangkok',
            ),
            lessonShellBuilder: (request) {
              builderItem = request.item;
              return _lessonDestination(learning: fixture.learning);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('เริ่มทบทวน'));
      await tester.pumpAndSettle();

      expect(builderItem, isNotNull);
      expect(identical(builderItem, item), isFalse);
      expect(identical(builderItem!.snapshot, item.snapshot), isFalse);
      expect(builderItem!.identity, item.identity);
      expect(builderItem!.spelling, item.spelling);
      expect(builderItem!.meaning, item.meaning);
      expect(find.byType(UnifiedLessonShell), findsOneWidget);
    },
  );

  testWidgets('builder throw leaves no active durable session', (tester) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) => throw StateError('builder failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsOneWidget);
    expect(
      await _activeSessions(fixture.database),
      isEmpty,
      reason: 'a widget builder failure must compensate its durable session',
    );
  });

  testWidgets('different learning authority compensates the validated launch', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    var otherId = 0;
    final otherLearning = LearningUseCases(
      owners: const _Owners(),
      repository: DriftLearningRepository(fixture.database),
      generateId: () => 'other-${++otherId}',
      nowUtc: () => _now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'other'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: otherLearning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsOneWidget);
    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    expect(sessions, hasLength(1));
    expect(sessions.single.state, 'abandoned');
    expect(await _activeSessions(fixture.database), isEmpty);
  });

  testWidgets('configuration mismatch compensates failed attachment', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) => _lessonDestination(
            learning: fixture.learning,
            configuration: _sessionConfiguration(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    expect(sessions, hasLength(1));
    expect(sessions.single.state, 'abandoned');
    expect(await _activeSessions(fixture.database), isEmpty);
    expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsOneWidget);
  });

  testWidgets('unmount during durable start compensates the returned session', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    final release = Completer<void>();
    final persisted = Completer<void>();
    final delayed = _DelayedSessionLauncher(
      LearningUseCasesReviewSessionLauncher(fixture.learning),
      persisted: persisted,
      release: release,
    );
    final useCases = ReviewCenterUseCases(
      reader: _Reader(load: () async => [_item()]),
      ownerIdentities: DriftReviewOwnerIdentityReader(fixture.database),
      sessionLauncher: delayed,
      nowUtc: () => _now,
      timezoneId: 'Asia/Bangkok',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: fixture.learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await persisted.future;
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    release.complete();
    await tester.pumpAndSettle();

    expect(await _activeSessions(fixture.database), isEmpty);
  });

  testWidgets('returned controller attaches to the exact durable session', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    late UnifiedLessonController controller;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) {
            final controllers = <UnifiedLessonController>[];
            final destination = _lessonDestination(
              learning: fixture.learning,
              controllers: controllers,
            );
            controller = controllers.single;
            return destination;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();
    final durable = (await _activeSessions(fixture.database)).single;

    expect(controller.state.sessionId, durable.id);
    expect(controller.state.status, LessonSessionStatus.active);
  });

  testWidgets('negative launch clock fails before session persistence', (
    tester,
  ) async {
    var now = _now;
    final fixture = await _durableFixture(nowUtc: () => now);
    addTearDown(fixture.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: fixture.learning),
        ),
      ),
    );
    await tester.pumpAndSettle();
    now = DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true);

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถเริ่มการทบทวนได้'), findsOneWidget);
    expect(find.text('ไม่สามารถโหลดรายการทบทวนได้'), findsOneWidget);
    expect(find.text('station'), findsNothing);
    now = _now;
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.text('station'), findsOneWidget);
    expect(
      await fixture.database.select(fixture.database.learningSessions).get(),
      isEmpty,
    );
  });

  testWidgets('retired reused lease compensates every later session', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    UnifiedLessonShellLease? reused;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) =>
              reused ??= _lessonDestination(learning: fixture.learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();

    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    expect(sessions, hasLength(2));
    expect(sessions.map((session) => session.state), everyElement('abandoned'));
    expect(await _activeSessions(fixture.database), isEmpty);
  });

  testWidgets('route retirement closes the pinned owner after owner switch', (
    tester,
  ) async {
    final fixture = await _durableFixture();
    addTearDown(fixture.database.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewCenterScreen(
          useCases: fixture.useCases,
          lessonShellBuilder: (_) =>
              _lessonDestination(learning: fixture.learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('เริ่มทบทวน'));
    await tester.pumpAndSettle();
    await _switchToOwnerTwo(fixture.database);
    await fixture.database
        .into(fixture.database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'owner-2-active',
            ownerId: 'owner-2',
            activityType: 'quiz',
            state: 'active',
            startedAtUtcMs: _now.millisecondsSinceEpoch,
            appVersion: 'test',
            buildId: 'owner-2',
          ),
        );

    Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
    await tester.pumpAndSettle();

    final sessions = await fixture.database
        .select(fixture.database.learningSessions)
        .get();
    final review = sessions.singleWhere(
      (session) => session.id == 'session:review-1',
    );
    final ownerTwo = sessions.singleWhere(
      (session) => session.id == 'owner-2-active',
    );
    expect(review.state, 'abandoned');
    expect(ownerTwo.state, 'active');
  });

  test('review remains a child of composed Today with live route gating', () {
    final record = allTcasIdeaIntegrationCatalog.records.singleWhere(
      (candidate) => candidate.id == FeatureContractId.f22,
    );
    final todayHubRecord = allTcasIdeaIntegrationCatalog.records.singleWhere(
      (candidate) => candidate.id == FeatureContractId.f42,
    );
    final mainNavigation = File(
      'lib/screens/main_navigation_screen.dart',
    ).readAsStringSync();
    final todayHubView = File(
      'lib/screens/today_hub_view.dart',
    ).readAsStringSync();
    final productionEntryIds = RegExp(r"productionEntryId: '([^']+)'")
        .allMatches(mainNavigation)
        .map((match) => match.group(1))
        .whereType<String>()
        .toSet();
    final drawerKeys = RegExp(r"ValueKey<String>\('([^']+)'\)")
        .allMatches(mainNavigation)
        .map((match) => match.group(1))
        .whereType<String>()
        .where((key) => key.startsWith('drawer/'))
        .toSet();
    final todayHubBuilderStart = mainNavigation.indexOf(
      'Widget _buildTodayHub(BuildContext context,',
    );
    expect(todayHubBuilderStart, greaterThanOrEqualTo(0));
    final todayHubBuilderEnd = mainNavigation.indexOf(
      'Future<void> _resumeFromToday',
      todayHubBuilderStart,
    );
    expect(todayHubBuilderEnd, greaterThan(todayHubBuilderStart));
    final todayHubBuilder = mainNavigation.substring(
      todayHubBuilderStart,
      todayHubBuilderEnd,
    );
    final todayActionsStart = mainNavigation.indexOf(
      '_MainNavigationTodayHubActions _todayActions({',
    );
    expect(todayActionsStart, greaterThanOrEqualTo(0));
    final todayActionsEnd = mainNavigation.indexOf(
      'Widget _gate(',
      todayActionsStart,
    );
    expect(todayActionsEnd, greaterThan(todayActionsStart));
    final todayActions = mainNavigation.substring(
      todayActionsStart,
      todayActionsEnd,
    );

    expect(record.dependencies, contains(FeatureContractId.f20));
    expect(record.dependencies, contains(FeatureContractId.f21));
    expect(todayHubRecord.dependencies, contains(FeatureContractId.f22));
    // S01-AA makes Today primary; review remains its gated child.
    expect(productionEntryIds, contains('home/today'));
    expect(
      RegExp(
        r"void _openToday\(\) => _pushFeatureDestination\(\s*"
        r"'home/today',\s*Feature\.dailyContinuity,\s*_buildTodayHub,",
      ).hasMatch(mainNavigation),
      isTrue,
    );
    expect(productionEntryIds, isNot(contains('home/today/review')));
    expect(productionEntryIds, isNot(contains('home/review')));
    expect(drawerKeys, isNot(contains('drawer/review/center')));
    expect(
      todayHubView,
      contains("key: const ValueKey('today-hub-open-review')"),
    );
    expect(
      RegExp(
        r'widget\.actions\.openReview\(\s*'
        r'_dependencyReady\(snapshot, TodayHubDependency\.review\)\s*'
        r'\? snapshot\.reviewWork\s*'
        r': const <TodayHubReviewWorkItem>\[\],\s*\)',
      ).hasMatch(todayHubView),
      isTrue,
      reason: 'Only ready canonical review work may enter the composed action',
    );
    expect(todayHubBuilder, contains('_todayActions('));
    expect(todayHubBuilder, contains('actions: actions(null)'));
    expect(todayHubBuilder, contains('bindActions: actions'));
    expect(todayHubBuilder, contains('viewIsCurrent?.call() != false'));
    expect(
      todayHubBuilder,
      contains('fromTodayRoute: embedded ? null : context,'),
    );
    expect(
      todayActions,
      contains('if (isCurrent?.call() != false) await _openTodayReview(work);'),
    );
    expect(
      todayHubBuilder,
      contains('hasComposedDependencyFor(Feature.dailyContinuity)'),
    );
    expect(todayHubBuilder, contains('ProductionFeatureUnavailable'));
    expect(
      todayHubBuilder,
      contains('ProductionFeatureUnavailableReason.missingDependency'),
    );
    expect(
      RegExp(
        r"_pushFeatureDestination\(\s*'home/today/review',\s*"
        r'Feature\.dailyContinuity,',
      ).hasMatch(mainNavigation),
      isTrue,
    );
    expect(mainNavigation, contains('ReviewCenterScreen('));
  });
}

ReviewCenterUseCases _useCases({
  List<ReviewQueueItem>? result,
  ReviewCenterReader? reader,
  ReviewSessionLauncher? sessionLauncher,
}) => ReviewCenterUseCases(
  reader: reader ?? _Reader(load: () async => result ?? const []),
  ownerIdentities: const _OwnerIdentities(),
  sessionLauncher: sessionLauncher ?? _SessionLauncher(),
  nowUtc: () => DateTime.utc(2026, 8, 28, 12),
  timezoneId: 'Asia/Bangkok',
);

UnifiedLessonShellLease _unusedDestination(ReviewLessonLaunchRequest _) =>
    throw StateError('launch is not expected in this test');

UnifiedLessonShellLease _lessonDestination({
  required LearningUseCases learning,
  List<UnifiedLessonController>? controllers,
  SessionConfiguration? configuration,
}) {
  final controller = UnifiedLessonController(
    learning: learning,
    adapter: const _ReviewLessonAdapter(),
  );
  if (configuration != null) {
    controller.bindSessionConfiguration(
      configuration,
      revalidate: (candidate) async => candidate,
    );
  }
  controllers?.add(controller);
  return UnifiedLessonShellLease(
    controller: controller,
    learning: learning,
    nowUtc: () => _now,
    builder: (_) => Scaffold(
      body: Center(child: Text('session ${controller.state.sessionId}')),
    ),
  );
}

ReviewQueueItem _item({bool allReasons = false}) => ReviewQueueItem(
  snapshot: ReviewedLexicalContentSnapshot(
    identity: const ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: 'word-1',
      revision: 1,
    ),
    categoryId: 'category-1',
    spelling: 'station',
    normalizedSpelling: 'station',
    meaning: 'สถานี',
    normalizedMeaning: 'สถานี',
    partOfSpeech: 'noun',
    cefrLevel: null,
    source: 'manual',
    isGlobal: false,
    coreChecksumSha256: _canonicalChecksum(
      spelling: 'station',
      meaning: 'สถานี',
    ),
    provenance: ContentProvenance.userAuthored,
    reviewState: ContentReviewState.unreviewed,
    publicationState: ContentPublicationState.private,
    artifact: null,
  ),
  provenance: [
    if (allReasons)
      ReviewReasonProvenance.due(
        sourceId: 'srs-1',
        dueAtUtc: DateTime.utc(2026, 8, 28, 12),
      ),
    if (allReasons)
      ReviewReasonProvenance.incorrect(
        sourceId: 'attempt-1',
        occurredAtUtc: DateTime.utc(2026, 8, 27, 12),
      ),
    if (allReasons)
      ReviewReasonProvenance.reported(
        sourceId: 'report-1',
        occurredAtUtc: DateTime.utc(2026, 8, 27, 13),
        reportReason: ContentReportReason.answer,
      ),
    ReviewReasonProvenance.saved(
      sourceId: 'saved-1',
      occurredAtUtc: DateTime.utc(2026, 8, 27, 14),
    ),
  ],
);

final class _Reader implements ReviewCenterReader {
  const _Reader({required this.load});

  final Future<List<ReviewQueueItem>> Function() load;

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) => load();
}

final class _Owners implements LocalOwnerRepository {
  const _Owners();

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner-1',
        createdAtUtc: DateTime.utc(2026, 8, 28),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _OwnerIdentities implements ReviewOwnerIdentityReader {
  const _OwnerIdentities();

  @override
  Future<String> requireSingleActiveOwnerId() async => 'owner-1';
}

final class _SessionLauncher implements ReviewSessionLauncher {
  final Object _authorityIdentity = Object();
  var _nextId = 0;

  @override
  Object get authorityIdentity => _authorityIdentity;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) async => PinnedReviewSessionLaunch(
    session: QuizSession(
      id: 'review-${++_nextId}',
      ownerId: ownerId,
      startedAtUtc: _now,
      questions: [
        for (final snapshot in items)
          QuizQuestion(
            word: QuizWord(
              id: snapshot.identity.id,
              categoryId: snapshot.categoryId,
              spelling: snapshot.spelling,
              meaning: snapshot.meaning,
              partOfSpeech: snapshot.partOfSpeech,
              cefrLevel: snapshot.cefrLevel,
              normalizedSpelling: snapshot.normalizedSpelling,
              normalizedMeaning: snapshot.normalizedMeaning,
              contentRevision: snapshot.identity.revision,
              contentChecksumSha256: snapshot.coreChecksumSha256,
            ),
            options: [snapshot.meaning],
          ),
      ],
    ),
    content: items,
  );

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {}
}

final class _DelayedSessionLauncher implements ReviewSessionLauncher {
  const _DelayedSessionLauncher(
    this.delegate, {
    required this.persisted,
    required this.release,
  });

  final ReviewSessionLauncher delegate;
  final Completer<void> persisted;
  final Completer<void> release;

  @override
  Object get authorityIdentity => delegate.authorityIdentity;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) async {
    final session = await delegate.start(ownerId: ownerId, items: items);
    persisted.complete();
    await release.future;
    return session;
  }

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) => delegate.abandon(
    ownerId: ownerId,
    sessionId: sessionId,
    abandonedAtUtc: abandonedAtUtc,
  );
}

final class _ReviewLessonAdapter implements LessonModeAdapter {
  const _ReviewLessonAdapter();

  @override
  LessonMode get mode => LessonMode.meaningQuiz;

  @override
  EvidenceContext classify(LessonResponse response, LessonSupport support) =>
      support.evidenceContext;

  @override
  Future<LessonItem> next(LessonCursor cursor) async =>
      const LessonItem(id: 'word-1');
}

final class _PendingTimeRepository implements LearningTimeRepository {
  _PendingTimeRepository(this.entered, this.release);
  final Completer<void> entered;
  final Completer<void> release;
  @override
  Future<void> append(LearningTimeSegment segment) async {}
  @override
  Future<Duration> activeDuration(String sessionId) async {
    entered.complete();
    await release.future;
    return Duration.zero;
  }
}

final class _NamedReviewOwner implements ReviewOwnerIdentityReader {
  const _NamedReviewOwner(this.owner);
  final String owner;
  @override
  Future<String> requireSingleActiveOwnerId() async => owner;
}

final class _ReadReviewOwner implements ReviewOwnerIdentityReader {
  const _ReadReviewOwner(this.read);
  final Future<String> Function() read;
  @override
  Future<String> requireSingleActiveOwnerId() => read();
}

final class _DurableFixture {
  const _DurableFixture({
    required this.database,
    required this.learning,
    required this.useCases,
  });

  final AppDatabase database;
  final LearningUseCases learning;
  final ReviewCenterUseCases useCases;
}

Future<_DurableFixture> _durableFixture({
  DateTime Function()? nowUtc,
  File? file,
}) async {
  final clock = nowUtc ?? () => _now;
  final database = AppDatabase(
    file == null ? NativeDatabase.memory() : NativeDatabase(file),
  );
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: 'owner-1',
          createdAtUtcMs: _now.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-1',
          ownerId: 'owner-1',
          name: 'review',
          normalizedName: 'review',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-1',
          ownerId: 'owner-1',
          categoryId: 'category-1',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          contentRevision: const Value(1),
          contentChecksumSha256: Value(
            _canonicalChecksum(spelling: 'station', meaning: 'สถานี'),
          ),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  var nextId = 0;
  final learning = LearningUseCases(
    owners: DriftLocalOwnerRepository(
      database,
      generateId: () => 'generated-owner',
      nowUtc: clock,
    ),
    repository: DriftLearningRepository(database),
    generateId: () => 'review-${++nextId}',
    nowUtc: clock,
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'f22-test'),
  );
  final useCases = ReviewCenterUseCases(
    reader: _Reader(load: () async => [_item()]),
    ownerIdentities: DriftReviewOwnerIdentityReader(database),
    sessionLauncher: LearningUseCasesReviewSessionLauncher(learning),
    nowUtc: clock,
    timezoneId: 'Asia/Bangkok',
  );
  return _DurableFixture(
    database: database,
    learning: learning,
    useCases: useCases,
  );
}

Future<void> _switchToOwnerTwo(AppDatabase database) async {
  await database.transaction(() async {
    await (database.update(database.localOwners)
          ..where((row) => row.id.equals('owner-1')))
        .write(const LocalOwnersCompanion(isActive: Value(false)));
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-2',
            createdAtUtcMs: _now.millisecondsSinceEpoch,
          ),
        );
  });
}

Future<List<LearningSession>> _activeSessions(AppDatabase database) =>
    (database.select(
      database.learningSessions,
    )..where((row) => row.state.equals('active'))).get();

String _canonicalChecksum({
  required String spelling,
  required String meaning,
}) => ContentQualityPolicy.vocabularyChecksumSha256(
  categoryId: 'category-1',
  spelling: spelling,
  normalizedSpelling: spelling,
  meaning: meaning,
  normalizedMeaning: meaning,
  partOfSpeech: 'noun',
  cefrLevel: null,
  source: 'manual',
  isGlobal: false,
);

SessionConfiguration _sessionConfiguration() => SessionConfiguration.validated(
  schemaVersion: sessionConfigurationSchemaVersion,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'owner-1',
  mode: LessonMode.meaningQuiz,
  itemCount: 1,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 0,
  timing: const SessionTiming.timed(Duration(minutes: 1)),
  packIdentity: null,
  protocolId: 'protocol:test',
  protocolVersion: '1',
  protocolLimitsIdentity: 'authority:test',
);

final _now = DateTime.utc(2026, 8, 28, 12);

Future<void> _pumpReviewUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(finder, findsOneWidget);
}

Future<Map<String, List<String>>> _reviewTableSnapshot(
  AppDatabase database,
) async {
  final tables = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  final snapshot = <String, List<String>>{};
  for (final table in tables) {
    final name = table.read<String>('name');
    final rows = await database.customSelect('SELECT * FROM "$name"').get();
    snapshot[name] = rows.map((row) => jsonEncode(row.data)).toList()..sort();
  }
  return snapshot;
}
