import 'package:flutter/material.dart';

import '../account/account_error_mapper.dart';
import '../account/account_gateway.dart';
import '../account/account_validation.dart';
import '../navigation/app_route.dart';
import '../services/guest_session_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.accountGateway,
    required this.guestSessionService,
  });

  final AccountGateway accountGateway;
  final GuestSessionService guestSessionService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSessionActionPending = false;

  String? _validateEmail(String? value) =>
      AccountValidation.emailError(value ?? '');

  String? _validatePassword(String? value) =>
      (value ?? '').isEmpty ? 'กรุณากรอกรหัสผ่าน' : null;

  Future<void> _login() async {
    if (_isSessionActionPending ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _isSessionActionPending = true);

    final email = AccountValidation.normalizeEmail(_emailController.text);
    final password = _passwordController.text;
    try {
      final session = await widget.accountGateway.signIn(
        email: email,
        password: password,
      );
      if (!mounted) return;
      if (!session.isEmailVerified && !session.isAnonymous) {
        Navigator.of(context).pushReplacementNamed(
          AppRoute.verifyEmail.path,
          arguments: VerifyEmailRouteArgs(email: session.email ?? email),
        );
        return;
      }
      Navigator.of(context).pushReplacementNamed(AppRoute.home.path);
    } on AccountOperationException catch (error) {
      if (mounted) _showError(AccountErrorMapper.messageFor(error.code));
    } on Object {
      if (mounted) _showError(AccountErrorMapper.messageFor('unknown'));
    } finally {
      if (mounted) setState(() => _isSessionActionPending = false);
    }
  }

  Future<void> _startGuestSession() async {
    if (_isSessionActionPending) return;
    setState(() => _isSessionActionPending = true);
    try {
      final result = await widget.guestSessionService.start();
      if (!mounted) return;
      switch (result) {
        case GuestSessionStarted():
          Navigator.of(context).pushReplacementNamed(AppRoute.home.path);
        case GuestSessionFailed(:final reason):
          _showError(_guestFailureMessage(reason));
      }
    } on Object {
      if (mounted) {
        _showError(_guestFailureMessage(GuestSessionFailure.unknown));
      }
    } finally {
      if (mounted) setState(() => _isSessionActionPending = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _guestFailureMessage(GuestSessionFailure reason) => switch (reason) {
    GuestSessionFailure.firebaseUnavailable =>
      'ระบบยืนยันตัวตนยังไม่พร้อม กรุณาลองใหม่ภายหลัง',
    GuestSessionFailure.providerDisabled =>
      'โหมดผู้เยี่ยมชมยังไม่เปิดใช้งาน กรุณาเข้าสู่ระบบด้วยอีเมล',
    GuestSessionFailure.network =>
      'เชื่อมต่อเครือข่ายไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
    GuestSessionFailure.unknown =>
      'เริ่มโหมดผู้เยี่ยมชมไม่ได้ กรุณาลองใหม่หรือเข้าสู่ระบบด้วยอีเมล',
  };

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'เข้าสู่ระบบ (Login)',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const ValueKey<String>('login-email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    validator: _validateEmail,
                    decoration: const InputDecoration(
                      labelText: 'อีเมล (Email)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey<String>('login-password'),
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: _validatePassword,
                    decoration: const InputDecoration(
                      labelText: 'รหัสผ่าน (Password)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const ValueKey<String>('login-forgot-password'),
                      onPressed: _isSessionActionPending
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pushNamed(AppRoute.forgotPassword.path),
                      child: const Text('ลืมรหัสผ่าน?'),
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey<String>('login-submit'),
                    onPressed: _isSessionActionPending ? null : _login,
                    child: _isSessionActionPending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('เข้าสู่ระบบ (Login)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('login-guest'),
                    onPressed: _isSessionActionPending
                        ? null
                        : _startGuestSession,
                    icon: _isSessionActionPending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('ทดลองใช้งานทันที (Guest Mode)'),
                  ),
                  TextButton(
                    onPressed: _isSessionActionPending
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pushNamed(AppRoute.register.path),
                    child: const Text('ยังไม่มีบัญชีใช่ไหม? สมัครสมาชิกที่นี่'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
