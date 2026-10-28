import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 5),
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final destination = Platform.environment['LEXIQUEST_DEVICE_RESPONSE_PATH'];
    if (destination == null || destination.isEmpty) {
      throw StateError('Explicit device response evidence path required.');
    }
    await File(destination).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'capturedUtc': DateTime.now().toUtc().toIso8601String(),
        'fixture': 'integration_test/field_trial_core_journey_test.dart',
        'responseData': data,
      }),
      flush: true,
    );
  },
);
