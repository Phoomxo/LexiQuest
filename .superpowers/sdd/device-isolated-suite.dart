import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../../integration_test/field_trial_media_smoke_test.dart' as media;
import '../../test/features/learning/pair_matching/pair_configured_disposition_test.dart' as retry;
import '../../integration_test/adventure_performance_profile_test.dart' as profile;
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const flow = String.fromEnvironment('LEXIQUEST_DEVICE_FLOW');
  setUpAll(() async {
    final watch = Stopwatch()..start();
    while (binding.platformDispatcher.implicitView!.physicalSize.isEmpty &&
           watch.elapsed < const Duration(seconds:10)) {
      await Future<void>.delayed(const Duration(milliseconds:20));
    }
    expect(binding.platformDispatcher.implicitView!.physicalSize.isEmpty, isFalse);
  });
  switch(flow) {
    case 'media': media.main();
    case 'retry': retry.main();
    case 'performance': profile.main();
    default: throw StateError('Explicit isolated flow required');
  }
  testWidgets('DEVICE_SUITE_FINAL_SENTINEL', (tester) async {
    binding.reportData = {
      ...?binding.reportData,
      'flow':flow,
      'testResults':binding.results.map((k,v)=>MapEntry(k,v.toString())),
    };
    expect(binding.results.length, greaterThanOrEqualTo(1));
  });
  unawaited(publishService());
}
Future<void> publishService() async {
  final uri = (await developer.Service.getInfo()).serverUri;
  if (uri == null || uri.host != '127.0.0.1') throw StateError('Local VM service unavailable');
  await File('${Directory.systemTemp.path}/lexiquest-core-service-20260907.json').writeAsString(jsonEncode({'uri':uri.toString()}),flush:true);
}
