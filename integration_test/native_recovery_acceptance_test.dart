import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'support/native_recovery_fixture.dart';
import 'support/native_recovery_cases.dart';
import 'support/native_today_cases.dart' show todayAwait;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'BZ isolated pending and next actual Today OS restart',
    (tester) async {
      const channel = MethodChannel('lexiquest/native-recovery');
      final context = (await channel.invokeMapMethod<String, String>(
        'context',
      ))!;
      if (context['packageId'] != nativeRecoveryPackage ||
          !['seed', 'pending', 'next'].contains(context['phase'])) {
        throw StateError('Wrong BZ context');
      }
      final phase = context['phase']!;
      final run = context['runId']!;
      final support = Directory(context['supportPath']!);
      final receipt = <String, Object?>{
        'status': 'FAIL',
        'closed': false,
        'packageId': nativeRecoveryPackage,
        'runId': run,
        'phase': phase,
      };
      try {
        final fixture = await NativeRecoveryFixture.open(
          support,
          run,
          seed: phase == 'seed',
          requireAndroidSandbox: true,
        );
        HttpOverrides.global = fixture.network;
        final evidence = await runRecoveryPhase(tester, fixture, phase);
        receipt['transitions'] = evidence;
        receipt.addAll(evidence['after'] as Map<String, Object?>);
        final before = evidence['before'] as Map<String, Object?>?;
        receipt['beforeFixtureDigest'] = before?['fixtureDigest'];
        receipt['beforeProgressDigest'] = before?['progressDigest'];
        await tester.pumpWidget(const SizedBox.shrink());
        await todayAwait(tester, () => fixture.closeAndSealPhase(phase));
        receipt['cases'] = {
          for (final id
              in (phase == 'seed'
                  ? ['N01', 'N02', 'N03']
                  : phase == 'pending'
                  ? ['N04', 'N06']
                  : ['N07']))
            id: 'PASS',
        };
        receipt['closed'] = true;
        receipt['status'] = 'PASS';
      } catch (error) {
        receipt['failureType'] = error.runtimeType.toString();
        rethrow;
      } finally {
        await File(
          '${support.path}/$run-$phase.json',
        ).writeAsString(jsonEncode(receipt), flush: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
