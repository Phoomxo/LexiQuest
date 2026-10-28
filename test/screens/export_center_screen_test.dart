import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';

void main() {
  testWidgets('optional export guidance reflects format without write tools', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => 'test');
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: MaterialApp(home: ExportCenterScreen(ownerIdentities: _Owner())),
      ),
    );
    await tester.pumpAndSettle();
    for (final format in ExportFormat.values) {
      final choice = find.byKey(ValueKey(format));
      await tester.scrollUntilVisible(
        choice,
        format == ExportFormat.csv ? -200 : 200,
      );
      await tester.tap(choice);
      await tester.pumpAndSettle();
      final data = jsonDecode(
        (registry.snapshot()['context'] as List).single['value'] as String,
      );
      expect(data['format'], format.name);
      expect(data['status'], 'idle');
      expect(
        data['researchConsentRequired'],
        format == ExportFormat.researchJson,
      );
      expect(
        data['scope'],
        format == ExportFormat.anki
            ? 'vocabulary-only'
            : format == ExportFormat.ownerArchiveJson
            ? 'owner-manifest-not-restore'
            : 'selected-data',
      );
      expect(registry.snapshot()['actions'], isEmpty);
    }
  });

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

final class _Owner implements ReviewOwnerIdentityReader {
  @override
  Future<String> requireSingleActiveOwnerId() async => 'test';
}
