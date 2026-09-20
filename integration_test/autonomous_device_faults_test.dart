import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'field_trial_feature_controls_test.dart' as controls;
import 'field_trial_media_smoke_test.dart' as media;
import 'support/autonomous_service_receipt.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final receipt = writeAutonomousServiceReceipt();
  setUpAll(() => receipt);
  media.main();
  controls.main();
  tearDownAll(() {
    const expectedCases = <String>[
      'host fakes render camera microphone and model unavailable states',
      'operator override survives a production-shell restart',
    ];
    binding.reportData = <String, dynamic>{
      'suite': 'autonomous-device-faults',
      'evidenceLevel': 'DEVICE_FIXTURE',
      'results': binding.results.map(
        (name, result) => MapEntry(name, result.toString()),
      ),
    };
    for (final name in expectedCases) {
      expect(binding.results, contains(name));
    }
  });
}
