import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/learning/authored_native_starter_test.dart'
    as authored;
import '../test/features/learning/session_policy_use_cases_test.dart' as policy;
import '../test/screens/content_report_actual_native_test.dart' as reports;
import '../test/screens/quiz_screen_test.dart' as quiz;
import '../test/runtime/app_bootstrap_motivation_test.dart' as bootstrap;
import '../test/screens/authored_native_entry_test.dart' as native_entry;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Authored offline', authored.main);
  group('Session policy', policy.main);
  group('Native reports', reports.main);
  group('Configured UI', () {
    quiz.main(
      captureNativeFeedback: (tester) async {
        expect(
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
          320,
        );
        await binding.convertFlutterSurfaceToImage().timeout(
          const Duration(seconds: 20),
        );
        await tester.pump();
        final bytes = await binding
            .takeScreenshot('quiz-feedback-large-text')
            .timeout(const Duration(seconds: 20));
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        await tester.runAsync(() async {
          final directory = Directory(
            '${Directory.systemTemp.path}/lexiquest-offline',
          );
          await directory.create(recursive: true);
          await File(
            '${directory.path}/quiz-feedback-large-text.png',
          ).writeAsBytes(bytes, flush: true);
        });
      },
    );
  });
  group('Real bootstrap motivation', bootstrap.main);
  group('Authored Home entry', native_entry.main);
}
