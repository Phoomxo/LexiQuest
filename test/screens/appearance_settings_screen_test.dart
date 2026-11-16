import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_appearance_preferences.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/appearance_settings_screen.dart';

void main() {
  testWidgets(
    'successful save applies the selected theme with acknowledgement',
    (tester) async {
      final preferences = _AppearancePreferences();
      final controller = await AppAppearanceController.load(preferences);
      addTearDown(controller.dispose);
      await _pumpAppearance(tester, controller: controller);

      await tester.tap(find.text('โหมดมืด'));
      await tester.tap(find.byKey(const ValueKey<String>('appearance-save')));
      await tester.pump();
      expect(controller.themeMode, ThemeMode.system);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .semanticsLabel,
        'กำลังบันทึกการแสดงผล',
      );

      preferences.saveResult.complete(true);
      await tester.pumpAndSettle();

      expect(controller.themeMode, ThemeMode.dark);
      expect(find.text('บันทึกการแสดงผลแล้ว'), findsOneWidget);
    },
  );

  testWidgets('failed save neither applies nor reports success', (
    tester,
  ) async {
    final controller = await AppAppearanceController.load(
      _AppearancePreferences(saveValue: false),
    );
    addTearDown(controller.dispose);
    await _pumpAppearance(tester, controller: controller);

    await tester.tap(find.text('โหมดสว่าง'));
    await tester.tap(find.byKey(const ValueKey<String>('appearance-save')));
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.system);
    expect(find.text('บันทึกการแสดงผลแล้ว'), findsNothing);
    final failure = find.text('บันทึกการแสดงผลไม่สำเร็จ กรุณาลองใหม่');
    expect(failure, findsOneWidget);
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(of: failure, matching: find.byType(Semantics)),
          )
          .any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );
  });

  testWidgets('controls fit 360x800 at 200 percent text with 48dp action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = await AppAppearanceController.load(
      _AppearancePreferences(saveValue: true),
    );
    addTearDown(controller.dispose);

    await _pumpAppearance(tester, controller: controller, textScale: 2);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('appearance-save')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('appearance-save')))
          .height,
      greaterThanOrEqualTo(48),
    );
  });
}

Future<void> _pumpAppearance(
  WidgetTester tester, {
  required AppAppearanceController controller,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    AppAppearanceScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => MaterialApp(
          theme: M3Theme.lightTheme,
          darkTheme: M3Theme.darkTheme,
          themeMode: controller.themeMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const AppearanceSettingsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _AppearancePreferences implements AppAppearancePreferences {
  _AppearancePreferences({this.saveValue});

  final bool? saveValue;
  final saveResult = Completer<bool>();

  @override
  Future<AppAppearanceMode> load() async => AppAppearanceMode.system;

  @override
  Future<bool> save(AppAppearanceMode mode) =>
      saveValue == null ? saveResult.future : Future<bool>.value(saveValue);
}
