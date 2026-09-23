import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/history/application/learning_history_use_cases.dart';
import 'package:vocab_learning_app/features/history/data/drift_learning_history_reader.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/history/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_history_projection.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_session_purpose.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';

import '../features/learning/pair_matching/pair_matching_evidence_contract_test.dart'
    show PairHarness;
import '../features/learning/pair_matching/pair_matching_source_composer_test.dart'
    as pair_fixture;

void main() {
  for (final sample in <(LessonMode, String)>[
    (LessonMode.flashcard, 'บัตรคำใช้การประเมินความจำด้วยตนเอง ไม่ใช่คะแนนสอบ'),
    (LessonMode.meaningQuiz, 'กิจกรรมเลือกจำแนกคำตอบจากตัวเลือก'),
    (LessonMode.definitionQuiz, 'กิจกรรมเลือกจำแนกคำตอบจากตัวเลือก'),
    (LessonMode.cloze, 'กิจกรรมตอบคำถามจากบริบทของประโยค'),
    (
      LessonMode.associativeReading,
      'การอ่านเป็นการสัมผัสภาษา ไม่ใช่คะแนนความถูกต้อง',
    ),
    (
      LessonMode.cefrReading,
      'การอ่านเป็นการสัมผัสภาษา ไม่ใช่คะแนนความถูกต้อง',
    ),
  ]) {
    testWidgets('R15 history explains ${sample.$1.name} evidence', (
      tester,
    ) async {
      String? owner = 'owner:history';
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: _app(
            reader: _Reader([
              _entry(
                sessionId: 'semantic-history',
                mode: sample.$1,
                state: LearningHistoryTerminalState.completed,
                packTitle: null,
                localWordSet: true,
                duration: const Duration(minutes: 1),
                startedAtUtc: DateTime.utc(2026, 9, 13),
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(sample.$2), findsOneWidget);
      expect(find.textContaining('100%'), findsNothing);
      final context = registry.snapshot()['context'] as List;
      final data =
          jsonDecode(context.single['value'] as String) as Map<String, dynamic>;
      expect(data['mode'], sample.$1.name);
      expect(data['state'], 'completed');
      expect(data['interpretation'], sample.$2);
      expect(data['firstAnswers']['total'], 0);
      expect(data.containsKey('score'), isFalse);
      expect(registry.snapshot()['actions'], isEmpty);
      owner = 'other';
      expect(registry.snapshot()['context'], isEmpty);
    });
  }

  testWidgets(
    'local CEFR history explains missing title without enabling replay',
    (tester) async {
      final entry = _entry(
        sessionId: 'local-cefr-history',
        mode: LessonMode.cefrReading,
        state: LearningHistoryTerminalState.completed,
        packTitle: null,
        localWordSet: true,
        duration: const Duration(minutes: 1),
        startedAtUtc: DateTime.utc(2026, 9, 12),
      );
      await tester.pumpWidget(_app(reader: _Reader([entry]), textScale: 2));
      await tester.pumpAndSettle();
      expect(find.text('กิจกรรมอ่านตามระดับ CEFR'), findsOneWidget);
      expect(
        find.text(entry.localCefrPresentation!.detailThai),
        findsOneWidget,
      );
      expect(find.text('เนื้อหาที่บันทึกไว้ไม่พร้อมใช้งาน'), findsNothing);
      expect(
        find.byKey(const ValueKey('replay-history-local-cefr-history')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'canonical completed normal and replay survive abandoned Pair in one bounded History page',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final normal = _pairOperation(
        ownerId: 'synthetic-owner',
        token: 'mixed-normal',
        createdAtUtc: DateTime.utc(2026, 9, 5),
      );
      final h = PairHarness(
        pinnedPlan: normal.plan,
        launchId: normal.launchOperationId,
      );
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      await _finishPairOperation(
        harness: h,
        operation: normal,
        alreadyStarted: true,
      );
      final replay = _pairOperation(
        ownerId: h.owner,
        token: 'mixed-replay',
        createdAtUtc: DateTime.utc(2026, 9, 5, 0, 1),
        purpose: PairSessionPurpose.practiceReplay,
        sourceSessionId: normal.plan.learningSessionId,
        shuffleSeed: 101,
      );
      await _finishPairOperation(harness: h, operation: replay);
      final stopped = _pairOperation(
        ownerId: h.owner,
        token: 'mixed-stopped',
        createdAtUtc: DateTime.utc(2026, 9, 5, 0, 2),
        configured: true,
      );
      await PairMatchingAtomicStartAdapter(
        repository: h.real,
        capability: InternalPairMatchingCapability(
          allowlist: PairCuratedAllowlist(
            version: stopped.plan.allowlistVersion,
            items: stopped.plan.orderedLexicalItems,
          ),
          isEnabled: () => true,
        ),
      ).startMeasured(stopped);
      final consumed = stopped.configuration!.timing.maximumActiveEffort!;
      for (var i = 0; i < 2; i++) {
        await h.real.addSessionConfigurationActiveEffort(
          ownerId: h.owner,
          sessionId: stopped.plan.learningSessionId,
          configurationIdentity: stopped.configuration!.contentIdentity,
          delta: const Duration(minutes: 5),
        );
      }
      await h.real.abandonSession(
        ownerId: h.owner,
        sessionId: stopped.plan.learningSessionId,
        abandonedAtUtc: stopped.plan.createdAtUtc.add(consumed),
      );
      final reader = DriftLearningHistoryReader(
        h.db,
        learningTime: DriftLearningTimeRepository(
          h.db,
          owners: h.learning.owners,
        ),
        nowUtc: () => DateTime.utc(2026, 9, 6),
      );
      final entries = await reader.list(HistoryFilter(ownerId: h.owner));
      expect(entries, hasLength(3));
      final tapped = <String>[];
      await tester.pumpWidget(
        _app(
          textScale: 2,
          reader: reader,
          owners: h.learning.owners,
          pairReader: DriftPairMatchingSessionPurposeReader(h.db),
          onPairReplay: (projection, operationId) async {
            tapped.add(projection.sessionId);
          },
        ),
      );
      await tester.pumpAndSettle();
      for (final operation in [normal, replay]) {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        final action = find.byKey(
          ValueKey('pair-replay-history-${operation.plan.learningSessionId}'),
        );
        await tester.scrollUntilVisible(action, 250, maxScrolls: 100);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(action).onPressed, isNotNull);
        expect(
          find.text('คำตอบครั้งแรก 4/4'),
          findsWidgets,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .whereType<String>()
              .where((t) => t.contains('ครั้งแรก'))
              .join(', '),
        );
        expect(
          find.textContaining(normal.plan.learningSessionId),
          findsNothing,
        );
        await tester.tap(action);
        await tester.pumpAndSettle();
      }
      expect(tapped.toSet(), {
        normal.plan.learningSessionId,
        replay.plan.learningSessionId,
      });
      final stoppedAction = find.byKey(
        ValueKey('pair-replay-history-${stopped.plan.learningSessionId}'),
      );
      await tester.scrollUntilVisible(stoppedAction, -250);
      expect(tester.widget<FilledButton>(stoppedAction).onPressed, isNull);
      expect(find.text('รอบจับคู่หยุดก่อนจบ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'f43 screen renders deterministic terminal cards with accessible non-color status',
    (tester) async {
      final entries = <LearningHistoryEntry>[
        _entry(
          sessionId: 'session:completed',
          mode: LessonMode.meaningQuiz,
          state: LearningHistoryTerminalState.completed,
          packTitle: 'Travel Essentials',
          duration: const Duration(minutes: 2),
          startedAtUtc: DateTime.utc(2026, 8, 31, 9),
        ),
        _entry(
          sessionId: 'session:abandoned',
          mode: LessonMode.typedRecall,
          state: LearningHistoryTerminalState.abandoned,
          packTitle: 'Travel Essentials',
          duration: const Duration(seconds: 45),
          startedAtUtc: DateTime.utc(2026, 8, 30, 9),
        ),
      ];
      final reader = _Reader(entries);

      await tester.pumpWidget(_app(reader: reader));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'ประวัติการเรียน'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('learning-history-session:completed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('learning-history-session:abandoned')),
        findsOneWidget,
      );
      expect(find.text('Travel Essentials'), findsNWidgets(2));
      expect(find.text('แบบทดสอบความหมาย'), findsOneWidget);
      expect(find.text('พิมพ์คำตอบ'), findsOneWidget);
      expect(find.text('เวลาฝึกจริง 2 นาที'), findsOneWidget);
      expect(find.text('เวลาฝึกจริง 45 วินาที'), findsOneWidget);
      expect(find.text('เสร็จสิ้น'), findsOneWidget);
      expect(find.text('ละทิ้ง'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      final completedTop = tester.getTopLeft(
        find.byKey(const ValueKey('learning-history-session:completed')),
      );
      final abandonedTop = tester.getTopLeft(
        find.byKey(const ValueKey('learning-history-session:abandoned')),
      );
      expect(completedTop.dy, lessThan(abandonedTop.dy));
      expect(
        find.bySemanticsLabel(
          'เสร็จสิ้น, Travel Essentials, แบบทดสอบความหมาย, '
          'เวลาฝึกจริง 2 นาที',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'f43 screen renders deleted content fallback without inventing pack metadata',
    (tester) async {
      final reader = _Reader(<LearningHistoryEntry>[
        _entry(
          sessionId: 'session:missing',
          mode: LessonMode.definitionQuiz,
          state: LearningHistoryTerminalState.completed,
          packTitle: null,
          availability: LearningHistoryContentAvailability.unavailable,
          duration: const Duration(minutes: 1),
          startedAtUtc: DateTime.utc(2026, 8, 31, 8),
        ),
      ]);

      await tester.pumpWidget(_app(reader: reader));
      await tester.pumpAndSettle();

      expect(find.text('เนื้อหาที่บันทึกไว้ไม่พร้อมใช้งาน'), findsOneWidget);
      expect(find.text('Travel Essentials'), findsNothing);
      expect(find.textContaining('pack:travel'), findsNothing);
      expect(find.text('แบบทดสอบคำจำกัดความ'), findsOneWidget);
      expect(find.text('เวลาฝึกจริง 1 นาที'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('replay-history-session:missing')),
        findsNothing,
        reason: 'deleted content cannot be replayed by inventing a pack',
      );
    },
  );

  testWidgets(
    'f43 replay is single flight through the lesson authority and becomes retryable after failure',
    (tester) async {
      final entry = _entry(
        sessionId: 'session:completed',
        mode: LessonMode.meaningQuiz,
        state: LearningHistoryTerminalState.completed,
        packTitle: 'Travel Essentials',
        duration: const Duration(minutes: 2),
        startedAtUtc: DateTime.utc(2026, 8, 31, 9),
      );
      final reader = _Reader(<LearningHistoryEntry>[entry]);
      final launcher = _ControlledLauncher();
      var generatedOperations = 0;

      await tester.pumpWidget(
        _app(
          reader: reader,
          launcher: launcher,
          generateReplayOperationId: () =>
              'history-replay:screen-${++generatedOperations}',
        ),
      );
      await tester.pumpAndSettle();

      final replay = find.byKey(
        const ValueKey('replay-history-session:completed'),
      );
      await tester.tap(replay);
      await tester.pump();
      await tester.tap(replay);
      await tester.pump();
      expect(reader.replayCalls, 1);
      expect(launcher.commands, hasLength(1));
      expect(
        tester.widget<FilledButton>(replay).onPressed,
        isNull,
        reason: 'double submit must not create two session identities',
      );

      launcher.pending.single.completeError(StateError('route unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('ไม่สามารถเริ่มเซสชันใหม่ได้'), findsOneWidget);
      expect(tester.widget<FilledButton>(replay).onPressed, isNotNull);

      await tester.tap(replay);
      await tester.pump();
      expect(reader.replayCalls, 2);
      expect(launcher.commands, hasLength(2));
      expect(
        reader.replayOperationIds,
        const <String>['history-replay:screen-1', 'history-replay:screen-1'],
        reason: 'one user action must retain its identity through retry',
      );
      launcher.pending.last.complete();
      await tester.pumpAndSettle();
      expect(find.text('ไม่สามารถเริ่มเซสชันใหม่ได้'), findsNothing);

      await tester.tap(replay);
      await tester.pump();
      expect(reader.replayCalls, 3);
      expect(reader.replayOperationIds.last, 'history-replay:screen-2');
      expect(launcher.commands, hasLength(3));
      launcher.pending.last.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'f43 replay retains each unresolved card operation identity across interleaved attempts',
    (tester) async {
      final reader = _Reader(<LearningHistoryEntry>[
        _entry(
          sessionId: 'session:a',
          mode: LessonMode.meaningQuiz,
          state: LearningHistoryTerminalState.completed,
          packTitle: 'Travel Essentials',
          duration: const Duration(minutes: 2),
          startedAtUtc: DateTime.utc(2026, 8, 31, 9),
        ),
        _entry(
          sessionId: 'session:b',
          mode: LessonMode.typedRecall,
          state: LearningHistoryTerminalState.completed,
          packTitle: 'Travel Essentials',
          duration: const Duration(minutes: 1),
          startedAtUtc: DateTime.utc(2026, 8, 30, 9),
        ),
      ]);
      final launcher = _ControlledLauncher();
      var generatedOperations = 0;

      await tester.pumpWidget(
        _app(
          reader: reader,
          launcher: launcher,
          generateReplayOperationId: () =>
              'history-replay:interleaved-${++generatedOperations}',
        ),
      );
      await tester.pumpAndSettle();

      final replayA = find.byKey(const ValueKey('replay-history-session:a'));
      final replayB = find.byKey(const ValueKey('replay-history-session:b'));

      await tester.tap(replayA);
      await tester.pump();
      launcher.pending.single.completeError(StateError('lost acknowledgement'));
      await tester.pumpAndSettle();

      await tester.tap(replayB);
      await tester.pump();
      launcher.pending.last.complete();
      await tester.pumpAndSettle();

      await tester.tap(replayA);
      await tester.pump();

      expect(
        reader.replayOperationIds,
        const <String>[
          'history-replay:interleaved-1',
          'history-replay:interleaved-2',
          'history-replay:interleaved-1',
        ],
        reason:
            'acknowledging B must not erase A\'s unresolved replay identity',
      );
      expect(
        launcher.commands.map((command) => command.sessionId),
        const <String>[
          'session:replay-1',
          'session:replay-2',
          'session:replay-1',
        ],
        reason: 'A retry must target the same durable replay session',
      );

      launcher.pending.last.complete();
      await tester.pumpAndSettle();
    },
  );

  test(
    'Pair results are authenticated for displayed sessions and owner drift fails closed',
    () async {
      final fixture = await _canonicalPairFixture(token: 'use-case');
      final pairReader = _PairPurposeReader(
        <String, PairMatchingSessionPurpose>{
          fixture.projection.sessionId: fixture.purpose,
        },
      );
      final stable = LearningHistoryUseCases(
        owners: _SequenceOwners(<String>[fixture.ownerId, fixture.ownerId]),
        reader: _Reader(const <LearningHistoryEntry>[]),
        sessionLauncher: _ImmediateLauncher(),
        pairReader: pairReader,
      );

      final results = await stable.loadPairResults(<String>[
        fixture.projection.sessionId,
        fixture.projection.sessionId,
      ]);

      expect(results, hasLength(1));
      expect(results.single.sessionId, fixture.projection.sessionId);
      expect(pairReader.sessionIds, <String>[fixture.projection.sessionId]);

      final drifted = LearningHistoryUseCases(
        owners: _SequenceOwners(<String>[fixture.ownerId, 'owner:changed']),
        reader: _Reader(const <LearningHistoryEntry>[]),
        sessionLauncher: _ImmediateLauncher(),
        pairReader: _PairPurposeReader(<String, PairMatchingSessionPurpose>{
          fixture.projection.sessionId: fixture.purpose,
        }),
      );
      await expectLater(
        drifted.loadPairResults(<String>[fixture.projection.sessionId]),
        throwsStateError,
      );
    },
  );

  test('malformed Pair purpose remains a failed-closed read', () async {
    final useCases = LearningHistoryUseCases(
      owners: const _Owners(),
      reader: _Reader(const <LearningHistoryEntry>[]),
      sessionLauncher: _ImmediateLauncher(),
      pairReader: const _FailingPairPurposeReader(),
    );

    await expectLater(
      useCases.loadPairResults(const <String>['session:malformed-pair']),
      throwsStateError,
    );
  });

  testWidgets(
    'Pair replay uses the typed callback, keeps retry identity, and never calls generic replay',
    (tester) async {
      final fixture = await _canonicalPairFixture(token: 'typed-replay');
      final entry = _entry(
        sessionId: fixture.projection.sessionId,
        ownerId: fixture.ownerId,
        mode: LessonMode.matching,
        state: LearningHistoryTerminalState.completed,
        packTitle: 'Travel Essentials',
        duration: const Duration(minutes: 2),
        startedAtUtc: DateTime.utc(2026, 9, 5),
        pairSummary: fixture.projection,
      );
      final historyReader = _Reader(<LearningHistoryEntry>[entry]);
      final pending = <Completer<void>>[];
      final sources = <PairMatchingHistoryProjection>[];
      final operationIds = <String>[];
      var generated = 0;

      await tester.pumpWidget(
        _app(
          reader: historyReader,
          owners: _Owners(fixture.ownerId),
          pairReader: _PairPurposeReader(<String, PairMatchingSessionPurpose>{
            fixture.projection.sessionId: fixture.purpose,
          }),
          generateReplayOperationId: () => 'history-pair-replay:${++generated}',
          onPairReplay: (source, operationId) {
            sources.add(source);
            operationIds.add(operationId);
            final completer = Completer<void>();
            pending.add(completer);
            return completer.future;
          },
        ),
      );
      await tester.pumpAndSettle();

      final replay = find.byKey(
        ValueKey('pair-replay-history-${fixture.projection.sessionId}'),
      );
      await tester.tap(replay);
      await tester.pump();
      await tester.tap(replay);
      await tester.pump();
      expect(sources.map((source) => source.sessionId), <String>[
        fixture.projection.sessionId,
      ]);
      expect(historyReader.replayCalls, 0);
      expect(tester.widget<FilledButton>(replay).onPressed, isNull);

      pending.single.completeError(StateError('lost acknowledgement'));
      await tester.pumpAndSettle();
      expect(find.text('ไม่สามารถเริ่มการฝึกซ้ำได้'), findsOneWidget);

      await tester.tap(replay);
      await tester.pump();
      expect(operationIds, const <String>[
        'history-pair-replay:1',
        'history-pair-replay:1',
      ]);
      expect(historyReader.replayCalls, 0);
      pending.last.complete();
      await tester.pumpAndSettle();

      await tester.tap(replay);
      await tester.pump();
      expect(operationIds.last, 'history-pair-replay:2');
      pending.last.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Pair overview separates normal and direct-source replay latest/best and honest elapsed values',
    (tester) async {
      final overview = await _canonicalPairOverviewFixtures();
      final entries = <LearningHistoryEntry>[
        for (final fixture in overview.fixtures)
          _entry(
            sessionId: fixture.projection.sessionId,
            ownerId: fixture.ownerId,
            mode: LessonMode.matching,
            state: LearningHistoryTerminalState.completed,
            packTitle: 'Travel Essentials',
            duration: const Duration(minutes: 1),
            startedAtUtc: DateTime.utc(2026, 9, 5),
            pairSummary: fixture.projection,
          ),
      ];

      await tester.pumpWidget(
        _app(
          reader: _Reader(entries),
          owners: _Owners(overview.fixtures.first.ownerId),
          pairReader: _PairPurposeReader(<String, PairMatchingSessionPurpose>{
            for (final fixture in overview.fixtures)
              fixture.projection.sessionId: fixture.purpose,
          }),
        ),
      );
      await tester.pumpAndSettle();

      final latestNormal = find.byKey(
        ValueKey('pair-history-${overview.latestNormal.projection.sessionId}'),
      );
      expect(
        find.descendant(of: latestNormal, matching: find.text('รอบปกติล่าสุด')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: latestNormal,
          matching: find.text('เวลาเรียนจริงทั้งรอบ 0 วินาที'),
        ),
        findsOneWidget,
      );

      final bestNormal = find.byKey(
        ValueKey('pair-history-${overview.bestNormal.projection.sessionId}'),
      );
      await tester.scrollUntilVisible(bestNormal, 200);
      expect(
        find.descendant(of: bestNormal, matching: find.text('รอบปกติดีที่สุด')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: bestNormal,
          matching: find.text('ไม่มีข้อมูลเวลาเรียนจริงครบทั้งรอบ'),
        ),
        findsOneWidget,
      );

      final latestReplay = find.byKey(
        ValueKey('pair-history-${overview.latestReplay.projection.sessionId}'),
      );
      await tester.scrollUntilVisible(latestReplay, 300);
      expect(
        find.descendant(
          of: latestReplay,
          matching: find.text('ฝึกซ้ำล่าสุดของต้นทางนี้'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: latestReplay,
          matching: find.textContaining('รอบต้นทาง: Travel Essentials'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: latestReplay,
          matching: find.text('รอบฝึกซ้ำไม่เพิ่มความก้าวหน้าหรือรางวัล'),
        ),
        findsOneWidget,
      );

      final bestReplay = find.byKey(
        ValueKey('pair-history-${overview.bestReplay.projection.sessionId}'),
      );
      await tester.scrollUntilVisible(bestReplay, 300);
      expect(
        find.descendant(
          of: bestReplay,
          matching: find.text('ฝึกซ้ำดีที่สุดของต้นทางนี้'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: bestReplay,
          matching: find.textContaining('รอบต้นทาง: Travel Essentials'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Pair replay is explicitly unavailable without composition and English action stays accessible',
    (tester) async {
      final fixture = await _canonicalPairFixture(
        token: 'disabled',
        interactiveElapsedMs: null,
      );
      final entry = _entry(
        sessionId: fixture.projection.sessionId,
        ownerId: fixture.ownerId,
        mode: LessonMode.matching,
        state: LearningHistoryTerminalState.completed,
        packTitle: null,
        localWordSet: true,
        duration: const Duration(minutes: 1),
        startedAtUtc: DateTime.utc(2026, 9, 5),
        pairSummary: fixture.projection,
      );

      await tester.pumpWidget(
        _app(
          reader: _Reader(<LearningHistoryEntry>[entry]),
          owners: _Owners(fixture.ownerId),
          pairReader: _PairPurposeReader(<String, PairMatchingSessionPurpose>{
            fixture.projection.sessionId: fixture.purpose,
          }),
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      final replay = find.byKey(
        ValueKey('pair-replay-history-${fixture.projection.sessionId}'),
      );
      expect(replay, findsOneWidget);
      expect(tester.widget<FilledButton>(replay).onPressed, isNull);
      expect(tester.getSize(replay).height, greaterThanOrEqualTo(48));
      expect(find.text('Practice Replay unavailable'), findsOneWidget);
      expect(find.text('Saved word set'), findsOneWidget);
      expect(find.text('Saved content is unavailable'), findsNothing);
      expect(
        find.text('Full interactive duration unavailable'),
        findsOneWidget,
      );
      final essential = tester.widget<Text>(
        find.text('Practice Replay unavailable'),
      );
      expect(essential.overflow, isNull);
    },
  );

  for (final unavailable in [false, true]) {
    testWidgets('optional Pair history context unavailable=$unavailable', (
      tester,
    ) async {
      final fixture = await _canonicalPairFixture(token: 'ai-pair');
      String? owner = fixture.ownerId;
      final registry = MenuActionRegistry(currentOwner: () => owner);
      final entry = _entry(
        sessionId: fixture.projection.sessionId,
        ownerId: fixture.ownerId,
        mode: LessonMode.matching,
        state: LearningHistoryTerminalState.completed,
        packTitle: null,
        localWordSet: true,
        duration: const Duration(minutes: 1),
        startedAtUtc: DateTime.utc(2026, 9, 5),
        pairSummary: fixture.projection,
      );
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: _app(
            reader: _Reader([entry]),
            owners: _Owners(fixture.ownerId),
            pairReader: unavailable
                ? const _FailingPairPurposeReader()
                : _PairPurposeReader({
                    fixture.projection.sessionId: fixture.purpose,
                  }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final values = registry.snapshot()['context'] as List;
      final data =
          jsonDecode(values.single['value'] as String) as Map<String, dynamic>;
      expect(data['mode'], 'matching');
      expect(data['resultAvailable'], !unavailable);
      expect(data['replayAddsProgressOrRewards'], false);
      if (unavailable) {
        expect(data.containsKey('stars'), false);
        expect(data.containsKey('matched'), false);
      } else {
        expect(data['stars'], fixture.projection.result.stars);
        expect(data['matched'], fixture.projection.result.matched);
        expect(
          data['firstAnswers']['total'],
          fixture.projection.firstAnswers.total,
        );
        expect(data['purpose'], 'learning');
      }
      expect(registry.snapshot()['actions'], isEmpty);
      owner = 'different-owner';
      expect(registry.snapshot()['context'], isEmpty);
    });
  }

  testWidgets('malformed Pair data disables both replay authorities', (
    tester,
  ) async {
    final marker = await _canonicalPairFixture(token: 'malformed-marker');
    final entry = _entry(
      sessionId: marker.projection.sessionId,
      ownerId: marker.ownerId,
      mode: LessonMode.matching,
      state: LearningHistoryTerminalState.completed,
      packTitle: 'Travel Essentials',
      duration: const Duration(minutes: 1),
      startedAtUtc: DateTime.utc(2026, 9, 5),
      pairSummary: marker.projection,
    );
    final historyReader = _Reader(<LearningHistoryEntry>[entry]);
    var pairCalls = 0;

    await tester.pumpWidget(
      _app(
        reader: historyReader,
        owners: _Owners(marker.ownerId),
        pairReader: const _FailingPairPurposeReader(),
        onPairReplay: (_, _) async {
          pairCalls += 1;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผลจับคู่ไม่พร้อมใช้งาน'), findsOneWidget);
    expect(historyReader.replayCalls, 0);
    expect(pairCalls, 0);
    final replay = find.byKey(
      ValueKey('pair-replay-history-${marker.projection.sessionId}'),
    );
    expect(tester.widget<FilledButton>(replay).onPressed, isNull);
  });

  testWidgets('f43 load failure is explicit and retryable', (tester) async {
    final reader = _Reader(<LearningHistoryEntry>[])
      ..loadFailure = StateError('read failed');

    await tester.pumpWidget(_app(reader: reader));
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถโหลดประวัติการเรียนได้'), findsOneWidget);
    expect(
      find.bySemanticsLabel('โหลดประวัติการเรียนไม่สำเร็จ'),
      findsOneWidget,
    );
    reader.loadFailure = null;
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีประวัติการเรียน'), findsOneWidget);
    expect(reader.loadCalls, 2);
  });
}

Widget _app({
  required LearningHistoryReader reader,
  LearningHistorySessionLauncher? launcher,
  LearningHistoryReplayOperationIdGenerator? generateReplayOperationId,
  LocalOwnerRepository owners = const _Owners(),
  PairMatchingSessionPurposeReader? pairReader,
  Future<void> Function(
    PairMatchingHistoryProjection source,
    String replayOperationId,
  )?
  onPairReplay,
  Locale locale = const Locale('th'),
  double textScale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  locale: locale,
  supportedLocales: const <Locale>[Locale('th'), Locale('en')],
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    _TestMaterialLocalizationsDelegate(),
    _TestWidgetsLocalizationsDelegate(),
    _TestCupertinoLocalizationsDelegate(),
  ],
  home: LearningHistoryScreen(
    useCases: LearningHistoryUseCases(
      owners: owners,
      reader: reader,
      sessionLauncher: launcher ?? _ImmediateLauncher(),
      pairReader: pairReader,
    ),
    generateReplayOperationId:
        generateReplayOperationId ?? () => 'history-replay:screen-default',
    onPairReplay: onPairReplay,
  ),
);

final class _TestMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _TestMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'th' || locale.languageCode == 'en';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_TestMaterialLocalizationsDelegate old) => false;
}

final class _TestWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _TestWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'th' || locale.languageCode == 'en';

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      DefaultWidgetsLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_TestWidgetsLocalizationsDelegate old) => false;
}

final class _TestCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _TestCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'th' || locale.languageCode == 'en';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(_TestCupertinoLocalizationsDelegate old) => false;
}

const _packIdentity = ContentIdentity(
  type: ContentType.learningPack,
  id: 'pack:travel',
  revision: 1,
);

LearningHistoryEntry _entry({
  required String sessionId,
  required LessonMode mode,
  required LearningHistoryTerminalState state,
  required String? packTitle,
  required Duration duration,
  required DateTime startedAtUtc,
  String ownerId = 'owner:history',
  LearningHistoryContentAvailability availability =
      LearningHistoryContentAvailability.available,
  PairMatchingHistoryProjection? pairSummary,
  bool pairPurposeUnavailable = false,
  bool localWordSet = false,
}) {
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: ownerId,
    mode: mode,
    itemCount: 1,
    direction: SessionDirection.forward,
    difficulty: SessionDifficulty.standard,
    hintBudget: 0,
    timing: const SessionTiming.untimedAlternative(
      maximumActiveEffort: Duration(minutes: 10),
    ),
    packIdentity: localWordSet ? null : _packIdentity,
    protocolId: 'protocol:local-standard',
    protocolVersion: '1',
    protocolLimitsIdentity:
        const SessionConfigurationProtocolLimits.standard().contentIdentity,
  );
  return LearningHistoryEntry(
    sessionId: sessionId,
    ownerId: ownerId,
    mode: mode,
    packIdentity: localWordSet ? null : _packIdentity,
    packTitle: packTitle,
    contentAvailability: localWordSet
        ? LearningHistoryContentAvailability.unavailable
        : availability,
    activeLearningDuration: duration,
    terminalState: state,
    startedAtUtc: startedAtUtc,
    endedAtUtc: startedAtUtc.add(const Duration(minutes: 5)),
    correctCount: state == LearningHistoryTerminalState.completed ? 1 : 0,
    wrongCount: 0,
    score: state == LearningHistoryTerminalState.completed ? 100 : null,
    sessionConfiguration: configuration,
    evidence: const <LearningHistoryEvidence>[],
    pairSummary: pairSummary,
    pairPurposeUnavailable: pairPurposeUnavailable,
  );
}

final class _Reader implements LearningHistoryReader {
  _Reader(this.entries);

  final List<LearningHistoryEntry> entries;
  Object? loadFailure;
  int loadCalls = 0;
  int replayCalls = 0;
  final List<String> replayOperationIds = <String>[];
  final Map<String, LessonStartCommand> _commandsByOperation =
      <String, LessonStartCommand>{};

  @override
  Future<List<LearningHistoryEntry>> list(HistoryFilter filter) async {
    loadCalls += 1;
    final failure = loadFailure;
    if (failure != null) throw failure;
    return List<LearningHistoryEntry>.unmodifiable(entries);
  }

  @override
  Future<LessonStartCommand> replayAsNewSession(
    String sourceSessionId, {
    required String replayOperationId,
  }) async {
    replayCalls += 1;
    replayOperationIds.add(replayOperationId);
    final entry = entries.singleWhere(
      (candidate) => candidate.sessionId == sourceSessionId,
    );
    final mode = entry.mode;
    final configuration = entry.sessionConfiguration;
    if (mode == null || configuration == null) {
      throw StateError('history entry has no replayable lesson pins');
    }
    return _commandsByOperation.putIfAbsent(
      replayOperationId,
      () => LessonStartCommand(
        mode: mode,
        sessionId: 'session:replay-${_commandsByOperation.length + 1}',
        startedAtUtc: DateTime.utc(
          2026,
          8,
          31,
          14,
          _commandsByOperation.length + 1,
        ),
        itemCount: configuration.itemCount,
        ownerId: entry.ownerId,
        configuration: configuration,
      ),
    );
  }
}

final class _ControlledLauncher implements LearningHistorySessionLauncher {
  final List<LessonStartCommand> commands = <LessonStartCommand>[];
  final List<Completer<void>> pending = <Completer<void>>[];

  @override
  Object get authorityIdentity => this;

  @override
  Future<void> start(LessonStartCommand command) {
    commands.add(command);
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future;
  }
}

final class _ImmediateLauncher implements LearningHistorySessionLauncher {
  @override
  Object get authorityIdentity => this;

  @override
  Future<void> start(LessonStartCommand command) async {}
}

final class _Owners implements LocalOwnerRepository {
  const _Owners([this.ownerId = 'owner:history']);

  final String ownerId;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: ownerId, createdAtUtc: DateTime.utc(2026, 8, 31));

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _SequenceOwners implements LocalOwnerRepository {
  _SequenceOwners(this.ownerIds);

  final List<String> ownerIds;
  var _index = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    final ownerId = ownerIds[_index < ownerIds.length ? _index++ : _index - 1];
    return identity.LocalOwner(
      id: ownerId,
      createdAtUtc: DateTime.utc(2026, 8, 31),
    );
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _PairPurposeReader implements PairMatchingSessionPurposeReader {
  _PairPurposeReader(this.purposes);

  final Map<String, PairMatchingSessionPurpose> purposes;
  final List<String> sessionIds = <String>[];

  @override
  Future<PairMatchingSessionPurpose> read({
    required String ownerId,
    required String sessionId,
  }) async {
    sessionIds.add(sessionId);
    final purpose = purposes[sessionId];
    if (purpose == null || purpose.snapshot?.engine.plan.ownerId != ownerId) {
      throw StateError('Pair purpose is unavailable');
    }
    return purpose;
  }
}

final class _FailingPairPurposeReader
    implements PairMatchingSessionPurposeReader {
  const _FailingPairPurposeReader();

  @override
  Future<PairMatchingSessionPurpose> read({
    required String ownerId,
    required String sessionId,
  }) async {
    throw StateError('Persisted Pair purpose is unavailable or corrupt');
  }
}

final class _CanonicalPairFixture {
  const _CanonicalPairFixture({required this.ownerId, required this.purpose});

  final String ownerId;
  final PairMatchingSessionPurpose purpose;
  PairMatchingHistoryProjection get projection =>
      PairMatchingHistoryProjection(purpose.snapshot!);
}

final class _CanonicalPairOverview {
  const _CanonicalPairOverview({
    required this.fixtures,
    required this.latestNormal,
    required this.bestNormal,
    required this.latestReplay,
    required this.bestReplay,
  });

  final List<_CanonicalPairFixture> fixtures;
  final _CanonicalPairFixture latestNormal;
  final _CanonicalPairFixture bestNormal;
  final _CanonicalPairFixture latestReplay;
  final _CanonicalPairFixture bestReplay;
}

Future<_CanonicalPairFixture> _canonicalPairFixture({
  required String token,
  int assistedCount = 0,
  int? interactiveElapsedMs = 0,
}) async {
  const ownerId = 'synthetic-owner';
  final operation = _pairOperation(
    ownerId: ownerId,
    token: token,
    createdAtUtc: DateTime.utc(2026, 9, 5),
  );
  final harness = PairHarness(
    pinnedPlan: operation.plan,
    launchId: operation.launchOperationId,
  );
  try {
    await harness.initialize(measured: interactiveElapsedMs != null);
    final purpose = await _finishPairOperation(
      harness: harness,
      operation: operation,
      alreadyStarted: true,
      measured: interactiveElapsedMs != null,
      interactiveElapsedMs: interactiveElapsedMs ?? 0,
      assistedCount: assistedCount,
    );
    return _CanonicalPairFixture(ownerId: ownerId, purpose: purpose);
  } finally {
    await harness.db.close();
  }
}

Future<_CanonicalPairOverview> _canonicalPairOverviewFixtures() async {
  const ownerId = 'synthetic-owner';
  final created = DateTime.utc(2026, 9, 5);
  final normalA = _pairOperation(
    ownerId: ownerId,
    token: 'overview-normal-a',
    createdAtUtc: created,
  );
  final normalB = _pairOperation(
    ownerId: ownerId,
    token: 'overview-normal-b',
    createdAtUtc: created,
  );
  final latestNormalOperation =
      normalA.plan.learningSessionId.compareTo(normalB.plan.learningSessionId) <
          0
      ? normalA
      : normalB;
  final bestNormalOperation = identical(latestNormalOperation, normalA)
      ? normalB
      : normalA;
  final harness = PairHarness(
    pinnedPlan: normalA.plan,
    launchId: normalA.launchOperationId,
  );
  try {
    await harness.initialize(
      measured: identical(normalA, latestNormalOperation),
    );
    final normalPurposeA = await _finishPairOperation(
      harness: harness,
      operation: normalA,
      alreadyStarted: true,
      measured: identical(normalA, latestNormalOperation),
      interactiveElapsedMs: 0,
      assistedCount: identical(normalA, latestNormalOperation) ? 1 : 0,
    );
    final normalPurposeB = await _finishPairOperation(
      harness: harness,
      operation: normalB,
      measured: identical(normalB, latestNormalOperation),
      interactiveElapsedMs: 0,
      assistedCount: identical(normalB, latestNormalOperation) ? 1 : 0,
    );
    final normals = <String, PairMatchingSessionPurpose>{
      normalA.plan.learningSessionId: normalPurposeA,
      normalB.plan.learningSessionId: normalPurposeB,
    };
    final bestSourceId = bestNormalOperation.plan.learningSessionId;
    final replayCreated = DateTime.utc(2026, 9, 5, 0, 1);
    final replayA = _pairOperation(
      ownerId: ownerId,
      token: 'overview-replay-a',
      createdAtUtc: replayCreated,
      purpose: PairSessionPurpose.practiceReplay,
      sourceSessionId: bestSourceId,
      shuffleSeed: 101,
    );
    final replayB = _pairOperation(
      ownerId: ownerId,
      token: 'overview-replay-b',
      createdAtUtc: replayCreated,
      purpose: PairSessionPurpose.practiceReplay,
      sourceSessionId: bestSourceId,
      shuffleSeed: 102,
    );
    final latestReplayOperation =
        replayA.plan.learningSessionId.compareTo(
              replayB.plan.learningSessionId,
            ) <
            0
        ? replayA
        : replayB;
    final bestReplayOperation = identical(latestReplayOperation, replayA)
        ? replayB
        : replayA;
    final replayPurposeA = await _finishPairOperation(
      harness: harness,
      operation: replayA,
      assistedCount: identical(replayA, latestReplayOperation) ? 4 : 0,
    );
    final replayPurposeB = await _finishPairOperation(
      harness: harness,
      operation: replayB,
      assistedCount: identical(replayB, latestReplayOperation) ? 4 : 0,
    );
    final replays = <String, PairMatchingSessionPurpose>{
      replayA.plan.learningSessionId: replayPurposeA,
      replayB.plan.learningSessionId: replayPurposeB,
    };

    _CanonicalPairFixture fixture(
      PairMatchingStartOperation operation,
      Map<String, PairMatchingSessionPurpose> purposes,
    ) => _CanonicalPairFixture(
      ownerId: ownerId,
      purpose: purposes[operation.plan.learningSessionId]!,
    );

    final latestNormal = fixture(latestNormalOperation, normals);
    final bestNormal = fixture(bestNormalOperation, normals);
    final latestReplay = fixture(latestReplayOperation, replays);
    final bestReplay = fixture(bestReplayOperation, replays);
    return _CanonicalPairOverview(
      fixtures: <_CanonicalPairFixture>[
        latestNormal,
        bestNormal,
        latestReplay,
        bestReplay,
      ],
      latestNormal: latestNormal,
      bestNormal: bestNormal,
      latestReplay: latestReplay,
      bestReplay: bestReplay,
    );
  } finally {
    await harness.db.close();
  }
}

PairMatchingStartOperation _pairOperation({
  required String ownerId,
  required String token,
  required DateTime createdAtUtc,
  PairSessionPurpose purpose = PairSessionPurpose.learning,
  String? sourceSessionId,
  int shuffleSeed = 17,
  bool configured = false,
}) {
  final launchOperationId = 'history-test:$token';
  final plan = PairMatchingPlanV1(
    ownerId: ownerId,
    orderedLexicalItems: <PairLexicalItem>[
      for (var index = 0; index < 4; index += 1) pair_fixture.fixture(index),
    ],
    direction: PairDirection.enToTh,
    density: PairDensity.compact4,
    shuffleSeed: shuffleSeed,
    timerPreset: PairTimerPreset.off,
    allowlistVersion: 'history-test-v1',
    learningSessionId: pairSessionId(ownerId, launchOperationId),
    entryKind: PairSourceSurface.history,
    sourceSnapshotId: 'history-source:$token',
    createdAtUtc: createdAtUtc,
    sessionPurpose: purpose,
    sourceSessionId: sourceSessionId,
  );
  return PairMatchingStartOperation(
    plan: plan,
    launchOperationId: launchOperationId,
    appVersion: 'synthetic',
    buildId: 'synthetic',
    configuration: configured
        ? SessionConfiguration.validated(
            schemaVersion: sessionConfigurationSchemaVersion,
            policyVersion: sessionConfigurationPolicyVersion,
            ownerId: ownerId,
            mode: LessonMode.matching,
            itemCount: 4,
            direction: SessionDirection.forward,
            difficulty: SessionDifficulty.standard,
            hintBudget: 0,
            timing: const SessionTiming.untimedAlternative(
              maximumActiveEffort: Duration(minutes: 10),
            ),
            packIdentity: null,
            protocolId: 'protocol:local-standard',
            protocolVersion: '1',
            protocolLimitsIdentity:
                const SessionConfigurationProtocolLimits.standard()
                    .contentIdentity,
          )
        : null,
  );
}

Future<PairMatchingSessionPurpose> _finishPairOperation({
  required PairHarness harness,
  required PairMatchingStartOperation operation,
  bool alreadyStarted = false,
  bool measured = false,
  int interactiveElapsedMs = 0,
  int assistedCount = 0,
}) async {
  if (!alreadyStarted) {
    final starter = PairMatchingAtomicStartAdapter(
      repository: harness.real,
      capability: InternalPairMatchingCapability(
        allowlist: PairCuratedAllowlist(
          version: operation.plan.allowlistVersion,
          items: operation.plan.orderedLexicalItems,
        ),
        isEnabled: () => true,
      ),
    );
    await (measured
        ? starter.startMeasured(operation)
        : starter.start(operation));
  }
  var monotonicMicros = 0;
  final coordinator = await PairMatchingSessionCoordinator.restore(
    operation: operation,
    learning: harness.learning,
    evidence: CurrentActivityEvidenceAdapter(learning: harness.learning),
    activeOwnerId: () => harness.owner,
    monotonicMicros: () => monotonicMicros,
  );
  monotonicMicros = interactiveElapsedMs * 1000;
  for (
    var index = 0;
    index < operation.plan.orderedLexicalItems.length;
    index++
  ) {
    final wordId = operation.plan.orderedLexicalItems[index].wordId;
    if (index < assistedCount) {
      await coordinator.dispatch(
        PairRevealMapping(
          operationId: '${coordinator.state.operationRevision}:reveal-$index',
          ownerId: harness.owner,
          sessionId: operation.plan.learningSessionId,
          roundOrdinal: coordinator.state.roundOrdinal,
          expectedRevision: coordinator.state.operationRevision,
          wordId: wordId,
        ),
      );
    }
    await _tapPair(coordinator, harness.owner, wordId, PairTileSide.prompt);
    await _tapPair(coordinator, harness.owner, wordId, PairTileSide.target);
  }
  await coordinator.finish();
  return DriftPairMatchingSessionPurposeReader(
    harness.db,
  ).read(ownerId: harness.owner, sessionId: operation.plan.learningSessionId);
}

Future<void> _tapPair(
  PairMatchingSessionCoordinator coordinator,
  String ownerId,
  String wordId,
  PairTileSide side,
) => coordinator.dispatch(
  PairSelectTile(
    operationId: '${coordinator.state.operationRevision}:tap-${side.name}',
    ownerId: ownerId,
    sessionId: coordinator.operation.plan.learningSessionId,
    roundOrdinal: coordinator.state.roundOrdinal,
    expectedRevision: coordinator.state.operationRevision,
    tile: PairTile(side, wordId),
    responseTimeMs: 25,
  ),
);
