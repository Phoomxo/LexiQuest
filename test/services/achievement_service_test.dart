import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/services/achievement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AchievementService loads default badges and unlocks badge', () async {
    final service = AchievementService();
    final badges = await service.loadBadges();

    expect(badges.length, 3);
    expect(badges.first.isUnlocked, false);

    final unlocked = await service.unlockBadge('pronunciation_master');
    expect(unlocked, true);

    final reloaded = await service.loadBadges();
    expect(reloaded.first.isUnlocked, true);

    final repeatUnlock = await service.unlockBadge('pronunciation_master');
    expect(repeatUnlock, false);
  });
}
