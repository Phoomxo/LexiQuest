import 'package:flutter/material.dart';

import '../features/assessment/domain/assessment_models.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/recommendation/application/recommendation_use_cases.dart';
import '../features/review/domain/review_queue_item.dart';
import '../features/today_hub/domain/today_hub_models.dart';
import '../navigation/navigation_glossary.dart';
import '../runtime/registries/feature_registry.dart';

abstract interface class TodayHubActionDelegate {
  Future<void> resume(LearningSessionSummary session);
  Future<void> startRecommendation(TodayHubRecommendation recommendation);
  Future<void> openReview(List<TodayHubReviewWorkItem> work);
  Future<void> openHistory();
  Future<void> startAssessment(TodayHubAssignedAssessment assessment);
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
        padding: const EdgeInsets.all(24),
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

enum _Action { resume, recommendation, review, history, assessment }

final class _TodayHubViewState extends State<TodayHubView> {
  final Set<_Action> _inFlight = <_Action>{};
  Listenable? _featureChanges;

  @override
  void initState() {
    super.initState();
    _observeFeatures();
  }

  @override
  void didUpdateWidget(TodayHubView oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    setState(() => _inFlight.add(action));
    try {
      if (allowed != null && !allowed()) return;
      await invoke();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('ไม่สามารถเปิดรายการนี้ได้ กรุณาลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _inFlight.remove(action));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final children = <Widget>[];
    for (final section in snapshot.sectionOrder) {
      switch (section) {
        case TodayHubSectionKind.resume:
          final session = snapshot.resumableSession;
          if (session != null) children.add(_resumeCard(session));
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
          children.addAll(snapshot.reviewWork.map(_reviewCard));
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
          break;
        case TodayHubSectionKind.continuity:
          final streak = snapshot.gentleStreak;
          if (streak != null) {
            children.add(_streakCard(streak.currentStreakDays));
          }
          _statusFor(
            children,
            TodayHubDependency.gentleStreak,
            'ข้อมูลความต่อเนื่องยังไม่พร้อมใช้งาน',
          );
      }
    }
    children.add(_childActions(snapshot));
    return ListView.separated(
      key: const ValueKey('today-hub-view'),
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) => children[index],
    );
  }

  void _statusFor(
    List<Widget> children,
    TodayHubDependency dependency,
    String label,
  ) {
    final state = widget.snapshot.dependencyStates[dependency];
    if (state == TodayHubDependencyState.unavailable ||
        state == TodayHubDependencyState.corrupt) {
      children.add(_statusCard(label));
    }
  }

  Widget _resumeCard(LearningSessionSummary session) {
    final entry = NavigationGlossary.require('today-hub-resume-action');
    final onPressed = _inFlight.contains(_Action.resume)
        ? null
        : () => _run(_Action.resume, () => widget.actions.resume(session));
    return Card(
      key: const ValueKey('today-hub-resume'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'เรียนต่อจากเดิม',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('เซสชัน ${session.activityType}'),
            const SizedBox(height: 12),
            _glossaryAction(
              entry: entry,
              onTap: onPressed,
              child: FilledButton.icon(
                key: const ValueKey('today-hub-resume-action'),
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
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            work.snapshot.spelling,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(work.snapshot.meaning),
          const SizedBox(height: 8),
          for (final source in work.provenance) ...<Widget>[
            Text(_reviewReasonLabel(source.reason)),
            Text(source.sourceId),
          ],
          if (work.recommendation != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_recommendationReasonLabel(work.recommendation!.reason)),
          ],
        ],
      ),
    ),
  );

  Widget _recommendationCard(TodayHubRecommendation recommendation) {
    if (!recommendation.isAuthoritative) {
      return _statusCard(
        _recommendationReasonLabel(recommendation.result.reason),
      );
    }
    final entry = NavigationGlossary.require('today-hub-start-recommendation');
    final onPressed = _inFlight.contains(_Action.recommendation)
        ? null
        : () => _run(
            _Action.recommendation,
            () => widget.actions.startRecommendation(recommendation),
            allowed: () => recommendation.isAuthoritative,
          );
    return Card(
      key: const ValueKey('today-hub-recommendation'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'คำแนะนำสำหรับวันนี้',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_recommendationReasonLabel(recommendation.result.reason)),
            const SizedBox(height: 12),
            _glossaryAction(
              entry: entry,
              onTap: onPressed,
              child: FilledButton.icon(
                key: const ValueKey('today-hub-start-recommendation'),
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
      assessment.run.state == AssessmentRunState.active &&
      widget.features.isEnabled(Feature.researchAssessment);

  Widget _assessmentCard(TodayHubAssignedAssessment assessment) {
    final entry = NavigationGlossary.require('today-hub-assessment-action');
    final onPressed = _inFlight.contains(_Action.assessment)
        ? null
        : () => _run(
            _Action.assessment,
            () => widget.actions.startAssessment(assessment),
            allowed: () => _assessmentEnabled(assessment),
          );
    return Card(
      key: const ValueKey('today-hub-assessment'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'แบบประเมินที่ได้รับมอบหมาย',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _glossaryAction(
              entry: entry,
              onTap: onPressed,
              child: FilledButton.icon(
                key: const ValueKey('today-hub-assessment-action'),
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

  Widget _streakCard(int days) => Card(
    key: const ValueKey('today-hub-gentle-streak'),
    child: Semantics(
      container: true,
      label: 'ความต่อเนื่อง $days วัน พักได้เมื่อจำเป็น',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.wb_sunny_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'ต่อเนื่อง $days วัน — พักได้เมื่อจำเป็น แล้วกลับมาเมื่อพร้อม',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _childActions(TodayHubSnapshot snapshot) {
    final reviewEntry = NavigationGlossary.require('today-hub-open-review');
    final historyEntry = NavigationGlossary.require('today-hub-open-history');
    final openReview = _inFlight.contains(_Action.review)
        ? null
        : () => _run(
            _Action.review,
            () => widget.actions.openReview(snapshot.reviewWork),
          );
    final openHistory = _inFlight.contains(_Action.history)
        ? null
        : () => _run(_Action.history, widget.actions.openHistory);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _glossaryAction(
          entry: reviewEntry,
          onTap: openReview,
          child: OutlinedButton.icon(
            key: const ValueKey('today-hub-open-review'),
            onPressed: openReview,
            icon: Icon(reviewEntry.icon),
            label: Text(reviewEntry.fullThaiLabel),
          ),
        ),
        _glossaryAction(
          entry: historyEntry,
          onTap: openHistory,
          child: OutlinedButton.icon(
            key: const ValueKey('today-hub-open-history'),
            onPressed: openHistory,
            icon: Icon(historyEntry.icon),
            label: Text(historyEntry.fullThaiLabel),
          ),
        ),
      ],
    );
  }

  Widget _glossaryAction({
    required NavigationGlossaryEntry entry,
    required VoidCallback? onTap,
    required Widget child,
  }) => Tooltip(
    message: entry.tooltip,
    child: Semantics(
      button: true,
      enabled: onTap != null,
      label: entry.semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: child,
    ),
  );

  Widget _statusCard(String message) => Card(
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
  ReviewQueueReason.dueSrs => 'ถึงกำหนด SRS',
  ReviewQueueReason.incorrectAnswer => 'เคยตอบผิด',
  ReviewQueueReason.reported => 'รายการที่รายงานไว้',
  ReviewQueueReason.saved => 'รายการที่บันทึกไว้',
};

String _recommendationReasonLabel(
  RecommendationPanelReason reason,
) => switch (reason) {
  RecommendationPanelReason.weakEvidence => 'หลักฐานยังไม่แข็งแรง',
  RecommendationPanelReason.learnerPreference => 'ตรงกับรูปแบบที่เลือกไว้',
  RecommendationPanelReason.learnerOverride => 'ใช้ตัวเลือกที่คุณเลือก',
  RecommendationPanelReason.staleEvidence => 'ข้อมูลคำแนะนำล้าสมัย',
  RecommendationPanelReason.missingEvidence => 'ยังมีข้อมูลไม่เพียงพอ',
  RecommendationPanelReason.corruptEvidence => 'ข้อมูลคำแนะนำไม่พร้อมใช้งาน',
  RecommendationPanelReason.modeUnavailable => 'กิจกรรมนี้ยังไม่พร้อมใช้งาน',
  RecommendationPanelReason.protocolLocked => 'กิจกรรมถูกจำกัดตามโปรโตคอล',
  RecommendationPanelReason.canonicalAuthorityUnavailable =>
    'ข้อมูลหลักยังไม่พร้อมใช้งาน',
  RecommendationPanelReason.noEligibleActivity =>
    'ยังไม่มีกิจกรรมที่เหมาะสมในตอนนี้',
};
