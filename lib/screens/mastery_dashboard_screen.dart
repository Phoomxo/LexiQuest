import 'package:flutter/material.dart';

import '../features/progress/domain/learning_calendar.dart';
import '../features/progress/domain/personal_learning_profile.dart';
import '../features/progress/domain/progress_models.dart';
import '../navigation/app_routes.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/app_dependencies.dart';
import '../utils/local_study_datetime.dart';
import '../widgets/learning_summary_card.dart';
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
    this.onOpenWeakness,
    this.onOpenReview,
  });

  final MasteryProfileLoader? loader;
  final OpenLearningCalendarAction? openLearningCalendar;
  final VoidCallback? onOpenWeakness;
  final VoidCallback? onOpenReview;

  @override
  State<MasteryDashboardScreen> createState() => _MasteryDashboardScreenState();
}

class _MasteryDashboardScreenState extends State<MasteryDashboardScreen> {
  Future<PersonalLearningProfile>? _load;
  AppDependencies? _dependencies;
  var _wasActive = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.valuesOf(context).enabled;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final dependencyChanged = !identical(_dependencies, dependencies);
    _dependencies = dependencies;
    if (!isActive) {
      _wasActive = false;
      return;
    }
    if (!_wasActive ||
        _load == null ||
        (widget.loader == null && dependencyChanged)) {
      _reload();
    }
    _wasActive = true;
  }

  @override
  void didUpdateWidget(MasteryDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.loader, widget.loader) &&
        TickerMode.valuesOf(context).enabled) {
      _reload();
      // A loader replacement and tab activation can occur in the same frame.
      _wasActive = true;
    }
  }

  void _reload() {
    final loader =
        widget.loader ?? _dependencies?.progress?.loadPersonalLearningProfile;
    _load = loader == null
        ? Future<PersonalLearningProfile>.error(
            StateError('personal learning profile dependency unavailable'),
          )
        : loader();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ภาพรวมการเรียน')),
      body: FutureBuilder<PersonalLearningProfile>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
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
            onOpenWeakness: widget.onOpenWeakness,
            onOpenReview: widget.onOpenReview,
            openLearningCalendar:
                widget.openLearningCalendar ?? _openLearningCalendar,
          );
        },
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody(
    this.profile, {
    required this.openLearningCalendar,
    this.onOpenWeakness,
    this.onOpenReview,
  });

  final PersonalLearningProfile profile;
  final OpenLearningCalendarAction openLearningCalendar;
  final VoidCallback? onOpenWeakness;
  final VoidCallback? onOpenReview;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _WeeklyEvidenceSummary(profile: profile),
        const SizedBox(height: 24),
        Text('สิ่งที่ควรทำต่อ', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          'คำที่เคยตอบผิดช่วยบอกจุดที่ควรฝึก ส่วนคำถึงกำหนดทบทวนมาจากตารางทบทวนเดิม',
        ),
        if (onOpenReview != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('mastery-open-review'),
            onPressed: onOpenReview,
            icon: const Icon(Icons.event_repeat),
            label: const Text('เปิดศูนย์ทบทวน'),
          ),
        ],
        if (onOpenWeakness != null) ...[
          const SizedBox(height: 12),
          Tooltip(
            message: NavigationGlossary.require('home/weakness').tooltip,
            child: Semantics(
              button: true,
              enabled: true,
              label: NavigationGlossary.require('home/weakness').semanticsLabel,
              onTap: onOpenWeakness,
              excludeSemantics: true,
              child: OutlinedButton.icon(
                key: const ValueKey('home/weakness'),
                onPressed: onOpenWeakness,
                icon: const Icon(Icons.psychology_outlined),
                label: Text(
                  NavigationGlossary.require('home/weakness').fullThaiLabel,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (profile.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'ยังไม่มีหลักฐานการเรียนที่เพียงพอ',
              textAlign: TextAlign.center,
            ),
          ),
        _AxisSection(
          title: 'ความชำนาญ',
          child:
              profile.mastery.availability == ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
          title: 'ทบทวนแบบเว้นระยะ',
          child: profile.srs.availability == ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
          title: 'เวลาเรียนจริง',
          child:
              profile.effort.availability == ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : _MetricRow(
                  label: 'เวลาที่ลงมือเรียนสัปดาห์นี้',
                  value: _duration(profile.effort.activeDuration),
                ),
        ),
        _AxisSection(
          title: 'ความแม่นยำ',
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
          title: 'จุดที่ควรฝึกเพิ่ม',
          child:
              profile.weakness.availability ==
                  ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : profile.weakness.items.isEmpty
              ? const Text('ไม่พบจุดอ่อนในหลักฐานปัจจุบัน')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
          title: 'ความต่อเนื่องในการเรียน',
          child:
              profile.engagement.availability ==
                  ProfileAxisAvailability.noEvidence
              ? const _NoEvidence()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MetricRow(
                      label: 'XP',
                      value: '${profile.engagement.totalXp}',
                    ),
                    _MetricRow(
                      label: 'เรียนต่อเนื่อง',
                      value: '${profile.engagement.currentStreakDays} วัน',
                    ),
                    _MetricRow(
                      label: 'ภารกิจที่สำเร็จ',
                      value: '${profile.engagement.completedQuestCount}',
                    ),
                    _MetricRow(
                      label: 'ความสำเร็จ',
                      value: '${profile.engagement.achievementCount}',
                    ),
                  ],
                ),
        ),
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

class _WeeklyEvidenceSummary extends StatelessWidget {
  const _WeeklyEvidenceSummary({required this.profile});

  final PersonalLearningProfile profile;

  @override
  Widget build(BuildContext context) {
    final accuracy = profile.accuracy;
    final calendar = profile.calendar;
    final weekEnd = calendar.weekStart.add(const Duration(days: 6));
    final period =
        '${formatStudyCalendarDate(calendar.weekStart)} – '
        '${formatStudyCalendarDate(weekEnd)}';
    final timezone = studyTimezoneLabel(calendar.timezoneId);
    final hasEvidence =
        accuracy.availability == ProfileAxisAvailability.available &&
        accuracy.sampleSize > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LearningSummaryCard(
          icon: Icons.school_outlined,
          title: hasEvidence ? 'คำตอบสัปดาห์นี้' : 'ยังไม่มีคำตอบในสัปดาห์นี้',
          value: hasEvidence
              ? '${accuracy.correctCount} / ${accuracy.sampleSize}'
              : null,
          caption: hasEvidence
              ? 'ตอบถูก ${accuracy.correctCount} จาก ${accuracy.sampleSize} คำตอบ'
              : null,
        ),
        Text(
          '$period · เวลา$timezone (${calendar.timezoneId})',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (!hasEvidence)
          const Text('เริ่มฝึกเมื่อพร้อม แล้วกลับมาดูผลได้')
        else ...<Widget>[
          Text(
            accuracy.sampleSize == 1
                ? 'มีเพียง 1 คำตอบ จึงมีข้อมูลน้อย'
                : 'คำตอบอาจมาจากกิจกรรมหลายรูปแบบ',
          ),
          const SizedBox(height: 8),
          const Text(
            'ข้อมูลนี้ยังใช้สรุปว่าจำคำศัพท์ได้เองไม่ได้ และยังไม่มีผลก่อนและหลังที่เปรียบเทียบกันได้',
          ),
        ],
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
          Text(value, style: Theme.of(context).textTheme.titleLarge),
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
          Text(skill.label),
          const SizedBox(height: 4),
          Text(
            accuracy == null
                ? 'ยังไม่มีข้อมูล'
                : '${(accuracy * 100).toStringAsFixed(0)}%',
          ),
          const SizedBox(height: 8),
          if (accuracy != null) LinearProgressIndicator(value: accuracy),
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
