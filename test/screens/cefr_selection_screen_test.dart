import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/cefr_selection_screen.dart';

void main() {
  testWidgets(
    'CefrSelectionScreen renders tabs, search bar, and filters by query',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: CefrSelectionScreen()));
      await tester.pumpAndSettle();

      expect(find.text('คำศัพท์ตามระดับ'), findsOneWidget);
      expect(find.text('เริ่มทบทวนรายการนี้'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'achieve');
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(Card), matching: find.text('achieve')),
        findsOneWidget,
      );
    },
  );

  for (final size in const [
    Size(360, 800),
    Size(412, 915),
    Size(800, 360),
    Size(1280, 800),
  ]) {
    testWidgets('CEFR remains usable at 200 percent text on $size', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: CefrSelectionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('เริ่มทบทวนรายการนี้'), findsOneWidget);
      final title = tester.renderObject<RenderParagraph>(
        find.text('คำศัพท์ตามระดับ'),
      );
      expect(title.didExceedMaxLines, isFalse);
      final exception = tester.takeException();
      expect(exception, isNull);
    });
  }

  testWidgets('initial level and semantic colors follow the dark scheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: M3Theme.darkTheme,
        home: const CefrSelectionScreen(initialLevel: 'B2'),
      ),
    );
    await tester.pumpAndSettle();

    final scheme = M3Theme.darkTheme.colorScheme;
    final tabs = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabs.controller?.index, 4);
    expect(
      tester
          .widget<Container>(find.byKey(const ValueKey('cefr-summary')))
          .color,
      scheme.surfaceContainerLow,
    );
    final level = tester.widget<CircleAvatar>(
      find.byKey(const ValueKey('cefr-level-B2')).first,
    );
    expect(level.backgroundColor, scheme.primaryContainer);
    final levelLabel = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('cefr-level-B2')).first,
        matching: find.text('B2'),
      ),
    );
    expect(levelLabel.style?.color, scheme.onPrimaryContainer);
  });
}
