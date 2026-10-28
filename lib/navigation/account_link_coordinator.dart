import 'dart:async';

import 'package:app_links/app_links.dart';

import '../account/account_models.dart';
import 'app_route.dart';

typedef AccountRouteNavigator =
    void Function(AppRoute route, Object? arguments);

final class AccountLinkCoordinator {
  AccountLinkCoordinator({
    required AppLinks appLinks,
    required AccountRouteNavigator navigate,
  }) : this._(appLinks.getInitialLink, appLinks.uriLinkStream, navigate);

  AccountLinkCoordinator.forTesting({
    required Future<Uri?> initialLink,
    required Stream<Uri> uriLinks,
    required AccountRouteNavigator navigate,
  }) : this._(() => initialLink, uriLinks, navigate);

  AccountLinkCoordinator._(this._initialLink, this._uriLinks, this._navigate);

  final Future<Uri?> Function() _initialLink;
  final Stream<Uri> _uriLinks;
  final AccountRouteNavigator _navigate;
  final Set<AccountActionLink> _handledActions = <AccountActionLink>{};
  StreamSubscription<Uri>? _subscription;

  Future<void> start() async {
    _subscription ??= _uriLinks.listen(
      _handleSafely,
      onError: _containStreamError,
    );
    try {
      _handleSafely(await _initialLink());
    } on Object {
      // Platform lookup failures are non-fatal. The warm-link subscription
      // remains active and no link contents or provider details are logged.
    }
  }

  void _handleSafely(Uri? uri) {
    try {
      _handle(uri);
    } on Object {
      // Navigation/parser failures must not escape the asynchronous boundary.
    }
  }

  void _containStreamError(Object error, StackTrace stackTrace) {
    // Intentionally contained without logging sensitive link diagnostics.
  }

  void _handle(Uri? uri) {
    if (uri == null) return;
    final action = AccountActionLink.tryParse(uri);
    if (action == null || !_handledActions.add(action)) return;
    switch (action.mode) {
      case AccountActionMode.resetPassword:
        _navigate(
          AppRoute.resetPassword,
          ResetPasswordRouteArgs(code: action.code),
        );
      case AccountActionMode.verifyEmail:
        _navigate(
          AppRoute.verifyEmail,
          VerifyEmailActionRouteArgs(code: action.code),
        );
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
