import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_diagnostics.dart';
import 'package:vocab_learning_app/features/adventure/presentation/adventure_pair_renderer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_board_view.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import '../../learning/pair_matching/pair_board_view_test.dart'
    show pairBoardTestPlan;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final thaiFont = FontLoader(M3Theme.thaiFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([thaiFont.load(), materialIcons.load()]);
  });
  testWidgets('Playful Quest Thai regular six pair visual', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plan = pairBoardTestPlan(density: PairDensity.standard6);
    final model = PairBoardModel(
      state: PairMatchingState.initial(plan),
      timer: PairTimerState.initial(plan.timerPreset),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: M3Theme.lightTheme,
        home: Builder(
          builder: (context) => Localizations.override(
            context: context,
            locale: const Locale('th'),
            child: Scaffold(
              body: AdventurePairRenderer(
                model: model,
                diagnostics: AdventureDiagnostics(),
                reportFailure: (_) {},
                standardBoard: PairBoardView(
                  model: model,
                  onSelectTile: (_) {},
                  onRevealMapping: (_) {},
                  onConfirmGuidedMapping: (_, _) {},
                  onPronounce: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('pair-board-regular')), findsOneWidget);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/adventure_pair_th_regular.png'),
    );
  });
  for (final language in ['th', 'en']) {
    testWidgets(
      'Playful Quest $language text200 reduced motion preserves board semantics',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final plan = pairBoardTestPlan(longThai: true);
          final model = PairBoardModel(
            state: PairMatchingState.initial(plan),
            timer: PairTimerState.initial(plan.timerPreset),
          );
          var commands = 0;
          final board = PairBoardView(
            model: model,
            onSelectTile: (_) {
              commands++;
            },
            onRevealMapping: (_) {
              commands++;
            },
            onConfirmGuidedMapping: (_, _) {
              commands++;
            },
            onPronounce: (_) {
              commands++;
            },
          );
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: M3Theme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Localizations.override(
                  context: context,
                  locale: Locale(language),
                  child: Scaffold(
                    body: AdventurePairRenderer(
                      model: model,
                      standardBoard: board,
                      diagnostics: AdventureDiagnostics(),
                      reportFailure: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.widget<PairBoardView>(find.byType(PairBoardView)),
            same(board),
          );
          expect(
            find.byKey(const ValueKey('adventure-pair-chrome')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('pair-board-focused')),
            findsOneWidget,
          );
          expect(
            find.text('Explore each pair at your own pace.'),
            findsNothing,
          );
          expect(
            find.text('ค่อย ๆ สำรวจคำแต่ละคู่ในจังหวะของคุณ'),
            findsNothing,
          );
          final title = find.text(
            language == 'en' ? 'Pair quest' : 'ภารกิจจับคู่',
          );
          expect(
            tester.getBottomRight(title).dy,
            lessThanOrEqualTo(tester.getTopLeft(find.byType(PairBoardView)).dy),
            reason:
                'All visible chrome text fits above the canonical board viewport.',
          );
          expect(commands, 0);
          expect(tester.binding.transientCallbackCount, 0);
          final firstId = model.state.orderFor(PairTileSide.prompt).first;
          final tile = find.byKey(ValueKey('pair-tile:prompt:$firstId'));
          expect(
            tester
                .getSemantics(tile)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue,
          );
          await expectLater(
            find.byType(Scaffold),
            matchesGoldenFile(
              'goldens/adventure_pair_${language}_narrow_text200.png',
            ),
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'typed late health failure reports once without answer or diagnostic payload',
    (tester) async {
      final plan = pairBoardTestPlan();
      final health = AdventurePairDecorationHealth();
      final diagnostics = AdventureDiagnostics(maxCountPerCode: 1);
      final failures = <PairDecorationFailure>[];
      final model = PairBoardModel(
        state: PairMatchingState.initial(plan),
        timer: PairTimerState.initial(plan.timerPreset),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdventurePairRenderer(
              model: model,
              standardBoard: const Text('canonical board'),
              health: health,
              diagnostics: diagnostics,
              reportFailure: failures.add,
            ),
          ),
        ),
      );
      health.reportFailure(PairDecorationFailure.unavailable);
      health.reportFailure(PairDecorationFailure.unavailable);
      await tester.pump();
      expect(failures, [PairDecorationFailure.unavailable]);
      expect(diagnostics.snapshot().toJson(), {
        'schemaVersion': 1,
        'counters': {'entryFallbackDependencyUnavailable': 1},
      });
      await tester.pumpWidget(const SizedBox.shrink());
      health.dispose();
    },
  );
}
