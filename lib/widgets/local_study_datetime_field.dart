import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../utils/local_study_datetime.dart';
import 'study_time_picker.dart';

/// Editing is ephemeral. No callback produces an instant until both clocks
/// are chosen, and ambiguous clocks require an explicit offset selection.
final class LocalStudyDateTimeField extends StatefulWidget {
  const LocalStudyDateTimeField({
    super.key,
    required this.fieldKey,
    required this.onChanged,
    required this.referenceUtc,
    this.initialUtc,
    this.initialTimezoneId = 'Asia/Bangkok',
    this.enabled = true,
    this.onPickerRoute,
  });

  final String fieldKey;
  final void Function(DateTime? instantUtc, String timezoneId) onChanged;
  final DateTime referenceUtc;
  final DateTime? initialUtc;
  final String initialTimezoneId;
  final bool enabled;
  final ValueChanged<Route<dynamic>>? onPickerRoute;

  @override
  State<LocalStudyDateTimeField> createState() =>
      _LocalStudyDateTimeFieldState();
}

final class _LocalStudyDateTimeFieldState
    extends State<LocalStudyDateTimeField> {
  late String _zone;
  DateTime? _date;
  TimeOfDay? _time;
  DateTime? _selected;
  List<DateTime> _candidates = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    ensureStudyTimeZones();
    _zone = widget.initialTimezoneId;
    _selected = widget.initialUtc;
    if (_selected != null) {
      final local = studyLocalDateTime(_selected!, _zone);
      _date = DateTime.utc(local.year, local.month, local.day);
      _time = TimeOfDay(hour: local.hour, minute: local.minute);
    }
  }

  void _resolve() {
    _selected = null;
    _candidates = [];
    _error = null;
    if (_date != null && _time != null) {
      _candidates = resolveLocalStudyDateTime(
        // UTC carries calendar fields only here, before IANA resolution.
        // Host-local DateTime can normalize a device DST gap prematurely.
        DateTime.utc(
          _date!.year,
          _date!.month,
          _date!.day,
          _time!.hour,
          _time!.minute,
        ),
        _zone,
      );
      if (_candidates.isEmpty) {
        _error = 'เวลานี้ไม่มีในเขตเวลานี้ กรุณาเลือกใหม่';
      } else if (_candidates.length == 1) {
        _selected = _candidates.single;
      }
    }
    widget.onChanged(_selected, _zone);
  }

  Future<void> _pickDate() async {
    final local = studyLocalDateTime(widget.referenceUtc, _zone);
    final picked = await showDatePicker(
      context: context,
      initialEntryMode: DatePickerEntryMode.input,
      initialDate: _date ?? DateTime.utc(local.year, local.month, local.day),
      firstDate: DateTime.utc(1900),
      lastDate: DateTime.utc(2200),
      helpText: 'เลือกวันที่ · ใช้ปี ค.ศ. เช่น 2026',
      fieldLabelText: 'วันที่ (ปี ค.ศ.)',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
      builder: (context, child) {
        final route = ModalRoute.of(context);
        if (route != null) widget.onPickerRoute?.call(route);
        return child!;
      },
    );
    if (!mounted || picked == null || !widget.enabled) return;
    setState(() {
      _date = DateTime.utc(picked.year, picked.month, picked.day);
      _resolve();
    });
  }

  Future<void> _pickTime() async {
    final local = studyLocalDateTime(widget.referenceUtc, _zone);
    final picked = await showStudyTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay(hour: local.hour, minute: local.minute),
      helpText: 'เลือกเวลา',
      onPickerRoute: widget.onPickerRoute,
    );
    if (!mounted || picked == null || !widget.enabled) return;
    setState(() {
      _time = picked;
      _resolve();
    });
  }

  Future<void> _pickZone() async {
    var query = '';
    final zones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    final picked = await showDialog<String>(
      context: context,
      builder: (context) {
        final route = ModalRoute.of(context);
        if (route != null) widget.onPickerRoute?.call(route);
        return StatefulBuilder(
          builder: (context, update) {
            final filtered = zones
                .where(
                  (zone) => '${studyTimezoneLabel(zone)} $zone'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
                )
                .toList();
            return AlertDialog(
              title: const Text('เขตเวลาเรียน'),
              content: SizedBox(
                width: 360,
                height: 360,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'ค้นหาประเทศหรือเมือง',
                      ),
                      onChanged: (value) => update(() => query = value),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(studyTimezoneLabel(filtered[index])),
                          subtitle: Text(filtered[index]),
                          onTap: () => Navigator.pop(context, filtered[index]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || picked == null || !widget.enabled) return;
    setState(() {
      _zone = picked;
      _resolve();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        key: ValueKey('${widget.fieldKey}/date'),
        onPressed: widget.enabled ? _pickDate : null,
        icon: const Icon(Icons.calendar_month),
        label: Text(
          _date == null ? 'เลือกวันที่' : formatStudyCalendarDate(_date!),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: ValueKey('${widget.fieldKey}/time'),
        onPressed: widget.enabled ? _pickTime : null,
        icon: const Icon(Icons.schedule),
        label: Text(
          _time == null
              ? 'เลือกเวลา'
              : formatStudyClockMinutes(_time!.hour * 60 + _time!.minute),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: ValueKey('${widget.fieldKey}/timezone'),
        onPressed: widget.enabled ? _pickZone : null,
        child: Text('เขตเวลา: ${studyTimezoneLabel(_zone)}'),
      ),
      if (_candidates.length > 1) ...[
        const SizedBox(height: 8),
        const Text('เวลานี้เกิดขึ้นสองครั้ง กรุณาเลือกเวลาและ UTC offset'),
        for (final candidate in _candidates)
          OutlinedButton(
            key: ValueKey(
              '${widget.fieldKey}/fold/${candidate.toIso8601String()}',
            ),
            onPressed: widget.enabled
                ? () => setState(() {
                    _selected = candidate;
                    widget.onChanged(candidate, _zone);
                  })
                : null,
            child: Text(
              '${_selected == candidate ? '✓ ' : ''}${formatLocalStudyDateTime(candidate, _zone)}',
            ),
          ),
      ],
      if (_selected != null) ...[
        const SizedBox(height: 8),
        Text(formatLocalStudyDateTime(_selected!, _zone)),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );
}
