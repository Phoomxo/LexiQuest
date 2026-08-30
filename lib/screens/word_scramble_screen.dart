import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/accessibility/domain/accessibility_policy.dart';
import '../features/accessibility/presentation/accessibility_scope.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../runtime/app_dependencies.dart';

List<String> createStableScramble(String word) {
  final letters = word.characters.toList();
  if (letters.length < 2) return letters;
  var shift =
      word.runes.fold<int>(0, (sum, rune) => sum + rune) % letters.length;
  if (shift == 0) shift = 1;
  final result = <String>[...letters.skip(shift), ...letters.take(shift)];
  if (result.join() == word) {
    final different = result.indexWhere((letter) => letter != result.first);
    if (different > 0) {
      final first = result.first;
      result[0] = result[different];
      result[different] = first;
    }
  }
  return result;
}

class WordScrambleScreen extends StatefulWidget {
  final String word;
  final String? ownerId;
  final String? sessionId;
  final String? wordId;
  final int attemptNumber;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;
  final WordScrambleModeAdapter modeAdapter;

  const WordScrambleScreen({
    super.key,
    required this.word,
    this.ownerId,
    this.sessionId,
    this.wordId,
    this.attemptNumber = 1,
    this.evidenceAdapter,
    this.modeAdapter = const WordScrambleModeAdapter(),
  });

  @override
  State<WordScrambleScreen> createState() => _WordScrambleScreenState();
}

class _WordScrambleScreenState extends State<WordScrambleScreen> {
  List<String> scrambledLetters = [];
  List<String?> userAnswer = [];
  List<int> usedIndexes = [];
  bool _isComplete = false;
  bool? _committedEvaluation;
  DateTime? _startedAtUtc;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  LearningUseCases? _learning;
  PendingCurrentActivityEvidence? _pendingEvidence;
  PendingLearningSessionClose? _pendingSessionClose;
  UnifiedLessonSessionLifecycle? _lifecycle;
  bool _pendingWasCorrect = false;
  bool _sessionCompleted = false;
  late int _nextAttemptNumber;

  WordScrambleModeAdapter get _modeAdapter => widget.modeAdapter;
  bool get _acceptsModeOperations =>
      mounted && (_lifecycle?.acceptsOperations ?? true);
  bool get _persistenceLocked =>
      _pendingEvidence != null || _pendingSessionClose != null;
  bool get _interactionLocked => _persistenceLocked || _sessionCompleted;

  @override
  void initState() {
    super.initState();
    _scrambleWord();
    _startedAtUtc = DateTime.now().toUtc();
    _nextAttemptNumber = widget.attemptNumber;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    _learning = dependencies?.learning;
    _evidenceAdapter =
        widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    _lifecycle = UnifiedLessonSessionLifecycleScope.maybeOf(context);
  }

  void _scrambleWord() {
    scrambledLetters = createStableScramble(widget.word);
    userAnswer = List.filled(scrambledLetters.length, null);
    usedIndexes.clear();
  }

  Future<void> _checkAnswer() async {
    if (_interactionLocked || !_acceptsModeOperations) return;
    final response = userAnswer.join();
    final evaluation = _modeAdapter.evaluate(
      target: widget.word,
      response: response,
    );
    final evidence = _evidenceAdapter;
    final sessionId = widget.sessionId;
    final wordId = widget.wordId;
    if (evidence == null || sessionId == null || wordId == null) {
      _publishEvaluation(evaluation.isCorrect);
      return;
    }
    final pending = _pendingEvidence = _modeAdapter
        .capture(
          evidence: evidence,
          ownerId: widget.ownerId,
          sessionId: sessionId,
          wordId: wordId,
          target: widget.word,
          response: response,
          responseTimeMs: DateTime.now()
              .toUtc()
              .difference(_startedAtUtc!)
              .inMilliseconds,
          attemptNumber: _nextAttemptNumber,
        )
        .pending;
    _pendingWasCorrect = evaluation.isCorrect;
    setState(() {});
    try {
      await (_lifecycle?.runAcceptedOperation(pending.record) ??
          pending.record());
      if (identical(_pendingEvidence, pending)) {
        await _afterEvidenceCommitted(_pendingWasCorrect);
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _resetGame() {
    if (_interactionLocked || !_acceptsModeOperations) return;
    setState(() {
      _isComplete = false;
      _committedEvaluation = null;
      _scrambleWord();
    });
  }

  void _selectLetter(int letterIndex) {
    if (_interactionLocked ||
        !_acceptsModeOperations ||
        usedIndexes.contains(letterIndex)) {
      return;
    }
    final slotIndex = userAnswer.indexWhere((letter) => letter == null);
    if (slotIndex < 0) return;
    setState(() {
      userAnswer[slotIndex] = scrambledLetters[letterIndex];
      usedIndexes.add(letterIndex);
    });
  }

  Future<void> _retryEvidence() async {
    final pending = _pendingEvidence;
    if (pending == null || !pending.requiresRetry || !_acceptsModeOperations) {
      return;
    }
    try {
      await (_lifecycle?.runAcceptedOperation(pending.retry) ??
          pending.retry());
      if (identical(_pendingEvidence, pending)) {
        await _afterEvidenceCommitted(_pendingWasCorrect);
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _afterEvidenceCommitted(bool shouldComplete) async {
    _pendingEvidence = null;
    _publishEvaluation(shouldComplete);
    final lifecycle = _lifecycle;
    final learning = _learning;
    final sessionId = widget.sessionId;
    if (!shouldComplete ||
        lifecycle == null ||
        learning == null ||
        sessionId == null) {
      if (!shouldComplete) _nextAttemptNumber += 1;
      if (mounted) setState(() {});
      return;
    }
    final close = _pendingSessionClose ??= learning.captureSessionClose(
      sessionId: sessionId,
      ownerId: widget.ownerId,
    );
    if (mounted) setState(() {});
    try {
      await _lifecycle!.complete(close);
      _pendingSessionClose = null;
      _sessionCompleted = true;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _publishEvaluation(bool isCorrect) {
    if (!mounted) return;
    setState(() {
      _committedEvaluation = isCorrect;
      if (isCorrect) _isComplete = true;
    });
    if (isCorrect) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ถูกต้อง')));
    }
  }

  Future<void> _retrySessionClose() async {
    final close = _pendingSessionClose;
    if (close == null || !close.requiresRetry || !_acceptsModeOperations) {
      return;
    }
    try {
      await _lifecycle!.complete(close);
      _pendingSessionClose = null;
      _sessionCompleted = true;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AccessibilityScope.of(context).reducedMotion;
    return PopScope(
      canPop: !_persistenceLocked,
      child: AccessibilityModeScaffold(
        appBar: AppBar(title: const Text('เกมเรียงตัวอักษร')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AccessibilitySemanticRegion(
                    role: AccessibilitySemanticRole.prompt,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: List.generate(scrambledLetters.length, (index) {
                        return DragTarget<int>(
                          onWillAcceptWithDetails: (details) =>
                              !_interactionLocked && userAnswer[index] == null,
                          onAcceptWithDetails: (details) {
                            if (_interactionLocked || !_acceptsModeOperations) {
                              return;
                            }
                            setState(() {
                              userAnswer[index] =
                                  scrambledLetters[details.data];
                              usedIndexes.add(details.data);
                            });
                          },
                          builder: (context, candidateData, rejectedData) {
                            return AnimatedContainer(
                              duration: reducedMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 300),
                              margin: const EdgeInsets.all(5),
                              constraints: const BoxConstraints(
                                minWidth: 56,
                                minHeight: 56,
                              ),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: userAnswer[index] != null
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                userAnswer[index] ?? "",
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AccessibilitySemanticRegion(
                    role: AccessibilitySemanticRole.responseAndInput,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: List.generate(scrambledLetters.length, (
                            index,
                          ) {
                            final canSelect =
                                !_interactionLocked &&
                                !usedIndexes.contains(index);
                            void select() => _selectLetter(index);
                            return Visibility(
                              visible: !usedIndexes.contains(index),
                              child: FocusableActionDetector(
                                enabled: canSelect,
                                shortcuts: const <ShortcutActivator, Intent>{
                                  SingleActivator(LogicalKeyboardKey.enter):
                                      ActivateIntent(),
                                  SingleActivator(LogicalKeyboardKey.space):
                                      ActivateIntent(),
                                },
                                actions: <Type, Action<Intent>>{
                                  ActivateIntent:
                                      CallbackAction<ActivateIntent>(
                                        onInvoke: (_) {
                                          select();
                                          return null;
                                        },
                                      ),
                                },
                                child: Semantics(
                                  button: true,
                                  enabled: canSelect,
                                  label:
                                      'Select letter '
                                      '${scrambledLetters[index]}',
                                  onTap: canSelect ? select : null,
                                  child: GestureDetector(
                                    onTap: canSelect ? select : null,
                                    child: Draggable<int>(
                                      data: index,
                                      feedback: Material(
                                        child: _buildLetterTile(
                                          scrambledLetters[index],
                                          isDragging: true,
                                        ),
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.0,
                                        child: _buildLetterTile(
                                          scrambledLetters[index],
                                        ),
                                      ),
                                      child: _buildLetterTile(
                                        scrambledLetters[index],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _isComplete || _interactionLocked
                              ? null
                              : _checkAnswer,
                          child: const Text('ตรวจสอบคำตอบ'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: _interactionLocked ? null : _resetGame,
                          child: const Text('เริ่มใหม่'),
                        ),
                        if (_pendingEvidence?.requiresRetry ?? false)
                          TextButton(
                            onPressed: _retryEvidence,
                            child: const Text('ลองบันทึกผลอีกครั้ง'),
                          ),
                        if (_pendingSessionClose?.requiresRetry ?? false)
                          TextButton(
                            onPressed: _retrySessionClose,
                            child: const Text('ลองปิดเซสชันอีกครั้ง'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_committedEvaluation != null) ...[
                    AccessibilitySemanticRegion(
                      role: AccessibilitySemanticRole.feedback,
                      child: Card(
                        key: ValueKey<String>(
                          _committedEvaluation!
                              ? 'word-scramble-complete'
                              : 'word-scramble-incorrect',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _committedEvaluation!
                                ? 'เรียงคำศัพท์สำเร็จ'
                                : 'ยังไม่ถูก ลองอีกครั้ง',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLetterTile(String letter, {bool isDragging = false}) {
    return Container(
      constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      padding: const EdgeInsets.all(4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDragging
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Text(
        letter,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    );
  }
}
