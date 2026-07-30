import 'dart:async';

import 'package:flutter/material.dart';

import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';

class ShadowingChallengeScreen extends StatefulWidget {
  const ShadowingChallengeScreen({
    super.key,
    required this.referenceSentence,
    this.voiceProvider,
    this.speechPractice,
  });

  final String referenceSentence;
  final VoiceProvider? voiceProvider;
  final SpeechPracticeUseCases? speechPractice;

  @override
  State<ShadowingChallengeScreen> createState() =>
      _ShadowingChallengeScreenState();
}

class _ShadowingChallengeScreenState extends State<ShadowingChallengeScreen>
    with WidgetsBindingObserver {
  late final VoiceProvider _voice;
  bool _ownsVoice = false;
  SpeechPracticeUseCases? _speech;
  bool _listening = false;
  String _transcript = '';
  String? _error;
  TranscriptPronunciationAssessment? _assessment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = widget.voiceProvider ?? VoiceServiceFactory.create();
    _ownsVoice = widget.voiceProvider == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _speech ??=
        widget.speechPractice ??
        AppDependenciesScope.maybeOf(context)?.speechPractice;
  }

  Future<void> _playReference() async {
    try {
      await _voice.speak(
        VoiceRequest.create(
          text: widget.referenceSentence,
          language: 'en',
          voiceId: 'device-default',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: 'shadowing:${widget.referenceSentence.hashCode}',
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
          setState(() {
            _transcript = event.transcript;
            _assessment = speech.assess(
              target: widget.referenceSentence,
              event: event,
            );
            if (event.isFinal) _listening = false;
          });
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
      appBar: AppBar(title: const Text('ฝึกพูดตามเสียงต้นแบบ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.referenceSentence,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey<String>('shadowing-play-reference'),
              onPressed: _playReference,
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('ฟังเสียงต้นแบบ (1.0x)'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey<String>('shadowing-listen-button'),
              onPressed: _toggleListening,
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
