import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'device-performance-probe.dart' as profile;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final watch = Stopwatch()..start();
    while (binding.platformDispatcher.implicitView!.physicalSize.isEmpty &&
        watch.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      binding.platformDispatcher.implicitView!.physicalSize.isEmpty,
      isFalse,
      reason: 'Real Android viewport must arrive before the profile reads it.',
    );
  });
  profile.main();
  testWidgets('DEVICE_SUITE_FINAL_SENTINEL', (tester) async {
    binding.reportData = {
      ...?binding.reportData,
      'flow': 'performance',
      // This integration target intentionally lives outside test/.
      // ignore: invalid_use_of_visible_for_testing_member
      'testResults': binding.results.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    };
    // This sentinel inspects only the integration runner's completed results.
    // ignore: invalid_use_of_visible_for_testing_member
    expect(binding.results.length, greaterThanOrEqualTo(1));
  });
  unawaited(publishService());
}

Future<void> publishService() async {
  final uri = (await developer.Service.getInfo()).serverUri;
  if (uri == null || uri.host != '127.0.0.1') {
    throw StateError('Local VM service unavailable');
  }
  await File(
    '${Directory.systemTemp.path}/lexiquest-core-service-20260907.json',
  ).writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}
