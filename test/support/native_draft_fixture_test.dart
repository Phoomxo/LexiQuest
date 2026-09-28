import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../integration_test/support/native_draft_fixture.dart';
import '../../integration_test/support/native_draft_cases.dart';
import '../../integration_test/support/native_today_cases.dart' show todayAwait;

void main() {
  const cePackage = 'com.lexiquest.app.nativeDraftCe';
  test('isolated draft run identity binds the correct package', () {
    expect(runIsolatedDraftPackage('cb-host'), nativeDraftPackage);
    expect(runIsolatedDraftPackage('cd-host'), nativeDraftCdPackage);
    expect(runIsolatedDraftPackage('ce-host'), cePackage);
    expect(() => runIsolatedDraftPackage('cb-../escape'), throwsStateError);
    expect(() => runIsolatedDraftPackage('cd-../escape'), throwsStateError);
    expect(() => runIsolatedDraftPackage('ce-../escape'), throwsStateError);
  });

  test('CE sandbox accepts only its own Android package path', () {
    for (final prefix in ['/data/user/0', '/data/data']) {
      expect(nativeDraftSandboxMatches(canonical: '$prefix/$cePackage/files', runId: 'ce-synthetic-01', isAndroid: true), isTrue);
      expect(nativeDraftSandboxMatches(canonical: '$prefix/$nativeDraftCdPackage/files', runId: 'ce-synthetic-01', isAndroid: true), isFalse);
    }
    expect(nativeDraftSandboxMatches(canonical: '/data/user/0/$cePackage/files', runId: 'ce-synthetic-01', isAndroid: false), isFalse);
  });

  test('CD sandbox accepts only its own Android package path', () {
    expect(
      nativeDraftSandboxMatches(
        canonical: '/data/user/0/$nativeDraftCdPackage/files',
        runId: 'cd-synthetic-01',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      nativeDraftSandboxMatches(
        canonical: '/data/user/0/$nativeDraftPackage/files',
        runId: 'cd-synthetic-01',
        isAndroid: true,
      ),
      isFalse,
    );
    expect(
      nativeDraftSandboxMatches(
        canonical: '/data/data/$nativeDraftCdPackage/files',
        runId: 'cd-synthetic-01',
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      nativeDraftSandboxMatches(
        canonical: '/data/user/0/$nativeDraftCdPackage/files',
        runId: 'cd-synthetic-01',
        isAndroid: false,
      ),
      isFalse,
    );
  });

  testWidgets('CB selected draft survives disk reopen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('cb-host-'),
    ))!;
    Map<String, Object?>? previous;
    for (final phase in ['seed', 'resume']) {
      final fixture = await todayAwait(
        tester,
        () => NativeDraftFixture.open(root, 'cb-host', seed: phase == 'seed'),
      );
      final receipt = await runDraftPhase(tester, fixture, phase);
      if (previous != null) {
        expect(
          receipt['before'],
          previous['after'],
          reason: 'All 58 tables and draft identity must survive reopening',
        );
      }
      previous = receipt;
      await tester.pumpWidget(const SizedBox.shrink());
      await todayAwait(tester, () => fixture.closeAndSealPhase(phase));
    }
    await tester.runAsync(() async {
      await expectLater(
        NativeDraftFixture.open(root, 'cb-host', seed: true),
        throwsStateError,
      );
      await expectLater(
        NativeDraftFixture.open(root, 'cb-absent', seed: false),
        throwsStateError,
      );
      await expectLater(
        NativeDraftFixture.open(root, '../escape', seed: true),
        throwsArgumentError,
      );
      await expectLater(
        NativeDraftFixture.open(
          root,
          'cb-android',
          seed: true,
          requireAndroidSandbox: true,
        ),
        throwsStateError,
      );
    });
  });
}
