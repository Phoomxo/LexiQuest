import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../services/guest_session_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.guestSessionService, this.account});

  final GuestSessionService? guestSessionService;
  final AccountUseCases? account;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  GuestSessionService? _guest;
  AccountUseCases? _account;
  bool _busy = false;
  bool _obscure = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _guest ??= widget.guestSessionService ?? dependencies?.guestSessionService;
    _account ??= widget.account ?? dependencies?.account;
  }

  Future<void> _signIn() async {
    final account = _account;
    if (account == null || _busy) {
      _show('ระบบบัญชีออนไลน์ไม่พร้อม การเรียนแบบ Guest ยังใช้งานได้');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await account.signIn(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      if (session.emailVerified) {
        await AppNavigator.resetTo<void>(context, AppRoute.home);
      } else {
        await AppNavigator.push<void>(
          context,
          AppRoute.emailVerification,
          arguments: EmailVerificationArgs(session.email ?? _email.text),
        );
      }
    } on AccountException catch (error) {
      if (mounted) _show(_accountFailure(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startGuest() async {
    final guest = _guest;
    if (guest == null || _busy) return;
    setState(() => _busy = true);
    final result = await guest.start();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is GuestSessionStarted) {
      await AppNavigator.resetTo<void>(context, AppRoute.home);
    } else {
      _show('เริ่มโหมด Guest ไม่สำเร็จ กรุณาตรวจเครือข่ายหรือลองใหม่');
    }
  }

  Future<void> _forgotPassword() async {
    final emailController = TextEditingController(text: _email.text);
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('รีเซ็ตรหัสผ่าน'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'อีเมล'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, emailController.text),
            child: const Text('ส่งลิงก์'),
          ),
        ],
      ),
    );
    emailController.dispose();
    if (email == null || !mounted) return;
    final account = _account;
    if (account == null) {
      _show('ระบบบัญชีออนไลน์ไม่พร้อม');
      return;
    }
    try {
      await account.sendPasswordReset(email);
      if (mounted) {
        _show('ส่งอีเมลรีเซ็ตรหัสผ่านแล้ว หากมีบัญชีนี้อยู่ในระบบ');
      }
    } on AccountException catch (error) {
      if (mounted) _show(_accountFailure(error.code));
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
      appBar: AppBar(title: const Text('เข้าสู่ระบบ LexiQuest')),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.menu_book_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                decoration: const InputDecoration(
                  labelText: 'อีเมล',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'รหัสผ่าน',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: const Text('ลืมรหัสผ่าน'),
                ),
              ),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: const Text('เข้าสู่ระบบ'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  key: const ValueKey<String>('guest-mode-button'),
                  onPressed: _busy ? null : _startGuest,
                  child: const Text('เรียนแบบ Guest'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => AppNavigator.push<void>(context, AppRoute.register),
                child: const Text('สร้างบัญชีใหม่'),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _accountFailure(AccountFailureCode code) => switch (code) {
  AccountFailureCode.invalidEmail => 'รูปแบบอีเมลไม่ถูกต้อง',
  AccountFailureCode.weakPassword => 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร',
  AccountFailureCode.emailInUse => 'อีเมลนี้ถูกใช้แล้ว',
  AccountFailureCode.invalidCredential => 'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
  AccountFailureCode.userDisabled => 'บัญชีนี้ถูกระงับ',
  AccountFailureCode.tooManyRequests => 'มีคำขอมากเกินไป กรุณาลองภายหลัง',
  AccountFailureCode.requiresRecentLogin => 'กรุณาเข้าสู่ระบบใหม่ก่อนทำรายการ',
  AccountFailureCode.invalidActionCode => 'ลิงก์ยืนยันไม่ถูกต้อง',
  AccountFailureCode.expiredActionCode => 'ลิงก์ยืนยันหมดอายุแล้ว',
  AccountFailureCode.network => 'ไม่สามารถเชื่อมต่อเครือข่ายได้',
  AccountFailureCode.unavailable => 'ผู้ให้บริการบัญชีไม่พร้อมใช้งาน',
  AccountFailureCode.cancelled => 'ยกเลิกรายการแล้ว',
  AccountFailureCode.unknown => 'ทำรายการบัญชีไม่สำเร็จ',
};
