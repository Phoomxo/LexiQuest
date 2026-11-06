import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../widgets/adaptive_content_pane.dart';
import '../../learning_profile/presentation/learning_timezone_picker.dart';
import '../application/study_reminder_runtime.dart';
import '../domain/study_reminder.dart';

class StudyReminderSettingsScreen extends StatefulWidget {
  const StudyReminderSettingsScreen({
    super.key,
    required this.runtime,
    required this.ownerId,
  });
  final StudyReminderRuntime runtime;
  final String ownerId;
  @override
  State<StudyReminderSettingsScreen> createState() =>
      _StudyReminderSettingsScreenState();
}

class _StudyReminderSettingsScreenState
    extends State<StudyReminderSettingsScreen>
    with WidgetsBindingObserver {
  static const _retiredMessage =
      'พื้นที่ข้อมูลหรือหน้าจอเปลี่ยนแล้ว โปรดกลับไปเปิดการเตือนใหม่';

  StreamSubscription<void>? _changes;
  Completer<void>? _zonePickerRetirement;
  StudyReminderView? _view;
  StudyReminderChangeIntent? _pending;
  ModalRoute<dynamic>? _route;
  AppDependencies? _dependencies;
  var _bound = false, _retired = false, _busy = false, _loading = true;
  var _foreground = true, _choosing = false, _enabled = false;
  var _generation = 0, _read = 0;
  int? _minute;
  String? _zone, _status;

  bool _current(int generation) =>
      mounted &&
      !_retired &&
      generation == _generation &&
      ((_foreground && widget.runtime.isForeground) ||
          (_busy && widget.runtime.isRequestingPermission)) &&
      ((_route?.isCurrent ?? true) || _choosing) &&
      !widget.runtime.isRetired &&
      widget.runtime.currentOwnerId == widget.ownerId;
  bool _writeCurrent(int generation) =>
      _current(generation) && !_choosing && (_route?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.runtime.watchChanges().listen(
      (_) {
        if (!mounted || _retired) return;
        if (widget.runtime.isRetired ||
            widget.runtime.currentOwnerId != widget.ownerId) {
          setState(_retire);
        } else if (!_busy &&
            _foreground &&
            widget.runtime.isForeground &&
            (_route?.isCurrent ?? true)) {
          unawaited(_load(resetDraft: false));
        }
      },
      onError: (Object _) {
        if (mounted) setState(_retire);
      },
      onDone: () {
        if (mounted) setState(_retire);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    if (_zonePickerRetirement?.isCompleted == false) {
      _zonePickerRetirement!.complete();
    }
    _generation++;
    _read++;
    _pending = null;
    _view = null;
    _busy = false;
    _loading = false;
    _minute = null;
    _zone = null;
    _enabled = false;
    _status = _retiredMessage;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    ModalRoute.isCurrentOf(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    if ((_bound && !identical(dependencies, _dependencies)) ||
        (dependencies != null &&
            !identical(dependencies.studyReminders, widget.runtime)) ||
        (_route?.isCurrent == false && !_choosing)) {
      _retire();
    }
    _bound = true;
    _dependencies = dependencies;
  }

  @override
  void didUpdateWidget(StudyReminderSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime) ||
        oldWidget.ownerId != widget.ownerId) {
      _retire();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground &&
        !_retired &&
        !(_busy && widget.runtime.isRequestingPermission) &&
        mounted) {
      setState(() {
        _generation++;
        _read++;
        _loading = true;
        if (_zonePickerRetirement?.isCompleted == false) {
          _zonePickerRetirement!.complete();
        }
      });
    } else if (_foreground && !_busy && !_retired) {
      unawaited(_load(resetDraft: false));
    }
  }

  Future<void> _load({bool resetDraft = true}) async {
    final generation = _generation, read = ++_read;
    bool current() => _current(generation) && read == _read;
    try {
      final view = await widget.runtime.load(
        expectedOwnerId: widget.ownerId,
        stillCurrent: current,
      );
      if (!current()) return;
      final initializeDraft = resetDraft || _view == null;
      setState(() {
        _view = view;
        _loading = false;
        if (initializeDraft) {
          _enabled = view.setting.enabled;
          _minute = view.setting.minuteOfDay;
          _zone = view.setting.timezoneId;
          _pending = null;
        }
      });
    } on Object {
      if (!current()) return;
      setState(() {
        _loading = false;
        _status = 'อ่านการเตือนไม่ได้ ลองเปิดหน้านี้ใหม่';
      });
    }
  }

  void _edited(int generation, VoidCallback change) {
    if (_busy ||
        _loading ||
        !_current(generation) ||
        _route?.isCurrent == false) {
      return;
    }
    setState(() {
      change();
      _pending = null;
      _status = null;
    });
  }

  Future<void> _chooseTime(int generation) async {
    if (!_current(generation) || _busy || _loading || _choosing) return;
    _choosing = true;
    try {
      final result = await showTimePicker(
        context: context,
        initialTime: _minute == null
            ? TimeOfDay.now()
            : TimeOfDay(hour: _minute! ~/ 60, minute: _minute! % 60),
      );
      if (_current(generation) && result != null) {
        _edited(generation, () {
          _minute = result.hour * 60 + result.minute;
        });
      }
    } finally {
      _choosing = false;
    }
  }

  Future<void> _chooseZone(int generation) async {
    if (!_current(generation) || _busy || _loading || _choosing) return;
    _choosing = true;
    final retirement = _zonePickerRetirement = Completer<void>();
    try {
      final result = await Navigator.of(context)
          .push<LearningTimezoneSelection>(
            MaterialPageRoute(
              builder: (_) => FutureBuilder<void>(
                future: retirement.future,
                builder: (_, _) => _current(generation)
                    ? LearningTimezonePicker(
                        selected: _zone,
                        stillCurrent: () => _current(generation),
                      )
                    : Scaffold(
                        appBar: AppBar(),
                        body: const Center(child: Text(_retiredMessage)),
                      ),
              ),
            ),
          );
      final zone = result?.timezoneId;
      if (_current(generation) && zone != null) {
        _edited(generation, () {
          _zone = zone;
        });
      }
    } finally {
      _zonePickerRetirement = null;
      _choosing = false;
    }
  }

  Future<void> _save(int generation) async {
    if (!_writeCurrent(generation) || _busy || _loading || _view == null) {
      return;
    }
    if (_minute == null || _zone == null) {
      setState(() {
        _status = 'เลือกเวลาและเขตเวลาก่อนบันทึก';
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final pending = _pending;
      final intent = pending == null
          ? await widget.runtime.prepareChange(
              expectedOwnerId: widget.ownerId,
              choice: StudyReminderChoice(
                enabled: _enabled,
                minuteOfDay: _minute!,
                timezoneId: _zone!,
              ),
              stillCurrent: () => _writeCurrent(generation),
            )
          : await widget.runtime.renewChange(
              pending,
              stillCurrent: () => _writeCurrent(generation),
            );
      if (!_writeCurrent(generation)) return;
      _pending = intent;
      final view = await widget.runtime.apply(intent);
      if (!_current(generation)) return;
      setState(() {
        _view = view;
        _pending = null;
        _status = view.setting.enabled
            ? 'บันทึกแล้ว ระบบรับคำขอเตือนรอบถัดไปแล้ว เวลาอาจคลาดเคลื่อนตามอุปกรณ์'
            : 'บันทึกการปิดแล้ว ระบบรับคำขอยกเลิกการเตือนแล้ว';
      });
    } on StudyReminderException catch (failure) {
      if (!_current(generation)) return;
      setState(() {
        _status = switch (failure.code) {
          StudyReminderFailureCode.permissionDenied =>
            'ยังไม่ได้รับสิทธิ์แจ้งเตือน จึงยังไม่เปิดการเตือน',
          StudyReminderFailureCode.platformUnavailable =>
            'อุปกรณ์นี้ยังไม่รองรับการเตือนผ่านแอป',
          StudyReminderFailureCode.requestUnconfirmed =>
            'บันทึกค่าที่เลือกแล้ว แต่ยังยืนยันคำขอของระบบไม่ได้ กดบันทึกเพื่อลองคำขอเดิมอีกครั้ง',
          StudyReminderFailureCode.staleRevision =>
            'การตั้งค่าเปลี่ยนแล้ว โปรดเปิดหน้านี้ใหม่ก่อนบันทึก',
          _ => 'บันทึกไม่ได้ โปรดกลับไปเปิดการเตือนใหม่',
        };
        if (failure.code == StudyReminderFailureCode.staleRevision) {
          _pending = null;
        }
      });
    } on Object {
      if (_current(generation)) {
        setState(() {
          _status = 'บันทึกไม่ได้ โปรดลองใหม่';
        });
      }
    } finally {
      if (mounted && !_retired) {
        setState(() {
          _busy = false;
        });
        if (_foreground && widget.runtime.isForeground) {
          unawaited(_load(resetDraft: false));
        }
      }
    }
  }

  @override
  void dispose() {
    _retire();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final generation = _generation;
    final editable =
        _writeCurrent(generation) && !_busy && !_loading && view != null;
    final time = _minute == null
        ? 'เลือกเวลา'
        : TimeOfDay(
            hour: _minute! ~/ 60,
            minute: _minute! % 60,
          ).format(context);
    return Scaffold(
      appBar: AppBar(title: const Text('เตือนทบทวน')),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.formMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'เวลาสั้น ๆ สำหรับคำศัพท์',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'เลือกเวลาที่เหมาะกับคุณ การเตือนเริ่มเมื่อคุณเปิดและบันทึกเท่านั้น',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (view != null) ...[
              const SizedBox(height: 20),
              Text(
                view.setting.enabled
                    ? 'ค่าที่บันทึก: เปิดการเตือน'
                    : 'ค่าที่บันทึก: ปิดการเตือน',
                key: const Key('reminder-saved-state'),
              ),
              const SizedBox(height: 8),
              Text(
                !view.platform.supported
                    ? 'สถานะอุปกรณ์: ยังไม่รองรับการเตือนผ่านแอป'
                    : view.platform.notificationsAllowed
                    ? 'สิทธิ์แจ้งเตือนบนอุปกรณ์: อนุญาต'
                    : 'สิทธิ์แจ้งเตือนบนอุปกรณ์: ยังไม่อนุญาต',
              ),
            ],
            const SizedBox(height: 20),
            SwitchListTile.adaptive(
              key: const Key('reminder-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('เปิดการเตือนทุกวัน'),
              value: _enabled,
              onChanged:
                  editable && (view.platform.supported == true || _enabled)
                  ? (value) => _edited(generation, () {
                      _enabled = value;
                    })
                  : null,
            ),
            OutlinedButton.icon(
              key: const Key('reminder-time'),
              onPressed: editable ? () => _chooseTime(generation) : null,
              icon: const Icon(Icons.schedule),
              label: Text(time),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('reminder-zone'),
              onPressed: editable ? () => _chooseZone(generation) : null,
              icon: const Icon(Icons.public),
              label: Text(_zone ?? 'เลือกเขตเวลา'),
            ),
            const SizedBox(height: 20),
            const Text(
              'แสดงเพียงข้อความชวนทบทวนทั่วไป การประหยัดแบตเตอรี่และการตั้งค่าอุปกรณ์อาจทำให้แจ้งเตือนช้าหรือไม่แสดง การรับคำขอไม่ใช่หลักฐานว่าส่งถึงแล้ว',
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Semantics(liveRegion: true, child: Text(_status!)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('reminder-save'),
              onPressed: editable ? () => _save(generation) : null,
              child: Text(
                _busy
                    ? 'กำลังบันทึก…'
                    : _pending != null
                    ? 'ลองคำขอเดิมอีกครั้ง'
                    : 'บันทึกการเตือน',
              ),
            ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
              child: const Text('กลับ'),
            ),
          ],
        ),
      ),
    );
  }
}
