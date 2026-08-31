import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../features/assessment/domain/assessment_models.dart';
import '../features/history/application/learning_history_use_cases.dart';
import '../features/history/domain/learning_history_models.dart';
import '../features/learning/domain/lesson_mode.dart';

typedef LearningHistoryReplayOperationIdGenerator = String Function();

String _defaultReplayOperationId() => 'history-replay:${const Uuid().v4()}';

/// G1 f43 read-only surface. f42 remains the sole future production parent.
final class LearningHistoryScreen extends StatefulWidget {
  const LearningHistoryScreen({
    super.key,
    required this.useCases,
    this.generateReplayOperationId = _defaultReplayOperationId,
  });

  final LearningHistoryUseCases useCases;
  final LearningHistoryReplayOperationIdGenerator generateReplayOperationId;

  @override
  State<LearningHistoryScreen> createState() => _LearningHistoryScreenState();
}

final class _LearningHistoryScreenState extends State<LearningHistoryScreen> {
  late Future<List<LearningHistoryEntry>> _load;
  String? _openingSessionId;
  final Map<String, String> _pendingReplayOperationIdsBySource =
      <String, String>{};

  @override
  void initState() {
    super.initState();
    _load = widget.useCases.load();
  }

  void _retryLoad() {
    final next = widget.useCases.load();
    setState(() {
      _load = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติการเรียน')),
      body: FutureBuilder<List<LearningHistoryEntry>>(
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
          final entries = snapshot.data!;
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
              return _HistoryCard(
                key: ValueKey('learning-history-${entry.sessionId}'),
                entry: entry,
                opening: _openingSessionId == entry.sessionId,
                replayEnabled:
                    _openingSessionId == null &&
                    entry.contentAvailability ==
                        LearningHistoryContentAvailability.available,
                onReplay: () => _replay(entry),
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
}

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
    final packTitle = assessment == null
        ? entry.packTitle ?? 'เนื้อหาที่บันทึกไว้ไม่พร้อมใช้งาน'
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
              const SizedBox(height: 4),
              if (assessment == null) ...[
                Text(modeLabel),
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
