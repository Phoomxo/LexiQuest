import 'package:flutter/material.dart';

enum AppRoute { login, register, emailVerification, home }

final class EmailVerificationArgs {
  const EmailVerificationArgs(this.email);

  final String email;
}

final class AppPage<T> {
  const AppPage({required this.name, required this.builder});

  final String name;
  final WidgetBuilder builder;
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
  }) {
    final route = MaterialPageRoute<T>(
      settings: RouteSettings(name: page.name),
      builder: page.builder,
    );
    return replace
        ? Navigator.of(context).pushReplacement<T, T>(route)
        : Navigator.of(context).push<T>(route);
  }
}

extension AppRoutePath on AppRoute {
  String get path => switch (this) {
    AppRoute.login => '/login',
    AppRoute.register => '/register',
    AppRoute.emailVerification => '/email-verification',
    AppRoute.home => '/home',
  };
}
