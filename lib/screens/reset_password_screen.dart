import 'package:flutter/material.dart';

import '../account/account_error_mapper.dart';
import '../account/account_gateway.dart';
import '../account/account_validation.dart';
import '../navigation/app_route.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.accountGateway,
    required this.code,
  });

  final AccountGateway accountGateway;
  final String code;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isVerifying = true;
  bool _isSubmitting = false;
  bool _canSubmit = false;
  bool _requiresNewLink = false;

  @override
  void initState() {
    super.initState();
    _verifyCode();
  }

  Future<void> _verifyCode() async {
    try {
      await widget.accountGateway.verifyPasswordResetCode(widget.code);
      if (mounted) setState(() => _canSubmit = true);
    } on AccountOperationException catch (error) {
      if (mounted) {
        setState(() => _requiresNewLink = _isInvalidResetCode(error.code));
        _showMessage(AccountErrorMapper.messageFor(error.code));
      }
    } on Object {
      if (mounted) _showMessage(AccountErrorMapper.messageFor('unknown'));
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  String? _validatePassword(String? value) =>
      AccountValidation.passwordError(value ?? '');

  String? _validateConfirmation(String? value) =>
      AccountValidation.confirmationError(
        _passwordController.text,
        value ?? '',
      );

  Future<void> _submit() async {
    if (_isVerifying ||
        _isSubmitting ||
        !_canSubmit ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await widget.accountGateway.confirmPasswordReset(
        code: widget.code,
        newPassword: _passwordController.text,
      );
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoute.login.path, (_) => false);
      }
    } on AccountOperationException catch (error) {
      if (mounted) {
        if (_isInvalidResetCode(error.code)) {
          setState(() {
            _canSubmit = false;
            _requiresNewLink = true;
          });
        }
        _showMessage(AccountErrorMapper.messageFor(error.code));
      }
    } on Object {
      if (mounted) _showMessage(AccountErrorMapper.messageFor('unknown'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool _isInvalidResetCode(String code) =>
      code == 'expired-action-code' || code == 'invalid-action-code';

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งรหัสผ่านใหม่')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _requiresNewLink
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'ลิงก์นี้ใช้ไม่ได้แล้ว',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        key: const ValueKey<String>('reset-request-new-link'),
                        onPressed: () => Navigator.of(
                          context,
                        ).pushReplacementNamed(AppRoute.forgotPassword.path),
                        child: const Text('ขอลิงก์ใหม่'),
                      ),
                    ],
                  )
                : Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const ValueKey<String>('reset-password'),
                          controller: _passwordController,
                          obscureText: true,
                          validator: _validatePassword,
                          decoration: const InputDecoration(
                            labelText: 'รหัสผ่านใหม่',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey<String>('reset-confirmation'),
                          controller: _confirmationController,
                          obscureText: true,
                          validator: _validateConfirmation,
                          decoration: const InputDecoration(
                            labelText: 'ยืนยันรหัสผ่านใหม่',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          key: const ValueKey<String>('reset-submit'),
                          onPressed:
                              _canSubmit && !_isSubmitting && !_isVerifying
                              ? _submit
                              : null,
                          child: _isVerifying
                              ? const CircularProgressIndicator()
                              : const Text('บันทึกรหัสผ่านใหม่'),
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
