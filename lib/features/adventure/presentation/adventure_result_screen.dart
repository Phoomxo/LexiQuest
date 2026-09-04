import 'package:flutter/material.dart';

import '../domain/adventure_result.dart';

final class AdventureResultScreen extends StatelessWidget {
  const AdventureResultScreen({
    super.key,
    required this.result,
    required this.onNextAction,
  });

  final AdventureResult result;
  final VoidCallback? onNextAction;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สรุปการเดินทาง · Journey summary')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _Section(
          key: const ValueKey('adventure-result-learning'),
          icon: Icons.school_outlined,
          title: 'การเรียนรู้ · Learning',
          lines: <String>[
            'ตอบถูก ${result.learning.correctCount} รายการ',
            'ควรกลับมาทบทวน ${result.learning.reviewDueCount} รายการ',
          ],
        ),
        _Section(
          key: const ValueKey('adventure-result-effort'),
          icon: Icons.timer_outlined,
          title: 'ความพยายาม · Effort',
          lines: <String>[
            'ลงมือทำ ${result.effort.completedItems} รายการ',
            'เวลาเรียนจริง ${result.effort.activeDuration.inMinutes} นาที',
          ],
        ),
        _Section(
          key: const ValueKey('adventure-result-engagement'),
          icon: Icons.favorite_outline,
          title: 'การมีส่วนร่วม · Engagement',
          lines: <String>[
            result.engagement.completedMission
                ? 'ภารกิจรอบนี้จบแล้ว เก่งที่ลงมือทำ'
                : 'หยุดพักได้ แล้วค่อยกลับมาเมื่อพร้อม',
          ],
        ),
        _rewardCard(result.reward),
        if (result.technicalMessage case final message?)
          _Section(
            key: const ValueKey('adventure-result-technical'),
            icon: Icons.info_outline,
            title: 'สถานะระบบ · Technical status',
            lines: <String>[message],
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('adventure-result-next-action'),
          onPressed: result.nextAction == AdventureNextAction.none
              ? null
              : onNextAction,
          icon: const Icon(Icons.arrow_forward),
          label: Text(_nextLabel(result.nextAction)),
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
      title: 'รางวัล · Reward',
      lines: <String>[message],
    );
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final line in lines) Text(line),
              ],
            ),
          ),
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
