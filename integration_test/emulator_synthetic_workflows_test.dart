import 'package:integration_test/integration_test.dart';

import '../test/screens/fill_in_the_blanks_screen_test.dart' as cloze;
import '../test/screens/pre_post_assessment_screen_test.dart' as assessment;
import '../test/screens/typed_cloze_scratchpad_test.dart' as scratchpad;
import 'reminder_database_boundary_test.dart' as reminder;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  cloze.main();
  scratchpad.main();
  assessment.main();
  reminder.main();
}
