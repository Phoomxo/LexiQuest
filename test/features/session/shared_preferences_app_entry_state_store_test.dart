import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/features/session/data/shared_preferences_app_entry_state_store.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists guest choice and clear restores signed-out state', () async {
    final preferences = await SharedPreferences.getInstance();
    final entryState = SharedPreferencesAppEntryStateStore(preferences);

    expect(await entryState.read(), AppEntryMode.signedOut);

    await entryState.markGuest();
    expect(await entryState.read(), AppEntryMode.guest);

    await entryState.clear();
    expect(await entryState.read(), AppEntryMode.signedOut);
  });

  test('clearing an already-empty store succeeds', () async {
    final preferences = await SharedPreferences.getInstance();
    final entryState = SharedPreferencesAppEntryStateStore(preferences);

    await expectLater(entryState.clear(), completes);
    expect(await entryState.read(), AppEntryMode.signedOut);
  });
}
