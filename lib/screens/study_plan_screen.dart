import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../features/goals/application/study_plan_use_cases.dart';
import '../features/goals/domain/study_plan.dart';
import '../features/identity/application/owner_generation.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature.dart';
import 'personal_sets_screen.dart';
import '../utils/local_study_datetime.dart';

Future<void> openStudyPlan(BuildContext context) => AppNavigator.pushPage<void>(
  context,
  AppPage<void>(
    name: 'study-planning/plan',
    builder: (_) => ProductionFeatureGate(
      feature: Feature.studyPlanning,
      registry: AppDependenciesScope.maybeOf(context)?.features,
      builder: (_) => const StudyPlanScreen(),
    ),
  ),
);

final class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key, this.useCases});
  final StudyPlanUseCases? useCases;
  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

final class _StudyPlanScreenState extends State<StudyPlanScreen>
    with WidgetsBindingObserver {
  StudyPlanUseCases? _app;
  OwnerGenerationToken? _owner;
  StreamSubscription<bool>? _watch;
  final _minutes = TextEditingController(text: '10');
  final _restoreText = TextEditingController();
  String? _backup;
  List<({String id, String title})> _goals = [];
  Map<String, String> _labels = {};
  String? _goal, _error;
  StudyPlanRevision? _active, _pending;
  bool _busy = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app =
        widget.useCases ?? AppDependenciesScope.maybeOf(context)?.studyPlans;
    if (!identical(app, _app)) {
      _clear();
      _app = app;
      if (app != null) _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        _clear();
        _error = 'กรุณาโหลดแผนอีกครั้งหลังกลับเข้าแอป';
      });
    }
  }

  void _clear() {
    _epoch++;
    unawaited(_watch?.cancel());
    _watch = null;
    _owner = null;
    _active = _pending = null;
    _goals = [];
    _labels = {};
    _goal = null;
    _busy = false;
    _minutes.text = '10';
    _backup = null;
    _restoreText.clear();
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_watch?.cancel());
    _minutes.dispose();
    _restoreText.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _clear();
    final app = _app!;
    await _work((ticket) async {
      final owner = await app.begin();
      final active = await app.active(owner);
      final goals = await app.goals(owner);
      final labels = await app.labels(owner);
      if (!_valid(ticket)) return;
      _owner = owner;
      _active = active;
      _goals = goals;
      _labels = labels;
      _goal = goals.any((g) => g.id == active?.goalId) ? active?.goalId : null;
      _minutes.text = '${active?.availableMinutes ?? 10}';
      _watch = app
          .watchOwnerCurrent(owner)
          .listen(
            (current) {
              if (mounted && identical(_owner, owner) && !current) {
                setState(() {
                  _clear();
                  _error = 'บัญชีหรือสิทธิ์เปลี่ยนแล้ว กรุณาโหลดข้อมูลล่าสุด';
                });
              }
            },
            onError: (Object _) {
              if (mounted && identical(_owner, owner)) {
                setState(() {
                  _clear();
                  _error = 'ไม่สามารถยืนยันบัญชีได้';
                });
              }
            },
          );
    });
  }

  bool _valid(int ticket) => mounted && ticket == _epoch;
  Future<void> _work(Future<void> Function(int) body) async {
    final ticket = _epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body(ticket);
    } on Object {
      if (_valid(ticket)) {
        _error =
            'บันทึกหรืออ่านแผนไม่สำเร็จ ลองรายการเดิมอีกครั้ง หรือโหลดข้อมูลล่าสุดเพื่อสร้างข้อเสนอใหม่';
      }
    } finally {
      if (_valid(ticket)) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _preview() => _work((ticket) async {
    final minutes = int.tryParse(_minutes.text);
    if (minutes == null || minutes < 0 || minutes > 1440) {
      _error = 'กรอกเวลาระหว่าง 0–1440 นาที';
      return;
    }
    final owner = _owner!;
    final current = await _app!.active(owner);
    final p = await _app!.propose(
      owner,
      operationId: const Uuid().v4(),
      availableMinutes: minutes,
      goalId: _goal,
    );
    if (p.expectedPriorRevision != (current?.revision ?? 0)) {
      throw StateError('Study plan diff base changed during preview');
    }
    final labels = await _app!.labels(owner);
    if (_valid(ticket)) {
      _active = current;
      _labels = labels;
      _pending = p;
    }
  });
  Future<void> _accept() => _work((ticket) async {
    final owner = _owner!;
    final p = _pending!;
    final app = _app!;
    await app.accept(
      owner,
      p,
      mutationAllowed: () =>
          _valid(ticket) &&
          identical(owner, _owner) &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    );
    final active = await app.active(owner);
    if (_valid(ticket)) {
      _active = active;
      _pending = null;
    }
  });
  Future<void> _export() => _work((ticket) async {
    final result = await _app!.exportArchive(_owner!);
    if (_valid(ticket)) {
      _backup = const JsonEncoder.withIndent('  ').convert(result);
    }
  });
  Future<void> _restore() => _work((ticket) async {
    final owner = _owner!;
    final envelope = Map<String, Object?>.from(
      jsonDecode(_restoreText.text) as Map,
    );
    await _app!.restoreArchive(
      owner,
      envelope,
      mutationAllowed: () =>
          _valid(ticket) &&
          identical(owner, _owner) &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    );
    final active = await _app!.active(owner);
    if (_valid(ticket)) {
      _active = active;
      _pending = null;
      _minutes.text = '${active?.availableMinutes ?? 10}';
      _goal = _goals.any((g) => g.id == active?.goalId) ? active?.goalId : null;
    }
  });

  Widget _summary(StudyPlanRevision p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('${p.learningDay} · ${p.timezoneId}'),
      if (p.deadlineAtUtc case final deadline?)
        Text('ครบกำหนด ${formatLocalStudyDateTime(deadline, p.timezoneId)}'),
      Text(
        'ทบทวน ${p.dueItems.length} · งานใหม่ ${p.newItems.length} · ยกยอด ${p.carryOver.length}',
      ),
      if (p.availableMinutes == 0)
        const Text('วันนี้ไม่มีเวลา งานถึงกำหนดยังคงอยู่ในคิวทบทวน'),
      if (p.missedDays > 0)
        Text(
          'ผ่านไป ${p.missedDays} วันเต็มหลังแผนเดิม — ใช้คิวปัจจุบันโดยไม่ลบความคืบหน้า',
        ),
      if (p.deadlinePassed)
        const Text('เลยกำหนดเป้าหมายแล้ว สามารถวางแผนใหม่ได้'),
      if (p.dueItems.isEmpty && p.newItems.isEmpty && p.carryOver.isEmpty)
        const Text('ขณะนี้ไม่มีงานในแผน สามารถเลือกคำจากชุดคำส่วนตัวได้'),
    ],
  );
  Widget _itemDiff(StudyPlanRevision p) {
    final before = {...?_active?.dueItems, ...?_active?.newItems};
    final after = {...p.dueItems, ...p.newItems};
    String names(Iterable<String> ids) =>
        ids.map((id) => _labels[id] ?? 'คำที่ไม่พร้อมใช้งาน').join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (after.difference(before).isNotEmpty)
          Text('เพิ่มในวันนี้: ${names(after.difference(before))}'),
        if (before.difference(after).isNotEmpty)
          Text(
            'นำออกจากแผนวันนี้: ${names(before.difference(after))} (ไม่ลบผลการเรียน)',
          ),
        if (p.carryOver.isNotEmpty) Text('ยกยอด: ${names(p.carryOver)}'),
      ],
    );
  }

  String? _assistanceSummary(StudyPlanRevision? plan, String state) {
    if (_owner == null || _busy || _error != null) return null;
    return jsonEncode({
      'state': plan == null ? 'none' : state,
      'purpose': 'planning-only-not-score-or-completion',
      'estimateMinutesPerItem': 1,
      if (plan != null) ...{
        'revision': plan.revision,
        'minutes': plan.availableMinutes,
        'learningDay': plan.learningDay,
        'timezone': plan.timezoneId,
        'dueCount': plan.dueItems.length,
        'newCount': plan.newItems.length,
        'carryOverCount': plan.carryOver.length,
        'missedDays': plan.missedDays,
        'deadlinePassed': plan.deadlinePassed,
        'deadlineUtc': plan.deadlineAtUtc?.toIso8601String(),
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _pending;
    final screen = Scaffold(
      appBar: AppBar(title: const Text('แผนการเรียนของฉัน')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'จัดเวลาทบทวนก่อนงานใหม่ ประมาณ 1 นาทีต่อคำ เป็นค่าประมาณเพื่อวางแผน ไม่ใช่คะแนนหรือเวลาที่รับประกัน',
              ),
              if (_app == null) const Text('แผนการเรียนยังไม่พร้อมใช้งาน'),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) ...[
                Text(_error!, key: const ValueKey('plan-error')),
                OutlinedButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('โหลดข้อมูลล่าสุด'),
                ),
              ],
              if (_active case final active?) ...[
                const SizedBox(height: 12),
                Text(
                  'แผนที่ยอมรับ r${active.revision}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                _summary(active),
              ],
              if (_owner != null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('goal:${_active?.operationId}'),
                  initialValue: _goal ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'เป้าหมายและกำหนดเวลา',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('ไม่มีเป้าหมายที่ผูกไว้'),
                    ),
                    ..._goals.map(
                      (g) =>
                          DropdownMenuItem(value: g.id, child: Text(g.title)),
                    ),
                  ],
                  onChanged: _busy || p != null
                      ? null
                      : (value) =>
                            setState(() => _goal = value == '' ? null : value),
                ),
                TextField(
                  controller: _minutes,
                  key: const ValueKey('plan-minutes'),
                  enabled: !_busy && p == null,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'เวลาว่างวันนี้ (นาที)',
                  ),
                ),
                const SizedBox(height: 12),
                if (p == null)
                  FilledButton(
                    onPressed: _busy ? null : _preview,
                    child: const Text('ดูข้อเสนอและเปรียบเทียบ'),
                  ),
                if (p != null) ...[
                  Text(
                    'ข้อเสนอ r${p.revision}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    'เวลา: ${_active?.availableMinutes ?? 'ยังไม่มีแผน'} เป็น ${p.availableMinutes} นาที',
                  ),
                  Text(
                    'ทบทวน: ${_active?.dueItems.length ?? 0} เป็น ${p.dueItems.length}',
                  ),
                  Text(
                    'งานใหม่: ${_active?.newItems.length ?? 0} เป็น ${p.newItems.length}',
                  ),
                  Text(
                    'ยกยอด: ${_active?.carryOver.length ?? 0} เป็น ${p.carryOver.length}',
                  ),
                  _itemDiff(p),
                  _summary(p),
                  FilledButton(
                    onPressed: _busy ? null : _accept,
                    child: const Text('ยอมรับแผน'),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _pending = null;
                            _error = null;
                          }),
                    child: const Text('ไม่รับข้อเสนอ'),
                  ),
                ],
                OutlinedButton(
                  onPressed: _busy ? null : () => openPersonalSets(context),
                  child: const Text('เปิดชุดคำส่วนตัว'),
                ),
                if (_active != null)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () =>
                              Navigator.of(context).popUntil((r) => r.isFirst),
                    child: const Text('กลับหน้าหลักเพื่อเริ่มงานวันนี้'),
                  ),
                if (p == null) ...[
                  OutlinedButton(
                    onPressed: _busy ? null : _export,
                    child: const Text('สำรองประวัติแผน'),
                  ),
                  if (_backup case final backup?) ...[
                    const Text(
                      'สำรองเฉพาะประวัติแผนของบัญชีนี้ การคืนค่าไม่ย้อนแผนที่ใช้อยู่และไม่คืนค่าฐานข้อมูลทั้งหมด',
                    ),
                    SizedBox(
                      height: 160,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          backup,
                          key: const ValueKey('plan-backup-json'),
                        ),
                      ),
                    ),
                  ],
                  TextField(
                    controller: _restoreText,
                    key: const ValueKey('plan-restore-json'),
                    enabled: !_busy,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'วางข้อมูลสำรองประวัติแผน',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _restore,
                    child: const Text('คืนค่าประวัติแผน'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
    return MenuActionBinding(
      id: 'study-planning/active-summary',
      label: 'ข้อมูลแผนที่ยอมรับแล้ว',
      ownerId: _owner?.ownerId,
      onInvoke: null,
      readValue: _assistanceSummary(_active, 'accepted'),
      child: MenuActionBinding(
        id: 'study-planning/proposal-summary',
        label: 'ข้อเสนอแผนที่ยังไม่บันทึก',
        ownerId: _owner?.ownerId,
        onInvoke: null,
        readValue: _assistanceSummary(_pending, 'proposed'),
        child: screen,
      ),
    );
  }
}
