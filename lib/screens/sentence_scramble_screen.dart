import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../features/content_reports/domain/content_report.dart';
import '../features/content_reports/presentation/content_report_button.dart';
import '../features/learning/domain/learning_evidence_contract.dart';
import '../features/learning/domain/learning_time_admission.dart';
import '../features/learning/presentation/lesson_scaffold.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/sentence_scramble_content.dart';
import '../features/learning/presentation/native_exercise_checkpoint_binding.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';

class SentenceScrambleScreen extends StatefulWidget {
  const SentenceScrambleScreen({
    super.key,
    required this.session,
    required this.learning,
    this.resumeState,
    this.ownerChanges,
    this.voice,
    this.languageCode = 'th',
  });
  final SentenceScrambleSession session;
  final LearningUseCases learning;
  final NativeExerciseState? resumeState;
  final Stream<String?>? ownerChanges;
  final VoiceUseCases? voice;
  final String languageCode;

  @override
  State<SentenceScrambleScreen> createState() => _SentenceScrambleScreenState();
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

class _SentenceScrambleScreenState extends State<SentenceScrambleScreen>
    with WidgetsBindingObserver {
  final _response = TextEditingController();
  final _latency = Stopwatch();
  AppDependencies? _dependencies;
  VoiceUseCases? _voice;
  StreamSubscription<String?>? _owners;
  ModalRoute<dynamic>? _route;
  ModalRoute<dynamic>? _exitDialogRoute;
  late final List<String> _bank;
  late final List<int?> _slots;
  late final List<FocusNode> _tokenFocus;
  final _filledSlots = <int>[];
  bool _bound = false;
  bool _invalidated = false;
  bool _routeVisible = false;
  bool _reportOverlay = false;
  bool _startRequested = false;
  bool _writeInFlight = false;
  bool _redrawScheduled = false;
  bool _confirmingExit = false;
  bool _exitDialogCovered = false;
  bool _exitDialogClosing = false;
  StateSetter? _exitDialogRedraw;
  bool _allowPop = false;
  bool _ownsPlayback = false;
  bool _voiceBusy = false;
  bool _heardOriginal = false;
  bool _voiceFailed = false;
  Future<void>? _playbackStop;
  String? _ownerId;
  int _epoch = 0;
  int _audioEpoch = 0;
  _Step _step = _Step.starting;
  NativeExerciseCheckpointBinding? _checkpoint;
  RecordAnswerCommand? get _pendingAnswer =>
      _invalidated ? null : _checkpoint?.answer;
  bool _draftBusy = false;
  bool _draftFailed = false;
  bool _draftDirty = false;
  List<int?>? _tileDraft;

  String _copy(String th, String en) => widget.languageCode == 'th' ? th : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bank = List<String>.unmodifiable([
      for (final index in widget.session.tokenOrder)
        widget.session.content.tokens[index],
    ]);
    _slots = List<int?>.filled(_bank.length, null);
    _tokenFocus = List.generate(_bank.length, (_) => FocusNode());
  }

  void _redraw() {
    if (!mounted) return;
    void update() {
      if (!mounted) return;
      if (_invalidated) _response.clear();
      setState(() {});
      if (_confirmingExit && _exitDialogRoute?.isCurrent == true) {
        _exitDialogRedraw?.call(() {});
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_redrawScheduled) return;
      _redrawScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _redrawScheduled = false;
        update();
      });
    } else {
      update();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final dependencies = AppDependenciesScope.maybeOf(context);
    final voice = widget.voice ?? dependencies?.voice;
    if (!_bound) {
      _bound = true;
      _dependencies = dependencies;
      _voice = voice;
      final source =
          widget.ownerChanges ?? dependencies?.progress?.watchActiveOwnerId();
      if (source == null) {
        _invalidate();
      } else {
        _owners = source.listen(
          (owner) {
            if (!mounted || _invalidated) return;
            if (owner == null ||
                owner != widget.session.ownerId ||
                (_ownerId != null && owner != _ownerId)) {
              _invalidate();
              return;
            }
            _ownerId = owner;
            _redraw();
            WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
          },
          onError: (Object _, StackTrace _) => _invalidate(),
          onDone: _invalidate,
        );
      }
    } else if (!identical(_dependencies, dependencies) ||
        !identical(_voice, voice)) {
      _invalidate();
    }
    final visible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    if ((_routeVisible && !visible && !_confirmingExit && !_reportOverlay) ||
        !Visibility.of(context)) {
      _invalidate();
    }
    _routeVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
  }

  @override
  void didUpdateWidget(covariant SentenceScrambleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        !identical(widget.resumeState, oldWidget.resumeState) ||
        !identical(widget.learning, oldWidget.learning) ||
        !identical(widget.ownerChanges, oldWidget.ownerChanges) ||
        !identical(widget.voice, oldWidget.voice) ||
        widget.languageCode != oldWidget.languageCode) {
      _invalidate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _invalidate();
  }

  bool _current(int epoch) =>
      mounted &&
      !_invalidated &&
      epoch == _epoch &&
      _ownerId == widget.session.ownerId &&
      !_confirmingExit &&
      _routeVisible &&
      _route?.isCurrent == true &&
      Visibility.of(context) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _canAnswer =>
      _current(_epoch) &&
      _step == _Step.answering &&
      _pendingAnswer == null &&
      !_draftBusy &&
      _checkpoint?.hasPendingDraft != true;
  bool get _canListen =>
      _current(_epoch) &&
      !_draftBusy &&
      _checkpoint?.hasPendingDraft != true &&
      _voice != null &&
      widget.session.content.sentence.length <= 500;

  void _invalidate() {
    if (!mounted || _invalidated) return;
    _invalidated = true;
    _epoch++;
    _checkpoint?.retire();
    _latency.stop();
    _slots.fillRange(0, _slots.length, null);
    _filledSlots.clear();
    unawaited(_stopPlayback());
    _redraw();
  }

  void _tryStart() {
    if (_startRequested || !_current(_epoch)) return;
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
    if (!_current(epoch) || _writeInFlight) return;
    _step = _Step.starting;
    _writeInFlight = true;
    _redraw();
    _checkpoint ??= NativeExerciseCheckpointBinding(
      learning: widget.learning,
      display: widget.session,
      resumeState: widget.resumeState,
      stillCurrent: () => _current(epoch),
    );
    try {
      await _checkpoint!.initialize();
      if (_current(epoch)) _restoreCheckpoint();
    } on Object {
      if (_current(epoch)) _step = _Step.startFailed;
    } finally {
      _writeInFlight = false;
      _redraw();
    }
  }

  Future<void> _saveDraft() async {
    final epoch = _epoch;
    if (!_current(epoch) || _writeInFlight || _step != _Step.answering) return;
    _latency.stop();
    _draftBusy = true;
    _writeInFlight = true;
    _draftFailed = false;
    _redraw();
    try {
      await _checkpoint!.saveDraft(
        _checkpoint!.hasPendingDraft ? null : _captureDraft(),
      );
      if (_current(epoch)) _restoreCheckpoint();
    } on Object {
      if (_current(epoch)) _draftFailed = true;
    } finally {
      _draftBusy = false;
      _writeInFlight = false;
      _redraw();
    }
  }

  String get _arranged =>
      _slots.whereType<int>().map((index) => _bank[index]).join(' ');
  bool get _hasAnswer =>
      _response.text.trim().isNotEmpty ||
      _slots.every((index) => index != null);

  Future<void> _save() async {
    final epoch = _epoch;
    final retry = _step == _Step.saveFailed;
    if (!_current(epoch) ||
        _writeInFlight ||
        (!retry && (!_canAnswer || !_hasAnswer))) {
      return;
    }
    _latency.stop();
    _step = _Step.saving;
    _writeInFlight = true;
    _redraw();
    try {
      await _checkpoint!.saveAnswer(
        _checkpoint!.hasPendingInput ? null : _captureDraft(),
      );
      if (_current(epoch)) _restoreCheckpoint();
    } on Object {
      if (_current(epoch)) _step = _Step.saveFailed;
    } finally {
      _writeInFlight = false;
      _redraw();
    }
  }

  Future<void> _finish() async {
    final epoch = _epoch;
    if (!_current(epoch) ||
        _writeInFlight ||
        (_step != _Step.saved && _step != _Step.finishFailed)) {
      return;
    }
    _step = _Step.finishing;
    _writeInFlight = true;
    _redraw();
    try {
      final summary = await _checkpoint!.finish();
      if (_current(epoch)) _leaveRoute(summary: summary, expectedEpoch: epoch);
    } on Object {
      if (_current(epoch)) _step = _Step.finishFailed;
    } finally {
      _writeInFlight = false;
      _redraw();
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
                  _current(_epoch) &&
                      !_draftBusy &&
                      _step == _Step.answering &&
                      !_writeInFlight
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

  Future<void> _stopPlayback() {
    _audioEpoch++;
    _voiceBusy = false;
    final pending = _playbackStop;
    if (pending != null) return pending;
    if (!_ownsPlayback) return Future<void>.value();
    _ownsPlayback = false;
    final voice = _voice;
    final stopping = () async {
      try {
        await voice?.stop();
      } on Object {
        // Playback failure has no effect on the canonical learning receipt.
      }
    }();
    _playbackStop = stopping;
    unawaited(
      stopping.whenComplete(() {
        if (identical(_playbackStop, stopping)) _playbackStop = null;
      }),
    );
    return stopping;
  }

  Future<void> _listen() async {
    if (!_canListen || _voiceBusy) return;
    final epoch = _epoch;
    final voice = _voice!;
    final stop = _stopPlayback();
    final audioEpoch = _audioEpoch;
    _voiceBusy = true;
    _voiceFailed = false;
    _redraw();
    await stop;
    if (!_current(epoch) ||
        !identical(voice, _voice) ||
        audioEpoch != _audioEpoch) {
      return;
    }
    _ownsPlayback = true;
    _heardOriginal = true;
    try {
      await voice.speak(
        VoiceRequest.create(
          text: widget.session.content.sentence,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: widget.session.evidenceContentRevision,
          contentType: 'sentence_scramble',
        ),
      );
    } on Object {
      if (_current(epoch) && audioEpoch == _audioEpoch) {
        _voiceFailed = true;
        await _stopPlayback();
      }
    } finally {
      if (mounted && epoch == _epoch && audioEpoch == _audioEpoch) {
        _voiceBusy = false;
      }
      _redraw();
    }
  }

  void _leaveRoute({
    LearningSessionSummary? summary,
    int? expectedEpoch,
    ModalRoute<dynamic>? expectedRoute,
  }) {
    if (!mounted ||
        _route?.isCurrent != true ||
        (expectedRoute != null && !identical(_route, expectedRoute)) ||
        (expectedEpoch != null && (expectedEpoch != _epoch || _invalidated))) {
      return;
    }
    final navigator = Navigator.of(context);
    _allowPop = true;
    _invalidate();
    if (navigator.canPop()) navigator.pop(summary);
  }

  Future<void> _requestBack() async {
    if (!mounted ||
        _writeInFlight ||
        _confirmingExit ||
        _route?.isCurrent != true ||
        !Visibility.of(context) ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (!_startRequested || _invalidated) {
      _leaveRoute();
      return;
    }
    final epoch = _epoch;
    final route = _route;
    if (!_current(epoch)) return;
    _confirmingExit = true;
    _exitDialogCovered = false;
    _exitDialogClosing = false;
    unawaited(_stopPlayback());
    _redraw();
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, redrawDialog) {
          _exitDialogRedraw = redrawDialog;
          final dialog = ModalRoute.of(context);
          _exitDialogRoute = dialog;
          if (dialog?.isActive == true &&
              ModalRoute.isCurrentOf(context) != true &&
              !_exitDialogClosing &&
              dialog?.animation?.status != AnimationStatus.reverse) {
            _exitDialogCovered = true;
            _invalidate();
          }
          void close(bool accepted) {
            if (mounted &&
                (!accepted || !_invalidated) &&
                identical(dialog, _exitDialogRoute) &&
                dialog?.isCurrent == true) {
              _exitDialogClosing = true;
              Navigator.of(dialogContext).pop(accepted);
            }
          }

          return AlertDialog(
            scrollable: true,
            title: Text(
              _copy(
                _invalidated ? 'กิจกรรมไม่พร้อมใช้งาน' : 'ออกจากรอบนี้หรือไม่',
                _invalidated ? 'Activity unavailable' : 'Leave this round?',
              ),
            ),
            content: Text(
              _copy(
                'เล่นต่อจากฉบับร่างที่ยืนยันแล้วได้ในประวัติ การแก้ไขที่ยังไม่บันทึกจะไม่ถูกเก็บ',
                'Continue acknowledged drafts from History. Unsaved changes will not be kept.',
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('sentence-back-keep'),
                onPressed: () => close(false),
                child: Text(_copy('อยู่ต่อ', 'Keep playing')),
              ),
              FilledButton(
                key: const ValueKey('sentence-back-leave'),
                onPressed: _invalidated ? null : () => close(true),
                child: Text(_copy('ออกจากรอบ', 'Leave round')),
              ),
            ],
          );
        },
      ),
    );
    _exitDialogClosing = true;
    final dialog = _exitDialogRoute;
    await dialog?.completed;
    if (!mounted) return;
    _confirmingExit = false;
    _exitDialogRoute = null;
    _exitDialogRedraw = null;
    _routeVisible = _route?.isCurrent == true && Visibility.of(context);
    if (_exitDialogCovered || !_current(epoch) || !identical(route, _route)) {
      _invalidate();
      _redraw();
      return;
    }
    if (leave == true) {
      _leaveRoute(expectedEpoch: epoch, expectedRoute: route);
    } else {
      _redraw();
    }
  }

  bool _canUse(int index) =>
      _canAnswer &&
      index >= 0 &&
      index < _bank.length &&
      !_slots.contains(index);
  bool _canDrop(int slot, int source) =>
      _canUse(source) &&
      slot >= 0 &&
      slot < _slots.length &&
      _slots[slot] == null;
  void _drop(int slot, int source) {
    if (!_canDrop(slot, source)) return;
    _response.clear();
    _slots[slot] = source;
    _tileDraft = _slots;
    _draftDirty = true;
    _filledSlots.add(slot);
    _redraw();
  }

  void _pick(int source) {
    final slot = _slots.indexOf(null);
    if (slot >= 0) _drop(slot, source);
  }

  void _undo() {
    if (!_canAnswer) return;
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
    _redraw();
  }

  void _clear() {
    if (!_canAnswer) return;
    _draftDirty = true;
    _response.clear();
    _slots.fillRange(0, _slots.length, null);
    _filledSlots.clear();
    _redraw();
  }

  @override
  void dispose() {
    _epoch++;
    _checkpoint?.retire();
    _invalidated = true;
    unawaited(_owners?.cancel());
    unawaited(_stopPlayback());
    WidgetsBinding.instance.removeObserver(this);
    _latency.stop();
    _response.dispose();
    for (final node in _tokenFocus) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _slot(int index) => DragTarget<int>(
    key: ValueKey('sentence-slot-$index'),
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
      child: Tooltip(
        message: _slots[index] == null ? '' : _bank[_slots[index]!],
        child: Text(
          _slots[index] == null ? ' ' : _bank[_slots[index]!],
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ),
  );

  Widget _token(int index) {
    final token = _bank[index];
    final available = _canUse(index);
    final maxWidth = (MediaQuery.sizeOf(context).width - 48)
        .clamp(52.0, 672.0)
        .toDouble();
    Widget feedback() => Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth, minHeight: 48),
        padding: const EdgeInsets.all(12),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Text(
          token,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
    return Draggable<int>(
      data: index,
      maxSimultaneousDrags: available ? 1 : 0,
      feedback: feedback(),
      childWhenDragging: Opacity(opacity: 0.3, child: feedback()),
      child: OutlinedButton(
        key: ValueKey('sentence-token-$index'),
        focusNode: _tokenFocus[index],
        onPressed: available ? () => _pick(index) : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.all(12),
        ),
        child: Tooltip(
          message: token,
          child: Text(
            token,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = {
      _Step.startFailed,
      _Step.saveFailed,
      _Step.finishFailed,
    }.contains(_step);
    final saved = {
      _Step.saved,
      _Step.finishing,
      _Step.finishFailed,
    }.contains(_step);
    final showForm = _step != _Step.starting && _step != _Step.startFailed;
    return PopScope<LearningSessionSummary>(
      canPop:
          !_writeInFlight && (_allowPop || !_startRequested || _invalidated),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _invalidate();
        } else {
          unawaited(_requestBack());
        }
      },
      child: LessonScaffold(
        title: _copy('เรียงคำเป็นประโยค', 'Sentence Scramble'),
        leading: IconButton(
          key: const ValueKey('sentence-back'),
          tooltip: _copy('กลับ', 'Back'),
          onPressed: _writeInFlight ? null : _requestBack,
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
              OutlinedButton(
                onPressed: _writeInFlight ? null : _requestBack,
                child: Text(_copy('กลับไปหน้าเรียน', 'Back to learning')),
              ),
            ] else ...[
              Text(
                _copy(
                  'เรียงชิ้นคำให้เป็นประโยคเดิม',
                  'Arrange the pieces into the original sentence.',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _copy(
                  'เกมเรียงประโยคเพื่อความสนุก',
                  'A sentence game for fun.',
                ),
              ),
              Text(_copy('ประโยคสร้างด้วย AI', 'AI-generated sentence')),
              if (showForm) ...[
                const SizedBox(height: 16),
                Text(
                  _copy(
                    'ความหมายของคำศัพท์ที่ใช้: ${widget.session.word.meaning}',
                    'Owned vocabulary meaning: ${widget.session.word.meaning}',
                  ),
                  key: const ValueKey('sentence-meaning-cue'),
                ),
                Text(
                  _copy(
                    'ความหมายของคำศัพท์ ไม่ใช่คำแปลประโยค',
                    'Vocabulary meaning, not a sentence translation.',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _copy(
                    'คงตัวพิมพ์และเครื่องหมายวรรคตอนตามชิ้นคำ',
                    'Keep the displayed capitalization and punctuation.',
                  ),
                ),
                if (_voice != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('sentence-listen-original'),
                        onPressed: _canListen && !_voiceBusy ? _listen : null,
                        icon: const Icon(Icons.volume_up_outlined),
                        label: Text(
                          _heardOriginal
                              ? _copy('ฟังอีกครั้ง', 'Replay original')
                              : _copy('ฟังประโยคต้นฉบับ', 'Listen to original'),
                        ),
                      ),
                      OutlinedButton(
                        key: const ValueKey('sentence-stop'),
                        onPressed: _current(_epoch) && _ownsPlayback
                            ? () {
                                unawaited(_stopPlayback());
                                _redraw();
                              }
                            : null,
                        child: Text(_copy('หยุดเสียง', 'Stop')),
                      ),
                    ],
                  ),
                  if (widget.session.content.sentence.length > 500)
                    Text(
                      _copy(
                        'ประโยคนี้ยาวเกินขอบเขตเสียง แต่ยังตอบแบบฝึกได้',
                        'This sentence exceeds the voice limit. You can still answer.',
                      ),
                    ),
                  if (_voiceFailed)
                    Text(
                      _copy(
                        'เล่นเสียงไม่สำเร็จ ลองอีกครั้งได้',
                        'Audio is unavailable. You may retry.',
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Text(
                  _copy(
                    'ลากชิ้นคำลงช่อง หรือกดเลือกตามลำดับ',
                    'Drag pieces into slots, or tap them in order.',
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
                    _arranged,
                    key: const ValueKey('sentence-arranged'),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_bank.length, _token),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('sentence-undo'),
                      onPressed:
                          _canAnswer &&
                              (_filledSlots.isNotEmpty ||
                                  _response.text.isNotEmpty)
                          ? _undo
                          : null,
                      child: Text(_copy('ย้อนกลับ', 'Undo')),
                    ),
                    OutlinedButton(
                      key: const ValueKey('sentence-clear'),
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
                  key: const ValueKey('sentence-response'),
                  controller: _response,
                  enabled: _canAnswer,
                  minLines: 2,
                  maxLines: 5,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) =>
                          newValue.text.runes.length <=
                                  SentenceScrambleContent.maxSentenceRunes &&
                              utf8.encode(newValue.text).length <=
                                  SentenceScrambleContent.maxSentenceUtf8Bytes
                          ? newValue
                          : oldValue,
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: _copy(
                      'หรือพิมพ์ประโยคแทนการเรียง',
                      'Or type the sentence',
                    ),
                    helperText: _copy(
                      'สูงสุด 1,024 ตัวอักษร',
                      'Up to 1,024 characters',
                    ),
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    if (!_canAnswer) return;
                    _tileDraft = null;
                    _draftDirty = true;
                    _slots.fillRange(0, _slots.length, null);
                    _filledSlots.clear();
                    _redraw();
                  },
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 16),
                if (!saved)
                  if (_checkpoint?.state != null) _draftPanel(),
                if (!saved)
                  FilledButton(
                    key: const ValueKey('sentence-save'),
                    onPressed: _canAnswer && _hasAnswer ? _save : null,
                    child: Text(_copy('บันทึกคำตอบ', 'Save answer')),
                  ),
              ],
              if (_writeInFlight) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  _copy(
                    failed
                        ? 'ยังยืนยันผลไม่ได้ กรุณาลองส่งรายการเดิมอีกครั้ง'
                        : _writeInFlight
                        ? 'กำลังดำเนินการ…'
                        : saved
                        ? 'บันทึกคำตอบแล้ว กดเสร็จสิ้นเพื่อปิดกิจกรรม'
                        : 'ตอบเมื่อพร้อม แล้วกดบันทึกคำตอบ',
                    failed
                        ? 'Confirmation is unavailable. Retry the original request.'
                        : _writeInFlight
                        ? 'Working…'
                        : saved
                        ? 'Answer saved. Finish to close this activity.'
                        : 'Answer when ready, then save your response.',
                  ),
                  key: const ValueKey('sentence-status'),
                ),
              ),
              if (failed)
                OutlinedButton(
                  key: const ValueKey('sentence-retry'),
                  onPressed: _writeInFlight
                      ? null
                      : () => switch (_step) {
                          _Step.startFailed => _start(),
                          _Step.saveFailed => _save(),
                          _Step.finishFailed => _finish(),
                          _ => Future<void>.value(),
                        },
                  child: Text(
                    _copy('ลองส่งอีกครั้ง', 'Retry original request'),
                  ),
                ),
              if (saved) ...[
                const SizedBox(height: 16),
                Text(
                  _pendingAnswer!.isCorrect
                      ? _copy(
                          'ตรงกับประโยคต้นฉบับ · บันทึกแล้ว',
                          'Matches the original sentence · Saved',
                        )
                      : _copy(
                          'บันทึกคำตอบแล้ว ประโยคต้นฉบับคือ',
                          'Answer saved. The original sentence is',
                        ),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    widget.session.content.sentence,
                    key: const ValueKey('sentence-feedback'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('sentence-finish'),
                  onPressed: _step == _Step.saved ? _finish : null,
                  child: Text(_copy('เสร็จสิ้น', 'Finish')),
                ),
                if (_step == _Step.saved &&
                    LearningEvidenceContract.isOrdinaryEvidence(
                      _pendingAnswer!.evidenceContext,
                    ))
                  ContentReportButton.content(
                    key: const ValueKey('content-report-sentence-scramble'),
                    expectedOwnerId: widget.session.ownerId,
                    sessionId: widget.session.id,
                    sourceIdentity: (
                      _checkpoint!.state!.plan.id,
                      _checkpoint!.state!.checkpointRevision,
                    ),
                    sourceText: widget.session.content.sentence,
                    callerContext: LearningTimeCallerContext.ordinary,
                    canOpen: () => _current(_epoch) && _step == _Step.saved,
                    onOverlayChanged: (open) {
                      _reportOverlay = open;
                    },
                    targetForSelection: (text, excerpt) =>
                        ContentReportTarget.aiOutput(
                          text: text,
                          isExcerpt: excerpt,
                          sessionId: widget.session.id,
                          acceptedPlanId: _checkpoint!.state!.plan.id,
                          contentKind: widget.session.content.kind.wire,
                          modelVersion: widget.session.content.modelVersion,
                          cached: widget.session.content.cached,
                          origin: ContentReportAiOrigin.unrecorded,
                        ),
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
