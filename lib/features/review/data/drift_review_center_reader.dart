import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../learning/data/drift_learning_event_store.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/lexical_prompt_artifact_identity.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import '../../vocabulary/domain/vocabulary_word.dart' as vocabulary_domain;
import '../domain/content_quality_report.dart';
import '../domain/review_queue_item.dart';

final class DriftReviewOwnerIdentityReader
    implements ReviewOwnerIdentityReader {
  const DriftReviewOwnerIdentityReader(this.database);

  final AppDatabase database;

  @override
  Future<String> requireSingleActiveOwnerId() async {
    final rows =
        await (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..orderBy([(row) => OrderingTerm.asc(row.id)])
              ..limit(2))
            .get();
    if (rows.length != 1) {
      throw StateError('review requires exactly one active owner');
    }
    final ownerId = rows.single.id;
    if (ownerId.isEmpty || ownerId != ownerId.trim()) {
      throw StateError('active review owner identity is corrupt');
    }
    return ownerId;
  }
}

final class DriftReviewCenterReader implements ReviewCenterReader {
  DriftReviewCenterReader(
    this.database, {
    DriftLearningEventStore? learningEvents,
    this.contentManifests,
  }) : learningEvents = learningEvents ?? DriftLearningEventStore(database);

  final AppDatabase database;
  final DriftLearningEventStore learningEvents;
  final ContentManifestRepository? contentManifests;

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async {
    if (filter.includeReasons.isEmpty) return const [];
    final categories =
        await (database.select(database.vocabularyCategories)..where(
              (row) =>
                  row.ownerId.equals(filter.ownerId) &
                  row.isDeleted.equals(false),
            ))
            .get();
    final categoryIds = categories.map((row) => row.id).toSet();
    if (categoryIds.isEmpty) return const [];
    final words =
        await (database.select(database.vocabularyWords)..where(
              (row) =>
                  row.ownerId.equals(filter.ownerId) &
                  row.isDeleted.equals(false),
            ))
            .get();
    final available = <_ContentKey, VocabularyWord>{};
    for (final word in words) {
      if (!ContentQualityPolicy.isAvailableVocabulary(
        categoryAvailable: categoryIds.contains(word.categoryId),
        id: word.id,
        categoryId: word.categoryId,
        spelling: word.spelling,
        normalizedSpelling: word.normalizedSpelling,
        meaning: word.meaning,
        normalizedMeaning: word.normalizedMeaning,
        partOfSpeech: word.partOfSpeech,
        cefrLevel: word.cefrLevel,
        source: word.source,
        isGlobal: word.isGlobal,
        contentRevision: word.contentRevision,
        contentChecksumSha256: word.contentChecksumSha256,
        contentProvenance: word.contentProvenance,
        contentReviewState: word.contentReviewState,
        contentPublicationState: word.contentPublicationState,
        isDeleted: word.isDeleted,
      )) {
        continue;
      }
      available[_ContentKey(word.id, word.contentRevision)] = word;
    }
    if (available.isEmpty) return const [];

    final manifestRows =
        await (database.select(database.contentManifests)..where(
              (row) =>
                  row.contentType.equals(ContentType.lexicalMetadata.name) &
                  row.contentId.isIn(
                    available.keys.map((key) => key.id).toSet(),
                  ),
            ))
            .get();
    final manifests = <_ContentKey, ContentManifestRow>{};
    for (final row in manifestRows) {
      if (_isCanonicalLexicalManifest(row)) {
        manifests[_ContentKey(row.contentId, row.revision)] = row;
      }
    }

    final builders = <_ContentKey, _QueueBuilder>{};
    _QueueBuilder? builderFor(String id, int revision) {
      final key = _ContentKey(id, revision);
      final word = available[key];
      if (word == null) return null;
      return builders.putIfAbsent(
        key,
        () => _QueueBuilder(word, manifests[key]),
      );
    }

    await _readDue(filter, available, builderFor);
    await _readIncorrect(filter, available, manifests, builderFor);
    await _readReports(filter, builderFor);
    await _readSaved(filter, builderFor);

    final result =
        builders.values
            .where((builder) => builder.sources.isNotEmpty)
            .map((builder) => builder.build())
            .where((item) => item.hasAnyReason(filter.includeReasons))
            .toList(growable: false)
          ..sort(ReviewQueueItem.compare);
    final limit = filter.limit;
    return List<ReviewQueueItem>.unmodifiable(
      limit == null || result.length <= limit ? result : result.take(limit),
    );
  }

  Future<void> _readDue(
    ReviewQueueFilter filter,
    Map<_ContentKey, VocabularyWord> available,
    _QueueBuilder? Function(String id, int revision) builderFor,
  ) async {
    final rows =
        await (database.select(database.srsStates)..where(
              (row) =>
                  row.ownerId.equals(filter.ownerId) &
                  row.dueAtUtcMs.isSmallerOrEqualValue(
                    filter.evaluatedAtUtc.millisecondsSinceEpoch,
                  ),
            ))
            .get();
    final revisionById = <String, int>{
      for (final entry in available.entries) entry.key.id: entry.key.revision,
    };
    for (final row in rows) {
      final revision = revisionById[row.wordId];
      if (revision == null || row.dueAtUtcMs < 0) continue;
      _tryAdd(
        builderFor(row.wordId, revision),
        () => ReviewReasonProvenance.due(
          sourceId: row.id,
          dueAtUtc: _utc(row.dueAtUtcMs),
        ),
      );
    }
  }

  Future<void> _readIncorrect(
    ReviewQueueFilter filter,
    Map<_ContentKey, VocabularyWord> available,
    Map<_ContentKey, ContentManifestRow> manifests,
    _QueueBuilder? Function(String id, int revision) builderFor,
  ) async {
    final verifiedRichMetadata =
        <_ContentKey, vocabulary_domain.RichLexicalMetadata?>{};
    for (final entry in manifests.entries) {
      verifiedRichMetadata[entry.key] = await _verifiedRichLexicalMetadata(
        entry.key,
        entry.value,
      );
    }
    final sessions = await (database.select(
      database.learningSessions,
    )..where((row) => row.ownerId.equals(filter.ownerId))).get();
    final sessionIds = sessions.map((row) => row.id).toSet();
    if (sessionIds.isEmpty) return;
    final rows =
        await (database.select(database.answerAttempts)..where(
              (row) =>
                  row.ownerId.equals(filter.ownerId) &
                  row.isCorrect.equals(false),
            ))
            .get();
    for (final row in rows) {
      if (!sessionIds.contains(row.sessionId) ||
          row.occurredAtUtcMs < 0 ||
          row.evidenceClass == EvidenceClass.assessment.name ||
          row.evidenceClass == EvidenceClass.recreational.name) {
        continue;
      }
      final source = await _validatedSource(row);
      if (source == null) continue;
      final sourceRevision = source.contentRevision;
      if (sourceRevision == null) continue;
      final availableEntries = available.entries.where(
        (entry) => entry.key.id == row.wordId,
      );
      if (availableEntries.length != 1) continue;
      final availableEntry = availableEntries.single;
      final word = availableEntry.value;
      final manifest = manifests[availableEntry.key];
      final richMetadata = verifiedRichMetadata[availableEntry.key];
      final candidates = LexicalPromptArtifactResolver.resolveReaderCandidates(
        promptMode: row.promptMode,
        wordId: row.wordId,
        coreRevision: word.contentRevision,
        coreChecksumSha256: word.contentChecksumSha256,
        verifiedArtifactLoaded: richMetadata != null,
        usesAcceptedVariants:
            richMetadata?.acceptedSpellingVariants.isNotEmpty ?? false,
        verifiedArtifactRevision: manifest?.revision,
        verifiedArtifactChecksumSha256: manifest?.checksumSha256,
      );
      if (!candidates.any(
        (candidate) => candidate.evidenceContentRevision == sourceRevision,
      )) {
        continue;
      }
      _tryAdd(
        builderFor(row.wordId, word.contentRevision),
        () => ReviewReasonProvenance.incorrect(
          sourceId: row.id,
          occurredAtUtc: _utc(row.occurredAtUtcMs),
        ),
      );
    }
  }

  Future<void> _readReports(
    ReviewQueueFilter filter,
    _QueueBuilder? Function(String id, int revision) builderFor,
  ) async {
    final rows = await (database.select(
      database.contentQualityReports,
    )..where((row) => row.ownerId.equals(filter.ownerId))).get();
    for (final row in rows) {
      if (row.contentType != ContentType.lexicalMetadata.name ||
          row.contentRevision <= 0 ||
          row.submittedAtUtcMs < 0) {
        continue;
      }
      final reason = _enumByName(ContentReportReason.values, row.reasonCode);
      if (reason == null) continue;
      _tryAdd(
        builderFor(row.contentId, row.contentRevision),
        () => ReviewReasonProvenance.reported(
          sourceId: row.id,
          occurredAtUtc: _utc(row.submittedAtUtcMs),
          reportReason: reason,
        ),
      );
    }
  }

  Future<void> _readSaved(
    ReviewQueueFilter filter,
    _QueueBuilder? Function(String id, int revision) builderFor,
  ) async {
    final rows =
        await (database.select(database.savedLearningItems)..where(
              (row) =>
                  row.ownerId.equals(filter.ownerId) &
                  row.isDeleted.equals(false),
            ))
            .get();
    for (final row in rows) {
      if (row.contentType != ContentType.lexicalMetadata.name ||
          row.contentRevision <= 0 ||
          row.savedAtUtcMs < 0) {
        continue;
      }
      _tryAdd(
        builderFor(row.contentId, row.contentRevision),
        () => ReviewReasonProvenance.saved(
          sourceId: row.id,
          occurredAtUtc: _utc(row.savedAtUtcMs),
        ),
      );
    }
  }

  Future<EventEnvelopeV2?> _validatedSource(AnswerAttempt row) async {
    try {
      return await learningEvents.readValidatedSourceForAttempt(attempt: row);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    } on StateError {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<vocabulary_domain.RichLexicalMetadata?> _verifiedRichLexicalMetadata(
    _ContentKey key,
    ContentManifestRow manifestRow,
  ) async {
    final manifests = contentManifests;
    if (manifests == null) return null;
    final identity = ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: key.id,
      revision: key.revision,
    );
    try {
      final verified = await manifests.requireVerified(identity);
      if (verified.manifest.identity != identity ||
          verified.manifest.checksumSha256 != manifestRow.checksumSha256 ||
          verified.manifest.byteLength != manifestRow.byteLength) {
        return null;
      }
      final metadata =
          vocabulary_domain.RichLexicalMetadata.fromVerifiedArtifact(
            bytes: verified.bytes,
            wordId: key.id,
            contentRevision: key.revision,
            verifiedArtifactChecksumSha256: verified.manifest.checksumSha256,
          );
      if (metadata.verifiedContentRevision != key.revision ||
          metadata.verifiedArtifactChecksumSha256 !=
              manifestRow.checksumSha256) {
        return null;
      }
      return metadata;
    } on Object {
      return null;
    }
  }
}

bool _isCanonicalLexicalManifest(ContentManifestRow row) =>
    row.contentType == ContentType.lexicalMetadata.name &&
    row.contentId.isNotEmpty &&
    row.contentId == row.contentId.trim() &&
    row.revision > 0 &&
    _sha256.hasMatch(row.checksumSha256) &&
    row.byteLength > 0 &&
    row.provenance == ContentProvenance.packaged.name &&
    row.sourceUri.isNotEmpty &&
    row.sourceUri == row.sourceUri.trim() &&
    row.reviewState == ContentReviewState.approved.name &&
    row.publicationState == ContentPublicationState.published.name &&
    row.createdAtUtcMs >= 0 &&
    row.reviewedAtUtcMs != null &&
    row.reviewedAtUtcMs! >= 0 &&
    row.publishedAtUtcMs != null &&
    row.publishedAtUtcMs! >= 0;

final class _ContentKey {
  const _ContentKey(this.id, this.revision);

  final String id;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is _ContentKey && other.id == id && other.revision == revision;

  @override
  int get hashCode => Object.hash(id, revision);
}

final class _QueueBuilder {
  _QueueBuilder(this.word, this.manifest);

  final VocabularyWord word;
  final ContentManifestRow? manifest;
  final List<ReviewReasonProvenance> sources = [];

  ReviewQueueItem build() => ReviewQueueItem(
    snapshot: ReviewedLexicalContentSnapshot(
      identity: ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: word.id,
        revision: word.contentRevision,
      ),
      categoryId: word.categoryId,
      spelling: word.spelling,
      normalizedSpelling: word.normalizedSpelling,
      meaning: word.meaning,
      normalizedMeaning: word.normalizedMeaning,
      partOfSpeech: word.partOfSpeech,
      cefrLevel: word.cefrLevel,
      source: word.source,
      isGlobal: word.isGlobal,
      coreChecksumSha256: word.contentChecksumSha256!,
      provenance: ContentProvenance.values.byName(word.contentProvenance),
      reviewState: ContentReviewState.values.byName(word.contentReviewState),
      publicationState: ContentPublicationState.values.byName(
        word.contentPublicationState,
      ),
      artifact: manifest == null
          ? null
          : ReviewedLexicalArtifactSnapshot(
              storageId: manifest!.id,
              identity: ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: manifest!.contentId,
                revision: manifest!.revision,
              ),
              checksumSha256: manifest!.checksumSha256,
              byteLength: manifest!.byteLength,
            ),
    ),
    provenance: sources,
  );
}

void _tryAdd(_QueueBuilder? builder, ReviewReasonProvenance Function() create) {
  if (builder == null) return;
  try {
    builder.sources.add(create());
  } catch (_) {
    // Corrupt or ambiguous authority rows fail closed at the read boundary.
  }
}

T? _enumByName<T extends Enum>(Iterable<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
