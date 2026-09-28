import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../integration_test/support/native_terminal_fixture.dart';
import '../../integration_test/support/native_terminal_cases.dart';
import '../../integration_test/support/native_today_cases.dart' show todayAwait;

void main() {
  testWidgets('CA committed terminal acknowledgement survives disk reopen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = (await tester.runAsync(() => Directory.systemTemp.createTemp('ca-host-')))!;
    Map<String, Object?>? previous;
    for (final phase in ['seed', 'resume', 'closed']) {
      final fixture = await todayAwait(tester, () => NativeTerminalFixture.open(root, 'ca-host', seed: phase == 'seed'));
      final receipt = await runTerminalPhase(tester, fixture, phase);
      if (previous != null) {
        expect(receipt['before'], previous['after'], reason: 'All 58 tables and terminal identity must survive reopening');
      }
      previous = receipt;
      await tester.pumpWidget(const SizedBox.shrink());
      await todayAwait(tester, () => fixture.closeAndSealPhase(phase));
    }
    await tester.runAsync(() async {
      await expectLater(NativeTerminalFixture.open(root, 'ca-host', seed: true), throwsStateError);
      await expectLater(NativeTerminalFixture.open(root, 'ca-absent', seed: false), throwsStateError);
      await expectLater(NativeTerminalFixture.open(root, '../escape', seed: true), throwsArgumentError);
      await expectLater(NativeTerminalFixture.open(root, 'ca-android', seed: true, requireAndroidSandbox: true), throwsStateError);
    });
  });
}
