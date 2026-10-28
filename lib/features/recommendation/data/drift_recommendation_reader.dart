import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../preferences/data/drift_learner_preferences_repository.dart';
import '../../preferences/domain/learner_preferences.dart';
import '../../progress/data/drift_personal_learning_profile_reader.dart';
import '../../progress/data/drift_progress_queries.dart';
import '../../progress/domain/personal_learning_profile.dart';
import '../domain/recommendation_models.dart';

/// Immutable read-only input for f37's application policy.
final class RecommendationReadModel {
  RecommendationReadModel({
    required this.ownerId,
    required this.profile,
    required this.preferences,
    required List<RecommendationDecision> decisions,
    required this.latestPracticeEvidenceAtUtc,
  }) : decisions = List<RecommendationDecision>.unmodifiable(decisions);

  final String ownerId;
  final PersonalLearningProfile profile;
  final LearnerPreferences preferences;
  final List<RecommendationDecision> decisions;
  final DateTime? latestPracticeEvidenceAtUtc;
}

/// Composes existing canonical readers without owning or persisting a result.
final class DriftRecommendationReader {
  DriftRecommendationReader(
    AppDatabase database, {
    DriftProgressQueries? progress,
    DriftPersonalLearningProfileReader? profiles,
    DriftLearnerPreferencesRepository? preferences,
  }) : database = database,
       progress = progress ?? DriftProgressQueries(database),
       profiles = profiles ?? DriftPersonalLearningProfileReader(database),
       preferences = preferences ?? DriftLearnerPreferencesRepository(database);

  final AppDatabase database;
  final DriftProgressQueries progress;
  final DriftPersonalLearningProfileReader profiles;
  final DriftLearnerPreferencesRepository preferences;

  /// Confirms the owner supplied by the f42 composition seam without creating
  /// a guest owner or initializing any owner-scoped projection.
  Future<bool> hasActiveOwner(String ownerId) async {
    _requireIdentifier(ownerId, 'ownerId');
    final row =
        await (database.select(database.localOwners)..where(
              (candidate) =>
                  candidate.id.equals(ownerId) &
                  candidate.isActive.equals(true),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<RecommendationReadModel> load({
    required String ownerId,
    required DateTime nowUtc,
    required String timezoneId,
  }) async {
    _requireIdentifier(ownerId, 'ownerId');
    _requireIdentifier(timezoneId, 'timezoneId');
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    final profile = await profiles.load(
      ownerId: ownerId,
      nowUtc: nowUtc,
      timezoneId: timezoneId,
    );
    final learnerPreferences = await preferences.read(ownerId);
    final decisions = await progress.loadFlashcardFirstDecisions(
      ownerId: ownerId,
      nowUtc: nowUtc,
    );
    final latestPracticeEvidenceAtUtc = await progress
        .loadLatestPracticeEvidenceAtUtc(ownerId: ownerId);
    return RecommendationReadModel(
      ownerId: ownerId,
      profile: profile,
      preferences: learnerPreferences,
      decisions: decisions,
      latestPracticeEvidenceAtUtc: latestPracticeEvidenceAtUtc,
    );
  }
}

void _requireIdentifier(String value, String name) {
  if (value.isEmpty || value.trim() != value || value.runes.length > 256) {
    throw ArgumentError.value(value, name, 'must be canonical bounded text');
  }
}
