import 'package:flutter/material.dart';

import '../features/account/application/account_use_cases.dart';
import '../features/account/application/local_data_deletion.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../features/consent/domain/research_consent.dart';
import '../features/identity/domain/local_owner_repository.dart';
import '../features/offline_content/application/offline_content_manager.dart';
import '../features/preferences/application/display_preferences_controller.dart';
import '../features/research/presentation/research_participation_screen.dart';
import '../navigation/navigation_glossary.dart';
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
  Future<ResearchConsentStatus>? _consentStatus;
  bool _consentDialogOpen = false;
  LocalDataEraser? _localDataEraser;
  LocalOwnerRepository? _localOwners;
  DisplayPreferencesController? _displayPreferences;
  OfflineContentManager? _offlineContent;
  FeatureRegistry? _featureRegistry;
  Listenable? _featureChanges;
  bool _busy = false;
  bool _displayBusy = false;
  bool _erasureConfirming = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _account ??= widget.account ?? dependencies?.account;
    _researchConsent ??=
        widget.researchConsent ?? dependencies?.researchConsent;
    _consentStatus ??= _researchConsent?.load();
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
    if (!identical(oldWidget.researchConsent, widget.researchConsent)) {
      _researchConsent =
          widget.researchConsent ??
          AppDependenciesScope.maybeOf(context)?.researchConsent;
      _consentStatus = _researchConsent?.load();
    }
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
    if (!mounted ||
        eraser == null ||
        owners == null ||
        _busy ||
        _erasureConfirming) {
      return;
    }
    _erasureConfirming = true;
    try {
      // Bind the confirmation to the owner presented, before opening the dialog.
      final owner = await owners.getOrCreateActiveOwner();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ลบข้อมูลในเครื่องทั้งหมดหรือไม่?'),
          content: const Text(
            'ข้อมูลการเรียน คำศัพท์ ความยินยอม ประวัติการใช้ AI และกุญแจ API '
            'ที่บันทึกไว้ในเครื่องของผู้เรียนปัจจุบันจะถูกลบถาวร',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              key: const ValueKey<String>('confirm-local-erasure'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ลบข้อมูลในเครื่อง'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _busy = true);
      final currentOwner = await owners.getOrCreateActiveOwner();
      if (!mounted) return;
      if (currentOwner.id != owner.id) {
        _show('ผู้เรียนเปลี่ยนแล้ว กรุณาเปิดการยืนยันลบข้อมูลอีกครั้ง');
        return;
      }
      await eraser.eraseAll(ownerId: owner.id);
      if (mounted) _show('ลบข้อมูลในเครื่องแล้ว');
    } on Object {
      if (mounted) _show('ลบข้อมูลในเครื่องได้ไม่ครบ กรุณาลองอีกครั้ง');
    } finally {
      _erasureConfirming = false;
      if (mounted) {
        final consent = _researchConsent;
        if (consent != null) _reloadConsent(consent);
        setState(() => _busy = false);
      }
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
    } on Object {
      if (mounted) _show('การบันทึกขัดข้อง กำลังตรวจสอบสถานะความยินยอมล่าสุด');
    } finally {
      if (mounted) {
        _reloadConsent(consent);
        setState(() => _busy = false);
      }
    }
  }

  void _reloadConsent(ResearchConsentUseCases consent) {
    final next = consent.load();
    // Observe early errors until FutureBuilder subscribes on the next frame.
    // Keep the same future so its error still renders the unavailable state.
    next.ignore();
    setState(() {
      _consentStatus = next;
    });
  }

  Future<void> _openResearchConsentDetails(bool accepted) async {
    final consent = _researchConsent;
    if (consent == null || _busy || _consentDialogOpen) return;
    _consentDialogOpen = true;
    try {
      final owner = await consent.owners.getOrCreateActiveOwner();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ความยินยอมใช้ข้อมูลวิจัย'),
          content: SingleChildScrollView(
            child: Text(
              'ใช้ความยินยอมนี้เมื่อส่งออกข้อมูลที่เลือกเป็นชุดข้อมูลวิจัย '
              'การยืนยันไม่ใช่การสมัครเข้าร่วมงานวิจัยแรงจูงใจ '
              'และไม่เริ่มส่งข้อมูลโดยอัตโนมัติ\n\n'
              'การเข้าร่วมงานวิจัยมีขั้นตอนและสิทธิ์ที่ต้องตรวจสอบแยกต่างหาก '
              'คุณเรียนตามปกติได้แม้ไม่ยินยอม\n\n'
              'ถอนความยินยอมได้เพื่อหยุดการส่งออกชุดวิจัยครั้งต่อไป '
              'และหยุดการเก็บและส่งข้อมูลวิจัยที่ผูกกับความยินยอมฉบับนี้ '
              'ของผู้เรียนปัจจุบัน รวมถึงปิดรอบการวัดผลที่เกี่ยวข้อง '
              'ไฟล์ที่เคยส่งออกแล้วจะไม่ถูกลบโดยการถอนนี้\n\n'
              'ฉบับความยินยอม: ${consent.consentVersion}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              key: const ValueKey('confirm-research-export-consent'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                accepted ? 'ยืนยันถอนความยินยอม' : 'ยินยอมสำหรับส่งออก',
              ),
            ),
          ],
        ),
      );
      if (confirmed != true ||
          !mounted ||
          !identical(consent, _researchConsent)) {
        return;
      }
      final currentOwner = await consent.owners.getOrCreateActiveOwner();
      if (!mounted) return;
      if (currentOwner.id != owner.id) {
        _show('ผู้เรียนเปลี่ยนแล้ว กรุณาตรวจสอบความยินยอมอีกครั้ง');
        _reloadConsent(consent);
        return;
      }
      await _changeResearchConsent(!accepted);
    } on Object {
      if (mounted) _show('อ่านข้อมูลความยินยอมไม่ได้ กรุณาลองใหม่');
    } finally {
      _consentDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final session = _account?.currentSession;
    final cloudReady =
        dependencies?.runtimeStatus.firebase == RuntimeAvailability.ready;
    final displayEntry = NavigationGlossary.require('settings/display');
    final systemThemeEntry = NavigationGlossary.require('theme-system');
    final lightThemeEntry = NavigationGlossary.require('theme-light');
    final darkThemeEntry = NavigationGlossary.require('theme-dark');
    final reducedMotionEntry = NavigationGlossary.require(
      'reduced-motion-switch',
    );
    final accountEntry = NavigationGlossary.require('settings/account');
    final offlineContentEntry = NavigationGlossary.require(
      'settings/offline-content',
    );
    final researchConsentEntry = NavigationGlossary.require(
      'settings/research-consent',
    );
    final cloudStatusEntry = NavigationGlossary.require(
      'settings/cloud-status',
    );
    final changePasswordEntry = NavigationGlossary.require(
      'settings/change-password',
    );
    final logoutEntry = NavigationGlossary.require('settings/logout');
    final eraseLocalDataEntry = NavigationGlossary.require('erase-local-data');
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่า')),
      body: ListTileTheme(
        data: ListTileTheme.of(context).copyWith(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          titleTextStyle: Theme.of(context).textTheme.titleMedium,
          subtitleTextStyle: Theme.of(context).textTheme.bodySmall,
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_displayPreferences case final display?)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Tooltip(
                        message: displayEntry.tooltip,
                        child: Semantics(
                          header: true,
                          label: displayEntry.semanticsLabel,
                          child: Row(
                            children: [
                              Icon(displayEntry.icon),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  displayEntry.fullThaiLabel,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.start,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Tooltip(
                            message: systemThemeEntry.tooltip,
                            child: Semantics(
                              button: true,
                              enabled: !_displayBusy,
                              label: systemThemeEntry.semanticsLabel,
                              selected: display.themeMode == ThemeMode.system,
                              onTap: _displayBusy
                                  ? null
                                  : () => _selectTheme(ThemeMode.system),
                              excludeSemantics: true,
                              child: ChoiceChip(
                                key: const ValueKey<String>('theme-system'),
                                selected: display.themeMode == ThemeMode.system,
                                onSelected: _displayBusy
                                    ? null
                                    : (_) => _selectTheme(ThemeMode.system),
                                label: Text(systemThemeEntry.fullThaiLabel),
                                avatar: Icon(systemThemeEntry.icon),
                              ),
                            ),
                          ),
                          Tooltip(
                            message: lightThemeEntry.tooltip,
                            child: Semantics(
                              button: true,
                              enabled: !_displayBusy,
                              label: lightThemeEntry.semanticsLabel,
                              selected: display.themeMode == ThemeMode.light,
                              onTap: _displayBusy
                                  ? null
                                  : () => _selectTheme(ThemeMode.light),
                              excludeSemantics: true,
                              child: ChoiceChip(
                                key: const ValueKey<String>('theme-light'),
                                selected: display.themeMode == ThemeMode.light,
                                onSelected: _displayBusy
                                    ? null
                                    : (_) => _selectTheme(ThemeMode.light),
                                label: Text(lightThemeEntry.fullThaiLabel),
                                avatar: Icon(lightThemeEntry.icon),
                              ),
                            ),
                          ),
                          Tooltip(
                            message: darkThemeEntry.tooltip,
                            child: Semantics(
                              button: true,
                              enabled: !_displayBusy,
                              label: darkThemeEntry.semanticsLabel,
                              selected: display.themeMode == ThemeMode.dark,
                              onTap: _displayBusy
                                  ? null
                                  : () => _selectTheme(ThemeMode.dark),
                              excludeSemantics: true,
                              child: ChoiceChip(
                                key: const ValueKey<String>('theme-dark'),
                                selected: display.themeMode == ThemeMode.dark,
                                onSelected: _displayBusy
                                    ? null
                                    : (_) => _selectTheme(ThemeMode.dark),
                                label: Text(darkThemeEntry.fullThaiLabel),
                                avatar: Icon(darkThemeEntry.icon),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Tooltip(
                        message: reducedMotionEntry.tooltip,
                        child: Semantics(
                          enabled: !_displayBusy,
                          label: reducedMotionEntry.semanticsLabel,
                          hint:
                              'ปิดแอนิเมชันเสริม โดยยังเคารพการตั้งค่าของระบบเสมอ',
                          toggled: display.reducedMotionEnabled,
                          onTap: _displayBusy
                              ? null
                              : () => _setReducedMotion(
                                  !display.reducedMotionEnabled,
                                ),
                          excludeSemantics: true,
                          child: SwitchListTile(
                            key: const ValueKey<String>(
                              'reduced-motion-switch',
                            ),
                            contentPadding: EdgeInsets.zero,
                            secondary: Icon(reducedMotionEntry.icon),
                            title: Text(reducedMotionEntry.fullThaiLabel),
                            subtitle: const Text(
                              'ปิดแอนิเมชันเสริม โดยยังเคารพการตั้งค่าของระบบเสมอ',
                            ),
                            value: display.reducedMotionEnabled,
                            onChanged: _displayBusy ? null : _setReducedMotion,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Tooltip(
              message: accountEntry.tooltip,
              child: Semantics(
                label: accountEntry.semanticsLabel,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      session == null ? accountEntry.icon : Icons.verified_user,
                    ),
                    title: Text(session?.email ?? 'โหมดใช้งานในเครื่อง'),
                    subtitle: Text(
                      session == null
                          ? 'ข้อมูลการเรียนอยู่ในเครื่องและอัปเกรดบัญชีได้ภายหลัง'
                          : session.emailVerified
                          ? 'ยืนยันอีเมลแล้ว'
                          : 'รอยืนยันอีเมล',
                    ),
                  ),
                ),
              ),
            ),
            if (_offlineContent != null &&
                _featureRegistry?.isVisible(Feature.offlineContent) == true)
              Tooltip(
                message: offlineContentEntry.tooltip,
                child: Semantics(
                  button: true,
                  enabled: true,
                  label: offlineContentEntry.semanticsLabel,
                  hint: 'ดาวน์โหลด ตรวจสอบ ซ่อมแซม และลบไฟล์ในเครื่อง',
                  onTap: _openOfflineContent,
                  excludeSemantics: true,
                  child: Card(
                    child: ListTile(
                      key: const ValueKey<String>('settings/offline-content'),
                      minTileHeight: 48,
                      leading: Icon(offlineContentEntry.icon),
                      title: Text(offlineContentEntry.fullThaiLabel),
                      subtitle: const Text(
                        'ดาวน์โหลด ตรวจสอบ ซ่อมแซม และลบไฟล์ในเครื่อง',
                      ),
                      onTap: _openOfflineContent,
                    ),
                  ),
                ),
              ),
            if (_researchConsent case final consent?)
              FutureBuilder<ResearchConsentStatus>(
                future: _consentStatus,
                builder: (context, snapshot) {
                  final failed =
                      snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasError;
                  final ready =
                      snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData &&
                      !snapshot.hasError;
                  final accepted = ready && snapshot.data!.accepted;
                  final description = failed
                      ? 'อ่านสถานะความยินยอมไม่ได้ กรุณาลองใหม่'
                      : !ready
                      ? 'กำลังอ่านสถานะความยินยอม'
                      : accepted
                      ? 'ยินยอมฉบับ ${snapshot.data!.version} สำหรับส่งออกชุดวิจัย — ถอนความยินยอมได้'
                      : 'ยังไม่ยินยอมส่งออกชุดวิจัย — เรียนตามปกติได้';
                  final enabled = ready && !_busy;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Tooltip(
                      message: researchConsentEntry.tooltip,
                      child: Semantics(
                        button: true,
                        enabled: enabled || failed,
                        label: researchConsentEntry.semanticsLabel,
                        value: description,
                        hint: failed
                            ? 'ลองอ่านสถานะอีกครั้ง'
                            : 'อ่านรายละเอียดก่อนตัดสินใจเกี่ยวกับชุดข้อมูลวิจัย',
                        onTap: failed
                            ? () => _reloadConsent(consent)
                            : enabled
                            ? () => _openResearchConsentDetails(accepted)
                            : null,
                        excludeSemantics: true,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    accepted
                                        ? researchConsentEntry.icon
                                        : Icons.assignment_outlined,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      researchConsentEntry.fullThaiLabel,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                description,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton(
                                  key: ValueKey(
                                    failed
                                        ? 'research-consent-retry'
                                        : 'research-consent-details',
                                  ),
                                  onPressed: failed
                                      ? () => _reloadConsent(consent)
                                      : enabled
                                      ? () => _openResearchConsentDetails(
                                          accepted,
                                        )
                                      : null,
                                  child: Text(
                                    failed ? 'ลองใหม่' : 'รายละเอียด',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (AppDependenciesScope.maybeOf(context)?.adventureResearch
                case final research?)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  key: const ValueKey('settings/research-participation'),
                  minTileHeight: 64,
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('การเข้าร่วมวิจัยแรงจูงใจ'),
                  subtitle: const Text(
                    'นำเข้าสิทธิ์ที่ลงนามแล้ว ตรวจสถานะ หรือถอนการเข้าร่วม',
                  ),
                  onTap: () async {
                    final identities = AppDependenciesScope.maybeOf(
                      context,
                    )?.activeOwnerIdentities;
                    if (identities == null) return;
                    final ownerId = await identities
                        .requireSingleActiveOwnerId();
                    if (!context.mounted) return;
                    await AppNavigator.pushPage<void>(
                      context,
                      AppPage<void>(
                        name: 'settings/research-participation',
                        builder: (_) => ResearchParticipationScreen(
                          runtime: research,
                          ownerId: ownerId,
                        ),
                      ),
                    );
                  },
                ),
              ),
            Tooltip(
              message: cloudStatusEntry.tooltip,
              child: Semantics(
                label: cloudStatusEntry.semanticsLabel,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      cloudReady
                          ? cloudStatusEntry.icon
                          : Icons.cloud_off_outlined,
                    ),
                    title: Text(cloudStatusEntry.fullThaiLabel),
                    subtitle: Text(
                      cloudReady
                          ? 'พร้อมใช้งาน'
                          : 'ไม่พร้อมใช้งาน · การเรียนออฟไลน์ยังทำงานได้',
                    ),
                  ),
                ),
              ),
            ),
            if (session != null && !session.isAnonymous) ...[
              Tooltip(
                message: changePasswordEntry.tooltip,
                child: Semantics(
                  button: true,
                  enabled: !_busy,
                  label: changePasswordEntry.semanticsLabel,
                  onTap: _busy ? null : _changePassword,
                  excludeSemantics: true,
                  child: Card(
                    child: ListTile(
                      minTileHeight: 48,
                      leading: Icon(changePasswordEntry.icon),
                      title: Text(changePasswordEntry.fullThaiLabel),
                      onTap: _busy ? null : _changePassword,
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: logoutEntry.tooltip,
                child: Semantics(
                  button: true,
                  enabled: !_busy,
                  label: logoutEntry.semanticsLabel,
                  hint: 'สร้างพื้นที่ใช้งานในเครื่องใหม่โดยไม่ลบข้อมูลบัญชี',
                  onTap: _busy ? null : _logout,
                  excludeSemantics: true,
                  child: Card(
                    child: ListTile(
                      minTileHeight: 48,
                      leading: Icon(logoutEntry.icon),
                      title: Text(logoutEntry.fullThaiLabel),
                      subtitle: const Text(
                        'สร้างพื้นที่ใช้งานในเครื่องใหม่โดยไม่ลบข้อมูลบัญชี',
                      ),
                      onTap: _busy ? null : _logout,
                    ),
                  ),
                ),
              ),
            ],
            if (_localDataEraser != null && _localOwners != null)
              Tooltip(
                message: eraseLocalDataEntry.tooltip,
                child: Semantics(
                  button: true,
                  enabled: !_busy,
                  label: eraseLocalDataEntry.semanticsLabel,
                  hint: eraseLocalDataEntry.tooltip,
                  onTap: _busy ? null : _eraseLocalData,
                  excludeSemantics: true,
                  child: Card(
                    child: ListTile(
                      key: const ValueKey<String>('erase-local-data'),
                      minTileHeight: 48,
                      leading: Icon(eraseLocalDataEntry.icon),
                      title: Text(eraseLocalDataEntry.fullThaiLabel),
                      subtitle: Text(eraseLocalDataEntry.tooltip),
                      onTap: _busy ? null : _eraseLocalData,
                    ),
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
}
