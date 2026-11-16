import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/learning_world_map_screen.dart';

void main() {
  testWidgets('LearningWorldMapScreen renders CEFR campaign nodes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LearningWorldMapScreen()));
    await tester.pumpAndSettle();

    expect(find.text('แผนที่การเรียนรู้'), findsOneWidget);
    expect(find.text('เกาะเริ่มต้น · ระดับ A1'), findsOneWidget);
  });

  testWidgets('campaign node opens the matching CEFR level', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LearningWorldMapScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ศูนย์ความรู้ · ระดับ B2'));
    await tester.pumpAndSettle();

    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller?.index, 4);
    expect(find.text('ระดับ B2'), findsOneWidget);
  });

  testWidgets('roadmap does not invent locked progress and supports dark 2x', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: LearningWorldMapScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.lock), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
