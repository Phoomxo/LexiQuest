import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/support/native_resume_fixture.dart';
import '../../integration_test/support/native_resume_cases.dart';

void main() {
  test('BW verify rejects absent seed and traversal', () async {
    final root = await Directory.systemTemp.createTemp('bw-host-');
    await expectLater(
      NativeResumeFixture.open(root, 'bw-missing', seed: false),
      throwsStateError,
    );
    await expectLater(
      NativeResumeFixture.open(root, '../bad', seed: true),
      throwsArgumentError,
    );
    await expectLater(
      NativeResumeFixture.open(
        root,
        'bw-android',
        seed: true,
        requireAndroidSandbox: true,
      ),
      throwsStateError,
    );
  });
  testWidgets(
    'BW disk close reopen restores exact feedback with every table unchanged',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('bw-host-ui-'),
      ))!;
      final seed = await resumeAwait(
        tester,
        () => NativeResumeFixture.open(root, 'bw-host', seed: true),
      );
      await runResumePhase(tester, seed, seedPhase: true);
      final expected = await resumeAwait(tester, seed.snapshot);
      await tester.pumpWidget(const SizedBox.shrink());
      await resumeAwait(tester, seed.closeAndSeal);
      final verify = await resumeAwait(
        tester,
        () => NativeResumeFixture.open(root, 'bw-host', seed: false),
      );
      await resumeAwait(tester, () async {
        await expectLater(verify.seed(), throwsStateError);
      });
      await resumeAwait(tester, verify.verifySealed);
      await runResumePhase(tester, verify, seedPhase: false);
      expect(await resumeAwait(tester, verify.snapshot), expected);
      await tester.pumpWidget(const SizedBox.shrink());
      await resumeAwait(tester, verify.close);
      await resumeAwait(tester, () async {
        await expectLater(
          NativeResumeFixture.open(root, 'bw-host', seed: true),
          throwsStateError,
        );
      });
    },
  );
}
