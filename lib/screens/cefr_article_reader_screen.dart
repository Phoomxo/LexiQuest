import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../features/accessibility/domain/accessibility_policy.dart';
import '../features/accessibility/presentation/accessibility_scope.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/voice/presentation/route_voice_session_mixin.dart';
import '../runtime/app_dependencies.dart';
import '../voice/voice_models.dart';

class CefrArticleReaderScreen extends StatefulWidget {
  final String title;
  final String content;
  final String cefrLevel;
  final VoiceUseCases? voice;
  final LearningUseCases? learning;
  final String? ownerId;
  final String? sessionId;
  final String? wordId;
  final int attemptNumber;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final CefrReadingModeAdapter modeAdapter;

  const CefrArticleReaderScreen({
    super.key,
    required this.title,
    required this.content,
    required this.cefrLevel,
    this.voice,
    this.learning,
    this.ownerId,
    this.sessionId,
    this.wordId,
    this.attemptNumber = 1,
    this.evidenceAdapter,
    this.modeAdapter = const CefrReadingModeAdapter(),
  });

  @override
  State<CefrArticleReaderScreen> createState() =>
      _CefrArticleReaderScreenState();
}

class _CefrArticleReaderScreenState extends State<CefrArticleReaderScreen>
    with
        WidgetsBindingObserver,
        RouteVoiceSessionMixin<CefrArticleReaderScreen> {
  VoiceUseCases? _voice;
  String? _selectedWord;
  DateTime? _startedAtUtc;
  LearningUseCases? _learning;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  PendingCurrentActivityEvidence? _pendingEvidence;
  PendingLearningSessionClose? _pendingSessionClose;
  UnifiedLessonSessionLifecycle? _lifecycle;
  bool _completed = false;

  CefrReadingModeAdapter get _modeAdapter => widget.modeAdapter;
  bool get _acceptsModeOperations =>
      mounted && (_lifecycle?.acceptsOperations ?? true);
  bool get _sessionCloseRetryRequired =>
      (_pendingSessionClose?.requiresRetry ?? false) ||
      (_lifecycle?.sessionCompletionRetryRequired ?? false);

  @override
  void initState() {
    super.initState();
    _startedAtUtc = DateTime.now().toUtc();
  }

  @override
  VoiceUseCases? get routeVoiceUseCases => _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _voice = widget.voice ?? dependencies?.voice;
    _learning = widget.learning ?? dependencies?.learning;
    _evidenceAdapter =
        widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    _lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
    refreshRouteVoiceSession();
  }

  Future<void> _speakWord(String word) async {
    if (_pendingEvidence != null ||
        _pendingSessionClose != null ||
        !_acceptsModeOperations) {
      return;
    }
    setState(() {
      _selectedWord = word;
    });
    try {
      await routeVoiceSession?.speak(
        VoiceRequest.create(
          text: word,
          language: 'en',
          voiceId: 'teacher_female',
          speed: 1.0,
          mode: VoiceMode.practice,
          contentId: word,
          contentType: 'article_reader',
        ),
      );
    } catch (_) {}
  }

  Future<void> _completeReading() async {
    if (_completed ||
        _pendingEvidence != null ||
        _pendingSessionClose != null ||
        !_acceptsModeOperations) {
      return;
    }
    _modeAdapter.evaluate();
    final evidence = _evidenceAdapter;
    final sessionId = widget.sessionId;
    final wordId = widget.wordId;
    if (evidence == null || sessionId == null || wordId == null) {
      setState(() => _completed = true);
      return;
    }
    final pending = _pendingEvidence = _modeAdapter
        .capture(
          evidence: evidence,
          ownerId: widget.ownerId,
          sessionId: sessionId,
          wordId: wordId,
          responseTimeMs: DateTime.now()
              .toUtc()
              .difference(_startedAtUtc!)
              .inMilliseconds,
          attemptNumber: widget.attemptNumber,
        )
        .pending;
    setState(() {});
    try {
      await (_lifecycle?.runAcceptedOperation(pending.record) ??
          pending.record());
    } catch (_) {
      if (mounted) setState(() {});
      return;
    }
    _pendingEvidence = null;
    await _completeSessionIfOwned(sessionId);
  }

  Future<void> _completeSessionIfOwned(String sessionId) async {
    final learning = _learning;
    if (learning == null) {
      if (mounted) setState(() => _completed = true);
      return;
    }
    final close = _pendingSessionClose ??= learning.captureSessionClose(
      sessionId: sessionId,
      ownerId: widget.ownerId,
    );
    if (mounted) setState(() {});
    try {
      await (_lifecycle?.complete(close) ?? close.finish());
      _pendingSessionClose = null;
      if (mounted) setState(() => _completed = true);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _retryPersistence() async {
    if (!_acceptsModeOperations) return;
    final evidence = _pendingEvidence;
    if (evidence != null && evidence.requiresRetry) {
      try {
        await (_lifecycle?.runAcceptedOperation(evidence.retry) ??
            evidence.retry());
      } catch (_) {
        if (mounted) setState(() {});
        return;
      }
      _pendingEvidence = null;
      final sessionId = widget.sessionId;
      if (sessionId != null) await _completeSessionIfOwned(sessionId);
      return;
    }
    final close = _pendingSessionClose;
    if (close == null || !_sessionCloseRetryRequired) return;
    try {
      await (_lifecycle?.complete(close) ?? close.retry());
      _pendingSessionClose = null;
      if (mounted) setState(() => _completed = true);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.content.split(RegExp(r'\s+'));

    return PopScope(
      canPop: _pendingEvidence == null && _pendingSessionClose == null,
      child: AccessibilityModeScaffold(
        appBar: AppBar(
          title: Text(
            'บทความ CEFR (${widget.cefrLevel})',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.indigo,
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AccessibilitySemanticRegion(
                role: AccessibilitySemanticRole.prompt,
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'แตะที่คำศัพท์เพื่อฟังเสียงอ่าน AI:',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 8,
                      children: words.map((w) {
                        final cleanWord = w.replaceAll(
                          RegExp(r'[^a-zA-Z]'),
                          '',
                        );
                        final isSelected =
                            _selectedWord == cleanWord && cleanWord.isNotEmpty;
                        final tile = Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.amber.shade200
                                : Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            w,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: Colors.black87,
                            ),
                          ),
                        );
                        if (cleanWord.isEmpty) return tile;
                        final canReplay =
                            _pendingEvidence == null &&
                            _pendingSessionClose == null &&
                            _acceptsModeOperations;
                        void replay() => unawaited(_speakWord(cleanWord));

                        return FocusableActionDetector(
                          enabled: canReplay,
                          shortcuts: const <ShortcutActivator, Intent>{
                            SingleActivator(LogicalKeyboardKey.enter):
                                ActivateIntent(),
                            SingleActivator(LogicalKeyboardKey.space):
                                ActivateIntent(),
                          },
                          actions: <Type, Action<Intent>>{
                            ActivateIntent: CallbackAction<ActivateIntent>(
                              onInvoke: (_) {
                                replay();
                                return null;
                              },
                            ),
                          },
                          child: Semantics(
                            button: true,
                            enabled: canReplay,
                            label: 'Replay $cleanWord',
                            onTap: canReplay ? replay : null,
                            child: GestureDetector(
                              excludeFromSemantics: true,
                              onTap: canReplay ? replay : null,
                              child: tile,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              if (_selectedWord != null && _selectedWord!.isNotEmpty) ...[
                const Divider(height: 30),
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'คำศัพท์ที่เลือก: "$_selectedWord"',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Replay selected word',
                        icon: const Icon(
                          Icons.volume_up,
                          color: Colors.indigo,
                          size: 30,
                        ),
                        onPressed: () => _speakWord(_selectedWord!),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              AccessibilitySemanticRegion(
                role: AccessibilitySemanticRole.responseAndInput,
                child: FilledButton.icon(
                  key: const ValueKey<String>('cefr-reading-complete'),
                  onPressed:
                      _completed ||
                          _pendingEvidence != null ||
                          _pendingSessionClose != null
                      ? null
                      : _completeReading,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(_completed ? 'อ่านจบแล้ว' : 'อ่านบทความจบแล้ว'),
                ),
              ),
              if ((_pendingEvidence?.requiresRetry ?? false) ||
                  _sessionCloseRetryRequired)
                AccessibilitySemanticRegion(
                  role: AccessibilitySemanticRole.responseAndInput,
                  child: TextButton(
                    onPressed: _retryPersistence,
                    child: const Text('ลองบันทึกผลอีกครั้ง'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
