import 'package:flutter/material.dart';

import '../features/progress/domain/progress_models.dart';
import '../runtime/app_dependencies.dart';

typedef ProgressLoader = Future<ProgressSnapshot> Function();

class MasteryDashboardScreen extends StatefulWidget {
  const MasteryDashboardScreen({super.key, this.loader});

  final ProgressLoader? loader;

  @override
  State<MasteryDashboardScreen> createState() => _MasteryDashboardScreenState();
}

class _MasteryDashboardScreenState extends State<MasteryDashboardScreen> {
  Future<ProgressSnapshot>? _load;
  var _wasActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.valuesOf(context).enabled;
    if (!isActive || (_wasActive && _load != null)) {
      _wasActive = isActive;
      return;
    }
    final loader =
        widget.loader ?? AppDependenciesScope.maybeOf(context)?.progress?.load;
    _load = loader == null
        ? Future<ProgressSnapshot>.error(
            StateError('progress dependency unavailable'),
          )
        : loader();
    _wasActive = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ภาพรวมการเรียน')),
      body: FutureBuilder<ProgressSnapshot>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _DashboardMessage(
              'ไม่สามารถอ่านประวัติการเรียนในเครื่องได้',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final progress = snapshot.data!;
          if (progress.sampleSize == 0) {
            return const _DashboardMessage(
              'ยังไม่มีคำตอบที่บันทึกไว้\nจำนวนตัวอย่าง: 0',
            );
          }
          return _DashboardBody(progress);
        },
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody(this.progress);

  final ProgressSnapshot progress;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricCard(
              label: 'ความแม่นยำ',
              value: '${((progress.accuracy ?? 0) * 100).toStringAsFixed(0)}%',
            ),
            _MetricCard(label: 'Streak', value: '${progress.streakDays} วัน'),
            _MetricCard(label: 'XP', value: '${progress.totalXp}'),
            _MetricCard(
              label: 'Session ที่จบ',
              value: '${progress.completedSessions}',
            ),
            _MetricCard(
              label: 'ถึงกำหนดทบทวน',
              value: '${progress.dueReviewCount}',
            ),
            _MetricCard(label: 'Level', value: '${progress.gameLevel}'),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'ทักษะจากหลักฐานจริง',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        ...progress.skills.map((skill) => _SkillRow(skill)),
        const SizedBox(height: 12),
        Text(
          'จำนวนตัวอย่างทั้งหมด: ${progress.sampleSize} • '
          'อัลกอริทึมเวอร์ชัน ${progress.algorithmVersion}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow(this.skill);

  final SkillEvidence skill;

  @override
  Widget build(BuildContext context) {
    final accuracy = skill.accuracy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(skill.label)),
                Text(
                  accuracy == null
                      ? 'ยังไม่มีข้อมูล'
                      : '${(accuracy * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: accuracy ?? 0),
            const SizedBox(height: 6),
            Text('จำนวนตัวอย่าง: ${skill.sampleSize}'),
          ],
        ),
      ),
    );
  }
}

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
