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
  final _confirmPassword = TextEditingController();
  AccountUseCases? _account;
  ResearchConsentUseCases? _researchConsent;
  bool _busy = false;
  bool _consent = false;
  bool _obscure = true;
  String? _emailError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _consentError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _account ??= widget.account ?? dependencies?.account;
    _researchConsent ??=
        widget.researchConsent ?? dependencies?.researchConsent;
  }

  Future<void> _register() async {
    if (_busy) return;
    final account = _account;
    final emailError = _registrationEmailError(_email.text);
    final passwordError = _registrationPasswordError(_password.text);
    final confirmPasswordError = _registrationConfirmationError(
      _password.text,
      _confirmPassword.text,
    );
    final consentError = _consent
        ? null
        : 'กรุณายอมรับประกาศความเป็นส่วนตัวก่อน';
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmPasswordError = confirmPasswordError;
      _consentError = consentError;
    });
    if (emailError != null ||
        passwordError != null ||
        confirmPasswordError != null ||
        consentError != null) {
      return;
    }
    if (account == null) {
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
      final researchConsent = _researchConsent;
      if (researchConsent != null) {
        try {
          final consentContext = await researchConsent.load();
          if (!mounted) return;
          final accepted = await showResearchConsentDialog(context);
          var recorded = true;
          if (accepted == true) {
            recorded = await researchConsent.accept(
              expectedOwnerId: consentContext.ownerId,
            );
          } else if (accepted == false && consentContext.accepted) {
            recorded = await researchConsent.withdraw(
              expectedOwnerId: consentContext.ownerId,
            );
          }
          if (!recorded && mounted) {
            _show('สถานะผู้ใช้เปลี่ยน จึงไม่ได้บันทึกความยินยอมการวิจัย');
          }
        } catch (_) {
          if (mounted) {
            _show(
              'ตรวจสอบสถานะการวิจัยไม่ได้ '
              'จึงไม่ได้บันทึกความยินยอมการวิจัย',
            );
          }
        }
      }
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

  Future<void> _showPrivacyNotice() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ประกาศความเป็นส่วนตัวและเงื่อนไขทดลองใช้'),
        content: const SingleChildScrollView(
          child: Text(
            'LexiQuest ใช้อีเมลเพื่อสร้างและดูแลบัญชี '
            'และเก็บข้อมูลคำศัพท์กับความคืบหน้าการเรียนเพื่อให้บริการแก่คุณ\n\n'
            'กล้อง ไมโครโฟน และผู้ช่วย AI จะทำงานเมื่อคุณเลือกใช้ฟีเจอร์นั้น '
            'คุณส่งออกหรือลบบัญชีและข้อมูลได้จากการตั้งค่า\n\n'
            'การเข้าร่วมงานวิจัยเป็นทางเลือกและจะถามแยกหลังสร้างบัญชี '
            'การไม่เข้าร่วมไม่กระทบการเรียนตามปกติ',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('รับทราบ'),
          ),
        ],
      ),
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
    _confirmPassword.dispose();
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
              'โดยไม่ลบประวัติการเรียนในเครื่อง',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'อีเมล',
                errorText: _emailError,
              ),
              onChanged: (_) {
                if (_emailError != null) {
                  setState(() => _emailError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'รหัสผ่านอย่างน้อย 8 ตัวอักษร',
                errorText: _passwordError,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                ),
              ),
              onChanged: (_) {
                if (_passwordError != null || _confirmPasswordError != null) {
                  setState(() {
                    _passwordError = null;
                    _confirmPasswordError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmPassword,
              enabled: !_busy,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'ยืนยันรหัสผ่าน',
                errorText: _confirmPasswordError,
              ),
              onChanged: (_) {
                if (_confirmPasswordError != null) {
                  setState(() => _confirmPasswordError = null);
                }
              },
            ),
            CheckboxListTile(
              value: _consent,
              contentPadding: EdgeInsets.zero,
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _consent = value ?? false;
                      _consentError = null;
                    }),
              title: const Text(
                'อ่านและรับทราบประกาศความเป็นส่วนตัวและเงื่อนไขทดลองใช้',
              ),
            ),
            if (_consentError case final error?)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextButton(
              onPressed: _busy ? null : _showPrivacyNotice,
              child: const Text('อ่านประกาศความเป็นส่วนตัว'),
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
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'กำลังสร้างบัญชี',
                  ),
                ),
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

String? _registrationEmailError(String value) {
  final email = value.trim();
  if (email.isEmpty) return 'กรอกอีเมล';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
      ? null
      : 'ตรวจสอบรูปแบบอีเมล';
}

String? _registrationPasswordError(String value) {
  if (value.length < 8) return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
  if (value.length > 128) return 'รหัสผ่านต้องไม่เกิน 128 ตัวอักษร';
  return null;
}

String? _registrationConfirmationError(String password, String confirmation) {
  if (confirmation.isEmpty) return 'ยืนยันรหัสผ่าน';
  return password == confirmation ? null : 'รหัสผ่านและการยืนยันไม่ตรงกัน';
}
