import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/features/session/data/shared_preferences_app_entry_state_store.dart';
import '../../integration_test/support/native_baseline_fixture.dart';
import '../../integration_test/support/native_baseline_cases.dart';

void main() {
  for (final phase in ['N01', 'N02', 'N03']) {
    testWidgets(
      'BM host $phase uses canonical navigation and local authorities',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final fixture = await tester.runAsync(() async {
          final root = await Directory.systemTemp.createTemp('bm-navigation-');
          final fixture = await NativeBaselineFixture.open(
            root,
            'bm-navigation',
            seed: true,
          );
          await fixture.seed();
          return fixture;
        });
        final entry = SharedPreferencesAppEntryStateStore(
          await SharedPreferences.getInstance(),
        );
        await entry.markGuest();
        try {
          await runBaselineCase(tester, fixture!, entry, phase);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          await baselineAwait(tester, fixture!.close);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
