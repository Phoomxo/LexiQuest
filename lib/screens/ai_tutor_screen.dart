import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

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
  List<TutorContextTurn> _completedTurns = [];
  String _sessionId = const Uuid().v4();
  String? _contextScopeId;
  String _cefrLevel = 'A1';
  TutorIntent _intent = TutorIntent.conversation;
  static const _intentLabels = {
    TutorIntent.conversation: 'สนทนา',
    TutorIntent.explanation: 'อธิบาย',
    TutorIntent.practice: 'แบบฝึกหัด',
  };
  AiCancellation? _generationCancellation;
  Future<void>? _resetSpeechCancellation;
  String _selectedScenario = _scenarios.first;
  bool _isGenerating = false;
  bool _isListening = false;
  bool _hasKey = false;
  String? _error;
  int _interactionEpoch = 0;
  int _voiceAttemptEpoch = 0;
  int _speechAttemptEpoch = 0;

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
      _resetConversation();
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
    _speechAttemptEpoch++;
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
    _speechAttemptEpoch++;
    _isListening = false;
    final speechSession = _speechSession;
    _speechSession = null;
    await speechSession?.release();
  }

  @override
  void onVoiceRouteResumed() {
    _ensureSpeechSession();
    unawaited(_loadKeyStatus());
  }

  void _resetConversation() {
    final cancellation = _retireSpeechAttempt();
    _resetSpeechCancellation = cancellation;
    cancellation.ignore();
    _interactionEpoch++;
    _generationCancellation?.cancel();
    _generationCancellation = null;
    _isGenerating = false;
    _sessionId = const Uuid().v4();
    _completedTurns = [];
    _messages.clear();
    _inputController.clear();
    _error = null;
  }

  Future<void> _retireSpeechAttempt() {
    // Invalidate callbacks synchronously, before native cancellation completes.
    _speechAttemptEpoch++;
    _isListening = false;
    return _speechSession?.cancel() ?? Future<void>.value();
  }

  void _applyStatus(AiTutorSettingsStatus status) {
    if (_contextScopeId != status.contextScopeId) _resetConversation();
    _contextScopeId = status.contextScopeId;
    _hasKey = status.hasKey;
  }

  Future<void> _loadKeyStatus() async {
    final tutor = _tutor;
    final epoch = _interactionEpoch;
    if (tutor == null) return;
    try {
      final status = await tutor.loadSettings();
      if (mounted && epoch == _interactionEpoch && identical(tutor, _tutor)) {
        setState(() => _applyStatus(status));
      }
    } on AiTutorException {
      if (mounted && epoch == _interactionEpoch && identical(tutor, _tutor)) {
        setState(() => _hasKey = false);
      }
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
    // Re-read the local owner/credential fence before attaching any history.
    final preparationEpoch = _interactionEpoch;
    setState(() => _isGenerating = true);
    try {
      final status = await tutor.loadSettings();
      if (!mounted ||
          preparationEpoch != _interactionEpoch ||
          !identical(tutor, _tutor)) {
        return;
      }
      if (status.contextScopeId != _contextScopeId) {
        setState(() => _applyStatus(status));
        return;
      }
      setState(() => _applyStatus(status));
    } on AiTutorException catch (error) {
      if (mounted && preparationEpoch == _interactionEpoch) {
        setState(() {
          _isGenerating = false;
          _error = _aiFailureText(error.code);
        });
      }
      return;
    }
    final requestContext = TutorRequestContext(
      sessionId: _sessionId,
      scopeId: _contextScopeId,
      cefrLevel: _cefrLevel,
      intent: _intent,
      priorTurns: _completedTurns,
    );
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
        context: requestContext,
        cancellation: cancellation,
      );
      if (!mounted || epoch != _interactionEpoch || cancellation.isCancelled) {
        return;
      }
      final status = await tutor.loadSettings();
      if (!mounted || epoch != _interactionEpoch || cancellation.isCancelled) {
        return;
      }
      if (status.contextScopeId != requestContext.scopeId) {
        setState(() => _applyStatus(status));
        return;
      }
      setState(() {
        _completedTurns = TutorRequestContext(
          sessionId: _sessionId,
          priorTurns: [
            ..._completedTurns,
            TutorContextTurn(role: TutorTurnRole.learner, text: text),
            TutorContextTurn(role: TutorTurnRole.tutor, text: reply.text),
          ],
        ).priorTurns;
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
      final cancellation = _retireSpeechAttempt();
      final attempt = _speechAttemptEpoch;
      setState(() {});
      try {
        await cancellation;
      } on Object {
        if (mounted && attempt == _speechAttemptEpoch) {
          setState(() => _error = 'หยุดไมโครโฟนไม่สำเร็จ กรุณาลองอีกครั้ง');
        }
      }
      return;
    }
    if (speech == null) {
      setState(() => _error = 'ระบบรู้จำเสียงไม่พร้อมใช้งาน');
      return;
    }
    final attempt = ++_speechAttemptEpoch;
    final conversation = _sessionId;
    bool isCurrent() =>
        mounted &&
        attempt == _speechAttemptEpoch &&
        conversation == _sessionId &&
        identical(speech, _speechSession) &&
        speech.isCurrent;
    setState(() => _error = null);
    try {
      await speech.start(
        locale: 'en-US',
        onEvent: (event) {
          if (!isCurrent()) return;
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
          if (!isCurrent()) return;
          setState(() {
            _isListening = false;
            _error = _speechFailureText(failure);
          });
        },
        onStatus: (status) {
          if (isCurrent()) setState(() => _isListening = status == 'listening');
        },
      );
      if (isCurrent()) setState(() => _isListening = speech.isListening);
    } on SpeechPracticeException catch (error) {
      if (isCurrent()) setState(() => _error = _speechFailureText(error.code));
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
    final cancellation = _retireSpeechAttempt();
    if (mounted) setState(() {});
    try {
      await cancellation;
    } on Object {
      // Best-effort microphone cleanup cannot block route voice cleanup.
    }
  }

  Future<void> _finishConversationAudioReset() async {
    _voiceAttemptEpoch++;
    try {
      // Reset already retired speech. Await that same native cleanup instead
      // of enqueueing another cancel while the first one is still pending.
      await _resetSpeechCancellation;
    } on Object {
      // A failed microphone cleanup must not prevent stopping reply playback.
    }
    try {
      await routeVoiceSession?.stop();
    } on Object {
      // The route remains usable after resume; cleanup failures are bounded.
    }
  }

  Future<void> _openAiSettings() async {
    setState(_resetConversation);
    _interactionEpoch += 1;
    _generationCancellation?.cancel();
    _generationCancellation = null;
    await _finishConversationAudioReset();
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
            tooltip: 'เริ่มบทสนทนาใหม่',
            onPressed: () {
              setState(_resetConversation);
              _finishConversationAudioReset().ignore();
            },
            icon: const Icon(Icons.add_comment_outlined),
          ),
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
            Expanded(
              child: ListView(
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
                                setState(() {
                                  _resetConversation();
                                  _selectedScenario = value;
                                });
                              }
                            },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 12,
                      children: [
                        DropdownButton<String>(
                          key: const ValueKey('ai-tutor-level'),
                          value: _cefrLevel,
                          hint: const Text('ระดับฝึก'),
                          items: [
                            for (final level in TutorRequestContext.levels)
                              DropdownMenuItem(
                                value: level,
                                child: Text(level),
                              ),
                          ],
                          onChanged: _isGenerating
                              ? null
                              : (level) {
                                  if (level != null) {
                                    setState(() {
                                      _resetConversation();
                                      _cefrLevel = level;
                                    });
                                  }
                                },
                        ),
                        DropdownButton<TutorIntent>(
                          key: const ValueKey('ai-tutor-intent'),
                          value: _intent,
                          items: [
                            for (final intent in TutorIntent.values)
                              DropdownMenuItem(
                                value: intent,
                                child: Text(_intentLabels[intent]!),
                              ),
                          ],
                          onChanged: _isGenerating
                              ? null
                              : (intent) {
                                  if (intent != null) {
                                    setState(() {
                                      _resetConversation();
                                      _intent = intent;
                                    });
                                  }
                                },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      _hasKey
                          ? 'ตรวจข้อความก่อนกดส่ง ข้อความจะส่งไปยังผู้ให้บริการตามความยินยอมที่บันทึกไว้ และอาจมีค่าใช้จ่าย'
                          : 'ตั้งค่าบัญชีและรหัสเชื่อมต่อของผู้ให้บริการ AI ก่อนเริ่ม',
                      key: const ValueKey<String>('ai-tutor-key-status'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _messages.isEmpty
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
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              for (final message in _messages)
                                Align(
                                  alignment: message.isUser
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Card(
                                    color: message.isUser
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            message.sender,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          SelectableText(message.text),
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
                                                      _speakAiResponse(
                                                        message.text,
                                                      ),
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
                                ),
                            ],
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
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
