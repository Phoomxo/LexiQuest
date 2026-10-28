import 'package:flutter/material.dart';

import '../features/learning/domain/lesson_mode.dart';
import '../features/recommendation/application/recommendation_use_cases.dart';

typedef RecommendationActivityAction = Future<void> Function(LessonMode mode);

/// Passive f37 presentation seam. The future f42 parent owns navigation.
class RecommendationPanel extends StatefulWidget {
  const RecommendationPanel({
    super.key,
    required this.result,
    required this.onActivitySelected,
  });

  final RecommendationPanelResult result;
  final RecommendationActivityAction onActivitySelected;

  @override
  State<RecommendationPanel> createState() => _RecommendationPanelState();
}

class _RecommendationPanelState extends State<RecommendationPanel> {
  LessonMode? _busyMode;

  Future<void> _select(LessonMode mode) async {
    if (_busyMode != null) return;
    setState(() => _busyMode = mode);
    try {
      await widget.onActivitySelected(mode);
    } finally {
      if (mounted) setState(() => _busyMode = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return Semantics(
      container: true,
      label: 'คำแนะนำกิจกรรมถัดไป',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'กิจกรรมถัดไป',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_reasonLabel(result.reason)),
              const SizedBox(height: 4),
              Text(_freshnessLabel(result.freshness)),
              if (result.protocolConstraint !=
                  RecommendationProtocolConstraint.open) ...[
                const SizedBox(height: 8),
                Semantics(
                  container: true,
                  label: _protocolSemanticsLabel(result.protocolConstraint),
                  excludeSemantics: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.policy_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _protocolStatusLabel(result.protocolConstraint),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (result.availability ==
                      RecommendationResultAvailability.unavailable &&
                  result.reason !=
                      RecommendationPanelReason.noEligibleActivity) ...[
                const SizedBox(height: 12),
                const Text('ยังไม่มีกิจกรรมที่พร้อมใช้งาน'),
              ],
              if (result.recommendedMode case final mode?) ...[
                const SizedBox(height: 12),
                _ActivityButton(
                  mode: mode,
                  label: 'เริ่มกิจกรรม ${_modeLabel(mode)}',
                  busy: _busyMode != null,
                  filled: true,
                  onPressed: () => _select(mode),
                ),
              ],
              if (result.alternatives.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('เลือกกิจกรรมที่พร้อมใช้งานได้'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final mode in result.alternatives)
                      _ActivityButton(
                        mode: mode,
                        label: 'เลือกกิจกรรม ${_modeLabel(mode)}',
                        busy: _busyMode != null,
                        filled: false,
                        onPressed: () => _select(mode),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityButton extends StatelessWidget {
  const _ActivityButton({
    required this.mode,
    required this.label,
    required this.busy,
    required this.filled,
    required this.onPressed,
  });

  final LessonMode mode;
  final String label;
  final bool busy;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final action = busy ? null : onPressed;
    final child = filled
        ? FilledButton(onPressed: action, child: Text(_modeLabel(mode)))
        : OutlinedButton(onPressed: action, child: Text(_modeLabel(mode)));
    return Semantics(
      container: true,
      button: true,
      enabled: !busy,
      label: label,
      onTap: action,
      excludeSemantics: true,
      child: child,
    );
  }
}

String _reasonLabel(RecommendationPanelReason reason) => switch (reason) {
  RecommendationPanelReason.weakEvidence => 'พบคำที่ควรทบทวนจากหลักฐานการฝึก',
  RecommendationPanelReason.learnerPreference =>
    'จัดลำดับจากค่ากิจกรรมที่ผู้เรียนเลือกไว้',
  RecommendationPanelReason.learnerOverride => 'ใช้กิจกรรมที่ผู้เรียนเลือก',
  RecommendationPanelReason.staleEvidence =>
    'หลักฐานเดิมเกินช่วงที่ใช้แนะนำได้',
  RecommendationPanelReason.missingEvidence =>
    'ยังไม่มีหลักฐานเพียงพอสำหรับคำแนะนำเฉพาะบุคคล',
  RecommendationPanelReason.corruptEvidence =>
    'หลักฐานไม่สมบูรณ์ จึงไม่สร้างคำแนะนำเฉพาะบุคคล',
  RecommendationPanelReason.modeUnavailable =>
    'กิจกรรมที่เหมาะสมยังไม่พร้อมใช้งาน',
  RecommendationPanelReason.protocolLocked => 'โปรโตคอลจำกัดกิจกรรมที่เลือกได้',
  RecommendationPanelReason.canonicalAuthorityUnavailable =>
    'ยังไม่สามารถอ่านหลักฐานการเรียนได้',
  RecommendationPanelReason.noEligibleActivity =>
    'ยังไม่มีกิจกรรมที่พร้อมใช้งาน',
};

String _freshnessLabel(
  RecommendationEvidenceFreshness freshness,
) => switch (freshness) {
  RecommendationEvidenceFreshness.current => 'แนะนำจากหลักฐานที่ยังใหม่',
  RecommendationEvidenceFreshness.stale => 'หลักฐานหมดอายุสำหรับการแนะนำ',
  RecommendationEvidenceFreshness.missing => 'ไม่มีหลักฐานสำหรับอนุมานระดับ',
  RecommendationEvidenceFreshness.corrupt => 'ไม่ใช้หลักฐานที่ตรวจสอบไม่ได้',
};

String _protocolStatusLabel(RecommendationProtocolConstraint constraint) =>
    switch (constraint) {
      RecommendationProtocolConstraint.open => 'ไม่มีข้อจำกัดโปรโตคอล',
      RecommendationProtocolConstraint.constrained =>
        'โปรโตคอลจำกัดกิจกรรมไว้ในขอบเขตที่อนุญาต',
      RecommendationProtocolConstraint.overrideDenied =>
        'โปรโตคอลไม่อนุญาตกิจกรรมที่เลือก',
    };

String _protocolSemanticsLabel(RecommendationProtocolConstraint constraint) =>
    switch (constraint) {
      RecommendationProtocolConstraint.open => 'สถานะโปรโตคอล: เปิด',
      RecommendationProtocolConstraint.constrained =>
        'สถานะโปรโตคอล: จำกัดตามโปรโตคอล',
      RecommendationProtocolConstraint.overrideDenied =>
        'สถานะโปรโตคอล: ปฏิเสธการเลือก',
    };

String _modeLabel(LessonMode mode) => switch (mode) {
  LessonMode.associativeReading => 'Associative reading',
  LessonMode.meaningQuiz => 'Meaning quiz',
  LessonMode.typedRecall => 'Typed recall',
  LessonMode.definitionQuiz => 'Definition quiz',
  LessonMode.cloze => 'Cloze',
  LessonMode.matching => 'Matching',
  LessonMode.flashcard => 'Flashcard',
  LessonMode.handwritingScratchpad => 'Handwriting',
  LessonMode.dictation => 'Dictation',
  LessonMode.speaking => 'Speaking',
  LessonMode.shadowing => 'Shadowing',
  LessonMode.cefrReading => 'CEFR reading',
  LessonMode.sentenceScramble => 'Sentence scramble',
  LessonMode.wordScramble => 'Word scramble',
};
