import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';

class EmailActionScreen extends StatefulWidget {
  const EmailActionScreen({super.key, required this.action, this.account});

  final EmailAction action;
  final AccountUseCases? account;

  @override
  State<EmailActionScreen> createState() => _EmailActionScreenState();
}

class _EmailActionScreenState extends State<EmailActionScreen> {
  final _password = TextEditingController();
  AccountUseCases? _account;
  bool _busy = false;
  String? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _account ??=
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account;
    if (widget.action.mode == EmailActionMode.verifyEmail &&
        !_busy &&
        _status == null) {
      _apply();
    }
  }

  Future<void> _apply() async {
    final account = _account;
    if (account == null || _busy) return;
    setState(() => _busy = true);
    try {
      await account.applyEmailAction(
        widget.action,
        newPassword: widget.action.mode == EmailActionMode.resetPassword
            ? _password.text
            : null,
      );
      if (!mounted) return;
      setState(() {
        _status = widget.action.mode == EmailActionMode.verifyEmail
            ? 'ยืนยันอีเมลสำเร็จ'
            : 'เปลี่ยนรหัสผ่านสำเร็จ';
      });
    } on AccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _status = switch (error.code) {
          AccountFailureCode.expiredActionCode => 'ลิงก์นี้หมดอายุแล้ว',
          AccountFailureCode.weakPassword =>
            'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร',
          _ => 'ลิงก์นี้ไม่ถูกต้องหรือถูกใช้งานแล้ว',
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reset = widget.action.mode == EmailActionMode.resetPassword;
    return Scaffold(
      appBar: AppBar(title: Text(reset ? 'ตั้งรหัสผ่านใหม่' : 'ยืนยันอีเมล')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              if (reset && _status == null) ...[
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'รหัสผ่านใหม่อย่างน้อย 8 ตัวอักษร',
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _apply,
                    child: const Text('เปลี่ยนรหัสผ่าน'),
                  ),
                ),
              ],
              if (_busy) const CircularProgressIndicator(),
              if (_status != null) ...[
                Text(_status!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      AppNavigator.resetTo<void>(context, AppRoute.login),
                  child: const Text('กลับหน้าเข้าสู่ระบบ'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
