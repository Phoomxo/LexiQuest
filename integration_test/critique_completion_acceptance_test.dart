import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/screens/ai_tutor_screen_test.dart' as tutor;
import '../test/screens/associative_reading_session_screen_test.dart'
    as reading;
import '../test/screens/bundled_starter_pack_flow_test.dart' as starter;
import '../test/screens/gemini_settings_screen_test.dart' as settings;
import '../test/screens/home_reading_result_test.dart' as reading_result;
import '../test/screens/reading_keyboard_focus_test.dart' as keyboard;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Reading', reading.main);
  group('Home Reading result', reading_result.main);
  group('Reading keyboard', keyboard.main);
  group('Starter preview', starter.main);
  group('Tutor settings', settings.main);
  group('Tutor', tutor.main);
}
