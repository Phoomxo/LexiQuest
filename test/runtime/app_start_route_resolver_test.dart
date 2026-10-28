import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_start_route_resolver.dart';

final class _FakeEntryStateStore implements AppEntryStateStore {
  _FakeEntryStateStore(this._mode);
  AppEntryMode _mode;

  @override
  Future<AppEntryMode> read() async => _mode;

  @override
  Future<void> markGuest() async => _mode = AppEntryMode.guest;

  @override
  Future<void> clear() async => _mode = AppEntryMode.signedOut;
}

final class _ThrowingEntryStateStore implements AppEntryStateStore {
  @override
  Future<AppEntryMode> read() async => throw Exception('storage failure');
  @override
  Future<void> markGuest() async {}
  @override
  Future<void> clear() async {}
}

void main() {
  test('signed-out entry resolves to login', () async {
    final resolver = AppStartRouteResolver(
      entryState: _FakeEntryStateStore(AppEntryMode.signedOut),
    );
    expect(
      await resolver.resolve(hasAuthenticatedSession: false),
      AppRoute.login,
    );
  });

  test('guest entry resolves to home', () async {
    final resolver = AppStartRouteResolver(
      entryState: _FakeEntryStateStore(AppEntryMode.guest),
    );
    expect(
      await resolver.resolve(hasAuthenticatedSession: false),
      AppRoute.home,
    );
  });

  test('authenticated session overrides entry state to home', () async {
    final resolver = AppStartRouteResolver(
      entryState: _FakeEntryStateStore(AppEntryMode.signedOut),
    );
    expect(
      await resolver.resolve(hasAuthenticatedSession: true),
      AppRoute.home,
    );
  });

  test('store failure resolves to login (fail-closed)', () async {
    final resolver = AppStartRouteResolver(
      entryState: _ThrowingEntryStateStore(),
    );
    expect(
      await resolver.resolve(hasAuthenticatedSession: false),
      AppRoute.login,
    );
  });
}
