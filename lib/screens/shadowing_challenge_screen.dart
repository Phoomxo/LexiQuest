import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_models.dart';

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
    with WidgetsBindingObserver {
  late final VoiceUseCases _voice;
  bool _ownsVoice = false;
  SpeechPracticeUseCases? _speech;
  LearningUseCases? _learning;
  String? _referenceSentence;
  String? _wordId;
  String? _sessionId;
  Future<void>? _learningLoad;
  bool _evidenceSaved = false;
  bool _listening = false;
  String _transcript = '';
  String? _error;
  TranscriptPronunciationAssessment? _assessment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = widget.voice ?? VoiceUseCases.createDefault();
    _ownsVoice = widget.voice == null;
    _referenceSentence = widget.referenceSentence;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _speech ??=
        widget.speechPractice ??
        AppDependenciesScope.maybeOf(context)?.speechPractice;
    _learning ??=
        widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;
    if (_referenceSentence == null && _learningLoad == null) {
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
    if (reference == null) return;
    try {
      await _voice.speak(
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
    if (_listening) {
      await _speech?.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final speech = _speech;
    if (speech == null) {
      setState(() => _error = 'ระบบรู้จำเสียงไม่พร้อมใช้งาน');
      return;
    }
    setState(() {
      _error = null;
      _transcript = '';
      _assessment = null;
    });
    try {
      await speech.start(
        locale: 'en-US',
        onEvent: (event) {
          if (!mounted) return;
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
          if (!mounted) return;
          setState(() {
            _listening = false;
            _error = _failureText(failure);
          });
        },
        onStatus: (status) {
          if (mounted) setState(() => _listening = status == 'listening');
        },
      );
      if (mounted) setState(() => _listening = speech.isListening);
    } on SpeechPracticeException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.code));
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
            '${event.engine}:${event.locale}:transcript-similarity-v1',
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
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_cancelForLifecycle());
    }
  }

  Future<void> _cancelForLifecycle() async {
    await _speech?.cancel();
    if (mounted && _listening) setState(() => _listening = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech?.cancel());
    unawaited(_voice.stop());
    _voice.disposeIfOwned(_ownsVoice);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: reference == null ? null : _toggleListening,
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
