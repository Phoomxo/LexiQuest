import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'study_preferences_panel.dart';

import '../config/m3_theme.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/progress/domain/progress_models.dart';
import '../features/motivation/domain/streak_policy.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/registries/feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'account_deletion_screen.dart';
import 'achievements_screen.dart';
import 'export_center_screen.dart';
import 'thesis_chart_screen.dart';

typedef ProfileProgressLoader = Future<ProgressSnapshot> Function();

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({
    super.key,
    this.loader,
    this.account,
    this.onOpenMenu,
    this.isActive = true,
  });

  final ProfileProgressLoader? loader;
  final AccountUseCases? account;
  final VoidCallback? onOpenMenu;
  final bool isActive;

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  Future<ProgressSnapshot>? _load;
  ProfileProgressLoader? _loader;
  AccountUseCases? _account;
  String? _accountUid;
  ValueListenable<int>? _progressUpdates;

  AccountUseCases? get _currentAccount =>
      widget.account ?? AppDependenciesScope.maybeOf(context)?.account;

  ProfileProgressLoader? get _currentLoader =>
      widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindSources();
  }

  void _bindSources({bool reload = false}) {
    final updates = AppDependenciesScope.maybeOf(context)?.progressUpdates;
    final updatesChanged = !identical(updates, _progressUpdates);
    if (updatesChanged) {
      _progressUpdates?.removeListener(_refresh);
      _progressUpdates = updates;
      updates?.addListener(_refresh);
    }
    final account = _currentAccount;
    final uid = account?.currentSession?.uid;
    final accountChanged = !identical(_account, account) || _accountUid != uid;
    _account = account;
    _accountUid = uid;
    if (reload ||
        updatesChanged ||
        _load == null ||
        _currentLoader != _loader ||
        accountChanged) {
      _load = _loadProgress();
    }
  }

  @override
  void didUpdateWidget(ProfileSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindSources(reload: widget.isActive && !oldWidget.isActive);
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

  @override
  void dispose() {
    _progressUpdates?.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _editName() async {
    final account = _currentAccount;
    final uid = account?.currentSession?.uid;
    if (account == null || uid == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _EditDisplayNameDialog(
        account: account,
        isCurrent: () =>
            mounted &&
            identical(_currentAccount, account) &&
            account.currentSession?.uid == uid,
      ),
    );
    if (mounted) setState(() {});
  }

  void _openPersonalData() => AppNavigator.pushPage<void>(
    context,
    AppPage<void>(name: 'account/data', builder: (_) => const _PersonalData()),
  );

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
          key: ValueKey((_account, _accountUid, _loader)),
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
                    TextButton(
                      onPressed: _openPersonalData,
                      child: const Text('ข้อมูลของฉัน'),
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
            final dependencies = AppDependenciesScope.maybeOf(context);
            final learningDaysVisible =
                (dependencies?.features.isVisible(Feature.mastery) ?? true) &&
                (dependencies?.fieldFeatures.isVisible(FieldFeature.mastery) ??
                    true);
            final collectionVisible =
                (dependencies?.features.isVisible(Feature.achievements) ??
                    true) &&
                (dependencies?.fieldFeatures.isVisible(
                      FieldFeature.achievements,
                    ) ??
                    true);
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
                if (dependencies?.studyPreferences != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.flag_outlined),
                      title: const Text('วิธีเรียนและวันเป้าหมาย'),
                      subtitle: const Text('เลือกสิ่งที่อยากฝึก หรือข้ามได้'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showStudyPreferences(context),
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
                if (learningDaysVisible)
                  _Metric(
                    label: 'เรียนต่อเนื่อง',
                    value:
                        progress.learningDays != null &&
                            progress.learningDays!.status !=
                                StreakFoldStatus.ready
                        ? 'รอตรวจวันเรียน'
                        : '${progress.streakDays} วัน',
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
                  child: Text('XP รวมคะแนนจากคำตอบและภารกิจที่รับแล้ว'),
                ),
                if (collectionVisible)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.emoji_events_outlined),
                      title: const Text('ของสะสม'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => AppNavigator.pushPage<void>(
                        context,
                        AppPage<void>(
                          name: 'rewards/collection',
                          builder: (_) => AchievementsScreen(
                            loader: widget.loader,
                            showCollection: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('ข้อมูลของฉัน'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _openPersonalData,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PersonalData extends StatelessWidget {
  const _PersonalData();

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final deletion = dependencies?.accountDeletion;
    final session = dependencies?.account?.currentSession;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ข้อมูลของฉัน'),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (dependencies?.exports != null &&
                dependencies!.fieldFeatures.isVisible(FieldFeature.export))
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('บันทึกสำเนาข้อมูล'),
                subtitle: const Text('เลือกข้อมูลการเรียนที่ต้องการเก็บ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => AppNavigator.pushPage<void>(
                  context,
                  AppPage<void>(
                    name: 'export/center',
                    builder: (_) => const ExportCenterScreen(),
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('ข้อมูลสำหรับงานวิจัย'),
              subtitle: const Text('ดูตัวอย่างการอ่านกราฟ'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => AppNavigator.pushPage<void>(
                context,
                AppPage<void>(
                  name: 'research/sample-chart',
                  builder: (_) => const ThesisChartScreen(
                    returnLabel: 'กลับไปที่ข้อมูลของฉัน',
                  ),
                ),
              ),
            ),
            if (deletion != null && session != null && !session.isAnonymous)
              ListTile(
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('ลบบัญชีและข้อมูล'),
                subtitle: const Text('อ่านผลกระทบและขั้นตอนการลบ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final current = AppDependenciesScope.maybeOf(context);
                  if (!identical(current?.accountDeletion, deletion) ||
                      current?.account?.currentSession?.uid != session.uid) {
                    return;
                  }
                  AppNavigator.pushPage<void>(
                    context,
                    AppPage<void>(
                      name: 'account/delete',
                      builder: (_) => AccountDeletionScreen(
                        useCases: deletion,
                        expectedFirebaseUid: session.uid,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _EditDisplayNameDialog extends StatefulWidget {
  const _EditDisplayNameDialog({
    required this.account,
    required this.isCurrent,
  });

  final AccountUseCases account;
  final bool Function() isCurrent;

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
    if (!widget.isCurrent()) {
      setState(() => _error = 'บัญชีเปลี่ยนแล้ว กรุณาปิดแล้วเปิดใหม่');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.account.updateDisplayName(_name.text);
      if (mounted) {
        if (widget.isCurrent()) {
          Navigator.pop(context);
        } else {
          setState(() => _error = 'บัญชีเปลี่ยนแล้ว กรุณาปิดแล้วเปิดใหม่');
        }
      }
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
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final valueText = Text(
      value,
      style: Theme.of(context).textTheme.titleLarge,
    );
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: largeText ? valueText : null,
        trailing: largeText ? null : valueText,
      ),
    );
  }
}
