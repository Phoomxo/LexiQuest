import '../features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:flutter/material.dart';

import '../features/assessment/domain/assessment_models.dart';
import '../features/goals/domain/learning_goal.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/motivation/domain/streak_policy.dart';
import '../features/recommendation/application/recommendation_use_cases.dart';
import '../features/reminders/domain/study_reminder.dart';
import '../features/review/domain/review_queue_item.dart';
import '../features/today_hub/domain/today_hub_models.dart';
import '../navigation/navigation_glossary.dart';
import '../navigation/app_routes.dart';
import '../runtime/registries/feature_registry.dart';
import '../utils/local_study_datetime.dart';
import 'choose_mode_screen.dart';

abstract interface class TodayHubActionDelegate {
  Future<void> resume(LearningSessionSummary session);
  Future<void> startRecommendation(TodayHubRecommendation recommendation);
  Future<void> openReview(List<TodayHubReviewWorkItem> work);
  Future<void> openHistory();
  Future<void> startAssessment(TodayHubAssignedAssessment assessment);
  Future<void> openPlanning({required String ownerId});
}

String _activityLabel(String activity) {
  final entryId = switch (activity) {
    'quiz' || 'meaningQuiz' || 'meaning-quiz' => 'home/learn/quiz',
    'typedRecall' || 'typed-recall' => 'home/learn/quiz/typed-recall',
    'matching' => 'home/learn/quiz/matching',
    'cloze' => 'home/learn/quiz/cloze',
    'definitionQuiz' || 'definition-quiz' => 'home/learn/quiz/definition',
    'srsReview' || 'flashcard' => 'home/learn/srs',
    'associativeReading' ||
    'associative-reading' => 'home/learn/associative-reading',
    'cefrReading' || 'cefr-reading' => 'home/learn/reading/cefr',
    'dictation' => 'home/learn/quiz/dictation',
    'sentenceScramble' ||
    'sentence-scramble' => 'home/learn/quiz/sentence-scramble',
    'wordScramble' || 'word-scramble' => 'home/learn/quiz/word-scramble',
    'speaking' => 'home/learn/speech/speaking',
    'shadowing' => 'home/learn/speech/shadowing',
    'reviewCenter' => 'home/today/review',
    _ => null,
  };
  return NavigationGlossary.entries[entryId]?.fullThaiLabel ??
      'กิจกรรมการเรียนที่บันทึกไว้';
}

final class TodayHubLoading extends StatelessWidget {
  const TodayHubLoading({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: 'กำลังโหลดรายการวันนี้',
      child: const CircularProgressIndicator(),
    ),
  );
}

final class TodayHubLoadFailure extends StatelessWidget {
  const TodayHubLoadFailure({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      container: true,
      label: 'โหลดรายการวันนี้ไม่สำเร็จ',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text(
              'ไม่สามารถโหลดรายการวันนี้ได้',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('today-hub-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองอีกครั้ง'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Snapshot-only Standard renderer shared by both Today entry paths.
final class TodayHubView extends StatefulWidget {
  const TodayHubView({
    super.key,
    required this.snapshot,
    required this.actions,
    required this.features,
    required this.assessmentAvailable,
  });

  final TodayHubSnapshot snapshot;
  final TodayHubActionDelegate actions;
  final FeatureRegistry features;
  final bool assessmentAvailable;

  @override
  State<TodayHubView> createState() => _TodayHubViewState();
}

enum _Action { resume, recommendation, review, history, assessment, planning }

final class _TodayHubViewState extends State<TodayHubView> {
  final Set<_Action> _inFlight = <_Action>{};
  Listenable? _featureChanges;
  bool _reviewExpanded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _observeFeatures();
  }

  @override
  void didUpdateWidget(TodayHubView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      _reviewExpanded = false;
      _inFlight.clear();
      _generation += 1;
    }
    if (!identical(oldWidget.features, widget.features)) _observeFeatures();
  }

  void _observeFeatures() {
    _featureChanges?.removeListener(_featuresChanged);
    final next = widget.features is Listenable
        ? widget.features as Listenable
        : null;
    _featureChanges = next;
    next?.addListener(_featuresChanged);
  }

  void _featuresChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_featuresChanged);
    super.dispose();
  }

  Future<void> _run(
    _Action action,
    Future<void> Function() invoke, {
    bool Function()? allowed,
  }) async {
    if (_inFlight.contains(action) || (allowed != null && !allowed())) return;
    final generation = _generation;
    setState(() => _inFlight.add(action));
    try {
      if (allowed != null && !allowed()) return;
      await invoke();
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('ไม่สามารถเปิดรายการนี้ได้ กรุณาลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _inFlight.remove(action));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final children = <Widget>[
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const ValueKey('today-hub-manual-practice'),
          onPressed: () => AppNavigator.pushPage<void>(
            context,
            AppPage<void>(
              name: 'home/learn',
              builder: (_) =>
                  ChooseModeScreen(featureRegistry: widget.features),
            ),
          ),
          icon: const Icon(Icons.grid_view_outlined),
          label: const Text('เลือกฝึกเอง'),
        ),
      ),
    ];
    final sectionStarts = <int>{};
    for (final section in snapshot.sectionOrder) {
      final sectionStart = children.length;
      switch (section) {
        case TodayHubSectionKind.resume:
          final session = snapshot.resumableSession;
          if (session != null &&
              _dependencyReady(snapshot, TodayHubDependency.activeSession)) {
            children.add(_resumeCard(session));
          }
          _statusFor(
            children,
            TodayHubDependency.activeSession,
            'เซสชันที่ค้างอยู่ไม่พร้อมใช้งาน',
          );
        case TodayHubSectionKind.assigned:
          final assessment = snapshot.assignedAssessment;
          if (assessment != null && _assessmentEnabled(assessment)) {
            children.add(_assessmentCard(assessment));
          }
          _statusFor(
            children,
            TodayHubDependency.assessment,
            'แบบประเมินยังไม่พร้อมใช้งาน',
          );
        case TodayHubSectionKind.review:
          children.add(_reviewSummary(snapshot));
          final readyWork =
              _dependencyReady(snapshot, TodayHubDependency.review)
              ? snapshot.reviewWork
              : const <TodayHubReviewWorkItem>[];
          final work = _reviewExpanded ? readyWork : readyWork.take(3);
          children.addAll(work.map(_reviewCard));
          if (readyWork.length > 3) {
            children.add(
              TextButton.icon(
                key: const ValueKey('today-hub-expand-review'),
                onPressed: () =>
                    setState(() => _reviewExpanded = !_reviewExpanded),
                icon: Icon(
                  _reviewExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                label: Text(
                  _reviewExpanded
                      ? 'แสดงให้น้อยลง'
                      : 'ดูทั้งหมด ${snapshot.reviewWork.length} คำ',
                ),
              ),
            );
          }
          _statusFor(
            children,
            TodayHubDependency.review,
            'รายการทบทวนไม่พร้อมใช้งาน',
          );
        case TodayHubSectionKind.recommendation:
          if (snapshot.recommendation.mergedInto == null) {
            children.add(_recommendationCard(snapshot.recommendation));
          }
        case TodayHubSectionKind.planning:
          if (widget.features.isVisible(Feature.studyPlanning)) {
            if (_planningAvailable(snapshot)) {
              children.add(_planningCard(snapshot));
            }
            _statusFor(
              children,
              TodayHubDependency.goals,
              'เป้าหมายการเรียนยังไม่พร้อมใช้งาน',
            );
            _statusFor(
              children,
              TodayHubDependency.reminders,
              'ข้อมูลการเตือนยังไม่พร้อมใช้งาน',
            );
          }
        case TodayHubSectionKind.continuity:
          final streak = snapshot.gentleStreak;
          if (streak != null) {
            children.add(_streakCard(streak));
          }
          _statusFor(
            children,
            TodayHubDependency.gentleStreak,
            'ข้อมูลความต่อเนื่องยังไม่พร้อมใช้งาน',
          );
      }
      if (children.length > sectionStart) sectionStarts.add(sectionStart);
    }
    // The production reader omits review when there is no due work. Ordinary
    // Review Center access remains available independently of that section.
    if (!snapshot.sectionOrder.contains(TodayHubSectionKind.review)) {
      sectionStarts.add(children.length);
      _statusFor(
        children,
        TodayHubDependency.review,
        'รายการทบทวนไม่พร้อมใช้งาน',
      );
      children.add(_reviewSummary(snapshot));
    }
    sectionStarts.add(children.length);
    children.add(_historyAction());
    final primaryKey = switch (_primaryAction()) {
      _Action.resume => 'today-hub-resume',
      _Action.assessment => 'today-hub-assessment',
      _Action.review => 'today-hub-review-summary',
      _Action.recommendation => 'today-hub-recommendation',
      _ => null,
    };
    final primaryIndex = primaryKey == null
        ? -1
        : children.indexWhere(
            (child) => child.key == ValueKey<String>(primaryKey),
          );
    if (primaryIndex > 0) {
      final manual = children.removeAt(0);
      children.insert(primaryIndex, manual);
      final shiftedStarts = sectionStarts
          .map((index) => index <= primaryIndex ? index - 1 : index)
          .toSet();
      sectionStarts
        ..clear()
        ..addAll(shiftedStarts)
        ..add(primaryIndex)
        ..add(primaryIndex + 1);
    }
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: MenuActionListView(
            key: const ValueKey('today-hub-view'),
            padding: EdgeInsets.fromLTRB(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
              16,
              MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
              32,
            ),
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0)
                  SizedBox(height: sectionStarts.contains(index) ? 24 : 12),
                children[index],
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _statusFor(
    List<Widget> children,
    TodayHubDependency dependency,
    String label,
  ) {
    final state = widget.snapshot.dependencyStates[dependency];
    if (state == TodayHubDependencyState.stale ||
        state == TodayHubDependencyState.unavailable ||
        state == TodayHubDependencyState.corrupt) {
      children.add(_statusCard(label));
    }
  }

  Widget _resumeCard(LearningSessionSummary session) {
    final snapshot = widget.snapshot;
    final entry = NavigationGlossary.require('today-hub-resume-action');
    final onPressed = _inFlight.contains(_Action.resume)
        ? null
        : () => _run(
            _Action.resume,
            () => widget.actions.resume(session),
            allowed: () => identical(widget.snapshot, snapshot),
          );
    return Card(
      key: const ValueKey('today-hub-resume'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                'เรียนต่อจากเดิม',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(_activityLabel(session.activityType)),
            const SizedBox(height: 12),
            _glossaryAction(
              entry: entry,
              onTap: onPressed,
              child: FilledButton.icon(
                key: const ValueKey('today-hub-resume-action'),
                style: _actionStyle(_Action.resume),
                onPressed: onPressed,
                icon: Icon(entry.icon),
                label: Text(entry.fullThaiLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(TodayHubReviewWorkItem work) => Card(
    key: ValueKey('today-hub-review:${work.identity.id}'),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            work.snapshot.spelling,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(work.snapshot.meaning),
          const SizedBox(height: 8),
          for (final source in work.provenance)
            Text(
              _reviewReasonLabel(source.reason),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (work.recommendation != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _recommendationReasonLabel(work.recommendation!.reason),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );

  Widget _recommendationCard(TodayHubRecommendation recommendation) {
    final snapshot = widget.snapshot;
    if (!recommendation.isAuthoritative) {
      return _statusCard(
        _recommendationReasonLabel(recommendation.result.reason),
      );
    }
    if (!_dependencyReady(snapshot, TodayHubDependency.recommendation)) {
      return _statusCard('คำแนะนำยังไม่พร้อม');
    }
    final entry = NavigationGlossary.require('today-hub-start-recommendation');
    final onPressed = _inFlight.contains(_Action.recommendation)
        ? null
        : () => _run(
            _Action.recommendation,
            () => widget.actions.startRecommendation(recommendation),
            allowed: () =>
                identical(widget.snapshot, snapshot) &&
                recommendation.isAuthoritative,
          );
    return Card(
      key: const ValueKey('today-hub-recommendation'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                'คำแนะนำสำหรับวันนี้',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            Text(_recommendationReasonLabel(recommendation.result.reason)),
            const SizedBox(height: 12),
            _glossaryAction(
              entry: entry,
              onTap: onPressed,
              child: FilledButton.icon(
                key: const ValueKey('today-hub-start-recommendation'),
                style: _actionStyle(_Action.recommendation),
                onPressed: onPressed,
                icon: Icon(entry.icon),
                label: Text(entry.fullThaiLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _assessmentEnabled(TodayHubAssignedAssessment assessment) =>
      widget.assessmentAvailable &&
      _dependencyReady(widget.snapshot, TodayHubDependency.assessment) &&
      assessment.run.state == AssessmentRunState.active &&
      widget.features.isEnabled(Feature.researchAssessment);

  Widget _assessmentCard(TodayHubAssignedAssessment assessment) {
    final snapshot = widget.snapshot;
    final entry = NavigationGlossary.require('today-hub-assessment-action');
    final onPressed = _inFlight.contains(_Action.assessment)
        ? null
        : () => _run(
            _Action.assessment,
            () => widget.actions.startAssessment(assessment),
            allowed: () =>
                identical(widget.snapshot, snapshot) &&
                _assessmentEnabled(assessment),
          );
    return Card(
      key: const ValueKey('today-hub-assessment'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                'แบบประเมินที่ได้รับมอบหมาย',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            _glossaryAction(
              entry: entry,
              onTap: onPressed,
              child: FilledButton.icon(
                key: const ValueKey('today-hub-assessment-action'),
                style: _actionStyle(_Action.assessment),
                onPressed: onPressed,
                icon: Icon(entry.icon),
                label: Text(entry.fullThaiLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _streakCard(GentleStreakSnapshot streak) {
    final message = switch (streak.phase) {
      GentleStreakPhase.empty =>
        'เริ่มเรียนเมื่อพร้อม ค่อย ๆ สร้างความต่อเนื่องไปด้วยกัน',
      GentleStreakPhase.steady =>
        'ต่อเนื่อง ${streak.currentStreakDays} วัน พักได้เมื่อจำเป็น แล้วกลับมาเมื่อพร้อม',
      GentleStreakPhase.grace =>
        'เรียนต่อเนื่อง ${streak.currentStreakDays} วันแล้ว วันนี้พักได้ แล้วกลับมาเมื่อพร้อม',
      GentleStreakPhase.recovery =>
        'กลับมาเริ่มทีละนิดได้ ครั้งก่อนเรียนต่อเนื่อง ${streak.currentStreakDays} วัน\nเคยทำได้สูงสุด ${streak.longestStreakDays} วัน',
    };
    return Card(
      key: const ValueKey('today-hub-gentle-streak'),
      margin: EdgeInsets.zero,
      child: Semantics(
        container: true,
        label: message,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.wb_sunny_outlined),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewSummary(TodayHubSnapshot snapshot) {
    final reviewEntry = NavigationGlossary.require('today-hub-open-review');
    final openReview = _inFlight.contains(_Action.review)
        ? null
        : () => _run(
            _Action.review,
            () => widget.actions.openReview(
              _dependencyReady(snapshot, TodayHubDependency.review)
                  ? snapshot.reviewWork
                  : const <TodayHubReviewWorkItem>[],
            ),
            allowed: () => identical(widget.snapshot, snapshot),
          );
    return Column(
      key: const ValueKey('today-hub-review-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            !_dependencyReady(snapshot, TodayHubDependency.review)
                ? 'ศูนย์ทบทวน'
                : snapshot.reviewWork.isEmpty
                ? 'ยังไม่มีคำที่รอทบทวน'
                : 'รายการทบทวน ${snapshot.reviewWork.length} คำ',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 8),
        _glossaryAction(
          entry: reviewEntry,
          onTap: openReview,
          child: OutlinedButton.icon(
            key: const ValueKey('today-hub-open-review'),
            style: _actionStyle(_Action.review),
            onPressed: openReview,
            icon: Icon(reviewEntry.icon),
            label: Text(reviewEntry.fullThaiLabel),
          ),
        ),
      ],
    );
  }

  Widget _historyAction() {
    final historyEntry = NavigationGlossary.require('today-hub-open-history');
    final openHistory = _inFlight.contains(_Action.history)
        ? null
        : () => _run(_Action.history, widget.actions.openHistory);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: _glossaryAction(
        entry: historyEntry,
        onTap: openHistory,
        child: OutlinedButton.icon(
          key: const ValueKey('today-hub-open-history'),
          onPressed: openHistory,
          icon: Icon(historyEntry.icon),
          label: Text(historyEntry.fullThaiLabel),
        ),
      ),
    );
  }

  bool _dependencyReady(
    TodayHubSnapshot snapshot,
    TodayHubDependency dependency,
  ) =>
      snapshot.dependencyStates[dependency] == TodayHubDependencyState.ready ||
      snapshot.dependencyStates[dependency] == TodayHubDependencyState.empty;

  _Action? _primaryAction() {
    final snapshot = widget.snapshot;
    _Action? first;
    for (final section in snapshot.sectionOrder) {
      first = switch (section) {
        TodayHubSectionKind.resume
            when snapshot.resumableSession != null &&
                _dependencyReady(snapshot, TodayHubDependency.activeSession) =>
          _Action.resume,
        TodayHubSectionKind.assigned
            when snapshot.assignedAssessment != null &&
                _assessmentEnabled(snapshot.assignedAssessment!) =>
          _Action.assessment,
        TodayHubSectionKind.review
            when snapshot.reviewWork.isNotEmpty &&
                _dependencyReady(snapshot, TodayHubDependency.review) =>
          _Action.review,
        TodayHubSectionKind.recommendation
            when snapshot.recommendation.isAuthoritative &&
                snapshot.recommendation.mergedInto == null &&
                _dependencyReady(snapshot, TodayHubDependency.recommendation) =>
          _Action.recommendation,
        _ => null,
      };
      if (first != null) break;
    }
    return first;
  }

  ButtonStyle _actionStyle(_Action action) {
    final first = _primaryAction();
    final colors = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      foregroundColor: first == action ? colors.onPrimary : colors.primary,
      backgroundColor: first == action ? colors.primary : Colors.transparent,
      side: first == action
          ? BorderSide.none
          : BorderSide(color: colors.outlineVariant),
    );
  }

  bool _planningAvailable(TodayHubSnapshot snapshot) =>
      _dependencyReady(snapshot, TodayHubDependency.goals) ||
      _dependencyReady(snapshot, TodayHubDependency.reminders);

  Widget _planningCard(TodayHubSnapshot snapshot) {
    final goalsReady = _dependencyReady(snapshot, TodayHubDependency.goals);
    final goals = goalsReady ? snapshot.goals : const <LearningGoal>[];
    final reminders = _dependencyReady(snapshot, TodayHubDependency.reminders)
        ? snapshot.reminders
              .where((item) => item.isEnabled && !item.isDeleted)
              .toList()
        : const <StudyReminder>[];
    return Card(
      key: const ValueKey('today-hub-planning'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                goalsReady ? 'เป้าหมายของฉัน' : 'การเตือนของฉัน',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            if (goalsReady && goals.isEmpty)
              const Text('ตั้งเป้าหมายเล็ก ๆ ที่อยากทำให้ได้'),
            for (final goal in goals.take(3)) ...[
              Text(goal.title, style: Theme.of(context).textTheme.titleMedium),
              Text(
                'ครบกำหนด ${formatLocalStudyDateTime(goal.deadlineAtUtc, goal.timezone.timezoneId)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            if (goals.length > 3)
              Text('มีเป้าหมายทั้งหมด ${goals.length} รายการ'),
            if (reminders.isNotEmpty) ...[
              Text(
                'การเตือนที่ตั้งไว้',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final reminder in reminders.take(3))
                Text(
                  'เวลาแจ้งเตือนที่ตั้งไว้ ${formatLocalStudyDateTime(reminder.effectiveScheduledAtUtc, reminder.timezone.timezoneId)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Text(
                'การเตือนแต่ละรายการทำงานครั้งเดียว',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('today-hub-open-planning'),
              onPressed:
                  _inFlight.contains(_Action.planning) ||
                      !widget.features.isEnabled(Feature.studyPlanning)
                  ? null
                  : () => _run(
                      _Action.planning,
                      () => widget.actions.openPlanning(
                        ownerId: snapshot.ownerId,
                      ),
                      allowed: () =>
                          identical(widget.snapshot, snapshot) &&
                          widget.features.isEnabled(Feature.studyPlanning) &&
                          _planningAvailable(snapshot),
                    ),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('จัดการเป้าหมายและการเตือน'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glossaryAction({
    required NavigationGlossaryEntry entry,
    required VoidCallback? onTap,
    required Widget child,
  }) => Tooltip(
    message: entry.tooltip,
    child: MenuActionBinding(
      id: entry.id,
      label: entry.fullThaiLabel,
      onInvoke: onTap,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: entry.semanticsLabel,
        onTap: onTap,
        excludeSemantics: true,
        child: child,
      ),
    ),
  );

  Widget _statusCard(String message) => Card(
    margin: EdgeInsets.zero,
    child: Semantics(
      container: true,
      label: message,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}

String _reviewReasonLabel(ReviewQueueReason reason) => switch (reason) {
  ReviewQueueReason.dueSrs => 'ถึงเวลาทบทวน',
  ReviewQueueReason.incorrectAnswer => 'เคยตอบผิด',
  ReviewQueueReason.reported => 'รายการที่รายงานไว้',
  ReviewQueueReason.saved => 'รายการที่บันทึกไว้',
};

String _recommendationReasonLabel(
  RecommendationPanelReason reason,
) => switch (reason) {
  RecommendationPanelReason.weakEvidence => 'ลองฝึกคำนี้อีกครั้ง',
  RecommendationPanelReason.learnerPreference => 'ตรงกับรูปแบบที่เลือกไว้',
  RecommendationPanelReason.learnerOverride => 'ใช้ตัวเลือกที่คุณเลือก',
  RecommendationPanelReason.staleEvidence => 'ข้อมูลคำแนะนำล้าสมัย',
  RecommendationPanelReason.missingEvidence => 'ยังมีข้อมูลไม่เพียงพอ',
  RecommendationPanelReason.corruptEvidence => 'ข้อมูลคำแนะนำไม่พร้อมใช้งาน',
  RecommendationPanelReason.modeUnavailable => 'กิจกรรมนี้ยังไม่พร้อมใช้งาน',
  RecommendationPanelReason.protocolLocked =>
    'กิจกรรมนี้ใช้ตามเงื่อนไขที่ได้รับมอบหมาย',
  RecommendationPanelReason.canonicalAuthorityUnavailable =>
    'ข้อมูลหลักยังไม่พร้อมใช้งาน',
  RecommendationPanelReason.noEligibleActivity =>
    'ยังไม่มีกิจกรรมที่เหมาะสมในตอนนี้',
};
