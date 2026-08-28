import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';
import 'media_dependency_unavailable.dart';

class SpeakToTextScreen extends StatefulWidget {
  const SpeakToTextScreen({
    super.key,
    required this.correctWord,
    this.voice,
    this.speechPractice,
    this.learning,
    this.ownerId,
    this.sessionId,
    this.wordId,
    this.attemptNumber = 1,
    this.evidenceAdapter,
    this.modeAdapter = const SpeakingModeAdapter(),
  });

  final String correctWord;
  final VoiceUseCases? voice;
  final SpeechPracticeUseCases? speechPractice;
  final LearningUseCases? learning;
  final String? ownerId;
  final String? sessionId;
  final String? wordId;
  final int attemptNumber;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final SpeakingModeAdapter modeAdapter;

  @override
  State<SpeakToTextScreen> createState() => _SpeakToTextScreenState();
}

class _SpeakToTextScreenState extends State<SpeakToTextScreen>
    with WidgetsBindingObserver, RouteVoiceSessionMixin<SpeakToTextScreen>
    implements EphemeralLessonState {
  VoiceUseCases? _voice;
  SpeechPracticeUseCases? _speech;
  SpeechPracticeSession? _speechSession;
  LearningUseCases? _learning;
  bool _initialPlaybackScheduled = false;
  bool _listenPending = false;
  int _listenEpoch = 0;
  int? _acceptedFinalEpoch;
  bool _listening = false;
  String _transcript = '';
  String? _error;
  TranscriptPronunciationAssessment? _assessment;
  DateTime? _startedAtUtc;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  PendingCurrentActivityEvidence? _pendingEvidence;
  PendingLearningSessionClose? _pendingSessionClose;
  UnifiedLessonSessionLifecycle? _lifecycle;
  UnifiedLessonSessionLifecycleScope? _lifecycleScope;
  bool _sessionCompleted = false;

  SpeakingModeAdapter get _modeAdapter => widget.modeAdapter;
  bool get _acceptsModeOperations =>
      mounted && (_lifecycle?.acceptsOperations ?? true);
  bool get _persistenceLocked =>
      _pendingEvidence != null || _pendingSessionClose != null;
  bool get _sessionCloseRetryRequired =>
      (_pendingSessionClose?.requiresRetry ?? false) ||
      (_lifecycle?.sessionCompletionRetryRequired ?? false);

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  Future<void> onVoiceRouteCovered() async {
    _clearRawSpeechState();
    final session = _speechSession;
    _speechSession = null;
    await session?.release();
  }

  @override
  void onVoiceRouteResumed() => _bindDependencies(refreshVoice: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScope = UnifiedLessonSessionLifecycleScope.maybeScopeOf(context);
    if (!identical(nextScope, _lifecycleScope)) {
      _lifecycleScope?.unregisterEphemeralState(this);
      _lifecycleScope = nextScope;
      nextScope?.registerEphemeralState(this);
    }
    _bindDependencies();
  }

  @override
  void didUpdateWidget(SpeakToTextScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindDependencies();
  }

  void _bindDependencies({bool refreshVoice = true}) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? true;
    final speech = widget.speechPractice ?? dependencies?.speechPractice;
    if (!identical(speech, _speech) || !routeIsCurrent) {
      _listenEpoch += 1;
      _listenPending = false;
      _listening = false;
      _speechSession?.release().ignore();
      _speechSession = null;
    }
    _voice = widget.voice ?? dependencies?.voice;
    _lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    if (refreshVoice) refreshRouteVoiceSession();
    _speech = speech;
    _learning = widget.learning ?? dependencies?.learning;
    final learning = _learning;
    if (learning != null) {
      _evidenceAdapter =
          widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
      if (_evidenceAdapter == null) {
        throw StateError('current activity evidence dependency unavailable');
      }
    }
    if (routeIsCurrent &&
        speech != null &&
        (_speechSession == null || !_speechSession!.isCurrent)) {
      _speechSession?.release().ignore();
      _speechSession = speech.acquireSession();
    }
    if (routeIsCurrent &&
        _voice != null &&
        _speech != null &&
        !_initialPlaybackScheduled) {
      _initialPlaybackScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _speakWord();
      });
    }
  }

  Future<void> _speakWord() async {
    if (_persistenceLocked || _sessionCompleted || !_acceptsModeOperations) {
      return;
    }
    final session = routeVoiceSession;
    if (session == null) return;
    try {
      await session.speak(
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
    } catch (_) {
      if (mounted) setState(() => _error = 'ระบบอ่านออกเสียงไม่พร้อมใช้งาน');
    }
  }

  Future<void> _startListening() async {
    if (_listenPending ||
        _persistenceLocked ||
        _sessionCompleted ||
        !_acceptsModeOperations) {
      return;
    }
    final speech = _speech;
    var session = _speechSession;
    if (speech == null) {
      setState(() => _error = 'ระบบรู้จำเสียงไม่พร้อมใช้งานบนอุปกรณ์นี้');
      return;
    }
    if (session == null || !session.isCurrent) {
      session?.release().ignore();
      session = speech.acquireSession();
      _speechSession = session;
    }
    final activeSession = session;
    final epoch = ++_listenEpoch;
    _acceptedFinalEpoch = null;
    _listenPending = true;
    setState(() {
      _error = null;
      _transcript = '';
      _assessment = null;
    });
    _startedAtUtc = DateTime.now().toUtc();
    try {
      final started = await activeSession.start(
        locale: 'en-US',
        onEvent: (event) => _onSpeechEvent(event, epoch),
        onFailure: (failure) {
          if (!_acceptsModeOperations ||
              epoch != _listenEpoch ||
              _acceptedFinalEpoch == epoch) {
            return;
          }
          setState(() {
            _listening = false;
            _error = _speechFailureText(failure);
          });
        },
        onStatus: (status) {
          if (!_acceptsModeOperations ||
              epoch != _listenEpoch ||
              _acceptedFinalEpoch == epoch) {
            return;
          }
          setState(() => _listening = status == 'listening');
        },
      );
      if (!_acceptsModeOperations || epoch != _listenEpoch) return;
      if (_acceptedFinalEpoch == epoch) {
        _listenPending = false;
        return;
      }
      if (!started) {
        _listenPending = false;
        setState(() => _listening = false);
        return;
      }
      _listenPending = false;
      setState(() => _listening = activeSession.isListening);
    } on SpeechPracticeException catch (error) {
      if (!_acceptsModeOperations ||
          epoch != _listenEpoch ||
          _acceptedFinalEpoch == epoch) {
        return;
      }
      _listenPending = false;
      setState(() {
        _listening = false;
        _error = _speechFailureText(error.code);
      });
    }
  }

  void _onSpeechEvent(SpeechRecognitionEvent event, int epoch) {
    if (!_acceptsModeOperations ||
        epoch != _listenEpoch ||
        _acceptedFinalEpoch == epoch) {
      return;
    }
    if (event.isFinal) {
      _acceptedFinalEpoch = epoch;
      _listenPending = false;
      _speechSession?.stop().ignore();
    }
    final assessment = _speech!.assess(
      target: widget.correctWord,
      event: event,
    );
    setState(() {
      _transcript = event.transcript;
      _assessment = assessment;
      if (event.isFinal) _listening = false;
    });
    if (event.isFinal) unawaited(_recordEvidence(assessment));
  }

  Future<void> _recordEvidence(
    TranscriptPronunciationAssessment assessment,
  ) async {
    final learning = _learning;
    final sessionId = widget.sessionId;
    final wordId = widget.wordId;
    if (learning == null || sessionId == null || wordId == null) return;
    if (!_acceptsModeOperations) return;
    final elapsed = _startedAtUtc == null
        ? null
        : DateTime.now().toUtc().difference(_startedAtUtc!).inMilliseconds;
    final pending = _pendingEvidence ??= _modeAdapter
        .capture(
          evidence: _evidenceAdapter!,
          ownerId: widget.ownerId,
          sessionId: sessionId,
          wordId: wordId,
          assessment: assessment,
          responseTimeMs: elapsed,
          attemptNumber: widget.attemptNumber,
        )
        .pending;
    if (mounted) setState(() {});
    try {
      await (_lifecycle?.runAcceptedOperation(pending.record) ??
          pending.record());
      _pendingEvidence = null;
      await _completeShellSession();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'บันทึกผลการฝึกไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    }
  }

  Future<void> _retryEvidence() async {
    final pending = _pendingEvidence;
    if (pending == null || !pending.requiresRetry || !_acceptsModeOperations) {
      return;
    }
    setState(() => _error = null);
    try {
      await (_lifecycle?.runAcceptedOperation(pending.retry) ??
          pending.retry());
      _pendingEvidence = null;
      await _completeShellSession();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'บันทึกผลการฝึกไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    }
  }

  Future<void> _completeShellSession() async {
    final lifecycle = _lifecycle;
    final learning = _learning;
    final sessionId = widget.sessionId;
    if (lifecycle == null || learning == null || sessionId == null) {
      if (mounted) setState(() {});
      return;
    }
    final close = _pendingSessionClose ??= learning.captureSessionClose(
      sessionId: sessionId,
      ownerId: widget.ownerId,
    );
    if (mounted) setState(() {});
    try {
      await _lifecycle!.complete(close);
      _pendingSessionClose = null;
      _sessionCompleted = true;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'บันทึกคำตอบแล้วแต่ปิดเซสชันไม่สำเร็จ');
      }
    }
  }

  Future<void> _retrySessionClose() async {
    final close = _pendingSessionClose;
    if (close == null ||
        !_sessionCloseRetryRequired ||
        !_acceptsModeOperations) {
      return;
    }
    setState(() => _error = null);
    try {
      await _lifecycle!.complete(close);
      _pendingSessionClose = null;
      _sessionCompleted = true;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'ปิดเซสชันไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    }
  }

  Future<void> _stopListening() async {
    _listenEpoch += 1;
    _listenPending = false;
    await _speechSession?.stop();
    if (mounted) setState(() => _listening = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      clearEphemeralState();
    }
  }

  @override
  void clearEphemeralState() {
    final session = _speechSession;
    _clearRawSpeechState();
    session?.cancel().ignore();
  }

  void _clearRawSpeechState({bool notify = true}) {
    _listenEpoch += 1;
    _listenPending = false;
    _acceptedFinalEpoch = null;
    _listening = false;
    _startedAtUtc = null;
    if (notify && mounted) {
      setState(() {
        _transcript = '';
        _assessment = null;
        _error = null;
      });
    } else {
      _transcript = '';
      _assessment = null;
      _error = null;
    }
  }

  @override
  void dispose() {
    _lifecycleScope?.unregisterEphemeralState(this);
    _clearRawSpeechState(notify: false);
    _speechSession?.release().ignore();
    _speechSession = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_voice == null) {
      return const MediaDependencyUnavailable(
        reason: MediaDependencyUnavailableReason.voice,
      );
    }
    if (_speech == null) {
      return const MediaDependencyUnavailable(
        reason: MediaDependencyUnavailableReason.speechPractice,
      );
    }
    final assessment = _assessment;
    final evidenceLocked = _persistenceLocked;
    return PopScope(
      canPop: !evidenceLocked,
      child: Scaffold(
        appBar: AppBar(title: const Text('ฝึกออกเสียง')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('พูดคำว่า', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Semantics(
                button: true,
                label: 'ฟังการออกเสียงคำว่า ${widget.correctWord}',
                child: InkWell(
                  onTap: evidenceLocked || _sessionCompleted
                      ? null
                      : _speakWord,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.correctWord,
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
                          'วิธีวัด: ${assessment.method}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Text(
                          'ไม่มีการวัด pitch หรือ phoneme จากเอนจินนี้',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const ValueKey<String>('speech-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey<String>('speech-listen-button'),
                onPressed:
                    _listenPending || _persistenceLocked || _sessionCompleted
                    ? null
                    : (_listening ? _stopListening : _startListening),
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Text(_listening ? 'หยุดฟัง' : 'เริ่มพูด'),
              ),
              if (_pendingEvidence?.requiresRetry ?? false) ...[
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey<String>('current-evidence-retry'),
                  onPressed: _retryEvidence,
                  child: const Text('Retry saved pronunciation'),
                ),
              ],
              if (_sessionCloseRetryRequired) ...[
                const SizedBox(height: 12),
                FilledButton(
                  key: const ValueKey<String>('session-close-retry'),
                  onPressed: _retrySessionClose,
                  child: const Text('Retry session completion'),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: evidenceLocked
                    ? null
                    : () => Navigator.maybePop(context),
                child: Text(
                  assessment?.isExactMatch == true || _sessionCompleted
                      ? 'เสร็จสิ้น'
                      : 'กลับไปแบบทดสอบ',
                ),
              ),
            ],
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
