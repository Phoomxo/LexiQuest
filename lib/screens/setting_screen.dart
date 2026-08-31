import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/application/local_data_deletion.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../features/identity/domain/local_owner_repository.dart';
import '../features/offline_content/application/offline_content_manager.dart';
import '../features/preferences/application/display_preferences_controller.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/app_runtime_status.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import 'offline_content_manager_screen.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({
    super.key,
    this.account,
    this.researchConsent,
    this.localDataEraser,
    this.localOwners,
    this.displayPreferences,
  });

  final AccountUseCases? account;
  final ResearchConsentUseCases? researchConsent;
  final LocalDataEraser? localDataEraser;
  final LocalOwnerRepository? localOwners;
  final DisplayPreferencesController? displayPreferences;

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  AccountUseCases? _account;
  ResearchConsentUseCases? _researchConsent;
  LocalDataEraser? _localDataEraser;
  LocalOwnerRepository? _localOwners;
  DisplayPreferencesController? _displayPreferences;
  OfflineContentManager? _offlineContent;
  FeatureRegistry? _featureRegistry;
  Listenable? _featureChanges;
  bool _busy = false;
  bool _displayBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _account ??= widget.account ?? dependencies?.account;
    _researchConsent ??=
        widget.researchConsent ?? dependencies?.researchConsent;
    _localDataEraser ??=
        widget.localDataEraser ?? dependencies?.localDataEraser;
    _localOwners ??= widget.localOwners ?? dependencies?.localOwners;
    _offlineContent ??= dependencies?.offlineContent;
    _bindFeatureRegistry(dependencies?.features);
    _bindDisplayPreferences(
      widget.displayPreferences ?? dependencies?.displayPreferences,
    );
  }

  @override
  void didUpdateWidget(covariant SettingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.displayPreferences, widget.displayPreferences)) {
      final dependencies = AppDependenciesScope.maybeOf(context);
      _bindDisplayPreferences(
        widget.displayPreferences ?? dependencies?.displayPreferences,
      );
    }
  }

  void _bindDisplayPreferences(DisplayPreferencesController? controller) {
    if (identical(_displayPreferences, controller)) return;
    _displayPreferences?.removeListener(_onDisplayPreferencesChanged);
    _displayPreferences = controller;
    controller?.addListener(_onDisplayPreferencesChanged);
  }

  void _onDisplayPreferencesChanged() {
    if (mounted) setState(() {});
  }

  void _bindFeatureRegistry(FeatureRegistry? registry) {
    if (identical(_featureRegistry, registry)) return;
    _featureChanges?.removeListener(_onFeatureRegistryChanged);
    _featureRegistry = registry;
    final changes = registry is Listenable ? registry as Listenable : null;
    _featureChanges = changes;
    changes?.addListener(_onFeatureRegistryChanged);
  }

  void _onFeatureRegistryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _displayPreferences?.removeListener(_onDisplayPreferencesChanged);
    _featureChanges?.removeListener(_onFeatureRegistryChanged);
    super.dispose();
  }

  Future<void> _openOfflineContent() async {
    final manager = _offlineContent;
    final registry = _featureRegistry;
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (manager == null ||
        registry == null ||
        !registry.isEnabled(Feature.offlineContent) ||
        dependencies == null ||
        !identical(dependencies.offlineContent, manager) ||
        !dependencies.hasComposedDependencyFor(Feature.offlineContent)) {
      return;
    }
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'settings/offline-content',
        builder: (_) => ProductionFeatureGate(
          feature: Feature.offlineContent,
          registry: registry,
          builder: (_) => OfflineContentManagerScreen(
            manager: manager,
            canInvoke: () =>
                registry.isEnabled(Feature.offlineContent) &&
                identical(dependencies.offlineContent, manager),
          ),
        ),
      ),
    );
  }

  Future<void> _selectTheme(ThemeMode mode) async {
    final display = _displayPreferences;
    if (display == null || _displayBusy) return;
    setState(() => _displayBusy = true);
    try {
      await display.selectThemeMode(mode);
    } on Object {
      if (mounted) _show('บันทึกธีมไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _displayBusy = false);
    }
  }

  Future<void> _setReducedMotion(bool enabled) async {
    final display = _displayPreferences;
    if (display == null || _displayBusy) return;
    setState(() => _displayBusy = true);
    try {
      await display.setReducedMotion(enabled);
    } on Object {
      if (mounted) _show('บันทึกการลดการเคลื่อนไหวไม่สำเร็จ');
    } finally {
      if (mounted) setState(() => _displayBusy = false);
    }
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

  Future<void> _eraseLocalData() async {
    final eraser = _localDataEraser;
    final owners = _localOwners;
    if (eraser == null || owners == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erase all local data?'),
        content: const Text(
          'This permanently removes local learning data, vocabulary, consent, '
          'AI usage, and the active owner\'s saved provider API key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey<String>('confirm-local-erasure'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Erase local data'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final owner = await owners.getOrCreateActiveOwner();
      await eraser.eraseAll(ownerId: owner.id);
      if (mounted) _show('Local data erased.');
    } on Object {
      if (mounted) _show('Local data could not be fully erased.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeResearchConsent(bool accept) async {
    final consent = _researchConsent;
    if (consent == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (accept) {
        await consent.accept();
      } else {
        await consent.withdraw();
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          if (_displayPreferences case final display?)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'การแสดงผล',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      children: [
                        ChoiceChip(
                          key: const ValueKey<String>('theme-system'),
                          selected: display.themeMode == ThemeMode.system,
                          onSelected: _displayBusy
                              ? null
                              : (_) => _selectTheme(ThemeMode.system),
                          label: const Text('ระบบ'),
                          avatar: const Icon(Icons.settings_suggest_outlined),
                        ),
                        ChoiceChip(
                          key: const ValueKey<String>('theme-light'),
                          selected: display.themeMode == ThemeMode.light,
                          onSelected: _displayBusy
                              ? null
                              : (_) => _selectTheme(ThemeMode.light),
                          label: const Text('สว่าง'),
                          avatar: const Icon(Icons.light_mode_outlined),
                        ),
                        ChoiceChip(
                          key: const ValueKey<String>('theme-dark'),
                          selected: display.themeMode == ThemeMode.dark,
                          onSelected: _displayBusy
                              ? null
                              : (_) => _selectTheme(ThemeMode.dark),
                          label: const Text('มืด'),
                          avatar: const Icon(Icons.dark_mode_outlined),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      key: const ValueKey<String>('reduced-motion-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('ลดการเคลื่อนไหว'),
                      subtitle: const Text(
                        'ปิดแอนิเมชันเสริม โดยยังเคารพการตั้งค่าของระบบเสมอ',
                      ),
                      value: display.reducedMotionEnabled,
                      onChanged: _displayBusy ? null : _setReducedMotion,
                    ),
                  ],
                ),
              ),
            ),
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
          if (_offlineContent != null &&
              _featureRegistry?.isVisible(Feature.offlineContent) == true)
            ListTile(
              key: const ValueKey<String>('settings/offline-content'),
              minTileHeight: 48,
              leading: const Icon(Icons.offline_pin_outlined),
              title: const Text('เนื้อหาออฟไลน์'),
              subtitle: const Text(
                'ดาวน์โหลด ตรวจสอบ ซ่อมแซม และลบไฟล์ในเครื่อง',
              ),
              onTap: _openOfflineContent,
            ),
          if (_researchConsent case final consent?)
            FutureBuilder(
              future: consent.load(),
              builder: (context, snapshot) {
                final accepted = snapshot.data?.accepted ?? false;
                return Card(
                  child: ListTile(
                    minTileHeight: 64,
                    leading: Icon(
                      accepted
                          ? Icons.fact_check_outlined
                          : Icons.assignment_outlined,
                    ),
                    title: const Text('ความยินยอมงานวิจัย'),
                    subtitle: Text(
                      accepted
                          ? 'ยินยอมฉบับ ${ResearchConsentUseCases.currentVersion} — ถอนความยินยอมได้'
                          : 'ยังไม่ยินยอม ข้อมูลจะไม่ถูกส่งออกเป็นชุดวิจัย',
                    ),
                    trailing: TextButton(
                      onPressed:
                          snapshot.connectionState == ConnectionState.waiting ||
                              _busy
                          ? null
                          : () => _changeResearchConsent(!accepted),
                      child: Text(accepted ? 'ถอน' : 'ยินยอม'),
                    ),
                  ),
                );
              },
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
          if (_localDataEraser != null && _localOwners != null)
            ListTile(
              key: const ValueKey<String>('erase-local-data'),
              minTileHeight: 48,
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Erase all local data'),
              subtitle: const Text(
                'Includes vocabulary, learning history, consent, and saved AI key.',
              ),
              onTap: _busy ? null : _eraseLocalData,
            ),
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
