import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/features/session/data/shared_preferences_app_entry_state_store.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'support/native_baseline_fixture.dart';
import 'support/native_baseline_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'BM isolated native baseline with explicit phase receipts',
    (tester) async {
      const channel = MethodChannel('lexiquest/native-baseline');
      final context = (await channel.invokeMapMethod<String, String>(
        'context',
      ))!;
      if (context['packageId'] != nativeBaselinePackage) {
        throw StateError('Wrong package');
      }
      final run = context['runId']!;
      final phase = context['phase']!;
      if (phase != 'seed' && phase != 'verify') {
        throw StateError('Invalid phase');
      }
      final support = Directory(context['supportPath']!);
      final cases = <String, String>{};
      NativeBaselineFixture? fixture;
      final receipt = <String, Object?>{
        'packageId': nativeBaselinePackage,
        'runId': run,
        'phase': phase,
        'status': 'FAIL',
        'closed': false,
        'cases': cases,
        'viewport': {
          'width': tester.view.physicalSize.width,
          'height': tester.view.physicalSize.height,
          'pixelRatio': tester.view.devicePixelRatio,
        },
      };
      try {
        fixture = await NativeBaselineFixture.open(
          support,
          run,
          seed: phase == 'seed',
          requireAndroidSandbox: true,
        );
        HttpOverrides.global = fixture.network;
        final prefs = await SharedPreferences.getInstance();
        final entry = SharedPreferencesAppEntryStateStore(prefs);
        if (phase == 'seed') {
          await fixture.seed();
          await entry.markGuest();
          for (final caseId in ['N01', 'N02', 'N03']) {
            cases[caseId] = 'RUNNING';
            await runBaselineCase(tester, fixture, entry, caseId);
            expect(tester.takeException(), isNull);
            cases[caseId] = 'PASS';
          }
          receipt.addAll(await fixture.snapshot());
          await fixture.closeAndSeal();
        } else {
          cases['N04'] = 'RUNNING';
          await prefs.reload();
          expect(await entry.read(), AppEntryMode.guest);
          // No bootstrap, seed, UI mounting or mutations in verify-only phase.
          receipt.addAll(await fixture.snapshot());
          await fixture.verifySealed();
          await fixture.close();
          cases['N04'] = 'PASS';
        }
        receipt['closed'] = true;
        receipt['status'] = 'PASS';
      } catch (error) {
        receipt['failureType'] = error.runtimeType.toString();
        for (final id in cases.keys.toList()) {
          if (cases[id] == 'RUNNING') cases[id] = 'FAIL';
        }
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // Receipts contain only synthetic identity, counts and test status.
        await File(
          '${support.path}/$run-$phase.json',
        ).writeAsString(jsonEncode(receipt), flush: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
