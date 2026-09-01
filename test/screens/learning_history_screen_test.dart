import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/history/application/learning_history_use_cases.dart';
import 'package:vocab_learning_app/features/history/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';

void main() {
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
  required _Reader reader,
  LearningHistorySessionLauncher? launcher,
  LearningHistoryReplayOperationIdGenerator? generateReplayOperationId,
}) => MaterialApp(
  home: LearningHistoryScreen(
    useCases: LearningHistoryUseCases(
      owners: const _Owners(),
      reader: reader,
      sessionLauncher: launcher ?? _ImmediateLauncher(),
    ),
    generateReplayOperationId:
        generateReplayOperationId ?? () => 'history-replay:screen-default',
  ),
);

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
  LearningHistoryContentAvailability availability =
      LearningHistoryContentAvailability.available,
}) {
  final configuration = SessionConfiguration.validated(
    schemaVersion: sessionConfigurationSchemaVersion,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: 'owner:history',
    mode: mode,
    itemCount: 1,
    direction: SessionDirection.forward,
    difficulty: SessionDifficulty.standard,
    hintBudget: 0,
    timing: const SessionTiming.untimedAlternative(
      maximumActiveEffort: Duration(minutes: 10),
    ),
    packIdentity: _packIdentity,
    protocolId: 'protocol:local-standard',
    protocolVersion: '1',
    protocolLimitsIdentity:
        const SessionConfigurationProtocolLimits.standard().contentIdentity,
  );
  return LearningHistoryEntry(
    sessionId: sessionId,
    ownerId: 'owner:history',
    mode: mode,
    packIdentity: _packIdentity,
    packTitle: packTitle,
    contentAvailability: availability,
    activeLearningDuration: duration,
    terminalState: state,
    startedAtUtc: startedAtUtc,
    endedAtUtc: startedAtUtc.add(const Duration(minutes: 5)),
    correctCount: state == LearningHistoryTerminalState.completed ? 1 : 0,
    wrongCount: 0,
    score: state == LearningHistoryTerminalState.completed ? 100 : null,
    sessionConfiguration: configuration,
    evidence: const <LearningHistoryEvidence>[],
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
  const _Owners();

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner:history',
        createdAtUtc: DateTime.utc(2026, 8, 31),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}
