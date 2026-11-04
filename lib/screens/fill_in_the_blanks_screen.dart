import 'dart:async';

import 'package:flutter/material.dart';

import '../features/content_reports/domain/content_report.dart';
import '../features/content_reports/presentation/content_report_button.dart';
import '../features/learning/domain/learning_evidence_contract.dart';
import 'package:flutter/scheduler.dart';

import '../features/learning/presentation/lesson_scaffold.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/native_sentence_source.dart';
import '../features/learning/domain/learning_time_admission.dart';
import '../features/learning/presentation/native_exercise_checkpoint_binding.dart';
import '../features/learning_time/application/learning_time_use_cases.dart';
import '../features/learning_time/presentation/learning_time_binding.dart';
import '../runtime/app_dependencies.dart';
import '../widgets/handwriting_scratchpad.dart';

class FillInTheBlanksScreen extends StatefulWidget {
  const FillInTheBlanksScreen({
    super.key,
    required this.session,
    required this.learning,
    this.resumeState,
    this.ownerChanges,
    this.learningTime,
    this.learningTimeCallerContext = LearningTimeCallerContext.unavailable,
    this.languageCode = 'th',
  });
  final ClozeSession session;
  final LearningUseCases learning;
  final NativeExerciseState? resumeState;
  final Stream<String?>? ownerChanges;
  final LearningTimeUseCases? learningTime;
  final LearningTimeCallerContext learningTimeCallerContext;
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
  bool _reportOverlay = false;
  bool _startRequested = false;
  bool _redrawScheduled = false;
  String? _ownerId;
  String? _selected;
  int _epoch = 0;
  _Step _step = _Step.starting;
  NativeExerciseCheckpointBinding? _checkpoint;
  RecordAnswerCommand? get _pendingAnswer =>
      _invalidated ? null : _checkpoint?.answer;
  bool _draftBusy = false;
  bool _draftFailed = false;
  bool _draftDirty = false;
  LearningTimeBinding? _timeBinding;

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

  void _redraw() {
    if (!mounted) return;
    void update() {
      if (!mounted) return;
      if (_invalidated) _response.clear();
      setState(() {});
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
        _ownerId = ownerId;
        _redraw();
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryStart());
      },
      onError: (Object _, StackTrace _) => _invalidate(),
      onDone: _invalidate,
    );
  }

  @override
  void didUpdateWidget(covariant FillInTheBlanksScreen oldWidget) {
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
    _invalidated = true;
    _checkpoint?.retire();
    _timeBinding?.close();
    _epoch++;
    _selected = null;
    _latency.stop();
    _redraw();
  }

  void _tryStart() {
    if (_startRequested || !_current(_epoch)) {
      return;
    }
    _startRequested = true;
    unawaited(_start());
  }

  NativeExerciseDraft _captureDraft() => NativeExerciseDraft(
    text: widget.session is TypedClozeSession ? _response.text : '',
    optionId: widget.session is ChoiceClozeSession ? _selected : null,
    responseTimeMs: _checkpoint!.elapsedMilliseconds(_latency.elapsed),
  );

  void _restoreCheckpoint() {
    final state = _checkpoint!.state!;
    final draft = state.checkpoint.draft;
    _latency
      ..stop()
      ..reset();
    _response.text = draft.text;
    _selected = draft.optionId;
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
      unawaited(_readyTime());
    } on Object {
      if (_current(epoch)) setState(() => _step = _Step.startFailed);
    }
  }

  Future<void> _saveDraft() async {
    final epoch = _epoch;
    if (!_current(epoch) || _draftBusy || _step != _Step.answering) return;
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

  Future<void> _readyTime() async {
    final time = widget.learningTime ?? _dependencies?.learningTime;
    final epoch = _epoch;
    if (time == null ||
        !_canAnswer ||
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
    try {
      final proof = await widget.learning.admitCanonicalLearningTime(
        NativeLearningTimeAdmission(
          _checkpoint!.exercise,
          hintLevel: 0,
          callerContext: widget.learningTimeCallerContext,
        ),
        expectedOwnerId: widget.session.ownerId,
        stillCurrent: () =>
            _canAnswer &&
            _current(epoch) &&
            binding.visibilityGeneration == visibility &&
            time.captureGeneration == capture,
      );
      if (_canAnswer &&
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

  Future<void> _save() async {
    final epoch = _epoch;
    final retry = _step == _Step.saveFailed;
    final hasAnswer = widget.session is TypedClozeSession
        ? _response.text.trim().isNotEmpty
        : _selected != null;
    if (!_current(epoch) || (!retry && (!_canAnswer || !hasAnswer))) return;
    if (!retry) _timeBinding?.interacted();
    _timeBinding?.suspend();
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

  void _timeInput() {
    if (!_canAnswer) {
      return;
    }
    final time = widget.learningTime ?? _dependencies?.learningTime;
    final binding = _timeBinding;
    binding?.interacted();
    final lease = binding?.lease;
    if (lease == null || time?.acceptsInteraction(lease) != true) {
      unawaited(_readyTime());
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
    _timeBinding?.dispose();
    _checkpoint?.retire();
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
      child: LessonScaffold(
        title: _copy('เติมคำในบริบท', 'Complete the sentence'),
        leading: IconButton(
          key: const ValueKey('cloze-back'),
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
                  'เติมคำศัพท์เป้าหมายตามความหมายนี้ในช่องว่าง',
                  'Fill the gap with your target vocabulary word for this meaning.',
                ),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _copy(
                  widget.session.content.source is AuthoredSentenceSource
                      ? 'ประโยคจากชุดคำศัพท์ที่ติดตั้ง · ฝึกแบบมีตัวช่วย'
                      : 'ประโยคสร้างด้วย AI · ฝึกแบบมีตัวช่วย',
                  widget.session.content.source is AuthoredSentenceSource
                      ? 'Installed pack context · assisted practice'
                      : 'AI-generated context · assisted practice',
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
                        _timeInput();
                        setState(() {
                          _selected = value;
                          _draftDirty = true;
                        });
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
                    onChanged: (_) {
                      if (_canAnswer) {
                        _draftDirty = true;
                        _timeInput();
                        _redraw();
                      }
                    },
                    onSubmitted: (_) => _save(),
                  ),
                if (widget.session is TypedClozeSession) ...[
                  const SizedBox(height: 12),
                  HandwritingScratchpad(
                    key: ObjectKey(widget.session),
                    canEdit: () => _canAnswer && _pendingAnswer == null,
                    languageCode: widget.languageCode,
                  ),
                ],
                const SizedBox(height: 16),
                if (!saved)
                  if (_checkpoint?.state != null) _draftPanel(),
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
                if (widget.session is TypedClozeSession)
                  Text(
                    _copy(
                      'ผลนี้ตรวจเฉพาะคำที่พิมพ์ เปรียบเทียบลายมือกับคำตอบได้ด้วยตนเอง',
                      'This result checks typed text only. Compare your handwriting with the answer yourself.',
                    ),
                  ),
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
                if (_step == _Step.saved &&
                    widget.learningTimeCallerContext !=
                        LearningTimeCallerContext.researchControlled &&
                    LearningEvidenceContract.isOrdinaryEvidence(
                      _pendingAnswer!.evidenceContext,
                    ))
                  ContentReportButton.content(
                    key: const ValueKey('content-report-cloze'),
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
                        widget.session.content.source is AuthoredSentenceSource
                        ? ContentReportTarget.packEntry(
                            text: text,
                            isExcerpt: excerpt,
                            packId:
                                (widget.session.content.source
                                        as AuthoredSentenceSource)
                                    .pack
                                    .packId,
                            packVersion:
                                (widget.session.content.source
                                        as AuthoredSentenceSource)
                                    .pack
                                    .version,
                            packageSha256:
                                (widget.session.content.source
                                        as AuthoredSentenceSource)
                                    .pack
                                    .packageSha256,
                            entryCode:
                                (widget.session.content.source
                                        as AuthoredSentenceSource)
                                    .target
                                    .entry
                                    .code,
                            entrySha256:
                                (widget.session.content.source
                                        as AuthoredSentenceSource)
                                    .target
                                    .entry
                                    .contentSha256,
                          )
                        : ContentReportTarget.aiOutput(
                            text: text,
                            isExcerpt: excerpt,
                            sessionId: widget.session.id,
                            acceptedPlanId: _checkpoint!.state!.plan.id,
                            contentKind:
                                (widget.session.content.source
                                        as GeneratedSentenceSource)
                                    .kind
                                    .wire,
                            modelVersion:
                                (widget.session.content.source
                                        as GeneratedSentenceSource)
                                    .modelVersion,
                            cached:
                                (widget.session.content.source
                                        as GeneratedSentenceSource)
                                    .cached,
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
