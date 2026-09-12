import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/accessibility/presentation/accessibility_scope.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_repair_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_board_view.dart';

const pairBoardSurfaceKey = ValueKey<String>('pair-board-test-surface');

PairMatchingPlanV1 pairBoardTestPlan({
  PairDensity density = PairDensity.compact4,
  PairDirection direction = PairDirection.enToTh,
  bool longThai = false,
}) {
  final pairs = <(String, String)>[
    ('apple', 'แอปเปิล'),
    ('house', 'บ้าน'),
    ('water', 'น้ำ'),
    ('cat', 'แมว'),
    ('mountain', 'ภูเขา'),
    ('book', 'หนังสือ'),
  ];
  return PairMatchingPlanV1(
    ownerId: 'owner:pair-board-test',
    orderedLexicalItems: <PairLexicalItem>[
      for (final (index, pair) in pairs.take(density.pairCount).indexed)
        PairLexicalItem(
          wordId: 'word:$index',
          contentRevision: 1,
          checksum: '${index + 1}' * 64,
          spelling: pair.$1,
          meaning: longThai && index == 0
              ? 'ผลไม้สีแดงที่มีความหมายยาวเพื่อทดสอบการตัดบรรทัดภาษาไทย'
              : pair.$2,
          sourceLocale: 'en',
          targetLocale: 'th',
          sourceReasons: const <PairSourceReason>{PairSourceReason.dueSrs},
        ),
    ],
    direction: direction,
    density: density,
    shuffleSeed: 42,
    timerPreset: PairTimerPreset.off,
    allowlistVersion: 'pair-board-test-v1',
    learningSessionId: 'session:pair-board-test',
    entryKind: PairSourceSurface.learn,
    sourceSnapshotId: 'snapshot:pair-board-test',
    createdAtUtc: DateTime.utc(2026, 9, 5),
  );
}

PairMatchingState pairBoardSelect(
  PairMatchingState state,
  PairTileSide side,
  String wordId, {
  String suffix = 'select',
}) => PairMatchingEngine.reduce(
  state,
  PairSelectTile(
    operationId: '${state.operationRevision}:$suffix',
    ownerId: state.plan.ownerId,
    sessionId: state.plan.learningSessionId,
    roundOrdinal: state.roundOrdinal,
    expectedRevision: state.operationRevision,
    tile: PairTile(side, wordId),
    responseTimeMs: 25,
  ),
).state;

PairMatchingState pairBoardAcknowledge(PairMatchingState state) =>
    PairMatchingEngine.acknowledge(state, state.pending!.operationId);

PairMatchingState pairBoardMatch(PairMatchingState state, String wordId) {
  var next = pairBoardSelect(
    state,
    PairTileSide.prompt,
    wordId,
    suffix: 'prompt-$wordId',
  );
  next = pairBoardSelect(
    next,
    PairTileSide.target,
    wordId,
    suffix: 'target-$wordId',
  );
  return pairBoardAcknowledge(next);
}

PairMatchingState pairBoardWrong(PairMatchingState state, String wordId) {
  final otherId = state.plan.orderedLexicalItems
      .map((item) => item.wordId)
      .firstWhere((id) => id != wordId && !state.matchedWordIds.contains(id));
  var next = pairBoardSelect(
    state,
    PairTileSide.prompt,
    wordId,
    suffix: 'wrong-prompt-$wordId',
  );
  next = pairBoardSelect(
    next,
    PairTileSide.target,
    otherId,
    suffix: 'wrong-target-$wordId',
  );
  return pairBoardAcknowledge(next);
}

PairMatchingState pairBoardGuidedState(PairMatchingPlanV1 plan) {
  final ids = plan.orderedLexicalItems.map((item) => item.wordId).toList();
  var state = pairBoardWrong(PairMatchingState.initial(plan), ids[0]);
  state = pairBoardMatch(state, ids[1]);
  state = pairBoardMatch(state, ids[2]);
  expect(state.repairFor(ids[0])?.status, PairRepairStatus.available);
  state = pairBoardWrong(state, ids[0]);
  expect(state.repairFor(ids[0])?.status, PairRepairStatus.guidedRequired);
  expect(state.supportAtRevision[ids[0]], isNotNull);
  return state;
}

PairBoardModel pairBoardTestModel({
  required PairMatchingState state,
  PairTimerState? timer,
  bool busy = false,
  bool focusedTraversal = false,
  bool audioAvailable = false,
  String? statusMessage,
  String? audioFallback,
}) => PairBoardModel(
  state: state,
  timer: timer ?? PairTimerState.initial(PairTimerPreset.off),
  busy: busy,
  focusedTraversal: focusedTraversal,
  audioAvailable: audioAvailable,
  statusMessage: statusMessage,
  audioFallback: audioFallback,
);

Widget pairBoardTestApp({
  required PairBoardModel model,
  Locale locale = const Locale('th'),
  Size size = const Size(412, 915),
  double textScale = 1,
  bool accessibleNavigation = false,
  bool highContrast = false,
  bool reducedMotion = false,
  ThemeMode themeMode = ThemeMode.light,
  ValueChanged<PairTile>? onSelectTile,
  ValueChanged<String>? onRevealMapping,
  void Function(String wordId, int shownSupportRevision)?
  onConfirmGuidedMapping,
  ValueChanged<PairTile>? onPronounce,
  Widget? shellFeedback,
  Key? boardKey,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: M3Theme.lightTheme,
  darkTheme: M3Theme.darkTheme,
  themeMode: themeMode,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      size: size,
      textScaler: TextScaler.linear(textScale),
      accessibleNavigation: accessibleNavigation,
      highContrast: highContrast,
      disableAnimations: reducedMotion,
    ),
    child: child!,
  ),
  home: Builder(
    builder: (context) => Localizations.override(
      context: context,
      locale: locale,
      child: RepaintBoundary(
        key: pairBoardSurfaceKey,
        child: Scaffold(
          body: AccessibilityScope(
            child: PairBoardView(
              key: boardKey,
              model: model,
              onSelectTile: onSelectTile ?? (_) {},
              onRevealMapping: onRevealMapping ?? (_) {},
              onConfirmGuidedMapping: onConfirmGuidedMapping ?? (_, _) {},
              onPronounce: onPronounce ?? (_) {},
              shellFeedback: shellFeedback,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'regular board uses canonical side order, balanced columns, and stable identity keys',
    (tester) async {
      final plan = pairBoardTestPlan(density: PairDensity.standard6);
      final state = PairMatchingState.initial(plan);
      await tester.pumpWidget(
        pairBoardTestApp(model: pairBoardTestModel(state: state)),
      );

      expect(
        find.byKey(const ValueKey<String>('pair-board-regular')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('pair-board-focused')),
        findsNothing,
      );
      final promptOrder = state.orderFor(PairTileSide.prompt);
      final targetOrder = state.orderFor(PairTileSide.target);
      for (final (index, id) in promptOrder.indexed) {
        final tile = find.byKey(ValueKey<String>('pair-tile:prompt:$id'));
        expect(tile, findsOneWidget);
        if (index > 0) {
          final prior = find.byKey(
            ValueKey<String>('pair-tile:prompt:${promptOrder[index - 1]}'),
          );
          expect(
            tester.getTopLeft(prior).dy,
            lessThan(tester.getTopLeft(tile).dy),
          );
        }
      }
      for (final (index, id) in targetOrder.indexed) {
        final tile = find.byKey(ValueKey<String>('pair-tile:target:$id'));
        expect(tile, findsOneWidget);
        if (index > 0) {
          final prior = find.byKey(
            ValueKey<String>('pair-tile:target:${targetOrder[index - 1]}'),
          );
          expect(
            tester.getTopLeft(prior).dy,
            lessThan(tester.getTopLeft(tile).dy),
          );
        }
      }
      expect(
        tester
            .getTopLeft(
              find.byKey(
                ValueKey<String>('pair-tile:prompt:${promptOrder.first}'),
              ),
            )
            .dx,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  ValueKey<String>('pair-tile:target:${targetOrder.first}'),
                ),
              )
              .dx,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('pair-column:prompt'))).height,
        tester.getSize(find.byKey(const ValueKey('pair-column:target'))).height,
      );
      for (final id in {...promptOrder, ...targetOrder}) {
        for (final side in PairTileSide.values) {
          expect(
            tester
                .getSize(
                  find.byKey(ValueKey<String>('pair-tile:${side.name}:$id')),
                )
                .height,
            greaterThanOrEqualTo(56),
          );
        }
      }
    },
  );

  testWidgets(
    'compact board tiles are at least 64px and wide content is bounded',
    (tester) async {
      final state = PairMatchingState.initial(pairBoardTestPlan());
      await tester.pumpWidget(
        pairBoardTestApp(
          model: pairBoardTestModel(state: state),
          size: const Size(1400, 900),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('pair-board-content'))).width,
        lessThanOrEqualTo(800),
      );
      for (final side in PairTileSide.values) {
        for (final id in state.orderFor(side)) {
          expect(
            tester
                .getSize(
                  find.byKey(ValueKey<String>('pair-tile:${side.name}:$id')),
                )
                .height,
            greaterThanOrEqualTo(64),
          );
        }
      }
    },
  );

  testWidgets(
    'selection and matching stay identity-only and keep progress canonical',
    (tester) async {
      final plan = pairBoardTestPlan();
      var state = PairMatchingState.initial(plan);
      final selected = <PairTile>[];
      await tester.pumpWidget(
        pairBoardTestApp(
          model: pairBoardTestModel(state: state),
          onSelectTile: selected.add,
        ),
      );
      final firstId = state.orderFor(PairTileSide.prompt).first;
      await tester.tap(
        find.byKey(ValueKey<String>('pair-tile:prompt:$firstId')),
      );
      expect(selected, hasLength(1));
      expect(selected.single.side, PairTileSide.prompt);
      expect(selected.single.wordId, firstId);

      state = pairBoardSelect(state, PairTileSide.prompt, firstId);
      await tester.pumpWidget(
        pairBoardTestApp(model: pairBoardTestModel(state: state)),
      );
      expect(find.bySemanticsLabel(RegExp('เลือกแล้ว')), findsOneWidget);
      expect(find.text('จับคู่แล้ว 0 จาก 4 คู่'), findsOneWidget);

      state = pairBoardMatch(PairMatchingState.initial(plan), firstId);
      await tester.pumpWidget(
        pairBoardTestApp(model: pairBoardTestModel(state: state)),
      );
      expect(find.text('จับคู่แล้ว 1 จาก 4 คู่'), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('pair-placeholder:prompt:$firstId')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('pair-placeholder:target:$firstId')),
        findsOneWidget,
      );
      final matchedItem = plan.orderedLexicalItems.singleWhere(
        (item) => item.wordId == firstId,
      );
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(matchedItem.spelling))),
        findsNothing,
      );
    },
  );

  testWidgets(
    'wrong and waiting repair use approved supportive text, icon, and border',
    (tester) async {
      final plan = pairBoardTestPlan();
      final wrongId = plan.orderedLexicalItems.first.wordId;
      final state = pairBoardWrong(PairMatchingState.initial(plan), wrongId);
      await tester.pumpWidget(
        pairBoardTestApp(model: pairBoardTestModel(state: state)),
      );
      const wrongCopy = 'ยังไม่ใช่ ลองเก็บคำนี้ไว้แล้วกลับมาอีกครั้งนะ';
      const repairCopy = 'คำนี้จะกลับมาหลังฝึกคำอื่นอีกสักครู่';
      final feedback = find.byKey(
        const ValueKey<String>('pair-feedback:wrong'),
      );
      expect(feedback, findsOneWidget);
      expect(find.text(wrongCopy), findsOneWidget);
      expect(find.text(repairCopy), findsOneWidget);
      expect(
        find.descendant(
          of: feedback,
          matching: find.byIcon(Icons.info_outline),
        ),
        findsOneWidget,
      );
      final decorated = tester.widget<DecoratedBox>(feedback);
      expect((decorated.decoration as BoxDecoration).border, isNotNull);
      expect(find.text('จับคู่แล้ว 0 จาก 4 คู่'), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('pair-placeholder:prompt:$wrongId')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'guided mapping requires a separate confirmation with shown revision',
    (tester) async {
      final plan = pairBoardTestPlan();
      final state = pairBoardGuidedState(plan);
      final guidedId = plan.orderedLexicalItems.first.wordId;
      final confirmations = <(String, int)>[];
      var selected = 0;
      await tester.pumpWidget(
        pairBoardTestApp(
          model: pairBoardTestModel(state: state),
          onSelectTile: (_) => selected++,
          onConfirmGuidedMapping: (id, revision) =>
              confirmations.add((id, revision)),
        ),
      );
      expect(
        find.text('ช่วยกันจับคู่คำนี้ให้ครบ แล้วระบบจะเก็บไว้ทบทวนอีกครั้ง'),
        findsOneWidget,
      );
      final item = plan.orderedLexicalItems.first;
      expect(find.text(item.spelling), findsOneWidget);
      expect(find.text(item.meaning), findsOneWidget);
      expect(
        selected,
        0,
        reason: 'rendering guided support must not synthesize an answer',
      );
      final confirm = find.byKey(
        ValueKey<String>('pair-confirm-guided:$guidedId'),
      );
      await tester.ensureVisible(confirm);
      await tester.pump();
      await tester.tap(confirm);
      expect(confirmations, [(guidedId, state.supportAtRevision[guidedId]!)]);
      expect(selected, 0);
    },
  );

  testWidgets(
    'pronunciation is neutral and unavailable audio exposes text fallback',
    (tester) async {
      final plan = pairBoardTestPlan();
      final id = plan.orderedLexicalItems.first.wordId;
      final selectedState = pairBoardSelect(
        PairMatchingState.initial(plan),
        PairTileSide.prompt,
        id,
      );
      final pronounced = <PairTile>[];
      var reveals = 0;
      await tester.pumpWidget(
        pairBoardTestApp(
          model: pairBoardTestModel(state: selectedState, audioAvailable: true),
          onPronounce: pronounced.add,
          onRevealMapping: (_) => reveals++,
        ),
      );
      final pronounce = find.byKey(
        ValueKey<String>('pair-pronounce:prompt:$id'),
      );
      expect(find.text('ฟังคำอังกฤษ'), findsOneWidget);
      expect(tester.getSize(pronounce).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(pronounce).height, greaterThanOrEqualTo(48));
      await tester.tap(pronounce);
      expect(pronounced.single.side, PairTileSide.prompt);
      expect(pronounced.single.wordId, id);
      expect(reveals, 0);

      await tester.pumpWidget(
        pairBoardTestApp(
          model: pairBoardTestModel(
            state: selectedState,
            audioFallback: '/ˈæp.əl/ apple',
          ),
        ),
      );
      expect(
        find.byKey(ValueKey<String>('pair-pronounce:prompt:$id')),
        findsNothing,
      );
      expect(find.textContaining('/ˈæp.əl/ apple'), findsOneWidget);
    },
  );

  testWidgets('timer announces nonaligned 30 and 10 second crossings once', (
    tester,
  ) async {
    final state = PairMatchingState.initial(pairBoardTestPlan());
    final boardKey = GlobalKey();
    for (final (remaining, expectedLive) in <(int, bool)>[
      (30050, false),
      (29800, true),
      (29550, false),
      (10050, false),
      (9800, true),
      (9550, false),
    ]) {
      await tester.pumpWidget(
        pairBoardTestApp(
          boardKey: boardKey,
          model: pairBoardTestModel(
            state: state,
            timer: PairTimerState(
              mode: PairTimerMode.running,
              remainingActiveMs: remaining,
            ),
          ),
        ),
      );
      final timer = find.byKey(const ValueKey<String>('pair-timer'));
      expect(timer, findsOneWidget);
      final semantics = tester.getSemantics(timer).getSemanticsData();
      expect(semantics.flagsCollection.isLiveRegion, expectedLive);
      expect(semantics.hasAction(SemanticsAction.tap), isFalse);
    }
  });

  testWidgets('timer crossing deduplicates per round and timer phase', (
    tester,
  ) async {
    var state = PairMatchingState.initial(pairBoardTestPlan());
    var mode = PairTimerMode.running;
    var extensionUsed = false;
    final boardKey = GlobalKey();

    Future<void> pumpTimer(int remaining, bool expectedLive) async {
      await tester.pumpWidget(
        pairBoardTestApp(
          boardKey: boardKey,
          model: pairBoardTestModel(
            state: state,
            timer: PairTimerState(
              mode: mode,
              remainingActiveMs: remaining,
              extensionUsed: extensionUsed,
            ),
          ),
        ),
      );
      final semantics = tester
          .getSemantics(find.byKey(const ValueKey<String>('pair-timer')))
          .getSemanticsData();
      expect(semantics.flagsCollection.isLiveRegion, expectedLive);
      expect(semantics.hasAction(SemanticsAction.tap), isFalse);
    }

    await pumpTimer(30050, false);
    await pumpTimer(29800, true);
    await pumpTimer(30050, false);
    await pumpTimer(29800, false);

    mode = PairTimerMode.extendedRunning;
    extensionUsed = true;
    await pumpTimer(10050, false);
    await pumpTimer(9800, true);
    await pumpTimer(10050, false);
    await pumpTimer(9800, false);

    state = PairMatchingEngine.previewTimerAction(
      state,
      PairTimerAction.restart,
    );
    mode = PairTimerMode.running;
    extensionUsed = false;
    await pumpTimer(30050, false);
    await pumpTimer(29800, true);
  });

  testWidgets(
    'status is polite live feedback and shell feedback keeps canonical slot',
    (tester) async {
      final state = PairMatchingState.initial(pairBoardTestPlan());
      final selected = <PairTile>[];
      final original = PairBoardView(
        model: pairBoardTestModel(
          state: state,
          statusMessage: 'คำตอบได้รับการบันทึกแล้ว',
        ),
        onSelectTile: selected.add,
        onRevealMapping: (_) {},
        onConfirmGuidedMapping: (_, _) {},
        onPronounce: (_) {},
      );
      final paired = original.withShellFeedback(
        const Text('ผลตอบกลับจากบทเรียน'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: M3Theme.lightTheme,
          home: Scaffold(body: AccessibilityScope(child: paired)),
        ),
      );
      final status = tester
          .getSemantics(find.byKey(const ValueKey<String>('pair-status')))
          .getSemanticsData();
      expect(status.flagsCollection.isLiveRegion, isTrue);
      expect(status.label, contains('คำตอบได้รับการบันทึกแล้ว'));
      expect(find.text('ผลตอบกลับจากบทเรียน'), findsOneWidget);
      await tester.tap(
        find.byKey(
          ValueKey<String>(
            'pair-tile:prompt:${state.orderFor(PairTileSide.prompt).first}',
          ),
        ),
      );
      expect(selected, hasLength(1));
    },
  );
}
