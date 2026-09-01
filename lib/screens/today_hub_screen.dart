import 'package:flutter/material.dart';

import '../features/assessment/domain/assessment_models.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/recommendation/application/recommendation_use_cases.dart';
import '../features/review/domain/review_queue_item.dart';
import '../features/today_hub/application/today_hub_use_cases.dart';
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

final class TodayHubScreen extends StatefulWidget {
  const TodayHubScreen({
    super.key,
    required this.useCases,
    required this.actions,
    required this.features,
    required this.assessmentAvailable,
  });

  final TodayHubSnapshotLoader useCases;
  final TodayHubActionDelegate actions;
  final FeatureRegistry features;
  final bool assessmentAvailable;

  @override
  State<TodayHubScreen> createState() => _TodayHubScreenState();
}

enum _TodayHubAction { resume, recommendation, review, history, assessment }

final class _TodayHubScreenState extends State<TodayHubScreen> {
  TodayHubSnapshot? _snapshot;
  Object? _loadFailure;
  final Set<_TodayHubAction> _inFlight = <_TodayHubAction>{};
  Listenable? _featureChanges;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _observeFeatures();
    _load();
  }

  @override
  void didUpdateWidget(TodayHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.features, widget.features)) {
      _observeFeatures();
    }
    if (!identical(oldWidget.useCases, widget.useCases)) {
      _load();
    }
  }

  void _observeFeatures() {
    _featureChanges?.removeListener(_onFeaturesChanged);
    final changes = widget.features is Listenable
        ? widget.features as Listenable
        : null;
    _featureChanges = changes;
    changes?.addListener(_onFeaturesChanged);
  }

  void _onFeaturesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _snapshot = null;
        _loadFailure = null;
      });
    }
    try {
      final snapshot = await widget.useCases.load();
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _loadFailure = error);
    }
  }

  Future<void> _runAction(
    _TodayHubAction action,
    Future<void> Function() invoke, {
    bool Function()? allowed,
  }) async {
    if (_inFlight.contains(action) || (allowed != null && !allowed())) return;
    setState(() {
      _inFlight.add(action);
    });
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
      if (mounted) {
        setState(() {
          _inFlight.remove(action);
        });
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _featureChanges?.removeListener(_onFeaturesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('วันนี้')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loadFailure != null) {
      return Center(
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
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองอีกครั้ง'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(
        child: Semantics(
          label: 'กำลังโหลดรายการวันนี้',
          child: const CircularProgressIndicator(),
        ),
      );
    }

    final children = <Widget>[];
    for (final section in snapshot.sectionOrder) {
      switch (section) {
        case TodayHubSectionKind.resume:
          final session = snapshot.resumableSession;
          if (session != null) children.add(_resumeCard(session));
          _appendDependencyStatus(
            children,
            snapshot,
            TodayHubDependency.activeSession,
            label: 'เซสชันที่ค้างอยู่ไม่พร้อมใช้งาน',
          );
        case TodayHubSectionKind.assigned:
          final assessment = snapshot.assignedAssessment;
          if (assessment != null && _assessmentEnabled(assessment)) {
            children.add(_assessmentCard(assessment));
          }
          _appendDependencyStatus(
            children,
            snapshot,
            TodayHubDependency.assessment,
            label: 'แบบประเมินยังไม่พร้อมใช้งาน',
          );
        case TodayHubSectionKind.review:
          for (final work in snapshot.reviewWork) {
            children.add(_reviewCard(work));
          }
          _appendDependencyStatus(
            children,
            snapshot,
            TodayHubDependency.review,
            label: 'รายการทบทวนไม่พร้อมใช้งาน',
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
          _appendDependencyStatus(
            children,
            snapshot,
            TodayHubDependency.gentleStreak,
            label: 'ข้อมูลความต่อเนื่องยังไม่พร้อมใช้งาน',
          );
      }
    }
    children.add(_childActions(snapshot));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, index) => children[index],
    );
  }

  void _appendDependencyStatus(
    List<Widget> children,
    TodayHubSnapshot snapshot,
    TodayHubDependency dependency, {
    required String label,
  }) {
    final state = snapshot.dependencyStates[dependency];
    if (state == TodayHubDependencyState.unavailable ||
        state == TodayHubDependencyState.corrupt) {
      children.add(_statusCard(label));
    }
  }

  Widget _resumeCard(LearningSessionSummary session) {
    final busy = _inFlight.contains(_TodayHubAction.resume);
    final entry = NavigationGlossary.require('today-hub-resume-action');
    final onPressed = busy
        ? null
        : () => _runAction(
            _TodayHubAction.resume,
            () => widget.actions.resume(session),
          );
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

  Widget _reviewCard(TodayHubReviewWorkItem work) {
    return Card(
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
  }

  Widget _recommendationCard(TodayHubRecommendation recommendation) {
    if (!recommendation.isAuthoritative) {
      return _statusCard(
        _recommendationReasonLabel(recommendation.result.reason),
      );
    }
    final busy = _inFlight.contains(_TodayHubAction.recommendation);
    final entry = NavigationGlossary.require('today-hub-start-recommendation');
    final onPressed = busy
        ? null
        : () => _runAction(
            _TodayHubAction.recommendation,
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
    final busy = _inFlight.contains(_TodayHubAction.assessment);
    final entry = NavigationGlossary.require('today-hub-assessment-action');
    final onPressed = busy
        ? null
        : () => _runAction(
            _TodayHubAction.assessment,
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

  Widget _streakCard(int days) {
    return Card(
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
  }

  Widget _childActions(TodayHubSnapshot snapshot) {
    final reviewBusy = _inFlight.contains(_TodayHubAction.review);
    final historyBusy = _inFlight.contains(_TodayHubAction.history);
    final reviewEntry = NavigationGlossary.require('today-hub-open-review');
    final historyEntry = NavigationGlossary.require('today-hub-open-history');
    final openReview = reviewBusy
        ? null
        : () => _runAction(
            _TodayHubAction.review,
            () => widget.actions.openReview(snapshot.reviewWork),
          );
    final openHistory = historyBusy
        ? null
        : () => _runAction(_TodayHubAction.history, widget.actions.openHistory);
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

  Widget _statusCard(String message) {
    return Card(
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
