import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/screens/fill_in_the_blanks_screen_test.dart' as cloze;
import '../test/screens/typed_cloze_scratchpad_test.dart' as scratchpad;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (var round = 1; round <= 3; round++) {
    group('Scratchpad sequence $round', () {
      cloze.main();
      scratchpad.main();
    });
  }
}
