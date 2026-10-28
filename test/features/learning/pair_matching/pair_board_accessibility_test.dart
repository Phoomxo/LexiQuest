import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';

import 'pair_board_view_test.dart';

void _setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

OutlinedButton _tileButton(WidgetTester tester, PairTile tile) =>
    tester.widget<OutlinedButton>(
      find.byKey(
        ValueKey<String>('pair-tile:${tile.side.name}:${tile.wordId}'),
      ),
    );

void _performSemanticsTap(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  tester.binding.performSemanticsAction(
    SemanticsActionEvent(
      type: SemanticsAction.tap,
      nodeId: node.id,
      viewId: tester.view.viewId,
    ),
  );
}

void main() {
  testWidgets(
    'narrow, 200 percent text, accessible navigation, and explicit policy select focused flow',
    (tester) async {
      final state = PairMatchingState.initial(pairBoardTestPlan());
      for (final policy
          in <
            ({
              Size size,
              double scale,
              bool accessibleNavigation,
              bool focusedTraversal,
            })
          >[
            (
              size: const Size(359, 700),
              scale: 1,
              accessibleNavigation: false,
              focusedTraversal: false,
            ),
            (
              size: const Size(412, 800),
              scale: 2,
              accessibleNavigation: false,
              focusedTraversal: false,
            ),
            (
              size: const Size(412, 800),
              scale: 1,
              accessibleNavigation: true,
              focusedTraversal: false,
            ),
            (
              size: const Size(412, 800),
              scale: 1,
              accessibleNavigation: false,
              focusedTraversal: true,
            ),
          ]) {
        _setSurface(tester, policy.size);
        await tester.pumpWidget(
          pairBoardTestApp(
            model: pairBoardTestModel(
              state: state,
              focusedTraversal: policy.focusedTraversal,
            ),
            size: policy.size,
            textScale: policy.scale,
            accessibleNavigation: policy.accessibleNavigation,
          ),
        );
        expect(
          find.byKey(const ValueKey<String>('pair-board-focused')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('pair-board-regular')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'focused traversal moves source to targets and returns without an answer',
    (tester) async {
      _setSurface(tester, const Size(340, 760));
      final plan = pairBoardTestPlan();
      var state = PairMatchingState.initial(plan);
      final selected = <PairTile>[];
      Widget app() => pairBoardTestApp(
        model: pairBoardTestModel(state: state, focusedTraversal: true),
        size: const Size(340, 760),
        onSelectTile: selected.add,
      );

      await tester.pumpWidget(app());
      expect(find.text('เลือกคำ'), findsOneWidget);
      final sourceId = state.orderFor(PairTileSide.prompt).first;
      await tester.tap(
        find.byKey(ValueKey<String>('pair-tile:prompt:$sourceId')),
      );
      expect(selected, hasLength(1));
      expect(selected.single.side, PairTileSide.prompt);
      expect(selected.single.wordId, sourceId);

      state = pairBoardSelect(state, PairTileSide.prompt, sourceId);
      selected.clear();
      await tester.pumpWidget(app());
      expect(find.text('คำที่เลือก'), findsOneWidget);
      expect(find.text('เลือกความหมาย'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('pair-focused-source')),
        findsOneWidget,
      );
      final targetId = state.orderFor(PairTileSide.target).first;
      await tester.tap(
        find.byKey(ValueKey<String>('pair-tile:target:$targetId')),
      );
      expect(selected, hasLength(1));
      expect(selected.single.side, PairTileSide.target);
      expect(selected.single.wordId, targetId);

      selected.clear();
      await tester.tap(
        find.byKey(const ValueKey<String>('pair-change-source')),
      );
      expect(selected, hasLength(1));
      expect(selected.single.side, PairTileSide.prompt);
      expect(selected.single.wordId, sourceId);
    },
  );

  testWidgets(
    'Tab, Enter, Space, and semantics tap dispatch one identity callback each',
    (tester) async {
      _setSurface(tester, const Size(340, 760));
      final state = PairMatchingState.initial(pairBoardTestPlan());
      final calls = <PairTile>[];
      var reveals = 0;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          pairBoardTestApp(
            model: pairBoardTestModel(state: state, focusedTraversal: true),
            size: const Size(340, 760),
            onSelectTile: calls.add,
            onRevealMapping: (_) => reveals++,
          ),
        );
        final firstId = state.orderFor(PairTileSide.prompt).first;
        final first = find.byKey(ValueKey<String>('pair-tile:prompt:$firstId'));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          _tileButton(
            tester,
            PairTile(PairTileSide.prompt, firstId),
          ).focusNode?.hasFocus,
          isTrue,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(calls, hasLength(1));

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(calls, hasLength(2));

        final node = tester.getSemantics(first);
        tester.binding.performSemanticsAction(
          SemanticsActionEvent(
            type: SemanticsAction.tap,
            nodeId: node.id,
            viewId: tester.view.viewId,
          ),
        );
        await tester.pump();
        expect(calls, hasLength(3));
        expect(calls.every((tile) => tile.wordId == firstId), isTrue);
        expect(
          reveals,
          0,
          reason: 'focus and activation must never reveal an answer',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'focus nodes survive resize, locale, accessibility, and unrelated state changes',
    (tester) async {
      final boardKey = GlobalKey();
      final plan = pairBoardTestPlan();
      final selectedId = plan.orderedLexicalItems.first.wordId;
      var state = pairBoardSelect(
        PairMatchingState.initial(plan),
        PairTileSide.prompt,
        selectedId,
      );
      final targetId = state
          .orderFor(PairTileSide.target)
          .firstWhere((id) => id != selectedId);

      await tester.pumpWidget(
        pairBoardTestApp(
          boardKey: boardKey,
          model: pairBoardTestModel(state: state),
          locale: const Locale('th'),
          size: const Size(600, 800),
        ),
      );
      final tile = PairTile(PairTileSide.target, targetId);
      final originalNode = _tileButton(tester, tile).focusNode;
      expect(originalNode, isNotNull);

      await tester.pumpWidget(
        pairBoardTestApp(
          boardKey: boardKey,
          model: pairBoardTestModel(state: state, focusedTraversal: true),
          locale: const Locale('en'),
          size: const Size(340, 760),
          textScale: 2,
          accessibleNavigation: true,
        ),
      );
      expect(
        identical(_tileButton(tester, tile).focusNode, originalNode),
        isTrue,
      );

      final other = plan.orderedLexicalItems
          .map((item) => item.wordId)
          .firstWhere((id) => id != selectedId && id != targetId);
      state = pairBoardMatch(PairMatchingState.initial(plan), other);
      state = pairBoardSelect(state, PairTileSide.prompt, selectedId);
      await tester.pumpWidget(
        pairBoardTestApp(
          boardKey: boardKey,
          model: pairBoardTestModel(state: state, focusedTraversal: true),
          locale: const Locale('en'),
          size: const Size(340, 760),
        ),
      );
      expect(
        identical(_tileButton(tester, tile).focusNode, originalNode),
        isTrue,
      );
    },
  );

  testWidgets(
    'a newly matched pair focuses the first actionable unmatched prompt',
    (tester) async {
      final boardKey = GlobalKey();
      final plan = pairBoardTestPlan();
      var state = PairMatchingState.initial(plan);
      await tester.pumpWidget(
        pairBoardTestApp(
          boardKey: boardKey,
          model: pairBoardTestModel(state: state),
        ),
      );
      final matchedId = state.orderFor(PairTileSide.prompt).first;
      final matchedTarget = find.byKey(
        ValueKey<String>('pair-tile:target:$matchedId'),
      );
      _tileButton(
        tester,
        PairTile(PairTileSide.target, matchedId),
      ).focusNode!.requestFocus();
      await tester.pump();
      expect(
        tester.getSemantics(matchedTarget).flagsCollection.isFocused,
        Tristate.isTrue,
      );

      state = pairBoardMatch(state, matchedId);
      await tester.pumpWidget(
        pairBoardTestApp(
          boardKey: boardKey,
          model: pairBoardTestModel(state: state),
        ),
      );
      await tester.pump();
      final nextId = state
          .orderFor(PairTileSide.prompt)
          .firstWhere((id) => !state.matchedWordIds.contains(id));
      expect(
        _tileButton(
          tester,
          PairTile(PairTileSide.prompt, nextId),
        ).focusNode?.hasFocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'reverse direction exposes language-aware labels without duplicate nodes',
    (tester) async {
      final plan = pairBoardTestPlan(direction: PairDirection.thToEn);
      final state = PairMatchingState.initial(plan);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          pairBoardTestApp(
            model: pairBoardTestModel(state: state),
            locale: const Locale('en'),
          ),
        );
        final first = plan.orderedLexicalItems.first;
        expect(
          find.bySemanticsLabel(
            RegExp('Thai.*${RegExp.escape(first.meaning)}'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('English.*${RegExp.escape(first.spelling)}'),
          ),
          findsOneWidget,
        );
        for (final side in PairTileSide.values) {
          final tile = find.byKey(
            ValueKey<String>('pair-tile:${side.name}:${first.wordId}'),
          );
          final data = tester.getSemantics(tile).getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isTrue);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'guided confirmation semantics dispatches exact identity once in regular and focused flows',
    (tester) async {
      final plan = pairBoardTestPlan();
      final state = pairBoardGuidedState(plan);
      final guidedId = plan.orderedLexicalItems.first.wordId;
      final shownRevision = state.supportAtRevision[guidedId]!;
      final confirmations = <(String, int)>[];
      var selections = 0;
      var reveals = 0;
      final semantics = tester.ensureSemantics();
      try {
        for (final focused in <bool>[false, true]) {
          confirmations.clear();
          await tester.pumpWidget(
            pairBoardTestApp(
              model: pairBoardTestModel(
                state: state,
                focusedTraversal: focused,
              ),
              onSelectTile: (_) => selections++,
              onRevealMapping: (_) => reveals++,
              onConfirmGuidedMapping: (id, revision) =>
                  confirmations.add((id, revision)),
            ),
          );
          final confirm = find.byKey(
            ValueKey<String>('pair-confirm-guided:$guidedId'),
          );
          await tester.ensureVisible(confirm);
          await tester.pump();
          expect(
            tester
                .getSemantics(confirm)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );

          _performSemanticsTap(tester, confirm);
          await tester.pump();

          expect(confirmations, <(String, int)>[(guidedId, shownRevision)]);
          expect(selections, 0);
          expect(reveals, 0);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'busy and pending guided confirmations expose no semantics tap action',
    (tester) async {
      final plan = pairBoardTestPlan();
      final guided = pairBoardGuidedState(plan);
      final guidedId = plan.orderedLexicalItems.first.wordId;
      final otherId = plan.orderedLexicalItems
          .map((item) => item.wordId)
          .firstWhere(
            (id) =>
                id != guidedId &&
                !guided.matchedWordIds.contains(id) &&
                !guided.supportedWordIds.contains(id),
          );
      var pending = pairBoardSelect(
        guided,
        PairTileSide.prompt,
        otherId,
        suffix: 'pending-prompt',
      );
      pending = pairBoardSelect(
        pending,
        PairTileSide.target,
        otherId,
        suffix: 'pending-target',
      );
      expect(pending.pending, isNotNull);
      var confirmations = 0;
      final semantics = tester.ensureSemantics();
      try {
        for (final configuration
            in <({PairMatchingState state, bool busy, bool focused})>[
              (state: guided, busy: true, focused: false),
              (state: guided, busy: true, focused: true),
              (state: pending, busy: false, focused: false),
              (state: pending, busy: false, focused: true),
            ]) {
          await tester.pumpWidget(
            pairBoardTestApp(
              model: pairBoardTestModel(
                state: configuration.state,
                busy: configuration.busy,
                focusedTraversal: configuration.focused,
              ),
              onConfirmGuidedMapping: (_, _) => confirmations++,
            ),
          );
          final confirm = find.byKey(
            ValueKey<String>('pair-confirm-guided:$guidedId'),
          );
          await tester.ensureVisible(confirm);
          await tester.pump();
          expect(
            tester
                .getSemantics(confirm)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
        }
        expect(confirmations, 0);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'long Thai at 200 percent wraps essential labels without ellipsis',
    (tester) async {
      _setSurface(tester, const Size(320, 720));
      final plan = pairBoardTestPlan(longThai: true);
      final state = pairBoardSelect(
        PairMatchingState.initial(plan),
        PairTileSide.prompt,
        plan.orderedLexicalItems.first.wordId,
      );
      await tester.pumpWidget(
        pairBoardTestApp(
          model: pairBoardTestModel(state: state),
          size: const Size(320, 720),
          textScale: 2,
        ),
      );
      expect(
        find.byKey(const ValueKey<String>('pair-board-focused')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      for (final text in tester.widgetList<Text>(find.byType(Text))) {
        expect(text.overflow, isNot(TextOverflow.ellipsis));
      }
    },
  );
}
