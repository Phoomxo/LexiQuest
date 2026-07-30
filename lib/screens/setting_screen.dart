import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/app_runtime_status.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key, this.account});

  final AccountUseCases? account;

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  AccountUseCases? _account;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _account ??=
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account;
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('เปลี่ยนรหัสผ่าน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'รหัสผ่านใหม่อย่างน้อย 8 ตัวอักษร',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (submitted != true || !mounted) {
      current.dispose();
      next.dispose();
      return;
    }
    final currentPassword = current.text;
    final newPassword = next.text;
    current.dispose();
    next.dispose();
    final account = _account;
    if (account == null) return;
    setState(() => _busy = true);
    try {
      await account.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (mounted) _show('เปลี่ยนรหัสผ่านแล้ว');
    } on AccountException catch (error) {
      if (mounted) {
        _show(
          error.code == AccountFailureCode.requiresRecentLogin
              ? 'กรุณาเข้าสู่ระบบใหม่ก่อนเปลี่ยนรหัสผ่าน'
              : 'เปลี่ยนรหัสผ่านไม่สำเร็จ',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final account = _account;
    if (account == null || _busy) return;
    setState(() => _busy = true);
    try {
      await account.signOutToLocalGuest();
      if (!mounted) return;
      await AppNavigator.resetTo<void>(context, AppRoute.login);
    } on AccountException {
      if (mounted) _show('ออกจากระบบไม่สำเร็จ ข้อมูลในเครื่องยังไม่ถูกลบ');
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
    final dependencies = AppDependenciesScope.maybeOf(context);
    final session = _account?.currentSession;
    final cloudReady =
        dependencies?.runtimeStatus.firebase == RuntimeAvailability.ready;
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่า')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                session == null ? Icons.person_outline : Icons.verified_user,
              ),
              title: Text(session?.email ?? 'โหมด Guest'),
              subtitle: Text(
                session == null
                    ? 'ข้อมูลการเรียนอยู่ในเครื่องและอัปเกรดบัญชีได้ภายหลัง'
                    : session.emailVerified
                    ? 'ยืนยันอีเมลแล้ว'
                    : 'รอยืนยันอีเมล',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(
                cloudReady
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
              ),
              title: Text(cloudReady ? 'Cloud พร้อมใช้งาน' : 'Cloud ไม่พร้อม'),
              subtitle: const Text('การเรียนออฟไลน์ยังทำงานได้ตามปกติ'),
            ),
          ),
          if (session != null && !session.isAnonymous) ...[
            ListTile(
              minTileHeight: 48,
              leading: const Icon(Icons.password_outlined),
              title: const Text('เปลี่ยนรหัสผ่าน'),
              onTap: _busy ? null : _changePassword,
            ),
            ListTile(
              minTileHeight: 48,
              leading: const Icon(Icons.logout),
              title: const Text('ออกจากระบบ'),
              subtitle: const Text(
                'สร้างพื้นที่ Guest ใหม่โดยไม่ลบข้อมูลบัญชี',
              ),
              onTap: _busy ? null : _logout,
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
