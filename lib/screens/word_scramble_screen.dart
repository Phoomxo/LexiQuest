import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../runtime/app_dependencies.dart';

export '../features/learning/domain/word_scramble_letters.dart'
    show createStableScramble;

class WordScrambleScreen extends StatefulWidget {
  const WordScrambleScreen({
    super.key,
    required this.session,
    required this.learning,
    this.ownerChanges,
    this.languageCode = 'th',
  });
  final WordScrambleSession session;
  final LearningUseCases learning;
  final Stream<String?>? ownerChanges;
  final String languageCode;

  @override
  State<WordScrambleScreen> createState() => _WordScrambleScreenState();
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

class _WordScrambleScreenState extends State<WordScrambleScreen>
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
  late final List<int?> _slots;
  late final List<FocusNode> _letterFocus;
  final _filledSlots = <int>[];
  int _epoch = 0;
  _Step _step = _Step.starting;
  RecordAnswerCommand? _pendingAnswer;
  NativeFinishIntent? _pendingFinish;

  String _copy(String th, String en) => widget.languageCode == 'th' ? th : en;

  String get _meaningCue => widget.session.word.meaning.replaceAll(
    RegExp(
      r'(?<![\p{L}\p{N}\p{M}\p{Pc}])' +
          RegExp.escape(widget.session.word.spelling) +
          r'(?![\p{L}\p{N}\p{M}\p{Pc}])',
      caseSensitive: false,
      unicode: true,
    ),
    '_____',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _slots = List<int?>.filled(widget.session.letters.length, null);
    _letterFocus = List.generate(
      widget.session.letters.length,
      (_) => FocusNode(),
    );
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
  void didUpdateWidget(covariant WordScrambleScreen oldWidget) {
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
      _slots.fillRange(0, _slots.length, null);
      _filledSlots.clear();
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
    final hasAnswer = _hasAnswer;
    if (!_current(epoch) || (!retry && (!_canAnswer || !hasAnswer))) {
      return;
    }
    try {
      _pendingAnswer ??= widget.learning.prepareNativeAnswer(
        WordScrambleAnswerInput(
          exercise: widget.session,
          response: _response.text.isNotEmpty ? _response.text : _arranged,
          responseTime: _latency.elapsed,
        ),
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
    for (final node in _letterFocus) {
      node.dispose();
    }
    super.dispose();
  }

  String get _arranged => _slots
      .whereType<int>()
      .map((index) => widget.session.letters[index])
      .join();
  bool get _hasAnswer =>
      _response.text.trim().isNotEmpty ||
      _slots.every((index) => index != null);
  bool _canUse(int sourceIndex) =>
      _canAnswer &&
      _pendingAnswer == null &&
      sourceIndex >= 0 &&
      sourceIndex < widget.session.letters.length &&
      !_slots.contains(sourceIndex);
  bool _canDrop(int slotIndex, int sourceIndex) =>
      _canUse(sourceIndex) &&
      slotIndex >= 0 &&
      slotIndex < _slots.length &&
      _slots[slotIndex] == null;

  void _drop(int slotIndex, int sourceIndex) {
    if (!_canDrop(slotIndex, sourceIndex)) {
      return;
    }
    setState(() {
      _response.clear();
      _slots[slotIndex] = sourceIndex;
      _filledSlots.add(slotIndex);
    });
  }

  void _pick(int sourceIndex) {
    final slot = _slots.indexOf(null);
    if (slot >= 0) {
      _drop(slot, sourceIndex);
    }
  }

  void _undo() {
    if (!_canAnswer || _pendingAnswer != null) {
      return;
    }
    setState(() {
      if (_response.text.isNotEmpty) {
        _response.text = _response.text.characters
            .take(_response.text.characters.length - 1)
            .join();
        _response.selection = TextSelection.collapsed(
          offset: _response.text.length,
        );
      } else if (_filledSlots.isNotEmpty) {
        _slots[_filledSlots.removeLast()] = null;
      }
    });
  }

  void _clear() {
    if (!_canAnswer || _pendingAnswer != null) {
      return;
    }
    setState(() {
      _response.clear();
      _slots.fillRange(0, _slots.length, null);
      _filledSlots.clear();
    });
  }

  Widget _slot(int index) => DragTarget<int>(
    key: ValueKey('scramble-slot-$index'),
    onWillAcceptWithDetails: (details) => _canDrop(index, details.data),
    onAcceptWithDetails: (details) => _drop(index, details.data),
    builder: (context, candidates, rejected) => AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      constraints: const BoxConstraints(minWidth: 52, minHeight: 56),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _slots[index] != null
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Text(
        _slots[index] == null ? ' ' : widget.session.letters[_slots[index]!],
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ),
  );

  Widget _letter(int index) {
    final letter = widget.session.letters[index];
    final available = _canUse(index);
    Widget feedback() => Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(letter, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
    return Draggable<int>(
      data: index,
      maxSimultaneousDrags: available ? 1 : 0,
      feedback: feedback(),
      childWhenDragging: Opacity(opacity: 0.3, child: feedback()),
      child: OutlinedButton(
        key: ValueKey('scramble-letter-$index'),
        focusNode: _letterFocus[index],
        onPressed: available ? () => _pick(index) : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(56, 56),
          padding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(letter, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
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
            _copy('เกมเรียงตัวอักษร', 'Word Scramble'),
          ),
          leading: IconButton(
            key: const ValueKey('scramble-back'),
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
                      'เรียงตัวอักษรให้เป็นคำศัพท์ตามความหมาย',
                      'Arrange the letters to match the meaning.',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _copy(
                      'เกมคำศัพท์เพื่อความสนุก',
                      'A vocabulary game for fun.',
                    ),
                  ),
                  if (showForm) ...[
                    const SizedBox(height: 16),
                    Text(
                      key: const ValueKey('scramble-meaning-cue'),
                      _copy(
                        'ความหมายของคำเป้าหมาย: $_meaningCue',
                        'Target vocabulary meaning: $_meaningCue',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _copy(
                        'ช่องคำตอบ · ลากตัวอักษรลงช่องหรือกดเลือกตามลำดับ',
                        'Answer slots · drag a letter into a slot, or tap letters in order.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(_slots.length, _slot),
                    ),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        key: const ValueKey('scramble-arranged'),
                        _arranged,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List.generate(
                        widget.session.letters.length,
                        _letter,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          key: const ValueKey('scramble-undo'),
                          onPressed:
                              _canAnswer &&
                                  (_filledSlots.isNotEmpty ||
                                      _response.text.isNotEmpty)
                              ? _undo
                              : null,
                          child: Text(_copy('ย้อนกลับ', 'Undo')),
                        ),
                        OutlinedButton(
                          key: const ValueKey('scramble-clear'),
                          onPressed:
                              _canAnswer &&
                                  (_filledSlots.isNotEmpty ||
                                      _response.text.isNotEmpty)
                              ? _clear
                              : null,
                          child: Text(_copy('ล้างคำตอบ', 'Clear')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      key: const ValueKey('scramble-response'),
                      controller: _response,
                      enabled: _canAnswer,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: _copy(
                          'หรือพิมพ์คำตอบแทนการเรียง',
                          'Or type your answer',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (!_canAnswer) {
                          return;
                        }
                        setState(() {
                          _slots.fillRange(0, _slots.length, null);
                          _filledSlots.clear();
                        });
                      },
                      onSubmitted: (_) => _save(),
                    ),
                    const SizedBox(height: 16),
                    if (!saved)
                      FilledButton(
                        key: const ValueKey('scramble-save'),
                        onPressed: _canAnswer && _hasAnswer ? _save : null,
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
                      key: const ValueKey('scramble-status'),
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
                      key: const ValueKey('scramble-retry'),
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
                        key: const ValueKey('scramble-feedback'),
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
                      key: const ValueKey('scramble-finish'),
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
