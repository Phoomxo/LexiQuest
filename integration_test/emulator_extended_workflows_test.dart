import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/screens/native_durable_resume_screen_test.dart' as native_modes;
import '../test/screens/recall_ladder_entry_flow_test.dart' as recall_ladder;
import '../test/screens/earned_cosmetic_streak_flow_test.dart'
    as earned_rewards;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Native durable modes', native_modes.main);
  group('Recall ladder', recall_ladder.main);
  group('Earned rewards and streak', earned_rewards.main);
}
