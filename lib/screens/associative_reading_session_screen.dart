import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../runtime/app_dependencies.dart';

/// Six-stage Associative Reading Loop screen.
///
/// Stages:
///   1 Supported Reading  — read passage with target-word hints
///   2 Cue Fading         — re-read without translations
///   3 Active Recall      — type each target word from memory; answer recorded
///                          through the current-activity evidence adapter
///   4 Memory Association — enter a personal keyword/story for each word;
///                          saved via [AssociativeLearningPort]
///   5 Context Transfer   — write a new sentence using a target word
///   6 Finish             — summarise and complete
class AssociativeReadingSessionScreen extends StatefulWidget {
  const AssociativeReadingSessionScreen({
    super.key,
    required this.cefrLevel,
    required this.targetWords,
    required this.passageText,
    this.documentId,
    this.documentRevision = 1,
    this.learning,
    this.associativeLearning,
    this.targetWordIds,
    this.sessionId,
    this.evidenceAdapter,
  });

  final String cefrLevel;

  /// Display names of the target vocabulary words (e.g. 'banana').
  final List<String> targetWords;
  final String passageText;
  final String? documentId;
  final int documentRevision;
  final LearningUseCases? learning;

  /// Port for saving memory associations (Stage 4).
  /// Null is rendered as a typed unavailable state.
  final AssociativeLearningPort? associativeLearning;

  /// Map from word display name → Drift vocabulary word ID.
  /// A canonical session requires one nonblank unique ID per target word.
  final Map<String, String>? targetWordIds;

  /// Learning session ID for recording answers in Stage 3.
  /// Created externally (e.g. by [LearningUseCases.startQuiz]) before
  /// navigating to this screen.
  final String? sessionId;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;

  @override
  State<AssociativeReadingSessionScreen> createState() =>
      _AssociativeReadingSessionScreenState();
}

enum AssociativeReadingUnavailableReason {
  learning,
  currentActivityEvidence,
  associativeLearning,
}

class AssociativeReadingUnavailable extends StatelessWidget {
  const AssociativeReadingUnavailable({super.key, required this.reason});

  final AssociativeReadingUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Associative Reading')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Associative reading is unavailable on this installation.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _AssociativeReadingSessionScreenState
    extends State<AssociativeReadingSessionScreen>
    with WidgetsBindingObserver {
  static const _stageTitles = <String>[
    'Stage 1: Supported Reading',
    'Stage 2: Cue Fading',
    'Stage 3: Active Recall',
    'Stage 4: Memory Association',
    'Stage 5: Context Transfer',
    'Stage 6: Finish',
  ];

  LearningUseCases? _learning;
  AssociativeLearningPort? _associativeLearning;
  AssociativeReadingUnavailableReason? _unavailableReason;
  bool _initialized = false;

  int _currentStage = 1;
  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  PendingLearningSessionClose? _pendingSessionClose;
  PendingReadingProgress? _pendingCompletionProgress;
  PendingReadingProgress? _pendingCheckpointProgress;
  int? _pendingCheckpointPosition;
  bool _pendingCheckpointAdvancesStage = false;
  _PendingAssociationBatch? _pendingAssociationBatch;

  bool get _completionLocked =>
      _pendingSessionClose != null || _pendingCompletionProgress != null;
  bool get _checkpointLocked => _pendingCheckpointProgress != null;
  bool get _associationLocked => _pendingAssociationBatch != null;
  bool get _recallEvidenceLocked => _pendingRecallEvidence.any(
    (pending) => pending != null && !pending.isCommitted,
  );
  bool get _persistenceLocked =>
      _saving ||
      _completionLocked ||
      _checkpointLocked ||
      _associationLocked ||
      _recallEvidenceLocked;
  bool get _actionLocked =>
      _saving ||
      _completionLocked ||
      _checkpointLocked ||
      _associationLocked ||
      _completed;

  // Stage 3 — per-word recall controllers and results.
  late List<TextEditingController> _recallControllers;
  late List<bool?> _recallResults; // null=unanswered, true=correct, false=wrong
  late List<PendingCurrentActivityEvidence?> _pendingRecallEvidence;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  bool _recallBatchFrozen = false;
  bool _recallMappingInvalid = false;

  // Stage 4 — per-word association cue controllers.
  late List<TextEditingController> _cueControllers;

  String get _documentId {
    final supplied = widget.documentId?.trim();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    var hash = 2166136261;
    for (final unit in '${widget.cefrLevel}:${widget.passageText}'.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
    }
    return 'reading:$hash';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recallControllers = List.generate(
      widget.targetWords.length,
      (_) => TextEditingController(),
    );
    _recallResults = List.filled(widget.targetWords.length, null);
    _pendingRecallEvidence = List<PendingCurrentActivityEvidence?>.filled(
      widget.targetWords.length,
      null,
    );
    _cueControllers = List.generate(
      widget.targetWords.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final dependencies = AppDependenciesScope.maybeOf(context);
    _learning = widget.learning ?? dependencies?.learning;
    _associativeLearning =
        widget.associativeLearning ?? dependencies?.associativeLearning;
    final learning = _learning;
    if (learning == null) {
      _unavailableReason = AssociativeReadingUnavailableReason.learning;
      _loading = false;
      return;
    }
    _evidenceAdapter =
        widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    if (_evidenceAdapter == null) {
      _unavailableReason =
          AssociativeReadingUnavailableReason.currentActivityEvidence;
      _loading = false;
      return;
    }
    if (_associativeLearning == null) {
      _unavailableReason =
          AssociativeReadingUnavailableReason.associativeLearning;
      _loading = false;
      return;
    }
    learning
        .loadReadingProgress(
          documentId: _documentId,
          documentRevision: widget.documentRevision,
        )
        .then((progress) {
          if (!mounted) return;
          setState(() {
            _currentStage = (progress?.lastPosition ?? 1).clamp(1, 6);
            _completed = progress?.isCompleted ?? false;
            _loading = false;
          });
        })
        .catchError((Object _) {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_unavailableReason != null || _persistenceLocked || _completed) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(
        _checkpoint(
          isCompleted: false,
          showFailure: false,
          advancesStage: false,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _recallControllers) {
      c.dispose();
    }
    for (final c in _cueControllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _nextStage() async {
    if (_actionLocked) return;
    setState(() => _saving = true);

    // Stage-specific side effects before advancing.
    if (_currentStage == 3) {
      _recallMappingInvalid = false;
      final answersSaved = await _submitRecallAnswers();
      if (!mounted) return;
      if (!answersSaved) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _recallMappingInvalid
                  ? 'Active recall word mapping is invalid. '
                        'Restart this reading activity.'
                  : 'Could not save recall evidence. Try again.',
            ),
          ),
        );
        return;
      }
    } else if (_currentStage == 4) {
      final associationsSaved = await _saveAssociations();
      if (!mounted) return;
      if (!associationsSaved) {
        setState(() => _saving = false);
        return;
      }
    }

    if (_currentStage == 6) {
      await _finishCompletion();
      return;
    }

    await _advanceToStage(_currentStage + 1);
  }

  Future<void> _advanceToStage(int nextStage) async {
    final saved = await _checkpoint(
      position: nextStage,
      isCompleted: false,
      showFailure: true,
      advancesStage: true,
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    setState(() {
      _currentStage = nextStage;
      _saving = false;
    });
  }

  Future<void> _retryAssociationBatch() async {
    final pending = _pendingAssociationBatch;
    if (_saving || _completed || pending == null || !pending.requiresRetry) {
      return;
    }
    setState(() => _saving = true);
    final saved = await _saveAssociations();
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    await _advanceToStage(_currentStage + 1);
  }

  Future<void> _finishCompletion() async {
    final sessionId = widget.sessionId;
    if (sessionId != null) {
      final close = _pendingSessionClose ??= _learning!.captureSessionClose(
        sessionId: sessionId,
      );
      try {
        await close.finish();
        _pendingSessionClose = null;
      } catch (_) {
        _showCompletionFailure(
          'Could not finish the learning session. Try again.',
        );
        return;
      }
    }
    await _saveCompletionProgress();
  }

  Future<void> _retrySessionClose() async {
    final close = _pendingSessionClose;
    if (_saving || _completed || close == null || !close.requiresRetry) return;
    setState(() => _saving = true);
    try {
      await close.retry();
      _pendingSessionClose = null;
      await _saveCompletionProgress();
    } catch (_) {
      _showCompletionFailure(
        'Could not finish the learning session. Try again.',
      );
    }
  }

  Future<void> _saveCompletionProgress() async {
    final progress = _pendingCompletionProgress ??= _learning!
        .captureReadingProgress(
          documentId: _documentId,
          documentRevision: widget.documentRevision,
          position: 6,
          isCompleted: true,
        );
    try {
      await progress.save();
      _pendingCompletionProgress = null;
      await _completeAndPop();
    } catch (_) {
      _showCompletionFailure('บันทึกตำแหน่งอ่านไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
  }

  Future<void> _retryCompletionProgress() async {
    final progress = _pendingCompletionProgress;
    if (_saving || _completed || progress == null || !progress.requiresRetry) {
      return;
    }
    setState(() => _saving = true);
    try {
      await progress.retry();
      _pendingCompletionProgress = null;
      await _completeAndPop();
    } catch (_) {
      _showCompletionFailure('บันทึกตำแหน่งอ่านไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
  }

  Future<void> _completeAndPop() async {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _completed = true;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _showCompletionFailure(String message) {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Stage 3: Active Recall ─────────────────────────────────────────────────

  Future<bool> _submitRecallAnswers() async {
    final sessionId = widget.sessionId;
    final wordIds = widget.targetWordIds;
    if (_learning == null || sessionId == null) return true;

    if (!_recallBatchFrozen) {
      final validatedWordIds = _validateRecallWordIds(wordIds);
      if (validatedWordIds == null) {
        _recallMappingInvalid = true;
        return false;
      }
      _freezeRecallBatch(sessionId: sessionId, wordIds: validatedWordIds);
    }

    var allSaved = true;
    for (final pending in _pendingRecallEvidence) {
      if (pending == null || pending.isCommitted) continue;
      try {
        if (pending.requiresRetry) {
          await pending.retry();
        } else {
          await pending.record();
        }
      } catch (_) {
        allSaved = false;
      }
    }
    return allSaved;
  }

  /// Reads every controller and creates every pending command before the
  /// first provider resolution or local write begins.
  void _freezeRecallBatch({
    required String sessionId,
    required List<String> wordIds,
  }) {
    final pending = <PendingCurrentActivityEvidence?>[];
    final results = <bool?>[];
    for (var i = 0; i < widget.targetWords.length; i++) {
      final word = widget.targetWords[i];
      final wordId = wordIds[i];
      final typed = _recallControllers[i].text.trim().toLowerCase();
      final isCorrect = typed == word.trim().toLowerCase();
      results.add(isCorrect);
      pending.add(
        _evidenceAdapter!.capture(
          input: CurrentActivityInput.associativeRecall,
          sessionId: sessionId,
          wordId: wordId,
          isCorrect: isCorrect,
          responseTimeMs: null,
          attemptNumber: i + 1,
        ),
      );
    }
    _pendingRecallEvidence = List.unmodifiable(pending);
    _recallResults = List.unmodifiable(results);
    _recallBatchFrozen = true;
  }

  List<String>? _validateRecallWordIds(Map<String, String>? wordIds) {
    if (wordIds == null) return null;
    final validated = <String>[];
    final seen = <String>{};
    for (final word in widget.targetWords) {
      if (!wordIds.containsKey(word)) return null;
      final wordId = wordIds[word]!.trim();
      if (wordId.isEmpty || !seen.add(wordId)) return null;
      validated.add(wordId);
    }
    return List<String>.unmodifiable(validated);
  }

  // ── Stage 4: Memory Association ────────────────────────────────────────────

  Future<bool> _saveAssociations() async {
    final learning = _learning;
    final associativeLearning = _associativeLearning;
    if (learning == null || associativeLearning == null) return false;
    final draft = _pendingAssociationBatch == null
        ? _captureAssociationDraft()
        : null;

    try {
      var pending = _pendingAssociationBatch;
      if (pending == null) {
        pending = await _bindAssociationBatch(
          learning: learning,
          associativeLearning: associativeLearning,
          draft: draft!,
        );
        if (pending == null) return false;
        _pendingAssociationBatch = pending;
        if (mounted) setState(() {});
      }
      if (pending.requiresRetry) {
        await pending.retry();
      } else {
        await pending.save();
      }
      if (identical(_pendingAssociationBatch, pending)) {
        _pendingAssociationBatch = null;
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the memory association. Try again.'),
          ),
        );
      }
      return false;
    }
  }

  _AssociationBatchDraft _captureAssociationDraft() {
    final targetWords = List<String>.of(widget.targetWords);
    final targetWordIds = widget.targetWordIds == null
        ? null
        : Map<String, String>.of(widget.targetWordIds!);
    if (_cueControllers.length != targetWords.length) {
      throw StateError('association controller count does not match targets');
    }
    return _AssociationBatchDraft(
      capturedAtUtc: DateTime.now().toUtc(),
      entries: List<_AssociationDraftEntry>.generate(targetWords.length, (
        index,
      ) {
        final displayWord = targetWords[index];
        return _AssociationDraftEntry(
          ordinal: index,
          wordKey: targetWordIds?[displayWord] ?? displayWord,
          cue: _cueControllers[index].text.trim(),
        );
      }),
    );
  }

  Future<_PendingAssociationBatch?> _bindAssociationBatch({
    required LearningUseCases learning,
    required AssociativeLearningPort associativeLearning,
    required _AssociationBatchDraft draft,
  }) async {
    final ownerId = (await learning.owners.getOrCreateActiveOwner()).id;
    final writes = <_AssociationWrite>[];
    for (final entry in draft.entries) {
      if (entry.cue.isEmpty) {
        final existing = await associativeLearning.getMemoryState(
          ownerId,
          entry.wordKey,
        );
        final associations = await associativeLearning.getAssociationsForWord(
          ownerId,
          entry.wordKey,
        );
        if (associations.isEmpty || existing == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Create a memory cue for every target word before continuing.',
                ),
              ),
            );
          }
          return null;
        }
        continue;
      }
      writes.add(
        _AssociationWrite(
          association: AssociationRecord(
            associationId:
                'assoc:${entry.wordKey}:'
                '${draft.capturedAtUtc.millisecondsSinceEpoch}:'
                '${entry.ordinal}',
            ownerId: ownerId,
            wordKey: entry.wordKey,
            type: 'keyword',
            content: entry.cue,
            createdAtUtc: draft.capturedAtUtc,
          ),
          initialState: AssociativeMemoryState(
            ownerId: ownerId,
            wordKey: entry.wordKey,
            stability: 1,
            difficulty: 5,
            cueDependency: 1,
            lapseCount: 0,
            lastReviewedAtUtc: draft.capturedAtUtc,
            nextDueAtUtc: draft.capturedAtUtc.add(const Duration(days: 1)),
            algorithmVersion: 'associative-v1',
          ),
        ),
      );
    }
    return _PendingAssociationBatch(associativeLearning, writes: writes);
  }

  // ── Checkpoint ─────────────────────────────────────────────────────────────

  Future<bool> _checkpoint({
    int? position,
    required bool isCompleted,
    required bool showFailure,
    required bool advancesStage,
  }) async {
    final learning = _learning;
    if (learning == null) return true;
    if (_pendingCheckpointProgress != null) return false;
    final checkpointPosition = position ?? _currentStage;
    final pending = learning.captureReadingProgress(
      documentId: _documentId,
      documentRevision: widget.documentRevision,
      position: checkpointPosition,
      isCompleted: isCompleted,
    );
    _pendingCheckpointProgress = pending;
    _pendingCheckpointPosition = checkpointPosition;
    _pendingCheckpointAdvancesStage = advancesStage;
    if (mounted) setState(() {});
    try {
      await pending.save();
      if (identical(_pendingCheckpointProgress, pending)) {
        if (mounted) {
          setState(_clearPendingCheckpoint);
        } else {
          _clearPendingCheckpoint();
        }
      }
      return true;
    } catch (_) {
      if (mounted) {
        setState(() {});
        if (showFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกตำแหน่งอ่านไม่สำเร็จ กรุณาลองอีกครั้ง'),
            ),
          );
        }
      }
      return false;
    }
  }

  Future<void> _retryCheckpoint() async {
    final pending = _pendingCheckpointProgress;
    if (_saving || _completed || pending == null || !pending.requiresRetry) {
      return;
    }
    final checkpointPosition = _pendingCheckpointPosition;
    final advancesStage = _pendingCheckpointAdvancesStage;
    setState(() => _saving = true);
    try {
      await pending.retry();
      if (!mounted) return;
      setState(() {
        if (identical(_pendingCheckpointProgress, pending)) {
          _clearPendingCheckpoint();
        }
        if (advancesStage && checkpointPosition != null) {
          _currentStage = checkpointPosition;
        }
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกตำแหน่งอ่านไม่สำเร็จ กรุณาลองอีกครั้ง'),
        ),
      );
    }
  }

  void _clearPendingCheckpoint() {
    _pendingCheckpointProgress = null;
    _pendingCheckpointPosition = null;
    _pendingCheckpointAdvancesStage = false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final unavailableReason = _unavailableReason;
    if (unavailableReason != null) {
      return AssociativeReadingUnavailable(reason: unavailableReason);
    }
    final recallRetry = _pendingRecallEvidence.any(
      (pending) => pending?.requiresRetry ?? false,
    );
    final closeRetry = _pendingSessionClose?.requiresRetry ?? false;
    final progressRetry = _pendingCompletionProgress?.requiresRetry ?? false;
    final checkpointRetry = _pendingCheckpointProgress?.requiresRetry ?? false;
    final associationRetry = _pendingAssociationBatch?.requiresRetry ?? false;
    return PopScope(
      canPop: !_persistenceLocked,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Associative Reading (${widget.cefrLevel})'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: _currentStage / 6),
                    const SizedBox(height: 12),
                    Text(
                      _stageTitles[_currentStage - 1],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(child: _buildStageContent()),
                    ),
                    if (_saving) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: closeRetry
                          ? const ValueKey<String>(
                              'current-session-close-retry',
                            )
                          : progressRetry
                          ? const ValueKey<String>(
                              'current-reading-progress-retry',
                            )
                          : checkpointRetry
                          ? const ValueKey<String>(
                              'current-reading-checkpoint-retry',
                            )
                          : associationRetry
                          ? const ValueKey<String>('current-association-retry')
                          : recallRetry
                          ? const ValueKey<String>('current-evidence-retry')
                          : null,
                      onPressed: _saving || _completed
                          ? null
                          : closeRetry
                          ? _retrySessionClose
                          : progressRetry
                          ? _retryCompletionProgress
                          : checkpointRetry
                          ? _retryCheckpoint
                          : associationRetry
                          ? _retryAssociationBatch
                          : _completionLocked
                          ? null
                          : _checkpointLocked
                          ? null
                          : _associationLocked
                          ? null
                          : _nextStage,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(
                        closeRetry
                            ? 'Retry Session Completion'
                            : progressRetry
                            ? 'Retry Reading Completion'
                            : checkpointRetry
                            ? 'Retry Reading Checkpoint'
                            : associationRetry
                            ? 'Retry Memory Associations'
                            : recallRetry
                            ? 'Retry Evidence'
                            : _currentStage < 6
                            ? 'Complete & Continue'
                            : 'Finish Session',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStageContent() {
    switch (_currentStage) {
      // ── Stage 1: Supported Reading ─────────────────────────────────────────
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Read the passage and notice the target words.'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.passageText),
              ),
            ),
            const SizedBox(height: 12),
            Text('Target Words: ${widget.targetWords.join(', ')}'),
          ],
        );

      // ── Stage 2: Cue Fading ────────────────────────────────────────────────
      case 2:
        return const Text(
          'Cue Fading: re-read the passage without translations or highlights.',
        );

      // ── Stage 3: Active Recall ─────────────────────────────────────────────
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recall Test: type each target word from memory.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            ...List.generate(widget.targetWords.length, (i) {
              final result = _recallResults[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _recallControllers[i],
                  enabled: !_saving && !_recallBatchFrozen,
                  decoration: InputDecoration(
                    labelText: 'Word ${i + 1}',
                    hintText: 'Type from memory',
                    border: const OutlineInputBorder(),
                    suffixIcon: result == null
                        ? null
                        : Icon(
                            result ? Icons.check_circle : Icons.cancel,
                            color: result ? Colors.green : Colors.red,
                          ),
                  ),
                ),
              );
            }),
            if (_recallResults.any((r) => r != null))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_recallResults.where((r) => r == true).length}/'
                  '${widget.targetWords.length} correct',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
          ],
        );

      // ── Stage 4: Memory Association ────────────────────────────────────────
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create a memory keyword or story for each target word.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            ...List.generate(widget.targetWords.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.lightbulb_outline,
                          size: 16,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.targetWords[i],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cueControllers[i],
                      enabled:
                          !_saving && !_associationLocked && !_checkpointLocked,
                      decoration: const InputDecoration(
                        hintText: 'Keyword, story, or image...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              );
            }),
          ],
        );

      // ── Stage 5: Context Transfer ──────────────────────────────────────────
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Use one target word in a new sentence.'),
            const SizedBox(height: 12),
            TextField(
              enabled: !_saving && !_checkpointLocked,
              decoration: const InputDecoration(
                hintText: 'Enter a new sentence',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        );

      // ── Stage 6: Finish ────────────────────────────────────────────────────
      case 6:
      default:
        final correct = _recallResults.where((r) => r == true).length;
        final total = widget.targetWords.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fact_check_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Ready to finish',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (total > 0)
              Text('Recall score: $correct / $total')
            else
              const Text('Tap Finish Session to save completion.'),
          ],
        );
    }
  }
}

enum _PendingAssociationBatchStatus {
  captured,
  writing,
  retryRequired,
  committed,
}

final class _AssociationDraftEntry {
  const _AssociationDraftEntry({
    required this.ordinal,
    required this.wordKey,
    required this.cue,
  });

  final int ordinal;
  final String wordKey;
  final String cue;
}

final class _AssociationBatchDraft {
  _AssociationBatchDraft({
    required this.capturedAtUtc,
    required List<_AssociationDraftEntry> entries,
  }) : entries = List<_AssociationDraftEntry>.unmodifiable(entries);

  final DateTime capturedAtUtc;
  final List<_AssociationDraftEntry> entries;
}

final class _AssociationWrite {
  const _AssociationWrite({
    required this.association,
    required this.initialState,
  });

  final AssociationRecord association;
  final AssociativeMemoryState initialState;
}

/// One immutable Stage 4 batch. Successful prefixes are never replayed, while
/// a write that may have committed before throwing is retried with the same ID
/// and timestamp so both production and in-memory adapters remain idempotent.
final class _PendingAssociationBatch {
  _PendingAssociationBatch(
    this._associativeLearning, {
    required List<_AssociationWrite> writes,
  }) : _writes = List<_AssociationWrite>.unmodifiable(writes);

  final AssociativeLearningPort _associativeLearning;
  final List<_AssociationWrite> _writes;
  _PendingAssociationBatchStatus _status =
      _PendingAssociationBatchStatus.captured;
  Future<void>? _saveInFlight;
  var _nextWrite = 0;

  bool get requiresRetry =>
      _status == _PendingAssociationBatchStatus.retryRequired;

  Future<void> save() {
    final inFlight = _saveInFlight;
    if (inFlight != null) return inFlight;
    if (requiresRetry) {
      return Future<void>.error(
        StateError('explicit retry is required for association batch'),
      );
    }
    if (_status == _PendingAssociationBatchStatus.committed) {
      return Future<void>.value();
    }
    return _startSave();
  }

  Future<void> retry() {
    final inFlight = _saveInFlight;
    if (inFlight != null) return inFlight;
    if (!requiresRetry) {
      return Future<void>.error(
        StateError('association batch is not awaiting retry'),
      );
    }
    return _startSave();
  }

  Future<void> _startSave() {
    final future = _executeSave();
    _saveInFlight = future;
    return future;
  }

  Future<void> _executeSave() async {
    try {
      _status = _PendingAssociationBatchStatus.writing;
      while (_nextWrite < _writes.length) {
        final write = _writes[_nextWrite];
        await _associativeLearning.saveAssociationAndMemoryState(
          write.association,
          write.initialState,
        );
        _nextWrite++;
      }
      _status = _PendingAssociationBatchStatus.committed;
    } catch (_) {
      _status = _PendingAssociationBatchStatus.retryRequired;
      rethrow;
    } finally {
      _saveInFlight = null;
    }
  }
}
