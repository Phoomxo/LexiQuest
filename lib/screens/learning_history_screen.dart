import 'dart:convert';
import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../features/assessment/domain/assessment_models.dart';
import '../features/history/application/learning_history_use_cases.dart';
import '../features/history/domain/learning_history_models.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/pair_matching/domain/pair_matching_history_projection.dart';
import '../features/learning/pair_matching/domain/pair_matching_launch.dart';
import '../navigation/navigation_glossary.dart';

typedef LearningHistoryReplayOperationIdGenerator = String Function();
typedef PairHistoryReplayCallback =
    Future<void> Function(
      PairMatchingHistoryProjection source,
      String replayOperationId,
    );

String _defaultReplayOperationId() => 'history-replay:${const Uuid().v4()}';

/// G1 f43 read-only surface. f42 remains the sole future production parent.
final class LearningHistoryScreen extends StatefulWidget {
  const LearningHistoryScreen({
    super.key,
    required this.useCases,
    this.generateReplayOperationId = _defaultReplayOperationId,
    this.onPairReplay,
  });

  final LearningHistoryUseCases useCases;
  final LearningHistoryReplayOperationIdGenerator generateReplayOperationId;
  final PairHistoryReplayCallback? onPairReplay;

  @override
  State<LearningHistoryScreen> createState() => _LearningHistoryScreenState();
}

final class _LearningHistoryScreenState extends State<LearningHistoryScreen> {
  late Future<_HistoryPage> _load;
  String? _openingSessionId;
  final Map<String, String> _pendingReplayOperationIdsBySource =
      <String, String>{};

  @override
  void initState() {
    super.initState();
    _load = _loadHistory();
  }

  void _retryLoad() {
    final next = _loadHistory();
    setState(() {
      _load = next;
    });
  }

  Future<_HistoryPage> _loadHistory() async {
    final entries = await widget.useCases.load();
    final pairSessionIds = entries
        .where((entry) => entry.mode == LessonMode.matching)
        .map((entry) => entry.sessionId)
        .toList(growable: false);
    if (pairSessionIds.isEmpty) {
      return _HistoryPage(entries: entries);
    }
    try {
      final projections = await widget.useCases.loadPairResults(pairSessionIds);
      return _HistoryPage(entries: entries, pairResults: projections);
    } on Object {
      return _HistoryPage(entries: entries, pairReadFailed: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          NavigationGlossary.require('home/today/history').fullThaiLabel,
        ),
      ),
      body: FutureBuilder<_HistoryPage>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _HistoryMessage(
              semanticsLabel: 'โหลดประวัติการเรียนไม่สำเร็จ',
              message: 'ไม่สามารถโหลดประวัติการเรียนได้',
              action: FilledButton.icon(
                onPressed: _retryLoad,
                icon: const Icon(Icons.refresh),
                label: const Text('ลองอีกครั้ง'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(
              child: Semantics(
                label: 'กำลังโหลดประวัติการเรียน',
                child: const CircularProgressIndicator(),
              ),
            );
          }
          final page = snapshot.data!;
          final entries = page.entries;
          if (entries.isEmpty) {
            return const _HistoryMessage(
              semanticsLabel: 'ประวัติการเรียนว่าง',
              message: 'ยังไม่มีประวัติการเรียน',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final pairResult = page.pairResults[entry.sessionId];
              final pairEntry =
                  pairResult != null ||
                  entry.pairSummary != null ||
                  entry.pairPurposeUnavailable;
              if (pairEntry) {
                return MenuActionBinding(
                  id: 'history/session/$index',
                  label: 'Pair Matching history ${index + 1}',
                  ownerId: entry.ownerId,
                  onInvoke: null,
                  readValue: _pairHistoryAssistance(
                    entry,
                    page.pairReadFailed ? null : pairResult,
                  ),
                  child: _PairHistoryCard(
                    key: ValueKey('pair-history-${entry.sessionId}'),
                    entry: entry,
                    result: pairResult,
                    sourceEntry: entries
                        .where(
                          (candidate) =>
                              candidate.sessionId ==
                              pairResult?.sourceSessionId,
                        )
                        .firstOrNull,
                    overview: page.pairOverview,
                    pairReadFailed: page.pairReadFailed,
                    opening: _openingSessionId == entry.sessionId,
                    replayEnabled:
                        pairResult?.result.stars != null &&
                        widget.onPairReplay != null &&
                        _openingSessionId == null,
                    onReplay: pairResult == null
                        ? null
                        : () => _replayPair(pairResult),
                  ),
                );
              }
              return MenuActionBinding(
                id: 'history/session/$index',
                label: 'ข้อมูลประวัติการเรียนรายการที่ ${index + 1}',
                ownerId: entry.ownerId,
                onInvoke: null,
                readValue: _historyAssistance(entry),
                child: _HistoryCard(
                  key: ValueKey('learning-history-${entry.sessionId}'),
                  entry: entry,
                  opening: _openingSessionId == entry.sessionId,
                  replayEnabled:
                      _openingSessionId == null &&
                      entry.contentAvailability ==
                          LearningHistoryContentAvailability.available,
                  onReplay: () => _replay(entry),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _replay(LearningHistoryEntry entry) async {
    if (_openingSessionId != null ||
        entry.contentAvailability !=
            LearningHistoryContentAvailability.available) {
      return;
    }
    final operationId =
        _pendingReplayOperationIdsBySource[entry.sessionId] ??
        widget.generateReplayOperationId();
    setState(() {
      _openingSessionId = entry.sessionId;
      _pendingReplayOperationIdsBySource[entry.sessionId] = operationId;
    });
    var acknowledged = false;
    try {
      await widget.useCases.replayAsNewSession(
        entry.sessionId,
        replayOperationId: operationId,
      );
      acknowledged = true;
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเริ่มเซสชันใหม่ได้')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingSessionId = null;
          if (acknowledged) {
            _pendingReplayOperationIdsBySource.remove(entry.sessionId);
          }
        });
      }
    }
  }

  Future<void> _replayPair(PairMatchingHistoryProjection source) async {
    final callback = widget.onPairReplay;
    if (callback == null ||
        source.result.stars == null ||
        _openingSessionId != null) {
      return;
    }
    final operationId =
        _pendingReplayOperationIdsBySource[source.sessionId] ??
        widget.generateReplayOperationId();
    setState(() {
      _openingSessionId = source.sessionId;
      _pendingReplayOperationIdsBySource[source.sessionId] = operationId;
    });
    var acknowledged = false;
    try {
      await callback(source, operationId);
      acknowledged = true;
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถเริ่มการฝึกซ้ำได้')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingSessionId = null;
          if (acknowledged) {
            _pendingReplayOperationIdsBySource.remove(source.sessionId);
          }
        });
      }
    }
  }
}

final class _HistoryPage {
  _HistoryPage({
    required Iterable<LearningHistoryEntry> entries,
    Iterable<PairMatchingHistoryProjection> pairResults = const [],
    this.pairReadFailed = false,
  }) : entries = List<LearningHistoryEntry>.unmodifiable(entries),
       pairResults = Map<String, PairMatchingHistoryProjection>.unmodifiable({
         for (final result in pairResults) result.sessionId: result,
       }),
       pairOverview = PairMatchingHistoryOverview(pairResults);

  final List<LearningHistoryEntry> entries;
  final Map<String, PairMatchingHistoryProjection> pairResults;
  final PairMatchingHistoryOverview pairOverview;
  final bool pairReadFailed;
}

final class _PairHistoryCard extends StatelessWidget {
  const _PairHistoryCard({
    super.key,
    required this.entry,
    required this.result,
    this.sourceEntry,
    required this.overview,
    required this.pairReadFailed,
    required this.opening,
    required this.replayEnabled,
    required this.onReplay,
  });

  final LearningHistoryEntry entry;
  final PairMatchingHistoryProjection? result;
  final LearningHistoryEntry? sourceEntry;
  final PairMatchingHistoryOverview overview;
  final bool pairReadFailed;
  final bool opening;
  final bool replayEnabled;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    final english = Localizations.localeOf(context).languageCode == 'en';
    String copy(String thai, String englishCopy) =>
        english ? englishCopy : thai;
    final status = _terminalPresentation(entry.terminalState);
    final packTitle =
        entry.packTitle ??
        (result != null && entry.packIdentity == null
            ? copy('ชุดคำที่บันทึกไว้', 'Saved word set')
            : copy(
                'เนื้อหาที่บันทึกไว้ไม่พร้อมใช้งาน',
                'Saved content is unavailable',
              ));
    final projection = result;
    final stopped =
        !pairReadFailed &&
        entry.terminalState == LearningHistoryTerminalState.abandoned &&
        entry.pairSummary != null;
    final replay = projection?.purpose == PairSessionPurpose.practiceReplay;
    final heading = stopped
        ? copy('รอบจับคู่หยุดก่อนจบ', 'Pair Matching stopped before completion')
        : projection == null
        ? copy('ผลจับคู่ไม่พร้อมใช้งาน', 'Pair Matching result unavailable')
        : replay
        ? copy('ผลการฝึกซ้ำ', 'Practice Replay result')
        : copy('ผลการจับคู่', 'Pair Matching result');
    final badges = projection == null
        ? const <String>[]
        : _overviewBadges(projection, overview, english: english);
    final actionLabel = opening
        ? copy('กำลังเริ่มการฝึกซ้ำ', 'Starting Practice Replay')
        : replayEnabled
        ? copy('ฝึกซ้ำชุดเดิม', 'Practice Replay')
        : copy('การฝึกซ้ำไม่พร้อมใช้งาน', 'Practice Replay unavailable');
    final unavailable = projection == null || pairReadFailed;

    return Semantics(
      container: true,
      label: '${status.label}, $packTitle, $heading',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(status.icon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.label,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Semantics(
                header: true,
                child: Text(
                  heading,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 4),
              Text(packTitle),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  copy(
                    'เปรียบเทียบเฉพาะรายการที่โหลดในหน้านี้',
                    'Comparisons cover only results loaded on this page.',
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final badge in badges) Chip(label: Text(badge)),
                  ],
                ),
              ],
              if (projection != null) ...[
                const SizedBox(height: 8),
                Text(
                  copy(
                    'คำตอบครั้งแรก ${projection.firstAnswers.correct}/${projection.firstAnswers.total}',
                    'First answers ${projection.firstAnswers.correct}/${projection.firstAnswers.total}',
                  ),
                ),
                if (projection.repairAnswers.total > 0)
                  Text(
                    copy(
                      'ฝึกซ้ำแก้คำตอบ ${projection.repairAnswers.correct}/${projection.repairAnswers.total}',
                      'Repair practice ${projection.repairAnswers.correct}/${projection.repairAnswers.total}',
                    ),
                  ),
                Text(
                  copy(
                    'จับคู่แล้ว ${projection.result.matched} คู่',
                    'Matched ${projection.result.matched} pairs',
                  ),
                ),
                Text(
                  copy(
                    'ทำได้เอง ${projection.result.independent} คู่',
                    'Independent ${projection.result.independent} pairs',
                  ),
                ),
                Text(
                  copy(
                    'ใช้ตัวช่วย ${projection.result.assisted} คู่',
                    'Assisted ${projection.result.assisted} pairs',
                  ),
                ),
                Text(
                  projection.result.stars == null
                      ? copy('ยังไม่มีผลดาว', 'Not scored')
                      : copy(
                          'ดาว ${projection.result.stars}/3',
                          'Stars ${projection.result.stars}/3',
                        ),
                ),
                Text(_pairElapsedLabel(projection, english: english)),
                if (replay) ...[
                  Text(
                    copy(
                      sourceEntry == null
                          ? 'ฝึกซ้ำจากรอบต้นทางที่เลือกไว้'
                          : 'รอบต้นทาง: ${sourceEntry!.packTitle ?? 'ชุดคำที่บันทึกไว้'} • ${MaterialLocalizations.of(context).formatCompactDate(sourceEntry!.startedAtUtc.toLocal())}',
                      sourceEntry == null
                          ? 'Practice Replay of the selected source session'
                          : 'Source session: ${sourceEntry!.packTitle ?? 'Saved word set'} • ${MaterialLocalizations.of(context).formatCompactDate(sourceEntry!.startedAtUtc.toLocal())}',
                    ),
                  ),
                  Text(
                    copy(
                      'รอบฝึกซ้ำไม่เพิ่มความก้าวหน้าหรือรางวัล',
                      'Practice Replay does not add progress or rewards',
                    ),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  copy(
                    stopped
                        ? 'รอบนี้ยังไม่จบ จึงไม่มีผลดาวหรือการฝึกซ้ำ'
                        : 'ไม่สามารถยืนยันผลจับคู่จากข้อมูลที่บันทึกไว้ได้',
                    stopped
                        ? 'This session is incomplete and has no star result or Practice Replay.'
                        : 'The saved Pair Matching result could not be verified',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                copy(
                  'การฝึกซ้ำเป็นโหมดฝึก และไม่เพิ่มความก้าวหน้าหรือรางวัล',
                  'Practice Replay is practice-only and does not add progress or rewards',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: ValueKey('pair-replay-history-${entry.sessionId}'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: !unavailable && replayEnabled ? onReplay : null,
                icon: opening
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.replay),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<String> _overviewBadges(
  PairMatchingHistoryProjection result,
  PairMatchingHistoryOverview overview, {
  required bool english,
}) {
  String copy(String thai, String englishCopy) => english ? englishCopy : thai;
  final badges = <String>[];
  if (result.purpose == PairSessionPurpose.learning) {
    if (overview.latestNormal?.sessionId == result.sessionId) {
      badges.add(copy('รอบปกติล่าสุด', 'Latest normal result'));
    }
    if (overview.bestNormal?.sessionId == result.sessionId) {
      badges.add(copy('รอบปกติดีที่สุด', 'Best normal result'));
    }
  } else {
    final source = result.sourceSessionId!;
    if (overview.latestReplayFor(source)?.sessionId == result.sessionId) {
      badges.add(
        copy('ฝึกซ้ำล่าสุดของต้นทางนี้', 'Latest replay for this source'),
      );
    }
    if (overview.bestReplayFor(source)?.sessionId == result.sessionId) {
      badges.add(
        copy('ฝึกซ้ำดีที่สุดของต้นทางนี้', 'Best replay for this source'),
      );
    }
  }
  return List<String>.unmodifiable(badges);
}

String _pairElapsedLabel(
  PairMatchingHistoryProjection result, {
  required bool english,
}) {
  final elapsed = result.timer.interactiveElapsedMs;
  if (elapsed == null) {
    return english
        ? 'Full interactive duration unavailable'
        : 'ไม่มีข้อมูลเวลาเรียนจริงครบทั้งรอบ';
  }
  final seconds = elapsed ~/ 1000;
  return english
      ? 'Full interactive duration $seconds seconds'
      : 'เวลาเรียนจริงทั้งรอบ $seconds วินาที';
}

String _pairHistoryAssistance(
  LearningHistoryEntry entry,
  PairMatchingHistoryProjection? result,
) => jsonEncode({
  'scope': 'one-displayed-session-not-overall-proficiency',
  'mode': 'matching',
  'state': entry.terminalState.name,
  'resultAvailable': result != null,
  'replayAddsProgressOrRewards': false,
  if (result != null) ...{
    'purpose': result.purpose.name,
    'firstAnswers': {
      'correct': result.firstAnswers.correct,
      'total': result.firstAnswers.total,
    },
    'repairAnswers': {
      'correct': result.repairAnswers.correct,
      'total': result.repairAnswers.total,
    },
    'matched': result.result.matched,
    'independent': result.result.independent,
    'assisted': result.result.assisted,
    'stars': result.result.stars,
    'interactiveElapsedMs': result.timer.interactiveElapsedMs,
  },
});

String? _historyInterpretation(LessonMode? mode) => switch (mode) {
  LessonMode.flashcard => 'บัตรคำใช้การประเมินความจำด้วยตนเอง ไม่ใช่คะแนนสอบ',
  LessonMode.meaningQuiz ||
  LessonMode.definitionQuiz => 'กิจกรรมเลือกจำแนกคำตอบจากตัวเลือก',
  LessonMode.cloze => 'กิจกรรมตอบคำถามจากบริบทของประโยค',
  LessonMode.associativeReading =>
    'การอ่านเป็นการสัมผัสภาษา ไม่ใช่คะแนนความถูกต้อง',
  _ => null,
};

String _historyAssistance(LearningHistoryEntry entry) => jsonEncode({
  'scope': 'one-displayed-session-not-overall-proficiency',
  'mode': entry.mode?.name,
  'state': entry.terminalState.name,
  'activeSeconds': entry.activeLearningDuration.inSeconds,
  if (entry.assessmentSummary == null) ...{
    'firstAnswers': {
      'correct': entry.firstAnswers.correct,
      'total': entry.firstAnswers.total,
    },
    'repairAnswers': {
      'correct': entry.repairAnswers.correct,
      'total': entry.repairAnswers.total,
    },
    'interpretation': _historyInterpretation(entry.mode),
    'localCefrMetadataUnavailable': entry.localCefrPresentation != null,
  } else ...{
    'assessmentPhase': entry.assessmentSummary!.phase.name,
    'assessmentCorrect': entry.assessmentSummary!.correctCount,
    'assessmentSampleSize': entry.assessmentSummary!.sampleSize,
  },
});

final class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    super.key,
    required this.entry,
    required this.opening,
    required this.replayEnabled,
    required this.onReplay,
  });

  final LearningHistoryEntry entry;
  final bool opening;
  final bool replayEnabled;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    final status = _terminalPresentation(entry.terminalState);
    final assessment = entry.assessmentSummary;
    final localCefr = entry.localCefrPresentation;
    final packTitle = assessment == null
        ? entry.packTitle ??
              localCefr?.titleThai ??
              'เนื้อหาที่บันทึกไว้ไม่พร้อมใช้งาน'
        : 'แบบประเมินผลการเรียน';
    final modeLabel = _modeLabel(entry.mode);
    final durationLabel = _durationLabel(entry.activeLearningDuration);
    final assessmentPhaseLabel = assessment == null
        ? null
        : _assessmentPhaseLabel(assessment.phase);
    final assessmentOutcomeLabel = assessment == null
        ? null
        : _assessmentOutcomeLabel(assessment);
    final semanticsLabel = assessment == null
        ? '${status.label}, $packTitle, $modeLabel, $durationLabel'
        : '${status.label}, $packTitle, $assessmentPhaseLabel, '
              'เครื่องมือเวอร์ชัน ${assessment.instrumentVersion}, '
              'แบบฟอร์มเวอร์ชัน ${assessment.formVersion}, '
              '$assessmentOutcomeLabel, '
              'สิ้นสุด ${assessment.terminalAtUtc.toIso8601String()}';
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(status.icon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.label,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(packTitle, style: Theme.of(context).textTheme.titleMedium),
              if (localCefr != null) ...[
                const SizedBox(height: 8),
                Text(localCefr.detailThai),
              ],
              const SizedBox(height: 4),
              if (assessment == null) ...[
                Text(modeLabel),
                Text(
                  entry.firstAnswers.total == 0
                      ? 'ยังไม่มีคำตอบครั้งแรกที่ใช้คำนวณความถูกต้อง'
                      : 'คำตอบครั้งแรก ${entry.firstAnswers.correct}/${entry.firstAnswers.total}',
                ),
                if (entry.repairAnswers.total > 0)
                  Text(
                    'ฝึกซ้ำแก้คำตอบ ${entry.repairAnswers.correct}/${entry.repairAnswers.total}',
                  ),
                if (_historyInterpretation(entry.mode) case final explanation?)
                  Text(explanation),
                const SizedBox(height: 4),
                Text(durationLabel),
              ] else ...[
                Text(assessmentPhaseLabel!),
                const SizedBox(height: 4),
                Text('เครื่องมือเวอร์ชัน ${assessment.instrumentVersion}'),
                Text('แบบฟอร์มเวอร์ชัน ${assessment.formVersion}'),
                const SizedBox(height: 4),
                Text(assessmentOutcomeLabel!),
                const SizedBox(height: 4),
                Text('สิ้นสุด ${assessment.terminalAtUtc.toIso8601String()}'),
              ],
              if (entry.contentAvailability ==
                  LearningHistoryContentAvailability.available) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: ValueKey('replay-history-${entry.sessionId}'),
                  onPressed: replayEnabled ? onReplay : null,
                  icon: opening
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.replay),
                  label: Text(
                    opening ? 'กำลังเริ่มเซสชันใหม่' : 'เรียนอีกครั้ง',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.semanticsLabel,
    required this.message,
    this.action,
  });

  final String semanticsLabel;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticsLabel,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

({IconData icon, String label}) _terminalPresentation(
  LearningHistoryTerminalState state,
) => switch (state) {
  LearningHistoryTerminalState.completed => (
    icon: Icons.check_circle_outline,
    label: 'เสร็จสิ้น',
  ),
  LearningHistoryTerminalState.abandoned => (
    icon: Icons.cancel_outlined,
    label: 'ละทิ้ง',
  ),
};

String _modeLabel(LessonMode? mode) => switch (mode) {
  LessonMode.associativeReading => 'การอ่านเชื่อมโยง',
  LessonMode.meaningQuiz => 'แบบทดสอบความหมาย',
  LessonMode.typedRecall => 'พิมพ์คำตอบ',
  LessonMode.definitionQuiz => 'แบบทดสอบคำจำกัดความ',
  LessonMode.cloze => 'เติมคำในช่องว่าง',
  LessonMode.matching => 'จับคู่คำศัพท์',
  LessonMode.flashcard => 'บัตรคำ SRS',
  LessonMode.handwritingScratchpad => 'ฝึกเขียนคำศัพท์',
  LessonMode.dictation => 'ฟังแล้วพิมพ์',
  LessonMode.speaking => 'ฝึกพูด',
  LessonMode.shadowing => 'ฝึกพูดตาม',
  LessonMode.cefrReading => 'อ่านตามระดับ CEFR',
  LessonMode.sentenceScramble => 'เรียงประโยค',
  LessonMode.wordScramble => 'เรียงตัวอักษร',
  null => 'กิจกรรมการเรียนที่บันทึกไว้',
};

String _durationLabel(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds < 60) return 'เวลาฝึกจริง $seconds วินาที';
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  if (remainingSeconds == 0) return 'เวลาฝึกจริง $minutes นาที';
  return 'เวลาฝึกจริง $minutes นาที $remainingSeconds วินาที';
}

String _assessmentPhaseLabel(AssessmentPhase phase) => switch (phase) {
  AssessmentPhase.pre => 'แบบประเมินก่อนเรียน',
  AssessmentPhase.post => 'แบบประเมินหลังเรียน',
};

String _assessmentOutcomeLabel(LearningHistoryAssessmentSummary summary) {
  final accuracy = (summary.accuracy * 100).toStringAsFixed(0);
  return 'ผลลัพธ์ ${summary.correctCount} จาก ${summary.sampleSize} ข้อ '
      '($accuracy%)';
}
