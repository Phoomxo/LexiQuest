import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/learning/authored_native_starter_test.dart'
    as authored;
import '../test/features/learning/session_policy_use_cases_test.dart' as policy;
import '../test/screens/content_report_actual_native_test.dart' as reports;
import '../test/screens/quiz_screen_test.dart' as quiz;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Authored offline', authored.main);
  group('Session policy', policy.main);
  group('Native reports', reports.main);
  group('Configured UI', quiz.main);
}
