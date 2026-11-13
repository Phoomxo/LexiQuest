import 'package:flutter/material.dart';

import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../widgets/adaptive_content_pane.dart';
import '../navigation/app_routes.dart';
import '../services/ghost_shadow_duel_service.dart';
import 'weakness_clinic_screen.dart';

typedef GhostProgressLoader = Future<ProgressSnapshot> Function();

class GhostShadowDuelScreen extends StatefulWidget {
  const GhostShadowDuelScreen({
    super.key,
    this.progressLoader,
    this.learning,
    this.featureRegistry,
  });

  final GhostProgressLoader? progressLoader;
  final LearningUseCases? learning;
  final FieldFeatureRegistry? featureRegistry;

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
  String? _ownerId;
  GhostProgressLoader? _progressLoader;
  bool _invalid = false;
  RecordAnswerCommand? _pendingAnswer;
  String? _submittedText;
  String? _saveError;
  String? _finishError;
  LearningSessionSummary? _summary;
  final List<String> _log = <String>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_load != null) {
      if (!identical(
        _learning,
        widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning,
      )) {
        _invalidate();
      }
      return;
    }
    final dependencies = AppDependenciesScope.maybeOf(context);
    _learning ??= widget.learning ?? dependencies?.learning;
    final loader = widget.progressLoader ?? dependencies?.progress?.load;
    _progressLoader = loader;
    if (loader == null) {
      _load = Future<_DuelData>.error(
        StateError('learning evidence dependency unavailable'),
      );
      return;
    }
    _load = _loadDuel(loader, _learning);
  }

  @override
  void didUpdateWidget(GhostShadowDuelScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.learning, widget.learning) ||
        !identical(oldWidget.progressLoader, widget.progressLoader)) {
      _invalidate();
    }
  }

  void _invalidate() {
    if (!mounted || _invalid) return;
    setState(() {
      _invalid = true;
      _answer.clear();
      _summary = null;
      _log.clear();
    });
  }

  Future<bool> _ownerCurrent() async {
    final learning = _learning;
    if (!mounted || _invalid || learning == null) return false;
    try {
      final owner = await learning.owners.getOrCreateActiveOwner();
      if (!mounted) return false;
      if (!_invalid &&
          owner.id == _ownerId &&
          identical(
            learning,
            widget.learning ?? AppDependenciesScope.maybeOf(context)?.learning,
          )) {
        return true;
      }
    } catch (_) {
      // Unavailable owner authority must not admit learning evidence.
    }
    _invalidate();
    return false;
  }

  Future<_DuelData> _loadDuel(
    GhostProgressLoader loadProgress,
    LearningUseCases? learning,
  ) async {
    if (learning != null) {
      _ownerId = (await learning.owners.getOrCreateActiveOwner()).id;
    }
    final progress = await loadProgress();
    if (!mounted || _invalid || (learning != null && !await _ownerCurrent())) {
      throw StateError('duel context unavailable');
    }
    if (progress.sampleSize == 0 || progress.weaknesses.isEmpty) {
      return _DuelData.empty(progress);
    }
    if (learning == null) {
      throw StateError('learning dependency unavailable');
    }
    final session = await learning.startGhostDuel(
      wordIds: progress.weaknesses.map((item) => item.wordId),
    );
    if (!await _ownerCurrent()) throw StateError('duel context changed');
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
    if (_saving || _finished || _invalid) return;
    final input = _answer.text.trim().toLowerCase();
    if (_pendingAnswer == null && input.isEmpty) return;
    final question = data.session.questions[_index];
    _submittedText ??= input;
    final command = _pendingAnswer ??= RecordAnswerCommand(
      id: 'attempt:ghost:${data.session.id}:$_index',
      ownerId: _ownerId!,
      sessionId: data.session.id,
      wordId: question.word.id,
      promptMode: 'ghostSpelling',
      isCorrect: input == question.word.spelling.trim().toLowerCase(),
      responseTimeMs: _stopwatch.elapsedMilliseconds,
      attemptNumber: _index + 1,
      occurredAtUtc: DateTime.now().toUtc(),
      providerProvenance: 'local:ghost-duel:v1',
    );
    final responseMs = command.responseTimeMs!;
    final correct = command.isCorrect;
    setState(() => _saving = true);
    try {
      if (!await _ownerCurrent()) return;
      await _learning!.recordAnswer(
        sessionId: command.sessionId,
        wordId: command.wordId,
        promptMode: command.promptMode,
        isCorrect: correct,
        responseTimeMs: responseMs,
        attemptNumber: command.attemptNumber,
        providerProvenance: command.providerProvenance,
        attemptId: command.id,
        occurredAtUtc: command.occurredAtUtc,
      );
      if (!await _ownerCurrent()) return;
      final turn = GhostShadowDuelService.evaluateTurn(
        playerResponseTimeMs: responseMs.toDouble(),
        isCorrect: correct,
        snapshot: data.snapshot,
      );
      if (!mounted) return;
      setState(() {
        _answer.clear();
        _pendingAnswer = null;
        _submittedText = null;
        _saveError = null;
        if (turn.playerHitGhost) {
          _ghostHp = (_ghostHp - turn.damageDealt).clamp(
            0,
            data.opponent.maxHp,
          );
          _log.insert(
            0,
            '${question.word.spelling}: ถูก · $responseMs มิลลิวินาที · สร้างความเสียหาย ${turn.damageDealt}',
          );
        } else {
          _playerHp = (_playerHp - 15).clamp(0, 100);
          _log.insert(
            0,
            '${question.word.spelling}: ผิด · $responseMs มิลลิวินาที',
          );
        }
        _index += 1;
        _finished =
            _ghostHp == 0 ||
            _playerHp == 0 ||
            _index >= data.session.questions.length;
        _stopwatch
          ..reset()
          ..start();
      });
    } catch (_) {
      if (await _ownerCurrent() && mounted) {
        setState(
          () => _saveError = 'ยังยืนยันการบันทึกคำตอบไม่ได้ กรุณาลองอีกครั้ง',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _closeSession(String sessionId) async {
    if (_sessionClosed || _saving || !_finished || _invalid) return;
    setState(() => _saving = true);
    try {
      if (!await _ownerCurrent() || !mounted) return;
      final summary = await _learning!.finishSession(sessionId);
      if (!await _ownerCurrent() || !mounted) return;
      if (summary.id != sessionId || summary.state != 'completed') {
        throw StateError('unconfirmed session result');
      }
      setState(() {
        _summary = summary;
        _sessionClosed = true;
        _finishError = null;
      });
    } catch (_) {
      if (await _ownerCurrent() && mounted) {
        setState(
          () => _finishError = 'ยังยืนยันผลรอบนี้ไม่ได้ กรุณาลองอีกครั้ง',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openWeakness(FieldFeatureRegistry features) async {
    if (_saving || !_sessionClosed || _invalid) return;
    setState(() => _saving = true);
    try {
      if (!await _ownerCurrent() || !mounted) return;
      await AppNavigator.pushPage<void>(
        context,
        AppPage<void>(
          name: 'learning/ghost-weakness',
          builder: (_) => WeaknessClinicScreen(
            loader: () async {
              if (!await _ownerCurrent()) {
                throw StateError('duel owner changed');
              }
              final progress = await _progressLoader!();
              if (!await _ownerCurrent()) {
                throw StateError('duel owner changed');
              }
              return progress;
            },
            learning: _learning,
            featureRegistry: features,
          ),
        ),
      );
      if (mounted) await _ownerCurrent();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _answer.dispose();
    super.dispose();
  }

  Widget _exitMessage(String message, {bool liveRegion = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: liveRegion,
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('กลับไปเลือกกิจกรรม'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final features =
        widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.fieldFeatures;
    return Scaffold(
      appBar: AppBar(title: const Text('ดวลกับสถิติเดิม')),
      body: AdaptiveContentPane(
        child: _invalid
            ? _exitMessage(
                'บริบทการเรียนเปลี่ยนหรือไม่พร้อม กรุณาเปิดกิจกรรมใหม่\nคำตอบที่ส่งไปแล้วอาจบันทึกแล้ว',
                liveRegion: true,
              )
            : FutureBuilder<_DuelData>(
                future: _load,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _exitMessage(
                      'ไม่สามารถอ่านประวัติการเรียนได้',
                      liveRegion: true,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'กำลังเตรียมสถิติเดิม',
                      ),
                    );
                  }
                  final data = snapshot.data!;
                  if (data.session.isEmpty) {
                    return Center(
                      child: Text(
                        'ยังไม่มีจุดอ่อนจากคำตอบจริงสำหรับเริ่มเกม\n'
                        'คำนวณจาก ${data.progress.sampleSize} คำตอบ',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final question = _finished
                      ? null
                      : data.session.questions[_index];
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
                                semanticsLabel:
                                    'พลังของสถิติเดิม $_ghostHp จาก ${data.opponent.maxHp}',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'คำนวณจาก ${data.progress.sampleSize} คำตอบ · '
                                'ความแม่นยำ ${((data.progress.accuracy ?? 0) * 100).round()}% · '
                                'เวลาเฉลี่ย ${data.snapshot.avgResponseTimeMs.round()} มิลลิวินาที',
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
                          enabled: !_saving && _pendingAnswer == null,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'พิมพ์คำศัพท์ภาษาอังกฤษ',
                          ),
                          onSubmitted: (_) => _submit(data),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: _saving ? null : () => _submit(data),
                          child: Text(
                            _saving
                                ? 'กำลังบันทึก'
                                : _pendingAnswer != null
                                ? 'ลองบันทึกคำตอบอีกครั้ง'
                                : 'ตอบ',
                          ),
                        ),
                        if (_pendingAnswer != null)
                          Text('คำตอบที่รอยืนยัน: $_submittedText'),
                        if (_saveError != null)
                          Semantics(liveRegion: true, child: Text(_saveError!)),
                      ] else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_summary != null) ...[
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  'บันทึกผลรอบนี้แล้ว',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                'ตอบถูก ${_summary!.correctCount} · ตอบผิด ${_summary!.wrongCount} · รวม ${_summary!.correctCount + _summary!.wrongCount} คำตอบ',
                              ),
                              if (features != null &&
                                  features.isVisible(FieldFeature.weakness) &&
                                  _learning != null &&
                                  _progressLoader != null)
                                FilledButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _openWeakness(features),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  child: const Text('ฝึกคำที่ผิดจากประวัติ'),
                                ),
                            ] else ...[
                              FilledButton(
                                onPressed: _saving
                                    ? null
                                    : () => _closeSession(data.session.id),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: Text(
                                  _saving
                                      ? 'กำลังบันทึกผลรอบ'
                                      : _finishError == null
                                      ? 'จบรอบและบันทึกผล'
                                      : 'ลองบันทึกผลรอบอีกครั้ง',
                                ),
                              ),
                              if (_finishError != null)
                                Semantics(
                                  liveRegion: true,
                                  child: Text(_finishError!),
                                ),
                            ],
                          ],
                        ),
                      if (_log.isNotEmpty)
                        Semantics(
                          liveRegion: true,
                          child: const Text('บันทึกคำตอบแล้ว'),
                        ),
                      const SizedBox(height: 16),
                      for (final entry in _log) ListTile(title: Text(entry)),
                    ],
                  );
                },
              ),
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
