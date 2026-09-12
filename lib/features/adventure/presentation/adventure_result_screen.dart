import 'package:flutter/material.dart';

import '../../../widgets/learning_summary_card.dart';
import '../domain/adventure_result.dart';

final class AdventureResultScreen extends StatelessWidget {
  const AdventureResultScreen({
    super.key,
    required this.result,
    required this.onNextAction,
    this.header,
  });

  final AdventureResult result;
  final VoidCallback? onNextAction;
  final Widget? header;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สรุปภารกิจ')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        LearningSummaryCard(
          key: const ValueKey('adventure-result-learning'),
          icon: Icons.school_outlined,
          title: 'ผลการเรียนรอบนี้',
          value: '${result.learning.correctCount}',
          caption: 'ตอบถูก ${result.learning.correctCount} รายการ',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'ควรกลับมาทบทวน ${result.learning.reviewDueCount} รายการ',
          ),
        ),
        _rewardCard(result.reward),
        FilledButton.icon(
          key: const ValueKey('adventure-result-next-action'),
          onPressed: result.nextAction == AdventureNextAction.none
              ? null
              : onNextAction,
          icon: const Icon(Icons.arrow_forward),
          label: Text(_nextLabel(result.nextAction)),
        ),
        const SizedBox(height: 24),
        if (header case final header?) ...<Widget>[
          header,
          const SizedBox(height: 12),
        ],
        _Section(
          key: const ValueKey('adventure-result-effort'),
          icon: Icons.timer_outlined,
          title: 'ความพยายาม',
          lines: <String>[
            'ลงมือทำ ${result.effort.completedItems} รายการ',
            'เวลาเรียนจริง ${result.effort.activeDuration.inMinutes} นาที ${result.effort.activeDuration.inSeconds.remainder(60)} วินาที',
            'เวลาและกิจกรรมสะท้อนความพยายาม ไม่ใช่ระดับความรู้',
          ],
        ),
        _Section(
          key: const ValueKey('adventure-result-engagement'),
          // Static reaction follows the recorded outcome. It remains readable
          // without motion/audio and cannot replay a reward or delay navigation.
          icon: result.engagement.completedMission
              ? Icons.sentiment_very_satisfied_outlined
              : Icons.sentiment_satisfied_outlined,
          title: 'การลงมือเรียน',
          lines: <String>[
            result.engagement.completedMission
                ? 'ภารกิจรอบนี้จบแล้ว เก่งที่ลงมือทำ'
                : 'หยุดพักได้ แล้วค่อยกลับมาเมื่อพร้อม',
          ],
        ),
        _motivationCard(result.motivation),
        const SizedBox(height: 12),
        ExpansionTile(
          key: const ValueKey('adventure-result-details'),
          title: const Text('รายละเอียดหลักฐานและสถานะระบบ'),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          childrenPadding: const EdgeInsets.all(16),
          children: [
            if (result.technicalMessage case final message?)
              Text(message, key: const ValueKey('adventure-result-technical')),
            if (result.reward.receiptId case final receipt?)
              Text('หลักฐานรางวัล: $receipt'),
            for (final code in [
              ...result.motivation.questCodes,
              ...result.motivation.streakCodes,
              ...result.motivation.achievementCodes,
            ])
              Text(code),
          ],
        ),
      ],
    ),
  );

  Widget _rewardCard(AdventureRewardReceiptView reward) {
    final (icon, message) = switch (reward.state) {
      AdventureCanonicalRewardState.accepted => (
        Icons.verified_outlined,
        'รางวัลหลักได้รับการยืนยันแล้ว',
      ),
      AdventureCanonicalRewardState.pending => (
        Icons.sync_outlined,
        'การเรียนบันทึกแล้ว รางวัลหลักกำลังยืนยัน',
      ),
      AdventureCanonicalRewardState.unavailable => (
        Icons.redeem_outlined,
        'ยังไม่สามารถแสดงรางวัลหลักได้',
      ),
    };
    return _Section(
      key: const ValueKey('adventure-result-reward'),
      icon: icon,
      title: 'สถานะรางวัล',
      lines: <String>[
        message,
        if (reward.state == AdventureCanonicalRewardState.accepted &&
            reward.receiptId != null &&
            reward.canonicalAmount != null)
          'รางวัลที่ยืนยันแล้ว ${reward.canonicalAmount}',
      ],
    );
  }

  Widget _motivationCard(AdventureMotivationReceiptView motivation) => _Section(
    key: const ValueKey('adventure-result-motivation'),
    icon: Icons.flag_outlined,
    title: 'ความคืบหน้าที่ตรวจสอบแล้ว',
    lines: <String>[
      if (motivation.questState == AdventureCanonicalReceiptState.committed &&
          motivation.questCodes.isNotEmpty)
        'ทำกิจกรรมตามเป้าหมายแล้ว',
      _receiptLine('ภารกิจ', motivation.questState, motivation.questCodes),
      _receiptLine(
        'ความต่อเนื่อง',
        motivation.streakState,
        motivation.streakCodes,
      ),
      _receiptLine(
        'ความสำเร็จ',
        motivation.achievementState,
        motivation.achievementCodes,
      ),
    ],
  );

  String _receiptLine(
    String label,
    AdventureCanonicalReceiptState state,
    List<String> codes,
  ) {
    final status = switch (state) {
      AdventureCanonicalReceiptState.committed => 'ยืนยันแล้ว',
      AdventureCanonicalReceiptState.pending => 'กำลังยืนยัน',
      AdventureCanonicalReceiptState.notEligible => 'ไม่มีรายการใหม่',
      AdventureCanonicalReceiptState.unavailable => 'ยังไม่พร้อมแสดง',
    };
    return '$label: $status';
  }
}

final class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ExcludeSemantics(child: Icon(icon)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          for (final line in lines) ...[const SizedBox(height: 8), Text(line)],
        ],
      ),
    ),
  );
}

String _nextLabel(AdventureNextAction action) => switch (action) {
  AdventureNextAction.reviewCenter => 'ไปศูนย์ทบทวน',
  AdventureNextAction.spacedRepetition => 'ไปทบทวนแบบเว้นระยะ',
  AdventureNextAction.none => 'เสร็จแล้ว',
};
