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
  static const _uncertainMessage =
      'ยังยืนยันผลไม่ได้ กรุณาลองเข้าสู่ระบบหรือขอลิงก์ใหม่';
  final _password = TextEditingController();
  AccountUseCases? _account;
  int _generation = 0;
  bool _busy = false;
  bool _completed = false;
  bool _terminalError = false;
  bool _verificationStarted = false;
  bool _uncertainOutcome = false;
  String? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAccount();
    _verifyOnce();
  }

  @override
  void didUpdateWidget(covariant EmailActionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action.mode != widget.action.mode ||
        oldWidget.action.code != widget.action.code) {
      _resetAction();
      _verificationStarted = false;
    }
    _updateAccount();
    _verifyOnce();
  }

  void _resetAction() {
    _generation++;
    _busy = false;
    _completed = false;
    _terminalError = false;
    _uncertainOutcome = false;
    _status = null;
    _password.clear();
  }

  void _updateAccount() {
    final account =
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account;
    if (identical(account, _account)) return;
    _resetAction();
    _account = account;
    if (_verificationStarted) {
      _status = 'สถานะระบบบัญชีเปลี่ยน กรุณาเปิดลิงก์อีกครั้ง';
    }
  }

  void _verifyOnce() {
    if (widget.action.mode != EmailActionMode.verifyEmail ||
        _verificationStarted) {
      return;
    }
    _verificationStarted = true;
    _apply(_generation);
  }

  Future<void> _apply(int generation) async {
    final account = _account;
    final action = widget.action;
    if (!mounted ||
        generation != _generation ||
        account == null ||
        _busy ||
        _completed ||
        _terminalError ||
        action.mode == EmailActionMode.unknown) {
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await account.applyEmailAction(
        action,
        newPassword: action.mode == EmailActionMode.resetPassword
            ? _password.text
            : null,
      );
      if (!mounted || generation != _generation) return;
      _password.clear();
      setState(() {
        _completed = true;
        _uncertainOutcome = false;
        _status = action.mode == EmailActionMode.verifyEmail
            ? 'ยืนยันอีเมลสำเร็จ'
            : 'เปลี่ยนรหัสผ่านสำเร็จ';
      });
    } on AccountException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _terminalError =
            error.code == AccountFailureCode.invalidActionCode ||
            error.code == AccountFailureCode.expiredActionCode;
        if (_terminalError) _password.clear();
        // A dispatched reset may have committed before its acknowledgement failed.
        if (!_terminalError && error.code != AccountFailureCode.weakPassword) {
          _uncertainOutcome = true;
        }
        _status = switch (error.code) {
          AccountFailureCode.expiredActionCode =>
            'ลิงก์นี้หมดอายุแล้ว กรุณาขอลิงก์ใหม่จากหน้าเข้าสู่ระบบ',
          AccountFailureCode.invalidActionCode =>
            'ลิงก์นี้ไม่ถูกต้องหรือถูกใช้แล้ว',
          AccountFailureCode.weakPassword => 'รหัสผ่านต้องมี 8–128 ตัวอักษร',
          AccountFailureCode.network => 'เชื่อมต่อไม่ได้ กรุณาลองใหม่',
          AccountFailureCode.tooManyRequests =>
            'มีคำขอมากเกินไป กรุณาลองภายหลัง',
          _ => _uncertainMessage,
        };
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _uncertainOutcome = true;
        _status = _uncertainMessage;
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
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
    final unknown = widget.action.mode == EmailActionMode.unknown;
    final generation = _generation;
    final status = unknown
        ? 'ลิงก์นี้ไม่ถูกต้องหรือถูกใช้แล้ว'
        : _account == null
        ? 'ระบบบัญชีออนไลน์ไม่พร้อม กรุณาลองภายหลังหรือกลับหน้าเข้าสู่ระบบ'
        : _status;
    return Scaffold(
      appBar: AppBar(title: Text(reset ? 'ตั้งรหัสผ่านใหม่' : 'ยืนยันอีเมล')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (reset && !_completed && _account != null) ...[
                  TextField(
                    controller: _password,
                    enabled: !_busy && !_terminalError,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'รหัสผ่านใหม่',
                      helperText: 'ใช้รหัสผ่าน 8–128 ตัวอักษร',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _busy || _terminalError
                          ? null
                          : () => _apply(generation),
                      child: Text(
                        _busy ? 'กำลังเปลี่ยนรหัสผ่าน…' : 'เปลี่ยนรหัสผ่าน',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
                if (_busy)
                  Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: reset
                          ? 'กำลังเปลี่ยนรหัสผ่าน'
                          : 'กำลังยืนยันอีเมล',
                    ),
                  ),
                if (status != null) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(status, textAlign: TextAlign.center),
                  ),
                ],
                if (_uncertainOutcome && status != _uncertainMessage) ...[
                  const SizedBox(height: 16),
                  Text(_uncertainMessage, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 16),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () =>
                      AppNavigator.resetTo<void>(context, AppRoute.login),
                  child: const Text('กลับหน้าเข้าสู่ระบบ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
