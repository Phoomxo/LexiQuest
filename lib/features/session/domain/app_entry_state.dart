/// The participant's explicit app-entry choice, persisted separately from the
/// local owner record because bootstrap creates a local owner before the user
/// chooses Guest.
enum AppEntryMode { signedOut, guest }

/// Persists the participant's app-entry choice across process restarts.
abstract interface class AppEntryStateStore {
  Future<AppEntryMode> read();
  Future<void> markGuest();
  Future<void> clear();
}
