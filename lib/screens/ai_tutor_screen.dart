import 'dart:async';

import 'package:flutter/material.dart';

import '../config/m3_theme.dart';
import '../features/gemini/domain/gemini_contracts.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../runtime/app_dependencies.dart';
import '../navigation/app_routes.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_models.dart';
import '../widgets/adaptive_content_pane.dart';
import 'gemini_settings_screen.dart';
import 'choose_mode_screen.dart';
import 'quiz_screen.dart';
import 'device_permission_center_screen.dart';

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

final class TutorWordDraft {
  const TutorWordDraft({
    required this.controller,
    required this.ownerScope,
    required this.ownerEpoch,
    required this.text,
    this.wordId,
    this.spelling,
  });
  final GeminiTutorController controller;
  final GeminiScope ownerScope;
  final int ownerEpoch;
  final String text;
  final String? wordId;
  final String? spelling;
}

class AiTutorScreen extends StatefulWidget {
  const AiTutorScreen({
    super.key,
    this.voice,
    this.geminiTutor,
    this.speechPractice,
    this.wordDraft,
    this.learning,
  });

  final VoiceUseCases? voice;
  final GeminiTutorController? geminiTutor;
  final SpeechPracticeUseCases? speechPractice;
  final TutorWordDraft? wordDraft;
  final LearningUseCases? learning;

  @override
  State<AiTutorScreen> createState() => _AiTutorScreenState();
}

class _AiTutorScreenState extends State<AiTutorScreen>
    with WidgetsBindingObserver {
  static const _scenarios = [
    'สัมภาษณ์งาน',
    'เช็กอินที่สนามบิน',
    'สั่งอาหารที่คาเฟ่',
    'ประชุมวิชาการ',
    'เช็กอินโรงแรม',
  ];

  late final VoiceUseCases _voiceProvider;
  bool _ownsVoiceProvider = false;
  GeminiTutorController? _tutor;
  GeminiScope? _visibleScope;
  StreamSubscription<int>? _scopeSubscription;
  SpeechPracticeUseCases? _speech;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  GeminiCancellation? _generationCancellation;
  String _selectedScenario = _scenarios.first;
  GeminiTutorMode _selectedMode = GeminiTutorMode.guided;
  int _sendAttempts = 0;
  bool _sending = false;
  bool _canRetry = false;
  ChatMessage? _pendingMessage;
  bool _isGenerating = false;
  bool _isListening = false;
  bool _startingSpeech = false;
  bool _hasKey = false;
  bool _providerActive = false;
  bool _shareLearningSummary = false;
  String? _error;
  int _interactionEpoch = 0;
  bool _draftHandled = false;
  bool _draftPending = false;
  bool _wordDraftNotice = false;
  TutorWordDraft? _wordTarget;
  bool _openingTargetPractice = false;
  static const _draftUnavailable =
      'เตรียมคำถามไม่ได้ กรุณาพิมพ์ใหม่ในบัญชีปัจจุบัน หรือกลับไปฝึกคำศัพท์';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceProvider = widget.voice ?? VoiceUseCases.createDefault();
    _ownsVoiceProvider = widget.voice == null;
    _inputController.addListener(() => _draftPending = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTutor();
  }

  @override
  void didUpdateWidget(AiTutorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.geminiTutor, widget.geminiTutor)) _resolveTutor();
  }

  void _resolveTutor() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final resolvedTutor = widget.geminiTutor ?? dependencies?.geminiTutor;
    final draft = _draftHandled ? null : widget.wordDraft;
    _draftHandled = true;
    _speech ??= widget.speechPractice ?? dependencies?.speechPractice;
    if (!identical(resolvedTutor, _tutor)) {
      _interactionEpoch += 1;
      _generationCancellation?.cancel();
      _inputController.clear();
      _messages.clear();
      _draftPending = false;
      _wordDraftNotice = false;
      _wordTarget = null;
      _pendingMessage = null;
      _canRetry = false;
      _hasKey = false;
      _providerActive = false;
      _shareLearningSummary = false;
      if (_tutor != null) unawaited(_cancelAudioForLifecycle());
      unawaited(_scopeSubscription?.cancel());
      _tutor = resolvedTutor;
      _visibleScope = resolvedTutor?.scope;
      _scopeSubscription = resolvedTutor?.invalidations.listen(
        (_) => _onScopeInvalidated(),
      );
      _draftPending = draft != null;
      unawaited(_loadKeyStatus(draft: draft));
    } else if (draft != null) {
      _error = _draftUnavailable;
    }
  }

  Future<void> _loadKeyStatus({TutorWordDraft? draft}) async {
    final tutor = _tutor;
    if (tutor == null) return;
    final epoch = _interactionEpoch;
    final scopeEpoch = tutor.epoch;
    try {
      final status = await tutor.loadSettings();
      if (_current(epoch, scopeEpoch)) {
        setState(() {
          _hasKey = status.hasKey;
          _providerActive = status.providerConsent;
          _shareLearningSummary = status.shareLearningSummary;
          if (draft != null && _draftPending) {
            _draftPending = false;
            if (identical(tutor, draft.controller) &&
                tutor.scope == draft.ownerScope &&
                tutor.epoch == draft.ownerEpoch &&
                draft.text.trim().isNotEmpty &&
                draft.text.length <= 500 &&
                _inputController.text.isEmpty) {
              _inputController.text = draft.text;
              _wordDraftNotice = true;
              if (draft.wordId?.trim().isNotEmpty == true &&
                  draft.spelling?.trim().isNotEmpty == true) {
                _wordTarget = draft;
              }
            } else {
              _error = _draftUnavailable;
            }
          }
        });
      }
    } on GeminiException {
      if (_current(epoch, scopeEpoch)) {
        setState(() {
          _hasKey = false;
          _draftPending = false;
          if (draft != null) _error = _draftUnavailable;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final tutor = _tutor;
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    if (text.length > 500) {
      setState(
        () => _error = 'ข้อความต้องไม่เกิน 500 ตัวอักษร กรุณาแก้ไขก่อนส่ง',
      );
      return;
    }
    if (tutor == null) {
      setState(() => _error = 'ผู้ช่วยฝึกภาษายังไม่พร้อมใช้งาน');
      return;
    }
    if (_wordTarget != null && _shareLearningSummary) {
      setState(
        () => _error =
            'ปิดการแชร์สรุปผลเรียนในการตั้งค่าผู้ช่วย AI ก่อนส่งคำถามจากเนื้อหานี้',
      );
      return;
    }
    if (!_hasKey || !_providerActive || tutor.scope == null) {
      setState(
        () => _error = _geminiFailureText(
          !_hasKey
              ? GeminiFailureCode.missingKey
              : GeminiFailureCode.consentRequired,
        ),
      );
      return;
    }
    if (_sendAttempts >= 8) {
      setState(
        () => _error = 'ครบ 8 ครั้งในรอบนี้แล้ว เริ่มรอบใหม่เพื่อถามต่อ',
      );
      return;
    }
    final scenario = _selectedScenario;
    final mode = _selectedMode;
    final message = ChatMessage(sender: 'คุณ', text: text, isUser: true);
    final cancellation = GeminiCancellation();
    final epoch = ++_interactionEpoch;
    final scopeEpoch = tutor.epoch;
    _generationCancellation = cancellation;
    setState(() {
      _messages.add(message);
      _pendingMessage = message;
      _sending = true;
      _canRetry = false;
      _isListening = false;
      _startingSpeech = false;
      _isGenerating = true;
      _error = null;
    });
    _scrollToLatest();
    try {
      await _speech?.cancel();
      if (!_current(epoch, scopeEpoch)) return;
      // A screen-local attempt, not a provider receipt or a billing quota.
      setState(() => _sendAttempts += 1);
      final reply = await tutor.reply(
        scenario: scenario,
        learnerMessage: text,
        mode: mode,
        cancellation: cancellation,
      );
      if (!_current(epoch, scopeEpoch) || cancellation.isCancelled) return;
      setState(() {
        _pendingMessage = null;
        _inputController.clear();
        _messages.add(
          ChatMessage(
            sender: 'ผู้ช่วยฝึกภาษา',
            text: reply.text,
            isUser: false,
            model: reply.model,
          ),
        );
      });
      _scrollToLatest();
      if (_current(epoch, scopeEpoch)) unawaited(_speakAiResponse(reply.text));
    } on GeminiException catch (error) {
      if (_current(epoch, scopeEpoch)) {
        setState(() => _error = _geminiFailureText(error.code));
      }
    } on SpeechPracticeException catch (error) {
      if (_current(epoch, scopeEpoch)) {
        setState(() => _error = _speechFailureText(error.code));
      }
    } on Object {
      if (_current(epoch, scopeEpoch)) {
        setState(
          () => _error =
              'ระบบเสียงหรือผู้ช่วยฝึกภาษาไม่พร้อมใช้งาน ข้อมูลการเรียนในเครื่องยังใช้ได้',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          if (_current(epoch, scopeEpoch) &&
              identical(_pendingMessage, message)) {
            _messages.remove(message);
            _pendingMessage = null;
            _canRetry = true;
          }
        });
      }
      if (_current(epoch, scopeEpoch)) {
        setState(() => _isGenerating = false);
      }
      if (epoch == _interactionEpoch &&
          identical(_generationCancellation, cancellation)) {
        _generationCancellation = null;
      }
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _toggleMicListening() async {
    if (_startingSpeech || _sending) return;
    final epoch = _interactionEpoch;
    final scopeEpoch = _tutor?.epoch;
    final speech = _speech;
    if (_isListening) {
      await _cancelAudioForLifecycle();
      return;
    }
    if (speech == null) {
      setState(() => _error = 'ระบบรู้จำเสียงไม่พร้อมใช้งาน');
      return;
    }
    setState(() {
      _error = null;
      _startingSpeech = true;
    });
    try {
      await speech.start(
        locale: 'en-US',
        onEvent: (event) {
          if (!_current(epoch, scopeEpoch)) return;
          if (event.isFinal) {
            setState(() => _isListening = false);
            if (event.transcript.trim().isNotEmpty) {
              _inputController.text = event.transcript;
            }
          }
        },
        onFailure: (failure) {
          if (!_current(epoch, scopeEpoch)) return;
          setState(() {
            _isListening = false;
            _error = _speechFailureText(failure);
          });
        },
        onStatus: (status) {
          if (_current(epoch, scopeEpoch)) {
            setState(() => _isListening = status == 'listening');
          }
        },
      );
      if (_current(epoch, scopeEpoch)) {
        setState(() => _isListening = speech.isListening);
      }
    } on SpeechPracticeException catch (error) {
      if (_current(epoch, scopeEpoch)) {
        setState(() => _error = _speechFailureText(error.code));
      }
    } finally {
      if (_current(epoch, scopeEpoch)) setState(() => _startingSpeech = false);
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
    _draftPending = false;
    _interactionEpoch += 1;
    _generationCancellation?.cancel();
    _generationCancellation = null;
    if (mounted) {
      setState(() {
        if (_pendingMessage != null) {
          _messages.remove(_pendingMessage);
          _pendingMessage = null;
          _canRetry = true;
          _error = 'ยกเลิกคำขอแล้ว แก้ข้อความหรือลองส่งอีกครั้งได้';
        }
        _isListening = false;
        _startingSpeech = false;
        _isGenerating = false;
      });
    }
    await _stopAudio(reportFailure: true);
  }

  Future<void> _stopAudio({bool reportFailure = false}) async {
    final epoch = _interactionEpoch;
    final scopeEpoch = _tutor?.epoch;
    try {
      await Future.wait([
        if (_speech != null) _speech!.cancel(),
        _voiceProvider.stop(),
      ]);
    } on Object {
      if (reportFailure && _current(epoch, scopeEpoch)) {
        setState(() => _error = 'หยุดเสียงไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    }
  }

  bool _current(int epoch, int? scopeEpoch) =>
      mounted &&
      epoch == _interactionEpoch &&
      scopeEpoch == _tutor?.epoch &&
      _visibleScope == _tutor?.scope;

  void _onScopeInvalidated() {
    if (!mounted) return;
    _visibleScope = _tutor?.scope;
    unawaited(_cancelAudioForLifecycle());
    setState(() {
      _inputController.clear();
      _wordDraftNotice = false;
      _wordTarget = null;
      _messages.clear();
      _pendingMessage = null;
      _canRetry = false;
      _sendAttempts = 0;
      _hasKey = false;
      _providerActive = false;
      _shareLearningSummary = false;
      _error = widget.wordDraft == null ? null : _draftUnavailable;
    });
    unawaited(_loadKeyStatus());
  }

  Future<void> _openGeminiSettings() async {
    await _cancelAudioForLifecycle();
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

  void _startNewRound() {
    if (_sending || _startingSpeech || _isListening) return;
    _interactionEpoch += 1;
    _draftPending = false;
    unawaited(_stopAudio(reportFailure: true));
    setState(() {
      _messages.clear();
      _wordDraftNotice = false;
      _wordTarget = null;
      _inputController.clear();
      _pendingMessage = null;
      _sendAttempts = 0;
      _canRetry = false;
      _error = null;
    });
  }

  Future<void> _openPractice() async {
    await _cancelAudioForLifecycle();
    if (!mounted) return;
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/modes',
        builder: (_) => const ChooseModeScreen(),
      ),
    );
  }

  Future<void> _openTargetPractice() async {
    if (_openingTargetPractice) return;
    setState(() => _openingTargetPractice = true);
    try {
      await _openTargetPracticeOnce();
    } finally {
      if (mounted) setState(() => _openingTargetPractice = false);
    }
  }

  Future<void> _openTargetPracticeOnce() async {
    final target = _wordTarget;
    final tutor = _tutor;
    final learning =
        widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;
    if (target == null || tutor == null || learning == null) return;
    await _cancelAudioForLifecycle();
    if (!mounted ||
        !identical(_wordTarget, target) ||
        !identical(tutor, target.controller) ||
        tutor.scope != target.ownerScope ||
        tutor.epoch != target.ownerEpoch) {
      return;
    }
    try {
      final owner = await learning.owners.getOrCreateActiveOwner();
      final words = owner.id == target.ownerScope.ownerId
          ? await learning.repository.listQuizWords(
              ownerId: owner.id,
              wordIds: [target.wordId!],
              limit: 1,
            )
          : const [];
      if (!mounted ||
          !identical(_wordTarget, target) ||
          !identical(tutor, target.controller) ||
          tutor.scope != target.ownerScope ||
          tutor.epoch != target.ownerEpoch) {
        return;
      }
      if (words.length != 1 ||
          words.single.id != target.wordId ||
          words.single.spelling != target.spelling) {
        setState(() {
          _wordTarget = null;
          _wordDraftNotice = false;
          _error = 'คำศัพท์เปลี่ยนแล้ว กรุณากลับไปเลือกคำจากแหล่งเรียนอีกครั้ง';
        });
        return;
      }
    } on Object {
      if (mounted && identical(_wordTarget, target)) {
        setState(
          () => _error =
              'ตรวจสอบคำศัพท์ในเครื่องไม่สำเร็จ กรุณากลับไปเลือกคำอีกครั้ง',
        );
      }
      return;
    }
    await AppNavigator.pushPage<void>(
      context,
      AppPage<void>(
        name: 'learning/source-tutor-target',
        builder: (_) => QuizScreen(
          learning: learning,
          wordIds: [target.wordId!],
          selectionMode: QuizWordSelectionMode.sourcePractice,
        ),
      ),
    );
  }

  Future<void> _showTargetDataDisclosure() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('ข้อมูลที่ AI ใช้'),
      content: const Text(
        'เมื่อกดส่ง AI จะได้รับข้อความที่เห็นในช่องพิมพ์ สถานการณ์ และรูปแบบคำตอบเท่านั้น '
        'ชื่อไฟล์ ข้อความต้นฉบับ รหัสบัญชี รหัสคำศัพท์ และประวัติคำตอบไม่ได้ถูกส่ง',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ปิด'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _interactionEpoch += 1;
    _generationCancellation?.cancel();
    unawaited(_scopeSubscription?.cancel());
    unawaited(_stopAudio());
    _scrollController.dispose();
    _inputController.dispose();
    _voiceProvider.disposeIfOwned(_ownsVoiceProvider);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: M3Theme.appBarToolbarHeight(context),
        title: M3Theme.appBarTitle(context, 'ผู้ช่วย AI'),
        actions: [
          IconButton(
            tooltip: 'ตั้งค่าผู้ช่วย AI',
            onPressed: _openGeminiSettings,
            icon: const Icon(Icons.key_outlined),
          ),
        ],
      ),
      body: AdaptiveContentPane(
        maxWidth: AdaptiveContentPane.tutorMaxWidth,
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                if (_wordTarget != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Card(
                      key: const ValueKey('ai-tutor-word-target'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('คำที่กำลังฝึก: ${_wordTarget!.spelling}'),
                            const SizedBox(height: 4),
                            const Text(
                              'ไฟล์และข้อความต้นฉบับไม่ได้แนบ ตรวจแก้คำถามก่อนกดส่ง',
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                TextButton(
                                  key: const ValueKey(
                                    'ai-tutor-data-disclosure',
                                  ),
                                  onPressed: _showTargetDataDisclosure,
                                  child: const Text('ดูข้อมูลที่ AI ใช้'),
                                ),
                                FilledButton.tonal(
                                  key: const ValueKey(
                                    'ai-tutor-practice-target',
                                  ),
                                  onPressed: _openingTargetPractice
                                      ? null
                                      : _openTargetPractice,
                                  child: const Text('ฝึกคำนี้'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_wordDraftNotice && _wordTarget == null)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'ไฟล์และข้อความต้นฉบับไม่ได้แนบ ตรวจแก้คำถามก่อนกดส่ง',
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in GeminiTutorMode.values)
                        ChoiceChip(
                          label: Text(
                            mode == GeminiTutorMode.guided
                                ? 'คิดทีละขั้น'
                                : 'อธิบายให้เลย',
                          ),
                          selected: _selectedMode == mode,
                          onSelected: _sending
                              ? null
                              : (_) => setState(() => _selectedMode = mode),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedScenario,
                    decoration: const InputDecoration(
                      labelText: 'สถานการณ์สนทนา',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final scenario in _scenarios)
                        DropdownMenuItem(
                          value: scenario,
                          child: Text(
                            scenario,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _sending
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _selectedScenario = value);
                            }
                          },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    _hasKey
                        ? _providerActive
                              ? 'ระบบจะส่งข้อความเมื่อคุณกดส่ง ตามความยินยอมในรอบนี้'
                              : 'กรุณาเปิดการยินยอมสำหรับรอบนี้ในการตั้งค่า'
                        : 'ตั้งค่าผู้ช่วย AI ก่อนเริ่มใช้งาน',
                    key: const ValueKey<String>('ai-tutor-key-status'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'ลองส่งแล้ว $_sendAttempts/8 ครั้งในหน้านี้',
                        key: const ValueKey('ai-tutor-budget'),
                      ),
                      TextButton(
                        onPressed: _sending || _startingSpeech || _isListening
                            ? null
                            : _startNewRound,
                        child: const Text('เริ่มรอบใหม่'),
                      ),
                      TextButton(
                        onPressed: _openPractice,
                        child: const Text('กลับไปฝึกคำศัพท์'),
                      ),
                    ],
                  ),
                ),
                _messages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'ยังไม่มีบทสนทนา เลือกสถานการณ์แล้วพิมพ์หรือพูด'
                            'ภาษาอังกฤษเพื่อเริ่มฝึก',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
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
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
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
                                        'ตอบโดย Gemini',
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
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            key: const ValueKey<String>('ai-tutor-error'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        if (_error ==
                            _speechFailureText(
                              SpeechFailureCode.permissionPermanentlyDenied,
                            )) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => AppNavigator.pushPage<void>(
                              context,
                              AppPage<void>(
                                name: 'settings/device-permissions',
                                builder: (_) =>
                                    const DevicePermissionCenterScreen(),
                              ),
                            ),
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('เปิดศูนย์สิทธิ์อุปกรณ์'),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_isGenerating)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: LinearProgressIndicator(
                            semanticsLabel: 'กำลังรอคำตอบจากผู้ช่วย AI',
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              unawaited(_cancelAudioForLifecycle()),
                          child: const Text('ยกเลิก'),
                        ),
                      ],
                    ),
                  ),
                if (_canRetry)
                  TextButton(
                    onPressed: _sending ? null : _sendMessage,
                    child: const Text('ลองส่งอีกครั้ง'),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AdaptiveContentPane.tutorMaxWidth,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey<String>('ai-tutor-mic'),
                    tooltip: _isListening ? 'หยุดฟัง' : 'พูดภาษาอังกฤษ',
                    onPressed: _sending || _startingSpeech
                        ? null
                        : _toggleMicListening,
                    icon: Icon(_isListening ? Icons.stop : Icons.mic_none),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey<String>('ai-tutor-input'),
                      controller: _inputController,
                      enabled: !_sending,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'ข้อความถึง AI',
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
                    onPressed: _sending ? null : () => _sendMessage(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _geminiFailureText(GeminiFailureCode code) => switch (code) {
    GeminiFailureCode.missingKey =>
      'ยังไม่ได้ตั้งค่าผู้ช่วย AI กรุณาเปิดหน้าตั้งค่า',
    GeminiFailureCode.consentRequired =>
      'ยังไม่ได้ยินยอมใช้ผู้ช่วย AI กรุณาเปิดหน้าตั้งค่า',
    GeminiFailureCode.invalidKey =>
      'รหัสเชื่อมต่อผู้ช่วย AI ไม่ถูกต้องหรือถูกบล็อก',
    GeminiFailureCode.quota => 'สิทธิ์การใช้งานผู้ช่วย AI เต็มแล้ว',
    GeminiFailureCode.offline =>
      'อุปกรณ์ออฟไลน์ ข้อมูลการเรียนในเครื่องยังใช้ได้',
    GeminiFailureCode.timeout => 'ผู้ช่วย AI ตอบกลับช้าเกินกำหนด กรุณาลองใหม่',
    GeminiFailureCode.providerUnavailable =>
      'ผู้ช่วย AI ไม่พร้อมใช้งานชั่วคราว ข้อมูลในเครื่องไม่ได้รับผลกระทบ',
    GeminiFailureCode.malformedResponse => 'ผู้ช่วย AI ส่งคำตอบที่อ่านไม่ได้',
    GeminiFailureCode.blocked => 'คำขอถูกระบบความปลอดภัยปฏิเสธ',
    GeminiFailureCode.cancelled => 'ยกเลิกคำขอแล้ว',
    GeminiFailureCode.validation => 'ข้อความไม่ถูกต้องหรือยาวเกินกำหนด',
    GeminiFailureCode.secureStorage =>
      'ที่จัดเก็บรหัสเชื่อมต่อแบบปลอดภัยไม่พร้อมใช้งาน',
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
