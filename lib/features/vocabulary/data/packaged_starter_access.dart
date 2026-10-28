import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/vocabulary_failure.dart';
import 'packaged_starter_catalog.dart';

/// One read authorization for personal content and the exact shipped catalog.
/// Flags such as isGlobal never authorize another learner's vocabulary.
abstract final class PackagedStarterAccess {
  static Expression<bool> wordsFor(db.AppDatabase database, String ownerId) {
    final row = database.vocabularyWords;
    final personal =
        row.ownerId.equals(ownerId) &
        row.ownerId.equals(PackagedStarterCatalog.ownerId).not();
    Expression<bool> known = const Constant(false);
    for (final word in PackagedStarterCatalog.words) {
      final manifest = word.manifest;
      final artifact = existsQuery(
        database.select(database.contentManifests)..where(
          (entry) =>
              entry.id.equals(manifest.storageId) &
              entry.contentType.equals('lexicalMetadata') &
              entry.contentId.equals(word.id) &
              entry.revision.equals(1) &
              entry.checksumSha256.equals(word.artifactHash) &
              entry.byteLength.equals(word.artifactBytes) &
              entry.provenance.equals('packaged') &
              entry.reviewState.equals('approved') &
              entry.publicationState.equals('published') &
              entry.sourceUri.equals(manifest.sourceUri) &
              entry.createdAtUtcMs.equals(
                manifest.createdAtUtc.millisecondsSinceEpoch,
              ) &
              entry.reviewedAtUtcMs.equals(
                manifest.reviewedAtUtc!.millisecondsSinceEpoch,
              ) &
              entry.publishedAtUtcMs.equals(
                manifest.publishedAtUtc!.millisecondsSinceEpoch,
              ),
        ),
      );
      known =
          known |
          (row.id.equals(word.id) &
              row.spelling.equals(word.key) &
              row.normalizedSpelling.equals(word.key) &
              row.meaning.equals(word.meaning) &
              row.normalizedMeaning.equals(word.meaning) &
              row.contentChecksumSha256.equals(word.coreHash) &
              artifact);
    }
    final packaged =
        known &
        _ownerIntact(database) &
        existsQuery(
          database.select(database.vocabularyCategories)
            ..where((_) => _catalogCategory(database)),
        ) &
        row.ownerId.equals(PackagedStarterCatalog.ownerId) &
        row.categoryId.equals(PackagedStarterCatalog.categoryId) &
        row.partOfSpeech.equals('noun') &
        row.cefrLevel.isNull() &
        row.source.equals(PackagedStarterCatalog.source) &
        row.isGlobal.equals(true) &
        row.contentRevision.equals(1) &
        row.contentProvenance.equals('packaged') &
        row.contentReviewState.equals('approved') &
        row.contentPublicationState.equals('published') &
        row.localRevision.equals(1) &
        row.cloudRevision.equals(0) &
        row.lastAcknowledgedAtUtcMs.isNull() &
        row.serverUpdatedAtUtcMs.isNull() &
        row.isDeleted.equals(false) &
        row.createdAtUtcMs.equals(
          PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
        ) &
        row.updatedAtUtcMs.equals(
          PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
        );
    return personal | packaged;
  }

  static Expression<bool> categoriesFor(
    db.AppDatabase database,
    String ownerId,
  ) {
    final row = database.vocabularyCategories;
    return (row.ownerId.equals(ownerId) &
            row.ownerId.equals(PackagedStarterCatalog.ownerId).not()) |
        (_catalogCategory(database) & _ownerIntact(database));
  }

  static Expression<bool> _catalogCategory(db.AppDatabase database) {
    final row = database.vocabularyCategories;
    return row.id.equals(PackagedStarterCatalog.categoryId) &
        row.ownerId.equals(PackagedStarterCatalog.ownerId) &
        row.name.equals(PackagedStarterCatalog.categoryName) &
        row.normalizedName.equals(PackagedStarterCatalog.categoryName) &
        row.sortOrder.equals(0) &
        row.localRevision.equals(1) &
        row.cloudRevision.equals(0) &
        row.lastAcknowledgedAtUtcMs.isNull() &
        row.serverUpdatedAtUtcMs.isNull() &
        row.isDeleted.equals(false) &
        row.createdAtUtcMs.equals(
          PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
        ) &
        row.updatedAtUtcMs.equals(
          PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
        );
  }

  static Expression<bool> _ownerIntact(db.AppDatabase database) => existsQuery(
    database.select(database.localOwners)..where(
      (row) =>
          row.id.equals(PackagedStarterCatalog.ownerId) &
          row.isActive.equals(false) &
          row.firebaseUid.isNull() &
          row.upgradedAtUtcMs.isNull() &
          row.accountState.equals('localGuest') &
          row.createdAtUtcMs.equals(
            PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
          ),
    ),
  );

  static void requireMutable(String ownerId, {String? id, String? categoryId}) {
    if (ownerId == PackagedStarterCatalog.ownerId ||
        (id != null && PackagedStarterCatalog.isReservedId(id)) ||
        (categoryId != null &&
            PackagedStarterCatalog.isReservedId(categoryId))) {
      throw const InvalidVocabularyFailure('packagedContent', 'readOnly');
    }
  }
}
