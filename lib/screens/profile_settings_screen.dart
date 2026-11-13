import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';

typedef ProfileProgressLoader = Future<ProgressSnapshot> Function();

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({
    super.key,
    this.loader,
    this.account,
    this.onOpenMenu,
  });

  final ProfileProgressLoader? loader;
  final AccountUseCases? account;
  final VoidCallback? onOpenMenu;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  Future<ProgressSnapshot>? _load;
  ProfileProgressLoader? _loader;
  AccountUseCases? _account;

  ProfileProgressLoader? get _currentLoader =>
      widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _account ??=
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account;
    if (_load == null || _currentLoader != _loader) {
      _load = _loadProgress();
    }
  }

  @override
  void didUpdateWidget(ProfileSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) _load = _loadProgress();
  }

  Future<ProgressSnapshot> _loadProgress() {
    final loader = _loader = _currentLoader;
    final next = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : Future<ProgressSnapshot>.sync(loader);
    next.ignore();
    return next;
  }

  void _refresh() {
    if (!mounted) return;
    final next = _loadProgress();
    setState(() {
      _load = next;
    });
  }

  Future<void> _editName() async {
    final account = _account;
    if (account == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _EditDisplayNameDialog(account: account),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = _account?.currentSession;
    final account = session?.isAnonymous == false ? session : null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'โปรไฟล์'),
        actions: widget.onOpenMenu == null
            ? null
            : [
                IconButton(
                  key: const ValueKey<String>('shell-drawer-button'),
                  tooltip: 'เปิดเมนูเพิ่มเติม',
                  onPressed: widget.onOpenMenu,
                  icon: const Icon(Icons.menu),
                ),
              ],
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: FutureBuilder<ProgressSnapshot>(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: const Text('ไม่สามารถอ่านข้อมูลในเครื่องได้'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังอ่านข้อมูลโปรไฟล์',
                ),
              );
            }
            final progress = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(
                      account?.displayName ??
                          account?.email ??
                          'ผู้เรียนในเครื่อง',
                    ),
                    subtitle: Text(
                      account == null
                          ? 'ข้อมูลอยู่ในเครื่อง'
                          : account.emailVerified
                          ? 'บัญชียืนยันแล้ว'
                          : 'รอยืนยันอีเมล',
                    ),
                  ),
                ),
                if (account != null)
                  TextButton.icon(
                    onPressed: _editName,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('แก้ไขชื่อที่แสดง'),
                  ),
                const SizedBox(height: 8),
                _Metric(label: 'คะแนนประสบการณ์', value: '${progress.totalXp}'),
                _Metric(
                  label: 'เรียนต่อเนื่อง',
                  value: '${progress.streakDays} วัน',
                ),
                _Metric(
                  label: 'ระดับจากคะแนนประสบการณ์',
                  value: '${progress.gameLevel}',
                ),
                _Metric(
                  label: 'คำตอบที่ใช้คำนวณ',
                  value: '${progress.sampleSize}',
                ),
                _Metric(
                  label: 'ความสำเร็จที่ปลดล็อก',
                  value: '${progress.achievementCount}',
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('แสดงเฉพาะคะแนนจากคำตอบที่บันทึกจริง'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EditDisplayNameDialog extends StatefulWidget {
  const _EditDisplayNameDialog({required this.account});

  final AccountUseCases account;

  @override
  State<_EditDisplayNameDialog> createState() => _EditDisplayNameDialogState();
}

class _EditDisplayNameDialogState extends State<_EditDisplayNameDialog> {
  late final _name = TextEditingController(
    text: widget.account.currentSession?.displayName,
  );
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.updateDisplayName(_name.text);
      if (mounted) Navigator.pop(context);
    } on AccountException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.code == AccountFailureCode.invalidDisplayName
              ? 'กรอกชื่อ 1–50 ตัวอักษรในบรรทัดเดียว'
              : 'บันทึกชื่อไม่สำเร็จ กรุณาลองใหม่',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'บันทึกชื่อไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      scrollable: true,
      title: const Text('แก้ไขชื่อที่แสดง'),
      content: TextField(
        controller: _name,
        enabled: !_busy,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'ชื่อที่แสดง',
          errorText: _error,
          errorMaxLines: 3,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'กำลังบันทึก…' : 'บันทึก'),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(value, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}
