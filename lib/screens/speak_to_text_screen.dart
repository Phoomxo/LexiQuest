import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';
import 'word_scramble_screen.dart';
import '../navigation/app_routes.dart';

class SpeakToTextScreen extends StatefulWidget {
  const SpeakToTextScreen({
    super.key,
    required this.correctWord,
    this.voiceProvider,
    this.speechPractice,
    this.sessionId,
    this.wordId,
    this.attemptNumber = 1,
  });

  final String correctWord;
  final VoiceProvider? voiceProvider;
  final SpeechPracticeUseCases? speechPractice;
  final String? sessionId;
  final String? wordId;
  final int attemptNumber;

  @override
  State<SpeakToTextScreen> createState() => _SpeakToTextScreenState();
}

class _SpeakToTextScreenState extends State<SpeakToTextScreen>
    with WidgetsBindingObserver {
  late final VoiceProvider _voice;
  bool _ownsVoice = false;
  SpeechPracticeUseCases? _speech;
  LearningUseCases? _learning;
  bool _listening = false;
  String _transcript = '';
  String? _error;
  TranscriptPronunciationAssessment? _assessment;
  DateTime? _startedAtUtc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = widget.voiceProvider ?? VoiceServiceFactory.create();
    _ownsVoice = widget.voiceProvider == null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakWord());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _speech ??= widget.speechPractice ?? dependencies?.speechPractice;
    _learning ??= dependencies?.learning;
  }

  Future<void> _speakWord() async {
    try {
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
    } catch (_) {
      if (mounted) setState(() => _error = 'ระบบอ่านออกเสียงไม่พร้อมใช้งาน');
    }
  }

  Future<void> _startListening() async {
    final speech = _speech;
    if (speech == null) {
      setState(() => _error = 'ระบบรู้จำเสียงไม่พร้อมใช้งานบนอุปกรณ์นี้');
      return;
    }
    setState(() {
      _error = null;
      _transcript = '';
      _assessment = null;
    });
    _startedAtUtc = DateTime.now().toUtc();
    try {
      await speech.start(
        locale: 'en-US',
        onEvent: _onSpeechEvent,
        onFailure: (failure) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _error = _speechFailureText(failure);
          });
        },
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _listening = status == 'listening');
        },
      );
      if (mounted) setState(() => _listening = speech.isListening);
    } on SpeechPracticeException catch (error) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = _speechFailureText(error.code);
        });
      }
    }
  }

  void _onSpeechEvent(SpeechRecognitionEvent event) {
    if (!mounted) return;
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
    await _speech?.stop();
    if (mounted) setState(() => _listening = false);
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
    if (_ownsVoice && _voice is ManagedVoiceService) {
      _voice.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assessment = _assessment;
    return Scaffold(
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
                onTap: _speakWord,
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
                      const Text('ไม่มีการวัด pitch หรือ phoneme จากเอนจินนี้'),
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
              onPressed: _listening ? _stopListening : _startListening,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(_listening ? 'หยุดฟัง' : 'เริ่มพูด'),
            ),
            const SizedBox(height: 12),
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
