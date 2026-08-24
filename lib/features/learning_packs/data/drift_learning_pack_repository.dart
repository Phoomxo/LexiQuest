import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../domain/content_manifest.dart';
import '../domain/learning_pack.dart';
import '../domain/learning_pack_repository.dart';

/// Drift read adapter for the immutable v16 pack catalog. Verification stays
/// delegated to f04's canonical manifest authority.
final class DriftLearningPackRepository implements LearningPackRepository {
  const DriftLearningPackRepository(
    this.database, {
    required this.contentManifests,
  });

  final AppDatabase database;
  final ContentManifestRepository contentManifests;

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async {
    final visibleManifestRows =
        await (database.select(database.contentManifests)..where(
              (manifest) =>
                  manifest.contentType.equals(ContentType.learningPack.name) &
                  manifest.provenance.equals(ContentProvenance.packaged.name) &
                  manifest.reviewState.equals(
                    ContentReviewState.approved.name,
                  ) &
                  manifest.publicationState.equals(
                    ContentPublicationState.published.name,
                  ),
            ))
            .get();
    if (visibleManifestRows.isEmpty) return const [];

    final manifestIds = visibleManifestRows
        .map((manifest) => manifest.id)
        .toList(growable: false);
    final rows = await (database.select(
      database.learningPacks,
    )..where((pack) => pack.manifestId.isIn(manifestIds))).get();
    final summaries = <LearningPackSummary>[];
    for (final row in rows) {
      final summary = LearningPackSummary(
        packId: row.packId,
        revision: row.revision,
        title: row.title,
        cefrLevel: row.cefrLevel,
        topic: row.topic,
        skill: row.skill,
        goal: row.goal,
        contentIdentity: ContentIdentity(
          type: ContentType.learningPack,
          id: row.packId,
          revision: row.revision,
        ),
      );
      if (!filter.matches(summary)) continue;

      // This verifies lifecycle metadata, checksum, pinned canonical word ids,
      // and referenced lexical revisions before a row reaches the UI.
      await contentManifests.requireVerified(summary.contentIdentity);
      summaries.add(summary);
    }
    summaries.sort(_compareSummaries);
    return List<LearningPackSummary>.unmodifiable(summaries);
  }

  static int _compareSummaries(
    LearningPackSummary left,
    LearningPackSummary right,
  ) {
    final byTitle = left.title.compareTo(right.title);
    if (byTitle != 0) return byTitle;
    final byId = left.packId.compareTo(right.packId);
    if (byId != 0) return byId;
    return left.revision.compareTo(right.revision);
  }
}
