import 'dart:async';

import 'package:flutter/material.dart';

import '../runtime/app_dependencies.dart';
import '../services/study_reminders.dart';

Future<void> showStudyReminders(
  BuildContext context, {
  required String expectedOwnerId,
}) async {
  final scope = AppDependenciesScope.maybeOf(context);
  final owners = scope?.localOwners;
  if (scope == null || scope.studyReminders == null || owners == null) {
    return;
  }
  try {
    final owner = await owners.getOrCreateActiveOwner();
    if (!context.mounted ||
        !identical(AppDependenciesScope.maybeOf(context), scope) ||
        ModalRoute.of(context)?.isCurrent != true ||
        owner.id != expectedOwnerId) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: StudyReminderPanel(scope: scope, ownerId: owner.id),
      ),
    );
  } catch (_) {
    if (context.mounted &&
        identical(AppDependenciesScope.maybeOf(context), scope) &&
        ModalRoute.of(context)?.isCurrent == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดการเตือนฝึกไม่สำเร็จ กรุณาลองใหม่')),
      );
    }
  }
}

class StudyReminderPanel extends StatefulWidget {
  const StudyReminderPanel({
    super.key,
    required this.scope,
    required this.ownerId,
  });

  final AppDependencies scope;
  final String ownerId;

  @override
  State<StudyReminderPanel> createState() => _StudyReminderPanelState();
}

class _StudyReminderPanelState extends State<StudyReminderPanel>
    with WidgetsBindingObserver {
  StudyReminderStatus? _status;
  StudyReminderPreset? _selected;
  StreamSubscription<String?>? _ownerChanges;
  bool _active = false;
  bool _invalidated = false;
  bool _loaded = false;
  bool _loading = true;
  bool _busy = false;
  bool _refreshAfterWrite = false;
  int _generation = 0;
  String? _error;

  bool get _sameScope =>
      mounted &&
      !_invalidated &&
      identical(AppDependenciesScope.maybeOf(context), widget.scope);

  bool get _isCurrent =>
      _sameScope && ModalRoute.of(context)?.isCurrent == true;

  bool _accept(int generation) => _isCurrent && generation == _generation;

  bool _bound(int generation) => _sameScope && generation == _generation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownerChanges = widget.scope.watchActiveOwnerId()?.listen((ownerId) {
      if (ownerId != widget.ownerId) {
        _invalidate();
      }
    }, onError: (Object _) => _invalidate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sameScope) {
      _invalidated = true;
      _generation++;
      _status = null;
      _selected = null;
      _active = false;
      _loading = false;
    } else if (!_loaded) {
      _loaded = true;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant StudyReminderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scope, widget.scope) ||
        oldWidget.ownerId != widget.ownerId) {
      _invalidate();
    }
  }

  void _invalidate() {
    if (!mounted || _invalidated) {
      return;
    }
    _generation++;
    setState(() {
      _invalidated = true;
      _active = false;
      _status = null;
      _selected = null;
      _loading = false;
      _busy = false;
      _error = null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_isCurrent) {
      return;
    }
    if (_busy) {
      _refreshAfterWrite = true;
    } else {
      unawaited(_load());
    }
  }

  Future<bool> _requireOwner(int generation) async {
    if (!_accept(generation)) {
      return false;
    }
    final owners = widget.scope.localOwners;
    if (owners == null) {
      throw StateError('Reminder owner unavailable');
    }
    final owner = await owners.getOrCreateActiveOwner();
    if (!_accept(generation)) {
      return false;
    }
    if (owner.id != widget.ownerId) {
      _invalidate();
      return false;
    }
    return true;
  }

  Future<void> _load() async {
    if (!_isCurrent || _busy) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await _requireOwner(generation)) {
        return;
      }
      final reminders = widget.scope.studyReminders;
      if (reminders == null) {
        throw StateError('Reminders unavailable');
      }
      final status = await reminders.status(ownerId: widget.ownerId);
      if (!await _requireOwner(generation)) {
        return;
      }
      setState(() {
        _active = true;
        _status = status;
        _selected ??= status.preset;
      });
    } catch (_) {
      if (_accept(generation)) {
        setState(() {
          _status = null;
          _error = 'ตรวจสถานะการเตือนไม่สำเร็จ กรุณาลองใหม่';
        });
      }
    } finally {
      if (_bound(generation)) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _change({required bool enable}) async {
    if (!_isCurrent || !_active || _busy || _loading || _status == null) {
      return;
    }
    final preset = _selected;
    if (enable && preset == null) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _requireOwner(generation)) {
        return;
      }
      final reminders = widget.scope.studyReminders!;
      final status = enable
          ? await reminders.enable(
              ownerId: widget.ownerId,
              preset: preset!,
              isCurrent: () => _accept(generation) && _active,
            )
          : await reminders.disable(ownerId: widget.ownerId);
      if (!await _requireOwner(generation)) {
        return;
      }
      setState(() => _status = status);
    } catch (_) {
      if (_bound(generation)) {
        setState(() {
          _status = null;
          _error = 'ยังยืนยันการเปลี่ยนการเตือนไม่ได้ กรุณาตรวจสถานะอีกครั้ง';
        });
      }
    } finally {
      if (_bound(generation)) {
        setState(() {
          _busy = false;
          if (!_isCurrent) {
            _status = null;
            _error = 'กรุณาตรวจสถานะการเตือนอีกครั้ง';
          }
        });
        if (_refreshAfterWrite && _isCurrent) {
          _refreshAfterWrite = false;
          unawaited(_load());
        }
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_ownerChanges?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final available = _sameScope && widget.scope.studyReminders != null;
    final canChange =
        available && _active && !_loading && !_busy && status != null;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'เตือนให้กลับมาฝึก',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (!available)
            const Text(
              'บัญชีหรือการตั้งค่าของแอปเปลี่ยนแล้ว กรุณากลับไปเปิดใหม่',
            )
          else ...[
            if (_loading || _busy)
              const LinearProgressIndicator(
                semanticsLabel: 'กำลังตรวจการเตือน',
              ),
            if (status != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  !status.allowed
                      ? 'ยังไม่ได้รับอนุญาตให้แจ้งเตือน'
                      : status.preset == null
                      ? 'ปิดการเตือนอยู่'
                      : 'เปิดการเตือนแล้ว',
                ),
              ),
              if (status.preset case final saved?)
                Text('เวลาที่บันทึกไว้: ${_presetLabel(saved)}'),
              if (!status.allowed && status.preset != null)
                const Text(
                  'ยังเก็บเวลาที่เลือกไว้ แต่ระบบไม่อนุญาตให้แจ้งเตือน',
                ),
            ],
            const SizedBox(height: 16),
            const Text(
              'เลือกช่วงที่สะดวก การเตือนจะเปิดเมื่อคุณยืนยันและระบบอนุญาต',
            ),
            const SizedBox(height: 8),
            if (status != null && !_loading)
              for (final preset in StudyReminderPreset.values) ...[
                Semantics(
                  selected: _selected == preset,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: canChange
                        ? () => setState(() => _selected = preset)
                        : null,
                    icon: Icon(
                      _selected == preset
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                    ),
                    label: Text(_presetLabel(preset)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            const Text(
              'ใช้วันและเวลาตามเขตเวลาของเครื่อง ระบบอาจแจ้งเตือนช้ากว่าเวลาที่เลือก เช่น เมื่อประหยัดแบตเตอรี่',
            ),
            const SizedBox(height: 8),
            const Text('เรียนต่อได้ตามปกติเมื่อไม่อนุญาตหรือปิดการเตือน'),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(error)),
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('ตรวจสถานะอีกครั้ง'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: canChange && _selected != null
                  ? () => _change(enable: true)
                  : null,
              child: const Text('อนุญาตให้เตือน'),
            ),
            if (status?.preset != null)
              TextButton(
                onPressed: canChange ? () => _change(enable: false) : null,
                child: const Text('ปิดการเตือน'),
              ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              if (ModalRoute.of(context)?.isCurrent == true) {
                Navigator.pop(context);
              }
            },
            child: const Text('กลับไปแผนฝึก'),
          ),
        ],
      ),
    );
  }
}

String _presetLabel(StudyReminderPreset preset) => switch (preset) {
  StudyReminderPreset.weekdaysEvening => 'จันทร์ถึงศุกร์ เวลา 19:00 น.',
  StudyReminderPreset.weekendMorning => 'เสาร์และอาทิตย์ เวลา 09:00 น.',
};
