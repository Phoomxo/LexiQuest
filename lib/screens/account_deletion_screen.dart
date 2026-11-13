import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../features/account_deletion/application/account_deletion_use_cases.dart';
import '../features/account_deletion/domain/account_deletion_contracts.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({
    super.key,
    required this.useCases,
    this.idempotencyKey,
  });

  final AccountDeletionUseCases useCases;
  final String? idempotencyKey;

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  static const _confirmation = 'ลบบัญชี';
  final _controller = TextEditingController();
  late final String _idempotencyKey =
      widget.idempotencyKey ?? 'delete:${const Uuid().v4()}';
  bool _busy = false;
  bool _completed = false;
  String? _message;
  CloudDeletionReceipt? _cloudReceipt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _controller.text != _confirmation) return;
    setState(() {
      _busy = true;
      _message = 'กำลังส่งออกสำเนาและลบบัญชี…';
    });
    try {
      final pending = _cloudReceipt;
      if (pending == null) {
        await widget.useCases.deleteAccount(idempotencyKey: _idempotencyKey);
      } else {
        await widget.useCases.resumeLocalDeletion(pending);
      }
      if (!mounted) return;
      setState(() {
        _completed = true;
        _message = 'ลบบัญชีและข้อมูลในอุปกรณ์นี้เรียบร้อยแล้ว';
      });
    } on AccountDeletionException catch (error) {
      if (!mounted) return;
      setState(() {
        _cloudReceipt = error.cloudReceipt ?? _cloudReceipt;
        _message = _failureText(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'ดำเนินการไม่สำเร็จ โปรดลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _failureText(AccountDeletionException error) {
    if (_cloudReceipt != null) {
      return 'ลบบัญชีออนไลน์แล้ว แต่ยังลบข้อมูลในอุปกรณ์ไม่ครบ '
          'กดลองอีกครั้งเพื่อทำต่อจากจุดเดิม';
    }
    return switch (error.code) {
      AccountDeletionFailureCode.fullExportFailed ||
      AccountDeletionFailureCode.fullExportRequired =>
        'ส่งออกสำเนาข้อมูลไม่สำเร็จ จึงยังไม่ได้ลบบัญชี',
      AccountDeletionFailureCode.reauthenticationRequired =>
        'ต้องเข้าสู่ระบบอีกครั้งก่อนลบบัญชี',
      AccountDeletionFailureCode.ownerChanged ||
      AccountDeletionFailureCode.invalidIdentity =>
        'บัญชีที่ใช้งานเปลี่ยนไป จึงหยุดการลบเพื่อความปลอดภัย',
      AccountDeletionFailureCode.disabled ||
      AccountDeletionFailureCode.unavailable =>
        'ระบบลบบัญชียังไม่พร้อม ข้อมูลยังไม่ถูกลบ',
      _ => 'ลบบัญชีไม่สำเร็จ ข้อมูลในอุปกรณ์ยังไม่ถูกลบ',
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('ลบบัญชีและข้อมูล')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      _completed
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      size: 56,
                      color: _completed
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _completed
                          ? 'ลบบัญชีเรียบร้อย'
                          : 'การลบนี้ย้อนกลับไม่ได้',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _completed
                          ? 'คุณสามารถกลับไปเริ่มเรียนโดยไม่ใช้บัญชีได้'
                          : 'ระบบจะให้บันทึกสำเนาข้อมูลก่อน '
                                'จากนั้นยืนยันตัวตนและลบข้อมูลออนไลน์กับข้อมูลในอุปกรณ์นี้',
                      textAlign: TextAlign.center,
                    ),
                    if (!_completed) ...[
                      const SizedBox(height: 24),
                      TextField(
                        key: const ValueKey<String>(
                          'delete-account-confirmation',
                        ),
                        controller: _controller,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'พิมพ์ “ลบบัญชี” เพื่อยืนยัน',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const ValueKey<String>('delete-account-submit'),
                        onPressed: !_busy && _controller.text == _confirmation
                            ? _submit
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: 'กำลังส่งออกสำเนาและลบบัญชี',
                                ),
                              )
                            : const Icon(Icons.delete_forever_outlined),
                        label: Text(
                          _cloudReceipt == null
                              ? 'ส่งออกสำเนาและลบบัญชี'
                              : 'ลบข้อมูลในอุปกรณ์ต่อ',
                        ),
                      ),
                    ],
                    if (_message case final message?) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          message,
                          key: const ValueKey<String>('delete-account-status'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
