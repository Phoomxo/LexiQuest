import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../services/guest_session_service.dart';
import '../widgets/research_consent_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.guestSessionService,
    this.account,
    this.researchConsent,
  });

  final GuestSessionService? guestSessionService;
  final AccountUseCases? account;
  final ResearchConsentUseCases? researchConsent;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  GuestSessionService? _guest;
  AccountUseCases? _account;
  ResearchConsentUseCases? _researchConsent;
  bool _busy = false;
  bool _obscure = true;
  String? _emailError;
  String? _passwordError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _guest ??= widget.guestSessionService ?? dependencies?.guestSessionService;
    _account ??= widget.account ?? dependencies?.account;
    _researchConsent ??=
        widget.researchConsent ?? dependencies?.researchConsent;
  }

  Future<void> _signIn() async {
    final account = _account;
    if (_busy) return;
    if (account == null) {
      _show('ระบบบัญชีออนไลน์ไม่พร้อม คุณยังเรียนโดยไม่ใช้บัญชีได้');
      return;
    }
    final email = _email.text.trim();
    final emailError = _emailErrorText(email);
    final passwordError = _password.text.isEmpty ? 'กรอกรหัสผ่าน' : null;
    if (emailError != null || passwordError != null) {
      setState(() {
        _emailError = emailError;
        _passwordError = passwordError;
      });
      return;
    }
    setState(() {
      _busy = true;
      _emailError = null;
      _passwordError = null;
    });
    try {
      final session = await account.signIn(
        email: email,
        password: _password.text,
      );
      await _completeSignIn(session, fallbackEmail: email);
    } on AccountException catch (error) {
      if (mounted) _show(_accountFailure(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final account = _account;
    if (_busy) return;
    if (account == null || !account.googleSignInAvailable) {
      _show('ผู้ให้บริการบัญชีไม่พร้อมใช้งาน');
      return;
    }
    setState(() => _busy = true);
    try {
      final session = await account.signInWithGoogle();
      await _completeSignIn(session);
    } on AccountException catch (error) {
      if (mounted) _show(_accountFailure(error.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeSignIn(
    AccountSession session, {
    String fallbackEmail = '',
  }) async {
    if (!mounted) return;
    await _ensureResearchConsentDecision();
    if (!mounted) return;
    if (session.emailVerified) {
      await AppNavigator.resetTo<void>(context, AppRoute.home);
    } else {
      await AppNavigator.push<void>(
        context,
        AppRoute.emailVerification,
        arguments: EmailVerificationArgs(session.email ?? fallbackEmail),
      );
    }
  }

  Future<void> _startGuest() async {
    final guest = _guest;
    if (guest == null || _busy) return;
    await _ensureResearchConsentDecision();
    if (!mounted) return;
    setState(() => _busy = true);
    final result = await guest.start();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is GuestSessionStarted) {
      await AppNavigator.resetTo<void>(context, AppRoute.home);
    } else {
      _show('เริ่มเรียนโดยไม่ใช้บัญชีไม่สำเร็จ กรุณาตรวจเครือข่ายหรือลองใหม่');
    }
  }

  Future<void> _ensureResearchConsentDecision() async {
    final consent = _researchConsent;
    if (consent == null) return;
    try {
      final current = await consent.load();
      if (current.accepted || current.withdrawnAtUtc != null || !mounted) {
        return;
      }
      final accepted = await showResearchConsentDialog(context);
      if (accepted != true) return;
      final recorded = await consent.accept(expectedOwnerId: current.ownerId);
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

  Future<void> _forgotPassword() async {
    var resetEmail = _email.text;
    String? resetError;
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final value = resetEmail.trim();
            final error = _emailErrorText(value);
            if (error != null) {
              setDialogState(() => resetError = error);
              return;
            }
            Navigator.pop(dialogContext, value);
          }

          return AlertDialog(
            title: const Text('รีเซ็ตรหัสผ่าน'),
            content: TextFormField(
              initialValue: resetEmail,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: 'อีเมล',
                errorText: resetError,
              ),
              onChanged: (value) {
                resetEmail = value;
                if (resetError != null) {
                  setDialogState(() => resetError = null);
                }
              },
              onFieldSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(onPressed: submit, child: const Text('ส่งลิงก์')),
            ],
          );
        },
      ),
    );
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
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = ((width - 560) / 2)
        .clamp(24.0, double.infinity)
        .toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('เข้าสู่ระบบ LexiQuest')),
      body: SafeArea(
        child: Stack(
          children: [
            AutofillGroup(
              child: ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 24,
                ),
                children: [
                  const SizedBox(height: 32),
                  Icon(
                    Icons.menu_book_outlined,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'สร้างคลังคำของคุณ ฝึกทบทวน '
                    'และติดตามความก้าวหน้าภาษาอังกฤษ',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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
                    ).copyWith(errorText: _emailError),
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
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _signIn(),
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่าน',
                      prefixIcon: const Icon(Icons.lock_outline),
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
                      if (_passwordError != null) {
                        setState(() => _passwordError = null);
                      }
                    },
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
                  if (_account?.googleSignInAvailable == true) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>('google-sign-in-button'),
                        onPressed: _busy ? null : _signInWithGoogle,
                        icon: const Icon(Icons.account_circle_outlined),
                        label: const Text('ใช้บัญชี Google'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      key: const ValueKey<String>('guest-mode-button'),
                      onPressed: _busy ? null : _startGuest,
                      child: const Text('เรียนต่อโดยไม่ใช้บัญชี'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => AppNavigator.push<void>(
                            context,
                            AppRoute.register,
                          ),
                    child: const Text('สร้างบัญชีใหม่'),
                  ),
                ],
              ),
            ),
            if (_busy)
              const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังเข้าสู่ระบบ',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String? _emailErrorText(String value) {
  final email = value.trim();
  if (email.isEmpty) return 'กรอกอีเมล';
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
      ? null
      : 'ตรวจสอบรูปแบบอีเมล';
}

String _accountFailure(AccountFailureCode code) => switch (code) {
  AccountFailureCode.invalidEmail => 'รูปแบบอีเมลไม่ถูกต้อง',
  AccountFailureCode.invalidDisplayName => 'ชื่อที่แสดงไม่ถูกต้อง',
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
