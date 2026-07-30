import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.account});

  final AccountUseCases? account;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  AccountUseCases? _account;
  bool _busy = false;
  bool _consent = false;
  bool _obscure = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _account ??=
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account;
  }

  Future<void> _register() async {
    final account = _account;
    if (!_consent) {
      _show('กรุณายอมรับประกาศความเป็นส่วนตัวก่อน');
      return;
    }
    if (account == null || _busy) {
      _show('ระบบบัญชีออนไลน์ไม่พร้อม');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await account.register(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      await AppNavigator.replace<void, void>(
        context,
        AppRoute.emailVerification,
        arguments: EmailVerificationArgs(session.email ?? _email.text),
      );
    } on AccountException catch (error) {
      if (mounted) _show(_failure(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สร้างบัญชี')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'ข้อมูลการเรียนในเครื่องจะย้ายเข้าสู่บัญชีหลังสมัครสำเร็จ '
              'โดยไม่ลบประวัติ Guest',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'อีเมล'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'รหัสผ่านอย่างน้อย 8 ตัวอักษร',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              value: _consent,
              contentPadding: EdgeInsets.zero,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _consent = value ?? false),
              title: const Text(
                'ยอมรับประกาศความเป็นส่วนตัวและเงื่อนไขทดลองใช้',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _register,
                child: const Text('สมัครและส่งอีเมลยืนยัน'),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  String _failure(AccountFailureCode code) => switch (code) {
    AccountFailureCode.invalidEmail => 'รูปแบบอีเมลไม่ถูกต้อง',
    AccountFailureCode.weakPassword => 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร',
    AccountFailureCode.emailInUse => 'อีเมลนี้ถูกใช้แล้ว',
    AccountFailureCode.network => 'ไม่สามารถเชื่อมต่อเครือข่ายได้',
    _ => 'สมัครบัญชีไม่สำเร็จ กรุณาลองใหม่',
  };
}
