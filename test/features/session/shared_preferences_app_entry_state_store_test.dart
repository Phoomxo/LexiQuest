import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/features/session/data/shared_preferences_app_entry_state_store.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to signedOut when nothing is stored', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppEntryStateStore(
      await SharedPreferences.getInstance(),
    );

    expect(await store.read(), AppEntryMode.signedOut);
  });

  test('marks and restores guest across instances', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppEntryStateStore(
      await SharedPreferences.getInstance(),
    );
    await store.markGuest();

    final reopened = SharedPreferencesAppEntryStateStore(
      await SharedPreferences.getInstance(),
    );
    expect(await reopened.read(), AppEntryMode.guest);
  });

  test('clears back to signedOut', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesAppEntryStateStore(
      await SharedPreferences.getInstance(),
    );
    await store.markGuest();
    await store.clear();

    final reopened = SharedPreferencesAppEntryStateStore(
      await SharedPreferences.getInstance(),
    );
    expect(await reopened.read(), AppEntryMode.signedOut);
  });

  test('a malformed stored value falls back to signedOut', () async {
    SharedPreferences.setMockInitialValues({
      'lexiquest.app_entry_mode.v1': 'garbage',
    });
    final store = SharedPreferencesAppEntryStateStore(
      await SharedPreferences.getInstance(),
    );

    expect(await store.read(), AppEntryMode.signedOut);
  });

  test('markGuest rejects a failed preference write', () async {
    final store = SharedPreferencesAppEntryStateStore(
      _RejectingSharedPreferences(rejectSet: true),
    );

    await expectLater(store.markGuest(), throwsStateError);
  });

  test('clear rejects a failed preference removal', () async {
    final store = SharedPreferencesAppEntryStateStore(
      _RejectingSharedPreferences(rejectRemove: true),
    );

    await expectLater(store.clear(), throwsStateError);
  });
}

final class _RejectingSharedPreferences implements SharedPreferences {
  _RejectingSharedPreferences({
    this.rejectSet = false,
    this.rejectRemove = false,
  });

  final bool rejectSet;
  final bool rejectRemove;

  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) async => !rejectSet;

  @override
  Future<bool> remove(String key) async => !rejectRemove;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
