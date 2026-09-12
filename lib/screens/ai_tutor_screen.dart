import 'dart:async';

import 'package:flutter/material.dart';

import '../features/ai_tutor/domain/ai_tutor_contracts.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import '../navigation/app_routes.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../voice/voice_models.dart';
import 'ai_tutor_settings_screen.dart';

final class ChatMessage {
  const ChatMessage({
    required this.sender,
    required this.text,
    required this.isUser,
    this.model,
  });

  final String sender;
  final String text;
  final bool isUser;
  final String? model;
}

class AiTutorScreen extends StatefulWidget {
  const AiTutorScreen({
    super.key,
    this.voice,
    this.aiTutor,
    this.speechPractice,
    this.featureRegistry,
  });

  final VoiceUseCases? voice;
  final AiTutorController? aiTutor;
  final SpeechPracticeUseCases? speechPractice;
  final FeatureRegistry? featureRegistry;

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen>
    with WidgetsBindingObserver, RouteVoiceSessionMixin<AiTutorScreen> {
  static const _scenarios = [
    'Job Interview',
    'Airport Check-in',
    'Cafe Ordering',
    'Academic Conference',
    'Hotel Check-in',
  ];
  static const _scenarioLabels = {
    'Job Interview': 'สัมภาษณ์งาน',
    'Airport Check-in': 'เช็กอินที่สนามบิน',
    'Cafe Ordering': 'สั่งอาหารในคาเฟ่',
    'Academic Conference': 'ประชุมวิชาการ',
    'Hotel Check-in': 'เช็กอินโรงแรม',
  };

  VoiceUseCases? _voice;
  AiTutorController? _tutor;
  SpeechPracticeUseCases? _speech;
  SpeechPracticeSession? _speechSession;
  final TextEditingController _inputController = TextEditingController();
  final List<ChatMessage> _messages = [];
  AiCancellation? _generationCancellation;
  String _selectedScenario = _scenarios.first;
  bool _isGenerating = false;
  bool _isListening = false;
  bool _hasKey = false;
  String? _error;
  int _interactionEpoch = 0;
  int _voiceAttemptEpoch = 0;

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindResolvedDependencies();
  }

  @override
  void didUpdateWidget(covariant AiTutorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.voice, oldWidget.voice) ||
        !identical(widget.aiTutor, oldWidget.aiTutor) ||
        !identical(widget.speechPractice, oldWidget.speechPractice)) {
      _bindResolvedDependencies();
    }
  }

  void _bindResolvedDependencies() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final resolvedVoice = widget.voice ?? dependencies?.voice;
    if (!identical(_voice, resolvedVoice)) _voiceAttemptEpoch++;
    _voice = resolvedVoice;
    refreshRouteVoiceSession();
    final resolvedTutor = widget.aiTutor ?? dependencies?.aiTutor;
    _bindSpeechPractice(widget.speechPractice ?? dependencies?.speechPractice);
    if (!identical(resolvedTutor, _tutor)) {
      _tutor = resolvedTutor;
      unawaited(_loadKeyStatus());
    }
  }

  void _bindSpeechPractice(SpeechPracticeUseCases? resolved) {
    if (identical(resolved, _speech)) {
      _ensureSpeechSession();
      return;
    }
    final previous = _speechSession;
    _speechSession = null;
    _speech = resolved;
    _isListening = false;
    previous?.release().ignore();
    _ensureSpeechSession();
  }

  void _ensureSpeechSession() {
    if (!(ModalRoute.isCurrentOf(context) ?? true)) return;
    final speech = _speech;
    if (speech != null && _speechSession?.isCurrent != true) {
      _speechSession = speech.acquireSession();
    }
  }

  @override
  Future<void> onVoiceRouteCovered() async {
    _voiceAttemptEpoch++;
    final speechSession = _speechSession;
    _speechSession = null;
    await speechSession?.release();
  }

  @override
  void onVoiceRouteResumed() => _ensureSpeechSession();

  Future<void> _loadKeyStatus() async {
    final tutor = _tutor;
    if (tutor == null) return;
    try {
      final status = await tutor.loadSettings();
      if (mounted) setState(() => _hasKey = status.hasKey);
    } on AiTutorException {
      if (mounted) setState(() => _hasKey = false);
    }
  }

  Future<void> _sendMessage() async {
    final tutor = _tutor;
    final text = _inputController.text.trim();
    if (text.isEmpty || _isGenerating) return;
    if (tutor == null) {
      setState(() => _error = 'ผู้ช่วยฝึกภาษา AI ยังไม่พร้อมใช้งานในรุ่นนี้');
      return;
    }
    final cancellation = AiCancellation();
    final epoch = ++_interactionEpoch;
    _generationCancellation = cancellation;
    setState(() {
      _messages.add(ChatMessage(sender: 'คุณ', text: text, isUser: true));
      _inputController.clear();
      _isListening = false;
      _isGenerating = true;
      _error = null;
    });
    try {
      final reply = await tutor.reply(
        scenario: _selectedScenario,
        learnerMessage: text,
        cancellation: cancellation,
      );
      if (!mounted || epoch != _interactionEpoch) return;
      setState(() {
        _messages.add(
          ChatMessage(
            sender: 'ผู้ช่วย AI',
            text: reply.text,
            isUser: false,
            model: reply.model,
          ),
        );
      });
    } on AiTutorException catch (error) {
      if (mounted && epoch == _interactionEpoch) {
        setState(() => _error = _aiFailureText(error.code));
      }
    } finally {
      if (mounted && epoch == _interactionEpoch) {
        setState(() => _isGenerating = false);
      }
      if (epoch == _interactionEpoch &&
          identical(_generationCancellation, cancellation)) {
        _generationCancellation = null;
      }
    }
  }

  Future<void> _toggleMicListening() async {
    _ensureSpeechSession();
    final speech = _speechSession;
    if (_isListening) {
      await speech?.cancel();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    if (speech == null) {
      setState(() => _error = 'ระบบรู้จำเสียงไม่พร้อมใช้งาน');
      return;
    }
    setState(() => _error = null);
    try {
      await speech.start(
        locale: 'en-US',
        onEvent: (event) {
          if (!mounted) return;
          if (event.isFinal) {
            setState(() {
              _isListening = false;
              if (event.transcript.trim().isNotEmpty) {
                _inputController.text = event.transcript;
                _inputController.selection = TextSelection.collapsed(
                  offset: _inputController.text.length,
                );
              }
            });
          }
        },
        onFailure: (failure) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _error = _speechFailureText(failure);
          });
        },
        onStatus: (status) {
          if (mounted) setState(() => _isListening = status == 'listening');
        },
      );
      if (mounted) setState(() => _isListening = speech.isListening);
    } on SpeechPracticeException catch (error) {
      if (mounted) setState(() => _error = _speechFailureText(error.code));
    }
  }

  Future<void> _speakAiResponse(String text) async {
    final epoch = ++_voiceAttemptEpoch;
    try {
      await routeVoiceSession?.speak(
        VoiceRequest.create(
          text: text,
          language: 'en',
          voiceId: 'device-default',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: 'ai-tutor-response',
          contentType: 'ai_tutor',
        ),
      );
    } on Object catch (error) {
      _reportVoiceFailure(
        error,
        epoch,
        'อ่านเสียงไม่สำเร็จ คุณยังอ่านคำตอบบนหน้าจอได้',
      );
    }
  }

  Future<void> _stopReply() async {
    final epoch = ++_voiceAttemptEpoch;
    try {
      await routeVoiceSession?.stop();
    } on Object catch (error) {
      _reportVoiceFailure(
        error,
        epoch,
        'หยุดอ่านเสียงไม่สำเร็จ กรุณาลองอีกครั้ง',
      );
    }
  }

  void _reportVoiceFailure(Object error, int epoch, String message) {
    if (!mounted ||
        epoch != _voiceAttemptEpoch ||
        (error is VoiceFailure &&
            error.category == VoiceFailureCategory.cancelled)) {
      return;
    }
    setState(() => _error = message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _voiceAttemptEpoch++;
      _cancelGenerationForLifecycle();
      _cancelSpeechForLifecycle().ignore();
    }
  }

  void _cancelGenerationForLifecycle() {
    _interactionEpoch += 1;
    _generationCancellation?.cancel();
    _generationCancellation = null;
    if (mounted && _isGenerating) {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _cancelSpeechForLifecycle() async {
    try {
      await _speechSession?.cancel();
    } on Object {
      // Best-effort microphone cleanup cannot block route voice cleanup.
    }
    if (mounted && _isListening) setState(() => _isListening = false);
  }

  Future<void> _cancelAudioForLifecycle() async {
    _voiceAttemptEpoch++;
    await _cancelSpeechForLifecycle();
    try {
      await routeVoiceSession?.stop();
    } on Object {
      // The route remains usable after resume; cleanup failures are bounded.
    }
  }

  Future<void> _openAiSettings() async {
    _interactionEpoch += 1;
    _generationCancellation?.cancel();
    _generationCancellation = null;
    await _cancelAudioForLifecycle();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _isGenerating = false;
    });
    final featureRegistry =
        widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.features;
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'ai-tutor/settings',
        builder: (_) => ProductionFeatureGate(
          feature: Feature.aiTutor,
          registry: featureRegistry,
          builder: (_) => AiTutorSettingsScreen(aiTutor: _tutor),
        ),
      ),
    );
    await _loadKeyStatus();
  }

  @override
  void dispose() {
    _voiceAttemptEpoch++;
    _interactionEpoch += 1;
    _generationCancellation?.cancel();
    _speechSession?.release().ignore();
    _speechSession = null;
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ฝึกสนทนากับ AI'),
        actions: [
          IconButton(
            tooltip: 'ตั้งค่าผู้ให้บริการ AI',
            onPressed: _openAiSettings,
            icon: const Icon(Icons.key_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedScenario,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'สถานการณ์สนทนา',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final scenario in _scenarios)
                    DropdownMenuItem(
                      value: scenario,
                      child: Text(_scenarioLabels[scenario]!),
                    ),
                ],
                onChanged: _isGenerating
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedScenario = value);
                        }
                      },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _hasKey
                    ? 'ตรวจข้อความก่อนกดส่ง ข้อความจะส่งไปยังผู้ให้บริการตามความยินยอมที่บันทึกไว้ และอาจมีค่าใช้จ่าย'
                    : 'ตั้งค่าบัญชีและรหัสเชื่อมต่อของผู้ให้บริการ AI ก่อนเริ่ม',
                key: const ValueKey<String>('ai-tutor-key-status'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'ยังไม่มีบทสนทนา เลือกสถานการณ์แล้วพิมพ์หรือพูด'
                          'ภาษาอังกฤษ ตรวจข้อความแล้วกดส่งเมื่อพร้อม',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        return Align(
                          alignment: message.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Card(
                            color: message.isUser
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.sender,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(message.text),
                                  if (message.model != null)
                                    Text(
                                      'รุ่น AI: ${message.model}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  if (!message.isUser && _voice != null)
                                    Wrap(
                                      children: [
                                        IconButton(
                                          tooltip: 'ฟังคำตอบ',
                                          onPressed: () =>
                                              _speakAiResponse(message.text),
                                          icon: const Icon(
                                            Icons.volume_up_outlined,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'หยุดอ่าน',
                                          onPressed: _stopReply,
                                          icon: const Icon(
                                            Icons.stop_circle_outlined,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  _error!,
                  key: const ValueKey<String>('ai-tutor-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_isGenerating)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(child: LinearProgressIndicator()),
                    TextButton(
                      onPressed: () => _generationCancellation?.cancel(),
                      child: const Text('ยกเลิก'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey<String>('ai-tutor-mic'),
                    tooltip: _isListening ? 'หยุดฟัง' : 'พูดเพื่อกรอกข้อความ',
                    onPressed: _isGenerating ? null : _toggleMicListening,
                    icon: Icon(_isListening ? Icons.stop : Icons.mic_none),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('ai-tutor-input'),
                      controller: _inputController,
                      enabled: !_isGenerating,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'พิมพ์ภาษาอังกฤษ...',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey<String>('ai-tutor-send'),
                    tooltip: 'ส่ง',
                    onPressed: _isGenerating ? null : () => _sendMessage(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _aiFailureText(AiFailureCode code) => switch (code) {
    AiFailureCode.missingKey => 'เพิ่มรหัสเชื่อมต่อในการตั้งค่าผู้ให้บริการ AI',
    AiFailureCode.missingModel => 'เลือกรุ่น AI ในการตั้งค่าก่อนเริ่ม',
    AiFailureCode.consentRequired =>
      'กรุณาบันทึกความยินยอมในการตั้งค่าก่อนส่งข้อความ',
    AiFailureCode.invalidKey =>
      'ผู้ให้บริการไม่ยอมรับรหัสเชื่อมต่อ กรุณาตรวจในการตั้งค่า',
    AiFailureCode.requestRejected =>
      'ผู้ให้บริการไม่ยอมรับคำขอนี้ กรุณาตรวจรุ่น AI หรือแก้ข้อความ',
    AiFailureCode.quota => 'โควตาผู้ให้บริการหมด กรุณาตรวจบัญชีของคุณ',
    AiFailureCode.rateLimited => 'ส่งคำขอถี่เกินไป กรุณารอสักครู่แล้วลองใหม่',
    AiFailureCode.offline =>
      'ไม่มีอินเทอร์เน็ต คุณยังเรียนด้วยข้อมูลในเครื่องได้',
    AiFailureCode.timeout => 'ผู้ให้บริการตอบไม่ทันเวลา กรุณาลองใหม่',
    AiFailureCode.providerUnavailable =>
      'ผู้ให้บริการไม่พร้อมชั่วคราว ข้อมูลในเครื่องยังอยู่',
    AiFailureCode.providerDisabled =>
      'ผู้ให้บริการที่เลือกถูกปิดใช้งาน กรุณาตรวจการตั้งค่า',
    AiFailureCode.circuitOpen =>
      'พักการเชื่อมต่อชั่วคราวหลังเกิดข้อผิดพลาดหลายครั้ง กรุณาลองภายหลัง',
    AiFailureCode.localPersistence =>
      'บันทึกสถิติ AI ในเครื่องไม่ได้ชั่วคราว กรุณาลองภายหลัง',
    AiFailureCode.malformedResponse =>
      'คำตอบจากผู้ให้บริการอ่านไม่ได้ กรุณาลองใหม่',
    AiFailureCode.blocked => 'ผู้ให้บริการปฏิเสธข้อความนี้ กรุณาปรับข้อความ',
    AiFailureCode.cancelled => 'ยกเลิกคำขอ AI แล้ว',
    AiFailureCode.validation =>
      'ข้อความไม่ถูกต้องหรือยาวเกินไป กรุณาแก้ข้อความ',
    AiFailureCode.secureStorage =>
      'เข้าถึงที่เก็บรหัสเชื่อมต่ออย่างปลอดภัยไม่ได้ กรุณาลองภายหลัง',
    AiFailureCode.unsafeEndpoint =>
      'ปลายทางที่กำหนดเองไม่ปลอดภัย กรุณาตรวจการตั้งค่า',
  };

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
