import 'package:flutter/material.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';

/// Owns credential fields only for the lifetime of this explicit dialog.
class PasswordChangeDialog extends StatefulWidget {
  const PasswordChangeDialog({
    super.key,
    required this.account,
    required this.isCurrent,
  });
  final AccountUseCases account;
  final bool Function() isCurrent;
  @override
  State<PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _pending = false;
  bool _closed = false;
  bool _finished = false;
  String? _message;
  bool get _active =>
      mounted &&
      !_closed &&
      widget.isCurrent() &&
      ModalRoute.of(context)?.isCurrent == true;
  void _close() {
    if (!_active || _pending) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (!_active || _pending || _finished) return;
    if (_current.text.length < 8 ||
        _current.text.length > 128 ||
        _next.text.length < 8 ||
        _next.text.length > 128) {
      setState(
        () => _message = 'กรอกรหัสผ่านปัจจุบันและรหัสผ่านใหม่ 8–128 ตัวอักษร',
      );
      return;
    }
    setState(() {
      _pending = true;
      _message = null;
    });
    try {
      await widget.account.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
        isCurrent: () => _active,
      );
      if (_active) {
        setState(() {
          _finished = true;
          _message = 'เปลี่ยนรหัสผ่านแล้ว';
        });
      }
    } catch (error) {
      if (_active) {
        final code = error is AccountException ? error.code : null;
        final known =
            code == AccountFailureCode.invalidCredential ||
            code == AccountFailureCode.weakPassword ||
            code == AccountFailureCode.requiresRecentLogin ||
            code == AccountFailureCode.cancelled;
        setState(() {
          _finished = !known;
          _message = code == AccountFailureCode.requiresRecentLogin
              ? 'กรุณาเข้าสู่ระบบใหม่ก่อนเปลี่ยนรหัสผ่าน'
              : code == AccountFailureCode.cancelled
              ? 'บริบทบัญชีเปลี่ยนแล้ว กรุณาปิดและเปิดใหม่'
              : known
              ? 'ตรวจรหัสผ่านแล้วกดบันทึกอีกครั้งด้วยตนเอง'
              : 'ยังยืนยันผลการเปลี่ยนรหัสผ่านไม่ได้ รหัสผ่านอาจเปลี่ยนแล้ว กรุณาปิดและตรวจการเข้าสู่ระบบด้วยตนเองก่อนเริ่มรายการใหม่';
        });
      }
    } finally {
      if (mounted) {
        if (_finished) {
          _current.clear();
          _next.clear();
        }
        setState(() => _pending = false);
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_pending,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _closed = true;
    },
    child: AlertDialog(
      title: const Text('เปลี่ยนรหัสผ่าน'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_finished) ...[
              TextField(
                controller: _current,
                obscureText: true,
                enabled: !_pending,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'รหัสผ่านปัจจุบัน',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _next,
                obscureText: true,
                enabled: !_pending,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'รหัสผ่านใหม่อย่างน้อย 8 ตัวอักษร',
                ),
              ),
            ],
            if (_message != null)
              Semantics(liveRegion: true, child: Text(_message!)),
            if (_pending) const Text('กำลังดำเนินการ กรุณารอผล'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _pending ? null : _close,
          child: Text(_finished ? 'ปิด' : 'ยกเลิก'),
        ),
        if (!_finished)
          FilledButton(
            onPressed: _pending ? null : _save,
            child: const Text('บันทึก'),
          ),
      ],
    ),
  );
}
