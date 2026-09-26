import 'dart:async';
import 'dart:convert';
import '../features/ai_tutor/presentation/menu_action_binding.dart';
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
import 'password_change_dialog.dart';

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

class _SettingScreenState extends State<SettingScreen>
    with WidgetsBindingObserver {
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
  int _logoutGeneration = 0;
  AccountUseCases? _logoutAccount;
  Object? _logoutSessionIdentity;
  bool _logoutVisible = false;

  void _syncLogout() {
    final account =
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account;
    final session = account?.currentSession;
    final identity = session?.sessionIdentity ?? session;
    final visible = _displayActive;
    if (!identical(account, _logoutAccount) ||
        identity != _logoutSessionIdentity ||
        visible != _logoutVisible) {
      _logoutGeneration++;
    }
    _logoutAccount = account;
    _logoutSessionIdentity = identity;
    _logoutVisible = visible;
  }

  bool _logoutCurrent(int generation, AccountUseCases account) =>
      generation == _logoutGeneration &&
      _displayActive &&
      identical(
        account,
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account,
      );
  AccountUseCases? _passwordAccount;
  StreamSubscription<AccountSession?>? _passwordSessionSubscription;
  String? _passwordUid;
  Object? _passwordSessionIdentity;
  int _passwordGeneration = 0;
  bool _passwordVisible = false;
  DialogRoute<void>? _passwordRoute;
  bool get _passwordActive =>
      mounted &&
      !_displayExited &&
      _displayForeground &&
      TickerMode.valuesOf(context).enabled &&
      (_passwordRoute != null
          ? _passwordRoute!.isCurrent &&
                ModalRoute.of(context)?.isActive != false
          : ModalRoute.of(context)?.isCurrent != false);

  void _retirePassword() {
    _passwordGeneration++;
    final route = _passwordRoute;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  void _syncPassword() {
    final account =
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account;
    final session = account?.currentSession;
    final uid = session?.uid;
    final identity = session?.sessionIdentity ?? session;
    final visible = _passwordActive;
    if (!identical(account, _passwordAccount) ||
        uid != _passwordUid ||
        identity != _passwordSessionIdentity ||
        visible != _passwordVisible) {
      _retirePassword();
    }
    if (!identical(account, _passwordAccount)) {
      unawaited(_passwordSessionSubscription?.cancel());
      var initial = true;
      _passwordSessionSubscription = account?.sessionChanges.listen(
        (session) {
          if (!mounted || !identical(account, _passwordAccount)) return;
          if (!initial || session?.uid != _passwordUid) {
            setState(() {
              _retirePassword();
              // A null event can be our own provider acknowledgement. The
              // next build still retires the displayed account's controls.
              if (session != null || !_busy) _logoutGeneration++;
            });
          }
          initial = false;
        },
        onError: (Object _, StackTrace _) {
          if (mounted && identical(account, _passwordAccount)) {
            setState(() {
              _retirePassword();
              _logoutGeneration++;
            });
          }
        },
      );
    }
    _account = account;
    _passwordAccount = account;
    _passwordUid = uid;
    _passwordSessionIdentity = identity;
    _passwordVisible = visible;
  }

  bool _passwordCurrent(int generation, AccountUseCases account, String uid) =>
      generation == _passwordGeneration &&
      _passwordActive &&
      identical(account, _passwordAccount) &&
      identical(
        account,
        widget.account ?? AppDependenciesScope.maybeOf(context)?.account,
      ) &&
      (account.currentSession?.sessionIdentity ?? account.currentSession) ==
          _passwordSessionIdentity &&
      account.currentSession?.uid == uid &&
      account.currentSession?.isAnonymous == false;

  bool _displayBusy = false;
  int _displayGeneration = 0;
  bool _displayForeground = true;
  bool _displayVisible = false;
  bool _displayExited = false;
  String? _displayOwner;
  bool _displayReading = false;
  bool get _displayActive =>
      mounted &&
      !_displayExited &&
      _displayForeground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;
  bool _displayCurrent(int generation, DisplayPreferencesController display) =>
      generation == _displayGeneration &&
      identical(display, _displayPreferences) &&
      _displayActive;
  void _retireDisplay() {
    _displayGeneration++;
    _displayBusy = false;
  }

  void _syncDisplayVisibility() {
    final visible = _displayActive;
    if (visible != _displayVisible) _retireDisplay();
    _displayVisible = visible;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _displayForeground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _displayForeground = state == AppLifecycleState.resumed;
      _retireDisplay();
      _retirePassword();
      _logoutGeneration++;
      _syncDisplayVisibility();
    });
  }

  bool _erasureConfirming = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDisplayVisibility();
    _syncPassword();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _account = widget.account ?? dependencies?.account;
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
    _syncPassword();
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
    _retireDisplay();
    _displayPreferences = controller;
    _displayOwner = controller?.ownerId;
    _displayReading = controller?.isReading ?? false;
    controller?.addListener(_onDisplayPreferencesChanged);
  }

  void _onDisplayPreferencesChanged() {
    if (mounted) {
      setState(() {
        if ((_displayPreferences?.isReading ?? false) && !_displayReading) {
          _retireDisplay();
        }
        _displayReading = _displayPreferences?.isReading ?? false;
        if (_displayOwner != _displayPreferences?.ownerId) {
          _displayOwner = _displayPreferences?.ownerId;
          _retireDisplay();
        }
      });
    }
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
    _displayExited = true;
    unawaited(_passwordSessionSubscription?.cancel());
    _retirePassword();
    _retireDisplay();
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _changeDisplay(
    int generation,
    DisplayPreferencesController display,
    Future<void> Function(bool Function()) save,
  ) async {
    if (!_displayCurrent(generation, display) ||
        _displayBusy ||
        !display.canEdit) {
      return;
    }
    setState(() => _displayBusy = true);
    bool allowed() => _displayCurrent(generation, display);
    try {
      await save(allowed);
    } on Object {
      if (allowed()) {
        _show('ยังยืนยันผลบันทึกไม่ได้ โปรดอ่านค่าที่บันทึกก่อนเลือกอีกครั้ง');
      }
    } finally {
      if (allowed()) {
        setState(() {
          _displayBusy = false;
          _displayGeneration++;
        });
      }
    }
  }

  Future<void> _readDisplay(
    int generation,
    DisplayPreferencesController display,
  ) async {
    if (!_displayCurrent(generation, display) ||
        _displayBusy ||
        display.isReading) {
      return;
    }
    setState(() => _displayBusy = true);
    try {
      await display.initialize();
    } on Object {
      if (_displayCurrent(generation, display)) {
        _show('อ่านค่าการแสดงผลไม่ได้ ลองอ่านอีกครั้ง');
      }
    } finally {
      if (_displayCurrent(generation, display)) {
        setState(() {
          _displayBusy = false;
          _displayGeneration++;
        });
      }
    }
  }

  Future<void> _changePassword(
    int generation,
    AccountUseCases account,
    String uid,
  ) async {
    if (_busy ||
        _passwordRoute != null ||
        !_passwordCurrent(generation, account, uid)) {
      return;
    }
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PasswordChangeDialog(
        account: account,
        isCurrent: () => _passwordCurrent(generation, account, uid),
      ),
    );
    _passwordRoute = route;
    try {
      await Navigator.of(context).push(route);
    } finally {
      if (identical(_passwordRoute, route)) {
        _passwordRoute = null;
        _passwordGeneration++;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _logout(
    int generation,
    AccountUseCases account,
    Object identity,
  ) async {
    if (_busy ||
        !_logoutCurrent(generation, account) ||
        (account.currentSession?.sessionIdentity ?? account.currentSession) !=
            identity) {
      return;
    }
    setState(() => _busy = true);
    try {
      await account.signOutToLocalGuest(
        isCurrent: () =>
            _logoutCurrent(generation, account) &&
            (account.currentSession?.sessionIdentity ??
                    account.currentSession) ==
                identity,
      );
      if (!mounted || !_logoutCurrent(generation, account)) return;
      await AppNavigator.resetTo<void>(context, AppRoute.login);
    } on Object {
      if (_logoutCurrent(generation, account)) {
        _show(
          'ยังยืนยันผลการออกจากระบบไม่ได้ ข้อมูลในเครื่องไม่ได้ถูกลบ ตรวจสอบบัญชีที่แสดงก่อนเลือกออกจากระบบอีกครั้ง',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _logoutGeneration++;
        });
      }
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
    final generation = _displayGeneration;
    final displayReady =
        !_displayBusy &&
        _displayActive &&
        (_displayPreferences?.canEdit ?? false);
    final dependencies = AppDependenciesScope.maybeOf(context);
    _syncPassword();
    _syncLogout();
    final logoutAccount = _logoutAccount;
    final logoutIdentity = _logoutSessionIdentity;
    final logoutGeneration = _logoutGeneration;
    final logoutReady =
        !_busy &&
        _displayActive &&
        logoutAccount != null &&
        logoutIdentity != null;
    void logout() {
      if (logoutAccount != null && logoutIdentity != null) {
        unawaited(_logout(logoutGeneration, logoutAccount, logoutIdentity));
      }
    }

    final passwordAccount = _passwordAccount;
    final passwordSession = passwordAccount?.currentSession;
    final passwordGeneration = _passwordGeneration;
    final passwordReady =
        !_busy &&
        _passwordRoute == null &&
        _passwordActive &&
        passwordSession != null &&
        !passwordSession.isAnonymous;
    void openPassword() {
      if (passwordAccount != null && passwordSession != null) {
        unawaited(
          _changePassword(
            passwordGeneration,
            passwordAccount,
            passwordSession.uid,
          ),
        );
      }
    }

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
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _displayExited = true;
          _retirePassword();
          _retireDisplay();
        }
      },
      child: Scaffold(
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
          child: MenuActionListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_displayPreferences case final display?)
                if (!display.canEdit)
                  ListTile(
                    title: Text(
                      display.isReading
                          ? 'กำลังอ่านค่าการแสดงผล'
                          : 'อ่านค่าที่บันทึกก่อนเลือกอีกครั้ง',
                    ),
                    trailing: TextButton(
                      key: const ValueKey('display-retry'),
                      onPressed: display.isReading || _displayBusy
                          ? null
                          : () => _readDisplay(generation, display),
                      child: const Text('อ่านค่าอีกครั้ง'),
                    ),
                  ),
              if (_displayPreferences case final display?)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MenuActionBinding(
                          id: displayEntry.id,
                          ownerId: display.ownerId,
                          label: displayEntry.fullThaiLabel,
                          onInvoke: null,
                          readValue: display.ownerId == null
                              ? null
                              : 'ธีม ${display.themeMode.name} · ลดการเคลื่อนไหว ${display.reducedMotionEnabled}',
                          child: Tooltip(
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
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                ],
                              ),
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
                              child: MenuActionBinding(
                                id: systemThemeEntry.id,
                                ownerId: display.ownerId,
                                label: systemThemeEntry.fullThaiLabel,
                                onInvoke: !displayReady
                                    ? null
                                    : () => _changeDisplay(
                                        generation,
                                        display,
                                        (allowed) => display.selectThemeMode(
                                          ThemeMode.system,
                                          mutationAllowed: allowed,
                                        ),
                                      ),
                                child: Semantics(
                                  button: true,
                                  enabled: displayReady,
                                  label: systemThemeEntry.semanticsLabel,
                                  selected:
                                      display.themeMode == ThemeMode.system,
                                  onTap: !displayReady
                                      ? null
                                      : () => _changeDisplay(
                                          generation,
                                          display,
                                          (allowed) => display.selectThemeMode(
                                            ThemeMode.system,
                                            mutationAllowed: allowed,
                                          ),
                                        ),
                                  excludeSemantics: true,
                                  child: ChoiceChip(
                                    key: const ValueKey<String>('theme-system'),
                                    selected:
                                        display.themeMode == ThemeMode.system,
                                    onSelected: !displayReady
                                        ? null
                                        : (_) => _changeDisplay(
                                            generation,
                                            display,
                                            (allowed) =>
                                                display.selectThemeMode(
                                                  ThemeMode.system,
                                                  mutationAllowed: allowed,
                                                ),
                                          ),
                                    label: Text(systemThemeEntry.fullThaiLabel),
                                    avatar: Icon(systemThemeEntry.icon),
                                  ),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: lightThemeEntry.tooltip,
                              child: MenuActionBinding(
                                id: lightThemeEntry.id,
                                ownerId: display.ownerId,
                                label: lightThemeEntry.fullThaiLabel,
                                onInvoke: !displayReady
                                    ? null
                                    : () => _changeDisplay(
                                        generation,
                                        display,
                                        (allowed) => display.selectThemeMode(
                                          ThemeMode.light,
                                          mutationAllowed: allowed,
                                        ),
                                      ),
                                child: Semantics(
                                  button: true,
                                  enabled: displayReady,
                                  label: lightThemeEntry.semanticsLabel,
                                  selected:
                                      display.themeMode == ThemeMode.light,
                                  onTap: !displayReady
                                      ? null
                                      : () => _changeDisplay(
                                          generation,
                                          display,
                                          (allowed) => display.selectThemeMode(
                                            ThemeMode.light,
                                            mutationAllowed: allowed,
                                          ),
                                        ),
                                  excludeSemantics: true,
                                  child: ChoiceChip(
                                    key: const ValueKey<String>('theme-light'),
                                    selected:
                                        display.themeMode == ThemeMode.light,
                                    onSelected: !displayReady
                                        ? null
                                        : (_) => _changeDisplay(
                                            generation,
                                            display,
                                            (allowed) =>
                                                display.selectThemeMode(
                                                  ThemeMode.light,
                                                  mutationAllowed: allowed,
                                                ),
                                          ),
                                    label: Text(lightThemeEntry.fullThaiLabel),
                                    avatar: Icon(lightThemeEntry.icon),
                                  ),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: darkThemeEntry.tooltip,
                              child: MenuActionBinding(
                                id: darkThemeEntry.id,
                                ownerId: display.ownerId,
                                label: darkThemeEntry.fullThaiLabel,
                                onInvoke: !displayReady
                                    ? null
                                    : () => _changeDisplay(
                                        generation,
                                        display,
                                        (allowed) => display.selectThemeMode(
                                          ThemeMode.dark,
                                          mutationAllowed: allowed,
                                        ),
                                      ),
                                child: Semantics(
                                  button: true,
                                  enabled: displayReady,
                                  label: darkThemeEntry.semanticsLabel,
                                  selected: display.themeMode == ThemeMode.dark,
                                  onTap: !displayReady
                                      ? null
                                      : () => _changeDisplay(
                                          generation,
                                          display,
                                          (allowed) => display.selectThemeMode(
                                            ThemeMode.dark,
                                            mutationAllowed: allowed,
                                          ),
                                        ),
                                  excludeSemantics: true,
                                  child: ChoiceChip(
                                    key: const ValueKey<String>('theme-dark'),
                                    selected:
                                        display.themeMode == ThemeMode.dark,
                                    onSelected: !displayReady
                                        ? null
                                        : (_) => _changeDisplay(
                                            generation,
                                            display,
                                            (allowed) =>
                                                display.selectThemeMode(
                                                  ThemeMode.dark,
                                                  mutationAllowed: allowed,
                                                ),
                                          ),
                                    label: Text(darkThemeEntry.fullThaiLabel),
                                    avatar: Icon(darkThemeEntry.icon),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Tooltip(
                          message: reducedMotionEntry.tooltip,
                          child: MenuActionBinding(
                            id: reducedMotionEntry.id,
                            ownerId: display.ownerId,
                            label: reducedMotionEntry.fullThaiLabel,
                            onInvoke: !displayReady
                                ? null
                                : () => _changeDisplay(
                                    generation,
                                    display,
                                    (allowed) => display.setReducedMotion(
                                      !display.reducedMotionEnabled,
                                      mutationAllowed: allowed,
                                    ),
                                  ),
                            child: Semantics(
                              enabled: displayReady,
                              label: reducedMotionEntry.semanticsLabel,
                              hint:
                                  'ปิดแอนิเมชันเสริม โดยยังเคารพการตั้งค่าของระบบเสมอ',
                              toggled: display.reducedMotionEnabled,
                              onTap: !displayReady
                                  ? null
                                  : () => _changeDisplay(
                                      generation,
                                      display,
                                      (allowed) => display.setReducedMotion(
                                        !display.reducedMotionEnabled,
                                        mutationAllowed: allowed,
                                      ),
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
                                onChanged: !displayReady
                                    ? null
                                    : (enabled) => _changeDisplay(
                                        generation,
                                        display,
                                        (allowed) => display.setReducedMotion(
                                          enabled,
                                          mutationAllowed: allowed,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              MenuActionBinding(
                id: accountEntry.id,
                label: accountEntry.fullThaiLabel,
                onInvoke: null,
                readValue: session == null
                    ? 'ข้อมูลในเครื่อง'
                    : session.emailVerified
                    ? 'ยืนยันอีเมลแล้ว'
                    : 'รอยืนยันอีเมล',
                child: Tooltip(
                  message: accountEntry.tooltip,
                  child: Semantics(
                    label: accountEntry.semanticsLabel,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(
                          session == null
                              ? accountEntry.icon
                              : Icons.verified_user,
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
              ),
              if (_offlineContent != null &&
                  _featureRegistry?.isVisible(Feature.offlineContent) == true)
                Tooltip(
                  message: offlineContentEntry.tooltip,
                  child: MenuActionBinding(
                    id: offlineContentEntry.id,
                    label: offlineContentEntry.fullThaiLabel,
                    onInvoke: _openOfflineContent,
                    child: Semantics(
                      button: true,
                      enabled: true,
                      label: offlineContentEntry.semanticsLabel,
                      hint: 'ดาวน์โหลด ตรวจสอบ ซ่อมแซม และลบไฟล์ในเครื่อง',
                      onTap: _openOfflineContent,
                      excludeSemantics: true,
                      child: Card(
                        child: ListTile(
                          key: const ValueKey<String>(
                            'settings/offline-content',
                          ),
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
                        child: MenuActionBinding(
                          id: researchConsentEntry.id,
                          label: researchConsentEntry.fullThaiLabel,
                          onInvoke: failed
                              ? () => _reloadConsent(consent)
                              : enabled
                              ? () => _openResearchConsentDetails(accepted)
                              : null,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
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
              MenuActionBinding(
                id: cloudStatusEntry.id,
                label: cloudStatusEntry.fullThaiLabel,
                onInvoke: null,
                readValue: jsonEncode({
                  'firebaseAvailability':
                      dependencies?.runtimeStatus.firebase.name ?? 'unknown',
                  'syncEngineConfigured': dependencies?.syncEngine != null,
                  'syncCompletion': 'not-observed',
                  'interpretation':
                      'service-readiness-is-not-network-connectivity-or-confirmed-sync',
                  'baselineRequiresMcp': false,
                }),
                child: Tooltip(
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
              ),
              if (session != null && !session.isAnonymous) ...[
                Tooltip(
                  message: changePasswordEntry.tooltip,
                  child: MenuActionBinding(
                    id: changePasswordEntry.id,
                    label: changePasswordEntry.fullThaiLabel,
                    onInvoke: passwordReady ? openPassword : null,
                    child: Semantics(
                      button: true,
                      enabled: passwordReady,
                      label: changePasswordEntry.semanticsLabel,
                      onTap: passwordReady ? openPassword : null,
                      excludeSemantics: true,
                      child: Card(
                        child: ListTile(
                          minTileHeight: 48,
                          leading: Icon(changePasswordEntry.icon),
                          title: Text(changePasswordEntry.fullThaiLabel),
                          onTap: passwordReady ? openPassword : null,
                        ),
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: logoutEntry.tooltip,
                  child: MenuActionBinding(
                    id: logoutEntry.id,
                    label: logoutEntry.fullThaiLabel,
                    onInvoke: null,
                    child: Semantics(
                      button: true,
                      enabled: logoutReady,
                      label: logoutEntry.semanticsLabel,
                      hint:
                          'สร้างพื้นที่ใช้งานในเครื่องใหม่โดยไม่ลบข้อมูลบัญชี',
                      onTap: logoutReady ? logout : null,
                      excludeSemantics: true,
                      child: Card(
                        child: ListTile(
                          minTileHeight: 48,
                          leading: Icon(logoutEntry.icon),
                          title: Text(logoutEntry.fullThaiLabel),
                          subtitle: const Text(
                            'สร้างพื้นที่ใช้งานในเครื่องใหม่โดยไม่ลบข้อมูลบัญชี',
                          ),
                          onTap: logoutReady ? logout : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (_localDataEraser != null && _localOwners != null)
                Tooltip(
                  message: eraseLocalDataEntry.tooltip,
                  child: MenuActionBinding(
                    id: eraseLocalDataEntry.id,
                    label: eraseLocalDataEntry.fullThaiLabel,
                    onInvoke: _busy
                        ? null
                        : () {
                            unawaited(_eraseLocalData());
                          },
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
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
