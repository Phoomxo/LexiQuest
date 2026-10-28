import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';

void main() {
  test('Choose Mode and Settings expose only the sanitized Export Center', () {
    final chooseModeSource = File(
      'lib/screens/choose_mode_screen.dart',
    ).readAsStringSync();
    final settingsSource = File(
      'lib/screens/setting_screen.dart',
    ).readAsStringSync();

    expect(chooseModeSource, contains('ExportCenterScreen'));
    expect(chooseModeSource, isNot(contains('ThesisChartScreen')));
    expect(settingsSource, contains('ExportCenterScreen'));
    expect(settingsSource, isNot(contains('ThesisChartScreen')));
  });

  test('Export Center does not offer a sample Research CSV export', () {
    final source = File(
      'lib/screens/export_center_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('Research CSV')));
    expect(source, isNot(contains('_generateResearchCsv')));
    expect(source, isNot(contains('ResearchDataExporterService')));
  });

  test('Choose Mode does not expose the simulated object scanner', () {
    final source = File(
      'lib/screens/choose_mode_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('ObjectScannerScreen')));
    expect(source, isNot(contains('Camera Object Scanner')));
  });

  testWidgets(
    'reachable Export Center presents Anki and PDF without research outputs',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ExportCenterScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Anki Deck'), findsOneWidget);
      expect(find.text('PDF Glossary'), findsOneWidget);
      expect(find.textContaining('ข้อมูลวิจัย'), findsNothing);
      expect(find.textContaining('Research CSV'), findsNothing);
      expect(find.textContaining('Thesis'), findsNothing);
    },
  );
}
