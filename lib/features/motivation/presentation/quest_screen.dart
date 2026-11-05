import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/m3_theme.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../runtime/motivation_runtime.dart';
import '../../../widgets/adaptive_content_pane.dart';
import '../../quest/domain/quest_models.dart';
import 'quest_objective_label.dart';
import 'today_motivation_panel.dart';

class QuestScreen extends StatefulWidget {
  const QuestScreen({
    super.key,
    required this.runtime,
    required this.ownerId,
    this.onPractice,
  });
  final MotivationRuntime runtime;
  final String ownerId;
  final VoidCallback? onPractice;
  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> with WidgetsBindingObserver {
  StreamSubscription<void>? _changes;
  MotivationView? _view;
  MotivationProtection? _pending;
  ModalRoute<dynamic>? _route;
  AppDependencies? _dependencies;
  String? _status;
  var _bound = false;
  var _retired = false;
  var _foreground = true;
  var _covered = false;
  var _loading = true;
  var _busy = false;
  var _submitted = false;
  var _generation = 0;
  var _read = 0;

  bool get _visible =>
      mounted &&
      !_retired &&
      _foreground &&
      widget.runtime.isForeground &&
      (_route?.isCurrent ?? true);
  bool _current(int generation) =>
      _visible &&
      generation == _generation &&
      widget.runtime.currentOwnerId == widget.ownerId;

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
  void didUpdateWidget(QuestScreen oldWidget) {
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
    if (!_visible ||
        widget.runtime.currentOwnerId != widget.ownerId ||
        _view?.lease.isCurrent == false ||
        _pending?.lease.isCurrent == false) {
      _invalidate();
    }
    if (_visible && !_busy && _pending == null) unawaited(_reload());
  }

  void _invalidate() {
    _generation++;
    _read++;
    if (!mounted) return;
    setState(() {
      _view = null;
      _pending = null;
      _busy = false;
      _submitted = false;
      _loading = false;
      _status = null;
    });
  }

  void _retire() {
    if (_retired) return;
    _retired = true;
    _invalidate();
    unawaited(_changes?.cancel());
    if (mounted) {
      setState(() => _status = 'พื้นที่ข้อมูลเปลี่ยนแล้ว โปรดเปิดภารกิจใหม่');
    }
  }

  Future<void> _reload() async {
    if (!_visible || _busy || _pending != null) {
      if (mounted && !_busy) setState(() => _loading = false);
      return;
    }
    final generation = _generation;
    final read = ++_read;
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final view = await widget.runtime.load(
        expectedOwnerId: widget.ownerId,
        stillCurrent: () => _current(generation),
      );
      if (!_current(generation) || read != _read) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } on Object {
      if (!_visible || generation != _generation || read != _read) return;
      setState(() {
        _view = null;
        _loading = false;
        _status = 'ยังอ่านข้อมูลไม่ได้ ลองอ่านอีกครั้ง';
      });
    }
  }

  VoidCallback? _action(MotivationView view, VoidCallback action) {
    if (!_visible ||
        _busy ||
        _loading ||
        _pending != null ||
        !view.lease.isCurrent) {
      return null;
    }
    final generation = _generation;
    return () {
      if (!_current(generation) ||
          _busy ||
          _loading ||
          _pending != null ||
          !identical(view, _view) ||
          !view.lease.isCurrent) {
        return;
      }
      action();
    };
  }

  Future<void> _activate(MotivationView view) async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await widget.runtime.activate(
        ownerId: widget.ownerId,
        stillCurrent: () => _current(generation),
      );
      final updated = await widget.runtime.load(
        expectedOwnerId: widget.ownerId,
        stillCurrent: () => _current(generation),
      );
      if (!_current(generation)) return;
      setState(() {
        _busy = false;
        _view = updated;
        _status = 'อ่านภารกิจรอบปัจจุบันแล้ว';
      });
    } on Object {
      if (!_current(generation)) return;
      setState(() {
        _busy = false;
        _status = 'ยังเตรียมภารกิจไม่ครบ ลองอีกครั้งได้';
      });
    }
  }

  void _reviewProtection(MotivationView view) {
    final day = view.protectableDay;
    if (day == null) return;
    final generation = _generation;
    try {
      final intent = widget.runtime.prepareProtection(
        view: view,
        protectedDay: day,
        stillCurrent: () => _current(generation),
      );
      setState(() {
        _pending = intent;
        _submitted = false;
        _status = null;
      });
    } on Object {
      if (_current(generation)) {
        setState(
          () => _status = 'ข้อมูลวันพักเปลี่ยนแล้ว โปรดอ่านข้อมูลอีกครั้ง',
        );
      }
    }
  }

  VoidCallback? _pendingAction(
    MotivationProtection pending,
    VoidCallback action,
  ) {
    if (!_visible || _busy || !pending.lease.isCurrent) return null;
    final generation = _generation;
    return () {
      if (!_current(generation) ||
          _busy ||
          !identical(_pending, pending) ||
          !pending.lease.isCurrent) {
        return;
      }
      action();
    };
  }

  Future<void> _applyProtection(MotivationProtection pending) async {
    final generation = _generation;
    setState(() {
      _busy = true;
      _submitted = true;
      _status = null;
    });
    try {
      final updated = await widget.runtime.protect(pending);
      if (!mounted || !_current(generation) || !identical(_pending, pending)) {
        return;
      }
      final message = 'คุ้มครองสตรีกวันที่ ${pending.intent.protectedDay} แล้ว';
      setState(() {
        _view = updated;
        _pending = null;
        _busy = false;
        _submitted = false;
        _status = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      if (!_current(generation) || !identical(_pending, pending)) return;
      setState(() {
        _busy = false;
        _status = 'ยังไม่ได้รับการยืนยัน ลองคำขอเดิมอีกครั้งได้';
      });
    }
  }

  void _cancelProtection() {
    setState(() {
      _pending = null;
      _submitted = false;
      _status = null;
    });
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final pending = _pending;
    final history = view?.history ?? const <QuestInstance>[];
    final ordered = [...history]
      ..sort((a, b) => b.assignedAtUtc.compareTo(a.assignedAtUtc));
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ภารกิจและวันพัก'),
      ),
      body: SafeArea(
        child: AdaptiveContentPane(
          child: ListView(
            key: const ValueKey('quest-content'),
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading)
                Semantics(
                  liveRegion: true,
                  child: const Text('กำลังอ่านข้อมูลที่บันทึก'),
                ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_status!, key: const ValueKey('quest-status')),
                  ),
                ),
              if (view != null) ...[
                MotivationTotals(snapshot: view.motivation),
                if (view.motivation.usedUtcFallback)
                  const Text('ประวัติวันที่ไม่มีเขตเวลากำกับจะใช้ UTC'),
                const SizedBox(height: 12),
                const Text(
                  'ภารกิจอ้างอิงคำตอบตามเป้าหมายที่บันทึกแล้ว วันพักใช้รักษาสตรีกเมื่อเว้นวันเรียน',
                ),
                if (widget.runtime.activationFailure != null)
                  const Text(
                    'ยังปรับภารกิจรอบปัจจุบันไม่ครบ ลองเตรียมภารกิจอีกครั้งได้',
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('quest-activate'),
                  onPressed: _action(view, () => unawaited(_activate(view))),
                  icon: const Icon(Icons.refresh),
                  label: const Text('เตรียมภารกิจรอบปัจจุบัน'),
                ),
                if (widget.onPractice != null)
                  FilledButton.icon(
                    onPressed: _action(view, () {
                      _invalidate();
                      widget.onPractice!();
                      if (_visible) unawaited(_reload());
                    }),
                    icon: const Icon(Icons.school_outlined),
                    label: const Text('เลือกแบบฝึก'),
                  ),
                if (pending == null && view.protectableDay != null)
                  OutlinedButton.icon(
                    key: const ValueKey('quest-review-freeze'),
                    onPressed: _action(view, () => _reviewProtection(view)),
                    icon: const Icon(Icons.ac_unit_outlined),
                    label: const Text('ตรวจสอบการใช้สิทธิ์พักสตรีก'),
                  ),
              ],
              if (pending != null)
                Card(
                  key: const ValueKey('quest-freeze-review'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'ตรวจสอบวันพัก',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'คุ้มครองวันที่ ${pending.intent.protectedDay} ตามเขตเวลา ${pending.intent.timezoneId}',
                        ),
                        const Text(
                          'ใช้ 1 สิทธิ์คุ้มครองความต่อเนื่องของวันที่เว้นเรียน',
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          key: const ValueKey('quest-confirm-freeze'),
                          onPressed: _pendingAction(
                            pending,
                            () => unawaited(_applyProtection(pending)),
                          ),
                          child: Text(
                            _busy
                                ? 'กำลังตรวจสอบคำขอเดิม'
                                : _submitted
                                ? 'ลองคำขอเดิมอีกครั้ง'
                                : 'ยืนยันใช้ 1 สิทธิ์',
                          ),
                        ),
                        TextButton(
                          onPressed: _pendingAction(pending, _cancelProtection),
                          child: const Text('ยกเลิกคำขอนี้'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (view != null) ...[
                const SizedBox(height: 20),
                Text(
                  'ภารกิจและประวัติที่บันทึก',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (ordered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'ยังไม่มีรอบภารกิจ เลือกเตรียมภารกิจหรือเริ่มแบบฝึกได้ตามสะดวก',
                    ),
                  ),
                for (final instance in ordered)
                  _QuestCard(
                    instance: instance,
                    current:
                        instance.period?.contains(view.evaluatedAtUtc) == true,
                  ),
              ] else if (!_loading) ...[
                if (_status == null)
                  const Text('ภารกิจยังไม่พร้อมแสดงในขณะนี้'),
                if (_visible && !_retired)
                  TextButton(
                    onPressed: () => unawaited(_reload()),
                    child: const Text('อ่านข้อมูลอีกครั้ง'),
                  ),
              ],
            ],
          ),
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

class _QuestCard extends StatelessWidget {
  const _QuestCard({required this.instance, required this.current});
  final QuestInstance instance;
  final bool current;
  @override
  Widget build(BuildContext context) {
    final legacy = instance.period == null;
    final type = switch (instance.period?.kind) {
      'daily' => 'ภารกิจรายวัน',
      'weekly' => 'ภารกิจรายสัปดาห์',
      _ => 'ภารกิจเดิม',
    };
    final state = switch (instance.state) {
      QuestInstanceState.active => 'กำลังทำ',
      QuestInstanceState.completed => 'สำเร็จแล้ว',
      QuestInstanceState.expired => 'สิ้นสุดรอบแล้ว',
      QuestInstanceState.abandoned => 'หยุดรอบนี้แล้ว',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$type · $state',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!legacy)
              Text(
                'รอบ ${instance.period!.civilLabel} · ${current ? 'รอบปัจจุบัน' : 'ประวัติ'}',
              ),
            if (legacy)
              const Text('ประวัติเดิมที่ไม่มีรอบยืนยัน ไม่ใช้รับรางวัลใหม่'),
            for (final objective in instance.progress)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${questObjectiveLabel(instance.definition, objective.objectiveId) ?? 'ความคืบหน้าที่บันทึก'}: ${objective.currentCount}/${objective.targetCount}',
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      label:
                          'ความคืบหน้า ${objective.currentCount} จาก ${objective.targetCount}',
                      child: ExcludeSemantics(
                        child: LinearProgressIndicator(
                          value: objective.targetCount <= 0
                              ? 0.0
                              : (objective.currentCount / objective.targetCount)
                                    .clamp(0.0, 1.0)
                                    .toDouble(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!legacy)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'ครบเป้าหมายรับ ${instance.definition!.reward.xpAmount} XP${instance.period!.kind == 'weekly' ? ' และ 1 สิทธิ์พักสตรีก' : ''}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
