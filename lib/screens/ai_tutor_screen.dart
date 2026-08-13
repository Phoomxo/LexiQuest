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
    _voice = widget.voice ?? dependencies?.voice;
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

  Future<void> _sendMessage([String? spokenText]) async {
    final tutor = _tutor;
    final text = (spokenText ?? _inputController.text).trim();
    if (text.isEmpty || _isGenerating) return;
    if (tutor == null) {
      setState(() => _error = 'AI Tutor is unavailable in this build.');
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
            sender: 'AI Tutor',
            text: reply.text,
            isUser: false,
            model: reply.model,
          ),
        );
      });
      unawaited(_speakAiResponse(reply.text));
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
            setState(() => _isListening = false);
            if (event.transcript.trim().isNotEmpty) {
              unawaited(_sendMessage(event.transcript));
            }
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
    } on Object {
      // The verified text reply remains usable when device TTS is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
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
        title: const Text('AI Tutor'),
        actions: [
          IconButton(
            tooltip: 'AI provider settings',
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
                decoration: const InputDecoration(
                  labelText: 'สถานการณ์สนทนา',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final scenario in _scenarios)
                    DropdownMenuItem(value: scenario, child: Text(scenario)),
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
                    ? 'Messages use the selected provider under saved consent.'
                    : 'Add a provider API key before starting.',
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
                          'ภาษาอังกฤษเพื่อเรียก AI provider ที่เลือกไว้',
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
                                      'ผู้ให้บริการ: ${message.model}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
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
                    tooltip: _isListening ? 'หยุดฟัง' : 'พูดภาษาอังกฤษ',
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
    AiFailureCode.missingKey => 'Add an API key in AI provider settings.',
    AiFailureCode.missingModel => 'Select an AI model before starting.',
    AiFailureCode.consentRequired =>
      'Provider consent is required before sending a message.',
    AiFailureCode.invalidKey => 'The provider rejected this API key.',
    AiFailureCode.requestRejected => 'The provider rejected this request.',
    AiFailureCode.quota => 'The provider quota is exhausted.',
    AiFailureCode.rateLimited => 'The provider rate limit was reached.',
    AiFailureCode.offline =>
      'The device is offline. Local learning still works.',
    AiFailureCode.timeout => 'The provider timed out. Try again.',
    AiFailureCode.providerUnavailable =>
      'The provider is temporarily unavailable. Local data is unaffected.',
    AiFailureCode.providerDisabled => 'The selected provider is disabled.',
    AiFailureCode.circuitOpen =>
      'The provider is temporarily paused after repeated failures.',
    AiFailureCode.localPersistence =>
      'Local AI accounting is temporarily unavailable.',
    AiFailureCode.malformedResponse =>
      'The provider returned an invalid reply.',
    AiFailureCode.blocked => 'The provider blocked this request.',
    AiFailureCode.cancelled => 'The AI request was cancelled.',
    AiFailureCode.validation => 'The message is invalid or too long.',
    AiFailureCode.secureStorage => 'Secure API-key storage is unavailable.',
    AiFailureCode.unsafeEndpoint => 'The custom provider endpoint is unsafe.',
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
