import 'package:flutter/material.dart';

import '../account/account_error_mapper.dart';
import '../account/account_gateway.dart';
import '../account/account_models.dart';
import '../account/account_profile_provisioner.dart';
import '../account/account_validation.dart';
import '../navigation/app_route.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    this.accountGateway,
    this.profileProvisioner,
    this.recoveredSession,
    required this.guestUpgradeHandoff,
  });

  final AccountGateway? accountGateway;
  final AccountProfileProvisioning? profileProvisioner;
  final AccountSession? recoveredSession;
  final GuestUpgradeHandoff guestUpgradeHandoff;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _ageController = TextEditingController();
  bool _isSubmitting = false;
  AccountSession? _createdSession;
  GuestUpgradeResult? _guestUpgrade;
  bool _handoffAttempted = false;

  bool get _isRecovery =>
      _createdSession != null || widget.recoveredSession != null;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.recoveredSession?.email ?? '';
  }

  Future<void> _register() async {
    final gateway = widget.accountGateway;
    final provisioner = widget.profileProvisioner;
    if (_isSubmitting || !(_formKey.currentState?.validate() ?? false)) return;
    if (gateway == null || provisioner == null) {
      _showError('ระบบสมัครสมาชิกยังไม่พร้อม กรุณาลองใหม่อีกครั้ง');
      return;
    }

    setState(() => _isSubmitting = true);
    final email = AccountValidation.normalizeEmail(_emailController.text);
    final profile = AccountProfile(
      firstName: _firstNameController.text,
      lastName: _lastNameController.text,
      email: email,
      age: int.parse(_ageController.text.trim()),
    );
    try {
      final session =
          _createdSession ??
          widget.recoveredSession ??
          await _createOrUpgrade(
            gateway: gateway,
            email: email,
            password: _passwordController.text,
          );
      _createdSession ??= session;
      await provisioner.ensureProfile(session.uid, profile);
      await gateway.sendVerificationEmail();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(
        AppRoute.verifyEmail.path,
        arguments: VerifyEmailRouteArgs(email: email),
      );
    } on AccountOperationException catch (error) {
      if (mounted) _showError(AccountErrorMapper.messageFor(error.code));
    } on Object {
      if (mounted) _showError(AccountErrorMapper.messageFor('unknown'));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<AccountSession> _createOrUpgrade({
    required AccountGateway gateway,
    required String email,
    required String password,
  }) async {
    final existingUpgrade = _guestUpgrade;
    if (existingUpgrade != null) {
      return existingUpgrade.session;
    }
    if (gateway.currentSession?.isAnonymous == true) {
      final upgrade = await gateway.upgradeAnonymous(
        email: email,
        password: password,
      );
      _guestUpgrade = upgrade;
      _createdSession = upgrade.session;
      if (!_handoffAttempted) {
        _handoffAttempted = true;
        await widget.guestUpgradeHandoff(upgrade.previousUid, upgrade.session);
      }
      return upgrade.session;
    }
    return gateway.createAccount(email: email, password: password);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สมัครสมาชิก')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'สร้างบัญชีเพื่อเริ่มเรียนกับ LexiQuest',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey<String>('register-email'),
                  controller: _emailController,
                  readOnly: _isRecovery,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) =>
                      AccountValidation.emailError(value ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'อีเมล',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (!_isRecovery) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey<String>('register-password'),
                    controller: _passwordController,
                    obscureText: true,
                    validator: (value) =>
                        AccountValidation.passwordError(value ?? ''),
                    decoration: const InputDecoration(
                      labelText: 'รหัสผ่าน',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey<String>('register-confirmation'),
                    controller: _confirmationController,
                    obscureText: true,
                    validator: (value) => AccountValidation.confirmationError(
                      _passwordController.text,
                      value ?? '',
                    ),
                    decoration: const InputDecoration(
                      labelText: 'ยืนยันรหัสผ่าน',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey<String>('register-first-name'),
                  controller: _firstNameController,
                  validator: (value) =>
                      AccountValidation.firstNameError(value ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'ชื่อ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey<String>('register-last-name'),
                  controller: _lastNameController,
                  validator: (value) =>
                      AccountValidation.lastNameError(value ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'นามสกุล',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey<String>('register-age'),
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  validator: (value) => AccountValidation.ageError(value ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'อายุ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey<String>('register-submit'),
                  onPressed: _isSubmitting ? null : _register,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('สมัครสมาชิกและส่งอีเมลยืนยัน'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
