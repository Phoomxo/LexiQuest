import '../features/session/domain/app_entry_state.dart';
import '../navigation/app_routes.dart';

/// Resolves the launch route from the persisted app-entry state and the
/// authenticated-session flag. An authenticated Firebase session always
/// resolves to Home. A store failure resolves to Login (fail-closed).
final class AppStartRouteResolver {
  AppStartRouteResolver({required this._entryState});

  final AppEntryStateStore _entryState;

  Future<AppRoute> resolve({required bool hasAuthenticatedSession}) async {
    if (hasAuthenticatedSession) return AppRoute.home;
    try {
      final entry = await _entryState.read();
      return entry == AppEntryMode.guest ? AppRoute.home : AppRoute.login;
    } on Object {
      return AppRoute.login;
    }
  }
}
