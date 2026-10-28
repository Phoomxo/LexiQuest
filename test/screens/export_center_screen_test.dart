import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';

void main() {
  testWidgets(
    'archive hides selective controls and selective formats retain choices',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ExportCenterScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('คลังคำศัพท์'), 200);
      await tester.tap(find.text('คลังคำศัพท์'));
      await tester.pump();
      final archive = find.byKey(ValueKey(ExportFormat.ownerArchiveJson));
      await tester.scrollUntilVisible(archive, -200);
      await tester.pumpAndSettle();
      await tester.tap(archive);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      final csv = find.byKey(ValueKey(ExportFormat.csv));
      await tester.scrollUntilVisible(csv, -200);
      await tester.pumpAndSettle();
      await tester.tap(csv);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('คลังคำศัพท์'), 200);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'คลังคำศัพท์'),
            )
            .value,
        isFalse,
      );
    },
  );

  testWidgets('formats fit narrow viewport with large text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const ExportCenterScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
