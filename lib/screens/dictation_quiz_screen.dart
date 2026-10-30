import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';

class DictationQuizScreen extends StatefulWidget {
  const DictationQuizScreen({
    super.key,
    required this.session,
    required this.learning,
    this.voice,
    this.ownerChanges,
    this.languageCode = 'th',
  });

  final DictationSession session;
  final LearningUseCases learning;
  final VoiceUseCases? voice;
  final Stream<String?>? ownerChanges;
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
  bool _startRequested = false;
  bool _playBusy = false;
  bool _playSucceeded = false;
  bool _audioFailed = false;
  bool _assisted = false;
  String? _ownerId;
  int _epoch = 0;
  _Step _step = _Step.starting;
  RecordAnswerCommand? _pendingAnswer;
  NativeFinishIntent? _pendingFinish;

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
    if (!identical(widget.session, oldWidget.session) ||
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
      setState(() => _step = _Step.answering);
      await _play(1);
    } on Object {
      if (_current(epoch)) {
        setState(() => _step = _Step.startFailed);
      }
    }
  }

  Future<void> _play(double speed) async {
    final epoch = _epoch;
    if (!_current(epoch) || _step != _Step.answering || _playBusy) {
      return;
    }
    // Assistance is a captured interaction, including an unsuccessful request.
    setState(() {
      if (speed < 1) {
        _assisted = true;
      }
      _playBusy = true;
      _playSucceeded = false;
      _audioFailed = false;
    });
    try {
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
        setState(() => _audioFailed = true);
      }
    } finally {
      if (_current(epoch)) {
        setState(() => _playBusy = false);
      }
    }
  }

  bool get _canAnswer =>
      _current(_epoch) &&
      _step == _Step.answering &&
      _playSucceeded &&
      !_playBusy;

  Future<void> _save() async {
    final epoch = _epoch;
    final retry = _step == _Step.saveFailed;
    if (!_current(epoch) ||
        (!retry && (!_canAnswer || _response.text.trim().isEmpty))) {
      return;
    }
    try {
      _pendingAnswer ??= widget.learning.prepareNativeAnswer(
        DictationAnswerInput(
          exercise: widget.session,
          response: _response.text,
          assisted: _assisted,
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
      await _voice!.stop();
      if (!_current(epoch)) {
        return;
      }
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
      await _voice!.stop();
      if (!_current(epoch)) {
        return;
      }
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
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: M3Theme.appBarToolbarHeight(context),
          title: M3Theme.appBarTitle(
            context,
            _copy('ฟังแล้วพิมพ์คำศัพท์', 'Listen and spell'),
          ),
          leading: IconButton(
            key: const ValueKey('dictation-back'),
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
                                !_playBusy
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
                                !_playBusy
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
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 16),
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
