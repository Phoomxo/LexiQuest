import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';
Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 60),
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final path = Platform.environment['LEXIQUEST_DEVICE_RESPONSE_PATH'];
    if (path == null) throw StateError('Evidence path required');
    await File(path).writeAsString(jsonEncode({'capturedUtc':DateTime.now().toUtc().toIso8601String(),'data':data}),flush:true);
  },
);
