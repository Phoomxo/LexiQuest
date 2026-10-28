import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'device-media-probe.dart' as media;
import '../../test/features/learning/pair_matching/pair_configured_disposition_test.dart' as retry;
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('media-isolated-probe', media.main);
  group('configured-retry-isolated', retry.main);
  testWidgets('DEVICE_SUITE_FINAL_SENTINEL', (tester) async {
    binding.reportData = {'suite': 'focused-diagnosis', 'testResults': binding.results.map((k,v)=>MapEntry(k,v.toString()))};
    expect(binding.results.length, greaterThan(1));
  });
  unawaited(publishService());
}
Future<void> publishService() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverUri;
  if (uri == null || uri.host != '127.0.0.1') throw StateError('Local VM service unavailable');
  await File('${Directory.systemTemp.path}/lexiquest-core-service-20260907.json').writeAsString(jsonEncode({'uri':uri.toString()}), flush:true);
}
