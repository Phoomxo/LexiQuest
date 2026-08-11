import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';
import 'media_dependency_unavailable.dart';

class ShadowingChallengeScreen extends StatefulWidget {
  const ShadowingChallengeScreen({
    super.key,
    this.referenceSentence,
    this.voice,
    this.speechPractice,
    this.learning,
  });

  final String? referenceSentence;
  final VoiceUseCases? voice;
  final SpeechPracticeUseCases? speechPractice;
  final LearningUseCases? learning;

  @override
  State<ShadowingChallengeScreen> createState() =>
      _ShadowingChallengeScreenState();
}

class _ShadowingChallengeScreenState extends State<ShadowingChallengeScreen>
    with
        WidgetsBindingObserver,
        RouteVoiceSessionMixin<ShadowingChallengeScreen> {
  VoiceUseCases? _voice;
  SpeechPracticeUseCases? _speech;
  SpeechPracticeSession? _speechSession;
  LearningUseCases? _learning;
  String? _referenceSentence;
  String? _wordId;
  String? _sessionId;
  Future<void>? _learningLoad;
  bool _evidenceSaved = false;
  bool _listenPending = false;
  int _listenEpoch = 0;
  bool _listening = false;
  String _transcript = '';
  String? _error;
  TranscriptPronunciationAssessment? _assessment;

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  Future<void> onVoiceRouteCovered() async {
    _listenEpoch += 1;
    _listenPending = false;
    _listening = false;
    final session = _speechSession;
    _speechSession = null;
    await session?.release();
  }

  @override
  void onVoiceRouteResumed() => _bindDependencies(refreshVoice: false);

  @override
  void initState() {
    super.initState();
    _referenceSentence = widget.referenceSentence;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindDependencies();
  }

  @override
  void didUpdateWidget(ShadowingChallengeScreen oldWidget) {
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
    if (refreshVoice) refreshRouteVoiceSession();
    _speech = speech;
    _learning = widget.learning ?? dependencies?.learning;
    if (routeIsCurrent &&
        speech != null &&
        (_speechSession == null || !_speechSession!.isCurrent)) {
      _speechSession?.release().ignore();
      _speechSession = speech.acquireSession();
    }
    if (routeIsCurrent &&
        _voice != null &&
        _speech != null &&
        _referenceSentence == null &&
        _learningLoad == null) {
      _learningLoad = _loadLocalPrompt();
    }
  }

  Future<void> _loadLocalPrompt() async {
    final learning = _learning;
    if (learning == null) {
      if (mounted) {
        setState(() => _error = 'ไม่สามารถอ่านคำศัพท์ในเครื่องได้');
      }
      return;
    }
    try {
      final session = await learning.startQuiz(limit: 1);
      if (!mounted) return;
      if (session.isEmpty) {
        setState(() => _error = 'ยังไม่มีคำศัพท์สำหรับฝึกพูด');
        return;
      }
      setState(() {
        _sessionId = session.id;
        _wordId = session.questions.single.word.id;
        _referenceSentence = session.questions.single.word.spelling;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'ไม่สามารถเริ่มการฝึกพูดได้');
    }
  }

  Future<void> _playReference() async {
    final reference = _referenceSentence;
    final session = routeVoiceSession;
    if (reference == null || session == null) return;
    try {
      await session.speak(
        VoiceRequest.create(
          text: reference,
          language: 'en',
          voiceId: 'device-default',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: 'shadowing:${reference.hashCode}',
          contentType: 'shadowing-reference',
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _error = 'ระบบอ่านเสียงต้นแบบไม่พร้อมใช้งาน');
    }
  }

  Future<void> _toggleListening() async {
    if (_listenPending) return;
    if (_listening) {
      _listenEpoch += 1;
      _listenPending = false;
      await _speechSession?.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final speech = _speech;
    var session = _speechSession;
    if (speech == null) {
      setState(() => _error = 'ระบบรู้จำเสียงไม่พร้อมใช้งาน');
      return;
    }
    if (session == null || !session.isCurrent) {
      session?.release().ignore();
      session = speech.acquireSession();
      _speechSession = session;
    }
    final activeSession = session;
    final epoch = ++_listenEpoch;
    _listenPending = true;
    setState(() {
      _error = null;
      _transcript = '';
      _assessment = null;
    });
    try {
      final started = await activeSession.start(
        locale: 'en-US',
        onEvent: (event) {
          if (!mounted || epoch != _listenEpoch) return;
          final reference = _referenceSentence;
          if (reference == null) return;
          final assessment = speech.assess(target: reference, event: event);
          setState(() {
            _transcript = event.transcript;
            _assessment = assessment;
            if (event.isFinal) _listening = false;
          });
          if (event.isFinal) {
            unawaited(_recordEvidence(event, assessment));
          }
        },
        onFailure: (failure) {
          if (!mounted || epoch != _listenEpoch) return;
          setState(() {
            _listening = false;
            _error = _failureText(failure);
          });
        },
        onStatus: (status) {
          if (mounted && epoch == _listenEpoch) {
            setState(() => _listening = status == 'listening');
          }
        },
      );
      if (!mounted || epoch != _listenEpoch) return;
      if (!started) {
        _listenPending = false;
        setState(() => _listening = false);
        return;
      }
      _listenPending = false;
      setState(() => _listening = activeSession.isListening);
    } on SpeechPracticeException catch (error) {
      if (!mounted || epoch != _listenEpoch) return;
      _listenPending = false;
      setState(() => _error = _failureText(error.code));
    }
  }

  Future<void> _recordEvidence(
    SpeechRecognitionEvent event,
    TranscriptPronunciationAssessment assessment,
  ) async {
    final learning = _learning;
    final sessionId = _sessionId;
    final wordId = _wordId;
    if (_evidenceSaved ||
        learning == null ||
        sessionId == null ||
        wordId == null) {
      return;
    }
    _evidenceSaved = true;
    try {
      await learning.recordAnswer(
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'shadowing',
        isCorrect: assessment.similarityPercent >= 80,
        responseTimeMs: null,
        attemptNumber: 1,
        providerProvenance:
            '${event.engine}|${event.locale}|${assessment.method}',
      );
      await learning.finishSession(sessionId);
    } catch (_) {
      _evidenceSaved = false;
      if (mounted) {
        setState(() => _error = 'วิเคราะห์เสียงได้แต่บันทึกประวัติไม่สำเร็จ');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _cancelForLifecycle().ignore();
    }
  }

  Future<void> _cancelForLifecycle() async {
    final shouldCancel = _listenPending || _listening;
    _listenEpoch += 1;
    _listenPending = false;
    try {
      if (shouldCancel) await _speechSession?.cancel();
    } on Object {
      // Lifecycle cleanup is best effort and must not escape its detached hook.
    }
    if (mounted && _listening) setState(() => _listening = false);
  }

  @override
  void dispose() {
    _listenEpoch += 1;
    _listenPending = false;
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
    final reference = _referenceSentence;
    return Scaffold(
      appBar: AppBar(title: const Text('ฝึกพูดตามเสียงต้นแบบ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (reference == null && _error == null)
              const Center(child: CircularProgressIndicator())
            else if (reference != null)
              Text(reference, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey<String>('shadowing-play-reference'),
              onPressed: reference == null ? null : _playReference,
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('ฟังเสียงต้นแบบ (1.0x)'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('shadowing-listen-button'),
              onPressed: reference == null || _listenPending
                  ? null
                  : _toggleListening,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(_listening ? 'หยุดบันทึก' : 'พูดตามประโยค'),
            ),
            if (_transcript.isNotEmpty) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ข้อความที่ได้ยิน: $_transcript'),
                      if (assessment != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'ความเหมือนของข้อความ: '
                          '${assessment.similarityPercent}%',
                        ),
                        const Text(
                          'เกณฑ์บันทึกคำตอบถูก: ความเหมือนของข้อความอย่างน้อย 80% · อัลกอริทึม v1',
                        ),
                        Text(
                          'เอนจิน: ${assessment.engine} '
                          '(${assessment.locale})',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'เอนจินนี้ไม่ได้ส่งข้อมูล pitch หรือ phoneme '
                          'จึงไม่แสดงคะแนนที่คาดเดาขึ้น',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _failureText(SpeechFailureCode code) => switch (code) {
    SpeechFailureCode.permissionDenied => 'ไม่ได้รับสิทธิ์ใช้ไมโครโฟน',
    SpeechFailureCode.permissionPermanentlyDenied =>
      'สิทธิ์ไมโครโฟนถูกปิดถาวร กรุณาเปิดจากการตั้งค่าระบบ',
    SpeechFailureCode.noMatch => 'ไม่ได้ยินเสียงพูดที่ชัดเจน',
    SpeechFailureCode.cancelled => 'ยกเลิกการฟังแล้ว',
    SpeechFailureCode.unavailable ||
    SpeechFailureCode.engine => 'ระบบรู้จำเสียงไม่พร้อมใช้งาน',
  };
}
