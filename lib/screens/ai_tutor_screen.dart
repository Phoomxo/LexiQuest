import 'dart:async';

import 'package:flutter/material.dart';

import '../features/gemini/domain/gemini_contracts.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../navigation/app_routes.dart';
import '../voice/voice_models.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';
import 'gemini_settings_screen.dart';

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
    this.voiceProvider,
    this.geminiTutor,
    this.speechPractice,
  });

  final VoiceProvider? voiceProvider;
  final GeminiTutorController? geminiTutor;
  final SpeechPracticeUseCases? speechPractice;

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen>
    with WidgetsBindingObserver {
  static const _scenarios = [
    'Job Interview',
    'Airport Check-in',
    'Cafe Ordering',
    'Academic Conference',
    'Hotel Check-in',
  ];

  late final VoiceProvider _voiceProvider;
  bool _ownsVoiceProvider = false;
  GeminiTutorController? _tutor;
  SpeechPracticeUseCases? _speech;
  final TextEditingController _inputController = TextEditingController();
  final List<ChatMessage> _messages = [];
  GeminiCancellation? _generationCancellation;
  String _selectedScenario = _scenarios.first;
  bool _isGenerating = false;
  bool _isListening = false;
  bool _hasKey = false;
  String? _error;
  int _interactionEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceProvider = widget.voiceProvider ?? VoiceServiceFactory.create();
    _ownsVoiceProvider = widget.voiceProvider == null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final resolvedTutor = widget.geminiTutor ?? dependencies?.geminiTutor;
    _speech ??= widget.speechPractice ?? dependencies?.speechPractice;
    if (!identical(resolvedTutor, _tutor)) {
      _tutor = resolvedTutor;
      unawaited(_loadKeyStatus());
    }
  }

  Future<void> _loadKeyStatus() async {
    final tutor = _tutor;
    if (tutor == null) return;
    try {
      final status = await tutor.loadSettings();
      if (mounted) setState(() => _hasKey = status.hasKey);
    } on GeminiException {
      if (mounted) setState(() => _hasKey = false);
    }
  }

  Future<void> _sendMessage([String? spokenText]) async {
    final tutor = _tutor;
    final text = (spokenText ?? _inputController.text).trim();
    if (text.isEmpty || _isGenerating) return;
    if (tutor == null) {
      setState(() => _error = 'ระบบ Gemini ยังไม่พร้อมใช้งาน');
      return;
    }
    final cancellation = GeminiCancellation();
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
    } on GeminiException catch (error) {
      if (mounted && epoch == _interactionEpoch) {
        setState(() => _error = _geminiFailureText(error.code));
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
    final speech = _speech;
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
      await _voiceProvider.speak(
        VoiceRequest.create(
          text: text,
          language: 'en',
          voiceId: 'device-default',
          speed: 1,
          mode: VoiceMode.practice,
          contentId: 'gemini-tutor-response',
          contentType: 'ai_tutor',
        ),
      );
    } on Object {
      // The verified text reply remains usable when device TTS is unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_cancelAudioForLifecycle());
    }
  }

  Future<void> _cancelAudioForLifecycle() async {
    await _speech?.cancel();
    await _voiceProvider.stop();
    if (mounted && _isListening) setState(() => _isListening = false);
  }

  Future<void> _openGeminiSettings() async {
    _interactionEpoch += 1;
    _generationCancellation?.cancel();
    _generationCancellation = null;
    await _speech?.cancel();
    await _voiceProvider.stop();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _isGenerating = false;
    });
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'gemini/settings',
        builder: (_) => GeminiSettingsScreen(geminiTutor: _tutor),
      ),
    );
    await _loadKeyStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _interactionEpoch += 1;
    _generationCancellation?.cancel();
    unawaited(_speech?.cancel());
    unawaited(_voiceProvider.stop());
    _inputController.dispose();
    if (_ownsVoiceProvider && _voiceProvider is ManagedVoiceService) {
      _voiceProvider.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Tutor'),
        actions: [
          IconButton(
            tooltip: 'ตั้งค่า Gemini',
            onPressed: _openGeminiSettings,
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
                    ? 'ข้อความจะส่งไป Gemini ตามการยินยอมที่บันทึกไว้'
                    : 'เพิ่ม Gemini API key ก่อนเริ่มใช้งาน',
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
                          'ภาษาอังกฤษเพื่อเรียก Gemini จริง',
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

  String _geminiFailureText(GeminiFailureCode code) => switch (code) {
    GeminiFailureCode.missingKey =>
      'ยังไม่มี Gemini API key กรุณาเปิดหน้าตั้งค่า',
    GeminiFailureCode.consentRequired =>
      'ยังไม่ได้ยินยอมส่งข้อความไป Gemini กรุณาเปิดหน้าตั้งค่า',
    GeminiFailureCode.invalidKey => 'Gemini API key ไม่ถูกต้องหรือถูกบล็อก',
    GeminiFailureCode.quota => 'โควตาหรือเพดานใช้งาน Gemini เต็มแล้ว',
    GeminiFailureCode.offline =>
      'อุปกรณ์ออฟไลน์ ข้อมูลการเรียนในเครื่องยังใช้ได้',
    GeminiFailureCode.timeout => 'Gemini ตอบกลับช้าเกินกำหนด กรุณาลองใหม่',
    GeminiFailureCode.providerUnavailable =>
      'Gemini ไม่พร้อมใช้งานชั่วคราว ข้อมูลในเครื่องไม่ได้รับผลกระทบ',
    GeminiFailureCode.malformedResponse => 'Gemini ส่งคำตอบที่อ่านไม่ได้',
    GeminiFailureCode.blocked => 'คำขอถูกระบบความปลอดภัยของ Gemini ปฏิเสธ',
    GeminiFailureCode.cancelled => 'ยกเลิกคำขอ Gemini แล้ว',
    GeminiFailureCode.validation => 'ข้อความไม่ถูกต้องหรือยาวเกินกำหนด',
    GeminiFailureCode.secureStorage =>
      'ที่จัดเก็บ key แบบปลอดภัยไม่พร้อมใช้งาน',
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
