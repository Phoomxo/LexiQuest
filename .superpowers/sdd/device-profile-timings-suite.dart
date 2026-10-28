import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'device-isolated-suite.dart' as original;
import 'device-profile-timings-capture.dart';

// Run the unmodified original dispatcher/benchmark/sentinel. The observer copies
// bounded timing arrays only after watchPerformance has finished measuring.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final capture = ProfileTimingsCapture();
  binding.reportData = capture;
  original.main();
  tearDownAll(() {
    // Keep the original response and verdict untouched. Diagnostics go only to
    // the already scoped fixture log, after all measured work and assertions.
    const maxLineBytes = 900;
    final errors = List<String>.of(capture.errors);
    var rowCount = 0;
    var oversizedRow = false;
    for (final row in capture.transitions) {
      final line = 'PROFILE_TIMINGS_DIAGNOSTIC_ROW ${jsonEncode(row)}';
      if (utf8.encode(line).length > maxLineBytes) {
        oversizedRow = true;
        continue;
      }
      print(line);
      rowCount++;
    }
    if (oversizedRow) errors.add('transport-row-too-large');
    String summary(List<String> codes) =>
        'PROFILE_TIMINGS_DIAGNOSTIC_SUMMARY ${jsonEncode(<String, Object>{'schemaVersion': 1, 'diagnosticOnly': true, 'rowCount': rowCount, 'errors': codes})}';
    var footer = summary(errors);
    if (utf8.encode(footer).length > maxLineBytes) {
      footer = summary(<String>['transport-summary-too-large']);
    }
    print(footer);
  });
}
