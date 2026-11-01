import 'dart:async';

import 'package:flutter/material.dart';

import '../features/content_reports/presentation/content_report_button.dart';
import '../features/learning/domain/learning_evidence_contract.dart';
import '../features/learning/domain/learning_time_admission.dart';
import '../features/learning/presentation/lesson_scaffold.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/presentation/native_exercise_checkpoint_binding.dart';
import '../runtime/app_dependencies.dart';

export '../features/learning/domain/word_scramble_letters.dart'
    show createStableScramble;

class WordScrambleScreen extends StatefulWidget {
  const WordScrambleScreen({
    super.key,
    required this.session,
    required this.learning,
    this.resumeState,
    this.ownerChanges,
    this.languageCode = 'th',
  });
  final WordScrambleSession session;
  final LearningUseCases learning;
  final NativeExerciseState? resumeState;
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
  bool _reportOverlay = false;
  bool _startRequested = false;
  String? _ownerId;
  late final List<int?> _slots;
  late final List<FocusNode> _letterFocus;
  final _filledSlots = <int>[];
  int _epoch = 0;
  _Step _step = _Step.starting;
  NativeExerciseCheckpointBinding? _checkpoint;
  RecordAnswerCommand? get _pendingAnswer =>
      _invalidated ? null : _checkpoint?.answer;
  bool _draftBusy = false;
  bool _draftFailed = false;
  bool _draftDirty = false;
  List<int?>? _tileDraft;

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
    if (_routeVisible && !visible && !_reportOverlay) {
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
        !identical(widget.resumeState, oldWidget.resumeState) ||
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
  bool get _canAnswer =>
      _current(_epoch) &&
      _step == _Step.answering &&
      !_draftBusy &&
      _checkpoint?.hasPendingDraft != true;

  void _invalidate() {
    if (!mounted || _invalidated) {
      return;
    }
    _epoch++;
    _checkpoint?.retire();
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

  NativeExerciseDraft _captureDraft() => NativeExerciseDraft(
    text: _tileDraft == null ? _response.text : _arranged,
    tileSlots: _tileDraft,
    responseTimeMs: _checkpoint!.elapsedMilliseconds(_latency.elapsed),
  );

  void _restoreCheckpoint() {
    final state = _checkpoint!.state!;
    final draft = state.checkpoint.draft;
    _latency
      ..stop()
      ..reset();
    _response.text = draft.tileSlots == null ? draft.text : '';
    _slots.setAll(0, draft.tileSlots ?? List<int?>.filled(_slots.length, null));
    _tileDraft = draft.tileSlots == null ? null : _slots;
    _filledSlots.clear();
    _draftDirty = false;
    _step = switch (state.phase) {
      NativeCheckpointPhase.awaitingAnswer => _Step.answering,
      NativeCheckpointPhase.pendingAnswer => _Step.saveFailed,
      NativeCheckpointPhase.answered ||
      NativeCheckpointPhase.completed => _Step.saved,
      NativeCheckpointPhase.closing => _Step.finishFailed,
      NativeCheckpointPhase.abandoned => _Step.startFailed,
    };
    if (_step == _Step.answering) _latency.start();
  }

  Future<void> _start() async {
    final epoch = _epoch;
    if (!_current(epoch)) return;
    setState(() => _step = _Step.starting);
    _checkpoint ??= NativeExerciseCheckpointBinding(
      learning: widget.learning,
      display: widget.session,
      resumeState: widget.resumeState,
      stillCurrent: () => _current(epoch),
    );
    try {
      await _checkpoint!.initialize();
      if (!_current(epoch)) return;
      setState(_restoreCheckpoint);
    } on Object {
      if (_current(epoch)) setState(() => _step = _Step.startFailed);
    }
  }

  Future<void> _saveDraft() async {
    final epoch = _epoch;
    if (!_current(epoch) || _draftBusy || _step != _Step.answering) return;
    _latency.stop();
    setState(() {
      _draftBusy = true;
      _draftFailed = false;
    });
    try {
      await _checkpoint!.saveDraft(
        _checkpoint!.hasPendingDraft ? null : _captureDraft(),
      );
      if (_current(epoch)) setState(_restoreCheckpoint);
    } on Object {
      if (_current(epoch)) setState(() => _draftFailed = true);
    } finally {
      if (_current(epoch)) setState(() => _draftBusy = false);
    }
  }

  Future<void> _save() async {
    final epoch = _epoch;
    final retry = _step == _Step.saveFailed;
    if (!_current(epoch) || (!retry && (!_canAnswer || !_hasAnswer))) return;
    _latency.stop();
    setState(() => _step = _Step.saving);
    try {
      await _checkpoint!.saveAnswer(
        _checkpoint!.hasPendingInput ? null : _captureDraft(),
      );
      if (_current(epoch)) setState(_restoreCheckpoint);
    } on Object {
      if (_current(epoch)) setState(() => _step = _Step.saveFailed);
    }
  }

  Future<void> _finish() async {
    final epoch = _epoch;
    if (!_current(epoch) ||
        (_step != _Step.saved && _step != _Step.finishFailed)) {
      return;
    }
    setState(() => _step = _Step.finishing);
    try {
      final summary = await _checkpoint!.finish();
      if (mounted && _current(epoch)) {
        Navigator.of(context).pop(summary);
      }
    } on Object {
      if (_current(epoch)) setState(() => _step = _Step.finishFailed);
    }
  }

  Widget _draftPanel() {
    final state = _checkpoint!.state!;
    final awaiting = state.phase == NativeCheckpointPhase.awaitingAnswer;
    final message = _draftBusy
        ? _copy('กำลังบันทึกฉบับร่าง', 'Saving draft')
        : _draftFailed
        ? _copy(
            'ยังยืนยันฉบับร่างไม่ได้ ลองบันทึกอีกครั้ง',
            'Draft save is not confirmed. Retry saving.',
          )
        : _draftDirty
        ? _copy('มีการแก้ไขที่ยังไม่ได้บันทึก', 'Unsaved changes')
        : awaiting
        ? (widget.resumeState != null || state.checkpointRevision > 1
              ? _copy(
                  'ฉบับร่างบันทึกแล้ว ยังไม่เป็นคำตอบที่ส่ง',
                  'Draft saved. Answer not recorded.',
                )
              : _copy('ฉบับร่างยังไม่ได้บันทึก', 'Draft not saved'))
        : state.phase == NativeCheckpointPhase.pendingAnswer
        ? _copy(
            'ฉบับร่างบันทึกแล้ว รอยืนยันคำตอบเดิม',
            'Draft saved. Confirm the original answer.',
          )
        : _copy('คำตอบบันทึกแล้ว', 'Answer recorded');
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(message, key: const ValueKey('native-draft-status')),
          ),
          if (awaiting)
            OutlinedButton.icon(
              key: const ValueKey('native-draft-save'),
              onPressed:
                  _current(_epoch) && !_draftBusy && _step == _Step.answering
                  ? _saveDraft
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                _copy(
                  _checkpoint!.hasPendingDraft
                      ? 'ลองบันทึกฉบับร่างอีกครั้ง'
                      : 'บันทึกฉบับร่าง',
                  _checkpoint!.hasPendingDraft
                      ? 'Retry draft save'
                      : 'Save draft',
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _back() {
    _invalidate();
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _epoch++;
    _checkpoint?.retire();
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
      _tileDraft = _slots;
      _draftDirty = true;
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
      _draftDirty = true;
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
      _draftDirty = true;
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
      child: LessonScaffold(
        title: _copy('เกมเรียงตัวอักษร', 'Word Scramble'),
        leading: IconButton(
          key: const ValueKey('scramble-back'),
          tooltip: _copy('กลับ', 'Back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!_invalidated) ...[
              LessonProgress(
                current: 1,
                total: 1,
                languageCode: widget.languageCode,
              ),
              const SizedBox(height: 24),
            ],
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
                _copy('เกมคำศัพท์เพื่อความสนุก', 'A vocabulary game for fun.'),
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
                      _tileDraft = null;
                      _draftDirty = true;
                      _slots.fillRange(0, _slots.length, null);
                      _filledSlots.clear();
                    });
                  },
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                if (!saved)
                  if (_checkpoint?.state != null) _draftPanel(),
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
                if (_step == _Step.saved &&
                    LearningEvidenceContract.isOrdinaryEvidence(
                      _pendingAnswer!.evidenceContext,
                    ))
                  ContentReportButton.ownedWord(
                    key: const ValueKey('content-report-word-scramble'),
                    expectedOwnerId: widget.session.ownerId,
                    word: widget.session.word,
                    sessionId: widget.session.id,
                    callerContext: LearningTimeCallerContext.ordinary,
                    canOpen: () => _current(_epoch) && _step == _Step.saved,
                    onOverlayChanged: (open) {
                      _reportOverlay = open;
                    },
                    languageCode: widget.languageCode,
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
