import 'dart:async';

import 'package:flutter/material.dart';

import '../features/progress/application/progress_use_cases.dart';
import '../features/progress/domain/learning_calendar.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/learning_summary_card.dart';

typedef LearningCalendarLoader = Future<LearningCalendarSnapshot> Function();

/// Read-only calendar reached from the personal progress dashboard.
/// Production reads use the current canonical profile and owner authority.
final class LearningCalendarScreen extends StatefulWidget {
  const LearningCalendarScreen({super.key, this.loader});
  final LearningCalendarLoader? loader;
  @override
  State<LearningCalendarScreen> createState() => _LearningCalendarScreenState();
}

final class _LearningCalendarScreenState extends State<LearningCalendarScreen>
    with WidgetsBindingObserver {
  Future<LearningCalendarSnapshot>? _calendar;
  LearningCalendarLoader? _loader;
  ProgressUseCases? _progress;
  StreamSubscription<({String ownerId, String? firebaseUid})?>? _owners;
  var _epoch = 0;
  var _generation = 0;
  var _active = false;
  var _pending = false;
  var _exited = false;
  var _foreground = true;
  var _ownerReady = false;
  String? _ownerId;

  bool get _visible =>
      !_exited &&
      _foreground &&
      TickerMode.valuesOf(context).enabled &&
      ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exited) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _bind();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(LearningCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    final progress = widget.loader == null
        ? AppDependenciesScope.maybeOf(context)?.progress
        : null;
    final changed = !identical(progress, _progress) || widget.loader != _loader;
    final active = _visible;
    _progress = progress;
    _loader = widget.loader;
    if (changed || active != _active) {
      _active = active;
      _retire();
      _observe();
      if (active) _read();
    }
  }

  void _retire() {
    _generation++;
    _calendar = null;
    _pending = false;
  }

  bool _current(int generation) =>
      mounted && !_exited && generation == _generation;

  void _observe() {
    final epoch = ++_epoch;
    _owners?.cancel().ignore();
    _owners = null;
    _ownerReady = false;
    _ownerId = null;
    if (!_active || _progress == null) return;
    // Includes committed owner changes even when the dependency object is stable.
    _pending = true;
    _owners = _progress!.watchProfileOwner().listen(
      (owner) {
        if (!mounted || _exited || epoch != _epoch) return;
        setState(() {
          _retire();
          _ownerReady = true;
          _ownerId = owner?.ownerId;
          if (_active) _read();
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || _exited || epoch != _epoch) return;
        setState(() {
          _retire();
          _ownerReady = false;
          _ownerId = null;
          _calendar = Future<LearningCalendarSnapshot>.error(error, stack);
          _calendar!.ignore();
        });
      },
    );
  }

  void _read() {
    if (_progress != null && !_ownerReady) return;
    _retire();
    final generation = _generation;
    final loader = _loader;
    final progress = _progress;
    final ownerId = _ownerId;
    _pending = true;
    _calendar = Future<LearningCalendarSnapshot>.sync(() async {
      if (loader != null) return loader();
      if (progress == null || ownerId == null)
        throw StateError('calendar unavailable');
      final profile = await progress.loadPersonalLearningProfile();
      final current = await progress.owners.getOrCreateActiveOwner();
      if (profile.ownerId != ownerId || current.id != ownerId)
        throw StateError('calendar owner changed');
      return profile.calendar;
    });
    // Attach both handlers immediately, including before the next frame on retry.
    _calendar!.then<void>(
      (_) {
        if (_current(generation)) _pending = false;
      },
      onError: (Object _, StackTrace __) {
        if (_current(generation)) _pending = false;
      },
    );
  }

  void _retry(int generation) {
    if (!_current(generation) || !_active || !_visible || _pending) return;
    setState(() {
      if (_progress != null && !_ownerReady) {
        _retire();
        _observe();
      } else {
        _read();
      }
    });
  }

  void _exit() {
    _exited = true;
    _epoch++;
    _owners?.cancel().ignore();
    _owners = null;
    _retire();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exit();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_exited) setState(_exit);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ปฏิทินการเรียน')),
        body: !_active || _exited
            ? const SizedBox.shrink()
            : FutureBuilder<LearningCalendarSnapshot>(
                key: ValueKey(generation),
                future: _calendar,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              header: true,
                              child: const Text(
                                'ไม่สามารถอ่านข้อมูลการเรียนในเครื่องได้',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => _retry(generation),
                              icon: const Icon(Icons.refresh),
                              label: const Text('ลองอีกครั้ง'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  return _LearningCalendarBody(snapshot.data!);
                },
              ),
      ),
    );
  }
}

final class _LearningCalendarBody extends StatelessWidget {
  const _LearningCalendarBody(this.calendar);

  final LearningCalendarSnapshot calendar;

  @override
  Widget build(BuildContext context) {
    final weekly = calendar.weekly;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          header: true,
          child: Text(
            'สรุปสัปดาห์ ${_formatDay(calendar.weekStart)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          container: true,
          label: 'แกนความพยายาม',
          explicitChildNodes: true,
          child: _AxisCard(
            title: 'ความพยายาม (เวลาที่เรียนจริง)',
            value: _formatDuration(weekly.effort.activeDuration),
            detail: 'รวมจากช่วงเวลาที่บันทึกว่าผู้เรียนทำกิจกรรมจริง',
          ),
        ),
        Semantics(
          container: true,
          label: 'แกนความแม่นยำ',
          explicitChildNodes: true,
          child: _AxisCard(
            title: 'ความแม่นยำ',
            value: weekly.accuracy.accuracy == null
                ? null
                : '${(weekly.accuracy.accuracy! * 100).toStringAsFixed(0)}%',
            caption: _formatAccuracy(weekly.accuracy),
            detail: 'นับเฉพาะคำตอบการเรียน ไม่รวมผลประเมิน',
          ),
        ),
        Semantics(
          container: true,
          label: 'แกนการกระจายทักษะ',
          explicitChildNodes: true,
          child: _SkillDistributionCard(weekly.skillDistribution),
        ),
        Semantics(
          container: true,
          label: 'แกนแนวโน้มความแม่นยำ',
          explicitChildNodes: true,
          child: _AccuracyTrendCard(weekly.accuracyTrend),
        ),
        const SizedBox(height: 12),
        Text('รายวัน', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final day in calendar.days)
          Card(
            child: ListTile(
              title: Text(_formatDay(day.day)),
              subtitle: Text(
                'เวลาที่เรียนจริง ${_formatDuration(day.effort.activeDuration)} '
                '• ${_formatAccuracy(day.accuracy)}',
              ),
            ),
          ),
      ],
    );
  }
}

final class _AxisCard extends StatelessWidget {
  const _AxisCard({
    required this.title,
    required this.value,
    required this.detail,
    this.caption,
  });

  final String title;
  final String? value;
  final String detail;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LearningSummaryCard(title: title, value: value, caption: caption),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(detail),
        ),
      ],
    );
  }
}

final class _SkillDistributionCard extends StatelessWidget {
  const _SkillDistributionCard(this.skills);

  final List<LearningSkillDistribution> skills;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'การกระจายทักษะ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (skills.isEmpty)
              const Text('ยังไม่มีทักษะจากคำตอบในสัปดาห์นี้')
            else
              for (final skill in skills)
                Text(
                  '${skill.skillId}: ${_formatAccuracy(LearningAccuracyAxis(sampleSize: skill.sampleSize, correctCount: skill.correctCount))}',
                ),
          ],
        ),
      ),
    );
  }
}

final class _AccuracyTrendCard extends StatelessWidget {
  const _AccuracyTrendCard(this.trend);

  final List<LearningAccuracyTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'แนวโน้มความแม่นยำ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final point in trend)
              Text(
                '${_formatDay(point.day)}: ${_formatAccuracy(point.accuracy)}',
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) => '${value.inSeconds} วินาที';

String _formatAccuracy(LearningAccuracyAxis value) {
  final accuracy = value.accuracy;
  if (accuracy == null) return 'ยังไม่มีคำตอบที่นับความแม่นยำได้';
  return 'ตอบถูก ${value.correctCount} จาก ${value.sampleSize} คำตอบ · ${(accuracy * 100).toStringAsFixed(0)}%';
}

String _formatDay(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
