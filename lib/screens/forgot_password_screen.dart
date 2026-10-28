import 'package:flutter/material.dart';

import '../account/account_cooldown.dart';
import '../account/account_error_mapper.dart';
import '../account/account_gateway.dart';
import '../account/account_validation.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.accountGateway,
    this.cooldown,
  });

  final AccountGateway accountGateway;
  final AccountCooldown? cooldown;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  late final AccountCooldown _cooldown = widget.cooldown ?? AccountCooldown();
  bool _isSubmitting = false;
  String? _retryEmail;

  String? _validateEmail(String? value) =>
      AccountValidation.emailError(value ?? '');

  Future<void> _submit([String? email]) async {
    if (_isSubmitting) return;
    if (email == null && !(_formKey.currentState?.validate() ?? false)) return;
    if (!_cooldown.canSubmit) {
      _showMessage(
        'กรุณารอ ${_cooldown.remaining.inSeconds} วินาทีก่อนส่งอีเมลอีกครั้ง',
      );
      return;
    }

    final normalizedEmail = AccountValidation.normalizeEmail(
      email ?? _emailController.text,
    );
    setState(() => _isSubmitting = true);
    try {
      await widget.accountGateway.requestPasswordReset(normalizedEmail);
      _showAccepted();
    } on AccountOperationException catch (error) {
      if (error.code == 'user-not-found' || error.code == 'email-not-found') {
        _showAccepted();
      } else {
        if (mounted) setState(() => _retryEmail = normalizedEmail);
        _showMessage(AccountErrorMapper.messageFor(error.code));
      }
    } on Object {
      if (mounted) setState(() => _retryEmail = normalizedEmail);
      _showMessage(AccountErrorMapper.messageFor('unknown'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showAccepted() {
    _cooldown.start();
    if (mounted) {
      setState(() => _retryEmail = null);
      _showMessage(AccountErrorMapper.recoveryAcceptedMessage);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลืมรหัสผ่าน')),
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
                    'ตั้งรหัสผ่านใหม่',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const ValueKey<String>('recovery-email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: _validateEmail,
                    decoration: const InputDecoration(
                      labelText: 'อีเมล',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const ValueKey<String>('recovery-submit'),
                    onPressed: _isSubmitting ? null : _submit,
                    child: const Text('ส่งลิงก์ตั้งรหัสผ่านใหม่'),
                  ),
                  if (_retryEmail != null)
                    TextButton(
                      key: const ValueKey<String>('recovery-retry'),
                      onPressed: _isSubmitting
                          ? null
                          : () => _submit(_retryEmail),
                      child: const Text('ลองส่งอีกครั้ง'),
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
