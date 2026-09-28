import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/support/native_baseline_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'transport guard counts and rejects attempted external client creation',
    () {
      final guard = BaselineNoNetwork();
      HttpOverrides.runWithHttpOverrides(() {
        expect(() => HttpClient(), throwsStateError);
      }, guard);
      expect(guard.calls, 1);
    },
  );
  test('host directory cannot masquerade as Android package sandbox', () async {
    final root = await Directory.systemTemp.createTemp('bm-sandbox-');
    await expectLater(
      NativeBaselineFixture.open(
        root,
        'bm-unit',
        seed: true,
        requireAndroidSandbox: true,
      ),
      throwsStateError,
    );
    expect(await root.list().toList(), isEmpty);
  });
  test(
    'verify without seed rejects before directory/database mutation',
    () async {
      final root = await Directory.systemTemp.createTemp('bm-host-');
      await expectLater(
        NativeBaselineFixture.open(root, 'bm-unit', seed: false),
        throwsStateError,
      );
      expect(await root.list().toList(), isEmpty);
    },
  );
  test('run identity rejects traversal before mutation', () async {
    final root = await Directory.systemTemp.createTemp('bm-host-');
    await expectLater(
      NativeBaselineFixture.open(root, '../escape', seed: true),
      throwsArgumentError,
    );
    expect(await root.list().toList(), isEmpty);
  });
  test(
    'canonical owner word preferences and local cache survive verify-only reopen',
    () async {
      final root = await Directory.systemTemp.createTemp('bm-host-');
      final first = await NativeBaselineFixture.open(
        root,
        'bm-unit',
        seed: true,
      );
      await first.seed();
      await first.changePreferenceAndCreateWord();
      final before = await first.snapshot();
      expect(before['externalCalls'], 0);
      expect(before['researchRows'], 0);
      expect(before['outboxRows'], 0);
      await first.closeAndSeal();
      await expectLater(
        NativeBaselineFixture.open(root, 'bm-unit', seed: true),
        throwsStateError,
      );
      final second = await NativeBaselineFixture.open(
        root,
        'bm-unit',
        seed: false,
      );
      await expectLater(second.seed(), throwsStateError);
      final after = await second.snapshot();
      expect(after, before);
      expect(await second.verifySealed(), before['fixtureDigest']);
      await second.close();
    },
  );
}
