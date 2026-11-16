import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/source_reading_round.dart';
import '../runtime/app_dependencies.dart';

/// Six-stage Associative Reading Loop screen.
///
/// Stages:
///   1 Supported Reading  — read passage with target-word hints
///   2 Cue Fading         — re-read without translations
///   3 Active Recall      — type each target word from memory; answer recorded
///                          via [LearningUseCases.recordAnswer]
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
    this.ownerId,
    this.sourceScope,
  });

  final String cefrLevel;

  /// Display names of the target vocabulary words (e.g. 'banana').
  final List<String> targetWords;
  final String passageText;
  final String? documentId;
  final int documentRevision;
  final LearningUseCases? learning;

  /// Port for saving memory associations (Stage 4).
  /// Falls back to [InMemoryAssociativeLearningAdapter] when null.
  final AssociativeLearningPort? associativeLearning;

  /// Map from word display name → Drift vocabulary word ID.
  /// Required for Stage 3 SRS recording; Stage 3 is skipped when null.
  final Map<String, String>? targetWordIds;

  /// Learning session ID for recording answers in Stage 3.
  /// Created externally (e.g. by [LearningUseCases.startQuiz]) before
  /// navigating to this screen.
  final String? sessionId;
  final String? ownerId;
  final SourceReadingScope? sourceScope;

  @override
  State<AssociativeReadingSessionScreen> createState() =>
      _AssociativeReadingSessionScreenState();
}

class _AssociativeReadingSessionScreenState
    extends State<AssociativeReadingSessionScreen>
    with WidgetsBindingObserver {
  static const _stageTitles = <String>[
    'ขั้นที่ 1: อ่านพร้อมตัวช่วย',
    'ขั้นที่ 2: อ่านโดยลดตัวช่วย',
    'ขั้นที่ 3: ทดสอบจากความจำ',
    'ขั้นที่ 4: สร้างตัวช่วยจำ',
    'ขั้นที่ 5: แต่งประโยคใหม่',
    'ขั้นที่ 6: สรุปผล',
  ];

  LearningUseCases? _learning;
  AssociativeLearningPort? _associativeLearning;

  int _currentStage = 1;
  bool _loading = true;
  bool _saving = false;
  bool _completed = false;
  String? _sessionId;
  bool _sessionFinished = false;
  LearningSessionSummary? _sessionSummary;
  final _sentenceController = TextEditingController();
  SourceReadingRound? _sourceRound;
  AppDependencies? _sourceDependencies;
  StreamSubscription<String?>? _sourceOwnerChanges;
  Future<void>? _sourceDraftWrite;
  ({SourceReadingRound expected, SourceReadingDraft draft})? _sourcePendingSave;
  bool _sourceInvalidated = false;
  bool _sourceDraftPending = false;
  bool _sourceDraftSaved = false;
  bool _leavingAfterSourceDraft = false;
  String? _sourceError;

  // Stage 3 — per-word recall controllers and results.
  late List<TextEditingController> _recallControllers;
  late List<bool?> _recallResults; // null=unanswered, true=correct, false=wrong
  late List<bool?> _frozenRecallResults;
  late List<DateTime?> _recallAttemptTimes;

  // Stage 4 — per-word association cue controllers.
  late List<TextEditingController> _cueControllers;
  late List<DateTime?> _associationCreatedTimes;

  String get _documentId {
    if (widget.sourceScope case final scope?) return scope.documentId;
    final supplied = widget.documentId?.trim();
    if (supplied != null && supplied.isNotEmpty) return supplied;
    var hash = 2166136261;
    for (final unit in '${widget.cefrLevel}:${widget.passageText}'.codeUnits) {
      hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
    }
    return 'reading:$hash';
  }

  List<String> get _targetWords =>
      widget.sourceScope?.words.map((word) => word.spelling).toList() ??
      widget.targetWords;

  bool get _sourceActive => mounted && !_sourceInvalidated;

  bool get _sourceTransitionPending {
    final change = _sourcePendingSave;
    return change != null && change.expected.draft.phase != change.draft.phase;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recallControllers = List.generate(
      _targetWords.length,
      (_) => TextEditingController(),
    );
    _recallResults = List.filled(_targetWords.length, null);
    _frozenRecallResults = List.filled(_targetWords.length, null);
    _recallAttemptTimes = List.filled(_targetWords.length, null);
    _cueControllers = List.generate(
      _targetWords.length,
      (_) => TextEditingController(),
    );
    _associationCreatedTimes = List.filled(_targetWords.length, null);
    _associativeLearning = widget.associativeLearning;
    _sessionId = widget.sessionId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dependencies = AppDependenciesScope.maybeOf(context);
    final sourceScope = widget.sourceScope;
    if (sourceScope != null &&
        _learning != null &&
        !identical(dependencies, _sourceDependencies)) {
      _sourceInvalidated = true;
    }
    if (!_loading || _learning != null) return;
    _learning = widget.learning ?? dependencies?.learning;
    _associativeLearning ??=
        dependencies?.associativeLearning ??
        InMemoryAssociativeLearningAdapter();
    if (sourceScope != null) {
      if (dependencies != null &&
          !identical(_learning, dependencies.learning)) {
        _sourceInvalidated = true;
        return;
      }
      _sourceDependencies = dependencies;
      final ownerId = widget.ownerId;
      _sourceOwnerChanges = dependencies?.watchActiveOwnerId()?.listen((
        active,
      ) {
        if (active != ownerId) _invalidateSource();
      }, onError: (Object _) => _invalidateSource());
      unawaited(_loadSource(sourceScope));
      return;
    }
    final learning = _learning;
    if (learning == null) {
      setState(() => _loading = false);
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
  void didUpdateWidget(covariant AssociativeReadingSessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldScope = oldWidget.sourceScope;
    final newScope = widget.sourceScope;
    if ((oldScope != null || newScope != null) &&
        (oldScope == null ||
            newScope == null ||
            !oldScope.sameAs(newScope) ||
            oldWidget.ownerId != widget.ownerId ||
            !identical(oldWidget.learning, widget.learning))) {
      _sourceInvalidated = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.sourceScope != null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_checkpoint(isCompleted: false, showFailure: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sourceOwnerChanges?.cancel());
    _sentenceController.dispose();
    for (final c in _recallControllers) {
      c.dispose();
    }
    for (final c in _cueControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _invalidateSource() {
    if (_sourceActive) setState(() => _sourceInvalidated = true);
  }

  Future<void> _loadSource(SourceReadingScope scope) async {
    try {
      final round = await _learning!.openSourceReadingRound(
        expectedOwnerId: widget.ownerId!,
        scope: scope,
      );
      if (!_sourceActive) return;
      for (final (slot, controller) in _recallControllers.indexed) {
        controller.text = round.draft.recall[slot];
      }
      for (final (slot, controller) in _cueControllers.indexed) {
        controller.text = round.draft.cues[slot];
      }
      _sentenceController.text = round.draft.sentence;
      _sourceDraftSaved = round.revision > 0;
      _setSourceRound(round);
    } catch (_) {
      if (_sourceActive) {
        _sourceError = 'เปิดรอบเดิมไม่สำเร็จ กรุณากลับไปเลือกข้อความใหม่';
      }
    } finally {
      if (_sourceActive) setState(() => _loading = false);
    }
  }

  void _setSourceRound(SourceReadingRound round) {
    _sourceRound = round;
    _currentStage = switch (round.draft.phase) {
      SourceReadingPhase.supported => 1,
      SourceReadingPhase.reread => 2,
      SourceReadingPhase.recall ||
      SourceReadingPhase.comparison ||
      SourceReadingPhase.correction => 3,
      SourceReadingPhase.association => 4,
      SourceReadingPhase.sentence => 5,
      SourceReadingPhase.summary => 6,
    };
  }

  SourceReadingDraft _sourceDraft(
    SourceReadingPhase phase,
    SourceReadingFirstRecall? first,
  ) => SourceReadingDraft(
    phase: phase,
    first: first,
    recall: [for (final field in _recallControllers) field.text],
    cues: [for (final field in _cueControllers) field.text],
    sentence: _sentenceController.text,
  );

  void _sourceTextChanged(String _) {
    if (!_sourceActive || _saving || _sourceTransitionPending) return;
    _sourceDraftPending = true;
    setState(() {
      _sourceDraftSaved = false;
      _sourceError = null;
    });
    _sourceDraftWrite ??= _saveSourceDrafts().whenComplete(() {
      _sourceDraftWrite = null;
      if (_sourceActive) setState(() {});
    });
  }

  Future<void> _saveSourceDrafts() async {
    while (_sourceDraftPending && _sourceActive) {
      try {
        await _applyPendingSourceSave();
        if (!_sourceActive) return;
        _sourceDraftPending = false;
        final draft = _sourceRound!.draft;
        await _commitSourceDraft(_sourceDraft(draft.phase, draft.first));
        if (!_sourceActive) return;
        setState(() => _sourceDraftSaved = !_sourceDraftPending);
      } catch (_) {
        _sourceDraftPending = false;
        if (_sourceActive) {
          setState(() => _sourceError = 'บันทึกร่างไม่สำเร็จ กรุณาลองอีกครั้ง');
        }
        return;
      }
    }
  }

  Future<void> _commitSourceDraft(SourceReadingDraft draft) {
    _sourcePendingSave = (expected: _sourceRound!, draft: draft);
    return _applyPendingSourceSave();
  }

  Future<void> _applyPendingSourceSave() async {
    final change = _sourcePendingSave;
    if (change == null) return;
    final saved = await _learning!.saveSourceReadingRound(
      expectedOwnerId: widget.ownerId!,
      expected: change.expected,
      draft: change.draft,
    );
    if (!_sourceActive) return;
    _sourcePendingSave = null;
    final previousStage = _currentStage;
    _setSourceRound(saved);
    if (_currentStage != previousStage) {
      await _checkpoint(isCompleted: false, showFailure: true);
    }
  }

  Future<void> _leaveAfterSourceDraft() async {
    final pending = _sourceDraftWrite;
    if (_saving || pending == null || _leavingAfterSourceDraft) return;
    _leavingAfterSourceDraft = true;
    try {
      await pending;
      if (mounted &&
          !_sourceInvalidated &&
          !_saving &&
          _sourceDraftWrite == null &&
          _sourcePendingSave == null &&
          ModalRoute.isCurrentOf(context) == true &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } finally {
      _leavingAfterSourceDraft = false;
    }
  }

  bool _allSourceWordsMatch(List<String> answers) => _sourceRound!
      .scope
      .words
      .indexed
      .every((item) => sourceRecallMatches(answers[item.$1], item.$2.spelling));

  Future<void> _advanceSource({bool skipCorrection = false}) async {
    if (!_sourceActive || _saving || _sourceRound == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _sourceError = null;
    });
    try {
      await _sourceDraftWrite;
      if (!_sourceActive) return;
      final previousPhase = _sourceRound!.draft.phase;
      await _applyPendingSourceSave();
      if (!_sourceActive) return;
      final round = _sourceRound!;
      final phase = round.draft.phase;
      if (phase != previousPhase) {
        _sourceDraftSaved = true;
        return;
      }
      if (phase == SourceReadingPhase.summary) {
        final result = await _learning!.finishSourceReadingRound(
          expectedOwnerId: widget.ownerId!,
          round: round,
        );
        if (!_sourceActive) return;
        final saved = await _checkpoint(isCompleted: true, showFailure: true);
        if (saved &&
            mounted &&
            !_sourceInvalidated &&
            ModalRoute.isCurrentOf(context) == true) {
          Navigator.of(context).pop(result);
        }
        return;
      }
      final draft = _sourceDraft(phase, round.draft.first);
      final first = phase == SourceReadingPhase.recall
          ? (answers: draft.recall, checkedAtUtc: _learning!.nowUtc())
          : draft.first;
      final next = switch (phase) {
        SourceReadingPhase.supported => SourceReadingPhase.reread,
        SourceReadingPhase.reread => SourceReadingPhase.recall,
        SourceReadingPhase.recall || SourceReadingPhase.correction =>
          _allSourceWordsMatch(draft.recall)
              ? SourceReadingPhase.association
              : SourceReadingPhase.comparison,
        SourceReadingPhase.comparison =>
          skipCorrection
              ? SourceReadingPhase.association
              : SourceReadingPhase.correction,
        SourceReadingPhase.association => SourceReadingPhase.sentence,
        SourceReadingPhase.sentence => SourceReadingPhase.summary,
        SourceReadingPhase.summary => throw StateError('Source round finished'),
      };
      await _commitSourceDraft(_sourceDraft(next, first));
      if (!_sourceActive) return;
      _sourceDraftSaved = true;
    } catch (_) {
      if (_sourceActive) {
        _sourceError = 'บันทึกรอบฝึกไม่สำเร็จ กรุณาลองอีกครั้ง';
      }
    } finally {
      if (_sourceActive) setState(() => _saving = false);
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _nextStage() async {
    if (_saving) return;
    setState(() => _saving = true);

    // Stage-specific side effects before advancing.
    if (_currentStage == 3) {
      if (!await _submitRecallAnswers()) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    } else if (_currentStage == 4) {
      if (!await _saveAssociations()) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }
    if (!mounted) return;

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
    if (finishing) {
      final learning = _learning;
      final sessionId = _sessionId;
      if (learning != null && sessionId != null && !_sessionFinished) {
        try {
          final summary = await learning.finishSession(sessionId);
          if (!_isValidSummary(summary, sessionId)) {
            throw StateError('invalid reading summary');
          }
          _sessionSummary = summary;
          _sessionFinished = true;
        } catch (_) {
          if (mounted) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('บันทึกผลการอ่านไม่สำเร็จ กรุณาลองอีกครั้ง'),
              ),
            );
          }
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _completed = true;
      });
      final summary = _sessionSummary;
      Navigator.of(context).pop(
        summary == null
            ? null
            : LearningSessionResult(
                summary: summary,
                mistakeWordIds: _mistakeWordIds,
              ),
      );
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
    final wordIds = widget.targetWordIds;
    if (learning == null || wordIds == null) return true;
    if (await _ownerForWrite(showFailure: true) == null) return false;

    var sessionId = _sessionId;
    if (sessionId == null) {
      try {
        final session = await learning.startReadingForWords(
          wordIds: wordIds.values,
          limit: wordIds.length,
        );
        if (session.isEmpty) return true;
        sessionId = session.id;
        _sessionId = sessionId;
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เริ่มบันทึกแบบฝึกอ่านไม่สำเร็จ')),
          );
        }
        return false;
      }
    }

    final results = <bool?>[];
    for (var i = 0; i < widget.targetWords.length; i++) {
      final word = widget.targetWords[i];
      final wordId = wordIds[word];
      if (wordId == null) {
        results.add(null);
        continue;
      }
      final typed = _recallControllers[i].text.trim().toLowerCase();
      final expected = word.trim().toLowerCase();
      final isCorrect = _frozenRecallResults[i] ??= typed == expected;
      results.add(isCorrect);
      try {
        final occurredAtUtc = _recallAttemptTimes[i] ??= DateTime.now().toUtc();
        await learning.recordAnswer(
          sessionId: sessionId,
          wordId: wordId,
          promptMode: 'associativeRecall',
          isCorrect: isCorrect,
          responseTimeMs: null,
          attemptNumber: i + 1,
          attemptId: 'attempt:$sessionId:associative:$i',
          occurredAtUtc: occurredAtUtc,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกคำตอบไม่สำเร็จ กรุณาลองอีกครั้ง'),
            ),
          );
        }
        return false;
      }
    }
    try {
      final summary = await learning.finishSession(sessionId);
      if (!_isValidSummary(summary, sessionId)) {
        throw StateError('invalid reading summary');
      }
      _sessionSummary = summary;
      _sessionFinished = true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกผลการอ่านไม่สำเร็จ กรุณาลองอีกครั้ง'),
          ),
        );
      }
      return false;
    }
    if (mounted) setState(() => _recallResults = results);
    return true;
  }

  List<String> get _mistakeWordIds {
    final wordIds = widget.targetWordIds;
    if (wordIds == null) return const [];
    final mistakes = <String>{};
    for (var i = 0; i < widget.targetWords.length; i++) {
      if (_frozenRecallResults[i] != false) continue;
      final id = wordIds[widget.targetWords[i]];
      if (id != null) mistakes.add(id);
    }
    return mistakes.toList(growable: false);
  }

  bool _isValidSummary(LearningSessionSummary summary, String sessionId) {
    final attempted = _frozenRecallResults.whereType<bool>().length;
    final correct = _frozenRecallResults
        .where((result) => result == true)
        .length;
    final wrong = attempted - correct;
    final score = attempted == 0 ? 0 : ((correct * 100) / attempted).round();
    return summary.id == sessionId &&
        summary.state == 'completed' &&
        summary.correctCount == correct &&
        summary.wrongCount == wrong &&
        summary.score == score;
  }

  // ── Stage 4: Memory Association ────────────────────────────────────────────

  Future<bool> _saveAssociations() async {
    if (_cueControllers.every((controller) => controller.text.trim().isEmpty)) {
      return true;
    }
    final ownerId = await _ownerForWrite(showFailure: true);
    if (ownerId == null) return false;
    final associativeLearning =
        _associativeLearning ?? InMemoryAssociativeLearningAdapter();

    for (var i = 0; i < _targetWords.length; i++) {
      final cue = _cueControllers[i].text.trim();
      if (cue.isEmpty) continue;
      try {
        final word = _targetWords[i];
        final wordIdentity = widget.targetWordIds?[word] ?? i;
        final createdAtUtc = _associationCreatedTimes[i] ??= DateTime.now()
            .toUtc();
        await associativeLearning.saveAssociation(
          AssociationRecord(
            associationId:
                'assoc:$ownerId:$_documentId:${widget.documentRevision}:'
                '$wordIdentity',
            ownerId: ownerId,
            wordKey: word,
            type: 'keyword',
            content: cue,
            createdAtUtc: createdAtUtc,
          ),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกตัวช่วยจำไม่สำเร็จ กรุณาลองอีกครั้ง'),
            ),
          );
        }
        return false;
      }
    }
    return true;
  }

  // ── Checkpoint ─────────────────────────────────────────────────────────────

  Future<bool> _checkpoint({
    int? position,
    required bool isCompleted,
    required bool showFailure,
  }) async {
    final learning = _learning;
    if (learning == null) return true;
    if (await _ownerForWrite(showFailure: showFailure) == null) return false;
    if (!mounted || (widget.sourceScope != null && !_sourceActive)) {
      return false;
    }
    try {
      await learning.saveReadingProgress(
        documentId: _documentId,
        documentRevision:
            widget.sourceScope?.documentRevision ?? widget.documentRevision,
        position: position ?? _currentStage,
        isCompleted: isCompleted,
        expectedOwnerId: widget.ownerId,
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

  Future<String?> _ownerForWrite({required bool showFailure}) async {
    final expected = widget.ownerId?.trim();
    final learning = _learning;
    if (learning == null) {
      return expected == null || expected.isEmpty ? null : expected;
    }
    try {
      final current = await learning.owners.getOrCreateActiveOwner();
      if (expected != null && expected.isNotEmpty && expected != current.id) {
        if (showFailure) _showOwnerChanged();
        return null;
      }
      return current.id;
    } catch (_) {
      if (showFailure) _showOwnerChanged();
      return null;
    }
  }

  void _showOwnerChanged() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('บัญชีผู้เรียนเปลี่ยนแล้ว กรุณาเปิดกิจกรรมใหม่'),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_sourceInvalidated ||
        (widget.sourceScope != null && !_loading && _sourceRound == null)) {
      return Scaffold(
        appBar: AppBar(title: const Text('อ่านแล้วลองนึกคำ')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _sourceInvalidated
                  ? 'บัญชีผู้เรียนเปลี่ยนแล้ว กรุณาเปิดกิจกรรมใหม่'
                  : _sourceError!,
            ),
          ),
        ),
      );
    }
    final sourcePhase = _sourceRound?.draft.phase;
    final screen = Scaffold(
      appBar: AppBar(title: Text('อ่านแบบเชื่อมโยง (${widget.cefrLevel})')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'กำลังเตรียมบทอ่านแบบเชื่อมโยง',
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _currentStage / 6,
                    semanticsLabel:
                        'ความคืบหน้าการอ่านแบบเชื่อมโยง ขั้นตอน $_currentStage จาก 6',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _stageTitles[_currentStage - 1],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStageContent(),
                          if (_sourceError case final error?) Text(error),
                          if (_sourceDraftSaved &&
                              !_saving &&
                              (sourcePhase == SourceReadingPhase.recall ||
                                  sourcePhase ==
                                      SourceReadingPhase.correction ||
                                  sourcePhase ==
                                      SourceReadingPhase.association ||
                                  sourcePhase == SourceReadingPhase.sentence))
                            const Text('บันทึกร่างแล้ว'),
                        ],
                      ),
                    ),
                  ),
                  if (_saving)
                    const LinearProgressIndicator(
                      semanticsLabel: 'กำลังบันทึกผลการอ่าน',
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving || _completed
                        ? null
                        : sourcePhase == null
                        ? _nextStage
                        : _advanceSource,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(switch (sourcePhase) {
                      SourceReadingPhase.recall => 'ตรวจคำตอบ',
                      SourceReadingPhase.comparison => 'แก้คำตอบ',
                      SourceReadingPhase.correction => 'ตรวจอีกครั้ง',
                      SourceReadingPhase.association => 'ลองใช้ในประโยค',
                      _ =>
                        _currentStage < 6
                            ? 'เสร็จแล้ว ไปขั้นถัดไป'
                            : 'บันทึกและจบการฝึก',
                    }),
                  ),
                ],
              ),
            ),
    );
    if (widget.sourceScope == null) return screen;
    return PopScope<LearningSessionResult>(
      canPop: !_saving && _sourceDraftWrite == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leaveAfterSourceDraft());
      },
      child: screen,
    );
  }

  TextInputFormatter _sourceTextLimit(int limit) =>
      TextInputFormatter.withFunction(
        (previous, next) =>
            sourceReadingTextFits(next.text, limit) ? next : previous,
      );

  Widget _buildSourceRecall(SourceReadingRound round) {
    final first = round.draft.first;
    final comparison = round.draft.phase == SourceReadingPhase.comparison;
    final correcting = round.draft.phase == SourceReadingPhase.correction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          comparison
              ? 'เทียบคำตอบกับคำในบทอ่าน'
              : correcting
              ? 'แก้คำที่เขียนผิด'
              : 'พิมพ์คำศัพท์เป้าหมายแต่ละคำจากความจำ',
        ),
        const SizedBox(height: 12),
        for (final (slot, word) in round.scope.words.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: comparison
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('คำตอบครั้งแรก: ${first!.answers[slot]}'),
                      if (round.draft.recall[slot] != first.answers[slot])
                        Text('คำตอบล่าสุด: ${round.draft.recall[slot]}'),
                      Text('คำในบทอ่าน: ${word.spelling}'),
                    ],
                  )
                : TextField(
                    controller: _recallControllers[slot],
                    readOnly:
                        _saving ||
                        _sourceTransitionPending ||
                        (first != null &&
                            sourceRecallMatches(
                              first.answers[slot],
                              word.spelling,
                            )),
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      _sourceTextLimit(sourceReadingRecallMaxLength),
                    ],
                    onChanged: _sourceTextChanged,
                    decoration: InputDecoration(
                      labelText: 'คำที่ ${slot + 1}',
                      helperText:
                          round.scope.words.any(
                            (target) => word.meaning.toLowerCase().contains(
                              target.spelling.toLowerCase(),
                            ),
                          )
                          ? null
                          : word.meaning,
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                    ),
                  ),
          ),
        if (comparison)
          TextButton(
            onPressed: _saving
                ? null
                : () => _advanceSource(skipCorrection: true),
            child: const Text('ข้ามการแก้คำ'),
          ),
      ],
    );
  }

  Widget _buildStageContent() {
    switch (_currentStage) {
      // ── Stage 1: Supported Reading ─────────────────────────────────────────
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('อ่านเรื่องและสังเกตคำศัพท์เป้าหมาย'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.passageText),
              ),
            ),
            const SizedBox(height: 12),
            Text('คำศัพท์เป้าหมาย: ${_targetWords.join(', ')}'),
          ],
        );

      // ── Stage 2: Cue Fading ────────────────────────────────────────────────
      case 2:
        if (_sourceRound != null) return Text(widget.passageText);
        return const Text(
          'อ่านเรื่องอีกครั้งโดยไม่ดูคำแปลหรือข้อความที่เน้นไว้',
        );

      // ── Stage 3: Active Recall ─────────────────────────────────────────────
      case 3:
        if (_sourceRound case final round?) return _buildSourceRecall(round);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'พิมพ์คำศัพท์เป้าหมายแต่ละคำจากความจำ',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            ...List.generate(_targetWords.length, (i) {
              final result = _recallResults[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _recallControllers[i],
                  decoration: InputDecoration(
                    labelText: 'คำที่ ${i + 1}',
                    hintText: 'พิมพ์จากความจำ',
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
                  '${widget.targetWords.length} คำถูกต้อง',
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
              'สร้างคำใบ้หรือเรื่องสั้นเพื่อช่วยจำคำศัพท์แต่ละคำ',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            ...List.generate(_targetWords.length, (i) {
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
                          _targetWords[i],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cueControllers[i],
                      readOnly:
                          _sourceRound != null &&
                          (_saving || _sourceTransitionPending),
                      onChanged: _sourceRound == null
                          ? null
                          : _sourceTextChanged,
                      inputFormatters: _sourceRound == null
                          ? null
                          : [_sourceTextLimit(sourceReadingCueMaxLength)],
                      decoration: const InputDecoration(
                        hintText: 'คำใบ้ เรื่องสั้น หรือภาพที่นึกถึง',
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
            const Text('นำคำศัพท์เป้าหมายหนึ่งคำไปแต่งประโยคใหม่'),
            const SizedBox(height: 12),
            TextField(
              controller: _sourceRound == null ? null : _sentenceController,
              readOnly:
                  _sourceRound != null && (_saving || _sourceTransitionPending),
              onChanged: _sourceRound == null ? null : _sourceTextChanged,
              inputFormatters: _sourceRound == null
                  ? null
                  : [_sourceTextLimit(sourceReadingSentenceMaxLength)],
              decoration: const InputDecoration(
                hintText: 'พิมพ์ประโยคใหม่',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        );

      // ── Stage 6: Finish ────────────────────────────────────────────────────
      case 6:
      default:
        final source = _sourceRound;
        final first = source?.draft.first;
        final correct = first == null
            ? _recallResults.where((r) => r == true).length
            : source!.scope.words.indexed
                  .where(
                    (item) => sourceRecallMatches(
                      first.answers[item.$1],
                      item.$2.spelling,
                    ),
                  )
                  .length;
        final total = _targetWords.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fact_check_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'พร้อมจบการฝึก',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (total > 0)
              Text('จำได้ถูกต้อง: $correct / $total คำ')
            else
              const Text('แตะบันทึกและจบการฝึกเพื่อบันทึกผล'),
            if (source != null && source.draft.sentence.trim().isNotEmpty)
              Text(source.draft.sentence.trim()),
          ],
        );
    }
  }
}
