import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production navigation does not expose research export or thesis routes',
    () {
      final chooseModeSource = File(
        'lib/screens/choose_mode_screen.dart',
      ).readAsStringSync();
      final settingsSource = File(
        'lib/screens/setting_screen.dart',
      ).readAsStringSync();

      expect(chooseModeSource, isNot(contains('ExportCenterScreen')));
      expect(chooseModeSource, isNot(contains('ThesisChartScreen')));
      expect(settingsSource, isNot(contains('ExportCenterScreen')));
    },
  );

  test('Export Center does not offer a sample Research CSV export', () {
    final source = File(
      'lib/screens/export_center_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('Research CSV')));
    expect(source, isNot(contains('_generateResearchCsv')));
    expect(source, isNot(contains('ResearchDataExporterService')));
  });
}
