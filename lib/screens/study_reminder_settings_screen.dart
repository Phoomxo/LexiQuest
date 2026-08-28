import 'package:flutter/material.dart';

import '../features/reminders/application/study_reminder_use_cases.dart';
import '../features/reminders/domain/study_reminder.dart';
import '../features/reminders/domain/study_reminder_repository.dart';

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
    extends State<StudyReminderSettingsScreen> {
  final TextEditingController _scheduledAt = TextEditingController();
  final TextEditingController _timezone = TextEditingController(
    text: 'Asia/Bangkok',
  );
  final TextEditingController _quietStart = TextEditingController(text: '1320');
  final TextEditingController _quietEnd = TextEditingController(text: '420');
  Future<StudyReminder?>? _current;
  bool _submitting = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _current = widget.useCases.list().then(
      (reminders) => reminders
          .where(
            (reminder) =>
                reminder.source.stableIdentity == widget.source.stableIdentity,
          )
          .firstOrNull,
    );
  }

  Future<void> _optIn() async {
    if (_submitting || !widget.mutationAllowed()) return;
    setState(() {
      _submitting = true;
      _message = null;
    });
    try {
      final scheduled = DateTime.parse(_scheduledAt.text);
      if (!scheduled.isUtc || !_scheduledAt.text.endsWith('Z')) {
        throw const FormatException('UTC Z suffix required');
      }
      final start = int.parse(_quietStart.text);
      final end = int.parse(_quietEnd.text);
      if (start < 0 || start >= 24 * 60 || end < 0 || end >= 24 * 60) {
        throw const FormatException('quiet hours must be minutes of day');
      }
      final result = await widget.useCases.optIn(
        source: widget.source,
        scheduledAtUtc: scheduled,
        timezoneId: _timezone.text,
        quietHours: ReminderQuietHours(startMinutes: start, endMinutes: end),
        mutationAllowed: widget.mutationAllowed,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _message = switch (result) {
          StudyReminderOptInResult.scheduled => null,
          StudyReminderOptInResult.permissionDenied =>
            'Notifications are off. You can keep studying without reminders.',
          StudyReminderOptInResult.unavailable =>
            'Reminders are unavailable. Your learning goal is unchanged.',
          StudyReminderOptInResult.pendingRetry =>
            'Your choice is saved. We will reconcile it when notifications are available.',
          StudyReminderOptInResult.invalidSchedule =>
            'Choose a future time and a valid learning timezone.',
        };
        _reload();
      });
    } on StudyReminderMutationUnavailable {
      if (mounted) Navigator.of(context).maybePop();
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _message = 'Choose a future UTC time, timezone, and quiet hours.';
      });
    }
  }

  Future<void> _cancel(StudyReminder reminder) async {
    if (_submitting || !widget.mutationAllowed()) return;
    setState(() => _submitting = true);
    try {
      await widget.useCases.cancel(
        reminder.id,
        mutationAllowed: widget.mutationAllowed,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _message = 'Reminder off. Your learning goal is unchanged.';
        _reload();
      });
    } on StudyReminderMutationUnavailable {
      if (mounted) Navigator.of(context).maybePop();
    } on Object {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _scheduledAt.dispose();
    _timezone.dispose();
    _quietStart.dispose();
    _quietEnd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Study reminder')),
      body: FutureBuilder<StudyReminder?>(
        future: _current,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final reminder = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.sourceLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a gentle reminder for whenever study fits your day.',
              ),
              const SizedBox(height: 20),
              if (reminder?.isEnabled ?? false) ...[
                const Text('Reminder on'),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const ValueKey<String>('study-reminder/cancel'),
                  onPressed: _submitting ? null : () => _cancel(reminder!),
                  child: const Text('Turn off reminder'),
                ),
              ] else ...[
                TextField(
                  key: const ValueKey<String>('study-reminder/scheduled-at'),
                  controller: _scheduledAt,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Reminder time (UTC)',
                    hintText: '2026-08-29T02:00:00Z',
                  ),
                ),
                TextField(
                  key: const ValueKey<String>('study-reminder/timezone'),
                  controller: _timezone,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Learning timezone',
                  ),
                ),
                TextField(
                  key: const ValueKey<String>('study-reminder/quiet-start'),
                  controller: _quietStart,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quiet hours start (minutes after midnight)',
                  ),
                ),
                TextField(
                  key: const ValueKey<String>('study-reminder/quiet-end'),
                  controller: _quietEnd,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quiet hours end (minutes after midnight)',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey<String>('study-reminder/opt-in'),
                  onPressed: _submitting ? null : _optIn,
                  child: const Text('Turn on reminder'),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!),
              ],
            ],
          );
        },
      ),
    );
  }
}

bool _allowMutation() => true;
