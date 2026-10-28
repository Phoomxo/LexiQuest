// sharedprefs-ok: stores only the app entry mode flag (guest vs signed-in),
// not business or research data.
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_entry_state.dart';

/// [AppEntryStateStore] backed by SharedPreferences. Stores only `guest`
/// under the versioned key `lexiquest.app_entry_mode.v1`. Missing, malformed,
/// or unreadable values resolve to [AppEntryMode.signedOut] (fail-closed).
final class SharedPreferencesAppEntryStateStore implements AppEntryStateStore {
  SharedPreferencesAppEntryStateStore(this._prefs);

  static const _key = 'lexiquest.app_entry_mode.v1';
  static const _guestValue = 'guest';

  final SharedPreferences _prefs;

  @override
  Future<AppEntryMode> read() async {
    try {
      final value = _prefs.getString(_key);
      if (value == _guestValue) return AppEntryMode.guest;
      return AppEntryMode.signedOut;
    } on Object {
      return AppEntryMode.signedOut;
    }
  }

  @override
  Future<void> markGuest() async {
    final written = await _prefs.setString(_key, _guestValue);
    if (!written) {
      throw StateError('SharedPreferences rejected the app-entry write');
    }
  }

  @override
  Future<void> clear() async {
    final removed = await _prefs.remove(_key);
    if (!removed) {
      throw StateError('SharedPreferences rejected the app-entry removal');
    }
  }
}
