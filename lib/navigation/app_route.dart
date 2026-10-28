enum AppRoute {
  sessionGate('/'),
  login('/login'),
  register('/register'),
  verifyEmail('/verify-email'),
  forgotPassword('/forgot-password'),
  resetPassword('/reset-password'),
  home('/home'),
  changePassword('/change-password');

  const AppRoute(this.path);

  final String path;
}

final class VerifyEmailRouteArgs {
  const VerifyEmailRouteArgs({required this.email});

  final String email;
}

final class RegisterRouteArgs {
  const RegisterRouteArgs({required this.uid, required this.email});

  final String uid;
  final String email;
}

final class ResetPasswordRouteArgs {
  const ResetPasswordRouteArgs({required this.code});

  final String code;
}

final class VerifyEmailActionRouteArgs {
  const VerifyEmailActionRouteArgs({required this.code});

  final String code;
}
