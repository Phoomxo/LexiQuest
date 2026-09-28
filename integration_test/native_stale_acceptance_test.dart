import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'support/native_stale_fixture.dart';
import 'support/native_stale_cases.dart';
import 'support/native_today_cases.dart' show todayAwait;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'CF isolated stale route and revision rejection after Today restart',
    (tester) async {
      const channel = MethodChannel('lexiquest/native-stale');
      final context = (await channel.invokeMapMethod<String, String>(
        'context',
      ))!;
      final package = runIsolatedStalePackage(context['runId'] ?? '');
      if (context['packageId'] != package ||
          !['seed', 'resume'].contains(context['phase'])) {
        throw StateError('Wrong isolated draft context');
      }
      final phase = context['phase']!;
      final run = context['runId']!;
      final support = Directory(context['supportPath']!);
      final receipt = <String, Object?>{
        'status': 'FAIL',
        'closed': false,
        'packageId': package,
        'runId': run,
        'phase': phase,
      };
      try {
        final fixture = await NativeStaleFixture.open(
          support,
          run,
          seed: phase == 'seed',
          requireAndroidSandbox: true,
        );
        HttpOverrides.global = fixture.network;
        final evidence = await runStalePhase(tester, fixture, phase);
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
                  ? ['CF01', 'CF02']
                  : phase == 'resume'
                  ? ['CF03', 'CF04', 'CF05']
                  : <String>[]))
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
