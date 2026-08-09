import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_start_route_resolver.dart';

void main() {
  test(
    'resolves signed-out, explicit guest, authenticated, and cleared state',
    () async {
      final entryState = _MemoryAppEntryStateStore();
      final resolver = AppStartRouteResolver(entryState: entryState);

      expect(
        await resolver.resolve(hasAuthenticatedSession: false),
        AppRoute.login,
      );
      await entryState.markGuest();
      expect(
        await resolver.resolve(hasAuthenticatedSession: false),
        AppRoute.home,
      );
      expect(
        await resolver.resolve(hasAuthenticatedSession: true),
        AppRoute.home,
      );
      await entryState.clear();
      expect(
        await resolver.resolve(hasAuthenticatedSession: false),
        AppRoute.login,
      );
    },
  );
}

final class _MemoryAppEntryStateStore implements AppEntryStateStore {
  AppEntryMode mode = AppEntryMode.signedOut;

  @override
  Future<void> clear() async {
    mode = AppEntryMode.signedOut;
  }

  @override
  Future<void> markGuest() async {
    mode = AppEntryMode.guest;
  }

  @override
  Future<AppEntryMode> read() async => mode;
}
