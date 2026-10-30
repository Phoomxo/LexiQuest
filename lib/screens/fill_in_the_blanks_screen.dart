import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../runtime/app_dependencies.dart';

class FillInTheBlanksScreen extends StatefulWidget {
  const FillInTheBlanksScreen({
    super.key,
    required this.session,
    required this.learning,
    this.ownerChanges,
    this.languageCode = 'th',
  });
  final ClozeSession session;
  final LearningUseCases learning;
  final Stream<String?>? ownerChanges;
  final String languageCode;

  @override
  State<FillInTheBlanksScreen> createState() => _FillInTheBlanksScreenState();
}

enum _Step {
  starting,
  answering,
  saving,
  saved,
  finishing,
  startFailed,
  saveFailed,
  finishFailed,
}

class _FillInTheBlanksScreenState extends State<FillInTheBlanksScreen>
    with WidgetsBindingObserver {
  final _response = TextEditingController();
  final _latency = Stopwatch();
  AppDependencies? _dependencies;
  StreamSubscription<String?>? _owners;
  bool _bound = false;
  bool _invalidated = false;
  bool _routeVisible = false;
  bool _startRequested = false;
  String? _ownerId;
  String? _selected;
  int _epoch = 0;
  _Step _step = _Step.starting;
  RecordAnswerCommand? _pendingAnswer;
  NativeFinishIntent? _pendingFinish;

  String _copy(String th, String en) => widget.languageCode == 'th' ? th : en;

  String get _meaningCue => widget.session.word.meaning.replaceAll(
    RegExp(
      r'\b' + RegExp.escape(widget.session.word.spelling) + r'\b',
      caseSensitive: false,
    ),
    '_____',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    if (!_bound) {
      _bind(dependencies);
    } else if (!identical(_dependencies, dependencies)) {
      _invalidate();
    }
    final visible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    if (_routeVisible && !visible) {
      _invalidate();
    }
    _routeVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
  }

  void _bind(AppDependencies? dependencies) {
    _bound = true;
    _dependencies = dependencies;
    final source =
        widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
    if (source == null) {
      _invalidated = true;
      return;
    }
    _owners = source.listen(
      (ownerId) {
        if (!mounted || _invalidated) {
          return;
        }
        if (ownerId == null ||
            ownerId != widget.session.ownerId ||
            (_ownerId != null && ownerId != _ownerId)) {
          _invalidate();
          return;
        }
        setState(() => _ownerId = ownerId);
        _tryStart();
      },
      onError: (Object _, StackTrace _) => _invalidate(),
      onDone: _invalidate,
    );
  }

  @override
  void didUpdateWidget(covariant FillInTheBlanksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        !identical(widget.learning, oldWidget.learning) ||
        !identical(widget.ownerChanges, oldWidget.ownerChanges) ||
        widget.languageCode != oldWidget.languageCode) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _invalidate();
    }
  }

  bool _current(int epoch) =>
      mounted &&
      !_invalidated &&
      epoch == _epoch &&
      _ownerId == widget.session.ownerId &&
      _routeVisible &&
      ModalRoute.of(context)?.isCurrent == true &&
      Visibility.of(context) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _canAnswer => _current(_epoch) && _step == _Step.answering;

  void _invalidate() {
    if (!mounted || _invalidated) {
      return;
    }
    _epoch++;
    _latency.stop();
    _response.clear();
    setState(() {
      _selected = null;
      _invalidated = true;
    });
  }

  void _tryStart() {
    if (_startRequested || !_current(_epoch)) {
      return;
    }
    _startRequested = true;
    unawaited(_start());
  }

  Future<void> _start() async {
    final epoch = _epoch;
    if (!_current(epoch)) {
      return;
    }
    setState(() => _step = _Step.starting);
    try {
      await widget.learning.startNativeExercise(
        widget.session,
        stillCurrent: () => _current(epoch),
      );
      if (!_current(epoch)) {
        return;
      }
      _latency.start();
      setState(() => _step = _Step.answering);
    } on Object {
      if (_current(epoch)) {
        setState(() => _step = _Step.startFailed);
      }
    }
  }

  Future<void> _save() async {
    final epoch = _epoch;
    final retry = _step == _Step.saveFailed;
    final hasAnswer = widget.session is TypedClozeSession
        ? _response.text.trim().isNotEmpty
        : _selected != null;
    if (!_current(epoch) || (!retry && (!_canAnswer || !hasAnswer))) {
      return;
    }
    try {
      _pendingAnswer ??= widget.learning.prepareNativeAnswer(
        switch (widget.session) {
          final TypedClozeSession exercise => TypedClozeAnswerInput(
            exercise: exercise,
            response: _response.text,
            responseTime: _latency.elapsed,
          ),
          final ChoiceClozeSession exercise => ChoiceClozeAnswerInput(
            exercise: exercise,
            optionId: _selected!,
            responseTime: _latency.elapsed,
          ),
        },
      );
    } on Object {
      setState(() => _step = _Step.saveFailed);
      return;
    }
    _latency.stop();
    setState(() => _step = _Step.saving);
    try {
      await widget.learning.commitNativeAnswer(
        widget.session,
        _pendingAnswer!,
        stillCurrent: () => _current(epoch),
      );
      if (!_current(epoch)) {
        return;
      }
      setState(() => _step = _Step.saved);
    } on Object {
      if (_current(epoch)) {
        setState(() => _step = _Step.saveFailed);
      }
    }
  }

  Future<void> _finish() async {
    final epoch = _epoch;
    if (!_current(epoch) ||
        (_step != _Step.saved && _step != _Step.finishFailed)) {
      return;
    }
    try {
      _pendingFinish ??= widget.learning.prepareNativeFinish(
        widget.session,
        _pendingAnswer!,
      );
    } on Object {
      setState(() => _step = _Step.finishFailed);
      return;
    }
    setState(() => _step = _Step.finishing);
    try {
      final summary = await widget.learning.finishNativeExercise(
        _pendingFinish!,
        stillCurrent: () => _current(epoch),
      );
      if (!mounted || !_current(epoch)) {
        return;
      }
      Navigator.of(context).pop(summary);
    } on Object {
      if (_current(epoch)) {
        setState(() => _step = _Step.finishFailed);
      }
    }
  }

  void _back() {
    _invalidate();
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _epoch++;
    _invalidated = true;
    _owners?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _latency.stop();
    _response.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failed =
        _step == _Step.startFailed ||
        _step == _Step.saveFailed ||
        _step == _Step.finishFailed;
    final saved =
        _step == _Step.saved ||
        _step == _Step.finishing ||
        _step == _Step.finishFailed;
    final busy =
        _step == _Step.starting ||
        _step == _Step.saving ||
        _step == _Step.finishing;
    final showForm = _step != _Step.starting && _step != _Step.startFailed;
    final hasAnswer = widget.session is TypedClozeSession
        ? _response.text.trim().isNotEmpty
        : _selected != null;
    return PopScope<LearningSessionSummary>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _invalidate();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(
            context,
            _copy('เติมคำในบริบท', 'Complete the sentence'),
          ),
          leading: IconButton(
            key: const ValueKey('cloze-back'),
            tooltip: _copy('กลับ', 'Back'),
            onPressed: _back,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_invalidated) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _copy(
                        'กิจกรรมนี้ไม่พร้อมใช้งาน กลับไปเริ่มใหม่เมื่อพร้อม',
                        'This activity is no longer available. Go back to start again.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _back,
                    child: Text(_copy('กลับไปหน้าเรียน', 'Back to learning')),
                  ),
                ] else ...[
                  Text(
                    _copy(
                      'เติมคำศัพท์เป้าหมายตามความหมายนี้ในช่องว่าง',
                      'Fill the gap with your target vocabulary word for this meaning.',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _copy(
                      'ประโยคสร้างด้วย AI · ฝึกแบบมีตัวช่วย',
                      'AI-generated context · assisted practice',
                    ),
                  ),
                  if (showForm) ...[
                    const SizedBox(height: 16),
                    Text(
                      key: const ValueKey('cloze-meaning-cue'),
                      _copy(
                        'ความหมายของคำเป้าหมาย: $_meaningCue',
                        'Target vocabulary meaning: $_meaningCue',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      key: const ValueKey('cloze-context'),
                      '${widget.session.content.prefix}_____${widget.session.content.suffix}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    if (widget.session case ChoiceClozeSession(:final choices))
                      RadioGroup<String>(
                        groupValue: _selected,
                        onChanged: (value) {
                          if (_canAnswer) {
                            setState(() => _selected = value);
                          }
                        },
                        child: Column(
                          children: [
                            for (final word in choices)
                              RadioListTile<String>(
                                key: ValueKey('cloze-option-${word.id}'),
                                value: word.id,
                                enabled: _canAnswer,
                                title: Text(word.spelling),
                              ),
                          ],
                        ),
                      )
                    else
                      TextField(
                        key: const ValueKey('cloze-response'),
                        controller: _response,
                        enabled: _canAnswer,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: _copy('คำที่ขาดหายไป', 'Missing word'),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _save(),
                      ),
                    const SizedBox(height: 16),
                    if (!saved)
                      FilledButton(
                        key: const ValueKey('cloze-save'),
                        onPressed: _canAnswer && hasAnswer ? _save : null,
                        child: Text(_copy('บันทึกคำตอบ', 'Save answer')),
                      ),
                  ],
                  if (busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      key: const ValueKey('cloze-status'),
                      _copy(
                        failed
                            ? 'ยังยืนยันผลไม่ได้ กรุณาลองส่งรายการเดิมอีกครั้ง'
                            : busy
                            ? 'กำลังดำเนินการ…'
                            : saved
                            ? 'บันทึกคำตอบแล้ว กดเสร็จสิ้นเพื่อปิดกิจกรรม'
                            : 'ตอบเมื่อพร้อม แล้วกดบันทึกคำตอบ',
                        failed
                            ? 'Confirmation is unavailable. Retry the original request.'
                            : busy
                            ? 'Working…'
                            : saved
                            ? 'Answer saved. Finish to close this activity.'
                            : 'Answer when ready, then save your response.',
                      ),
                    ),
                  ),
                  if (failed) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('cloze-retry'),
                      onPressed: () => switch (_step) {
                        _Step.startFailed => _start(),
                        _Step.saveFailed => _save(),
                        _Step.finishFailed => _finish(),
                        _ => Future<void>.value(),
                      },
                      child: Text(_copy('ลองส่งอีกครั้ง', 'Retry')),
                    ),
                  ],
                  if (saved) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        key: const ValueKey('cloze-feedback'),
                        _pendingAnswer!.isCorrect
                            ? _copy(
                                'ตรงกับคำศัพท์เป้าหมาย · ${widget.session.word.spelling}',
                                'Matches the target word · ${widget.session.word.spelling}',
                              )
                            : _copy(
                                'คำศัพท์เป้าหมายคือ ${widget.session.word.spelling}',
                                'The target vocabulary word is ${widget.session.word.spelling}',
                              ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('cloze-finish'),
                      onPressed: _step == _Step.saved ? _finish : null,
                      child: Text(_copy('เสร็จสิ้น', 'Finish')),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
