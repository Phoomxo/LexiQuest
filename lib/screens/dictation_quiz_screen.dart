import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../features/content_reports/presentation/content_report_button.dart';
import '../features/learning/domain/learning_evidence_contract.dart';
import '../features/learning/presentation/lesson_scaffold.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/learning_time_admission.dart';
import '../features/learning/presentation/native_exercise_checkpoint_binding.dart';
import '../features/learning_time/application/learning_time_use_cases.dart';
import '../features/learning_time/presentation/learning_time_binding.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';

class DictationQuizScreen extends StatefulWidget {
  const DictationQuizScreen({
    super.key,
    required this.session,
    required this.learning,
    this.resumeState,
    this.voice,
    this.ownerChanges,
    this.learningTime,
    this.learningTimeCallerContext = LearningTimeCallerContext.unavailable,
    this.languageCode = 'th',
  });

  final DictationSession session;
  final LearningUseCases learning;
  final NativeExerciseState? resumeState;
  final VoiceUseCases? voice;
  final Stream<String?>? ownerChanges;
  final LearningTimeUseCases? learningTime;
  final LearningTimeCallerContext learningTimeCallerContext;
  final String languageCode;

  @override
  State<DictationQuizScreen> createState() => _DictationQuizScreenState();
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

class _DictationQuizScreenState extends State<DictationQuizScreen>
    with WidgetsBindingObserver {
  final _response = TextEditingController();
  final _latency = Stopwatch();
  AppDependencies? _dependencies;
  StreamSubscription<String?>? _owners;
  VoiceUseCases? _voice;
  bool _ownsVoice = false;
  bool _bound = false;
  bool _invalidated = false;
  bool _voiceRetired = false;
  bool _routeVisible = false;
  bool _reportOverlay = false;
  bool _startRequested = false;
  bool _playBusy = false;
  bool _playSucceeded = false;
  bool _audioFailed = false;
  bool _assisted = false;
  String? _ownerId;
  int _epoch = 0;
  _Step _step = _Step.starting;
  NativeExerciseCheckpointBinding? _checkpoint;
  RecordAnswerCommand? get _pendingAnswer =>
      _invalidated ? null : _checkpoint?.answer;
  bool _draftBusy = false;
  bool _draftFailed = false;
  bool _draftDirty = false;
  LearningTimeBinding? _timeBinding;
  // speak() acknowledges playback start; only a later stop ACK clears this.
  bool _referencePlaybackUnconfirmed = false;
  bool _timePlaybackStopPending = false;
  int _playbackGeneration = 0;

  bool get _thai => widget.languageCode == 'th';
  String _copy(String th, String en) => _thai ? th : en;

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
      _timeBinding?.retireDependencies();
      _invalidate();
    }
    final visible =
        ModalRoute.isCurrentOf(context) == true && Visibility.of(context);
    if (_routeVisible && !visible && !_reportOverlay) {
      _invalidate();
    }
    _routeVisible = visible;
    _timeBinding?.syncVisibility();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
  }

  void _bind(AppDependencies? dependencies) {
    _bound = true;
    _dependencies = dependencies;
    _voice =
        widget.voice ?? dependencies?.voice ?? VoiceUseCases.createDefault();
    _ownsVoice = widget.voice == null && dependencies?.voice == null;
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
  void didUpdateWidget(covariant DictationQuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.learningTime, oldWidget.learningTime) ||
        widget.learningTimeCallerContext !=
            oldWidget.learningTimeCallerContext) {
      _timeBinding?.retireDependencies();
      _timeBinding?.dispose();
      _timeBinding = null;
      unawaited(_readyTime());
    }
    if (!identical(widget.session, oldWidget.session) ||
        !identical(widget.resumeState, oldWidget.resumeState) ||
        !identical(widget.learning, oldWidget.learning) ||
        !identical(widget.voice, oldWidget.voice) ||
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

  void _invalidate() {
    if (!mounted || _invalidated) {
      return;
    }
    _epoch++;
    _checkpoint?.retire();
    _playbackGeneration++;
    _timeBinding?.close();
    _latency.stop();
    _response.clear();
    setState(() => _invalidated = true);
    unawaited(_retireVoice());
  }

  Future<void> _retireVoice() async {
    if (_voiceRetired) {
      return;
    }
    _voiceRetired = true;
    try {
      await _voice?.stop();
    } on Object {
      /* Cancellation cannot restore a stale screen. */
    }
  }

  void _tryStart() {
    if (_startRequested || !_current(_epoch)) {
      return;
    }
    _startRequested = true;
    unawaited(_start());
  }

  NativeExerciseDraft _captureDraft({bool? assisted}) => NativeExerciseDraft(
    text: _response.text,
    assisted: assisted ?? _assisted,
    responseTimeMs: _checkpoint!.elapsedMilliseconds(_latency.elapsed),
  );

  void _restoreCheckpoint() {
    final state = _checkpoint!.state!;
    final draft = state.checkpoint.draft;
    _latency
      ..stop()
      ..reset();
    _response.text = draft.text;
    _assisted = draft.assisted;
    _draftDirty = false;
    _step = switch (state.phase) {
      NativeCheckpointPhase.awaitingAnswer => _Step.answering,
      NativeCheckpointPhase.pendingAnswer => _Step.saveFailed,
      NativeCheckpointPhase.answered ||
      NativeCheckpointPhase.completed => _Step.saved,
      NativeCheckpointPhase.closing => _Step.finishFailed,
      NativeCheckpointPhase.abandoned => _Step.startFailed,
    };
    if (_step == _Step.answering && _playSucceeded && !_playBusy) {
      _latency.start();
    }
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
      if (widget.resumeState == null && _step == _Step.answering) {
        await _play(1);
      }
    } on Object {
      if (_current(epoch)) setState(() => _step = _Step.startFailed);
    }
  }

  Future<void> _saveDraft() async {
    final epoch = _epoch;
    if (!_current(epoch) ||
        _draftBusy ||
        _playBusy ||
        _step != _Step.answering) {
      return;
    }
    _timeBinding?.suspend();
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
      if (_current(epoch)) {
        setState(() => _draftBusy = false);
        unawaited(_readyTime());
      }
    }
  }

  Future<void> _play(double speed) async {
    final epoch = _epoch;
    if (!_current(epoch) ||
        _step != _Step.answering ||
        _playBusy ||
        _draftBusy ||
        _checkpoint?.hasPendingDraft == true) {
      return;
    }
    _playbackGeneration++;
    _timeBinding?.interacted();
    _timeBinding?.suspend();
    _latency.stop();
    setState(() {
      _playBusy = true;
      _playSucceeded = false;
      _audioFailed = false;
    });
    try {
      if (speed < 1 && !_assisted) {
        await _checkpoint!.saveDraft(_captureDraft(assisted: true));
        if (!_current(epoch)) return;
        setState(_restoreCheckpoint);
      }
      _referencePlaybackUnconfirmed = true;
      await _voice!.stop();
      if (!_current(epoch)) {
        return;
      }
      final word = widget.session.word;
      final contentPin = sha256.convert(
        utf8.encode(
          jsonEncode([word.id, widget.session.evidenceContentRevision]),
        ),
      );
      await _voice!.speak(
        VoiceRequest.create(
          text: word.spelling,
          language: 'en',
          voiceId: 'teacher_female',
          speed: speed,
          mode: VoiceMode.practice,
          contentId: 'dictation:$contentPin',
          contentType: 'dictation_quiz',
        ),
      );
      if (!_current(epoch)) {
        return;
      }
      if (!_latency.isRunning) {
        _latency.start();
      }
      setState(() => _playSucceeded = true);
    } on Object {
      if (_current(epoch)) {
        setState(() {
          _draftFailed = _checkpoint?.hasPendingDraft == true;
          _audioFailed = !_draftFailed;
        });
      }
    } finally {
      if (_current(epoch)) {
        setState(() => _playBusy = false);
        unawaited(_readyTime());
      }
    }
  }

  bool get _canAnswer =>
      _current(_epoch) &&
      _step == _Step.answering &&
      !_draftBusy &&
      _checkpoint?.hasPendingDraft != true &&
      _playSucceeded &&
      !_playBusy;

  Future<void> _readyTime() async {
    final time = widget.learningTime ?? _dependencies?.learningTime;
    final epoch = _epoch;
    if (time == null ||
        !_canAnswer ||
        _referencePlaybackUnconfirmed ||
        _timePlaybackStopPending ||
        widget.learningTimeCallerContext !=
            LearningTimeCallerContext.ordinary) {
      return;
    }
    final binding = _timeBinding ??= LearningTimeBinding(
      time: time,
      expectedOwnerId: widget.session.ownerId,
      visible: () => _current(epoch) && TickerMode.valuesOf(context).enabled,
    );
    final visibility = binding.visibilityGeneration;
    final capture = time.captureGeneration;
    final assisted = _assisted;
    try {
      final proof = await widget.learning.admitCanonicalLearningTime(
        NativeLearningTimeAdmission(
          _checkpoint!.exercise,
          hintLevel: assisted ? 1 : 0,
          callerContext: widget.learningTimeCallerContext,
        ),
        expectedOwnerId: widget.session.ownerId,
        stillCurrent: () =>
            _canAnswer &&
            !_referencePlaybackUnconfirmed &&
            !_timePlaybackStopPending &&
            _assisted == assisted &&
            _current(epoch) &&
            binding.visibilityGeneration == visibility &&
            time.captureGeneration == capture,
      );
      if (_canAnswer &&
          !_referencePlaybackUnconfirmed &&
          !_timePlaybackStopPending &&
          _assisted == assisted &&
          _current(epoch) &&
          binding.visibilityGeneration == visibility &&
          time.captureGeneration == capture) {
        await binding.ready(
          CanonicalTimeSource(
            proof,
            callerContext: widget.learningTimeCallerContext,
          ),
        );
      }
    } on Object {
      binding.suspend();
    }
  }

  void _timeInput() {
    final time = widget.learningTime ?? _dependencies?.learningTime;
    if (!_canAnswer ||
        time == null ||
        !time.captureEnabled ||
        widget.learningTimeCallerContext !=
            LearningTimeCallerContext.ordinary) {
      return;
    }
    if (_referencePlaybackUnconfirmed) {
      unawaited(_stopPlaybackForTime());
      return;
    }
    final binding = _timeBinding;
    binding?.interacted();
    final lease = binding?.lease;
    if (lease == null || !time.acceptsInteraction(lease)) {
      unawaited(_readyTime());
    }
  }

  Future<void> _stopPlaybackForTime() async {
    if (_timePlaybackStopPending) {
      return;
    }
    final epoch = _epoch;
    final playback = ++_playbackGeneration;
    _timePlaybackStopPending = true;
    var stopped = false;
    try {
      await _voice!.stop();
      if (_current(epoch) && !_playBusy && playback == _playbackGeneration) {
        _referencePlaybackUnconfirmed = false;
        stopped = true;
      }
    } on Object {
      return;
    } finally {
      _timePlaybackStopPending = false;
      if (stopped && _current(epoch) && playback == _playbackGeneration) {
        unawaited(_readyTime());
      }
    }
  }

  Future<void> _save() async {
    final epoch = _epoch;
    final retry = _step == _Step.saveFailed;
    if (!_current(epoch) ||
        (!retry && (!_canAnswer || _response.text.trim().isEmpty))) {
      return;
    }
    if (!retry) _timeBinding?.interacted();
    _timeBinding?.suspend();
    _latency.stop();
    setState(() => _step = _Step.saving);
    try {
      await _checkpoint!.saveAnswer(
        _checkpoint!.hasPendingInput ? null : _captureDraft(),
        beforeCommit: () => _voice!.stop(),
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
    _timeBinding?.close();
    setState(() => _step = _Step.finishing);
    try {
      final summary = await _checkpoint!.finish(
        beforeCommit: () => _voice!.stop(),
      );
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
                  _current(_epoch) &&
                      !_draftBusy &&
                      _step == _Step.answering &&
                      !_playBusy
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
    _timeBinding?.dispose();
    _checkpoint?.retire();
    _epoch++;
    _invalidated = true;
    _owners?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _latency.stop();
    _response.dispose();
    unawaited(_retireVoice());
    _voice?.disposeIfOwned(_ownsVoice);
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
        _step == _Step.finishing ||
        _playBusy;
    return PopScope<LearningSessionSummary>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _invalidate();
        }
      },
      child: LessonScaffold(
        title: _copy('ฟังแล้วพิมพ์คำศัพท์', 'Listen and spell'),
        leading: IconButton(
          key: const ValueKey('dictation-back'),
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
                  'ฟังเสียง แล้วพิมพ์คำที่ได้ยิน',
                  'Play the word, then type its spelling.',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('dictation-normal'),
                    onPressed:
                        _current(_epoch) &&
                            _step == _Step.answering &&
                            !_playBusy &&
                            !_draftBusy &&
                            _checkpoint?.hasPendingDraft != true
                        ? () => _play(1)
                        : null,
                    icon: const Icon(Icons.volume_up_outlined),
                    label: Text(
                      _copy('ฟังอีกครั้ง · 1.0×', 'Play again · 1.0×'),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('dictation-slow'),
                    onPressed:
                        _current(_epoch) &&
                            _step == _Step.answering &&
                            !_playBusy &&
                            !_draftBusy &&
                            _checkpoint?.hasPendingDraft != true
                        ? () => _play(.75)
                        : null,
                    icon: const Icon(Icons.slow_motion_video),
                    label: Text(
                      _copy('ฟังช้าลง · 0.75×', 'Play slowly · 0.75×'),
                    ),
                  ),
                ],
              ),
              if (_assisted)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _copy(
                      'รอบนี้เป็นการฝึกแบบมีตัวช่วย',
                      'This response uses assisted practice.',
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              TextField(
                key: const ValueKey('dictation-response'),
                controller: _response,
                enabled: _canAnswer,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: _copy('คำตอบของคุณ', 'Your spelling'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  _draftDirty = true;
                  _timeInput();
                  setState(() {});
                },
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              if (!saved)
                if (_checkpoint?.state != null) _draftPanel(),
              if (!saved)
                FilledButton(
                  key: const ValueKey('dictation-save'),
                  onPressed: _canAnswer && _response.text.trim().isNotEmpty
                      ? _save
                      : null,
                  child: Text(_copy('บันทึกคำตอบ', 'Save answer')),
                ),
              if (busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  key: const ValueKey('dictation-status'),
                  _copy(
                    _audioFailed
                        ? 'เล่นเสียงไม่สำเร็จ กรุณาลองฟังอีกครั้งก่อนตอบ'
                        : failed
                        ? 'ยังยืนยันผลไม่ได้ กรุณาลองส่งรายการเดิมอีกครั้ง'
                        : busy
                        ? 'กำลังดำเนินการ…'
                        : saved
                        ? 'บันทึกคำตอบแล้ว กดเสร็จสิ้นเพื่อปิดกิจกรรม'
                        : 'ฟังเสียงสำเร็จแล้วจึงบันทึกคำตอบได้',
                    _audioFailed
                        ? 'Playback failed. Play the word again before answering.'
                        : failed
                        ? 'Confirmation is unavailable. Retry the original request.'
                        : busy
                        ? 'Working…'
                        : saved
                        ? 'Answer saved. Finish to close this activity.'
                        : 'Save becomes available after successful playback.',
                  ),
                ),
              ),
              if (failed) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const ValueKey('dictation-retry'),
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
                    key: const ValueKey('dictation-feedback'),
                    _pendingAnswer!.isCorrect
                        ? _copy(
                            'ตอบถูก · ${widget.session.word.spelling}',
                            'Correct · ${widget.session.word.spelling}',
                          )
                        : _copy(
                            'คำตอบที่ถูกคือ ${widget.session.word.spelling}',
                            'The spelling is ${widget.session.word.spelling}',
                          ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('dictation-finish'),
                  onPressed: _step == _Step.saved ? _finish : null,
                  child: Text(_copy('เสร็จสิ้น', 'Finish')),
                ),
                if (_step == _Step.saved &&
                    widget.learningTimeCallerContext !=
                        LearningTimeCallerContext.researchControlled &&
                    LearningEvidenceContract.isOrdinaryEvidence(
                      _pendingAnswer!.evidenceContext,
                    ))
                  ContentReportButton.ownedWord(
                    key: const ValueKey('content-report-dictation'),
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
