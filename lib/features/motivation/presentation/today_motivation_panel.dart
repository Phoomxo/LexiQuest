import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../runtime/motivation_runtime.dart';
import '../domain/motivation_snapshot.dart';
import 'quest_objective_label.dart';

class TodayMotivationPanel extends StatefulWidget {
  const TodayMotivationPanel({
    super.key,
    required this.runtime,
    required this.ownerId,
    required this.onOpenQuests,
    this.onPractice,
  });
  final MotivationRuntime runtime;
  final String ownerId;
  final VoidCallback onOpenQuests;
  final VoidCallback? onPractice;
  @override
  State<TodayMotivationPanel> createState() => _TodayMotivationPanelState();
}

class _TodayMotivationPanelState extends State<TodayMotivationPanel>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _changes;
  MotivationView? _view;
  ModalRoute<dynamic>? _route;
  AppDependencies? _dependencies;
  var _bound = false;
  var _retired = false;
  var _foreground = true;
  var _covered = false;
  var _loading = true;
  var _generation = 0;
  var _read = 0;
  String? _status;

  bool get _visible =>
      mounted &&
      !_retired &&
      _foreground &&
      widget.runtime.isForeground &&
      (_route?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.runtime.watchChanges().listen(
      (_) => _changed(),
      onError: (Object _) => _retire(),
      onDone: _retire,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    if ((_bound && !identical(dependencies, _dependencies)) ||
        (dependencies?.database != null &&
            !identical(dependencies!.database, widget.runtime.database))) {
      _retire();
      return;
    }
    _dependencies = dependencies;
    if (!_bound) {
      _bound = true;
      unawaited(_reload());
    }
    if (_route?.isCurrent == false && !_covered) {
      _covered = true;
      _invalidate();
    } else if (_covered && _route?.isCurrent == true) {
      _covered = false;
      unawaited(_reload());
    }
  }

  @override
  void didUpdateWidget(TodayMotivationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime)) {
      _retire();
      return;
    }
    if (oldWidget.ownerId != widget.ownerId) {
      _invalidate();
      unawaited(_reload());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _invalidate();
    if (_foreground) unawaited(_reload());
  }

  void _changed() {
    if (!mounted || _retired) return;
    if (widget.runtime.isRetired) {
      _retire();
      return;
    }
    _invalidate();
    if (_visible) unawaited(_reload());
  }

  void _invalidate() {
    _generation++;
    _read++;
    if (!mounted) return;
    setState(() {
      _view = null;
      _loading = false;
    });
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _invalidate();
    unawaited(_changes?.cancel());
    if (mounted) {
      setState(
        () => _status = 'พื้นที่ข้อมูลเปลี่ยนแล้ว โปรดเปิดหน้าเรียนใหม่',
      );
    }
  }

  Future<void> _reload() async {
    if (!_visible) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final generation = _generation;
    final read = ++_read;
    bool current() => _visible && generation == _generation;
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final view = await widget.runtime.load(
        expectedOwnerId: widget.ownerId,
        stillCurrent: current,
      );
      if (!current() || read != _read) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } on Object {
      if (!current() || read != _read) return;
      setState(() {
        _view = null;
        _loading = false;
        _status = 'ยังอ่านภารกิจไม่ได้ ลองอ่านข้อมูลอีกครั้ง';
      });
    }
  }

  VoidCallback? _action(VoidCallback callback, MotivationView view) {
    if (!_visible || _loading || !view.lease.isCurrent) return null;
    final generation = _generation;
    return () {
      if (!_visible ||
          _loading ||
          generation != _generation ||
          !identical(_view, view) ||
          !view.lease.isCurrent) {
        return;
      }
      _invalidate();
      callback();
      if (_visible) unawaited(_reload());
    };
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final next = view?.history
        .where(
          (row) =>
              row.period?.contains(view.evaluatedAtUtc) == true &&
              row.state.name == 'active',
        )
        .firstOrNull;
    final objective = next?.progress
        .where((row) => !row.isComplete)
        .firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ภารกิจวันนี้', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_loading)
              Semantics(
                liveRegion: true,
                child: const Text('กำลังอ่านข้อมูลที่บันทึก'),
              )
            else if (view != null) ...[
              MotivationTotals(snapshot: view.motivation),
              if (widget.runtime.activationFailure != null)
                const Text(
                  'ยังปรับภารกิจรอบนี้ไม่ครบ เปิดภารกิจเพื่อลองอีกครั้งได้',
                ),
              const SizedBox(height: 12),
              Text(
                objective == null
                    ? 'เลือกแบบฝึกเพื่อเริ่มรอบถัดไปได้ตามสะดวก'
                    : 'เป้าหมายถัดไป: ${questObjectiveLabel(next?.definition, objective.objectiveId) ?? 'คำตอบที่บันทึก'} ${objective.currentCount}/${objective.targetCount}',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('today-open-quests'),
                onPressed: _action(widget.onOpenQuests, view),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('ดูภารกิจและประวัติ'),
              ),
              if (widget.onPractice != null)
                TextButton(
                  onPressed: _action(widget.onPractice!, view),
                  child: const Text('เลือกแบบฝึกต่อ'),
                ),
            ] else ...[
              Text(
                _status ?? 'ภารกิจจะแสดงเมื่อหน้าเรียนพร้อมใช้งาน',
                semanticsLabel: _status,
              ),
              if (_visible && !_retired)
                TextButton(
                  onPressed: () => unawaited(_reload()),
                  child: const Text('อ่านข้อมูลอีกครั้ง'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }
}

class MotivationTotals extends StatelessWidget {
  const MotivationTotals({super.key, required this.snapshot});
  final MotivationSnapshot snapshot;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Text('เขตเวลาสำหรับวันเรียนใหม่ · ${snapshot.timezoneId}'),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _Metric(
            label: 'วันที่เรียนต่อเนื่อง',
            value: '${snapshot.state.currentStreakDays} วัน',
          ),
          _Metric(label: 'XP จากภารกิจ', value: '${snapshot.questXp} XP'),
          _Metric(
            label: 'สิทธิ์พักสตรีก',
            value: '${snapshot.state.freezeCount} สิทธิ์',
          ),
        ],
      ),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ),
  );
}
