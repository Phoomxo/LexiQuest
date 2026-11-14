import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../config/app_appearance_preferences.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account_deletion/application/account_deletion_use_cases.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../features/consent/domain/research_consent.dart';
import '../features/device_model/application/device_model_use_cases.dart';
import '../features/device_model/domain/model_lifecycle.dart';
import '../features/device_model/domain/model_manifest.dart';
import '../features/motivation/application/streak_use_cases.dart';
import '../features/motivation/domain/timezone_policy.dart';
import '../features/sync/application/sync_engine.dart';
import '../features/sync/application/sync_status.dart';
import '../features/sync/application/sync_trigger.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../runtime/registries/feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import 'export_center_screen.dart';
import 'account_deletion_screen.dart';
import 'appearance_settings_screen.dart';
import 'gemini_settings_screen.dart';
import 'device_permission_center_screen.dart';
import 'object_scanner_screen.dart';
import 'shadowing_challenge_screen.dart';
import 'study_preferences_panel.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({
    super.key,
    this.account,
    this.accountDeletion,
    this.researchConsent,
    this.deviceModels,
    this.featureRegistry,
    this.deviceModelDownload,
  });

  final AccountUseCases? account;
  final AccountDeletionUseCases? accountDeletion;
  final ResearchConsentUseCases? researchConsent;
  final DeviceModelUseCases? deviceModels;
  final FieldFeatureRegistry? featureRegistry;
  final Future<ModelDownloadRecord> Function()? deviceModelDownload;

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  AccountUseCases? _account;
  AccountDeletionUseCases? _accountDeletion;
  ResearchConsentUseCases? _researchConsent;
  Future<ResearchConsentStatus>? _researchStatus;
  SyncTrigger? _syncTrigger;
  SyncStatusSource? _syncStatusSource;
  StreamSubscription<SyncStatusSnapshot?>? _syncStatusSubscription;
  SyncStatusSnapshot? _syncStatusSnapshot;
  _LocalSyncStatusPhase _localSyncStatusPhase =
      _LocalSyncStatusPhase.unavailable;
  int _syncStatusGeneration = 0;
  bool _busy = false;
  bool _syncBusy = false;
  int _syncRequestGeneration = 0;
  String? _syncStatus;
  DeviceModelUseCases? _deviceModels;
  FieldFeatureRegistry _fieldFeatures =
      const BuildFieldFeatureRegistry.fieldDefaults();
  ModelDownloadRecord? _modelRecord;
  _DeviceModelStatusPhase _modelStatusPhase =
      _DeviceModelStatusPhase.unavailable;
  int _modelStatusGeneration = 0;
  bool _modelBusy = false;
  String? _modelFeedback;
  StreakUseCases? _streak;
  bool _calendarVisible = false;
  final _calendarInput = TextEditingController();
  ValueListenable<int>? _calendarUpdates;
  ({String ownerId, OwnerCalendarRule current, OwnerCalendarRule? pending})?
  _calendarView;
  String? _calendarLoadedOwner;
  String? _calendarError;
  bool _calendarLoading = false;
  bool _calendarSaving = false;
  int _calendarGeneration = 0;
  int _calendarLoadRequest = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindDependencies();
  }

  @override
  void didUpdateWidget(SettingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindDependencies();
  }

  AccountUseCases? get _currentAccount =>
      widget.account ?? AppDependenciesScope.maybeOf(context)?.account;

  AccountDeletionUseCases? get _currentDeletion =>
      widget.accountDeletion ??
      AppDependenciesScope.maybeOf(context)?.accountDeletion;

  bool _isCurrentAccount(AccountUseCases account, String uid) =>
      mounted &&
      identical(_currentAccount, account) &&
      account.currentSession?.uid == uid;

  void _bindDependencies() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    _account = widget.account ?? dependencies?.account;
    _accountDeletion = widget.accountDeletion ?? dependencies?.accountDeletion;
    final researchConsent =
        widget.researchConsent ?? dependencies?.researchConsent;
    if (!identical(_researchConsent, researchConsent)) {
      _researchConsent = researchConsent;
      _researchStatus = researchConsent?.load();
    }
    if (!identical(_syncTrigger, dependencies?.syncTrigger)) {
      _syncTrigger = dependencies?.syncTrigger;
      _syncRequestGeneration++;
      _syncBusy = false;
      _syncStatus = null;
    }
    _replaceSyncStatusSource(dependencies?.syncStatus);
    _fieldFeatures =
        widget.featureRegistry ??
        dependencies?.fieldFeatures ??
        const BuildFieldFeatureRegistry.fieldDefaults();
    _replaceDeviceModels(widget.deviceModels ?? dependencies?.deviceModels);
    final features =
        dependencies?.features ?? const BuildFeatureRegistry.fieldDefaults();
    final streak = dependencies?.streak;
    final calendarVisible =
        streak != null &&
        features.isVisible(Feature.mastery) &&
        _fieldFeatures.isVisible(FieldFeature.mastery);
    final updates = calendarVisible ? dependencies?.progressUpdates : null;
    if (!identical(_calendarUpdates, updates)) {
      _calendarUpdates?.removeListener(_onCalendarUpdate);
      _calendarUpdates = updates;
      _calendarUpdates?.addListener(_onCalendarUpdate);
    }
    if (!identical(_streak, streak) || _calendarVisible != calendarVisible) {
      _streak = streak;
      _calendarVisible = calendarVisible;
      _calendarGeneration++;
      _calendarLoadRequest++;
      _calendarView = null;
      _calendarLoadedOwner = null;
      _calendarError = null;
      _calendarInput.clear();
      _calendarSaving = false;
      _calendarLoading = calendarVisible;
      if (calendarVisible) unawaited(_loadHomeCalendar(rebuild: false));
    }
  }

  bool _isCurrentCalendar(StreakUseCases source, int generation) =>
      mounted &&
      _calendarVisible &&
      identical(_streak, source) &&
      generation == _calendarGeneration;

  void _onCalendarUpdate() {
    if (!mounted || !_calendarVisible) return;
    if (_calendarSaving) {
      setState(() {
        _calendarView = null;
        _calendarLoading = true;
      });
      return;
    }
    unawaited(_loadHomeCalendar());
  }

  Future<void> _loadHomeCalendar({
    bool rebuild = true,
    bool clearError = false,
  }) async {
    final source = _streak;
    if (!_calendarVisible || source == null) return;
    final generation = _calendarGeneration;
    final request = ++_calendarLoadRequest;
    void loading() {
      _calendarLoading = true;
      _calendarView = null;
      if (clearError) _calendarError = null;
    }

    if (rebuild) {
      setState(loading);
    } else {
      loading();
    }
    try {
      final view = await source.loadCalendar();
      if (!_isCurrentCalendar(source, generation) ||
          request != _calendarLoadRequest) {
        return;
      }
      setState(() {
        _calendarView = view;
        _calendarLoading = false;
        if (_calendarLoadedOwner != view.ownerId) {
          _calendarInput.text = view.pending?.ianaId ?? view.current.ianaId;
        }
        _calendarLoadedOwner = view.ownerId;
      });
    } on Object {
      if (!_isCurrentCalendar(source, generation) ||
          request != _calendarLoadRequest) {
        return;
      }
      setState(() {
        _calendarLoading = false;
        _calendarError = 'โหลดปฏิทินการเรียนไม่ได้ โปรดลองโหลดใหม่';
      });
    }
  }

  Future<void> _saveHomeCalendar() async {
    final source = _streak;
    final view = _calendarView;
    if (!_calendarVisible ||
        source == null ||
        view == null ||
        _calendarLoading ||
        _calendarSaving ||
        _busy ||
        _syncBusy) {
      return;
    }
    final zone = _calendarInput.text.trim();
    if (zone.isEmpty) {
      setState(
        () => _calendarError = 'กรอกเขตเวลา IANA เช่น Asia/Bangkok หรือ UTC',
      );
      return;
    }
    final generation = _calendarGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _calendarSaving = true;
      _calendarError = null;
    });
    try {
      await source.selectHomeTimezone(
        expectedOwnerId: view.ownerId,
        ianaId: zone,
      );
      if (!_isCurrentCalendar(source, generation)) return;
      setState(() => _calendarSaving = false);
      await _loadHomeCalendar(clearError: true);
    } on Object catch (error) {
      if (!_isCurrentCalendar(source, generation)) return;
      setState(() {
        _calendarSaving = false;
        _calendarError = error is ArgumentError
            ? 'ไม่พบเขตเวลานี้ โปรดใช้ชื่อ IANA เช่น Asia/Bangkok หรือ UTC'
            : 'ยืนยันการเปลี่ยนเขตเวลาไม่ได้ โปรดตรวจสอบค่าปัจจุบันแล้วลองอีกครั้ง';
      });
      await _loadHomeCalendar();
    }
  }

  String _calendarActivation(int us) {
    final value = DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}'
        '${value.second == 0 ? '' : ':${two(value.second)}'} UTC';
  }

  Widget _homeCalendarCard() {
    final view = _calendarView;
    final pending = view?.pending;
    final disabled =
        _calendarLoading ||
        _calendarSaving ||
        _busy ||
        _syncBusy ||
        view == null;
    return Card(
      key: const ValueKey<String>('settings-home-calendar'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.public_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ปฏิทินการเรียน',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_calendarLoading) const Text('กำลังโหลดปฏิทินการเรียน…'),
            if (view != null) ...[
              Text(
                'เขตเวลาปัจจุบัน: ${view.current.ianaId}',
                key: const ValueKey<String>('settings-home-calendar-current'),
              ),
              if (pending != null) ...[
                const SizedBox(height: 8),
                Text(
                  'กำหนดไว้: ${pending.ianaId}\nเริ่ม ${_calendarActivation(pending.effectiveUtcUs)}',
                  key: const ValueKey<String>('settings-home-calendar-pending'),
                ),
              ],
            ],
            const SizedBox(height: 8),
            const Text(
              'การเดินทางไม่เปลี่ยนค่านี้อัตโนมัติ เขตเวลาใหม่เริ่มหลังสิ้นสัปดาห์ปัจจุบัน',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey<String>('settings-home-calendar-input'),
              controller: _calendarInput,
              enabled: !disabled,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'เขตเวลา IANA',
                helperText: 'เช่น Asia/Bangkok หรือ UTC',
                helperMaxLines: 2,
              ),
              onSubmitted: (_) => unawaited(_saveHomeCalendar()),
            ),
            if (_calendarError case final error?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const ValueKey<String>('settings-home-calendar-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey<String>('settings-home-calendar-save'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: disabled ? null : () => unawaited(_saveHomeCalendar()),
              child: Text(_calendarSaving ? 'กำลังบันทึก…' : 'บันทึกเขตเวลา'),
            ),
            if (_calendarError != null)
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _calendarLoading || _calendarSaving
                    ? null
                    : () => unawaited(_loadHomeCalendar(clearError: true)),
                child: const Text('โหลดข้อมูลใหม่'),
              ),
          ],
        ),
      ),
    );
  }

  void _replaceSyncStatusSource(SyncStatusSource? source) {
    if (identical(_syncStatusSource, source)) return;
    _syncStatusSource = source;
    final generation = ++_syncStatusGeneration;
    final previous = _syncStatusSubscription;
    _syncStatusSubscription = null;
    if (previous != null) unawaited(previous.cancel());
    _syncStatusSnapshot = null;
    _localSyncStatusPhase = source == null
        ? _LocalSyncStatusPhase.unavailable
        : _LocalSyncStatusPhase.loading;
    if (source == null) return;

    try {
      void markUnavailable() {
        if (!mounted || generation != _syncStatusGeneration) return;
        setState(() {
          _syncStatusSnapshot = null;
          _localSyncStatusPhase = _LocalSyncStatusPhase.unavailable;
        });
      }

      _syncStatusSubscription = source.watchCurrentOwnerSyncStatus().listen(
        (snapshot) {
          if (!mounted || generation != _syncStatusGeneration) return;
          setState(() {
            _syncStatusSnapshot = snapshot;
            _localSyncStatusPhase = snapshot == null
                ? _LocalSyncStatusPhase.unavailable
                : _LocalSyncStatusPhase.available;
          });
        },
        onError: (Object _, StackTrace _) => markUnavailable(),
        onDone: markUnavailable,
      );
    } catch (_) {
      _localSyncStatusPhase = _LocalSyncStatusPhase.unavailable;
    }
  }

  @override
  void dispose() {
    _calendarGeneration++;
    _calendarUpdates?.removeListener(_onCalendarUpdate);
    _calendarInput.dispose();
    _syncStatusGeneration++;
    _modelStatusGeneration++;
    final subscription = _syncStatusSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  void _replaceDeviceModels(DeviceModelUseCases? deviceModels) {
    if (identical(_deviceModels, deviceModels)) return;
    _deviceModels = deviceModels;
    final generation = ++_modelStatusGeneration;
    _modelRecord = null;
    _modelFeedback = null;
    _modelBusy = false;
    _modelStatusPhase = deviceModels == null
        ? _DeviceModelStatusPhase.unavailable
        : _DeviceModelStatusPhase.loading;
    if (deviceModels != null) {
      unawaited(_loadDeviceModelStatus(deviceModels, generation));
    }
  }

  Future<void> _loadDeviceModelStatus(
    DeviceModelUseCases deviceModels,
    int generation,
  ) async {
    try {
      final record = await deviceModels.status();
      if (!_isCurrentDeviceModel(deviceModels, generation)) return;
      setState(() {
        _modelRecord = record;
        _modelStatusPhase = _DeviceModelStatusPhase.available;
      });
    } catch (_) {
      if (!_isCurrentDeviceModel(deviceModels, generation)) return;
      setState(() {
        _modelRecord = null;
        _modelStatusPhase = _DeviceModelStatusPhase.unavailable;
      });
    }
  }

  bool _isCurrentDeviceModel(
    DeviceModelUseCases deviceModels,
    int generation,
  ) =>
      mounted &&
      generation == _modelStatusGeneration &&
      identical(deviceModels, _deviceModels);

  Future<void> _downloadDeviceModel() async {
    final deviceModels = _deviceModels;
    if (deviceModels == null || _modelBusy) return;
    final generation = _modelStatusGeneration;
    setState(() {
      _modelBusy = true;
      _modelFeedback = null;
    });
    try {
      await (widget.deviceModelDownload?.call() ??
          deviceModels.downloadAndActivate());
      if (_isCurrentDeviceModel(deviceModels, generation)) {
        setState(() => _modelFeedback = 'ดาวน์โหลดและเปิดใช้งานแล้ว');
      }
    } on ModelLifecycleException catch (error) {
      if (_isCurrentDeviceModel(deviceModels, generation)) {
        setState(() => _modelFeedback = _modelFailureText(error.code));
      }
    } catch (_) {
      if (_isCurrentDeviceModel(deviceModels, generation)) {
        setState(() => _modelFeedback = 'ดาวน์โหลดไม่สำเร็จ โปรดลองอีกครั้ง');
      }
    } finally {
      if (_isCurrentDeviceModel(deviceModels, generation)) {
        await _loadDeviceModelStatus(deviceModels, generation);
        if (_isCurrentDeviceModel(deviceModels, generation)) {
          setState(() => _modelBusy = false);
        }
      }
    }
  }

  Future<void> _changePassword() async {
    final account = _currentAccount;
    final session = account?.currentSession;
    if (account == null ||
        session == null ||
        session.isAnonymous ||
        _busy ||
        _syncBusy) {
      return;
    }
    var currentPassword = '';
    var newPassword = '';
    String? currentPasswordError;
    String? newPasswordError;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final currentError = _passwordChangeError(
              currentPassword,
              emptyMessage: 'กรอกรหัสผ่านปัจจุบัน',
              shortMessage: 'รหัสผ่านปัจจุบันต้องมีอย่างน้อย 8 ตัวอักษร',
            );
            final nextError = _passwordChangeError(
              newPassword,
              emptyMessage: 'กรอกรหัสผ่านใหม่',
              shortMessage: 'รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร',
            );
            setDialogState(() {
              currentPasswordError = currentError;
              newPasswordError = nextError;
            });
            if (currentError != null || nextError != null) return;
            Navigator.pop(dialogContext, true);
          }

          return AlertDialog(
            scrollable: true,
            title: const Text('เปลี่ยนรหัสผ่าน'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่านปัจจุบัน',
                    errorText: currentPasswordError,
                  ),
                  onChanged: (value) {
                    currentPassword = value;
                    if (currentPasswordError != null) {
                      setDialogState(() => currentPasswordError = null);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่านใหม่อย่างน้อย 8 ตัวอักษร',
                    errorText: newPasswordError,
                  ),
                  onChanged: (value) {
                    newPassword = value;
                    if (newPasswordError != null) {
                      setDialogState(() => newPasswordError = null);
                    }
                  },
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(onPressed: submit, child: const Text('บันทึก')),
            ],
          );
        },
      ),
    );
    if (submitted != true || !mounted) return;
    if (!_isCurrentAccount(account, session.uid)) {
      _show('บัญชีเปลี่ยนแล้ว กรุณาเปิดการตั้งค่าอีกครั้ง');
      return;
    }
    setState(() => _busy = true);
    try {
      await account.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (_isCurrentAccount(account, session.uid)) {
        _show('เปลี่ยนรหัสผ่านแล้ว');
      }
    } on AccountException catch (error) {
      if (_isCurrentAccount(account, session.uid)) {
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

  String? _passwordChangeError(
    String value, {
    required String emptyMessage,
    required String shortMessage,
  }) {
    if (value.isEmpty) return emptyMessage;
    if (value.length < 8) return shortMessage;
    if (value.length > 128) return 'รหัสผ่านต้องไม่เกิน 128 ตัวอักษร';
    return null;
  }

  Future<void> _logout() async {
    final account = _currentAccount;
    if (account == null ||
        account.currentSession?.isAnonymous != false ||
        _busy ||
        _syncBusy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await account.signOutToLocalGuest();
      if (!mounted || !identical(_currentAccount, account)) return;
      await AppNavigator.resetTo<void>(context, AppRoute.login);
    } on AccountException {
      if (mounted && identical(_currentAccount, account)) {
        _show('ออกจากระบบไม่สำเร็จ ข้อมูลในเครื่องยังไม่ถูกลบ');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _withdrawResearchConsent(String expectedOwnerId) async {
    final consent = _researchConsent;
    if (consent == null || _busy || _syncBusy) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    bool current() =>
        mounted &&
        identical(AppDependenciesScope.maybeOf(context), dependencies) &&
        identical(_researchConsent, consent);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('ยืนยันการถอนความยินยอม'),
        content: const Text(
          'หลังถอน ข้อมูลใหม่จะไม่ถูกส่งออกเป็นชุดวิจัย '
          'การเรียนและการส่งออกข้อมูลส่วนตัวยังใช้ได้ '
          'การกระทำนี้ไม่ลบบัญชีหรือข้อมูลในเครื่อง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ถอนความยินยอม'),
          ),
        ],
      ),
    );
    if (!current()) return;
    if (confirmed != true) {
      setState(() {
        _researchStatus = consent.load();
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final withdrawn = await consent.withdraw(
        expectedOwnerId: expectedOwnerId,
      );
      if (current()) {
        setState(() {
          _researchStatus = consent.load();
        });
        if (!withdrawn) {
          _show('สถานะความยินยอมเปลี่ยนแล้ว กรุณาตรวจสอบอีกครั้ง');
        }
      }
    } catch (_) {
      if (current()) {
        setState(() {
          _researchStatus = consent.load();
        });
        _show('ถอนความยินยอมไม่สำเร็จ ข้อมูลในเครื่องยังไม่ถูกลบ');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync() async {
    final trigger = _syncTrigger;
    final generation = _syncRequestGeneration;
    if (trigger == null || _syncBusy) return;
    setState(() {
      _syncBusy = true;
      _syncStatus = null;
    });
    late final String status;
    try {
      status = _syncResultText(
        await trigger.request(SyncTriggerReason.manualRetry),
      );
    } catch (_) {
      status =
          'ตรวจสอบการซิงก์ออนไลน์ไม่สำเร็จ ข้อมูลในเครื่องยังไม่ถูกลบ '
          'โปรดลองใหม่ภายหลัง';
    }
    if (!mounted ||
        generation != _syncRequestGeneration ||
        !identical(trigger, _syncTrigger)) {
      return;
    }
    setState(() {
      _syncBusy = false;
      _syncStatus = status;
    });
  }

  String _syncResultText(SyncRunResult result) => switch (result.status) {
    SyncRunStatus.completed =>
      'ตรวจสอบรอบนี้แล้ว: ส่ง ${result.pushed} รับ ${result.pulled} '
          'จัดการความขัดแย้ง ${result.conflicts} รายการ '
          'ข้อมูลในเครื่องยังอยู่',
    SyncRunStatus.partialFailure =>
      'รอบนี้สำเร็จบางส่วน: ส่ง ${result.pushed} รับ ${result.pulled} '
          'พบข้อผิดพลาด ${result.failures} จุด '
          '${result.retryRecommended ? 'ลองใหม่ภายหลังได้ ' : ''}'
          'ข้อมูลการเรียนในเครื่องยังใช้ได้',
    SyncRunStatus.skippedCloudDisabled =>
      'การซิงก์ออนไลน์ถูกปิดตามนโยบาย ข้อมูลในเครื่องยังใช้ได้',
    SyncRunStatus.skippedUnauthenticated =>
      'ยังไม่ได้เชื่อมบัญชี จึงใช้ข้อมูลในเครื่องต่อได้',
    SyncRunStatus.alreadyRunning =>
      'มีรอบตรวจสอบการซิงก์กำลังทำงานอยู่ ข้อมูลในเครื่องยังอยู่',
  };

  Widget _localSyncStatus() {
    final label = switch (_localSyncStatusPhase) {
      _LocalSyncStatusPhase.loading => 'กำลังตรวจสอบสถานะคิวในเครื่อง…',
      _LocalSyncStatusPhase.unavailable => 'ตรวจสอบสถานะคิวในเครื่องไม่ได้',
      _LocalSyncStatusPhase.available => _syncStatusText(_syncStatusSnapshot!),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: ExcludeSemantics(
          child: Text(
            label,
            key: const ValueKey<String>('settings-sync-queue-status'),
          ),
        ),
      ),
    );
  }

  String _syncStatusText(SyncStatusSnapshot status) =>
      'รอส่ง ${status.pending} · รอลองใหม่ ${status.retryWaiting}\n'
      'กำลังประมวลผลหรือรอกู้คืน ${status.inFlight} · '
      'รอเชื่อมบัญชี ${status.blockedAuth}\n'
      'ต้องตรวจสอบ ${status.permanentFailure} · '
      'ประวัติความขัดแย้งที่จัดการแล้ว ${status.handledConflicts}';

  void _openSettingsPage(String name, Widget page) {
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: name, builder: (_) => page),
    );
  }

  void _openAccountDeletion(
    AccountDeletionUseCases deletion,
    AccountUseCases? account,
    String? uid,
  ) {
    if (account == null ||
        uid == null ||
        !_isCurrentAccount(account, uid) ||
        !identical(_currentDeletion, deletion)) {
      _show('บัญชีเปลี่ยนแล้ว กรุณาเปิดการตั้งค่าอีกครั้ง');
      return;
    }
    _openSettingsPage(
      'account/delete',
      AccountDeletionScreen(useCases: deletion),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _featureRow({
    required Key key,
    required FieldFeature feature,
    required IconData icon,
    required String title,
    required String limitedReason,
    required VoidCallback onTap,
  }) {
    final state = _fieldFeatures.stateOf(feature);
    if (state == FieldFeatureState.hidden) return const SizedBox.shrink();
    return ListTile(
      key: key,
      minTileHeight: 64,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        state == FieldFeatureState.limited
            ? 'ใช้งานแบบจำกัด · $limitedReason'
            : 'พร้อมใช้งาน',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _deviceModelCard() {
    final deviceModels = _deviceModels;
    final manifest =
        deviceModels?.manifest ?? ModelManifest.fieldImageClassifier;
    final canAct =
        deviceModels != null &&
        _modelStatusPhase == _DeviceModelStatusPhase.available &&
        switch (_modelRecord?.state) {
          null ||
          ModelDownloadState.notStarted ||
          ModelDownloadState.failed ||
          ModelDownloadState.cancelled ||
          ModelDownloadState.ready => true,
          _ => false,
        };
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              minTileHeight: 64,
              leading: const Icon(Icons.offline_bolt_outlined),
              title: const Text('เนื้อหาสำหรับสแกนแบบออฟไลน์'),
              subtitle: Text(
                'เวอร์ชัน ${manifest.version} · '
                '${manifest.expectedBytes} ไบต์ '
                '(${_megabytes(manifest.expectedBytes)} MB)',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Semantics(
                liveRegion: true,
                child: Text(_deviceModelStatusText(deviceModels)),
              ),
            ),
            if (canAct)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  key: const ValueKey<String>('settings-device-model-action'),
                  onPressed: _modelBusy ? null : _downloadDeviceModel,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: _modelBusy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            semanticsLabel: 'กำลังดาวน์โหลดเนื้อหาสำหรับสแกน',
                          ),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(_deviceModelActionText()),
                ),
              ),
            if (_modelFeedback case final feedback?) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Semantics(liveRegion: true, child: Text(feedback)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _deviceModelStatusText(DeviceModelUseCases? deviceModels) {
    if (deviceModels == null) {
      return 'ยังไม่พร้อมใช้ในรุ่นนี้ และจะไม่ดาวน์โหลดเอง';
    }
    if (_modelStatusPhase == _DeviceModelStatusPhase.loading) {
      return 'กำลังตรวจสอบไฟล์ในอุปกรณ์…';
    }
    if (_modelStatusPhase == _DeviceModelStatusPhase.unavailable) {
      return 'ตรวจสอบไฟล์ในอุปกรณ์ไม่ได้ จึงยังไม่เริ่มดาวน์โหลด';
    }
    final record = _modelRecord;
    if (record == null) return 'ยังไม่ได้ดาวน์โหลด';
    return switch (record.state) {
      ModelDownloadState.notStarted => 'ยังไม่ได้ดาวน์โหลด',
      ModelDownloadState.downloading =>
        'กำลังดาวน์โหลด ${record.downloadedBytes} จาก ${record.expectedBytes} ไบต์',
      ModelDownloadState.verifying => 'ดาวน์โหลดแล้ว กำลังตรวจสอบไฟล์',
      ModelDownloadState.ready => 'ไฟล์พร้อม รอเปิดใช้งาน',
      ModelDownloadState.active => 'พร้อมใช้งานบนอุปกรณ์นี้',
      ModelDownloadState.failed =>
        'ดาวน์โหลดไม่สำเร็จ · ${_modelFailureText(record.failureCode)}',
      ModelDownloadState.cancelled => 'ยกเลิกการดาวน์โหลดแล้ว',
    };
  }

  String _deviceModelActionText() => switch (_modelRecord?.state) {
    ModelDownloadState.failed ||
    ModelDownloadState.cancelled => 'ลองดาวน์โหลดอีกครั้ง',
    ModelDownloadState.ready => 'เปิดใช้งานไฟล์ที่ดาวน์โหลดแล้ว',
    _ => _modelBusy ? 'กำลังดาวน์โหลด…' : 'ดาวน์โหลดและเปิดใช้งาน',
  };

  String _modelFailureText(ModelFailureCode? code) => switch (code) {
    ModelFailureCode.network => 'เชื่อมต่อเพื่อดาวน์โหลดไม่ได้',
    ModelFailureCode.writeFailed => 'บันทึกไฟล์ในอุปกรณ์ไม่ได้',
    ModelFailureCode.sizeMismatch ||
    ModelFailureCode.checksumMismatch => 'ไฟล์ที่ได้รับไม่สมบูรณ์',
    ModelFailureCode.interpreterRejected ||
    ModelFailureCode.incompatibleTensor => 'ไฟล์นี้ใช้กับอุปกรณ์ไม่ได้',
    ModelFailureCode.busy => 'มีการดาวน์โหลดอื่นกำลังทำงาน',
    ModelFailureCode.cancelled => 'ยกเลิกการดาวน์โหลดแล้ว',
    _ => 'ดาวน์โหลดไม่สำเร็จ โปรดลองอีกครั้ง',
  };

  String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final study = AppDependenciesScope.maybeOf(context)?.studyPreferences;
    final session = _account?.currentSession;
    final isRegistered = session != null && !session.isAnonymous;
    final scaffold = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !_busy && !_calendarSaving,
        title: const Text('ตั้งค่า'),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.proseMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: Icon(
                  !isRegistered
                      ? Icons.person_outline
                      : session.emailVerified
                      ? Icons.verified_user_outlined
                      : Icons.mark_email_unread_outlined,
                ),
                title: Text(
                  isRegistered
                      ? session.email ?? 'บัญชีผู้เรียน'
                      : 'ไม่ใช้บัญชี',
                ),
                subtitle: Text(
                  session == null
                      ? 'ข้อมูลการเรียนอยู่ในเครื่องและอัปเกรดบัญชีได้ภายหลัง'
                      : session.isAnonymous
                      ? 'การเรียนโดยไม่ใช้บัญชีไม่ต้องยืนยันอีเมล และข้อมูลในเครื่องยังใช้ได้'
                      : session.emailVerified
                      ? 'ยืนยันอีเมลแล้ว'
                      : 'รอยืนยันอีเมล',
                ),
              ),
            ),
            Card(
              child: ListTile(
                key: const ValueKey<String>('settings-appearance'),
                minTileHeight: 64,
                leading: const Icon(Icons.palette_outlined),
                title: const Text('การแสดงผล'),
                subtitle: const Text(
                  'เลือกโหมดสว่าง มืด หรือใช้ตามการตั้งค่าของอุปกรณ์',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: AppAppearanceScope.maybeOf(context) == null
                    ? null
                    : () => _openSettingsPage(
                        'settings/appearance',
                        const AppearanceSettingsScreen(),
                      ),
              ),
            ),
            if (_calendarVisible) _homeCalendarCard(),
            if (_researchConsent != null)
              FutureBuilder(
                future: _researchStatus,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Card(
                      child: ListTile(
                        minTileHeight: 64,
                        leading: Icon(Icons.hourglass_top_outlined),
                        title: Text('ความยินยอมงานวิจัย'),
                        subtitle: Text('กำลังตรวจสอบสถานะ…'),
                      ),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Semantics(
                      liveRegion: true,
                      child: const Card(
                        child: ListTile(
                          minTileHeight: 64,
                          leading: Icon(Icons.info_outline),
                          title: Text('ความยินยอมงานวิจัย'),
                          subtitle: Text(
                            'ตรวจสอบสถานะไม่ได้ '
                            'ระบบจะไม่เปิดการส่งออกชุดวิจัย',
                          ),
                        ),
                      ),
                    );
                  }
                  final status = snapshot.data!;
                  if (!status.accepted) {
                    return Card(
                      child: ListTile(
                        minTileHeight: 64,
                        leading: const Icon(Icons.assignment_outlined),
                        title: const Text('ความยินยอมงานวิจัย'),
                        subtitle: const Text(
                          'ไม่ได้เข้าร่วม '
                          'ข้อมูลการเรียนจะไม่ถูกส่งออกเป็นชุดวิจัย',
                        ),
                      ),
                    );
                  }
                  return Card(
                    child: Column(
                      children: [
                        const ListTile(
                          minTileHeight: 64,
                          leading: Icon(Icons.fact_check_outlined),
                          title: Text('ความยินยอมงานวิจัย'),
                          subtitle: Text(
                            'ยินยอมฉบับ '
                            '${ResearchConsentUseCases.currentVersion} '
                            'และถอนความยินยอมได้',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const ValueKey<String>(
                                'settings-research-withdraw',
                              ),
                              onPressed: _busy || _syncBusy
                                  ? null
                                  : () => _withdrawResearchConsent(
                                      status.ownerId,
                                    ),
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('ถอนความยินยอม'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ListTile(
                      minTileHeight: 64,
                      leading: Icon(Icons.cloud_sync_outlined),
                      title: Text('การซิงก์และการเรียนออฟไลน์'),
                      subtitle: Text(
                        'ลองส่งและรับเฉพาะข้อมูลที่ถึงคิว '
                        'ข้อมูลในเครื่องยังใช้ได้หากบริการซิงก์ไม่พร้อม',
                      ),
                    ),
                    _localSyncStatus(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey<String>('settings-sync-now'),
                          onPressed: _syncTrigger == null || _syncBusy || _busy
                              ? null
                              : _runSync,
                          icon: _syncBusy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    semanticsLabel: 'กำลังตรวจสอบการซิงก์',
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: Text(
                            _syncBusy
                                ? 'กำลังตรวจสอบ…'
                                : 'ตรวจสอบการซิงก์ตอนนี้',
                          ),
                        ),
                      ),
                    ),
                    if (_syncStatus case final status?) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            status,
                            key: const ValueKey<String>('settings-sync-status'),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (isRegistered) ...[
              ListTile(
                minTileHeight: 48,
                leading: const Icon(Icons.password_outlined),
                title: const Text('เปลี่ยนรหัสผ่าน'),
                onTap: _busy || _syncBusy ? null : _changePassword,
              ),
              ListTile(
                minTileHeight: 48,
                leading: const Icon(Icons.logout),
                title: const Text('ออกจากระบบ'),
                subtitle: const Text(
                  'สร้างพื้นที่เรียนในเครื่องใหม่โดยไม่ลบข้อมูลบัญชี',
                ),
                onTap: _busy || _syncBusy ? null : _logout,
              ),
              if (_accountDeletion case final deletion?)
                ListTile(
                  key: const ValueKey<String>('settings-delete-account'),
                  minTileHeight: 48,
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('ลบบัญชีและข้อมูล'),
                  subtitle: const Text(
                    'ส่งออกสำเนาก่อนลบ และยืนยันตัวตนอีกครั้ง',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || _syncBusy
                      ? null
                      : () => _openAccountDeletion(
                          deletion,
                          account,
                          session.uid,
                        ),
                ),
            ],
            if (study != null)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('วิธีเรียนและวันเป้าหมาย'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy ? null : () => showStudyPreferences(context),
              ),
            _sectionTitle('ข้อมูลและผู้ช่วยการเรียน'),
            Card(
              child: Column(
                children: [
                  if (_fieldFeatures.isVisible(FieldFeature.export))
                    _featureRow(
                      key: const ValueKey<String>('settings-feature-export'),
                      feature: FieldFeature.export,
                      icon: Icons.file_download_outlined,
                      title: 'ส่งออกข้อมูลการเรียน',
                      limitedReason:
                          'บางรูปแบบต้องมีข้อมูลและสิทธิ์ที่เกี่ยวข้อง',
                      onTap: () => _openSettingsPage(
                        'export/center',
                        const ExportCenterScreen(),
                      ),
                    ),
                  if (_fieldFeatures.isVisible(FieldFeature.aiTutor))
                    _featureRow(
                      key: const ValueKey<String>('settings-feature-ai'),
                      feature: FieldFeature.aiTutor,
                      icon: Icons.smart_toy_outlined,
                      title: 'ตั้งค่าผู้ช่วย AI',
                      limitedReason:
                          'ต้องเชื่อมต่อผู้ช่วย AI และยินยอมก่อนใช้งาน',
                      onTap: () => _openSettingsPage(
                        'gemini/settings',
                        const GeminiSettingsScreen(),
                      ),
                    ),
                ],
              ),
            ),
            _sectionTitle('เสียง กล้อง และเนื้อหาในอุปกรณ์'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    key: const ValueKey<String>('settings-permission-center'),
                    minTileHeight: 64,
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('สิทธิ์กล้องและไมโครโฟน'),
                    subtitle: const Text(
                      'ตรวจสอบสถานะโดยไม่เปิดหน้าต่างขอสิทธิ์',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openSettingsPage(
                      'settings/device-permissions',
                      const DevicePermissionCenterScreen(),
                    ),
                  ),
                  if (_fieldFeatures.isVisible(FieldFeature.speechPractice))
                    _featureRow(
                      key: const ValueKey<String>('settings-feature-voice'),
                      feature: FieldFeature.speechPractice,
                      icon: Icons.mic_none,
                      title: 'ฝึกพูดตามเสียง',
                      limitedReason:
                          'ต้องอนุญาตไมโครโฟนเมื่อเริ่มฝึก '
                          'และใช้ระบบรู้จำเสียงของอุปกรณ์',
                      onTap: () => _openSettingsPage(
                        'practice/shadowing',
                        const ShadowingChallengeScreen(),
                      ),
                    ),
                  if (_fieldFeatures.isVisible(FieldFeature.objectScanner))
                    _featureRow(
                      key: const ValueKey<String>('settings-feature-scanner'),
                      feature: FieldFeature.objectScanner,
                      icon: Icons.document_scanner_outlined,
                      title: 'สแกนวัตถุเป็นคำศัพท์',
                      limitedReason:
                          'ต้องอนุญาตกล้องเมื่อเริ่มสแกน '
                          'และดาวน์โหลดเนื้อหาออฟไลน์ก่อน',
                      onTap: () => _openSettingsPage(
                        'practice/object-scanner',
                        const ObjectScannerScreen(),
                      ),
                    ),
                ],
              ),
            ),
            _deviceModelCard(),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'กำลังดำเนินการ โปรดรอสักครู่',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return PopScope(canPop: !_busy && !_calendarSaving, child: scaffold);
  }
}

enum _LocalSyncStatusPhase { loading, available, unavailable }

enum _DeviceModelStatusPhase { loading, available, unavailable }
