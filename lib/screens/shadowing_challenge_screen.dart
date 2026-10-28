import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../features/media_practice/domain/speech_evidence_contract.dart';
import '../features/media_practice/domain/speech_evidence_use_cases.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/scoped_voice_provider.dart';
import '../voice/voice_capability.dart';
import '../voice/voice_mirror_recorder.dart';
import '../voice/voice_mirror_session_controller.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';

/// Optional AI target-speech mirror status surfaced to the participant.
enum VoiceMirrorStatus { idle, recording, enrolling, ready, error }

class ShadowingChallengeScreen extends StatefulWidget {
  const ShadowingChallengeScreen({
    super.key,
    this.referenceSentence,
    this.voiceProvider,
    this.speechPractice,
    this.learning,
    this.voiceMirrorController,
    this.voiceMirrorRecorder,
    this.speechEvidence,
    this.sessionId,
    this.wordId,
  });

  final String? referenceSentence;
  final VoiceProvider? voiceProvider;
  final SpeechPracticeUseCases? speechPractice;
  final LearningUseCases? learning;
  final VoiceMirrorSessionController? voiceMirrorController;
  final VoiceMirrorRecorder? voiceMirrorRecorder;
  final SpeechEvidenceUseCases? speechEvidence;
  final String? sessionId;
  final String? wordId;

  @override
  State<ShadowingChallengeScreen> createState() =>
      _ShadowingChallengeScreenState();
}

class _ShadowingChallengeScreenState extends State<ShadowingChallengeScreen>
    with WidgetsBindingObserver {
  VoiceProvider? _voice;
  SpeechPracticeUseCases? _speech;
  LearningUseCases? _learning;
  SpeechEvidenceUseCases? _speechEvidence;
  String? _referenceSentence;
  String? _wordId;
  String? _sessionId;
  Future<void>? _learningLoad;
  bool _evidenceSaved = false;
  bool _listening = false;
  String _transcript = '';
  String? _error;
  TranscriptPronunciationAssessment? _assessment;

  VoiceMirrorSessionController? _mirrorController;
  VoiceMirrorRecorder? _mirrorRecorder;
  bool _mirrorConsent = false;
  VoiceMirrorStatus _mirrorStatus = VoiceMirrorStatus.idle;
  String? _mirrorError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _referenceSentence = widget.referenceSentence;
    _sessionId = widget.sessionId;
    _wordId = widget.wordId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voice ??= resolveScopedVoiceProvider(context, widget.voiceProvider);
    _speech ??=
        widget.speechPractice ??
        AppDependenciesScope.maybeOf(context)?.speechPractice;
    _learning ??=
        widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;
    _speechEvidence ??= widget.speechEvidence;
    _mirrorController ??= widget.voiceMirrorController;
    _mirrorRecorder ??= widget.voiceMirrorRecorder;
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
    final voice = _voice;
    if (reference == null || voice == null) return;
    try {
      await voice.speak(
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
          final result = speech.assessEvidence(target: reference, event: event);
          final assessment = result.isAvailable
              ? (result as SpeechAssessmentAvailable).assessment
              : null;
          setState(() {
            _transcript = event.transcript;
            _assessment = assessment;
            if (event.isFinal) _listening = false;
          });
          if (event.isFinal) {
            unawaited(_recordEvidence(event, result));
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
    SpeechAssessmentResult result,
  ) async {
    final sessionId = _sessionId;
    final wordId = _wordId;
    if (_evidenceSaved || sessionId == null || wordId == null) {
      return;
    }
    final reference = _referenceSentence ?? '';
    _evidenceSaved = true;

    // Persist the real, non-fabricated speech evidence alongside the boolean
    // answer that feeds SRS. Silence/unavailable produces no score.
    final evidence = _speechEvidence;
    if (evidence != null) {
      try {
        await _persistSpeechEvidence(
          evidence: evidence,
          event: event,
          result: result,
          reference: reference,
          sessionId: sessionId,
          wordId: wordId,
        );
      } catch (_) {
        // Evidence persistence is best-effort; the boolean answer below still
        // records the learning outcome for SRS.
      }
    }

    final learning = _learning;
    if (learning == null) {
      return;
    }
    try {
      final isCorrect = result.isAvailable
          ? (result as SpeechAssessmentAvailable)
                    .assessment
                    .similarityPercent >=
                80
          : false;
      final provenance = result.isAvailable
          ? (result as SpeechAssessmentAvailable).provenance
                .toProvenanceString()
          : SpeechEvidenceProvenance(
              engine: event.engine,
              locale: event.locale,
              method: SpeechEvidenceProvenance.supportedMethod,
            ).toProvenanceString();
      await learning.recordAnswer(
        sessionId: sessionId,
        wordId: wordId,
        promptMode: 'shadowing',
        isCorrect: isCorrect,
        responseTimeMs: null,
        attemptNumber: 1,
        providerProvenance: provenance,
      );
      await learning.finishSession(sessionId);
    } catch (_) {
      _evidenceSaved = false;
      if (mounted) {
        setState(() => _error = 'วิเคราะห์เสียงได้แต่บันทึกประวัติไม่สำเร็จ');
      }
    }
  }

  Future<void> _persistSpeechEvidence({
    required SpeechEvidenceUseCases evidence,
    required SpeechRecognitionEvent event,
    required SpeechAssessmentResult result,
    required String reference,
    required String sessionId,
    required String wordId,
  }) async {
    final int? similarityScore;
    final bool isExactMatch;
    final double? recognitionConfidence;
    final String? unavailableReason;
    final String recognizedTranscript;
    final int sampleSize;
    if (result.isAvailable) {
      final available = result as SpeechAssessmentAvailable;
      similarityScore = available.assessment.similarityPercent;
      isExactMatch = available.assessment.isExactMatch;
      recognitionConfidence = available.recognitionConfidence;
      unavailableReason = null;
      recognizedTranscript = available.assessment.transcript;
      sampleSize = 1;
    } else {
      final unavailable = result as SpeechAssessmentUnavailable;
      similarityScore = null;
      isExactMatch = false;
      recognitionConfidence = null;
      unavailableReason = unavailable.reason.name;
      recognizedTranscript = event.transcript;
      sampleSize = 0;
    }
    await evidence.record(
      sessionId: sessionId,
      wordId: wordId,
      promptMode: 'shadowing',
      targetContent: reference,
      recognizedTranscript: recognizedTranscript,
      locale: event.locale,
      sttEngine: event.engine,
      similarityAlgorithm: SpeechEvidenceProvenance.supportedMethod,
      similarityScore: similarityScore,
      isExactMatch: isExactMatch,
      recognitionConfidence: recognitionConfidence,
      sampleSize: sampleSize,
      unavailableReason: unavailableReason,
      occurredAtUtc: event.recognizedAtUtc,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _mirrorController?.onAppLifecycleStateChanged(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_cancelForLifecycle());
    }
  }

  Future<void> _cancelForLifecycle() async {
    await _speech?.cancel();
    await _mirrorRecorder?.cancel();
    if (mounted && _listening) setState(() => _listening = false);
    _resetMirrorStatus();
  }

  void _resetMirrorStatus() {
    if (!mounted) return;
    if (_mirrorStatus != VoiceMirrorStatus.idle) {
      setState(() {
        _mirrorStatus = VoiceMirrorStatus.idle;
        _mirrorError = null;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_speech?.cancel());
    unawaited(_mirrorRecorder?.cancel());
    unawaited(_mirrorController?.onActivityLeave());
    final voice = _voice;
    if (voice != null) {
      unawaited(voice.stop());
    }
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
            if (_mirrorAvailable) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'เสียงเป้าหมายที่สร้างด้วย AI (ทางเลือก)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'ใช้เสียงของคุณเพื่อสร้างไกด์การออกเสียงเท่านั้น '
                        'ประมวลผลบนเซิร์ฟเวอร์และเก็บไว้ชั่วคราว '
                        'ครั้งละไม่เกิน 5 นาทีและรวมไม่เกิน 20 นาทีต่อเซสชัน '
                        'ข้อมูลเสียงและเซสชันถูกลบเมื่อจบ '
                        'ไม่บันทึก ไม่ส่งออก ไม่แชร์และไม่ซิงค์ '
                        'ปฏิเสธได้และยังใช้เสียงมาตรฐานได้ตามปกติ',
                      ),
                      SwitchListTile(
                        key: const ValueKey<String>('mirror-consent-switch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'ยินยอมใช้เสียงเป้าหมายที่สร้างด้วย AI',
                        ),
                        value: _mirrorConsent,
                        onChanged:
                            _mirrorStatus == VoiceMirrorStatus.recording ||
                                _mirrorStatus == VoiceMirrorStatus.enrolling
                            ? null
                            : _toggleMirrorConsent,
                      ),
                      if (_mirrorConsent) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (_mirrorStatus != VoiceMirrorStatus.ready) ...[
                              FilledButton.icon(
                                key: const ValueKey<String>(
                                  'mirror-enroll-button',
                                ),
                                onPressed:
                                    _mirrorStatus ==
                                            VoiceMirrorStatus.recording ||
                                        _mirrorStatus ==
                                            VoiceMirrorStatus.enrolling
                                    ? null
                                    : _startMirrorEnrollment,
                                icon: const Icon(Icons.graphic_eq),
                                label: const Text('เริ่มอัดเสียงตัวอย่าง'),
                              ),
                              if (_mirrorStatus ==
                                      VoiceMirrorStatus.recording ||
                                  _mirrorStatus ==
                                      VoiceMirrorStatus.enrolling) ...[
                                FilledButton.tonalIcon(
                                  key: const ValueKey<String>(
                                    'mirror-cancel-button',
                                  ),
                                  onPressed: _cancelMirrorEnrollment,
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: const Text('ยกเลิก'),
                                ),
                              ],
                            ],
                            if (_mirrorStatus == VoiceMirrorStatus.ready)
                              FilledButton.icon(
                                key: const ValueKey<String>(
                                  'mirror-play-button',
                                ),
                                onPressed: _playMirrorTarget,
                                icon: const Icon(Icons.spatial_audio_off),
                                label: const Text('ฟังเสียงเป้าหมาย (AI)'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'สถานะ: $_mirrorStatusText',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_mirrorError != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _mirrorError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
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

  // ---- Participant voice mirror (optional AI target speech) ----

  bool get _mirrorAvailable =>
      _mirrorController != null && _mirrorRecorder != null;

  Future<void> _toggleMirrorConsent(bool value) async {
    if (!value) {
      await _mirrorController?.withdrawConsent();
      await _mirrorRecorder?.cancel();
      if (mounted) {
        setState(() {
          _mirrorConsent = false;
          _mirrorStatus = VoiceMirrorStatus.idle;
          _mirrorError = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _mirrorConsent = true;
        _mirrorError = null;
      });
    }
  }

  Future<void> _startMirrorEnrollment() async {
    final controller = _mirrorController;
    final recorder = _mirrorRecorder;
    final reference = _referenceSentence;
    if (controller == null || recorder == null || reference == null) return;
    if (!_mirrorConsent) return;
    setState(() {
      _mirrorStatus = VoiceMirrorStatus.recording;
      _mirrorError = null;
    });
    try {
      await recorder.start();
      setState(() => _mirrorStatus = VoiceMirrorStatus.enrolling);
      final bytes = await recorder.stop();
      await controller.start(enrollmentWav: bytes);
      setState(() => _mirrorStatus = VoiceMirrorStatus.ready);
    } on VoiceMirrorRecorderFailure catch (failure) {
      await _handleMirrorRecorderFailure(failure);
    } on VoiceFailure catch (failure) {
      await _endMirrorAfterFailure(failure);
    } on Object {
      await _endMirrorAfterFailure(null);
    }
  }

  Future<void> _cancelMirrorEnrollment() async {
    await _mirrorRecorder?.cancel();
    await _mirrorController?.end();
    _resetMirrorStatus();
  }

  Future<void> _playMirrorTarget() async {
    final controller = _mirrorController;
    final voice = _voice;
    final reference = _referenceSentence;
    final wordId = _wordId;
    if (controller == null || voice == null || reference == null) return;
    if (_mirrorStatus != VoiceMirrorStatus.ready) return;
    try {
      await voice.speak(
        VoiceRequest.create(
          text: reference,
          language: 'en',
          voiceId: 'mirror',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: wordId ?? 'shadowing:${reference.hashCode}',
          contentType: 'shadowing-mirror',
          capability: VoiceCapability.sessionVoiceMirror,
          privacyScope: VoicePrivacyScope.participantTransient,
        ),
      );
    } on VoiceFailure {
      // Mirror unavailable: standard voice remains usable.
      if (mounted) {
        setState(() => _mirrorError = 'เสียง AI ใช้ไม่ได้ในขณะนี้');
      }
    }
  }

  Future<void> _handleMirrorRecorderFailure(
    VoiceMirrorRecorderFailure failure,
  ) async {
    await _mirrorController?.end();
    await _mirrorRecorder?.cancel();
    final message = switch (failure.code) {
      VoiceMirrorRecorderFailureCode.permissionDenied =>
        'ไม่ได้รับสิทธิ์ใช้ไมโครโฟนสำหรับเสียง AI',
      VoiceMirrorRecorderFailureCode.permissionPermanentlyDenied =>
        'สิทธิ์ไมโครโฟนถูกปิดถาวร กรุณาเปิดจากการตั้งค่าระบบ',
      VoiceMirrorRecorderFailureCode.emptyRecording ||
      VoiceMirrorRecorderFailureCode.startFailed ||
      VoiceMirrorRecorderFailureCode.readFailed =>
        'ไม่สามารถบันทึกเสียงสำหรับเสียง AI ได้',
      VoiceMirrorRecorderFailureCode.tooLarge => 'ไฟล์เสียงใหญ่เกินกำหนด',
      _ => 'เสียง AI ใช้ไม่ได้ในขณะนี้',
    };
    if (mounted) {
      setState(() {
        _mirrorStatus = VoiceMirrorStatus.error;
        _mirrorError = message;
      });
    }
  }

  Future<void> _endMirrorAfterFailure(VoiceFailure? failure) async {
    await _mirrorController?.end();
    await _mirrorRecorder?.cancel();
    if (mounted) {
      setState(() {
        _mirrorStatus = VoiceMirrorStatus.error;
        _mirrorError = failure == null
            ? 'เสียง AI ใช้ไม่ได้ในขณะนี้'
            : _mirrorSafeMessage();
      });
    }
  }

  String _mirrorSafeMessage() => 'เสียง AI ใช้ไม่ได้ในขณะนี้';

  String get _mirrorStatusText => switch (_mirrorStatus) {
    VoiceMirrorStatus.idle => 'ยังไม่ได้เริ่ม',
    VoiceMirrorStatus.recording => 'กำลังอัดเสียง…',
    VoiceMirrorStatus.enrolling => 'กำลังสร้างเสียงต้นแบบ…',
    VoiceMirrorStatus.ready => 'พร้อมใช้งาน',
    VoiceMirrorStatus.error => 'เกิดข้อผิดพลาด',
  };
}
