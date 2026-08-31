import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../assessment/data/drift_assessment_repository.dart';
import '../../assessment/domain/assessment_models.dart';
import '../../goals/domain/learning_goal.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../motivation/domain/streak_policy.dart';
import '../../quest/data/drift_quest_repository.dart';
import '../../quest/domain/quest_models.dart';
import '../../recommendation/application/recommendation_use_cases.dart';
import '../../research/data/drift_experiment_assignment_repository.dart';
import '../../reminders/domain/study_reminder.dart';
import '../../review/domain/review_queue_item.dart';
import '../domain/today_hub_models.dart';

final class DriftTodayHubReader implements TodayHubReader {
  DriftTodayHubReader(
    this.database, {
    required this.reviewReader,
    required this.recommendationUseCases,
  });

  final db.AppDatabase database;
  final ReviewCenterReader reviewReader;
  final RecommendationUseCases recommendationUseCases;

  @override
  Future<TodayHubSnapshot> compose(TodayHubRequest request) async {
    if (!await _hasExactActiveOwner(request.ownerId)) {
      return _identityUnavailable(request);
    }

    final states = <TodayHubDependency, TodayHubDependencyState>{
      for (final dependency in TodayHubDependency.values)
        dependency: TodayHubDependencyState.empty,
      TodayHubDependency.identity: TodayHubDependencyState.ready,
    };

    final session = await _loadSession(request.ownerId);
    states[TodayHubDependency.activeSession] = session.state;

    final review = await _loadReview(request);
    states[TodayHubDependency.review] = review.state;

    final recommendation = await _loadRecommendation(request);
    states[TodayHubDependency.recommendation] = recommendation.state;

    final merged = _mergeRecommendation(
      review.values,
      recommendation.result,
      review.state,
    );
    states[TodayHubDependency.review] = merged.reviewState;

    final assessment = await _loadAssessment(request.ownerId);
    states[TodayHubDependency.assessment] = assessment.state;

    final goals = await _loadGoals(request.ownerId);
    states[TodayHubDependency.goals] = goals.state;

    final reminders = await _loadReminders(
      request.ownerId,
      canonicalGoalIds: goals.values.map((goal) => goal.id).toSet(),
    );
    states[TodayHubDependency.reminders] = reminders.state;

    final quests = await _loadQuests(request.ownerId);
    states[TodayHubDependency.quests] = quests.state;

    final streak = await _loadStreak(request);
    states[TodayHubDependency.gentleStreak] = streak.state;

    if (!await _hasExactActiveOwner(request.ownerId)) {
      return _identityUnavailable(request);
    }

    final recommendationValue = TodayHubRecommendation(
      result: recommendation.result,
      isAuthoritative: recommendation.authoritative,
      mergedInto: recommendation.authoritative ? merged.identity : null,
    );
    final sections = <TodayHubSectionKind>[
      if (session.value != null) TodayHubSectionKind.resume,
      if (assessment.value != null) TodayHubSectionKind.assigned,
      if (merged.items.isNotEmpty) TodayHubSectionKind.review,
      if (merged.identity == null &&
          recommendation.result.availability !=
              RecommendationResultAvailability.unavailable)
        TodayHubSectionKind.recommendation,
      if (goals.values.isNotEmpty || reminders.values.isNotEmpty)
        TodayHubSectionKind.planning,
      if (quests.values.isNotEmpty || streak.value != null)
        TodayHubSectionKind.continuity,
    ];

    return TodayHubSnapshot(
      ownerId: request.ownerId,
      evaluatedAtUtc: request.evaluatedAtUtc,
      sectionOrder: sections,
      resumableSession: session.value,
      assignedAssessment: assessment.value,
      reviewWork: merged.items,
      recommendation: recommendationValue,
      goals: goals.values,
      reminders: reminders.values,
      quests: quests.values,
      gentleStreak: streak.value,
      dependencyStates: states,
    );
  }

  Future<bool> _hasExactActiveOwner(String ownerId) async {
    try {
      final rows =
          await (database.select(database.localOwners)
                ..where((row) => row.isActive.equals(true))
                ..orderBy([(row) => OrderingTerm.asc(row.id)])
                ..limit(2))
              .get();
      return rows.length == 1 && rows.single.id == ownerId;
    } catch (_) {
      return false;
    }
  }

  TodayHubSnapshot _identityUnavailable(TodayHubRequest request) {
    final unavailable = _unavailableRecommendation(request.ownerId);
    return TodayHubSnapshot(
      ownerId: request.ownerId,
      evaluatedAtUtc: request.evaluatedAtUtc,
      sectionOrder: const <TodayHubSectionKind>[],
      resumableSession: null,
      assignedAssessment: null,
      reviewWork: const <TodayHubReviewWorkItem>[],
      recommendation: TodayHubRecommendation(
        result: unavailable,
        isAuthoritative: false,
        mergedInto: null,
      ),
      goals: const <LearningGoal>[],
      reminders: const <StudyReminder>[],
      quests: const <QuestInstance>[],
      gentleStreak: null,
      dependencyStates: <TodayHubDependency, TodayHubDependencyState>{
        for (final dependency in TodayHubDependency.values)
          dependency: TodayHubDependencyState.unavailable,
      },
    );
  }

  Future<_ValueResult<LearningSessionSummary>> _loadSession(
    String ownerId,
  ) async {
    try {
      final candidates =
          await (database.select(database.learningSessions)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) & row.state.equals('active'),
                )
                ..orderBy([
                  (row) => OrderingTerm.desc(row.startedAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ])
                ..limit(1))
              .get();
      if (candidates.isEmpty) return const _ValueResult.empty();
      final session = await DriftLearningRepository(database)
          .loadSessionConfigurationState(
            ownerId: ownerId,
            sessionId: candidates.single.id,
          );
      if (session == null ||
          session.ownerId != ownerId ||
          session.state != 'active') {
        return const _ValueResult.corrupt();
      }
      return _ValueResult.ready(session);
    } catch (_) {
      return const _ValueResult.corrupt();
    }
  }

  Future<_ListResult<ReviewQueueItem>> _loadReview(
    TodayHubRequest request,
  ) async {
    try {
      final values = List<ReviewQueueItem>.of(
        await reviewReader.compose(
          ReviewQueueFilter(
            ownerId: request.ownerId,
            evaluatedAtUtc: request.evaluatedAtUtc,
            timezoneId: request.timezoneId,
          ),
        ),
      )..sort(ReviewQueueItem.compare);
      if (values.isEmpty) return const _ListResult.empty();

      final exactIdentities = <String>{};
      final revisionsById = <String, Set<int>>{};
      var corrupt = false;
      for (final item in values) {
        final identity = item.identity;
        final exact =
            '${identity.type.name}:${identity.id}@${identity.revision}';
        if (!exactIdentities.add(exact)) corrupt = true;
        revisionsById
            .putIfAbsent(identity.id, () => <int>{})
            .add(identity.revision);
      }
      if (revisionsById.values.any((revisions) => revisions.length != 1)) {
        corrupt = true;
      }
      return _ListResult<ReviewQueueItem>(
        values,
        corrupt
            ? TodayHubDependencyState.corrupt
            : TodayHubDependencyState.ready,
      );
    } catch (_) {
      return const _ListResult.unavailable();
    }
  }

  Future<_RecommendationResult> _loadRecommendation(
    TodayHubRequest request,
  ) async {
    try {
      final result = await recommendationUseCases.loadForRequest(
        ownerId: request.ownerId,
        evaluatedAtUtc: request.evaluatedAtUtc,
        timezoneId: request.timezoneId,
      );
      if (result.ownerId != request.ownerId) {
        return _RecommendationResult(
          _unavailableRecommendation(request.ownerId),
          TodayHubDependencyState.unavailable,
          false,
        );
      }
      final state = switch (result.freshness) {
        RecommendationEvidenceFreshness.stale => TodayHubDependencyState.stale,
        RecommendationEvidenceFreshness.corrupt =>
          TodayHubDependencyState.corrupt,
        RecommendationEvidenceFreshness.missing
            when result.availability ==
                RecommendationResultAvailability.unavailable =>
          TodayHubDependencyState.unavailable,
        RecommendationEvidenceFreshness.missing =>
          TodayHubDependencyState.empty,
        RecommendationEvidenceFreshness.current
            when result.availability ==
                RecommendationResultAvailability.unavailable =>
          TodayHubDependencyState.unavailable,
        RecommendationEvidenceFreshness.current =>
          TodayHubDependencyState.ready,
      };
      final authoritative =
          state == TodayHubDependencyState.ready &&
          result.availability == RecommendationResultAvailability.recommended &&
          result.recommendedMode != null;
      return _RecommendationResult(result, state, authoritative);
    } catch (_) {
      return _RecommendationResult(
        _unavailableRecommendation(request.ownerId),
        TodayHubDependencyState.unavailable,
        false,
      );
    }
  }

  _MergedReview _mergeRecommendation(
    List<ReviewQueueItem> reviewItems,
    RecommendationPanelResult recommendation,
    TodayHubDependencyState reviewState,
  ) {
    final contentId = recommendation.contentId;
    final matching = contentId == null
        ? const <ReviewQueueItem>[]
        : reviewItems
              .where((item) => item.identity.id == contentId)
              .toList(growable: false);
    final mergedIdentity = matching.length == 1
        ? matching.single.identity
        : null;
    return _MergedReview(
      <TodayHubReviewWorkItem>[
        for (final item in reviewItems)
          TodayHubReviewWorkItem(
            item: item,
            recommendation: item.identity == mergedIdentity
                ? recommendation
                : null,
          ),
      ],
      mergedIdentity,
      matching.length > 1 ? TodayHubDependencyState.corrupt : reviewState,
    );
  }

  Future<_ValueResult<TodayHubAssignedAssessment>> _loadAssessment(
    String ownerId,
  ) async {
    try {
      final rows =
          await (database.select(database.assessmentRuns)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.state.equals(AssessmentRunState.active.name),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.startedAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      if (rows.isEmpty) return const _ValueResult.empty();
      if (rows.length != 1) return const _ValueResult.corrupt();

      final run = await DriftAssessmentRepository(
        database,
      ).getRun(rows.single.id);
      if (run.ownerId != ownerId || run.state != AssessmentRunState.active) {
        return const _ValueResult.corrupt();
      }
      final assignment =
          await (database.select(database.experimentAssignments)
                ..where((row) => row.id.equals(run.assignmentId))
                ..limit(2))
              .get();
      if (assignment.length != 1) return const _ValueResult.corrupt();
      final exact = assignment.single;
      final canonicalAssignmentId =
          DriftExperimentAssignmentRepository.canonicalAssignmentId(
            ownerId: ownerId,
            experimentId: run.experimentId,
            experimentVersion: run.experimentVersion,
          );
      if (run.assignmentId != canonicalAssignmentId ||
          exact.ownerId != ownerId ||
          exact.experimentId != run.experimentId ||
          exact.experimentVersion != run.experimentVersion ||
          exact.cohort != run.cohort ||
          exact.protocolVersion != run.protocolVersion ||
          exact.assignedAtUtcMs < 0 ||
          exact.assignedAtUtcMs > run.startedAtUtc.millisecondsSinceEpoch) {
        return const _ValueResult.corrupt();
      }
      final sessions =
          await (database.select(database.learningSessions)
                ..where((row) => row.id.equals(run.learningSessionId))
                ..limit(2))
              .get();
      if (sessions.length != 1) return const _ValueResult.corrupt();
      final session = sessions.single;
      if (session.ownerId != ownerId ||
          session.activityType != 'assessment' ||
          session.state != 'active' ||
          session.startedAtUtcMs != run.startedAtUtc.millisecondsSinceEpoch ||
          session.endedAtUtcMs != null) {
        return const _ValueResult.corrupt();
      }
      return _ValueResult.ready(TodayHubAssignedAssessment(run: run));
    } catch (_) {
      return const _ValueResult.corrupt();
    }
  }

  Future<_ListResult<LearningGoal>> _loadGoals(String ownerId) async {
    try {
      final rows =
          await (database.select(database.learningGoals)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.isDeleted.equals(false) &
                      row.status.equals(LearningGoalStatus.active.name),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.deadlineAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      if (rows.isEmpty) return const _ListResult.empty();
      final values = <LearningGoal>[
        for (final row in rows)
          LearningGoal(
            id: row.id,
            kind: LearningGoalKindCodec.parse(row.kind),
            title: row.title,
            deadlineAtUtc: _utc(row.deadlineAtUtcMs),
            timezone: LearningGoalTimezoneContext(
              timezoneId: row.timezoneId,
              utcOffsetMinutes: row.timezoneOffsetMinutes,
            ),
            status: LearningGoalStatusCodec.parse(row.status),
            createdAtUtc: _utc(row.createdAtUtcMs),
            updatedAtUtc: _utc(row.updatedAtUtcMs),
          ),
      ];
      return _ListResult.ready(values);
    } catch (_) {
      return const _ListResult.corrupt();
    }
  }

  Future<_ListResult<StudyReminder>> _loadReminders(
    String ownerId, {
    required Set<String> canonicalGoalIds,
  }) async {
    try {
      final rows =
          await (database.select(database.studyReminders)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.isDeleted.equals(false) &
                      row.isEnabled.equals(true),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.scheduledAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      if (rows.isEmpty) return const _ListResult.empty();
      final values = <StudyReminder>[];
      for (final row in rows) {
        final source = switch (row.sourceKind) {
          'dueReview' when row.goalId == null =>
            const StudyReminderSource.dueReview(),
          'goalDeadline'
              when row.goalId != null &&
                  canonicalGoalIds.contains(row.goalId) =>
            StudyReminderSource.goalDeadline(row.goalId!),
          _ => throw StateError('invalid Today Hub reminder source'),
        };
        if ((row.quietHoursStartMinutes == null) !=
            (row.quietHoursEndMinutes == null)) {
          throw StateError('incomplete reminder quiet hours');
        }
        values.add(
          StudyReminder(
            id: row.id,
            ownerId: row.ownerId,
            source: source,
            scheduledAtUtc: _utc(row.scheduledAtUtcMs),
            timezone: StudyReminderTimezoneContext(
              timezoneId: row.timezoneId,
              utcOffsetMinutes: row.timezoneOffsetMinutes,
            ),
            quietHours: row.quietHoursStartMinutes == null
                ? null
                : ReminderQuietHours(
                    startMinutes: row.quietHoursStartMinutes!,
                    endMinutes: row.quietHoursEndMinutes!,
                  ),
            isEnabled: row.isEnabled,
            createdAtUtc: _utc(row.createdAtUtcMs),
            updatedAtUtc: _utc(row.updatedAtUtcMs),
            isDeleted: row.isDeleted,
          ),
        );
      }
      return _ListResult.ready(values);
    } catch (_) {
      return const _ListResult.corrupt();
    }
  }

  Future<_ListResult<QuestInstance>> _loadQuests(String ownerId) async {
    try {
      final values = await DriftQuestRepository(
        database,
      ).getActiveInstances(ownerId);
      if (values.any(
        (value) =>
            value.ownerId != ownerId ||
            value.state != QuestInstanceState.active,
      )) {
        return const _ListResult.corrupt();
      }
      return values.isEmpty
          ? const _ListResult.empty()
          : _ListResult.ready(values);
    } catch (_) {
      return const _ListResult.corrupt();
    }
  }

  Future<_ValueResult<GentleStreakSnapshot>> _loadStreak(
    TodayHubRequest request,
  ) async {
    try {
      final rows =
          await (database.select(database.streakStates)
                ..where((row) => row.ownerId.equals(request.ownerId))
                ..limit(2))
              .get();
      if (rows.isEmpty) return const _ValueResult.empty();
      if (rows.length != 1) return const _ValueResult.corrupt();
      final row = rows.single;
      final state = StreakState(
        ownerId: row.ownerId,
        currentStreakDays: row.currentStreakDays,
        longestStreakDays: row.longestStreakDays,
        freezeCount: row.freezeCount,
        lastLearnedAtUtcMs: row.lastLearnedAtUtcMs,
        updatedAtUtcMs: row.updatedAtUtcMs,
      );
      return _ValueResult.ready(
        StreakPolicy.snapshot(
          current: state,
          nowUtc: request.evaluatedAtUtc,
          timezoneId: request.timezoneId,
        ),
      );
    } catch (_) {
      return const _ValueResult.corrupt();
    }
  }
}

final class _ValueResult<T> {
  const _ValueResult(this.value, this.state);
  const _ValueResult.ready(T value)
    : this(value, TodayHubDependencyState.ready);
  const _ValueResult.empty() : this(null, TodayHubDependencyState.empty);
  const _ValueResult.corrupt() : this(null, TodayHubDependencyState.corrupt);

  final T? value;
  final TodayHubDependencyState state;
}

final class _ListResult<T> {
  _ListResult(Iterable<T> values, this.state)
    : values = List<T>.unmodifiable(values);
  _ListResult.ready(Iterable<T> values)
    : this(values, TodayHubDependencyState.ready);
  const _ListResult.empty()
    : values = const <Never>[],
      state = TodayHubDependencyState.empty;
  const _ListResult.unavailable()
    : values = const <Never>[],
      state = TodayHubDependencyState.unavailable;
  const _ListResult.corrupt()
    : values = const <Never>[],
      state = TodayHubDependencyState.corrupt;

  final List<T> values;
  final TodayHubDependencyState state;
}

final class _RecommendationResult {
  const _RecommendationResult(this.result, this.state, this.authoritative);

  final RecommendationPanelResult result;
  final TodayHubDependencyState state;
  final bool authoritative;
}

final class _MergedReview {
  _MergedReview(
    Iterable<TodayHubReviewWorkItem> items,
    this.identity,
    this.reviewState,
  ) : items = List<TodayHubReviewWorkItem>.unmodifiable(items);

  final List<TodayHubReviewWorkItem> items;
  final ContentIdentity? identity;
  final TodayHubDependencyState reviewState;
}

RecommendationPanelResult _unavailableRecommendation(String ownerId) =>
    RecommendationPanelResult.unavailable(
      ownerId: ownerId,
      reason: RecommendationPanelReason.canonicalAuthorityUnavailable,
      freshness: RecommendationEvidenceFreshness.missing,
      protocolConstraint: RecommendationProtocolConstraint.open,
    );

DateTime _utc(int millisecondsSinceEpoch) {
  if (millisecondsSinceEpoch < 0) {
    throw StateError('negative Today Hub source timestamp');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
    isUtc: true,
  );
}
