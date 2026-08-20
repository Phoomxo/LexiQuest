import 'dart:async';

import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../services/ghost_shadow_duel_service.dart';

typedef GhostProgressLoader = Future<ProgressSnapshot> Function();

class GhostShadowDuelScreen extends StatefulWidget {
  const GhostShadowDuelScreen({
    super.key,
    this.progressLoader,
    this.learning,
    this.evidenceAdapter,
  });

  final GhostProgressLoader? progressLoader;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? evidenceAdapter;

  @override
  State<GhostShadowDuelScreen> createState() => _GhostShadowDuelScreenState();
}

class _GhostShadowDuelScreenState extends State<GhostShadowDuelScreen> {
  LearningUseCases? _learning;
  Future<_DuelData>? _load;
  final _answer = TextEditingController();
  final _stopwatch = Stopwatch();
  int _index = 0;
  int _playerHp = 100;
  int _ghostHp = 0;
  bool _saving = false;
  bool _finished = false;
  bool _sessionClosed = false;
  final List<String> _log = <String>[];
  CurrentActivityEvidenceAdapter? _evidenceAdapter;
  PendingCurrentActivityEvidence? _pendingEvidence;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) return;
    final dependencies = AppDependenciesScope.maybeOf(context);
    _learning ??= widget.learning ?? dependencies?.learning;
    final learning = _learning;
    if (learning != null) {
      _evidenceAdapter =
          widget.evidenceAdapter ?? dependencies?.currentActivityEvidence;
    }
    final loader = widget.progressLoader ?? dependencies?.progress?.load;
    if (loader == null) {
      _load = Future<_DuelData>.error(
        StateError('learning evidence dependency unavailable'),
      );
      return;
    }
    if (learning != null && _evidenceAdapter == null) {
      _load = Future<_DuelData>.error(
        StateError('current activity evidence dependency unavailable'),
      );
      return;
    }
    _load = _loadDuel(loader, _learning);
  }

  Future<_DuelData> _loadDuel(
    GhostProgressLoader loadProgress,
    LearningUseCases? learning,
  ) async {
    final progress = await loadProgress();
    if (progress.sampleSize == 0 || progress.weaknesses.isEmpty) {
      return _DuelData.empty(progress);
    }
    if (learning == null) {
      throw StateError('learning dependency unavailable');
    }
    final session = await learning.startWeaknessPractice(
      wordIds: progress.weaknesses.map((item) => item.wordId),
    );
    if (session.isEmpty) return _DuelData.empty(progress);
    final averageMs = progress.averageResponseTimeMs ?? 3000;
    final ghostSnapshot = GhostSnapshot(
      recordedAt:
          progress.latestEvidenceAtUtc ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      accuracyRate: progress.accuracy ?? 0,
      avgResponseTimeMs: averageMs,
      weakWords: session.questions
          .map((question) => question.word.spelling)
          .toList(growable: false),
    );
    final opponent = GhostShadowDuelService.generateShadowOpponent(
      ghostSnapshot,
    );
    _ghostHp = opponent.maxHp;
    _stopwatch.start();
    return _DuelData(
      progress: progress,
      session: session,
      snapshot: ghostSnapshot,
      opponent: opponent,
    );
  }

  Future<void> _submit(_DuelData data) async {
    if (_saving || _finished || _pendingEvidence != null) return;
    final input = _answer.text.trim().toLowerCase();
    if (input.isEmpty) return;
    final question = data.session.questions[_index];
    final responseMs = _stopwatch.elapsedMilliseconds;
    final correct = input == question.word.spelling.trim().toLowerCase();
    final pending = _evidenceAdapter!.capture(
      input: CurrentActivityInput.ghostDuel,
      sessionId: data.session.id,
      wordId: question.word.id,
      isCorrect: correct,
      responseTimeMs: responseMs,
      attemptNumber: _index + 1,
      providerProvenance: 'local:ghost-duel:v1',
    );
    _pendingEvidence = pending;
    setState(() => _saving = true);
    await _commitPending(data, question, pending, retry: false);
  }

  Future<void> _retryEvidence(_DuelData data) async {
    final pending = _pendingEvidence;
    if (pending == null || !pending.requiresRetry || _saving) return;
    final question = data.session.questions[_index];
    setState(() => _saving = true);
    await _commitPending(data, question, pending, retry: true);
  }

  Future<void> _commitPending(
    _DuelData data,
    QuizQuestion question,
    PendingCurrentActivityEvidence pending, {
    required bool retry,
  }) async {
    try {
      if (retry) {
        await pending.retry();
      } else {
        await pending.record();
      }
      final turn = GhostShadowDuelService.evaluateTurn(
        playerResponseTimeMs: (pending.responseTimeMs ?? 0).toDouble(),
        isCorrect: pending.isCorrect,
        snapshot: data.snapshot,
      );
      if (!mounted) return;
      setState(() {
        _answer.clear();
        if (turn.playerHitGhost) {
          _ghostHp = (_ghostHp - turn.damageDealt).clamp(
            0,
            data.opponent.maxHp,
          );
          _log.insert(
            0,
            '${question.word.spelling}: ถูก · ${pending.responseTimeMs} ms · ${turn.damageDealt} damage',
          );
        } else {
          _playerHp = (_playerHp - 15).clamp(0, 100);
          _log.insert(
            0,
            '${question.word.spelling}: ผิด · ${pending.responseTimeMs} ms',
          );
        }
        _index += 1;
        _pendingEvidence = null;
        _finished =
            _ghostHp == 0 ||
            _playerHp == 0 ||
            _index >= data.session.questions.length;
        _stopwatch
          ..reset()
          ..start();
      });
      if (_finished) await _closeSession(data.session.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกคำตอบไม่สำเร็จ กรุณาลองใหม่')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeSession(String sessionId) async {
    if (_sessionClosed) return;
    _sessionClosed = true;
    await _learning?.finishSession(sessionId);
  }

  @override
  void dispose() {
    final load = _load;
    if (load != null) {
      unawaited(
        load.then((data) {
          if (!data.session.isEmpty) return _closeSession(data.session.id);
        }),
      );
    }
    _stopwatch.stop();
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ดวลกับสถิติเดิม')),
      body: FutureBuilder<_DuelData>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('ไม่สามารถอ่านประวัติการเรียนได้'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.session.isEmpty) {
            return Center(
              child: Text(
                'ยังไม่มีจุดอ่อนจากคำตอบจริงสำหรับเริ่มเกม\n'
                'จำนวนหลักฐาน: ${data.progress.sampleSize}',
                textAlign: TextAlign.center,
              ),
            );
          }
          final question = _finished ? null : data.session.questions[_index];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(data.opponent.name),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _ghostHp / data.opponent.maxHp,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'หลักฐาน ${data.progress.sampleSize} คำตอบ · '
                        'ความแม่นยำ ${((data.progress.accuracy ?? 0) * 100).round()}% · '
                        'เวลาเฉลี่ย ${data.snapshot.avgResponseTimeMs.round()} ms · '
                        'อัลกอริทึม v${data.progress.algorithmVersion}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('พลังผู้เรียน $_playerHp · พลังสถิติเดิม $_ghostHp'),
              const SizedBox(height: 16),
              if (question != null) ...[
                Text(
                  question.word.meaning,
                  key: const ValueKey<String>('ghost-prompt'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _answer,
                  enabled: !_saving && _pendingEvidence == null,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'พิมพ์คำศัพท์ภาษาอังกฤษ',
                  ),
                  onSubmitted: (_) => _submit(data),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: _pendingEvidence?.requiresRetry ?? false
                        ? const ValueKey<String>('current-evidence-retry')
                        : null,
                    onPressed: _saving
                        ? null
                        : _pendingEvidence?.requiresRetry ?? false
                        ? () => _retryEvidence(data)
                        : () => _submit(data),
                    child: Text(
                      _saving
                          ? 'กำลังบันทึก'
                          : _pendingEvidence?.requiresRetry ?? false
                          ? 'ลองบันทึกคำตอบอีกครั้ง'
                          : 'ตอบ',
                    ),
                  ),
                ),
              ] else
                Text(
                  'จบเกมแล้ว · บันทึก ${_log.length} คำตอบจริง',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              const SizedBox(height: 16),
              for (final entry in _log) ListTile(title: Text(entry)),
            ],
          );
        },
      ),
    );
  }
}

final class _DuelData {
  const _DuelData({
    required this.progress,
    required this.session,
    required this.snapshot,
    required this.opponent,
  });

  factory _DuelData.empty(ProgressSnapshot progress) => _DuelData(
    progress: progress,
    session: const QuizSession(id: '', questions: [], startedAtUtc: null),
    snapshot: GhostSnapshot(
      recordedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      accuracyRate: 0,
      avgResponseTimeMs: 0,
      weakWords: const [],
    ),
    opponent: const GhostOpponent(
      name: '',
      maxHp: 1,
      currentHp: 1,
      attackIntervalSeconds: 1,
      battleWords: [],
    ),
  );

  final ProgressSnapshot progress;
  final QuizSession session;
  final GhostSnapshot snapshot;
  final GhostOpponent opponent;
}
