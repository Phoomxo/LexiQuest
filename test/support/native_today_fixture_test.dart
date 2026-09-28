import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../integration_test/support/native_today_fixture.dart';
import '../../integration_test/support/native_today_cases.dart';

void main() {
  testWidgets('BY actual bootstrap Today survives disk close reopen exactly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('by-host-'),
    ))!;
    final seed = await todayAwait(
      tester,
      () => NativeTodayFixture.open(root, 'by-host', seed: true),
    );
    await runTodayPhase(tester, seed, seedPhase: true);
    await todayAwait(tester, seed.dependencies.learningReconciliation!.drain);
    final grants = await todayAwait(
      tester,
      () => seed.database.select(seed.database.rewardTransactions).get(),
    );
    expect(
      grants,
      hasLength(1),
      reason:
          'Ordinary committed answer must finish its canonical coin projection before restart',
    );
    final expected = await todayAwait(tester, seed.snapshot);
    await tester.pumpWidget(const SizedBox.shrink());
    await todayAwait(tester, seed.closeAndSeal);
    final verify = await todayAwait(
      tester,
      () => NativeTodayFixture.open(root, 'by-host', seed: false),
    );
    await todayAwait(tester, verify.verifySealed);
    await runTodayPhase(tester, verify, seedPhase: false);
    expect(await todayAwait(tester, verify.snapshot), expected);
    await tester.pumpWidget(const SizedBox.shrink());
    await todayAwait(tester, verify.close);
    await tester.runAsync(() async {
      await expectLater(
        NativeTodayFixture.open(root, 'by-host', seed: true),
        throwsStateError,
      );
      await expectLater(
        NativeTodayFixture.open(root, 'by-absent', seed: false),
        throwsStateError,
      );
      await expectLater(
        NativeTodayFixture.open(root, '../escape', seed: true),
        throwsArgumentError,
      );
      await expectLater(
        NativeTodayFixture.open(
          root,
          'by-android',
          seed: true,
          requireAndroidSandbox: true,
        ),
        throwsStateError,
      );
    });
  });
}
