import 'dart:async';

import 'package:flutter/material.dart';

import '../features/motivation/application/focus_use_cases.dart';
import '../features/motivation/domain/focus_models.dart';
import '../features/motivation/domain/timezone_policy.dart';
import '../runtime/app_dependencies.dart';
import 'study_preferences_panel.dart';

Future<void> showFocusPlanner(BuildContext context) async {
  final scope = AppDependenciesScope.maybeOf(context);
  final focus = scope?.focus;
  final owners = scope?.localOwners ?? focus?.owners;
  if (scope == null || focus == null || owners == null) return;
  try {
    final owner = await owners.getOrCreateActiveOwner();
    if (!context.mounted ||
        !identical(AppDependenciesScope.maybeOf(context), scope)) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _FocusPlannerPanel(
          scope: scope,
          focus: focus,
          ownerId: owner.id,
        ),
      ),
    );
  } catch (_) {
    if (context.mounted &&
        identical(AppDependenciesScope.maybeOf(context), scope)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('เปิดแผนการฝึกไม่สำเร็จ')));
    }
  }
}

class _FocusPlannerPanel extends StatefulWidget {
  const _FocusPlannerPanel({
    required this.scope,
    required this.focus,
    required this.ownerId,
  });

  final AppDependencies scope;
  final FocusUseCases focus;
  final String ownerId;

  @override
  State<_FocusPlannerPanel> createState() => _FocusPlannerPanelState();
}

class _FocusPlannerPanelState extends State<_FocusPlannerPanel>
    with WidgetsBindingObserver {
  FocusSnapshot? _round;
  FocusWeek? _week;
  bool _active = false;
  bool _loading = true;
  bool _busy = false;
  bool _timerVisible = false;
  bool _showWeek = false;
  String? _error;
  int _minutes = 5;
  int _generation = 0;
  Timer? _tick;
  late final Stream<bool> _activeOwner;
  StreamSubscription<bool>? _ownerSubscription;

  bool get _sameScope =>
      mounted && identical(AppDependenciesScope.maybeOf(context), widget.scope);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.scope.progressUpdates?.addListener(_refreshOpenRound);
    final db = widget.focus.repository.database;
    _activeOwner =
        (db.select(db.localOwners)..where((row) => row.isActive.equals(true)))
            .watch()
            .map((rows) => rows.length == 1 && rows.single.id == widget.ownerId)
            .distinct();
    _ownerSubscription = _activeOwner.listen(
      (active) {
        if (!_sameScope) return;
        if (!active) {
          _generation++;
          _tick?.cancel();
          setState(() {
            _round = null;
            _week = null;
            _active = false;
            _loading = false;
            _busy = false;
          });
        } else if (!_active) {
          _active = true;
          unawaited(_load());
        }
      },
      onError: (Object _) {
        if (!_sameScope) return;
        _generation++;
        _tick?.cancel();
        setState(() {
          _active = false;
          _loading = false;
          _round = null;
          _week = null;
        });
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _tick?.cancel();
    } else {
      _refreshOpenRound();
    }
  }

  void _refreshOpenRound() {
    if (_sameScope &&
        _active &&
        !_loading &&
        !_busy &&
        (_round?.state == FocusState.running ||
            _round?.state == FocusState.paused) &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(_load());
    }
  }

  bool _accept(int generation) =>
      _sameScope && _active && generation == _generation;

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final round = await widget.focus.recover(expectedOwnerId: widget.ownerId);
      if (!_accept(generation)) return;
      setState(() {
        _round = round ?? _round;
        if (round != null) _timerVisible = true;
      });
      _scheduleTick();
    } catch (_) {
      if (_accept(generation)) setState(() => _error = 'อ่านเวลาฝึกไม่สำเร็จ');
    } finally {
      if (_accept(generation)) setState(() => _loading = false);
    }
  }

  void _scheduleTick() {
    _tick?.cancel();
    if (_round?.state != FocusState.running ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_sameScope || !_active) {
        _tick?.cancel();
        return;
      }
      final round = _round;
      final remaining = round == null ? null : _remaining(round);
      if (!_busy && remaining == null) {
        _tick?.cancel();
        unawaited(_load());
      } else if (!_busy && remaining == 0) {
        _tick?.cancel();
        unawaited(_transition(FocusStep.finish));
      } else {
        setState(() {});
      }
    });
  }

  int? _remaining(FocusSnapshot round) {
    try {
      return widget.focus.remainingMs(round);
    } on StateError {
      return null;
    }
  }

  Future<void> _apply(Future<FocusSnapshot> Function() operation) async {
    if (_busy || !_sameScope || !_active) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await operation();
      if (!_accept(generation)) return;
      setState(() => _round = result);
      _scheduleTick();
    } catch (_) {
      if (_accept(generation)) {
        setState(() => _error = 'บันทึกเวลาไม่สำเร็จ กรุณาลองอีกครั้ง');
        if (_round?.state == FocusState.running ||
            _round?.state == FocusState.paused) {
          final current = await widget.focus
              .loadOpen(expectedOwnerId: widget.ownerId)
              .then<FocusSnapshot?>((value) => value, onError: (_) => null);
          if (_accept(generation) &&
              current != null &&
              current.revision != _round?.revision) {
            setState(() => _round = current);
            _scheduleTick();
          }
        }
      }
    } finally {
      if (_accept(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _transition(FocusStep step) async {
    final round = _round;
    if (round == null) return;
    final operation = switch (step) {
      FocusStep.pause => widget.focus.pause,
      FocusStep.resume => widget.focus.resume,
      FocusStep.finish => widget.focus.finish,
      FocusStep.recoverInterrupted => throw StateError('Use focus recovery'),
    };
    await _apply(
      () => operation(
        expectedOwnerId: widget.ownerId,
        id: round.id,
        expectedRevision: round.revision,
      ),
    );
  }

  Future<void> _showRecordedWeek({DateTime? monday}) async {
    if (_busy || !_sameScope || !_active) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _showWeek = true;
      _error = null;
    });
    try {
      var requested = monday;
      if (requested == null) {
        final streak = widget.scope.streak;
        final calendar = await streak?.loadCalendar();
        if (streak == null ||
            calendar == null ||
            calendar.ownerId != widget.ownerId) {
          throw StateError('Home calendar is unavailable');
        }
        final now = streak.nowUtc();
        final day = TimezonePolicy.getLearningDay(now, calendar.current.ianaId);
        requested = DateTime.utc(
          day.year,
          day.month,
          day.day - (day.weekday - 1),
        );
      }
      final week = await widget.focus.week(
        expectedOwnerId: widget.ownerId,
        civilMonday: requested,
      );
      if (_accept(generation)) setState(() => _week = week);
    } catch (_) {
      if (_accept(generation)) {
        setState(() {
          _week = null;
          _error = 'ยังอ่านสัปดาห์ตามปฏิทินบ้านไม่ได้';
        });
      }
    } finally {
      if (_accept(generation)) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _tick?.cancel();
    _ownerSubscription?.cancel();
    widget.scope.progressUpdates?.removeListener(_refreshOpenRound);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    final week = _week;
    final available = _sameScope && _active;
    final running = available && round?.state == FocusState.running;
    final remaining = available && round != null ? _remaining(round) : null;
    return PopScope(
      canPop: !_busy && !running,
      child: SafeArea(
        child: ListView(
          key: ValueKey(_showWeek),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _showWeek ? 'เวลาเรียนที่บันทึก' : 'วางแผนการฝึก',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (_loading || _busy)
              const LinearProgressIndicator(
                semanticsLabel: 'กำลังอ่านหรือบันทึกเวลา',
              ),
            if (!available && !_loading)
              const Text('บัญชีผู้เรียนเปลี่ยนแล้ว')
            else if (available) ...[
              if (_error != null) ...[
                Semantics(liveRegion: true, child: Text(_error!)),
                if (round == null && !_showWeek)
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('ลองใหม่'),
                  ),
              ],
              if (_showWeek) ...[
                if (week != null) ...[
                  Text('สัปดาห์เริ่ม ${_dayLabel(week.civilMonday)}'),
                  Text('เวลาฝึกที่บันทึก ${_duration(week.completedActiveMs)}'),
                  const Text('นับตามสัปดาห์ของวันที่เริ่ม และไม่นับเวลาพัก'),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _showRecordedWeek(
                                monday: week.civilMonday.subtract(
                                  const Duration(days: 7),
                                ),
                              ),
                        child: const Text('สัปดาห์ก่อน'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _showRecordedWeek(
                                monday: week.civilMonday.add(
                                  const Duration(days: 7),
                                ),
                              ),
                        child: const Text('สัปดาห์ถัดไป'),
                      ),
                    ],
                  ),
                  if (week.sessions.isEmpty)
                    const Text('ยังไม่มีเวลาฝึกในสัปดาห์นี้'),
                  for (final session in week.sessions) _FocusRecord(session),
                  if (week.unattributed.isNotEmpty) ...[
                    const Text('รอบที่ระบุสัปดาห์เริ่มไม่ได้'),
                    for (final session in week.unattributed)
                      _FocusRecord(session),
                  ],
                ],
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _showWeek = false),
                  child: const Text('กลับไปจับเวลา'),
                ),
              ] else ...[
                if (!_timerVisible)
                  FilledButton(
                    onPressed: _busy || _loading
                        ? null
                        : () => setState(() => _timerVisible = true),
                    child: const Text('จับเวลาฝึก'),
                  )
                else if (round == null ||
                    round.state == FocusState.interrupted ||
                    round.state == FocusState.completed) ...[
                  if (round != null) _FocusRecord(round),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final minutes in [5, 10])
                        ChoiceChip(
                          label: Text('$minutes นาที'),
                          selected: _minutes == minutes,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _minutes = minutes),
                        ),
                    ],
                  ),
                  FilledButton(
                    onPressed: _busy || _loading
                        ? null
                        : () => _apply(
                            () => widget.focus.start(
                              expectedOwnerId: widget.ownerId,
                              targetMs: _minutes * 60000,
                            ),
                          ),
                    child: const Text('เริ่มจับเวลา'),
                  ),
                ] else ...[
                  Text(
                    remaining == null
                        ? 'กำลังตรวจเวลาของรอบ'
                        : 'เหลือ ${_duration(remaining)}',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _transition(
                            running ? FocusStep.pause : FocusStep.resume,
                          ),
                    child: Text(running ? 'พักเวลา' : 'ฝึกต่อ'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _transition(FocusStep.finish),
                    child: const Text('บันทึกเวลารอบนี้'),
                  ),
                ],
                if (!running)
                  TextButton(
                    onPressed: _busy ? null : _showRecordedWeek,
                    child: const Text('ดูเวลาเรียนที่บันทึกไว้'),
                  ),
                if (!running && widget.scope.studyPreferences != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => showStudyPreferences(context),
                    child: const Text('ปรับวิธีเรียนและวันเป้าหมาย'),
                  ),
              ],
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy || running ? null : () => Navigator.pop(context),
              child: const Text('กลับไปภาพรวมการเรียน'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusRecord extends StatelessWidget {
  const _FocusRecord(this.session);

  final FocusSnapshot session;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ฝึกจริง ${_duration(session.activeMs)} · พัก ${_duration(session.pausedMs)}',
          ),
          if (session.hasUnknownGap) const Text('มีช่วงที่วัดเวลาไม่ได้'),
          if (session.state == FocusState.interrupted)
            const Text('รอบหยุดก่อนบันทึกจบ'),
          if (session.measuredActiveMs > session.activeMs)
            const Text('นับเวลาฝึกถึงเป้าหมายของรอบ'),
          for (final span in session.spans)
            Text(
              '${span.kind == FocusSpanKind.active ? 'ฝึก' : 'พัก'} '
              '${_utcLabel(span.observedStartUtcMs)} ถึง ${_utcLabel(span.observedEndUtcMs)} '
              '· ${span.elapsedUs == null ? 'ไม่ทราบระยะเวลา' : _duration(span.elapsedUs! ~/ 1000)}',
            ),
        ],
      ),
    ),
  );
}

String _duration(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60} นาที ${seconds % 60} วินาที';
}

String _dayLabel(DateTime day) => '${day.day}/${day.month}/${day.year}';

String _utcLabel(int milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  final minute = time.minute.toString().padLeft(2, '0');
  return '${_dayLabel(time)} ${time.hour.toString().padLeft(2, '0')}:$minute UTC';
}
