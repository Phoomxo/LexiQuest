import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_study_preferences_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/study_preferences.dart';
import '../features/motivation/domain/timezone_policy.dart';
import '../runtime/app_dependencies.dart';

Future<StudyMethod?> showStudyPreferences(
  BuildContext context, {
  String? firstRunAccountUid,
}) async {
  final scope = AppDependenciesScope.maybeOf(context);
  final repository = scope?.studyPreferences;
  final owners = scope?.localOwners;
  if (scope == null || repository == null || owners == null) return null;
  final firstRun = firstRunAccountUid != null;
  bool sameAccount() {
    if (!firstRun) return true;
    final session = scope.account?.currentSession;
    return session?.uid == firstRunAccountUid &&
        session?.isAnonymous == false &&
        session?.emailVerified == true;
  }

  try {
    final owner = await owners.getOrCreateActiveOwner();
    if (firstRun) {
      if (owner.firebaseUid != firstRunAccountUid || !sameAccount()) {
        return null;
      }
      final preferences = await repository.load(ownerId: owner.id);
      if (preferences.onboardingState != OnboardingState.unset) return null;
    }
    if (!context.mounted ||
        !identical(AppDependenciesScope.maybeOf(context), scope) ||
        !sameAccount() ||
        (firstRun && ModalRoute.of(context)?.isCurrent != true)) {
      return null;
    }
    final method = await showModalBottomSheet<StudyMethod>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        if (!identical(AppDependenciesScope.maybeOf(sheetContext), scope) ||
            !sameAccount()) {
          return const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('บัญชีผู้เรียนเปลี่ยนแล้ว'),
            ),
          );
        }
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: StudyPreferencesPanel(
            repository: repository,
            ownerId: owner.id,
            firstRun: firstRun,
            ownerUpdates: scope.progressUpdates,
            loadCivilToday: () async {
              final calendar = await scope.streak?.loadCalendar();
              if (calendar == null || calendar.ownerId != owner.id) {
                throw StateError('Home calendar is unavailable');
              }
              final now = scope.streak!.nowUtc();
              final day = TimezonePolicy.getLearningDay(
                now,
                calendar.current.ianaId,
              );
              return DateTime.utc(day.year, day.month, day.day);
            },
          ),
        );
      },
    );
    if (method != null &&
        sameAccount() &&
        context.mounted &&
        identical(AppDependenciesScope.maybeOf(context), scope) &&
        (await owners.getOrCreateActiveOwner()).id == owner.id &&
        sameAccount()) {
      return method;
    }
  } catch (_) {
    if (context.mounted &&
        identical(AppDependenciesScope.maybeOf(context), scope)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดการตั้งค่าการเรียนไม่สำเร็จ')),
      );
    }
  }
  return null;
}

/// Existing Settings/Profile surfaces host this panel; it does not create a route.
class StudyPreferencesPanel extends StatefulWidget {
  const StudyPreferencesPanel({
    super.key,
    required this.repository,
    required this.ownerId,
    required this.loadCivilToday,
    this.ownerUpdates,
    this.firstRun = false,
  });

  final DriftStudyPreferencesRepository repository;
  final String ownerId;
  final Future<DateTime> Function() loadCivilToday;
  final ValueListenable<int>? ownerUpdates;
  final bool firstRun;

  @override
  State<StudyPreferencesPanel> createState() => _StudyPreferencesPanelState();
}

class _StudyPreferencesPanelState extends State<StudyPreferencesPanel> {
  StreamSubscription<List<dynamic>>? _ownerSubscription;
  StudyPreferences? _view;
  DateTime? _today;
  StudyPurpose? _purpose;
  StudyMethod? _method;
  int? _minutes;
  String? _error;
  bool _active = false, _loading = true, _saving = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant StudyPreferencesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository) ||
        oldWidget.ownerId != widget.ownerId ||
        !identical(oldWidget.ownerUpdates, widget.ownerUpdates)) {
      oldWidget.ownerUpdates?.removeListener(_refresh);
      _ownerSubscription?.cancel();
      _bind();
    }
  }

  void _bind() {
    _generation++;
    _view = null;
    _active = false;
    _loading = true;
    widget.ownerUpdates?.addListener(_refresh);
    final owners = widget.repository.database.localOwners;
    final query = widget.repository.database.select(owners)
      ..where((row) => row.isActive.equals(true));
    _ownerSubscription = query.watch().listen(
      (rows) {
        final active = rows.length == 1 && rows.single.id == widget.ownerId;
        if (!mounted) return;
        if (!active) {
          setState(() {
            _generation++;
            _active = false;
            _loading = false;
            _view = null;
            _today = null;
          });
        } else {
          _active = true;
          unawaited(_load());
        }
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _generation++;
          _active = false;
          _loading = false;
          _view = null;
          _error = 'อ่านผู้ใช้ปัจจุบันไม่ได้';
        });
      },
    );
  }

  void _refresh() {
    if (!mounted || !_active || _saving) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _view = null;
        _error = null;
      });
    }
    try {
      final view = await widget.repository.load(ownerId: widget.ownerId);
      DateTime? today;
      if (!widget.firstRun) {
        try {
          final value = await widget.loadCivilToday();
          if (value.isUtc &&
              value == DateTime.utc(value.year, value.month, value.day)) {
            today = value;
          }
        } on Object {
          today = null;
        }
      }
      if (!mounted || !_active || generation != _generation) return;
      setState(() {
        _view = view;
        _purpose = view.purpose;
        _minutes = view.plannedMinutes;
        _method = view.method;
        _today = today;
        _loading = false;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'อ่านการตั้งค่าการเรียนไม่ได้';
      });
    }
  }

  Future<void> _save(
    Future<StudyPreferences> Function(StudyPreferences) operation, {
    bool finishFirstRun = false,
  }) async {
    final view = _view;
    if (!_active || _saving || view == null) return;
    final generation = _generation;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await operation(view);
      if (!mounted || !_active || generation != _generation) return;
      if (finishFirstRun && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(
          context,
          result.onboardingState == OnboardingState.completed
              ? result.method
              : null,
        );
        return;
      }
      setState(() {
        _view = result;
        _purpose = result.purpose;
        _minutes = result.plannedMinutes;
        _method = result.method;
      });
    } on Object {
      if (mounted && _active && generation == _generation) {
        setState(() => _error = 'บันทึกไม่สำเร็จ กรุณาโหลดใหม่แล้วลองอีกครั้ง');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseDate() async {
    final view = _view;
    final today = _today;
    if (view == null || today == null || _saving) return;
    final generation = _generation;
    final candidate = view.goalCivilDate ?? today;
    final first = DateTime.utc(1900);
    final last = DateTime.utc(2100, 12, 31);
    final initial = candidate.isBefore(first)
        ? first
        : candidate.isAfter(last)
        ? last
        : candidate;
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null || !mounted || !_active || generation != _generation) {
      return;
    }
    final civil = DateTime.utc(selected.year, selected.month, selected.day);
    await _save(
      (current) => widget.repository.setGoal(
        expectedOwnerId: widget.ownerId,
        expected: current,
        civilDate: civil,
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    widget.ownerUpdates?.removeListener(_refresh);
    _ownerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.firstRun
                  ? 'เลือกวิธีฝึกครั้งแรก'
                  : 'วิธีเรียนและวันเป้าหมาย',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'กำลังอ่านการตั้งค่าการเรียน',
                  ),
                ),
              )
            else if (!_active)
              Text(_error ?? 'บัญชีผู้เรียนเปลี่ยนแล้ว')
            else if (view == null) ...[
              Text(_error ?? 'ยังอ่านการตั้งค่าการเรียนไม่ได้'),
              TextButton(onPressed: _load, child: const Text('ลองใหม่')),
            ] else ...[
              const SizedBox(height: 16),
              const Text('อยากใช้ภาษาอังกฤษที่ไหน'),
              RadioGroup<StudyPurpose>(
                groupValue: _purpose,
                onChanged: (value) {
                  if (!_saving) setState(() => _purpose = value);
                },
                child: const Column(
                  children: [
                    RadioListTile<StudyPurpose>(
                      value: StudyPurpose.travel,
                      title: Text('เวลาเดินทาง · ฟังประกาศและอ่านป้าย'),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _purpose = null),
                child: const Text('ยังไม่มีเป้าหมายการเรียน'),
              ),
              const Text('มีเวลาฝึกแค่ไหน'),
              RadioGroup<int>(
                groupValue: _minutes,
                onChanged: (value) {
                  if (!_saving) setState(() => _minutes = value);
                },
                child: const Column(
                  children: [
                    RadioListTile<int>(
                      value: 5,
                      title: Text('ประมาณ 5 นาทีต่อครั้ง'),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _minutes = null),
                child: const Text('เลือกเวลาทุกครั้งที่ฝึก'),
              ),
              const Text('อยากฝึกแบบไหน'),
              RadioGroup<StudyMethod>(
                groupValue: _method,
                onChanged: (value) {
                  if (!_saving) setState(() => _method = value);
                },
                child: const Column(
                  children: [
                    RadioListTile<StudyMethod>(
                      value: StudyMethod.reading,
                      title: Text('อ่านเรื่องสั้นจากชีวิตประจำวัน'),
                    ),
                    RadioListTile<StudyMethod>(
                      value: StudyMethod.speaking,
                      title: Text('ฟังเสียงแล้วลองพูดตาม'),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _saving || (widget.firstRun && _method == null)
                    ? null
                    : () => _save(
                        (current) => widget.repository.saveLearning(
                          expectedOwnerId: widget.ownerId,
                          expected: current,
                          onboardingState: OnboardingState.completed,
                          purpose: _purpose,
                          plannedMinutes: _minutes,
                          method: _method,
                        ),
                        finishFirstRun: widget.firstRun,
                      ),
                child: Text(
                  widget.firstRun ? 'บันทึกและเริ่มฝึก' : 'บันทึกวิธีเรียน',
                ),
              ),
              TextButton(
                onPressed: _saving
                    ? null
                    : () => _save(
                        (current) => widget.repository.saveLearning(
                          expectedOwnerId: widget.ownerId,
                          expected: current,
                          onboardingState: OnboardingState.skipped,
                          purpose: current.purpose,
                          plannedMinutes: current.plannedMinutes,
                          method: current.method,
                        ),
                        finishFirstRun: widget.firstRun,
                      ),
                child: Text(widget.firstRun ? 'ข้ามก่อน' : 'ข้ามคำถาม'),
              ),
              if (!widget.firstRun) ...[
                const Divider(),
                Text(
                  'วันเป้าหมาย',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (view.goalState == GoalState.active &&
                    view.goalCivilDate != null) ...[
                  Text(
                    '${view.goalCivilDate!.day}/${view.goalCivilDate!.month}/${view.goalCivilDate!.year}',
                  ),
                  Text(
                    _today == null
                        ? 'ยังคำนวณวันคงเหลือไม่ได้'
                        : _countdown(view.goalCivilDate!, _today!),
                  ),
                ] else
                  Text(
                    view.goalState == GoalState.closed
                        ? 'ปิดเป้าหมายแล้ว'
                        : 'ยังไม่ได้ตั้งวันเป้าหมาย',
                  ),
                OutlinedButton(
                  onPressed: _saving || _today == null ? null : _chooseDate,
                  child: Text(
                    view.goalState == GoalState.active
                        ? 'แก้วันเป้าหมาย'
                        : 'ตั้งวันเป้าหมาย',
                  ),
                ),
                if (view.goalState == GoalState.active)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => _save(
                            (current) => widget.repository.closeGoal(
                              expectedOwnerId: widget.ownerId,
                              expected: current,
                            ),
                          ),
                    child: const Text('ปิดเป้าหมายนี้'),
                  ),
                if (_today == null) const Text('ปฏิทินบ้านไม่พร้อมใช้งาน'),
              ],
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
              if (_saving)
                const LinearProgressIndicator(semanticsLabel: 'กำลังบันทึก'),
            ],
          ],
        ),
      ),
    );
  }
}

String _countdown(DateTime goal, DateTime today) {
  final days = goal.difference(today).inDays;
  if (days == 0) return 'วันเป้าหมายคือวันนี้';
  return days > 0 ? 'อีก $days วัน' : 'ผ่านวันเป้าหมายมาแล้ว ${-days} วัน';
}
