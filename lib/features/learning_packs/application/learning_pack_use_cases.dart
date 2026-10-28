import '../../progress/application/progress_use_cases.dart';
import '../../progress/domain/progress_models.dart';
import '../domain/learning_pack.dart';
import '../domain/learning_pack_repository.dart';
import '../domain/learning_pack_detail.dart';
import '../domain/content_manifest.dart';

/// Read-only composition for the one study-planning parent delivery.
final class StudyPlanningUseCases {
  const StudyPlanningUseCases({required this.packs, required this.progress});

  final LearningPackRepository packs;
  final ProgressUseCases progress;

  Future<LearningPackCatalog> listPacks(LearningPackFilter filter) async {
    final summaries = await packs.list(filter);
    final snapshot = await progress.load();
    return LearningPackCatalog(packs: summaries, progress: snapshot);
  }

  Future<LearningPackDetail> loadPinnedVersion(ContentIdentity identity) async {
    if (identity.type != ContentType.learningPack || identity.revision < 1) {
      throw ArgumentError.value(
        identity,
        'identity',
        'must pin a pack revision',
      );
    }
    final detail = await packs.getVersion(identity.id, identity.revision);
    if (detail.summary.contentIdentity != identity) {
      throw StateError('Learning-pack identity drift.');
    }
    return detail;
  }
}

/// The progress value remains the canonical Progress projection; packs have
/// no progress columns or writer.
final class LearningPackCatalog {
  const LearningPackCatalog({required this.packs, required this.progress});

  final List<LearningPackSummary> packs;
  final ProgressSnapshot progress;
}
