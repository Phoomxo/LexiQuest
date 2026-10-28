import 'package:flutter/material.dart';

import '../account/account_error_mapper.dart';
import '../account/account_gateway.dart';
import '../account/account_validation.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.accountGateway});

  final AccountGateway accountGateway;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submit() async {
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.accountGateway.changePassword(
        currentPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmationController.clear();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on AccountOperationException catch (error) {
      if (!mounted) return;
      _currentPasswordController.clear();
      _showError(AccountErrorMapper.messageFor(error.code));
    } on Object {
      if (!mounted) return;
      _currentPasswordController.clear();
      _showError(AccountErrorMapper.messageFor('unknown'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('เปลี่ยนรหัสผ่าน')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey<String>('change-password-current'),
                controller: _currentPasswordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                validator: (value) =>
                    (value ?? '').isEmpty ? 'กรุณากรอกรหัสผ่านปัจจุบัน' : null,
                decoration: const InputDecoration(
                  labelText: 'รหัสผ่านปัจจุบัน',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('change-password-new'),
                controller: _newPasswordController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                validator: (value) =>
                    AccountValidation.passwordError(value ?? ''),
                decoration: const InputDecoration(
                  labelText: 'รหัสผ่านใหม่',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('change-password-confirmation'),
                controller: _confirmationController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                validator: (value) => AccountValidation.confirmationError(
                  _newPasswordController.text,
                  value ?? '',
                ),
                decoration: const InputDecoration(
                  labelText: 'ยืนยันรหัสผ่านใหม่',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const ValueKey<String>('change-password-submit'),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('บันทึกรหัสผ่านใหม่'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
