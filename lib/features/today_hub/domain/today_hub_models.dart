import '../../assessment/domain/assessment_models.dart';
import '../../goals/domain/learning_goal.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../motivation/domain/streak_policy.dart';
import '../../quest/domain/quest_models.dart';
import '../../recommendation/application/recommendation_use_cases.dart';
import '../../reminders/domain/study_reminder.dart';
import '../../review/domain/review_queue_item.dart';

enum TodayHubSectionKind {
  resume,
  assigned,
  review,
  recommendation,
  planning,
  continuity,
}

enum TodayHubDependency {
  identity,
  activeSession,
  review,
  recommendation,
  assessment,
  goals,
  reminders,
  quests,
  gentleStreak,
}

enum TodayHubDependencyState { ready, empty, stale, unavailable, corrupt }

final class TodayHubRequest {
  TodayHubRequest({
    required String ownerId,
    required DateTime evaluatedAtUtc,
    required String timezoneId,
  }) : ownerId = _canonicalText(ownerId, 'ownerId'),
       evaluatedAtUtc = _canonicalUtc(evaluatedAtUtc, 'evaluatedAtUtc'),
       timezoneId = _canonicalText(timezoneId, 'timezoneId');

  final String ownerId;
  final DateTime evaluatedAtUtc;
  final String timezoneId;
}

abstract interface class TodayHubReader {
  Future<TodayHubSnapshot> compose(TodayHubRequest request);
}

final class TodayHubReviewWorkItem {
  TodayHubReviewWorkItem({
    required ReviewQueueItem item,
    required this.recommendation,
  }) : snapshot = item.snapshot,
       provenance = List<ReviewReasonProvenance>.unmodifiable(item.provenance) {
    if (recommendation != null && recommendation!.contentId != identity.id) {
      throw ArgumentError(
        'recommendation content identity does not match work',
      );
    }
  }

  final ReviewedLexicalContentSnapshot snapshot;
  final List<ReviewReasonProvenance> provenance;
  final RecommendationPanelResult? recommendation;

  ContentIdentity get identity => snapshot.identity;
}

final class TodayHubRecommendation {
  TodayHubRecommendation({
    required this.result,
    required this.isAuthoritative,
    required this.mergedInto,
  }) {
    if (isAuthoritative &&
        (result.availability != RecommendationResultAvailability.recommended ||
            result.freshness != RecommendationEvidenceFreshness.current ||
            result.ownerId == null ||
            result.recommendedMode == null)) {
      throw ArgumentError('authoritative recommendation is not current');
    }
    if (mergedInto != null &&
        (!isAuthoritative || result.contentId != mergedInto!.id)) {
      throw ArgumentError('merged recommendation identity is inconsistent');
    }
  }

  final RecommendationPanelResult result;
  final bool isAuthoritative;
  final ContentIdentity? mergedInto;
}

final class TodayHubAssignedAssessment {
  TodayHubAssignedAssessment({required this.run}) {
    if (run.state != AssessmentRunState.active) {
      throw ArgumentError.value(run.state, 'run.state', 'must be active');
    }
  }

  final AssessmentRun run;

  String get assignmentId => run.assignmentId;
  String get learningSessionId => run.learningSessionId;
}

final class TodayHubSnapshot {
  TodayHubSnapshot({
    required this.ownerId,
    required this.evaluatedAtUtc,
    required Iterable<TodayHubSectionKind> sectionOrder,
    required this.resumableSession,
    required this.assignedAssessment,
    required Iterable<TodayHubReviewWorkItem> reviewWork,
    required this.recommendation,
    required Iterable<LearningGoal> goals,
    required Iterable<StudyReminder> reminders,
    required Iterable<QuestInstance> quests,
    required this.gentleStreak,
    required Map<TodayHubDependency, TodayHubDependencyState> dependencyStates,
  }) : sectionOrder = List<TodayHubSectionKind>.unmodifiable(sectionOrder),
       reviewWork = List<TodayHubReviewWorkItem>.unmodifiable(reviewWork),
       goals = List<LearningGoal>.unmodifiable(goals),
       reminders = List<StudyReminder>.unmodifiable(reminders),
       quests = List<QuestInstance>.unmodifiable(quests),
       dependencyStates =
           Map<TodayHubDependency, TodayHubDependencyState>.unmodifiable(
             dependencyStates,
           ) {
    _canonicalText(ownerId, 'ownerId');
    _canonicalUtc(evaluatedAtUtc, 'evaluatedAtUtc');
    final sectionSet = this.sectionOrder.toSet();
    if (sectionSet.length != this.sectionOrder.length ||
        !_isCanonicalSectionOrder(this.sectionOrder)) {
      throw ArgumentError.value(
        sectionOrder,
        'sectionOrder',
        'must be a unique canonical-order subsequence',
      );
    }
    if (this.dependencyStates.keys.toSet().length !=
            TodayHubDependency.values.length ||
        !this.dependencyStates.keys.toSet().containsAll(
          TodayHubDependency.values,
        )) {
      throw ArgumentError.value(
        dependencyStates,
        'dependencyStates',
        'must declare every Today Hub dependency',
      );
    }
    if ((resumableSession != null && resumableSession!.ownerId != ownerId) ||
        (assignedAssessment != null &&
            assignedAssessment!.run.ownerId != ownerId) ||
        this.reminders.any((reminder) => reminder.ownerId != ownerId) ||
        this.quests.any((quest) => quest.ownerId != ownerId) ||
        (gentleStreak != null && gentleStreak!.ownerId != ownerId) ||
        (recommendation.result.ownerId != null &&
            recommendation.result.ownerId != ownerId)) {
      throw ArgumentError('Today Hub source owner identity is inconsistent');
    }
  }

  final String ownerId;
  final DateTime evaluatedAtUtc;
  final List<TodayHubSectionKind> sectionOrder;
  final LearningSessionSummary? resumableSession;
  final TodayHubAssignedAssessment? assignedAssessment;
  final List<TodayHubReviewWorkItem> reviewWork;
  final TodayHubRecommendation recommendation;
  final List<LearningGoal> goals;
  final List<StudyReminder> reminders;
  final List<QuestInstance> quests;
  final GentleStreakSnapshot? gentleStreak;
  final Map<TodayHubDependency, TodayHubDependencyState> dependencyStates;

  TodayHubRecommendation? get authoritativeRecommendation =>
      recommendation.isAuthoritative ? recommendation : null;
}

String _canonicalText(String value, String name) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > 256 ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'))) {
    throw ArgumentError.value(value, name, 'must be canonical bounded text');
  }
  return value;
}

DateTime _canonicalUtc(DateTime value, String name) {
  if (!value.isUtc ||
      value.millisecondsSinceEpoch < 0 ||
      value.microsecondsSinceEpoch % Duration.microsecondsPerMillisecond != 0) {
    throw ArgumentError.value(
      value,
      name,
      'must be nonnegative millisecond-precise UTC',
    );
  }
  return DateTime.fromMillisecondsSinceEpoch(
    value.millisecondsSinceEpoch,
    isUtc: true,
  );
}

bool _isCanonicalSectionOrder(List<TodayHubSectionKind> sections) {
  var previous = -1;
  for (final section in sections) {
    if (section.index <= previous) return false;
    previous = section.index;
  }
  return true;
}
