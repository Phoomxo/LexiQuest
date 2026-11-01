import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/learning_time/application/learning_time_use_cases.dart';
import '../features/learning_time/presentation/recorded_time_view.dart'
    show formatRecordedLearningTime;
import '../features/progress/application/progress_use_cases.dart';
import '../features/progress/domain/learning_calendar.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/adaptive_content_pane.dart';

typedef LearningCalendarLoader =
    Future<LearningCalendarSnapshot> Function({
      required LearningCalendarPeriod period,
      required String expectedOwnerId,
      required bool Function() stillCurrent,
    });

class LearningCalendarScreen extends StatefulWidget {
  const LearningCalendarScreen({
    super.key,
    this.loader,
    this.ownerChanges,
    this.now,
  });
  final LearningCalendarLoader? loader;
  final Stream<String?>? ownerChanges;
  final DateTime Function()? now;

  @override
  State<LearningCalendarScreen> createState() => _LearningCalendarScreenState();
}

class _LearningCalendarScreenState extends State<LearningCalendarScreen>
    with WidgetsBindingObserver {
  ProgressUseCases? _progress;
  LearningTimeUseCases? _time;
  LearningCalendarLoader? _loader;
  Stream<String?>? _ownerSource;
  StreamSubscription<String?>? _owners;
  StreamSubscription<void>? _timeChanges;
  LearningCalendarSnapshot? _snapshot;
  late LearningCalendarPeriod _period;
  String? _owner;
  int _generation = 0;
  bool _monthly = false;
  bool _configured = false;
  bool _loading = false;
  bool _failed = false;
  bool? _routeVisible;

  DateTime get _today => (widget.now?.call() ?? DateTime.now()).toLocal();
  bool get _visible =>
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _period = LearningCalendarPeriod.weekEnding(_today);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
    final visible = _visible;
    if (visible != _routeVisible) {
      _routeVisible = visible;
      if (visible) {
        unawaited(_reload());
      } else {
        _generation++;
        _snapshot = null;
        _loading = false;
      }
    }
  }

  @override
  void didUpdateWidget(LearningCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final progress = dependencies?.progress;
    final time = dependencies?.learningTime;
    if (_configured &&
        identical(_progress, progress) &&
        identical(_time, time) &&
        identical(_loader, widget.loader) &&
        identical(_ownerSource, widget.ownerChanges)) {
      return;
    }
    _configured = true;
    _generation++;
    unawaited(_owners?.cancel());
    unawaited(_timeChanges?.cancel());
    _progress = progress;
    _time = time;
    _loader = widget.loader;
    _ownerSource = widget.ownerChanges;
    _owner = null;
    _snapshot = null;
    _failed = false;
    _loading = true;
    _owners = (widget.ownerChanges ?? progress?.watchActiveOwnerId())?.listen(
      _ownerChanged,
      onError: (Object _) => _ownerChanged(null),
      onDone: () => _ownerChanged(null),
    );
    _timeChanges = time?.changes.listen((_) => unawaited(_reload()));
    if (_owners == null) _loading = false;
  }

  void _ownerChanged(String? owner) {
    if (!mounted) return;
    _generation++;
    setState(() {
      _owner = owner;
      _snapshot = null;
      _failed = false;
      _loading = owner != null;
    });
    if (owner != null) unawaited(_reload());
  }

  Future<void> _reload() async {
    final owner = _owner;
    final progress = _progress;
    final loader = _loader;
    final time = _time;
    if (owner == null || !_visible || (loader == null && progress == null)) {
      return;
    }
    final generation = ++_generation;
    final period = _period;
    bool current() =>
        _visible &&
        generation == _generation &&
        _owner == owner &&
        identical(period, _period) &&
        identical(loader, _loader) &&
        identical(progress, _progress) &&
        identical(time, _time);
    setState(() {
      _loading = true;
      _failed = false;
      _snapshot = null;
    });
    try {
      final value = loader == null
          ? await progress!.loadCalendarForOwner(
              period: period,
              expectedOwnerId: owner,
              stillCurrent: current,
              learningTime: time,
            )
          : await loader(
              period: period,
              expectedOwnerId: owner,
              stillCurrent: current,
            );
      if (!current()) return;
      if (value.ownerId != owner ||
          value.days.length != period.dayCount ||
          value.period.firstDay != period.firstDay ||
          value.period.dayCount != period.dayCount) {
        throw StateError(
          'Calendar response does not match the captured request',
        );
      }
      setState(() => _snapshot = value);
    } on Object {
      if (current()) setState(() => _failed = true);
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  void _changeView(bool monthly) {
    if (_monthly == monthly) return;
    setState(() {
      _monthly = monthly;
      final selected = _period.dayAt(_period.dayCount - 1);
      _period = monthly
          ? LearningCalendarPeriod.month(selected.year, selected.month)
          : LearningCalendarPeriod.weekEnding(selected);
    });
    unawaited(_reload());
  }

  void _move(int direction) {
    final next = _monthly
        ? DateTime(_period.firstDay.year, _period.firstDay.month + direction)
        : DateTime(
            _period.firstDay.year,
            _period.firstDay.month,
            _period.firstDay.day + 6 + direction * 7,
          );
    if (next.year < 1970 || next.year > 9998) return;
    setState(
      () => _period = _monthly
          ? LearningCalendarPeriod.month(next.year, next.month)
          : LearningCalendarPeriod.weekEnding(next),
    );
    unawaited(_reload());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_reload());
    } else {
      _generation++;
      if (mounted) {
        setState(() {
          _snapshot = null;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_owners?.cancel());
    unawaited(_timeChanges?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _date(DateTime date) => '${date.day}/${date.month}/${date.year}';
  String _timeLabel(RecordedTimeRead value) => switch (value.status) {
    RecordedTimeStatus.recorded => formatRecordedLearningTime(
      value.activeDurationUs!,
      thai: true,
    ),
    RecordedTimeStatus.noneRecorded => 'ยังไม่มีเวลาที่บันทึก',
    RecordedTimeStatus.unavailable ||
    RecordedTimeStatus.unsupported => 'อ่านเวลาไม่ได้',
  };

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final styles = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ปฏิทินการเรียน'),
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.proseMaxWidth,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('รายสัปดาห์'),
                  selected: !_monthly,
                  onSelected: (_) => _changeView(false),
                ),
                ChoiceChip(
                  label: const Text('รายเดือน'),
                  selected: _monthly,
                  onSelected: (_) => _changeView(true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${_date(_period.firstDay)} ถึง ${_date(_period.dayAt(_period.dayCount - 1))}',
              style: styles.titleMedium,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  key: const ValueKey('calendar-previous'),
                  tooltip: 'ช่วงก่อนหน้า',
                  onPressed: () => _move(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                TextButton(
                  onPressed: () {
                    setState(
                      () => _period = _monthly
                          ? LearningCalendarPeriod.month(
                              _today.year,
                              _today.month,
                            )
                          : LearningCalendarPeriod.weekEnding(_today),
                    );
                    unawaited(_reload());
                  },
                  child: const Text('วันนี้'),
                ),
                IconButton(
                  key: const ValueKey('calendar-next'),
                  tooltip: 'ช่วงถัดไป',
                  onPressed: () => _move(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'กำลังอ่านปฏิทินการเรียน',
                ),
              ),
            if (_failed)
              Semantics(
                liveRegion: true,
                child: const Text('อ่านปฏิทินไม่สำเร็จ โปรดลองใหม่'),
              ),
            if (!_loading && !_failed && _owner == null)
              const Text('ยังไม่มีพื้นที่เรียนที่เปิดอยู่'),
            if (snapshot != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('สรุปช่วงที่เลือก', style: styles.titleLarge),
                      Text(
                        '${snapshot.answerCount} คำตอบ',
                        key: const ValueKey('calendar-total-answers'),
                      ),
                      Text('ตอบถูก ${snapshot.correctCount} คำตอบ'),
                      Text('จบช่วงฝึก ${snapshot.completedSessionCount} ครั้ง'),
                      Text(
                        'เวลาปฏิสัมพันธ์ที่บันทึก ${_timeLabel(snapshot.recordedTime)}',
                        key: const ValueKey('calendar-total-time'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'เวลาอยู่ในวันที่ยืนยันปฏิสัมพันธ์ครั้งสุดท้ายของแต่ละช่วง ใช้ระยะเวลาที่บันทึกจริง ไม่ใช่เวลาที่เปิดแอปค้างไว้',
              ),
              const SizedBox(height: 8),
              const Text(
                'จำนวนคำตอบและคำตอบถูกเป็นผลฝึกที่บันทึกไว้ แยกจากเวลาและข้อมูลวิจัย',
              ),
              for (final day in snapshot.days)
                Card(
                  key: ValueKey(
                    'calendar-day-${day.date.year}-${day.date.month}-${day.date.day}',
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_date(day.date), style: styles.titleMedium),
                        Text(
                          '${day.answerCount} คำตอบ · ตอบถูก ${day.correctCount}',
                        ),
                        Text('จบช่วงฝึก ${day.completedSessionCount} ครั้ง'),
                        Text('เวลาที่บันทึก ${_timeLabel(day.recordedTime)}'),
                      ],
                    ),
                  ),
                ),
            ],
            if (!_loading && _owner != null)
              OutlinedButton.icon(
                key: const ValueKey('calendar-refresh'),
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('โหลดข้อมูลใหม่'),
              ),
          ],
        ),
      ),
    );
  }
}
