import 'package:flutter/material.dart';

import '../features/progress/domain/learning_calendar.dart';
import '../widgets/learning_summary_card.dart';

typedef LearningCalendarLoader = Future<LearningCalendarSnapshot> Function();

/// f25's standalone, local read-model surface.
///
/// This screen intentionally has no production navigation registration. f36
/// owns the later parent composition and must keep this capability off until
/// its integration contract is met.
final class LearningCalendarScreen extends StatefulWidget {
  const LearningCalendarScreen({super.key, required this.loader});

  final LearningCalendarLoader loader;

  @override
  State<LearningCalendarScreen> createState() => _LearningCalendarScreenState();
}

final class _LearningCalendarScreenState extends State<LearningCalendarScreen> {
  late final Future<LearningCalendarSnapshot> _calendar = widget.loader();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ปฏิทินการเรียน')),
      body: FutureBuilder<LearningCalendarSnapshot>(
        future: _calendar,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'ไม่สามารถอ่านข้อมูลการเรียนในเครื่องได้',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _LearningCalendarBody(snapshot.data!);
        },
      ),
    );
  }
}

final class _LearningCalendarBody extends StatelessWidget {
  const _LearningCalendarBody(this.calendar);

  final LearningCalendarSnapshot calendar;

  @override
  Widget build(BuildContext context) {
    final weekly = calendar.weekly;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          header: true,
          child: Text(
            'สรุปสัปดาห์ ${_formatDay(calendar.weekStart)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          container: true,
          label: 'แกนความพยายาม',
          explicitChildNodes: true,
          child: _AxisCard(
            title: 'ความพยายาม (เวลาที่เรียนจริง)',
            value: _formatDuration(weekly.effort.activeDuration),
            detail: 'รวมจากช่วงเวลาที่บันทึกว่าผู้เรียนทำกิจกรรมจริง',
          ),
        ),
        Semantics(
          container: true,
          label: 'แกนความแม่นยำ',
          explicitChildNodes: true,
          child: _AxisCard(
            title: 'ความแม่นยำ',
            value: weekly.accuracy.accuracy == null
                ? null
                : '${(weekly.accuracy.accuracy! * 100).toStringAsFixed(0)}%',
            caption: _formatAccuracy(weekly.accuracy),
            detail: 'นับเฉพาะคำตอบการเรียน ไม่รวมผลประเมิน',
          ),
        ),
        Semantics(
          container: true,
          label: 'แกนการกระจายทักษะ',
          explicitChildNodes: true,
          child: _SkillDistributionCard(weekly.skillDistribution),
        ),
        Semantics(
          container: true,
          label: 'แกนแนวโน้มความแม่นยำ',
          explicitChildNodes: true,
          child: _AccuracyTrendCard(weekly.accuracyTrend),
        ),
        const SizedBox(height: 12),
        Text('รายวัน', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final day in calendar.days)
          Card(
            child: ListTile(
              title: Text(_formatDay(day.day)),
              subtitle: Text(
                'เวลาที่เรียนจริง ${_formatDuration(day.effort.activeDuration)} '
                '• ${_formatAccuracy(day.accuracy)}',
              ),
            ),
          ),
      ],
    );
  }
}

final class _AxisCard extends StatelessWidget {
  const _AxisCard({
    required this.title,
    required this.value,
    required this.detail,
    this.caption,
  });

  final String title;
  final String? value;
  final String detail;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LearningSummaryCard(title: title, value: value, caption: caption),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(detail),
        ),
      ],
    );
  }
}

final class _SkillDistributionCard extends StatelessWidget {
  const _SkillDistributionCard(this.skills);

  final List<LearningSkillDistribution> skills;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'การกระจายทักษะ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (skills.isEmpty)
              const Text('ยังไม่มีทักษะจากคำตอบในสัปดาห์นี้')
            else
              for (final skill in skills)
                Text(
                  '${skill.skillId}: ${_formatAccuracy(LearningAccuracyAxis(sampleSize: skill.sampleSize, correctCount: skill.correctCount))}',
                ),
          ],
        ),
      ),
    );
  }
}

final class _AccuracyTrendCard extends StatelessWidget {
  const _AccuracyTrendCard(this.trend);

  final List<LearningAccuracyTrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'แนวโน้มความแม่นยำ',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final point in trend)
              Text(
                '${_formatDay(point.day)}: ${_formatAccuracy(point.accuracy)}',
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) => '${value.inSeconds} วินาที';

String _formatAccuracy(LearningAccuracyAxis value) {
  final accuracy = value.accuracy;
  if (accuracy == null) return 'ยังไม่มีคำตอบที่นับความแม่นยำได้';
  return '${(accuracy * 100).toStringAsFixed(0)}% จาก ${value.sampleSize} คำตอบ';
}

String _formatDay(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';
