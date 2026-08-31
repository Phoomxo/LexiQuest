import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../domain/offline_content_repository.dart';
import '../domain/offline_content_state.dart';

final class DriftOfflineContentRepository implements OfflineContentRepository {
  const DriftOfflineContentRepository(this.database);

  final AppDatabase database;

  @override
  Future<ContentManifest> requireManifest(ContentIdentity identity) async {
    final row =
        await (database.select(database.contentManifests)..where(
              (candidate) =>
                  candidate.contentType.equals(identity.type.name) &
                  candidate.contentId.equals(identity.id) &
                  candidate.revision.equals(identity.revision),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    return _manifest(row);
  }

  @override
  Future<List<OfflineContentState>> catalog() async {
    final rows =
        await (database.select(database.contentManifests)..orderBy([
              (row) => OrderingTerm.asc(row.contentType),
              (row) => OrderingTerm.asc(row.contentId),
              (row) => OrderingTerm.desc(row.revision),
            ]))
            .get();
    final states = <OfflineContentState>[];
    for (final row in rows) {
      try {
        final manifest = _manifest(row);
        states.add(await _stateForManifest(manifest));
      } on OfflineContentFailure {
        // Invalid/unreviewed content is not a downloadable catalog entry.
      }
    }
    return List<OfflineContentState>.unmodifiable(states);
  }

  @override
  Future<OfflineContentState> state(ContentIdentity identity) async {
    return _stateForManifest(await requireManifest(identity));
  }

  @override
  Future<void> markDownloading(
    ContentManifest manifest, {
    required int downloadedBytes,
    required DateTime updatedAtUtc,
  }) {
    if (downloadedBytes < 0) {
      throw ArgumentError.value(downloadedBytes, 'downloadedBytes');
    }
    return _upsert(
      manifest,
      status: OfflineContentStatus.downloading,
      localPath: null,
      downloadedBytes: downloadedBytes,
      verifiedChecksumSha256: null,
      failureCode: null,
      updatedAtUtc: updatedAtUtc,
    );
  }

  @override
  Future<void> markFailure(
    ContentManifest manifest, {
    required OfflineContentStatus status,
    required OfflineContentFailureCode failureCode,
    required int downloadedBytes,
    required DateTime updatedAtUtc,
  }) {
    if (status != OfflineContentStatus.interrupted &&
        status != OfflineContentStatus.quarantined) {
      throw ArgumentError.value(status, 'status');
    }
    return _upsert(
      manifest,
      status: status,
      localPath: null,
      downloadedBytes: downloadedBytes,
      verifiedChecksumSha256: null,
      failureCode: failureCode,
      updatedAtUtc: updatedAtUtc,
    );
  }

  @override
  Future<void> persistVerified(VerifiedDownloadedArtifact artifact) {
    return database.transaction(() async {
      final persisted = await requireManifest(artifact.manifest.identity);
      if (!_sameManifest(persisted, artifact.manifest)) {
        throw const OfflineContentFailure(
          OfflineContentFailureCode.revisionMismatch,
        );
      }
      final expectedPath = OfflineContentArtifactKey.forManifest(
        persisted,
      ).publishedName;
      if (artifact.localPath != expectedPath) {
        throw const OfflineContentFailure(
          OfflineContentFailureCode.invalidState,
        );
      }
      await _upsert(
        persisted,
        status: OfflineContentStatus.verified,
        localPath: artifact.localPath,
        downloadedBytes: artifact.totalInstalledBytes,
        verifiedChecksumSha256: artifact.checksumSha256,
        failureCode: null,
        updatedAtUtc: artifact.verifiedAtUtc,
      );
    });
  }

  @override
  Future<void> markNotDownloaded(
    ContentManifest manifest, {
    required DateTime updatedAtUtc,
  }) => _upsert(
    manifest,
    status: OfflineContentStatus.notDownloaded,
    localPath: null,
    downloadedBytes: 0,
    verifiedChecksumSha256: null,
    failureCode: null,
    updatedAtUtc: updatedAtUtc,
  );

  Future<OfflineContentState> _stateForManifest(
    ContentManifest manifest,
  ) async {
    final row =
        await (database.select(database.contentDownloadStates)..where(
              (candidate) => candidate.manifestId.equals(manifest.storageId),
            ))
            .getSingleOrNull();
    if (row != null && row.id != _stateId(manifest.storageId)) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    if (row == null) {
      return OfflineContentState(
        manifestId: manifest.storageId,
        identity: manifest.identity,
        status: OfflineContentStatus.notDownloaded,
        localPath: null,
        downloadedBytes: 0,
        verifiedChecksumSha256: null,
        failureCode: null,
        updatedAtUtc: manifest.publishedAtUtc!,
      );
    }
    final status = _enumByName(OfflineContentStatus.values, row.state);
    final failure = row.failureCode == null
        ? null
        : _enumByName(OfflineContentFailureCode.values, row.failureCode!);
    if (status == null ||
        (row.failureCode != null && failure == null) ||
        (status == OfflineContentStatus.verified &&
            (row.localPath == null ||
                row.localPath !=
                    OfflineContentArtifactKey.forManifest(
                      manifest,
                    ).publishedName ||
                row.verifiedChecksumSha256 != manifest.checksumSha256 ||
                row.downloadedBytes < manifest.byteLength))) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    try {
      return OfflineContentState(
        manifestId: manifest.storageId,
        identity: manifest.identity,
        status: status,
        localPath: row.localPath,
        downloadedBytes: row.downloadedBytes,
        verifiedChecksumSha256: row.verifiedChecksumSha256,
        failureCode: failure,
        updatedAtUtc: _utc(row.updatedAtUtcMs),
      );
    } on ArgumentError catch (error) {
      throw OfflineContentFailure(
        OfflineContentFailureCode.invalidState,
        error,
      );
    }
  }

  Future<void> _upsert(
    ContentManifest manifest, {
    required OfflineContentStatus status,
    required String? localPath,
    required int downloadedBytes,
    required String? verifiedChecksumSha256,
    required OfflineContentFailureCode? failureCode,
    required DateTime updatedAtUtc,
  }) async {
    _requireUtc(updatedAtUtc);
    final persisted = await requireManifest(manifest.identity);
    if (!_sameManifest(persisted, manifest)) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    await database
        .into(database.contentDownloadStates)
        .insertOnConflictUpdate(
          ContentDownloadStatesCompanion.insert(
            id: _stateId(manifest.storageId),
            manifestId: manifest.storageId,
            state: Value(status.name),
            localPath: Value(localPath),
            downloadedBytes: Value(downloadedBytes),
            verifiedChecksumSha256: Value(verifiedChecksumSha256),
            failureCode: Value(failureCode?.name),
            updatedAtUtcMs: updatedAtUtc.millisecondsSinceEpoch,
          ),
        );
  }

  ContentManifest _manifest(ContentManifestRow row) {
    final type = _enumByName(ContentType.values, row.contentType);
    final provenance = _enumByName(ContentProvenance.values, row.provenance);
    final review = _enumByName(ContentReviewState.values, row.reviewState);
    final publication = _enumByName(
      ContentPublicationState.values,
      row.publicationState,
    );
    final reviewedAt = row.reviewedAtUtcMs == null
        ? null
        : _utc(row.reviewedAtUtcMs!);
    final publishedAt = row.publishedAtUtcMs == null
        ? null
        : _utc(row.publishedAtUtcMs!);
    if (type == null ||
        provenance == null ||
        review == null ||
        publication == null ||
        reviewedAt == null ||
        publishedAt == null) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    if (provenance != ContentProvenance.packaged ||
        review != ContentReviewState.approved ||
        publication != ContentPublicationState.published ||
        !_sha256.hasMatch(row.checksumSha256) ||
        row.byteLength <= 0 ||
        row.revision <= 0 ||
        !_canonicalText(row.id) ||
        !_canonicalText(row.contentId) ||
        !_canonicalText(row.sourceUri, maxLength: 2048) ||
        row.createdAtUtcMs < 0 ||
        (row.reviewedAtUtcMs ?? -1) < 0 ||
        (row.publishedAtUtcMs ?? -1) < 0 ||
        reviewedAt.isBefore(_utc(row.createdAtUtcMs)) ||
        publishedAt.isBefore(reviewedAt)) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    try {
      OfflineContentArtifactKey.requireCanonicalIdentity(
        ContentIdentity(type: type, id: row.contentId, revision: row.revision),
      );
      if (row.id.contains('/') ||
          row.id.contains('\\') ||
          row.id.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
        throw ArgumentError.value(row.id, 'manifest.storageId');
      }
    } on ArgumentError {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    return ContentManifest(
      storageId: row.id,
      identity: ContentIdentity(
        type: type,
        id: row.contentId,
        revision: row.revision,
      ),
      checksumSha256: row.checksumSha256,
      byteLength: row.byteLength,
      provenance: provenance,
      sourceUri: row.sourceUri,
      reviewState: review,
      publicationState: publication,
      createdAtUtc: _utc(row.createdAtUtcMs),
      reviewedAtUtc: reviewedAt,
      publishedAtUtc: publishedAt,
    );
  }
}

final class DriftOfflineContentRemovalAuthority
    implements OfflineContentRemovalAuthority {
  const DriftOfflineContentRemovalAuthority(this.database);

  final AppDatabase database;

  @override
  Future<bool> isRequired(ContentIdentity identity) =>
      database.transaction(() => _isRequired(identity));

  @override
  Future<T> withRemovalLease<T>(
    ContentIdentity identity,
    Future<T> Function() operation,
  ) => database.transaction(() async {
    if (await _isRequired(identity)) {
      throw const OfflineContentFailure(OfflineContentFailureCode.contentInUse);
    }
    return operation();
  });

  Future<bool> _isRequired(ContentIdentity identity) async {
    OfflineContentArtifactKey.requireCanonicalIdentity(identity);
    final sessions = await database
        .customSelect(
          'SELECT session_configuration_json FROM learning_sessions '
          "WHERE state NOT IN ('completed', 'abandoned')",
        )
        .get();
    for (final row in sessions) {
      final serialized = row.readNullable<String>('session_configuration_json');
      if (serialized == null) {
        throw const OfflineContentFailure(
          OfflineContentFailureCode.invalidState,
        );
      }
      try {
        final configuration = SessionConfiguration.fromStableSerialization(
          serialized,
        );
        if (configuration.packIdentity == identity) return true;
      } on Object catch (error) {
        throw OfflineContentFailure(
          OfflineContentFailureCode.invalidState,
          error,
        );
      }
    }
    if (identity.type != ContentType.assessmentForm) return false;
    final manifest =
        await (database.select(database.contentManifests)..where(
              (row) =>
                  row.contentType.equals(identity.type.name) &
                  row.contentId.equals(identity.id) &
                  row.revision.equals(identity.revision),
            ))
            .getSingleOrNull();
    if (manifest == null) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    final activeAssessment = await database
        .customSelect(
          'SELECT 1 FROM assessment_runs '
          'WHERE state = ? AND form_id = ? AND form_checksum_sha256 = ? '
          'LIMIT 1',
          variables: [
            const Variable<String>('active'),
            Variable<String>(identity.id),
            Variable<String>(manifest.checksumSha256),
          ],
        )
        .getSingleOrNull();
    return activeAssessment != null;
  }
}

String _stateId(String manifestId) =>
    'offline:${sha256.convert(utf8.encode(manifestId))}';

bool _sameManifest(ContentManifest left, ContentManifest right) =>
    left.storageId == right.storageId &&
    left.identity == right.identity &&
    left.checksumSha256 == right.checksumSha256 &&
    left.byteLength == right.byteLength &&
    left.provenance == right.provenance &&
    left.sourceUri == right.sourceUri &&
    left.reviewState == right.reviewState &&
    left.publicationState == right.publicationState &&
    left.createdAtUtc == right.createdAtUtc &&
    left.reviewedAtUtc == right.reviewedAtUtc &&
    left.publishedAtUtc == right.publishedAtUtc;

T? _enumByName<T extends Enum>(Iterable<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

void _requireUtc(DateTime value) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, 'updatedAtUtc', 'must be UTC');
  }
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

bool _canonicalText(String value, {int maxLength = 256}) =>
    value.isNotEmpty &&
    value == value.trim() &&
    value.runes.length <= maxLength;
