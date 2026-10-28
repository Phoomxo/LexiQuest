import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';

import 'pair_board_view_test.dart';

const _phone = Size(412, 915);
const _narrow = Size(320, 720);
const _wide = Size(1280, 900);
const _goldenDirectory = 'goldens/pair_board';

void _setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _expectGolden(WidgetTester tester, String name) async {
  await tester.pump();
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byType(Scaffold),
    matchesGoldenFile('$_goldenDirectory/$name'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final thaiFont = FontLoader(M3Theme.thaiFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait(<Future<void>>[thaiFont.load(), materialIcons.load()]);
  });

  testWidgets('golden: Thai regular six-pair board', (tester) async {
    _setSurface(tester, _phone);
    final state = PairMatchingState.initial(
      pairBoardTestPlan(density: PairDensity.standard6),
    );
    await tester.pumpWidget(
      pairBoardTestApp(
        model: pairBoardTestModel(state: state),
        size: _phone,
      ),
    );
    await _expectGolden(tester, 'thai_regular_standard6.png');
  });

  testWidgets('golden: Thai compact four-pair board', (tester) async {
    _setSurface(tester, _phone);
    final state = PairMatchingState.initial(pairBoardTestPlan());
    await tester.pumpWidget(
      pairBoardTestApp(
        model: pairBoardTestModel(state: state),
        size: _phone,
      ),
    );
    await _expectGolden(tester, 'thai_regular_compact4.png');
  });

  testWidgets('golden: English reverse board', (tester) async {
    _setSurface(tester, _phone);
    final plan = pairBoardTestPlan(direction: PairDirection.thToEn);
    final firstId = plan.sourceOrder.first;
    final state = pairBoardSelect(
      PairMatchingState.initial(plan),
      PairTileSide.prompt,
      firstId,
    );
    await tester.pumpWidget(
      pairBoardTestApp(
        model: pairBoardTestModel(state: state, audioAvailable: true),
        locale: const Locale('en'),
        size: _phone,
      ),
    );
    await _expectGolden(tester, 'english_reverse_selected.png');
  });

  testWidgets('golden: long Thai at 200 percent in focused narrow layout', (
    tester,
  ) async {
    _setSurface(tester, _narrow);
    final plan = pairBoardTestPlan(
      longThai: true,
      direction: PairDirection.thToEn,
    );
    final state = pairBoardSelect(
      PairMatchingState.initial(plan),
      PairTileSide.prompt,
      plan.orderedLexicalItems.first.wordId,
    );
    await tester.pumpWidget(
      pairBoardTestApp(
        model: pairBoardTestModel(state: state),
        size: _narrow,
        textScale: 2,
      ),
    );
    await _expectGolden(tester, 'thai_long_narrow_text_200.png');
    await tester.ensureVisible(
      find.byKey(const ValueKey('pair-focused-source')),
    );
    await _expectGolden(tester, 'thai_long_narrow_text_200_scrolled.png');
  });

  testWidgets('golden: wide board content stays centered and bounded', (
    tester,
  ) async {
    _setSurface(tester, _wide);
    final state = PairMatchingState.initial(
      pairBoardTestPlan(density: PairDensity.standard6),
    );
    await tester.pumpWidget(
      pairBoardTestApp(
        model: pairBoardTestModel(state: state),
        size: _wide,
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('pair-board-content'))).width,
      lessThanOrEqualTo(800),
    );
    await _expectGolden(tester, 'thai_wide_bounded.png');
  });

  testWidgets('golden: wrong repair state in dark high contrast', (
    tester,
  ) async {
    _setSurface(tester, _phone);
    final plan = pairBoardTestPlan();
    final state = pairBoardWrong(
      PairMatchingState.initial(plan),
      plan.orderedLexicalItems.first.wordId,
    );
    await tester.pumpWidget(
      pairBoardTestApp(
        model: pairBoardTestModel(state: state),
        size: _phone,
        themeMode: ThemeMode.dark,
        highContrast: true,
      ),
    );
    await _expectGolden(tester, 'thai_dark_high_contrast_wrong_repair.png');
  });

  testWidgets('golden: guided board honors reduced motion and audio fallback', (
    tester,
  ) async {
    _setSurface(tester, _phone);
    final plan = pairBoardTestPlan();
    final state = pairBoardGuidedState(plan);
    await tester.pumpWidget(
      pairBoardTestApp(
        model: pairBoardTestModel(
          state: state,
          audioFallback: 'แสดงคำและสัทอักษรแทนเสียง',
        ),
        size: _phone,
        reducedMotion: true,
      ),
    );
    await _expectGolden(tester, 'thai_guided_reduced_motion_no_audio.png');
  });
}
