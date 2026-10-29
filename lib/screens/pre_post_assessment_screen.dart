import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../features/assessment/application/assessment_use_cases.dart';
import '../features/assessment/domain/assessment_models.dart';

final class PrePostAssessmentScreen extends StatefulWidget {
  const PrePostAssessmentScreen({
    super.key,
    required this.useCases,
    required this.command,
    required this.ownerId,
    required this.current,
    required this.onFinished,
    required this.onExit,
    this.languageCode = 'th',
  });

  final AssessmentUseCases useCases;
  final AssessmentStartCommand command;
  final String ownerId;
  final ValueListenable<bool> current;
  final Future<void> Function() onFinished;
  final VoidCallback onExit;
  final String languageCode;

  @override
  State<PrePostAssessmentScreen> createState() =>
      _PrePostAssessmentScreenState();
}

enum _View {
  loading,
  question,
  ready,
  closing,
  finished,
  delivered,
  unavailable,
}

enum _Action { load, response, complete, abandon, delivery }

final class _PendingAnswer {
  const _PendingAnswer(this.itemId, this.option, this.latency);
  final String itemId;
  final String option;
  final int latency;
}

final class _PrePostAssessmentScreenState extends State<PrePostAssessmentScreen>
    with WidgetsBindingObserver {
  _View _view = _View.loading;
  _Action? _retryAction;
  _Action? _terminalIntent;
  AssessmentPresentation? _presentation;
  _PendingAnswer? _pending;
  String? _selected;
  final _answered = <String>{};
  final _itemClock = Stopwatch();
  final _leaseClock = Stopwatch();
  Duration _leaseBudget = Duration.zero;
  Timer? _expiry;
  ModalRoute<dynamic>? _route;
  int _generation = 0;
  bool _started = false;
  bool _busy = false;
  bool _treeVisible = true;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  bool get _thai => widget.languageCode.toLowerCase().startsWith('th');
  String _text(String th, String en) => _thai ? th : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.current.addListener(_bindingChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _treeVisible = Visibility.of(context);
    final routeCurrent = ModalRoute.isCurrentOf(context) == true;
    if (!routeCurrent || !_bindingAlive) {
      _invalidate(notify: false);
    } else {
      _queueLoad();
    }
  }

  @override
  void didUpdateWidget(covariant PrePostAssessmentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.current, widget.current)) {
      oldWidget.current.removeListener(_bindingChanged);
      widget.current.addListener(_bindingChanged);
    }
    if (!identical(oldWidget.useCases, widget.useCases) ||
        oldWidget.ownerId != widget.ownerId ||
        !identical(oldWidget.current, widget.current) ||
        oldWidget.languageCode != widget.languageCode ||
        !_sameCommand(oldWidget.command, widget.command)) {
      _reset();
      if (_bindingAlive) {
        _queueLoad();
      } else {
        _invalidate(notify: false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!mounted) {
      return;
    }
    if (!_foreground) {
      _invalidate();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++;
    _expiry?.cancel();
    _itemClock.stop();
    _leaseClock.stop();
    widget.current.removeListener(_bindingChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool get _bindingAlive =>
      mounted &&
      widget.current.value &&
      _foreground &&
      _treeVisible &&
      _route?.isCurrent == true;

  bool _capture(int generation, {required bool lease}) =>
      generation == _generation &&
      _bindingAlive &&
      _view != _View.unavailable &&
      _view != _View.finished &&
      _view != _View.delivered &&
      (!lease ||
          (_leaseBudget > Duration.zero && _leaseClock.elapsed < _leaseBudget));

  void _bindingChanged() {
    if (!mounted) {
      return;
    }
    if (!widget.current.value) {
      _invalidate();
    } else {
      setState(() {});
    }
  }

  void _reset() {
    _generation++;
    _expiry?.cancel();
    _itemClock
      ..stop()
      ..reset();
    _leaseClock
      ..stop()
      ..reset();
    _leaseBudget = Duration.zero;
    _presentation = null;
    _pending = null;
    _selected = null;
    _answered.clear();
    _retryAction = null;
    _terminalIntent = null;
    _busy = false;
    _started = false;
    _view = _View.loading;
  }

  void _invalidate({bool notify = true}) {
    void burn() {
      _reset();
      _started = true;
      _view = _View.unavailable;
    }

    if (notify && mounted) {
      setState(burn);
    } else {
      burn();
    }
  }

  void _queueLoad() {
    if (_started || _view == _View.unavailable) {
      return;
    }
    _started = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_capture(generation, lease: false)) {
        unawaited(_load(generation));
      }
    });
  }

  Future<void> _load(int generation) async {
    if (!_capture(generation, lease: false) || _busy) {
      return;
    }
    final useCases = widget.useCases;
    final command = widget.command;
    final ownerId = widget.ownerId;
    final elapsed = Stopwatch()..start();
    setState(() {
      _busy = true;
      _retryAction = null;
      _view = _View.loading;
    });
    try {
      final presentation = await useCases.beginPresentation(
        command,
        ownerId: ownerId,
        stillVisible: () => _capture(generation, lease: false),
      );
      elapsed.stop();
      if (!_capture(generation, lease: false)) {
        return;
      }
      final budget =
          presentation.validUntilUtc.difference(presentation.verifiedAtUtc) -
          elapsed.elapsed;
      if (budget <= Duration.zero) {
        _invalidate();
        return;
      }
      _leaseBudget = budget;
      _leaseClock
        ..reset()
        ..start();
      _expiry?.cancel();
      _expiry = Timer(budget, () {
        if (mounted && generation == _generation) {
          _invalidate();
        }
      });
      setState(() {
        _presentation = presentation;
        _answered.addAll(presentation.answeredItemIds);
        _view = _nextItem == null ? _View.ready : _View.question;
        _busy = false;
      });
      _startItemClock(generation);
    } on Object {
      _failed(generation, _Action.load, lease: false);
    } finally {
      elapsed.stop();
    }
  }

  AssessmentPresentationItem? get _nextItem {
    final presentation = _presentation;
    if (presentation == null) {
      return null;
    }
    for (final item in presentation.items) {
      if (!_answered.contains(item.itemId)) {
        return item;
      }
    }
    return null;
  }

  void _startItemClock(int generation) {
    _itemClock
      ..stop()
      ..reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_capture(generation, lease: true) && _view == _View.question) {
        _itemClock.start();
      }
    });
  }

  Future<void> _respond() async {
    final generation = _generation;
    final item = _nextItem;
    if (_busy || item == null || !_capture(generation, lease: true)) {
      return;
    }
    final option = _selected;
    if (_pending == null && option == null) {
      return;
    }
    _itemClock.stop();
    final pending =
        _pending ??
        _PendingAnswer(
          item.itemId,
          option!,
          _itemClock.elapsedMilliseconds.clamp(0, 0x7fffffff).toInt(),
        );
    _pending = pending;
    final useCases = widget.useCases;
    final ownerId = widget.ownerId;
    final runId = widget.command.runId;
    setState(() {
      _busy = true;
      _retryAction = null;
    });
    try {
      await useCases.submitPresentedResponse(
        ownerId: ownerId,
        runId: runId,
        itemId: pending.itemId,
        option: pending.option,
        responseTimeMs: pending.latency,
        stillVisible: () => _capture(generation, lease: true),
      );
      if (!_capture(generation, lease: true)) {
        return;
      }
      setState(() {
        _answered.add(pending.itemId);
        _pending = null;
        _selected = null;
        _retryAction = null;
        _busy = false;
        _view = _nextItem == null ? _View.ready : _View.question;
      });
      _startItemClock(generation);
    } on Object {
      _failed(generation, _Action.response, lease: true);
    }
  }

  Future<void> _close(_Action action) async {
    final generation = _generation;
    if (_busy ||
        !_capture(generation, lease: true) ||
        (_terminalIntent != null && _terminalIntent != action)) {
      return;
    }
    _terminalIntent = action;
    _itemClock.stop();
    final useCases = widget.useCases;
    final ownerId = widget.ownerId;
    final runId = widget.command.runId;
    setState(() {
      _busy = true;
      _retryAction = null;
      _pending = null;
      _selected = null;
      _presentation = null;
      _view = _View.closing;
    });
    try {
      if (action == _Action.complete) {
        await useCases.completePresentation(
          ownerId: ownerId,
          runId: runId,
          stillVisible: () => _capture(generation, lease: true),
        );
      } else {
        await useCases.abandonPresentation(
          ownerId: ownerId,
          runId: runId,
          stillVisible: () => _capture(generation, lease: true),
        );
      }
      if (!_capture(generation, lease: true)) {
        return;
      }
      _expiry?.cancel();
      _leaseClock.stop();
      setState(() {
        _view = _View.finished;
        _busy = false;
      });
      await _deliver(generation);
    } on Object {
      _failed(generation, action, lease: true);
    }
  }

  Future<void> _deliver(int generation) async {
    if (_busy ||
        generation != _generation ||
        !_bindingAlive ||
        _view != _View.finished) {
      return;
    }
    final onFinished = widget.onFinished;
    setState(() {
      _busy = true;
      _retryAction = null;
    });
    try {
      await onFinished();
      if (mounted && generation == _generation && _bindingAlive) {
        setState(() {
          _view = _View.delivered;
          _busy = false;
        });
      }
    } on Object {
      if (mounted && generation == _generation && _bindingAlive) {
        setState(() {
          _retryAction = _Action.delivery;
          _busy = false;
        });
      }
    }
  }

  void _failed(int generation, _Action action, {required bool lease}) {
    if (!_capture(generation, lease: lease)) {
      if (mounted && generation == _generation) {
        _invalidate();
      }
      return;
    }
    setState(() {
      _busy = false;
      _retryAction = action;
    });
  }

  void _retry() {
    switch (_retryAction) {
      case _Action.load:
        unawaited(_load(_generation));
      case _Action.response:
        unawaited(_respond());
      case _Action.complete || _Action.abandon:
        unawaited(_close(_retryAction!));
      case _Action.delivery:
        unawaited(_deliver(_generation));
      case null:
        break;
    }
  }

  void _exit() {
    if (_bindingAlive) {
      final onExit = widget.onExit;
      _invalidate();
      onExit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsLease =
        _view == _View.question ||
        _view == _View.ready ||
        _view == _View.closing;
    final unavailable =
        _view == _View.unavailable ||
        !_bindingAlive ||
        (needsLease && !_capture(_generation, lease: true));
    final item = unavailable || _view != _View.question ? null : _nextItem;
    final status = unavailable
        ? _text(
            'ไม่สามารถทำแบบประเมินได้ กลับไปเรียนต่อได้',
            'Assessment unavailable. You can return to learning.',
          )
        : _status;
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: FocusTraversalGroup(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 360 ? 16 : 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          widget.command.phase == AssessmentPhase.pre
                              ? _text('แบบประเมินก่อนเรียน', 'Pre-assessment')
                              : _text('แบบประเมินหลังเรียน', 'Post-assessment'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _text(
                          'การตอบเป็นทางเลือก คุณออกเพื่อกลับไปเรียนต่อได้',
                          'Responding is optional. You can leave and continue learning.',
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (item != null) ...[
                        Text(
                          _text(
                            'ข้อ ${_answered.length + 1} จาก ${_presentation!.items.length}',
                            'Item ${_answered.length + 1} of ${_presentation!.items.length}',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          header: true,
                          child: Text(
                            item.prompt,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(height: 8),
                        RadioGroup<String>(
                          groupValue: _pending?.option ?? _selected,
                          onChanged: (option) {
                            if (!_busy &&
                                _pending == null &&
                                _capture(_generation, lease: true)) {
                              setState(() => _selected = option);
                            }
                          },
                          child: Column(
                            children: [
                              for (final option in item.options)
                                RadioListTile<String>(
                                  key: ValueKey(
                                    'assessment-option-${item.itemId}-$option',
                                  ),
                                  value: option,
                                  title: Text(option),
                                  enabled: !_busy && _pending == null,
                                  contentPadding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Semantics(
                        key: const ValueKey('assessment-status'),
                        liveRegion: true,
                        label: status,
                        child: ExcludeSemantics(child: Text(status)),
                      ),
                      if (_busy && !unavailable) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                      ],
                      const SizedBox(height: 16),
                      if (!unavailable && item != null && _retryAction == null)
                        FilledButton(
                          key: const ValueKey('assessment-submit'),
                          style: buttonStyle,
                          onPressed: _busy || _selected == null
                              ? null
                              : () => unawaited(_respond()),
                          child: Text(_text('ส่งคำตอบ', 'Submit answer')),
                        ),
                      if (!unavailable && _retryAction != null)
                        OutlinedButton(
                          key: const ValueKey('assessment-retry'),
                          style: buttonStyle,
                          onPressed: _busy ? null : _retry,
                          child: Text(
                            _retryAction == _Action.delivery
                                ? _text('ลองไปต่ออีกครั้ง', 'Retry continuing')
                                : _text(
                                    'ลองยืนยันอีกครั้ง',
                                    'Retry confirmation',
                                  ),
                          ),
                        ),
                      if (!unavailable && _view == _View.ready)
                        FilledButton(
                          key: const ValueKey('assessment-finish'),
                          style: buttonStyle,
                          onPressed: _busy
                              ? null
                              : () => unawaited(_close(_Action.complete)),
                          child: Text(
                            _text('ยืนยันจบแบบประเมิน', 'Finish assessment'),
                          ),
                        ),
                      if (!unavailable &&
                          (_view == _View.question ||
                              _view == _View.ready)) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          key: const ValueKey('assessment-leave'),
                          style: buttonStyle,
                          onPressed: _busy
                              ? null
                              : () => unawaited(_close(_Action.abandon)),
                          child: Text(
                            _text('ออกจากแบบประเมิน', 'Leave assessment'),
                          ),
                        ),
                      ],
                      if (unavailable ||
                          (_view == _View.loading && _retryAction != null))
                        TextButton(
                          key: const ValueKey('assessment-exit'),
                          style: buttonStyle,
                          onPressed: _bindingAlive ? _exit : null,
                          child: Text(
                            _text('กลับไปเรียนต่อ', 'Return to learning'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _status {
    if (_retryAction == _Action.delivery) {
      return _text(
        'บันทึกแล้ว แต่ยังไปต่อไม่ได้ ลองไปต่ออีกครั้ง',
        'Saved, but continuing failed. Try continuing again.',
      );
    }
    if (_retryAction != null) {
      return _text(
        'ยังไม่ได้รับการยืนยัน ลองยืนยันคำสั่งเดิมอีกครั้ง',
        'Confirmation is unavailable. Retry the same action.',
      );
    }
    return switch (_view) {
      _View.loading => _text('กำลังเปิดแบบประเมิน', 'Opening assessment'),
      _View.question =>
        _busy
            ? _text('กำลังบันทึกคำตอบ', 'Saving response')
            : _text('เลือกคำตอบที่ตรงที่สุด', 'Choose the best answer'),
      _View.ready => _text(
        'ตอบครบแล้ว ยืนยันเพื่อจบแบบประเมิน',
        'All responses received. Confirm to finish.',
      ),
      _View.closing => _text('กำลังยืนยันการบันทึก', 'Confirming saved work'),
      _View.finished => _text('บันทึกแล้ว กำลังไปต่อ', 'Saved. Continuing.'),
      _View.delivered => _text('จบแบบประเมินแล้ว', 'Assessment finished'),
      _View.unavailable => _text(
        'ไม่สามารถทำแบบประเมินได้',
        'Assessment unavailable',
      ),
    };
  }
}

bool _sameCommand(AssessmentStartCommand a, AssessmentStartCommand b) =>
    a.runId == b.runId &&
    a.learningSessionId == b.learningSessionId &&
    a.studyCycleId == b.studyCycleId &&
    a.phase == b.phase &&
    a.instrumentId == b.instrumentId &&
    a.instrumentVersion == b.instrumentVersion &&
    a.formId == b.formId &&
    a.formVersion == b.formVersion;
