import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';

class OTPScreen extends StatefulWidget {
  const OTPScreen({super.key, required this.email, this.account});

  final String email;
  final AccountUseCases? account;

  @override
  State<OTPScreen> createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  AccountUseCases? _account;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _account ??=
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account;
  }

  Future<void> _check() async {
    final account = _account;
    if (account == null || _busy) {
      _show('ระบบยืนยันอีเมลไม่พร้อมใช้งาน');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await account.refreshVerification();
      if (!mounted) return;
      if (session.emailVerified) {
        await AppNavigator.resetTo<void>(context, AppRoute.home);
      } else {
        _show('กรุณายืนยันอีเมลก่อน');
      }
    } on AccountException {
      if (mounted) _show('ตรวจสอบสถานะยืนยันอีเมลไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final account = _account;
    if (account == null || _busy) return;
    setState(() => _busy = true);
    try {
      await account.resendVerification();
      if (mounted) _show('ส่งอีเมลยืนยันอีกครั้งแล้ว');
    } on AccountException {
      if (mounted) _show('ส่งอีเมลยืนยันไม่สำเร็จ');
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ยืนยันอีเมล')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 72),
              const SizedBox(height: 16),
              Text(
                'ส่งลิงก์ยืนยันไปที่\n${widget.email}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _check,
                  child: const Text('ฉันยืนยันอีเมลแล้ว'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: TextButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('ส่งอีเมลยืนยันใหม่'),
                ),
              ),
              if (_busy) const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
