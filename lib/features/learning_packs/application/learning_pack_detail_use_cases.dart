import '../../learning/application/lesson_mode_registry.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../progress/application/progress_use_cases.dart';
import '../../progress/domain/progress_models.dart';
import '../../../runtime/production_feature_contract.dart';
import '../../../runtime/registries/feature_registry.dart';
import '../domain/learning_pack_detail.dart';
import '../domain/learning_pack_repository.dart';

/// Read-only composition for a pinned pack revision. Content remains owned by
/// [LearningPackRepository], and progress remains the canonical projection.
typedef ProductionDependencyReadiness = bool Function(Feature feature);

final class LearningPackDetailUseCases {
  const LearningPackDetailUseCases({
    required this.packs,
    required this.progress,
    required this.lessonModes,
    required this.features,
    required this.hasComposedDependency,
  });

  final LearningPackRepository packs;
  final ProgressUseCases progress;
  final LessonModeRegistry? lessonModes;
  final FeatureRegistry? features;
  final ProductionDependencyReadiness hasComposedDependency;

  Future<LearningPackDetailView> loadVersion(
    String packId,
    int revision,
  ) async {
    final detail = await packs.getVersion(packId, revision);
    final snapshot = await progress.load();
    return LearningPackDetailView(
      detail: detail,
      progress: snapshot,
      activities: _activities(),
    );
  }

  List<LearningPackActivity> _activities() {
    final activities = <LearningPackActivity>[];
    for (final mode in LessonMode.values) {
      final registration = lessonModes?.find(mode);
      final availability = _isAvailable(registration)
          ? LearningPackActivityAvailability.available
          : LearningPackActivityAvailability.unavailable;
      activities.add(
        LearningPackActivity(mode: mode, availability: availability),
      );
    }
    activities.sort((left, right) => left.mode.id.compareTo(right.mode.id));
    return List<LearningPackActivity>.unmodifiable(activities);
  }

  bool _isAvailable(LessonModeRegistration? registration) {
    if (registration == null || !hasComposedDependency(registration.feature)) {
      return false;
    }
    final delivery = productionFeatureContract[registration.feature];
    return features?.isEnabled(registration.feature) == true &&
        delivery != null &&
        delivery.feature == registration.feature &&
        delivery.durable &&
        delivery.productionEntryId.trim().isNotEmpty &&
        delivery.dependencyId.trim().isNotEmpty &&
        registration.productionEntryId == delivery.productionEntryId;
  }
}

final class LearningPackDetailView {
  const LearningPackDetailView({
    required this.detail,
    required this.progress,
    required this.activities,
  });

  final LearningPackDetail detail;
  final ProgressSnapshot progress;
  final List<LearningPackActivity> activities;
}
