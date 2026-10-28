import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 65),
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final raw = Platform.environment['LEXIQUEST_DEVICE_RESPONSE_PATH'];
    if (raw == null || raw.isEmpty) {
      throw StateError('Explicit endurance response path required');
    }
    final destination = File(raw).absolute;
    if (await destination.exists()) {
      throw StateError('Preserve existing endurance response evidence');
    }
    if (!await destination.parent.exists()) {
      throw StateError('Endurance evidence parent must exist');
    }
    await destination.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'capturedUtc': DateTime.now().toUtc().toIso8601String(),
        'fixture': '.superpowers/sdd/device-autonomous-endurance-suite.dart',
        'data': data,
      }),
      flush: true,
    );
  },
);
