import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';

import '../features/reminders/application/study_reminder_use_cases.dart';
import '../features/reminders/data/drift_study_reminder_repository.dart';
import '../features/reminders/domain/study_reminder.dart';
import '../features/reminders/domain/study_reminder_repository.dart';
import '../utils/local_study_datetime.dart';
import '../widgets/local_study_datetime_field.dart';
import '../widgets/study_time_picker.dart';

final class StudyReminderSettingsScreen extends StatefulWidget {
  const StudyReminderSettingsScreen({
    super.key,
    required this.useCases,
    required this.source,
    required this.sourceLabel,
    this.mutationAllowed = _allowMutation,
  });

  final StudyReminderUseCases useCases;
  final StudyReminderSource source;
  final String sourceLabel;
  final StudyReminderMutationGuard mutationAllowed;

  @override
  State<StudyReminderSettingsScreen> createState() =>
      _StudyReminderSettingsScreenState();
}

final class _StudyReminderSettingsScreenState
    extends State<StudyReminderSettingsScreen>
    with WidgetsBindingObserver {
  DateTime? _scheduledAtUtc;
  String _timezoneId = 'Asia/Bangkok';
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);
  StreamSubscription<Object?>? _ownerSubscription;
  final Set<Route<dynamic>> _pickerRoutes = {};
  void _capturePicker(Route<dynamic> route) {
    _pickerRoutes.removeWhere((candidate) => !candidate.isActive);
    _pickerRoutes.add(route);
  }

  void _retirePickers() {
    final routes = _pickerRoutes.toList();
    _pickerRoutes.clear();
    for (final route in routes) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
  }

  String? _owner;
  StudyReminderStatusSnapshot? _snapshot;
  bool _reading = false;
  bool _readFailed = false;
  bool _active = false;
  bool _exited = false;
  bool _foreground = true;
  bool _pickingQuiet = false;
  int _draftEpoch = 0;
  int _bindingEpoch = 0;
  bool _submitting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _observeOwner();
  }

  void _observeOwner() {
    _ownerSubscription?.cancel().ignore();
    final repository = widget.useCases.repository;
    if (repository is! DriftStudyReminderRepository) return;
    _ownerSubscription = repository.database
        .tableUpdates(TableUpdateQuery.onTable(repository.database.localOwners))
        .listen(
          (_) {
            if (!mounted || _exited) return;
            setState(() {
              _retire();
              _readFailed = true;
              // Hide private data until the canonical owner can be read again.
              // A same-owner transient failure keeps the draft for explicit retry.
              if (_visible) _reload();
            });
            _retirePickers();
          },
          onError: (Object error, StackTrace stack) {
            if (!mounted || _exited) return;
            setState(() {
              _retire();
              _readFailed = true;
            });
            _retirePickers();
          },
        );
  }

  bool get _visible =>
      mounted &&
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;

  bool _isCurrent(int epoch) =>
      mounted && epoch == _bindingEpoch && _active && _visible;

  void _retire() {
    ++_bindingEpoch;
    _reading = false;
    _submitting = false;
  }

  void _clearDraft() {
    ++_draftEpoch;
    _owner = null;
    _snapshot = null;
    _scheduledAtUtc = null;
    _timezoneId = 'Asia/Bangkok';
    _quietStart = const TimeOfDay(hour: 22, minute: 0);
    _quietEnd = const TimeOfDay(hour: 7, minute: 0);
    _message = null;
  }

  void _bind() {
    final active = _visible;
    if (active == _active) return;
    _retire();
    _active = active;
    if (active) _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  void _reload() {
    final useCases = widget.useCases;
    final source = widget.source;
    final epoch = ++_bindingEpoch;
    _reading = true;
    _readFailed = false;
    Future<void>.sync(() async {
      final owner = await useCases.repository.activeOwnerId();
      if (!_isCurrent(epoch)) return;
      if (_owner != null && _owner != owner) _clearDraft();
      final value = await useCases.loadStatus(
        expectedOwnerId: owner,
        source: source,
      );
      final latestOwner = await useCases.repository.activeOwnerId();
      if (!_isCurrent(epoch)) return;
      if (owner != latestOwner) throw const StudyReminderMutationUnavailable();
      setState(() {
        _reading = false;
        _readFailed = value.status == StudyReminderDisplayStatus.unavailable;
        if (!_readFailed) {
          _owner = owner;
          _snapshot = value;
        }
      });
    }).then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (!_isCurrent(epoch)) return;
        setState(() {
          _reading = false;
          _readFailed = true;
        });
      },
    );
  }

  void _retry(int epoch) {
    if (!_isCurrent(epoch) || _reading || _submitting) return;
    setState(_reload);
  }

  @override
  void didUpdateWidget(covariant StudyReminderSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.useCases, widget.useCases) ||
        oldWidget.source != widget.source ||
        !identical(oldWidget.mutationAllowed, widget.mutationAllowed)) {
      _retire();
      _clearDraft();
      WidgetsBinding.instance.addPostFrameCallback((_) => _retirePickers());
      _observeOwner();
      _active = _visible;
      if (_active) _reload();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exited) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _bind();
    });
  }

  void _exit() {
    _exited = true;
    _active = false;
    _retire();
  }

  @override
  void dispose() {
    _exit();
    _ownerSubscription?.cancel().ignore();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _optIn(int epoch) async {
    if (!_isCurrent(epoch) ||
        _reading ||
        _readFailed ||
        _submitting ||
        !widget.mutationAllowed())
      return;
    final useCases = widget.useCases;
    final source = widget.source;
    final mutationAllowed = widget.mutationAllowed;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final owner = _owner;
      if (owner == null) return;
      if (!_isCurrent(epoch)) return;
      final activeOwner = await useCases.repository.activeOwnerId();
      if (!_isCurrent(epoch)) return;
      if (owner != activeOwner) {
        throw const StudyReminderMutationUnavailable();
      }
      final scheduled = _scheduledAtUtc;
      if (scheduled == null) {
        throw const FormatException('Choose date and time');
      }
      final start = _quietStart.hour * 60 + _quietStart.minute;
      final end = _quietEnd.hour * 60 + _quietEnd.minute;
      final result = await useCases.optIn(
        expectedOwnerId: owner,
        source: source,
        scheduledAtUtc: scheduled,
        timezoneId: _timezoneId,
        quietHours: ReminderQuietHours(startMinutes: start, endMinutes: end),
        mutationAllowed: () => _isCurrent(epoch) && mutationAllowed(),
      );
      if (!_isCurrent(epoch)) return;
      final latestOwner = await useCases.repository.activeOwnerId();
      if (!_isCurrent(epoch)) return;
      if (owner != latestOwner) {
        throw const StudyReminderMutationUnavailable();
      }
      if (!_isCurrent(epoch)) return;
      setState(() {
        _submitting = false;
        _message = switch (result) {
          StudyReminderOptInResult.scheduled => null,
          StudyReminderOptInResult.permissionDenied =>
            'ปิดการแจ้งเตือนอยู่ คุณยังเรียนต่อได้ตามปกติ',
          StudyReminderOptInResult.unavailable =>
            'การเตือนไม่พร้อมใช้งาน เป้าหมายการเรียนไม่เปลี่ยนแปลง',
          StudyReminderOptInResult.pendingRetry =>
            'บันทึกตัวเลือกแล้ว ระบบจะตรวจและปรับสถานะเมื่อการแจ้งเตือนพร้อมใช้งาน',
          StudyReminderOptInResult.invalidSchedule =>
            'กรุณาเลือกเวลาในอนาคตและเขตเวลาเรียนที่ถูกต้อง',
        };
        _reload();
      });
    } on FormatException {
      if (!_isCurrent(epoch)) return;
      setState(() {
        _submitting = false;
        _message = 'กรุณาเลือกวันที่ เวลา เขตเวลา และช่วงงดเตือนให้ครบ';
      });
    } on StudyReminderMutationUnavailable {
      if (mounted && _isCurrent(epoch)) {
        setState(() {
          _submitting = false;
          _reload();
        });
      }
    } on Object {
      if (!_isCurrent(epoch)) return;
      setState(() {
        _submitting = false;
        _message =
            'ยังยืนยันผลไม่ได้ กำลังอ่านสถานะล่าสุด ไม่มีการส่งคำสั่งซ้ำ';
        _reload();
      });
    }
  }

  Future<void> _cancel(StudyReminder reminder, int epoch) async {
    if (!_isCurrent(epoch) ||
        _reading ||
        _readFailed ||
        _submitting ||
        !widget.mutationAllowed())
      return;
    final useCases = widget.useCases;
    final mutationAllowed = widget.mutationAllowed;
    setState(() => _submitting = true);
    try {
      final owner = _owner;
      if (owner == null) return;
      if (!_isCurrent(epoch)) return;
      final activeOwner = await useCases.repository.activeOwnerId();
      if (!_isCurrent(epoch)) return;
      if (owner != activeOwner) {
        throw const StudyReminderMutationUnavailable();
      }
      await useCases.cancel(
        reminder.id,
        mutationAllowed: () => _isCurrent(epoch) && mutationAllowed(),
      );
      if (!_isCurrent(epoch)) return;
      setState(() {
        _submitting = false;
        _message = 'ปิดการเตือนแล้ว เป้าหมายการเรียนไม่เปลี่ยนแปลง';
        _reload();
      });
    } on StudyReminderMutationUnavailable {
      if (mounted && _isCurrent(epoch)) {
        setState(() {
          _submitting = false;
          _reload();
        });
      }
    } on Object {
      if (_isCurrent(epoch))
        setState(() {
          _submitting = false;
          _message =
              'ยังยืนยันผลไม่ได้ กำลังอ่านสถานะล่าสุด ไม่มีการส่งคำสั่งซ้ำ';
          _reload();
        });
    }
  }

  Future<void> _pickQuiet(bool start, int epoch) async {
    if (!_isCurrent(epoch) ||
        _reading ||
        _readFailed ||
        _submitting ||
        _pickingQuiet)
      return;
    _pickingQuiet = true;
    final draftEpoch = _draftEpoch;
    final picked = await showStudyTimePicker(
      context: context,
      initialTime: start ? _quietStart : _quietEnd,
      helpText: start ? 'เริ่มช่วงงดเตือน' : 'สิ้นสุดช่วงงดเตือน',
      onPickerRoute: _capturePicker,
    );
    _pickingQuiet = false;
    if (!_visible || draftEpoch != _draftEpoch || picked == null || _submitting)
      return;
    setState(() {
      if (start) {
        _quietStart = picked;
      } else {
        _quietEnd = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final epoch = _bindingEpoch;
    final draftEpoch = _draftEpoch;
    final ready = _active && !_reading && !_readFailed && _snapshot != null;
    final reminder = _snapshot?.reminder;
    final status = _snapshot?.status ?? StudyReminderDisplayStatus.unavailable;
    final statusMessage = _statusMessage(status);
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('เตือนเวลาเรียน')),
        body: Stack(
          children: [
            if (_owner != null)
              Offstage(
                offstage: !ready,
                child: KeyedSubtree(
                  key: ValueKey(_draftEpoch),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          widget.sourceLabel,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('เลือกเวลาเตือนเรียนที่เหมาะกับกิจวัตรของคุณ'),
                      const SizedBox(height: 24),
                      if (reminder?.isEnabled ?? false) ...[
                        Text(
                          statusMessage ?? 'เปิดการเตือนแล้ว',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'เวลาที่เลือก: ${formatLocalStudyDateTime(reminder!.scheduledAtUtc, reminder.timezone.timezoneId)}',
                        ),
                        Text(
                          'เวลาแจ้งเตือนที่ตั้งไว้: ${formatLocalStudyDateTime(reminder.effectiveScheduledAtUtc, reminder.timezone.timezoneId)}',
                        ),
                        if (reminder.quietHours != null)
                          Text(
                            'ช่วงงดเตือน ${formatStudyClockMinutes(reminder.quietHours!.startMinutes)}–${formatStudyClockMinutes(reminder.quietHours!.endMinutes)}',
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          key: const ValueKey<String>('study-reminder/cancel'),
                          onPressed: _submitting
                              ? null
                              : () => _cancel(reminder, epoch),
                          child: const Text('ปิดการเตือน'),
                        ),
                      ] else ...[
                        if (statusMessage != null) ...[
                          Text(statusMessage),
                          const SizedBox(height: 12),
                        ],
                        const Text('เตือนครั้งเดียวตามวันและเวลาที่เลือก'),
                        const SizedBox(height: 12),
                        LocalStudyDateTimeField(
                          fieldKey: 'study-reminder/scheduled-at',
                          onPickerRoute: _capturePicker,
                          referenceUtc: widget.useCases.nowUtc(),
                          initialUtc: _scheduledAtUtc,
                          initialTimezoneId: _timezoneId,
                          enabled: !_submitting,
                          onChanged: (instant, zone) {
                            if (!_visible ||
                                draftEpoch != _draftEpoch ||
                                _submitting)
                              return;
                            _scheduledAtUtc = instant;
                            _timezoneId = zone;
                          },
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          key: const ValueKey<String>(
                            'study-reminder/quiet-start',
                          ),
                          onPressed: _submitting
                              ? null
                              : () => _pickQuiet(true, epoch),
                          child: Text(
                            'เริ่มช่วงงดเตือน ${formatStudyClockMinutes(_quietStart.hour * 60 + _quietStart.minute)}',
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: const ValueKey<String>(
                            'study-reminder/quiet-end',
                          ),
                          onPressed: _submitting
                              ? null
                              : () => _pickQuiet(false, epoch),
                          child: Text(
                            'สิ้นสุดช่วงงดเตือน ${formatStudyClockMinutes(_quietEnd.hour * 60 + _quietEnd.minute)}',
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          key: const ValueKey<String>('study-reminder/opt-in'),
                          onPressed: _submitting ? null : () => _optIn(epoch),
                          child: const Text('เปิดการเตือน'),
                        ),
                      ],
                      if (_message != null && _message != statusMessage) ...[
                        const SizedBox(height: 12),
                        Text(_message!),
                      ],
                    ],
                  ),
                ),
              ),
            if (!ready && _reading)
              const Center(child: CircularProgressIndicator()),
            if (!ready && _readFailed)
              ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'ยังอ่านสถานะการเตือนไม่ได้ ลองอ่านใหม่ได้โดยไม่เปิดหรือปิดการเตือน',
                    ),
                  ),
                  OutlinedButton(
                    key: const ValueKey('study-reminder/retry'),
                    onPressed: () => _retry(epoch),
                    child: const Text('ลองอ่านใหม่'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String? _statusMessage(StudyReminderDisplayStatus status) => switch (status) {
  StudyReminderDisplayStatus.disabled => null,
  StudyReminderDisplayStatus.scheduled => null,
  StudyReminderDisplayStatus.pendingRetry =>
    'บันทึกตัวเลือกแล้ว ระบบจะตรวจและปรับสถานะเมื่อการแจ้งเตือนพร้อมใช้งาน',
  StudyReminderDisplayStatus.permissionDenied =>
    'ปิดการแจ้งเตือนอยู่ คุณยังเรียนต่อได้ตามปกติ',
  StudyReminderDisplayStatus.unavailable =>
    'การเตือนไม่พร้อมใช้งาน เป้าหมายการเรียนไม่เปลี่ยนแปลง',
  StudyReminderDisplayStatus.elapsed =>
    'ถึงเวลาที่เลือกแล้ว ยังไม่มีข้อมูลยืนยันว่าการแจ้งเตือนแสดงแล้ว',
};

bool _allowMutation() => true;
