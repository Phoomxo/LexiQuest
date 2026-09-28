import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'support/native_terminal_fixture.dart';
import 'support/native_terminal_cases.dart';
import 'support/native_today_cases.dart' show todayAwait;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'CA isolated terminal close actual Today OS restart',
    (tester) async {
      const channel = MethodChannel('lexiquest/native-terminal');
      final context = (await channel.invokeMapMethod<String, String>(
        'context',
      ))!;
      if (context['packageId'] != nativeTerminalPackage ||
          !['seed', 'resume', 'closed'].contains(context['phase'])) {
        throw StateError('Wrong CA context');
      }
      final phase = context['phase']!;
      final run = context['runId']!;
      final support = Directory(context['supportPath']!);
      final receipt = <String, Object?>{
        'status': 'FAIL',
        'closed': false,
        'packageId': nativeTerminalPackage,
        'runId': run,
        'phase': phase,
      };
      try {
        final fixture = await NativeTerminalFixture.open(
          support,
          run,
          seed: phase == 'seed',
          requireAndroidSandbox: true,
        );
        HttpOverrides.global = fixture.network;
        final evidence = await runTerminalPhase(tester, fixture, phase);
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
                  ? ['C01', 'C02', 'C03']
                  : phase == 'resume'
                  ? ['C04', 'C05', 'C06']
                  : ['C07']))
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
