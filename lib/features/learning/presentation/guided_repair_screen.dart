import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../navigation/app_routes.dart';
import '../../../runtime/app_dependencies.dart';
import '../../../runtime/production_feature_gate.dart';
import '../../../runtime/registries/feature.dart';
import '../../ai_tutor/application/ai_tutor_use_cases.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../application/guided_repair_use_cases.dart';
import '../domain/answer_feedback.dart';
import '../domain/guided_repair.dart';

final class GuidedRepairEntry extends StatelessWidget {
  const GuidedRepairEntry({super.key, required this.feedback, this.open});
  final AnswerFeedback feedback;
  final Future<GuidedRepairTicket> Function(GuidedRepairUseCases)? open;
  @override
  Widget build(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final app = dependencies?.guidedRepair;
    if (app == null ||
        !app.isAvailable() ||
        feedback.isCorrect ||
        feedback.committedContrastiveAttempt == null) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      icon: const Icon(Icons.school_outlined),
      label: const Text('ฝึกแก้คำตอบ'),
      onPressed: () => AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/guided-repair',
          builder: (_) => ProductionFeatureGate(
            feature: Feature.quiz,
            registry: dependencies?.features,
            builder: (_) => GuidedRepairScreen(
              useCases: app,
              feedback: feedback,
              open: open == null ? null : () => open!(app),
            ),
          ),
        ),
      ),
    );
  }
}

final class GuidedRepairScreen extends StatefulWidget {
  const GuidedRepairScreen({
    super.key,
    required this.useCases,
    required this.feedback,
    this.open,
  });
  final GuidedRepairUseCases useCases;
  final AnswerFeedback feedback;
  final Future<GuidedRepairTicket> Function()? open;
  @override
  State<GuidedRepairScreen> createState() => _GuidedRepairScreenState();
}

final class _GuidedRepairScreenState extends State<GuidedRepairScreen>
    with WidgetsBindingObserver, RouteAware {
  PageRoute<dynamic>? _route;
  final _answer = TextEditingController();
  GuidedRepairTicket? _ticket;
  StreamSubscription<bool>? _watch;
  AiCancellation? _ai;
  String? _error, _help;
  ({String id, String action, String answer, GuidedRepairTicket ticket})?
  _pending;
  bool _busy = false, _aiUsed = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    if (mounted) {
      setState(() {
        _retire();
        _error = 'กรุณาเปิดการฝึกอีกครั้งเมื่อกลับมา';
      });
    }
  }

  bool _current(int epoch) => mounted && epoch == _epoch;
  void _retire() {
    _epoch++;
    _ai?.cancel();
    _ai = null;
    unawaited(_watch?.cancel());
    _watch = null;
    _ticket = null;
    _pending = null;
    _answer.clear();
    _help = null;
    _busy = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() {
        _retire();
        _error = 'กรุณาเปิดการฝึกอีกครั้งหลังกลับเข้าแอป';
      });
    }
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket =
          await (widget.open?.call() ?? widget.useCases.open(widget.feedback));
      if (!_current(epoch)) return;
      _ticket = ticket;
      _watch = widget.useCases.watchCurrent(ticket.owner).listen((current) {
        if (!current && _current(epoch)) {
          setState(() {
            _retire();
            _error = 'บัญชีหรือสิทธิ์กิจกรรมเปลี่ยน กรุณากลับไปบทเรียน';
          });
        }
      });
    } on Object {
      if (_current(epoch)) {
        _error = 'การฝึกยังไม่พร้อมสำหรับคำตอบหรือเนื้อหานี้';
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _act(String action) async {
    final ticket = _ticket;
    if (_busy || ticket == null) return;
    final epoch = _epoch;
    _pending ??= (
      id: const Uuid().v4(),
      action: action,
      answer: action == 'answer' ? _answer.text : '',
      ticket: ticket,
    );
    final pending = _pending!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final next = await widget.useCases.act(
        pending.ticket,
        operationId: pending.id,
        action: pending.action,
        answer: pending.answer,
        mutationAllowed: () => _current(epoch),
      );
      if (!_current(epoch)) return;
      _ticket = next;
      _pending = null;
      _answer.clear();
    } on StateError {
      if (_current(epoch)) {
        setState(() {
          _retire();
          _error = 'บัญชี เนื้อหา หรือรายการฝึกเปลี่ยน กรุณาเปิดการฝึกอีกครั้ง';
        });
      }
    } on Object {
      if (_current(epoch)) {
        _error = 'บันทึกยังไม่ยืนยัน กดส่งรายการเดิมอีกครั้ง';
      }
    } finally {
      if (_current(epoch)) setState(() => _busy = false);
    }
  }

  Future<void> _askAi(AiTutorController tutor) async {
    if (_busy || _aiUsed || _ticket == null || _pending != null) return;
    // Consume a persisted hint before optional help; cancelling cannot reset it.
    await _act('hint');
    if (!mounted || _ticket == null || _pending != null) return;
    final ticket = _ticket!;
    final epoch = _epoch;
    final cancellation = _ai = AiCancellation();
    setState(() {
      _busy = true;
      _aiUsed = true;
    });
    final result = await AiTutorUseCases.guidedRepairHelp(
      cancellation: cancellation,
      fallback: ticket.context,
      request: (cancel) async {
        await widget.useCases.requireCurrent(ticket.owner);
        return (await tutor.reply(
          scenario:
              'Explain this vocabulary context briefly. Do not grade or award anything.',
          learnerMessage: ticket.context,
          cancellation: cancel,
        )).text;
      },
    );
    if (_current(epoch)) {
      setState(() {
        _help =
            '${result.generated ? 'คำแนะนำ AI (ยังไม่ตรวจทาน)' : 'คำแนะนำจากเนื้อหา'}: ${result.text}';
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _retire();
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final tutor = dependencies?.features.isEnabled(Feature.aiTutor) == true
        ? dependencies?.aiTutor
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('ฝึกแก้คำตอบ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!, semanticsLabel: _error),
            if (ticket != null) ...[
              Text(
                ticket.explanation?.correctRationale ??
                    'คำอธิบายที่ตรวจทานยังไม่พร้อม ใช้บริบทด้านล่างเพื่อฝึก',
              ),
              if (ticket.explanation case final explanation?)
                Text(explanation.distractorRationale),
              GuidedRepairPanel(
                state: ticket.state,
                contextText: ticket.context,
                answer: _answer,
                busy: _busy || _pending != null,
                onHint: () => _act('hint'),
                onAnswer: () => _act('answer'),
                onExit: () => Navigator.of(context).pop(),
              ),
              if (_pending != null)
                FilledButton(
                  onPressed: _busy ? null : () => _act(_pending!.action),
                  child: const Text('ส่งรายการเดิมอีกครั้ง'),
                ),
              if (tutor != null &&
                  !_aiUsed &&
                  !ticket.state.terminal &&
                  ticket.state.hintLevel < 2)
                TextButton(
                  onPressed: _busy ? null : () => _askAi(tutor),
                  child: const Text('ขอคำแนะนำ AI (ใช้หนึ่งคำใบ้)'),
                ),
              if (_help != null) Text(_help!),
            ] else if (!_busy) ...[
              TextButton(
                onPressed: _load,
                child: const Text('เปิดการฝึกอีกครั้ง'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('กลับไปบทเรียน'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class GuidedRepairPanel extends StatelessWidget {
  const GuidedRepairPanel({
    super.key,
    required this.state,
    required this.contextText,
    required this.answer,
    required this.busy,
    required this.onHint,
    required this.onAnswer,
    required this.onExit,
  });
  final GuidedRepairState state;
  final String contextText;
  final TextEditingController answer;
  final bool busy;
  final VoidCallback onHint, onAnswer, onExit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'การฝึกแบบมีตัวช่วย · guided practice\nไม่เปลี่ยนคำตอบเดิม ไม่เพิ่มคะแนนหรือความชำนาญ',
      ),
      Text('ครั้งที่ ${state.attempts}/3 · คำใบ้ ${state.hintLevel}/2'),
      Text('บริบท: $contextText'),
      if (state.hintLevel >= 1)
        const Text('ลองนึกถึงคำศัพท์ที่ตรงกับความหมายในบริบท'),
      if (state.hintLevel >= 2) Text('อ่านบริบทอีกครั้ง: $contextText'),
      if (state.terminal)
        Text(
          state.correct
              ? 'แก้คำตอบได้แล้ว (มีตัวช่วย)'
              : 'ฝึกครบจำนวนแล้ว กลับไปบทเรียนหรือทบทวนภายหลัง',
        ),
      const Text('พิมพ์คำศัพท์ภาษาอังกฤษ'),
      TextField(
        controller: answer,
        enabled: !busy && !state.terminal,
        maxLength: 256,
        decoration: const InputDecoration(hintText: 'คำศัพท์ภาษาอังกฤษ'),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: busy || state.terminal || state.hintLevel >= 2
                ? null
                : onHint,
            child: const Text('คำใบ้ถัดไป'),
          ),
          FilledButton(
            onPressed: busy || state.terminal ? null : onAnswer,
            child: const Text('ตรวจคำตอบฝึก'),
          ),
          TextButton(onPressed: onExit, child: const Text('กลับไปบทเรียน')),
        ],
      ),
    ],
  );
}
