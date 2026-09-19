import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/research_consent_dialog.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.account, this.researchConsent});

  final AccountUseCases? account;
  final ResearchConsentUseCases? researchConsent;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  AccountUseCases? _account;
  ResearchConsentUseCases? _researchConsent;
  bool _busy = false;
  AccountSession? _registeredSession;
  bool _verificationPending = false;
  bool? _researchDecision;
  String? _completionError;
  bool _consent = false;
  bool _researchAcceptedFromDetails = false;
  bool _obscure = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _account ??= widget.account ?? dependencies?.account;
    _researchConsent ??=
        widget.researchConsent ?? dependencies?.researchConsent;
  }

  Future<void> _register() async {
    if (!mounted || _busy) return;
    final account = _account;
    if (!_consent) {
      _show('กรุณายอมรับประกาศความเป็นส่วนตัวก่อน');
      return;
    }
    if (account == null || _busy) {
      _show('ระบบบัญชีออนไลน์ไม่พร้อม');
      return;
    }
    setState(() {
      _busy = true;
      _completionError = null;
    });
    try {
      final continuing = _registeredSession != null;
      final session = _registeredSession ??= await account.register(
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      if (!continuing) _verificationPending = session.verificationEmailPending;
      if (_verificationPending) {
        if (!continuing) {
          _markCompletionPending();
          return;
        }
        await account.resendVerification();
        _verificationPending = false;
        if (!mounted) return;
      }
      final researchConsent = _researchConsent;
      if (researchConsent != null) {
        final accepted = _researchDecision ??=
            _researchAcceptedFromDetails ||
            await showResearchConsentDialog(context);
        if (accepted) {
          await researchConsent.accept();
        } else {
          await researchConsent.withdraw();
        }
      }
      if (!mounted) return;
      await AppNavigator.replace<void, void>(
        context,
        AppRoute.emailVerification,
        arguments: EmailVerificationArgs(session.email ?? _email.text),
      );
    } on AccountException catch (error) {
      if (mounted) {
        if (_registeredSession == null) {
          _show(_failure(error.code));
        } else {
          _markCompletionPending();
        }
      }
    } on Object {
      if (mounted) {
        if (_registeredSession == null) {
          _show('สมัครบัญชีไม่สำเร็จ กรุณาลองใหม่');
        } else {
          _markCompletionPending();
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _markCompletionPending() {
    setState(
      () => _completionError = _verificationPending
          ? 'สร้างบัญชีแล้ว แต่ส่งอีเมลยืนยันไม่สำเร็จ '
                'กดดำเนินการต่อเพื่อส่งอีเมลอีกครั้ง โดยไม่ต้องสมัครบัญชีใหม่'
          : 'สร้างบัญชีแล้ว แต่ยังยืนยันการบันทึกความยินยอมไม่ได้ '
                'กรุณาลองดำเนินการต่อ โดยไม่ต้องสมัครบัญชีใหม่',
    );
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
              enabled: !_busy && _registeredSession == null,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'อีเมล'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy && _registeredSession == null,
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
              onChanged: _busy || _registeredSession != null
                  ? null
                  : (value) => setState(() {
                      _consent = value ?? false;
                      if (!_consent) _researchAcceptedFromDetails = false;
                    }),
              title: const Text(
                'อ่านและรับทราบประกาศความเป็นส่วนตัวและเงื่อนไขทดลองใช้',
              ),
            ),
            TextButton(
              onPressed: _busy || _registeredSession != null
                  ? null
                  : () async {
                      final accepted = await showResearchConsentDialog(context);
                      if (mounted && accepted) {
                        setState(() {
                          _consent = true;
                          _researchAcceptedFromDetails = true;
                        });
                      }
                    },
              child: const Text('อ่านรายละเอียดการเข้าร่วมและการใช้ข้อมูล'),
            ),
            if (_completionError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _completionError!,
                  key: const ValueKey('registration-completion-error'),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const ValueKey('registration-continue'),
                onPressed: _busy ? null : _register,
                child: Text(
                  _registeredSession == null
                      ? 'สมัครและส่งอีเมลยืนยัน'
                      : 'ดำเนินการต่อ',
                ),
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
