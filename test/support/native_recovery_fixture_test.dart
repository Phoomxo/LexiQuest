import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../integration_test/support/native_recovery_fixture.dart';
import '../../integration_test/support/native_recovery_cases.dart';
import '../../integration_test/support/native_today_cases.dart' show todayAwait;

void main() {
  testWidgets('BZ pending lost acknowledgement and next survive disk reopen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('bz-host-'),
    ))!;
    Map<String, Object?>? previous;
    for (final phase in ['seed', 'pending', 'next']) {
      final fixture = await todayAwait(
        tester,
        () =>
            NativeRecoveryFixture.open(root, 'bz-host', seed: phase == 'seed'),
      );
      final receipt = await runRecoveryPhase(tester, fixture, phase);
      if (previous != null) {
        expect(
          receipt['before'],
          previous['after'],
          reason: 'Every table and exact frozen state must survive reopening',
        );
      }
      previous = receipt;
      await tester.pumpWidget(const SizedBox.shrink());
      await todayAwait(tester, () => fixture.closeAndSealPhase(phase));
    }
    await tester.runAsync(() async {
      await expectLater(
        NativeRecoveryFixture.open(root, 'bz-host', seed: true),
        throwsStateError,
      );
      await expectLater(
        NativeRecoveryFixture.open(root, 'bz-absent', seed: false),
        throwsStateError,
      );
      await expectLater(
        NativeRecoveryFixture.open(root, '../escape', seed: true),
        throwsArgumentError,
      );
      await expectLater(
        NativeRecoveryFixture.open(
          root,
          'bz-android',
          seed: true,
          requireAndroidSandbox: true,
        ),
        throwsStateError,
      );
    });
  });
}
