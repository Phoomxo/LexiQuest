import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/screens/associative_reading_session_screen_test.dart'
    as reading;
import '../test/screens/bundled_starter_pack_flow_test.dart' as starter;
import '../test/screens/object_scanner_screen_test.dart' as scanner;
import '../test/screens/offline_reading_entry_test.dart' as reading_entry;
import '../test/screens/reading_tutor_learning_time_test.dart' as reading_time;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Reading', reading.main);
  group('Starter', starter.main);
  group('Scanner', scanner.main);
  group('Home reading', reading_entry.main);
  group('Reading time', reading_time.main);
}
