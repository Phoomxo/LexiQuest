import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../domain/personal_learning_profile.dart';
import 'drift_learning_calendar_reader.dart';
import 'drift_progress_queries.dart';

/// Read-only f36 composition over the existing canonical projection tables.
///
/// This reader never repairs, creates, or snapshots domain state. Assessment
/// isolation is inherited from [DriftProgressQueries] and
/// [DriftLearningCalendarReader].
final class DriftPersonalLearningProfileReader {
  DriftPersonalLearningProfileReader(
    this.database, {
    DriftProgressQueries? progress,
    DriftLearningCalendarReader? calendar,
  }) : progress = progress ?? DriftProgressQueries(database),
       calendar = calendar ?? DriftLearningCalendarReader(database);

  final AppDatabase database;
  final DriftProgressQueries progress;
  final DriftLearningCalendarReader calendar;

  Future<PersonalLearningProfile> load({
    required String ownerId,
    required DateTime nowUtc,
    required String timezoneId,
  }) async {
    _requireIdentifier(ownerId, 'ownerId');
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    _requireIdentifier(timezoneId, 'timezoneId');

    final progressSnapshot = await progress.load(
      ownerId: ownerId,
      nowUtc: nowUtc,
    );
    final calendarSnapshot = await calendar.loadWeek(
      ownerId: ownerId,
      referenceUtc: nowUtc,
      timezoneId: timezoneId,
    );
    final trackedWordCount = await _trackedSrsCount(ownerId);
    final streak = await (database.select(
      database.streakStates,
    )..where((row) => row.ownerId.equals(ownerId))).getSingleOrNull();
    final activeQuestCount = await _questCount(ownerId, 'active');
    final evidenceBearingActiveQuestCount =
        await _evidenceBearingActiveQuestCount(ownerId);
    final completedQuestCount = await _questCount(ownerId, 'completed');
    final ownedRewardItemCount = await _ownedRewardItemCount(ownerId);

    final masteryAvailable =
        progressSnapshot.sampleSize > 0 || trackedWordCount > 0;
    final weeklyAccuracy = calendarSnapshot.weekly.accuracy;
    final engagementAvailable =
        progressSnapshot.totalXp > 0 ||
        progressSnapshot.completedSessions > 0 ||
        (streak?.currentStreakDays ?? 0) > 0 ||
        evidenceBearingActiveQuestCount > 0 ||
        completedQuestCount > 0 ||
        progressSnapshot.achievementCount > 0 ||
        ownedRewardItemCount > 0;

    return PersonalLearningProfile(
      ownerId: ownerId,
      mastery: PersonalLearningMastery(
        availability: _availability(masteryAvailable),
        masteredWordCount: progressSnapshot.masteredWordCount,
        observedPracticeCount: progressSnapshot.sampleSize,
        skills: progressSnapshot.skills
            .where((skill) => skill.sampleSize > 0)
            .toList(growable: false),
      ),
      srs: PersonalLearningSrs(
        availability: _availability(trackedWordCount > 0),
        trackedWordCount: trackedWordCount,
        dueReviewCount: progressSnapshot.dueReviewCount,
      ),
      effort: PersonalLearningEffort(
        availability: _availability(
          calendarSnapshot.weekly.effort.activeDuration != Duration.zero,
        ),
        activeDuration: calendarSnapshot.weekly.effort.activeDuration,
      ),
      accuracy: PersonalLearningAccuracy(
        availability: _availability(weeklyAccuracy.sampleSize > 0),
        sampleSize: weeklyAccuracy.sampleSize,
        correctCount: weeklyAccuracy.correctCount,
      ),
      weakness: PersonalLearningWeakness(
        availability: _availability(progressSnapshot.sampleSize > 0),
        items: progressSnapshot.weaknesses,
      ),
      engagement: PersonalLearningEngagement(
        availability: _availability(engagementAvailable),
        totalXp: progressSnapshot.totalXp,
        avatarLevel: progressSnapshot.gameLevel,
        completedSessionCount: progressSnapshot.completedSessions,
        currentStreakDays: streak?.currentStreakDays ?? 0,
        longestStreakDays: streak?.longestStreakDays ?? 0,
        activeQuestCount: activeQuestCount,
        completedQuestCount: completedQuestCount,
        achievementCount: progressSnapshot.achievementCount,
        ownedRewardItemCount: ownedRewardItemCount,
      ),
      calendar: calendarSnapshot,
    );
  }

  Future<int> _trackedSrsCount(String ownerId) async {
    final count = database.srsStates.id.count();
    final row =
        await (database.selectOnly(database.srsStates)
              ..addColumns([count])
              ..where(database.srsStates.ownerId.equals(ownerId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> _questCount(String ownerId, String state) async {
    final count = database.questInstances.instanceId.count();
    final row =
        await (database.selectOnly(database.questInstances)
              ..addColumns([count])
              ..where(
                database.questInstances.ownerId.equals(ownerId) &
                    database.questInstances.state.equals(state),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> _evidenceBearingActiveQuestCount(String ownerId) async {
    final activeInstances =
        await (database.select(database.questInstances)..where(
              (row) => row.ownerId.equals(ownerId) & row.state.equals('active'),
            ))
            .get();
    if (activeInstances.isEmpty) return 0;

    final progressRows =
        await (database.select(database.questObjectiveProgress)..where(
              (row) =>
                  row.instanceId.isIn(
                    activeInstances
                        .map((instance) => instance.instanceId)
                        .toList(growable: false),
                  ) &
                  row.currentCount.isBiggerThanValue(0),
            ))
            .get();
    final evidenceBearingInstances = <String>{};
    for (final progress in progressRows) {
      if (_hasCanonicalQuestEvidence(
        currentCount: progress.currentCount,
        targetCount: progress.targetCount,
        sourceEventIdsJson: progress.sourceEventIdsJson,
      )) {
        evidenceBearingInstances.add(progress.instanceId);
      }
    }
    return evidenceBearingInstances.length;
  }

  Future<int> _ownedRewardItemCount(String ownerId) async {
    final count = database.ownedRewardItems.id.count();
    final row =
        await (database.selectOnly(database.ownedRewardItems)
              ..addColumns([count])
              ..where(database.ownedRewardItems.ownerId.equals(ownerId)))
            .getSingle();
    return row.read(count) ?? 0;
  }
}

ProfileAxisAvailability _availability(bool available) => available
    ? ProfileAxisAvailability.available
    : ProfileAxisAvailability.noEvidence;

void _requireIdentifier(String value, String name) {
  if (value.isEmpty || value.trim() != value || value.length > 256) {
    throw ArgumentError.value(value, name, 'must be canonical bounded text');
  }
}

bool _hasCanonicalQuestEvidence({
  required int currentCount,
  required int targetCount,
  required String sourceEventIdsJson,
}) {
  if (currentCount < 1 || targetCount < 1 || currentCount > targetCount) {
    return false;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(sourceEventIdsJson);
  } on FormatException {
    return false;
  }
  if (decoded is! List || decoded.length != currentCount) return false;
  final uniqueEventIds = <String>{};
  for (final value in decoded) {
    if (value is! String ||
        value.isEmpty ||
        value.trim() != value ||
        value.length > 256 ||
        !uniqueEventIds.add(value)) {
      return false;
    }
  }
  return true;
}
