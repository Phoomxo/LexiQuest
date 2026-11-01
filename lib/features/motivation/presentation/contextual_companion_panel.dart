import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/app_dependencies.dart';
import '../../../runtime/motivation_runtime.dart';
import '../../progress/application/progress_use_cases.dart';
import '../../progress/domain/progress_models.dart';
import '../../quest/domain/quest_models.dart';

class ContextualCompanionPanel extends StatefulWidget {
  const ContextualCompanionPanel({
    super.key,
    required this.runtime,
    required this.ownerId,
    this.progress,
    this.onPractice,
    this.onOpenQuests,
  });
  final MotivationRuntime runtime;
  final String ownerId;
  final ProgressUseCases? progress;
  final VoidCallback? onPractice, onOpenQuests;
  @override
  State<ContextualCompanionPanel> createState() =>
      _ContextualCompanionPanelState();
}

class _ContextualCompanionPanelState extends State<ContextualCompanionPanel>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _changes;
  MotivationView? _view;
  ProgressSnapshot? _progress;
  AppDependencies? _dependencies;
  ModalRoute<dynamic>? _route;
  var _bound = false;
  var _retired = false;
  var _foreground = true;
  var _covered = false;
  var _dismissed = false;
  var _read = 0;
  String? _status;

  bool get _visible =>
      mounted &&
      !_retired &&
      _foreground &&
      widget.runtime.isForeground &&
      (_route?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
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
    ModalRoute.isCurrentOf(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    if ((_bound && !identical(_dependencies, dependencies)) ||
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
    if (!_visible && !_covered) {
      _covered = true;
      _invalidate();
    } else if (_visible && _covered) {
      _covered = false;
      unawaited(_reload());
    }
  }

  @override
  void didUpdateWidget(ContextualCompanionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.runtime, oldWidget.runtime) ||
        !identical(widget.progress, oldWidget.progress)) {
      _retire();
    } else if (widget.ownerId != oldWidget.ownerId) {
      _dismissed = false;
      _changed();
    }
  }

  void _invalidate() {
    _read++;
    if (mounted) {
      setState(() {
        _view = null;
        _progress = null;
      });
    }
  }

  void _retire() {
    _retired = true;
    _invalidate();
    unawaited(_changes?.cancel());
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _invalidate();
    if (_foreground) unawaited(_reload());
  }

  Future<void> _reload() async {
    if (!_visible) return;
    final read = ++_read;
    bool current() => _visible && read == _read;
    try {
      final view = await widget.runtime.load(
        expectedOwnerId: widget.ownerId,
        stillCurrent: current,
      );
      if (!current() || !view.lease.isCurrent) return;
      setState(() {
        _view = view;
        _status = null;
      });
      final progress = widget.progress;
      if (progress == null) return;
      try {
        final facts = await progress.loadForOwner(
          expectedOwnerId: widget.ownerId,
          stillCurrent: () => current() && view.lease.isCurrent,
        );
        if (current() && view.lease.isCurrent) {
          setState(() => _progress = facts);
        }
      } on Object {
        // Motivation remains useful when the optional aggregate cannot be read.
      }
    } on Object {
      if (current()) {
        setState(() {
          _view = null;
          _status = 'ยังอ่านข้อมูลคู่หูไม่ได้ คุณเลือกแบบฝึกต่อได้ตามปกติ';
        });
      }
    }
  }

  VoidCallback? _action(VoidCallback? callback, MotivationView view) {
    if (callback == null || !_visible || !view.lease.isCurrent) return null;
    final read = _read;
    return () {
      if (!_visible ||
          read != _read ||
          !identical(_view, view) ||
          !view.lease.isCurrent) {
        return;
      }
      _invalidate();
      callback();
      if (_visible) unawaited(_reload());
    };
  }

  String _message(MotivationView view) {
    if (widget.runtime.activationFailure != null) {
      return 'ภารกิจยังปรับไม่ครบ เปิดภารกิจเพื่อลองอีกครั้งได้ '
          'คำตอบที่บันทึกแล้วยังอยู่';
    }
    final completed = view.history.any(
      (quest) =>
          quest.period?.contains(view.evaluatedAtUtc) == true &&
          quest.state == QuestInstanceState.completed,
    );
    if (completed) {
      return 'ทำภารกิจในรอบนี้สำเร็จแล้ว ดูรางวัลและประวัติได้เมื่อพร้อม';
    }
    if ((_progress?.dueReviewCount ?? 0) > 0) {
      return 'มีคำถึงเวลาทบทวน ${_progress!.dueReviewCount} คำ '
          'เลือกฝึกทีละนิดได้ตามเวลาของคุณ';
    }
    if ((_progress?.completedSessions ?? 0) > 0) {
      return 'มีรอบฝึกที่บันทึกแล้ว ${_progress!.completedSessions} รอบ '
          'พักหรือเลือกแบบฝึกถัดไปได้ตามสะดวก';
    }
    if (view.motivation.state.currentStreakDays > 0) {
      return 'มีวันที่ฝึกบันทึกแล้วในช่วงนี้ '
          'วันนี้เลือกทำเท่าที่ไหว หรือพักก่อนได้';
    }
    return 'เริ่มจากแบบฝึกสั้น ๆ ได้เมื่อพร้อม '
        'คู่หูใช้ข้อมูลที่บันทึกในเครื่องเพื่อช่วยเลือกก้าวถัดไป';
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('companion-show'),
          onPressed: _visible ? () => setState(() => _dismissed = false) : null,
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('แสดงคู่หู'),
        ),
      );
    }
    final view = _view;
    return Padding(
      key: const ValueKey('contextual-companion'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('คู่หูการเรียน', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              view != null && view.lease.isCurrent && _visible
                  ? _message(view)
                  : _status ?? 'คู่หูจะแสดงเมื่อข้อมูลการเรียนพร้อม',
            ),
          ),
          if (view != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.onOpenQuests != null)
                  OutlinedButton(
                    key: const ValueKey('companion-quests'),
                    onPressed: _action(widget.onOpenQuests, view),
                    child: const Text('ดูภารกิจ'),
                  ),
                if (widget.onPractice != null)
                  TextButton(
                    key: const ValueKey('companion-practice'),
                    onPressed: _action(widget.onPractice, view),
                    child: const Text('เลือกแบบฝึก'),
                  ),
              ],
            ),
          if (_status != null && _visible)
            TextButton(
              onPressed: _reload,
              child: const Text('อ่านข้อมูลคู่หูอีกครั้ง'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('companion-dismiss'),
              onPressed: _visible
                  ? () => setState(() => _dismissed = true)
                  : null,
              child: const Text('ซ่อนคู่หูชั่วคราว'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _read++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
