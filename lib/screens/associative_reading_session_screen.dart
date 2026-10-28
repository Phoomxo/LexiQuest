import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
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
  bool _restartedRound = false;
  String? _sessionId;
  bool _sessionFinished = false;
  LearningSessionSummary? _sessionSummary;

  // Stage 3 — per-word recall controllers and results.
  late List<TextEditingController> _recallControllers;
  late List<bool?> _recallResults; // null=unanswered, true=correct, false=wrong
  late List<bool?> _frozenRecallResults;
  late List<DateTime?> _recallAttemptTimes;

  // Stage 4 — per-word association cue controllers.
  late List<TextEditingController> _cueControllers;
  late List<DateTime?> _associationCreatedTimes;

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
    _frozenRecallResults = List.filled(widget.targetWords.length, null);
    _recallAttemptTimes = List.filled(widget.targetWords.length, null);
    _cueControllers = List.generate(
      widget.targetWords.length,
      (_) => TextEditingController(),
    );
    _associationCreatedTimes = List.filled(widget.targetWords.length, null);
    _associativeLearning = widget.associativeLearning;
    _sessionId = widget.sessionId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading || _learning != null) return;
    _learning =
        widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning;
    _associativeLearning ??=
        AppDependenciesScope.maybeOf(context)?.associativeLearning ??
        InMemoryAssociativeLearningAdapter();
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
            final savedStage = (progress?.lastPosition ?? 1).clamp(1, 6);
            _restartedRound = savedStage >= 4 && widget.targetWordIds != null;
            _currentStage = _restartedRound ? 1 : savedStage;
            _completed = !_restartedRound && (progress?.isCompleted ?? false);
            if (_restartedRound) _sessionId = null;
            _loading = false;
          });
        })
        .catchError((Object _) {
          if (mounted) setState(() => _loading = false);
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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

    for (var i = 0; i < widget.targetWords.length; i++) {
      final cue = _cueControllers[i].text.trim();
      if (cue.isEmpty) continue;
      try {
        final word = widget.targetWords[i];
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
    try {
      await learning.saveReadingProgress(
        documentId: _documentId,
        documentRevision: widget.documentRevision,
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
    return Scaffold(
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
                    child: SingleChildScrollView(child: _buildStageContent()),
                  ),
                  if (_saving)
                    const LinearProgressIndicator(
                      semanticsLabel: 'กำลังบันทึกผลการอ่าน',
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving || _completed ? null : _nextStage,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: Text(
                      _currentStage < 6
                          ? 'เสร็จแล้ว ไปขั้นถัดไป'
                          : 'บันทึกและจบการฝึก',
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
            if (_restartedRound) ...[
              Semantics(
                liveRegion: true,
                child: const Text('เริ่มรอบใหม่โดยเก็บประวัติคำตอบเดิมไว้'),
              ),
              const SizedBox(height: 12),
            ],
            const Text('อ่านเรื่องและสังเกตคำศัพท์เป้าหมาย'),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(widget.passageText),
              ),
            ),
            const SizedBox(height: 12),
            Text('คำศัพท์เป้าหมาย: ${widget.targetWords.join(', ')}'),
          ],
        );

      // ── Stage 2: Cue Fading ────────────────────────────────────────────────
      case 2:
        return const Text(
          'อ่านเรื่องอีกครั้งโดยไม่ดูคำแปลหรือข้อความที่เน้นไว้',
        );

      // ── Stage 3: Active Recall ─────────────────────────────────────────────
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'พิมพ์คำศัพท์เป้าหมายแต่ละคำจากความจำ',
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
        final correct = _recallResults.where((r) => r == true).length;
        final total = widget.targetWords.length;
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
          ],
        );
    }
  }
}
