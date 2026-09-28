import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'support/native_draft_fixture.dart';
import 'support/native_draft_cases.dart';
import 'support/native_today_cases.dart' show todayAwait;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'CB isolated draft actual Today OS restart',
    (tester) async {
      const channel = MethodChannel('lexiquest/native-draft');
      final context = (await channel.invokeMapMethod<String, String>(
        'context',
      ))!;
      final package = runIsolatedDraftPackage(context['runId'] ?? '');
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
        final fixture = await NativeDraftFixture.open(
          support,
          run,
          seed: phase == 'seed',
          requireAndroidSandbox: true,
        );
        HttpOverrides.global = fixture.network;
        final evidence = await runDraftPhase(tester, fixture, phase);
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
                  ? ['D01', 'D02']
                  : phase == 'resume'
                  ? ['D03', 'D04', 'D05']
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
