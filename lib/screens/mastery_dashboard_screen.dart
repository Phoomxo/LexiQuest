import 'package:flutter/material.dart';

import '../features/progress/domain/learning_calendar.dart';
import '../features/progress/domain/personal_learning_profile.dart';
import '../features/progress/domain/progress_models.dart';
import '../navigation/app_routes.dart';
import '../runtime/app_dependencies.dart';
import 'learning_calendar_screen.dart';

typedef ProgressLoader = Future<ProgressSnapshot> Function();
typedef MasteryProfileLoader = Future<PersonalLearningProfile> Function();
typedef OpenLearningCalendarAction =
    Future<void> Function(
      BuildContext context,
      LearningCalendarSnapshot calendar,
    );

class MasteryDashboardScreen extends StatefulWidget {
  const MasteryDashboardScreen({
    super.key,
    this.loader,
    this.openLearningCalendar,
  });

  final MasteryProfileLoader? loader;
  final OpenLearningCalendarAction? openLearningCalendar;

  @override
  State<MasteryDashboardScreen> createState() => _MasteryDashboardScreenState();
}

class _MasteryDashboardScreenState extends State<MasteryDashboardScreen> {
  Future<PersonalLearningProfile>? _load;
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
        widget.loader ??
        AppDependenciesScope.maybeOf(
          context,
        )?.progress?.loadPersonalLearningProfile;
    _load = loader == null
        ? Future<PersonalLearningProfile>.error(
            StateError('personal learning profile dependency unavailable'),
          )
        : loader();
    _wasActive = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ภาพรวมการเรียน')),
      body: FutureBuilder<PersonalLearningProfile>(
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
          return _DashboardBody(
            snapshot.data!,
            openLearningCalendar:
                widget.openLearningCalendar ?? _openLearningCalendar,
          );
        },
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody(this.profile, {required this.openLearningCalendar});

  final PersonalLearningProfile profile;
  final OpenLearningCalendarAction openLearningCalendar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (profile.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'ยังไม่มีหลักฐานการเรียนที่เพียงพอ',
              textAlign: TextAlign.center,
            ),
          ),
        _AxisSection(
          title: 'Mastery',
          child:
              profile.mastery.availability == ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : Column(
                  children: [
                    _MetricRow(
                      label: 'คำที่ชำนาญ',
                      value: '${profile.mastery.masteredWordCount}',
                    ),
                    for (final skill in profile.mastery.skills)
                      _SkillRow(skill),
                  ],
                ),
        ),
        _AxisSection(
          title: 'SRS',
          child: profile.srs.availability == ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : Column(
                  children: [
                    _MetricRow(
                      label: 'คำที่ติดตาม',
                      value: '${profile.srs.trackedWordCount}',
                    ),
                    _MetricRow(
                      label: 'ถึงกำหนดทบทวน',
                      value: '${profile.srs.dueReviewCount}',
                    ),
                  ],
                ),
        ),
        _AxisSection(
          title: 'Effort',
          child:
              profile.effort.availability == ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : _MetricRow(
                  label: 'เวลาเรียนที่ active สัปดาห์นี้',
                  value: _duration(profile.effort.activeDuration),
                ),
        ),
        _AxisSection(
          title: 'Accuracy',
          child: profile.accuracy.value == null
              ? const _NoEvidence()
              : _MetricRow(
                  label: 'ความแม่นยำจากการฝึก',
                  value:
                      '${(profile.accuracy.value! * 100).toStringAsFixed(0)}% '
                      'จาก ${profile.accuracy.sampleSize} คำตอบ',
                ),
        ),
        _AxisSection(
          title: 'Weakness',
          child:
              profile.weakness.availability ==
                  ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : profile.weakness.items.isEmpty
              ? const Text('ไม่พบจุดอ่อนในหลักฐานปัจจุบัน')
              : Column(
                  children: [
                    for (final item in profile.weakness.items)
                      ListTile(
                        title: Text(item.spelling),
                        subtitle: Text(
                          'ตอบผิด ${item.incorrectCount} จาก '
                          '${item.sampleSize} ครั้ง',
                        ),
                      ),
                  ],
                ),
        ),
        _AxisSection(
          title: 'Engagement',
          child:
              profile.engagement.availability ==
                  ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : Column(
                  children: [
                    _MetricRow(
                      label: 'XP',
                      value: '${profile.engagement.totalXp}',
                    ),
                    _MetricRow(
                      label: 'Streak',
                      value: '${profile.engagement.currentStreakDays} วัน',
                    ),
                    _MetricRow(
                      label: 'Quest ที่สำเร็จ',
                      value: '${profile.engagement.completedQuestCount}',
                    ),
                    _MetricRow(
                      label: 'ความสำเร็จ',
                      value: '${profile.engagement.achievementCount}',
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const Key('learning-calendar-action'),
          onPressed: () => openLearningCalendar(context, profile.calendar),
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('เปิดปฏิทินการเรียน'),
        ),
      ],
    );
  }
}

class _AxisSection extends StatelessWidget {
  const _AxisSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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
    );
  }
}

class _NoEvidence extends StatelessWidget {
  const _NoEvidence();

  @override
  Widget build(BuildContext context) => const Text('ยังไม่มีหลักฐาน');
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

Future<void> _openLearningCalendar(
  BuildContext context,
  LearningCalendarSnapshot calendar,
) async {
  await AppNavigator.pushPage<void>(
    context,
    AppPage<void>(
      name: 'progress/learning-calendar',
      builder: (_) => LearningCalendarScreen(loader: () async => calendar),
    ),
  );
}

String _duration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return minutes == 0 ? '$seconds วินาที' : '$minutes นาที $seconds วินาที';
}
