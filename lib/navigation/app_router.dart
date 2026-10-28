import 'package:flutter/material.dart';

import '../account/account_gateway.dart';
import '../account/account_models.dart';
import '../runtime/app_dependencies.dart';
import '../screens/change_password_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/login_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/otp_screen.dart';
import '../screens/register_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/session_gate_screen.dart';
import 'app_route.dart';

final class AppRouter {
  AppRouter(this.dependencies);

  static final navigatorKey = GlobalKey<NavigatorState>();

  final AppDependencies dependencies;

  Route<dynamic>? generateRoute(RouteSettings settings) {
    final path = settings.name;
    if (path == AppRoute.sessionGate.path) {
      return _route(
        settings,
        SessionGateScreen(
          accountGateway: dependencies.accountGateway,
          guestSessionService: dependencies.guestSessionService,
          profileProvisioner: dependencies.accountProfileProvisioning,
          guestUpgradeHandoff: dependencies.guestUpgradeHandoff,
        ),
      );
    }
    if (path == AppRoute.login.path) {
      return _route(
        settings,
        LoginScreen(
          accountGateway: dependencies.accountGateway,
          guestSessionService: dependencies.guestSessionService,
        ),
      );
    }
    if (path == AppRoute.register.path) {
      return _registerRoute(settings);
    }
    if (path == AppRoute.verifyEmail.path) {
      return _verifyEmailRoute(settings);
    }
    if (path == AppRoute.forgotPassword.path) {
      return _route(
        settings,
        ForgotPasswordScreen(accountGateway: dependencies.accountGateway),
      );
    }
    if (path == AppRoute.resetPassword.path) {
      return _resetPasswordRoute(settings);
    }
    if (path == AppRoute.changePassword.path) {
      if (settings.arguments != null) return null;
      return _route(
        settings,
        ChangePasswordScreen(accountGateway: dependencies.accountGateway),
      );
    }
    if (path == AppRoute.home.path) {
      return _route(settings, const MainNavigationScreen());
    }
    return null;
  }

  Route<dynamic>? _verifyEmailRoute(RouteSettings settings) {
    final args = settings.arguments;
    if (args is VerifyEmailActionRouteArgs) {
      return _route(
        settings,
        _VerifyEmailActionScreen(
          code: args.code,
          accountGateway: dependencies.accountGateway,
        ),
      );
    }
    if (args is! VerifyEmailRouteArgs) return null;
    return _route(
      settings,
      OTPScreen(
        email: args.email,
        accountGateway: dependencies.accountGateway,
        profileProvisioner: dependencies.accountProfileProvisioning,
      ),
    );
  }

  Route<dynamic>? _resetPasswordRoute(RouteSettings settings) {
    final args = settings.arguments;
    if (args is! ResetPasswordRouteArgs) return null;
    return _route(
      settings,
      ResetPasswordScreen(
        accountGateway: dependencies.accountGateway,
        code: args.code,
      ),
    );
  }

  Route<dynamic>? _registerRoute(RouteSettings settings) {
    final args = settings.arguments;
    if (args != null && args is! RegisterRouteArgs) return null;
    final recovery = args as RegisterRouteArgs?;
    return _route(
      settings,
      RegisterScreen(
        accountGateway: dependencies.accountGateway,
        profileProvisioner: dependencies.accountProfileProvisioning,
        guestUpgradeHandoff: dependencies.guestUpgradeHandoff,
        recoveredSession: recovery == null
            ? null
            : AccountSession(
                uid: recovery.uid,
                email: recovery.email,
                isAnonymous: false,
                isEmailVerified: false,
              ),
      ),
    );
  }

  MaterialPageRoute<dynamic> _route(RouteSettings settings, Widget child) {
    return MaterialPageRoute<dynamic>(
      settings: settings,
      builder: (_) => child,
    );
  }
}

final class _VerifyEmailActionScreen extends StatefulWidget {
  const _VerifyEmailActionScreen({
    required this.code,
    required this.accountGateway,
  });

  final String code;
  final AccountGateway accountGateway;

  @override
  State<_VerifyEmailActionScreen> createState() =>
      _VerifyEmailActionScreenState();
}

final class _VerifyEmailActionScreenState
    extends State<_VerifyEmailActionScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _applyCode();
  }

  Future<void> _applyCode() async {
    try {
      await widget.accountGateway.applyVerificationCode(widget.code);
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoute.login.path, (_) => false);
      }
    } on Object {
      if (mounted) setState(() => _error = 'ไม่สามารถยืนยันอีเมลได้');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ยืนยันอีเมล')),
    body: Center(child: Text(_error ?? 'กำลังยืนยันอีเมล...')),
  );
}
