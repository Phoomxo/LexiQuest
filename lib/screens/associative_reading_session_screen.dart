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
  /// Required for Stage 3 SRS recording; Stage 3 is skipped when null.
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

enum AssociativeReadingUnavailableReason { learning, associativeLearning }

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

  // Stage 3 — per-word recall controllers and results.
  late List<TextEditingController> _recallControllers;
  late List<bool?> _recallResults; // null=unanswered, true=correct, false=wrong
  late List<PendingCurrentActivityEvidence?> _pendingRecallEvidence;
  CurrentActivityEvidenceAdapter? _evidenceAdapter;

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
        widget.evidenceAdapter ??
        CurrentActivityEvidenceAdapter.legacy(learning);
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
    if (_unavailableReason != null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_checkpoint(isCompleted: false, showFailure: false));
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
    if (_saving) return;
    setState(() => _saving = true);

    // Stage-specific side effects before advancing.
    if (_currentStage == 3) {
      final answersSaved = await _submitRecallAnswers();
      if (!mounted) return;
      if (!answersSaved) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save recall evidence. Try again.'),
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

    final finishing = _currentStage == 6;
    final nextStage = finishing ? 6 : _currentStage + 1;
    final saved = await _checkpoint(
      position: nextStage,
      isCompleted: finishing,
      showFailure: true,
    );
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      return;
    }
    if (_currentStage == 3) {
      for (var i = 0; i < _pendingRecallEvidence.length; i++) {
        _pendingRecallEvidence[i] = null;
      }
    }
    if (finishing) {
      setState(() {
        _saving = false;
        _completed = true;
      });
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _currentStage = nextStage;
      _saving = false;
    });
  }

  // ── Stage 3: Active Recall ─────────────────────────────────────────────────

  Future<bool> _submitRecallAnswers() async {
    final learning = _learning;
    final sessionId = widget.sessionId;
    final wordIds = widget.targetWordIds;
    if (learning == null || sessionId == null || wordIds == null) return true;

    final results = <bool?>[];
    var allSaved = true;
    for (var i = 0; i < widget.targetWords.length; i++) {
      final word = widget.targetWords[i];
      final wordId = wordIds[word];
      if (wordId == null) {
        results.add(null);
        continue;
      }
      final typed = _recallControllers[i].text.trim().toLowerCase();
      final expected = word.trim().toLowerCase();
      final isCorrect = typed == expected;
      results.add(isCorrect);
      try {
        final pending = _pendingRecallEvidence[i] ??= await _evidenceAdapter!
            .prepare(
              input: CurrentActivityInput.associativeRecall,
              sessionId: sessionId,
              wordId: wordId,
              isCorrect: isCorrect,
              responseTimeMs: null,
              attemptNumber: i + 1,
            );
        await pending.record(learning);
      } catch (_) {
        allSaved = false;
      }
    }
    if (mounted) setState(() => _recallResults = results);
    return allSaved;
  }

  // ── Stage 4: Memory Association ────────────────────────────────────────────

  Future<bool> _saveAssociations() async {
    final learning = _learning;
    final associativeLearning = _associativeLearning;
    if (learning == null || associativeLearning == null) return false;

    try {
      final ownerId = (await learning.owners.getOrCreateActiveOwner()).id;
      final now = DateTime.now().toUtc();
      for (var i = 0; i < widget.targetWords.length; i++) {
        final displayWord = widget.targetWords[i];
        final wordKey = widget.targetWordIds?[displayWord] ?? displayWord;
        final cue = _cueControllers[i].text.trim();
        if (cue.isEmpty) {
          final existing = await associativeLearning.getMemoryState(
            ownerId,
            wordKey,
          );
          final associations = await associativeLearning.getAssociationsForWord(
            ownerId,
            wordKey,
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
            return false;
          }
          continue;
        }
        final association = AssociationRecord(
          associationId: 'assoc:$wordKey:${now.millisecondsSinceEpoch}:$i',
          ownerId: ownerId,
          wordKey: wordKey,
          type: 'keyword',
          content: cue,
          createdAtUtc: now,
        );
        final initialState = AssociativeMemoryState(
          ownerId: ownerId,
          wordKey: wordKey,
          stability: 1,
          difficulty: 5,
          cueDependency: 1,
          lapseCount: 0,
          lastReviewedAtUtc: now,
          nextDueAtUtc: now.add(const Duration(days: 1)),
          algorithmVersion: 'associative-v1',
        );
        await associativeLearning.saveAssociationAndMemoryState(
          association,
          initialState,
        );
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

  // ── Checkpoint ─────────────────────────────────────────────────────────────

  Future<bool> _checkpoint({
    int? position,
    required bool isCompleted,
    required bool showFailure,
  }) async {
    final learning = _learning;
    if (learning == null) return true;
    try {
      await learning.saveReadingProgress(
        documentId: _documentId,
        documentRevision: widget.documentRevision,
        position: position ?? _currentStage,
        isCompleted: isCompleted,
      );
      return true;
    } catch (_) {
      if (showFailure && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกตำแหน่งอ่านไม่สำเร็จ กรุณาลองอีกครั้ง'),
          ),
        );
      }
      return false;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final unavailableReason = _unavailableReason;
    if (unavailableReason != null) {
      return AssociativeReadingUnavailable(reason: unavailableReason);
    }
    return Scaffold(
      appBar: AppBar(title: Text('Associative Reading (${widget.cefrLevel})')),
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
                    onPressed: _saving || _completed ? null : _nextStage,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(
                      _currentStage < 6
                          ? 'Complete & Continue'
                          : 'Finish Session',
                    ),
                  ),
                ],
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
