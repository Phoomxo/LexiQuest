import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';

import '../test/screens/bundled_starter_pack_flow_test.dart' as starter;
import '../test/screens/learning_pack_test_support.dart';
import '../test/screens/matching_entry_history_flow_test.dart' as matching;
import '../test/screens/native_durable_resume_screen_test.dart' as native;
import '../test/screens/recall_ladder_entry_flow_test.dart' as recall;
import '../test/screens/score_continuation_test.dart' as score;
import '../test/screens/today_resume_panel_test.dart' as resume;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Starter entry', starter.main);
  group('Recommendation destinations', recall.main);
  group('Direct resume', resume.main);
  group('Matching resume routes', matching.main);
  group('Native resume routes', native.main);
  group('Result continuation', score.main);

  testWidgets('Android result remains reachable at double text size', (
    tester,
  ) async {
    expect(Platform.isAndroid, isTrue);
    expect(tester.view.physicalSize.width / tester.view.devicePixelRatio, 320);
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: M3Theme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ScoreScreen(
          correctAnswers: 10,
          wrongAnswers: 0,
          backLabel: 'กลับหน้าเรียน',
          onBack: () => completed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await _capture(binding, tester, 'score-top-2x');
    final finish = find.widgetWithText(FilledButton, 'กลับหน้าเรียน');
    await tester.ensureVisible(finish);
    await tester.pumpAndSettle();
    expect(finish.hitTestable(), findsOneWidget);
    await _capture(binding, tester, 'score-action-2x');
    await tester.tap(finish);
    expect(completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android catalog offers starter before importing a file', (
    tester,
  ) async {
    final harness = (await tester.runAsync(LearningPackUiHarness.open))!;
    try {
      expect(
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
        320,
      );
      await tester.pumpWidget(harness.app(largeText: true));
      await packUiReady(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('pack-open-starter')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await _capture(binding, tester, 'catalog-starter');
      await tapPackUi(tester, 'pack-open-starter');
      await revealPackUi(tester, 'pack-confirm-install');
      await _capture(binding, tester, 'starter-preview');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await closePackUi(tester, harness);
    }
  });
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
) async {
  final bytes = await binding.takeScreenshot(name);
  expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  await tester.runAsync(() async {
    final directory = Directory('${Directory.systemTemp.path}/lexiquest-flow');
    await directory.create(recursive: true);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('UX_SCREENSHOT ${file.path}');
  });
}
