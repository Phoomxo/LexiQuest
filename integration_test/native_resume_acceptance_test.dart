import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/native_resume_fixture.dart';
import 'support/native_resume_cases.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'BW isolated ordinary meaning feedback OS restart',
    (tester) async {
      const channel = MethodChannel('lexiquest/native-resume');
      final context = (await channel.invokeMapMethod<String, String>(
        'context',
      ))!;
      if (context['packageId'] != nativeResumePackage ||
          !['seed', 'verify'].contains(context['phase'])) {
        throw StateError('Wrong native context');
      }
      final phase = context['phase']!;
      final run = context['runId']!;
      final support = Directory(context['supportPath']!);
      final cases = <String, String>{};
      final receipt = <String, Object?>{
        'packageId': nativeResumePackage,
        'runId': run,
        'phase': phase,
        'status': 'FAIL',
        'closed': false,
        'cases': cases,
      };
      try {
        final fixture = await NativeResumeFixture.open(
          support,
          run,
          seed: phase == 'seed',
          requireAndroidSandbox: true,
        );
        HttpOverrides.global = fixture.network;
        final prefs = await SharedPreferences.getInstance();
        if (phase == 'seed') {
          if (prefs.containsKey('bw-guest')) {
            throw StateError('Guest seed collision');
          }
          await prefs.setString('bw-guest', run);
          await runResumePhase(tester, fixture, seedPhase: true);
          cases['N01'] =
              'PASS'; // Canonical ordinary admission and attached UI.
          cases['N02'] = 'PASS'; // Durable committed answer feedback.
          receipt.addAll(await resumeAwait(tester, fixture.snapshot));
          await tester.pumpWidget(const SizedBox.shrink());
          await resumeAwait(tester, fixture.closeAndSeal);
          cases['N03'] = 'PASS'; // Closed and flushed immutable seed seal.
        } else {
          await prefs.reload();
          expect(prefs.getString('bw-guest'), run);
          await resumeAwait(tester, fixture.verifySealed);
          // No seed/admission: reopen exact owner/session/plan and replay feedback.
          await runResumePhase(tester, fixture, seedPhase: false);
          receipt.addAll(await resumeAwait(tester, fixture.snapshot));
          await tester.pumpWidget(const SizedBox.shrink());
          await resumeAwait(tester, fixture.close);
          cases['N04'] = 'PASS';
        }
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
