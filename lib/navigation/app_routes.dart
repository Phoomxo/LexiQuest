import 'package:flutter/material.dart';

enum AppRoute { login, register, emailVerification, home }

final class EmailVerificationArgs {
  const EmailVerificationArgs(this.email);

  final String email;
}

final class AppPage<T> {
  const AppPage({
    required this.name,
    required this.builder,
    this.reduceMotion = false,
  });

  final String name;
  final WidgetBuilder builder;
  final bool reduceMotion;
}

abstract final class AppNavigator {
  static Future<T?> push<T>(
    BuildContext context,
    AppRoute route, {
    Object? arguments,
  }) {
    return Navigator.of(context).pushNamed<T>(route.path, arguments: arguments);
  }

  static Future<T?> replace<T, TO>(
    BuildContext context,
    AppRoute route, {
    Object? arguments,
    TO? result,
  }) {
    return Navigator.of(context).pushReplacementNamed<T, TO>(
      route.path,
      arguments: arguments,
      result: result,
    );
  }

  static Future<T?> resetTo<T>(
    BuildContext context,
    AppRoute route, {
    Object? arguments,
  }) {
    return Navigator.of(context).pushNamedAndRemoveUntil<T>(
      route.path,
      (_) => false,
      arguments: arguments,
    );
  }

  static Future<T?> pushPage<T>(
    BuildContext context,
    AppPage<T> page, {
    bool replace = false,
    ValueChanged<Route<T>>? onRouteCreated,
  }) {
    final settings = RouteSettings(name: page.name);
    final route =
        page.reduceMotion ||
            (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
        ? _ReducedMotionPageRoute<T>(settings: settings, builder: page.builder)
        : MaterialPageRoute<T>(settings: settings, builder: page.builder);
    onRouteCreated?.call(route);
    return replace
        ? Navigator.of(context).pushReplacement<T, T>(route)
        : Navigator.of(context).push<T>(route);
  }
}

class _ReducedMotionPageRoute<T> extends MaterialPageRoute<T> {
  _ReducedMotionPageRoute({required super.settings, required super.builder});
  @override
  TickerFuture didPush() {
    final result = super.didPush();
    // The launching control may detach in the same frame as an instant push.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = subtreeContext;
      if (isCurrent && context != null && context.mounted) {
        final scope = FocusScope.of(context);
        if (!scope.hasFocus) scope.requestFocus();
      }
    });
    return result;
  }

  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

extension AppRoutePath on AppRoute {
  String get path => switch (this) {
    AppRoute.login => '/login',
    AppRoute.register => '/register',
    AppRoute.emailVerification => '/email-verification',
    AppRoute.home => '/home',
  };
}
