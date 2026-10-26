import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';

void main() {
  void useCompactViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 876);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<void> revealInDrawer(WidgetTester tester, Finder item) async {
    await tester.scrollUntilVisible(
      item,
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact shell renders destinations and switches tabs', (
    WidgetTester tester,
  ) async {
    useCompactViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((destination) => destination.label),
      <String>['เรียน', 'คำศัพท์', 'ก้าวหน้า', 'โปรไฟล์'],
    );

    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pumpAndSettle();
    expect(find.text('ภาพรวมการเรียน'), findsOneWidget);

    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
  });

  testWidgets('shell switches from bottom navigation to rail at 600dp', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(599, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    final compactLearnState = tester.state<State>(
      find.byType(ChooseModeScreen),
    );

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsOneWidget);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(
      rail.destinations.map((destination) => (destination.label as Text).data),
      <String>['เรียน', 'คำศัพท์', 'ก้าวหน้า', 'โปรไฟล์'],
    );
    expect(
      tester.state<State>(find.byType(ChooseModeScreen)),
      same(compactLearnState),
    );
  });

  testWidgets('short landscape keeps the compact single-pane shell', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 360);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shell follows the approved phone and tablet matrix', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    for (final (size, usesRail) in <(Size, bool)>[
      (const Size(360, 800), false),
      (const Size(393, 876), false),
      (const Size(412, 915), false),
      (const Size(600, 960), true),
      (const Size(840, 900), true),
      (const Size(1280, 800), true),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();

      expect(
        find.byType(NavigationRail),
        usesRail ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(NavigationBar),
        usesRail ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'viewport $size');
    }
  });

  testWidgets('height boundary preserves state while switching shell', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 479);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    final compactState = tester.state<State>(find.byType(ChooseModeScreen));

    tester.view.physicalSize = const Size(800, 480);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      tester.state<State>(find.byType(ChooseModeScreen)),
      same(compactState),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large tablet keeps the adaptive shell within 1200dp', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
    await tester.pumpAndSettle();

    final railBounds = tester.getRect(find.byType(NavigationRail));
    final contentBounds = tester.getRect(find.byType(IndexedStack));
    expect(contentBounds.right - railBounds.left, lessThanOrEqualTo(1200));

    final menu = find.byKey(const ValueKey<String>('shell-drawer-button'));
    final firstLabel = find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('เรียน'),
    );
    expect(tester.getRect(menu).overlaps(tester.getRect(firstLabel)), isFalse);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
  });

  testWidgets('shell controls remain usable at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    useCompactViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MainNavigationScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final size in const [Size(360, 800), Size(800, 360)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey<String>('shell-drawer-button'));
      final menuSize = tester.getSize(menu);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(menuSize.width, greaterThanOrEqualTo(48));
      expect(menuSize.height, greaterThanOrEqualTo(48));
      final title = find.text('เลือกแบบฝึก');
      final titleParagraph = tester.renderObject<RenderParagraph>(title);
      expect(titleParagraph.didExceedMaxLines, isFalse, reason: '$size');
      expect(
        tester.getRect(menu).overlaps(tester.getRect(title)),
        isFalse,
        reason: '$size',
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }

    await tester.tap(find.byKey(const ValueKey<String>('shell-drawer-button')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single visible workspace keeps settings reachable', (
    WidgetTester tester,
  ) async {
    useCompactViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(
          featureRegistry: BuildFieldFeatureRegistry({}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('shell-drawer-button')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden progress features stay inaccessible from root screens', (
    WidgetTester tester,
  ) async {
    useCompactViewport(tester);
    const registry = BuildFieldFeatureRegistry({
      FieldFeature.quiz: FieldFeatureState.enabled,
      FieldFeature.mastery: FieldFeatureState.enabled,
    });
    await tester.pumpWidget(
      const MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ฝึกจุดอ่อน'), findsNothing);
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pumpAndSettle();
    expect(find.text('คำที่ควรฝึกเพิ่ม'), findsNothing);
    expect(find.text('ความสำเร็จ'), findsNothing);
    expect(find.text('ร้านธีม'), findsNothing);
  });

  testWidgets('field composition exposes completed field destinations', (
    WidgetTester tester,
  ) async {
    useCompactViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(
          featureRegistry: BuildFieldFeatureRegistry.fieldDefaults(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((destination) => destination.label),
      <String>['เรียน', 'คำศัพท์', 'ก้าวหน้า', 'โปรไฟล์'],
    );
    await tester.tap(find.byKey(const ValueKey<String>('shell-drawer-button')));
    await tester.pumpAndSettle();
    expect(find.text('ร้านค้ารางวัล'), findsOneWidget);
    expect(find.text('สแกนวัตถุ'), findsOneWidget);
    expect(find.text('ฝึกพูดตามเสียง'), findsOneWidget);
    await revealInDrawer(tester, find.text('ผู้ช่วยฝึกภาษาอังกฤษ'));
    expect(find.text('ผู้ช่วยฝึกภาษาอังกฤษ'), findsOneWidget);
    expect(find.text('ตั้งค่าผู้ช่วย AI'), findsNothing);
  });

  testWidgets('limited features explain requirements and offer setup actions', (
    WidgetTester tester,
  ) async {
    useCompactViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(
          featureRegistry: BuildFieldFeatureRegistry.fieldDefaults(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('shell-drawer-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('ทดลองใช้'), findsNWidgets(3));
    expect(find.textContaining('อนุญาตกล้อง'), findsOneWidget);
    expect(find.textContaining('อนุญาตไมโครโฟน'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'เตรียมใช้'), findsNWidgets(2));

    await revealInDrawer(tester, find.text('ผู้ช่วยฝึกภาษาอังกฤษ'));
    expect(find.textContaining('ต้องเชื่อมต่อผู้ช่วย AI'), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, 'เชื่อมต่อผู้ช่วย AI'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'เชื่อมต่อผู้ช่วย AI'));
    await tester.pumpAndSettle();
    expect(find.text('เชื่อมต่อ Gemini'), findsOneWidget);
  });

  testWidgets('enabled features do not show limited-state disclosure', (
    WidgetTester tester,
  ) async {
    useCompactViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(
          featureRegistry: BuildFieldFeatureRegistry.allEnabled(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('shell-drawer-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('ทดลองใช้'), findsNothing);
    expect(find.widgetWithText(TextButton, 'เตรียมใช้'), findsNothing);
    expect(
      find.widgetWithText(TextButton, 'เชื่อมต่อผู้ช่วย AI'),
      findsNothing,
    );
  });

  testWidgets('limited disclosures remain usable at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    useCompactViewport(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MainNavigationScreen(
            featureRegistry: BuildFieldFeatureRegistry.fieldDefaults(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('shell-drawer-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final button in tester.widgetList<TextButton>(
      find.widgetWithText(TextButton, 'เตรียมใช้'),
    )) {
      expect(button.onPressed, isNotNull);
    }

    await revealInDrawer(tester, find.text('ผู้ช่วยฝึกภาษาอังกฤษ'));
    expect(
      find.widgetWithText(TextButton, 'เชื่อมต่อผู้ช่วย AI'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
