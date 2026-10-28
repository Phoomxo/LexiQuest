import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../../integration_test/field_trial_core_journey_test.dart' as core;

void main() {
  core.main();
  unawaited(publishService());
}

Future<void> publishService() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null || !uri.isScheme('http') || !uri.host.startsWith('127.')) {
    throw StateError('Local authenticated VM service is unavailable.');
  }
  final file = File('${Directory.systemTemp.path}/lexiquest-core-service-20260907.json');
  await file.writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}
