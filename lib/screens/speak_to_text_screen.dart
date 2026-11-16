import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_models.dart';
import '../widgets/adaptive_content_pane.dart';
import 'word_scramble_screen.dart';
import '../navigation/app_routes.dart';
import 'device_permission_center_screen.dart';

class SpeakToTextScreen extends StatefulWidget {
  const SpeakToTextScreen({
    super.key,
    required this.correctWord,
    this.voice,
    this.speechPractice,
    this.sessionId,
    this.wordId,
    this.attemptNumber = 1,
    this.learning,
    this.sourceOwnerId,
  });

  final String correctWord;
  final VoiceUseCases? voice;
  final SpeechPracticeUseCases? speechPractice;
  final String? sessionId;
  final String? wordId;
  final int attemptNumber;
  final LearningUseCases? learning;
  final String? sourceOwnerId;

  @override
  State<SpeakToTextScreen> createState() => _SpeakToTextScreenState();
}

class _SpeakToTextScreenState extends State<SpeakToTextScreen>
    with WidgetsBindingObserver {
  late final VoiceUseCases _voice;
  bool _ownsVoice = false;
  SpeechPracticeUseCases? _speech;
  LearningUseCases? _learning;
  bool _listening = false;
  bool _starting = false;
  int _speechEpoch = 0;
  String _transcript = '';
  String? _error;
  TranscriptPronunciationAssessment? _assessment;
  DateTime? _startedAtUtc;
  bool _foreground = true;
  bool _stopping = false;
  bool _saving = false;
  bool _finishing = false;
  bool _leaving = false;
  bool _allowSourcePop = false;
  bool _sourceOwnerInvalid = false;
  bool _sourceFinalPending = false;
  bool _sourceSaved = false;
  int _eventSequence = 0;
  RecordAnswerCommand? _sourceAnswer;

  bool get _isSource => widget.sourceOwnerId != null;
  bool get _audioBlocked =>
      !_foreground ||
      _sourceOwnerInvalid ||
      _starting ||
      _stopping ||
      _saving ||
      _finishing ||
      _leaving ||
      (_isSource && (_sourceFinalPending || _sourceAnswer != null));

  bool _current(int epoch) =>
      mounted && _foreground && epoch == _speechEpoch && !_sourceOwnerInvalid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = widget.voice ?? VoiceUseCases.createDefault();
    _ownsVoice = widget.voice == null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakWord());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _speech ??= widget.speechPractice ?? dependencies?.speechPractice;
    _learning ??= widget.learning ?? dependencies?.learning;
  }

  @override
  void didUpdateWidget(SpeakToTextScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((_isSource || oldWidget.sourceOwnerId != null) &&
        (oldWidget.sourceOwnerId != widget.sourceOwnerId ||
            oldWidget.sessionId != widget.sessionId ||
            oldWidget.wordId != widget.wordId ||
            oldWidget.correctWord != widget.correctWord ||
            oldWidget.attemptNumber != widget.attemptNumber ||
            !identical(oldWidget.learning, widget.learning))) {
      _invalidateSource();
    }
  }

  Future<void> _speakWord() async {
    if (_audioBlocked || _listening) return;
    final epoch = _speechEpoch;
    try {
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      await _voice.speak(
        VoiceRequest.create(
          text: widget.correctWord,
          language: 'en',
          voiceId: 'device-default',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: widget.correctWord,
          contentType: 'vocabulary_word',
        ),
      );
      if (_current(epoch)) await _sourceOwnerCurrent();
    } catch (_) {
      if (_current(epoch)) {
        setState(() => _error = 'ระบบอ่านออกเสียงไม่พร้อมใช้งาน');
      }
    }
  }

  Future<void> _startListening() async {
    if (_audioBlocked || _listening) return;
    final speech = _speech;
    if (speech == null) {
      setState(() => _error = 'ระบบรู้จำเสียงไม่พร้อมใช้งานบนอุปกรณ์นี้');
      return;
    }
    final epoch = ++_speechEpoch;
    setState(() {
      _starting = true;
      _error = null;
      _transcript = '';
      _assessment = null;
    });
    try {
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      await _voice.stop();
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      _startedAtUtc = DateTime.now().toUtc();
      await speech.start(
        locale: 'en-US',
        onEvent: (event) => unawaited(_onSpeechEvent(event, epoch)),
        onFailure: (failure) {
          if (!_current(epoch) || (_isSource && _sourceAnswer != null)) return;
          setState(() {
            _listening = false;
            _sourceFinalPending = false;
            _assessment = null;
            _error = _speechFailureText(failure);
          });
        },
        onStatus: (status) {
          if (!_current(epoch) || (_isSource && _sourceAnswer != null)) return;
          setState(() => _listening = status == 'listening');
        },
      );
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      if (_current(epoch)) {
        setState(() => _listening = speech.isListening);
      }
    } on SpeechPracticeException catch (error) {
      if (_current(epoch) && !(_isSource && _sourceAnswer != null)) {
        setState(() {
          _listening = false;
          _error = _speechFailureText(error.code);
        });
      }
    } on Object {
      if (_current(epoch)) {
        setState(
          () => _error = 'หยุดเสียงหรือเริ่มไมโครโฟนไม่สำเร็จ กรุณาลองใหม่',
        );
      }
    } finally {
      if (mounted && epoch == _speechEpoch) setState(() => _starting = false);
    }
  }

  Future<void> _onSpeechEvent(SpeechRecognitionEvent event, int epoch) async {
    if (!_current(epoch) ||
        (_isSource && (_sourceFinalPending || _sourceAnswer != null))) {
      return;
    }
    final sequence = ++_eventSequence;
    final receivedAt = DateTime.now().toUtc();
    if (_isSource && event.isFinal) _sourceFinalPending = true;
    if (!await _sourceOwnerCurrent() ||
        !_current(epoch) ||
        sequence != _eventSequence) {
      return;
    }
    late final TranscriptPronunciationAssessment assessment;
    try {
      assessment = _speech!.assess(target: widget.correctWord, event: event);
    } on SpeechPracticeException catch (error) {
      setState(() {
        _listening = false;
        _assessment = null;
        _sourceFinalPending = false;
        _error = _speechFailureText(error.code);
      });
      return;
    }
    setState(() {
      _transcript = event.transcript;
      _assessment = assessment;
      if (event.isFinal) _listening = false;
    });
    if (!event.isFinal) return;
    if (_isSource) {
      final elapsed = _startedAtUtc == null
          ? null
          : receivedAt.difference(_startedAtUtc!).inMilliseconds;
      _sourceAnswer = RecordAnswerCommand(
        id: 'attempt:sourceVoice:${widget.sessionId}:${widget.attemptNumber}',
        ownerId: widget.sourceOwnerId!,
        sessionId: widget.sessionId!,
        wordId: widget.wordId!,
        promptMode: 'pronunciationTranscript',
        isCorrect: assessment.isExactMatch,
        responseTimeMs: elapsed == null || elapsed >= 0 ? elapsed : 0,
        attemptNumber: widget.attemptNumber,
        occurredAtUtc: receivedAt,
        providerProvenance:
            '${assessment.engine}|${assessment.locale}|${assessment.method}',
      );
      await _saveSourceAnswer();
    } else {
      await _recordEvidence(assessment);
    }
  }

  Future<bool> _sourceOwnerCurrent() async {
    if (!_isSource) return true;
    if (!mounted || _sourceOwnerInvalid) return false;
    try {
      final learning = _learning;
      if (learning == null ||
          widget.sourceOwnerId!.trim().isEmpty ||
          widget.sessionId == null ||
          widget.sessionId!.isEmpty ||
          widget.wordId == null ||
          widget.wordId!.isEmpty) {
        throw StateError('source session unavailable');
      }
      final owner = await learning.owners.getOrCreateActiveOwner();
      if (!mounted) return false;
      if (owner.id == widget.sourceOwnerId) return true;
    } on Object {
      // Unavailable owner authority must not admit source evidence.
    }
    _invalidateSource();
    return false;
  }

  void _invalidateSource() {
    if (!mounted) return;
    _speechEpoch++;
    setState(() {
      _sourceOwnerInvalid = true;
      _sourceSaved = false;
      _transcript = '';
      _assessment = null;
      _sourceAnswer = null;
      _listening = false;
      _starting = false;
      _error = 'บัญชีผู้เรียนเปลี่ยนหรือไม่พร้อม กรุณากลับไปเลือกคำใหม่';
    });
    unawaited(_cancelForLifecycle());
  }

  Future<void> _saveSourceAnswer() async {
    final answer = _sourceAnswer;
    if (answer == null ||
        _saving ||
        _sourceSaved ||
        _sourceOwnerInvalid ||
        _leaving) {
      return;
    }
    final epoch = _speechEpoch;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      await _stopAudio();
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      await _learning!.recordAnswer(
        sessionId: answer.sessionId,
        wordId: answer.wordId,
        promptMode: answer.promptMode,
        isCorrect: answer.isCorrect,
        responseTimeMs: answer.responseTimeMs,
        attemptNumber: answer.attemptNumber,
        attemptId: answer.id,
        occurredAtUtc: answer.occurredAtUtc,
        providerProvenance: answer.providerProvenance,
      );
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      setState(() => _sourceSaved = true);
    } on Object {
      if (await _sourceOwnerCurrent() && _current(epoch)) {
        setState(
          () => _error =
              'บันทึกผลยังไม่ยืนยันหรือหยุดเสียงไม่สำเร็จ '
              'กดลองบันทึกอีกครั้งเพื่อใช้ผลเดิม',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finishSource() async {
    if (!_sourceSaved ||
        _saving ||
        _finishing ||
        _sourceOwnerInvalid ||
        _leaving) {
      return;
    }
    final epoch = _speechEpoch;
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      await _stopAudio();
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      final summary = await _learning!.finishSession(widget.sessionId!);
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      final correct = _sourceAnswer!.isCorrect;
      if (summary.id != widget.sessionId ||
          summary.state != 'completed' ||
          summary.correctCount != (correct ? 1 : 0) ||
          summary.wrongCount != (correct ? 0 : 1) ||
          summary.score != (correct ? 100 : 0)) {
        throw StateError('source finish not acknowledged');
      }
      if (!mounted) return;
      setState(() => _allowSourcePop = true);
      Navigator.of(context).pop(summary);
    } on Object {
      if (await _sourceOwnerCurrent() && _current(epoch)) {
        setState(() => _error = 'ปิดการฝึกไม่สำเร็จ กรุณากดจบการฝึกอีกครั้ง');
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<void> _leaveSource() async {
    if (_saving || _finishing || _leaving) return;
    setState(() => _leaving = true);
    final stopped = await _cancelForLifecycle();
    if (mounted) {
      setState(() {
        _leaving = false;
        _allowSourcePop = stopped;
      });
      if (stopped) Navigator.of(context).pop();
    }
  }

  Future<void> _recordEvidence(
    TranscriptPronunciationAssessment assessment,
  ) async {
    final learning = _learning;
    final sessionId = widget.sessionId;
    final wordId = widget.wordId;
    if (learning == null || sessionId == null || wordId == null) return;
    final elapsed = _startedAtUtc == null
        ? null
        : DateTime.now().toUtc().difference(_startedAtUtc!).inMilliseconds;
    try {
      await learning.recordAnswer(
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'pronunciationTranscript',
        isCorrect: assessment.isExactMatch,
        responseTimeMs: elapsed,
        attemptNumber: widget.attemptNumber,
        providerProvenance:
            '${assessment.engine}|${assessment.locale}|${assessment.method}',
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'บันทึกผลการฝึกไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    }
  }

  Future<void> _stopListening() async {
    if (_stopping || _saving || _finishing) return;
    final epoch = _speechEpoch;
    setState(() => _stopping = true);
    try {
      if (!await _sourceOwnerCurrent() || !_current(epoch)) return;
      await _speech?.stop();
      if (await _sourceOwnerCurrent() && _current(epoch)) {
        setState(() => _listening = false);
      }
    } on Object {
      if (_current(epoch)) {
        setState(() => _error = 'หยุดไมโครโฟนไม่สำเร็จ กรุณายกเลิกแล้วลองใหม่');
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_cancelForLifecycle());
    }
  }

  Future<bool> _cancelForLifecycle() async {
    _speechEpoch += 1;
    _eventSequence++;
    if (mounted) {
      setState(() {
        _starting = false;
        _listening = false;
        if (_isSource && _sourceAnswer == null) {
          _sourceFinalPending = false;
          _assessment = null;
          _transcript = '';
        }
      });
    }
    try {
      await _stopAudio();
      return true;
    } on Object {
      if (mounted) {
        setState(() => _error = 'หยุดระบบเสียงไม่สำเร็จ กรุณายกเลิกอีกครั้ง');
      }
      return false;
    }
  }

  Future<void> _stopAudio() async {
    await Future.wait<void>([
      if (_speech != null) _speech!.cancel(),
      _voice.stop(),
    ]);
  }

  @override
  void dispose() {
    _speechEpoch += 1;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopAudio().catchError((Object _) {}));
    _voice.disposeIfOwned(_ownsVoice);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assessment = _assessment;
    return PopScope(
      canPop: !_isSource || _allowSourcePop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSource) unawaited(_leaveSource());
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ฝึกออกเสียง')),
        body: AdaptiveContentPane(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('พูดคำว่า', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  label: _sourceOwnerInvalid
                      ? 'คำศัพท์ไม่พร้อมในบัญชีนี้'
                      : 'ฟังการออกเสียงคำว่า ${widget.correctWord}',
                  child: InkWell(
                    onTap: _audioBlocked || _listening ? null : _speakWord,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _sourceOwnerInvalid
                                  ? 'คำศัพท์ไม่พร้อมในบัญชีนี้'
                                  : widget.correctWord,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.volume_up),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_isSource) ...[
                  const Text(
                    'ฝึกคำเดียวจากไฟล์ ไม่แนบไฟล์หรือข้อความต้นฉบับ '
                    'ไม่เก็บข้อความที่รู้จำเป็นหลักฐาน',
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _transcript.isEmpty
                              ? 'ระบบจะแสดงข้อความที่ได้ยินที่นี่'
                              : _transcript,
                          key: const ValueKey<String>('speech-transcript'),
                        ),
                        if (assessment != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            'ความเหมือนของข้อความ: '
                            '${assessment.similarityPercent}%',
                          ),
                          Text(
                            'วิธีประเมิน: เปรียบเทียบข้อความที่ระบบได้ยิน',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const Text(
                            'รอบนี้ประเมินจากข้อความที่ระบบฟังได้เท่านั้น '
                            'ยังไม่ได้วัดระดับเสียงหรือหน่วยเสียง',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const ValueKey<String>('speech-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  if (_error ==
                      _speechFailureText(
                        SpeechFailureCode.permissionPermanentlyDenied,
                      )) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => AppNavigator.pushPage<void>(
                        context,
                        AppPage<void>(
                          name: 'settings/device-permissions',
                          builder: (_) => const DevicePermissionCenterScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('เปิดศูนย์สิทธิ์อุปกรณ์'),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey<String>('speech-listen-button'),
                  onPressed: _audioBlocked
                      ? null
                      : _listening
                      ? _stopListening
                      : _startListening,
                  icon: Icon(_listening ? Icons.stop : Icons.mic),
                  label: Text(_listening ? 'หยุดฟัง' : 'เริ่มพูด'),
                ),
                const SizedBox(height: 12),
                if (_isSource) ...[
                  if (_saving || _finishing || _leaving)
                    const LinearProgressIndicator(
                      semanticsLabel: 'กำลังบันทึกหรือหยุดระบบเสียง',
                    ),
                  if (_sourceSaved)
                    const Text(
                      'บันทึกผลแล้ว กดจบการฝึกเพื่อกลับไปที่ไฟล์',
                      key: ValueKey('source-voice-saved'),
                    ),
                  if (_sourceAnswer != null &&
                      !_sourceSaved &&
                      !_sourceOwnerInvalid)
                    OutlinedButton(
                      key: const ValueKey('source-voice-retry-save'),
                      onPressed: _saving || _leaving || !_foreground
                          ? null
                          : _saveSourceAnswer,
                      child: const Text('ลองบันทึกอีกครั้ง'),
                    ),
                  FilledButton(
                    key: const ValueKey('source-voice-finish'),
                    onPressed:
                        _sourceSaved &&
                            !_sourceOwnerInvalid &&
                            !_finishing &&
                            !_leaving &&
                            !_saving &&
                            _foreground
                        ? _finishSource
                        : null,
                    child: const Text('จบการฝึกและกลับไปที่ไฟล์'),
                  ),
                  TextButton(
                    key: const ValueKey('source-voice-cancel'),
                    onPressed: _saving || _finishing || _leaving
                        ? null
                        : _leaveSource,
                    child: const Text('กลับโดยไม่ยืนยันจบการฝึก'),
                  ),
                ] else
                  OutlinedButton(
                    onPressed: assessment?.isExactMatch == true
                        ? () => AppNavigator.pushPage<void>(
                            context,
                            AppPage<void>(
                              name: 'learning/word-scramble',
                              builder: (_) =>
                                  WordScrambleScreen(word: widget.correctWord),
                            ),
                            replace: true,
                          )
                        : () => Navigator.maybePop(context),
                    child: Text(
                      assessment?.isExactMatch == true
                          ? 'ไปเกมเรียงคำ'
                          : 'กลับไปแบบทดสอบ',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _speechFailureText(SpeechFailureCode code) => switch (code) {
    SpeechFailureCode.permissionDenied => 'ไม่ได้รับสิทธิ์ใช้ไมโครโฟน',
    SpeechFailureCode.permissionPermanentlyDenied =>
      'สิทธิ์ไมโครโฟนถูกปิดถาวร กรุณาเปิดจากการตั้งค่าระบบ',
    SpeechFailureCode.noMatch => 'ไม่ได้ยินคำพูดที่ชัดเจน กรุณาลองอีกครั้ง',
    SpeechFailureCode.cancelled => 'ยกเลิกการฟังแล้ว',
    SpeechFailureCode.unavailable ||
    SpeechFailureCode.engine => 'ระบบรู้จำเสียงไม่พร้อมใช้งาน',
  };
}
