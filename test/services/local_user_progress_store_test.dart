import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/services/local_user_progress_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalUserProgressStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = LocalUserProgressStore();
  });

  test('getZpdLevel returns default A1 when uninitialized', () async {
    expect(await store.getZpdLevel(), 'A1');
  });

  test('saveZpdLevel updates and retrieves ZPD level correctly', () async {
    await store.saveZpdLevel('B2');
    expect(await store.getZpdLevel(), 'B2');
  });

  test('incrementStreak increments and tracks streak correctly', () async {
    expect(await store.getStreakCount(), 0);
    expect(await store.incrementStreak(), 1);
    expect(await store.incrementStreak(), 2);
    expect(await store.getStreakCount(), 2);
  });

  test('addMasteredWord adds unique word IDs', () async {
    await store.addMasteredWord('word_1');
    await store.addMasteredWord('word_2');
    await store.addMasteredWord('word_1'); // duplicate

    final list = await store.getMasteredWords();
    expect(list.length, 2);
    expect(list, containsAll(['word_1', 'word_2']));
  });

  test('saveSrsProgress and loadSrsProgress serialize correctly', () async {
    final testData = {'apple': {'box': 2, 'interval': 86400}};
    await store.saveSrsProgress(testData);

    final loaded = await store.loadSrsProgress();
    expect(loaded['apple']['box'], 2);
  });

  test('clearAll wipes saved state cleanly', () async {
    await store.saveZpdLevel('C1');
    await store.incrementStreak();
    await store.clearAll();

    expect(await store.getZpdLevel(), 'A1');
    expect(await store.getStreakCount(), 0);
  });
}
