import 'package:flutter/material.dart';

import '../features/account/domain/account_contracts.dart';
import '../screens/email_action_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/otp_screen.dart';
import '../screens/register_screen.dart';
import 'app_routes.dart';

abstract final class AppRouteFactory {
  static bool supportsInitialRoute(String routeName) {
    final uri = Uri.tryParse(routeName);
    if (uri != null && EmailAction.parse(uri) != null) return true;
    return switch (routeName) {
      '/login' || '/register' || '/home' || '/email-verification' => true,
      _ => false,
    };
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final uri = Uri.tryParse(settings.name ?? '');
    final action = uri == null ? null : EmailAction.parse(uri);
    if (action != null) {
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => EmailActionScreen(action: action),
      );
    }
    return switch (settings.name) {
      '/login' => _page(settings, const LoginScreen()),
      '/register' => _page(settings, const RegisterScreen()),
      '/home' => _page(settings, const MainNavigationScreen()),
      '/email-verification' => _verification(settings),
      _ => _page(settings, const LoginScreen()),
    };
  }

  static Route<void> _verification(RouteSettings settings) {
    final arguments = settings.arguments;
    if (arguments is! EmailVerificationArgs) {
      return _page(settings, const LoginScreen());
    }
    return _page(settings, OTPScreen(email: arguments.email));
  }

  static MaterialPageRoute<void> _page(RouteSettings settings, Widget child) =>
      MaterialPageRoute<void>(settings: settings, builder: (_) => child);
}
