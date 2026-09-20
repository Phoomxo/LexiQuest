import 'package:flutter/material.dart';

import '../features/reminders/application/study_reminder_use_cases.dart';
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
  late Future<String> _openingOwner;
  Future<StudyReminderStatusSnapshot>? _current;
  int _bindingEpoch = 0;
  bool _submitting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bind();
  }

  void _bind() {
    _bindingEpoch++;
    _openingOwner = widget.useCases.repository.activeOwnerId();
    _reload();
  }

  void _reload() {
    final useCases = widget.useCases;
    final source = widget.source;
    final epoch = _bindingEpoch;
    _current = _openingOwner.then((ownerId) {
      if (!_isCurrent(epoch)) throw const StudyReminderMutationUnavailable();
      return useCases.loadStatus(expectedOwnerId: ownerId, source: source);
    });
  }

  bool _isCurrent(int epoch) => mounted && epoch == _bindingEpoch;

  @override
  void didUpdateWidget(covariant StudyReminderSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.useCases, widget.useCases) ||
        oldWidget.source != widget.source) {
      _submitting = false;
      _message = null;
      _scheduledAtUtc = null;
      _timezoneId = 'Asia/Bangkok';
      _bind();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {
        _message = null;
        _reload();
      });
    }
  }

  @override
  void dispose() {
    _bindingEpoch++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _optIn() async {
    if (_submitting || !widget.mutationAllowed()) return;
    final epoch = _bindingEpoch;
    final useCases = widget.useCases;
    final source = widget.source;
    final mutationAllowed = widget.mutationAllowed;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final owner = await _openingOwner;
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
    } on StudyReminderMutationUnavailable {
      if (mounted && _isCurrent(epoch)) {
        Navigator.of(context).maybePop();
      }
    } on Object {
      if (!_isCurrent(epoch)) return;
      setState(() {
        _submitting = false;
        _message = 'กรุณาเลือกวันที่ เวลา เขตเวลา และช่วงงดเตือนให้ครบ';
      });
    }
  }

  Future<void> _cancel(StudyReminder reminder) async {
    if (_submitting || !widget.mutationAllowed()) return;
    final epoch = _bindingEpoch;
    final useCases = widget.useCases;
    final mutationAllowed = widget.mutationAllowed;
    setState(() => _submitting = true);
    try {
      final owner = await _openingOwner;
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
        Navigator.of(context).maybePop();
      }
    } on Object {
      if (_isCurrent(epoch)) setState(() => _submitting = false);
    }
  }

  Future<void> _pickQuiet(bool start) async {
    final epoch = _bindingEpoch;
    final picked = await showStudyTimePicker(
      context: context,
      initialTime: start ? _quietStart : _quietEnd,
      helpText: start ? 'เริ่มช่วงงดเตือน' : 'สิ้นสุดช่วงงดเตือน',
    );
    if (!_isCurrent(epoch) || picked == null || _submitting) return;
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
    return Scaffold(
      appBar: AppBar(title: const Text('เตือนเวลาเรียน')),
      body: FutureBuilder<StudyReminderStatusSnapshot>(
        future: _current,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final reminder = snapshot.data?.reminder;
          final status =
              snapshot.data?.status ?? StudyReminderDisplayStatus.unavailable;
          final statusMessage = _statusMessage(status);
          return ListView(
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
                  onPressed: _submitting ? null : () => _cancel(reminder),
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
                  referenceUtc: widget.useCases.nowUtc(),
                  initialUtc: _scheduledAtUtc,
                  initialTimezoneId: _timezoneId,
                  enabled: !_submitting,
                  onChanged: (instant, zone) {
                    _scheduledAtUtc = instant;
                    _timezoneId = zone;
                  },
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  key: const ValueKey<String>('study-reminder/quiet-start'),
                  onPressed: _submitting ? null : () => _pickQuiet(true),
                  child: Text(
                    'เริ่มช่วงงดเตือน ${formatStudyClockMinutes(_quietStart.hour * 60 + _quietStart.minute)}',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey<String>('study-reminder/quiet-end'),
                  onPressed: _submitting ? null : () => _pickQuiet(false),
                  child: Text(
                    'สิ้นสุดช่วงงดเตือน ${formatStudyClockMinutes(_quietEnd.hour * 60 + _quietEnd.minute)}',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const ValueKey<String>('study-reminder/opt-in'),
                  onPressed: _submitting ? null : _optIn,
                  child: const Text('เปิดการเตือน'),
                ),
              ],
              if (_message != null && _message != statusMessage) ...[
                const SizedBox(height: 12),
                Text(_message!),
              ],
            ],
          );
        },
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
