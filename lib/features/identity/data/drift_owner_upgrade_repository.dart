import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../assessment/data/drift_assessment_repository.dart';
import '../../assessment/domain/assessment_models.dart';
import '../../assessment/domain/assessment_repository.dart';
import '../../learning/data/drift_learning_projection_rebuilder.dart';
import '../../learning/data/drift_learning_event_store.dart';
import '../../learning/domain/evidence_eligibility_policy.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../learning/domain/srs_operation_identity.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning_packs/domain/content_quality_policy.dart';
import '../../motivation/data/drift_streak_repository.dart';
import '../../rewards/data/drift_avatar_progression_eligibility.dart';
import '../../rewards/data/drift_economy_cutover.dart';
import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import '../../rewards/domain/avatar_progression_policy.dart';
import '../../rewards/domain/reward_models.dart';
import '../../research/data/drift_experiment_assignment_repository.dart';
import '../../research/domain/experiment_assignment.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../sync/domain/owner_operation_gate.dart';
import '../../sync/domain/sync_failure.dart';
import '../../sync/domain/sync_store.dart';
import '../../time_tracking/domain/learning_time_segment.dart';
import '../domain/owner_upgrade.dart';

typedef OwnerUpgradeUtcNow = DateTime Function();
typedef OwnerUpgradeIdGenerator = String Function();
typedef DeleteOwnerSecretsForUpgrade = Future<void> Function(String ownerId);
typedef DeleteOwnerSecretsFencedForUpgrade =
    Future<void> Function(String ownerId, String operationToken);
typedef OwnerUpgradeGateDelay = Future<void> Function(Duration delay);

final class DriftOwnerUpgradeRepository implements OwnerUpgradeRepository {
  DriftOwnerUpgradeRepository(
    this._database, {
    required this.nowUtc,
    required this.generateConflictId,
    required this.generateOwnerId,
    required this.generateOwnerOperationToken,
    required this.deleteOwnerSecrets,
    this.deleteOwnerSecretsFenced,
    OwnerOperationGate? ownerOperationGate,
    this.ownerGateDelay = _defaultOwnerGateDelay,
    this.ownerGateLeaseDuration = const Duration(minutes: 10),
    this.ownerGateHeartbeatInterval = const Duration(minutes: 3),
    this.ownerGateRetryInterval = const Duration(milliseconds: 50),
    this.ownerGateWaitTimeout = const Duration(seconds: 30),
    this.evidencePolicy = const EvidenceEligibilityPolicySet(),
    this.rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
  }) : ownerOperationGate =
           ownerOperationGate ?? DriftOwnerOperationGate(_database);

  final db.AppDatabase _database;
  final OwnerUpgradeUtcNow nowUtc;
  final OwnerUpgradeIdGenerator generateConflictId;
  final OwnerUpgradeIdGenerator generateOwnerId;
  final OwnerUpgradeIdGenerator generateOwnerOperationToken;
  final DeleteOwnerSecretsForUpgrade deleteOwnerSecrets;
  final DeleteOwnerSecretsFencedForUpgrade? deleteOwnerSecretsFenced;
  final OwnerOperationGate ownerOperationGate;
  final OwnerUpgradeGateDelay ownerGateDelay;
  final Duration ownerGateLeaseDuration;
  final Duration ownerGateHeartbeatInterval;
  final Duration ownerGateRetryInterval;
  final Duration ownerGateWaitTimeout;
  final EvidenceEligibilityPolicy evidencePolicy;
  final EvidencePolicyRolloutModeProvider rolloutModeProvider;
  Future<void> _writeGate = Future<void>.value();

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) {
    final sourceId = _requiredId(activeOwnerId, 'activeOwnerId');
    final uid = _requiredId(firebaseUid, 'firebaseUid');
    return _serialized(
      () => _withOwnerOperationGate((operationToken) async {
        final sourceBeforeTransaction = await _ownerById(sourceId);
        if (sourceBeforeTransaction == null ||
            !sourceBeforeTransaction.isActive) {
          throw StateError('active local owner was not found');
        }
        final targetBeforeTransaction = await _ownerByFirebaseUid(uid);
        if (sourceBeforeTransaction.firebaseUid != uid &&
            targetBeforeTransaction != null) {
          // External secret deletion is intentionally outside SQLite. A later
          // inventory rollback cannot restore the deleted credential.
          final fencedDelete = deleteOwnerSecretsFenced;
          if (fencedDelete == null) {
            await deleteOwnerSecrets(sourceBeforeTransaction.id);
          } else {
            await fencedDelete(sourceBeforeTransaction.id, operationToken);
          }
        }

        return _database.transaction(() async {
          if (!await _fenceOwnerTransition(operationToken)) {
            throw StateError('owner-operation gate was lost');
          }
          final source = await _ownerById(sourceId);
          if (source == null || !source.isActive) {
            throw StateError('active local owner was not found');
          }
          if (source.firebaseUid == uid) {
            final avatarEligibility = DriftAvatarProgressionEligibility(
              _database,
              nowUtc: nowUtc,
            );
            final avatarReady = await _tryEstablishAvatarCutover(
              avatarEligibility,
              source.id,
            );
            await DriftStreakRepository(_database).establishCutover(
              ownerId: source.id,
              establishedAtUtc: _requireUtc(nowUtc()),
            );
            await DriftEconomyCutover(_database).ensureSeparated(source.id);
            await _rebuildAvatarOrQuarantine(
              avatarEligibility,
              source.id,
              avatarReady: avatarReady,
            );
            return OwnerUpgradeResult(
              targetOwnerId: source.id,
              mode: OwnerUpgradeMode.alreadyBound,
              conflictCount: 0,
            );
          }

          final target = await _ownerByFirebaseUid(uid);
          final upgradedAtUtc = _requireUtc(nowUtc());
          final upgradedAt = upgradedAtUtc.millisecondsSinceEpoch;
          if (target == null) {
            final avatarEligibility = DriftAvatarProgressionEligibility(
              _database,
              nowUtc: nowUtc,
            );
            final avatarReady = await _tryEstablishAvatarCutover(
              avatarEligibility,
              source.id,
            );
            await DriftStreakRepository(_database).establishCutover(
              ownerId: source.id,
              establishedAtUtc: upgradedAtUtc,
            );
            await DriftEconomyCutover(_database).ensureSeparated(source.id);
            await _rebuildAvatarOrQuarantine(
              avatarEligibility,
              source.id,
              avatarReady: avatarReady,
            );
            await _requeueOwnerForNewCloudNamespace(source.id, upgradedAt);
            await _reconcileExperimentAssignmentOutbox(
              ownerId: source.id,
              firebaseUid: uid,
              historicalOwnerIds: <String>{source.id},
            );
            await (_database.update(
              _database.localOwners,
            )..where((row) => row.id.equals(source.id))).write(
              db.LocalOwnersCompanion(
                firebaseUid: Value(uid),
                accountState: const Value('firebaseBound'),
                upgradedAtUtcMs: Value(upgradedAt),
              ),
            );
            return OwnerUpgradeResult(
              targetOwnerId: source.id,
              mode: OwnerUpgradeMode.anonymousBound,
              conflictCount: 0,
            );
          }

          await DriftStreakRepository(_database).mergeCutovers(
            sourceId: source.id,
            targetId: target.id,
            establishedAtUtc: upgradedAtUtc,
          );
          final avatarProgressionEligibility =
              DriftAvatarProgressionEligibility(_database, nowUtc: nowUtc);
          final sourceAvatarReady = await _tryEstablishAvatarCutover(
            avatarProgressionEligibility,
            source.id,
          );
          final targetAvatarReady = await _tryEstablishAvatarCutover(
            avatarProgressionEligibility,
            target.id,
          );
          final avatarCutoversReady = sourceAvatarReady && targetAvatarReady;
          var convertedTargetAvatarTransactionIds = const <String>{};
          if (!avatarCutoversReady) {
            convertedTargetAvatarTransactionIds =
                await avatarProgressionEligibility
                    .detachCutoversForQuarantinedMerge(
                      sourceId: source.id,
                      targetId: target.id,
                    );
          }
          var conflicts = 0;
          conflicts += await _mergeCategories(source.id, target.id, upgradedAt);
          conflicts += await _mergeWords(source.id, target.id, upgradedAt);
          conflicts += await _mergeSrsStates(source.id, target.id, upgradedAt);
          conflicts += await _mergeStreakState(
            source.id,
            target.id,
            upgradedAt,
          );
          conflicts += await _mergeLearningDays(
            source.id,
            target.id,
            upgradedAt,
          );
          conflicts += await _mergeAssociativeState(
            source.id,
            target.id,
            upgradedAt,
          );
          conflicts += await _mergeQuestState(source.id, target.id, upgradedAt);
          await _makeImportKeysUnique(source.id, target.id);
          conflicts += await _makeRewardKeysUnique(
            source.id,
            target.id,
            upgradedAt,
          );
          if (avatarCutoversReady) {
            await avatarProgressionEligibility.refreshForOwnerMerge(source.id);
            await avatarProgressionEligibility.refreshForOwnerMerge(target.id);
            convertedTargetAvatarTransactionIds =
                await avatarProgressionEligibility.mergeCutovers(
                  sourceId: source.id,
                  targetId: target.id,
                );
          }
          conflicts += await _mergeResearchConsents(
            source.id,
            target.id,
            upgradedAt,
          );
          conflicts += await _mergeSavedLearningItems(
            source.id,
            target.id,
            upgradedAt,
          );
          await _mergeLearnerPreferences(source.id, target.id, upgradedAt);
          await _mergeAssessmentRuns(source.id, target.id);
          await _mergeExperimentAssignments(source.id, target.id);
          conflicts += await _discardNaturalKeyDuplicates(
            source.id,
            target.id,
            upgradedAt,
          );
          await _discardAiUsageDuplicates(source.id, target.id);
          await _requeueOwnerForNewCloudNamespace(source.id, upgradedAt);
          await _reviveConvertedTargetAvatarPermissionFailures(
            ownerId: target.id,
            transactionIds: convertedTargetAvatarTransactionIds,
            rehomedAtUtcMs: upgradedAt,
          );
          await _normalizeLearningProjectionState(source.id, target.id);
          await _mergeSessionConfigurations(source.id, target.id);
          await _rebindLearningSessionConfigurations(source.id, target.id);
          conflicts += await _makeEventKeysUnique(
            source.id,
            target.id,
            upgradedAt,
          );
          await _moveOwnerRows(source.id, target.id);
          await _reconcileExperimentAssignmentOutbox(
            ownerId: target.id,
            firebaseUid: uid,
            historicalOwnerIds: <String>{source.id, target.id},
          );
          await _database.customUpdate(
            'UPDATE local_owners SET is_active = 0 WHERE is_active = 1',
          );
          await _database.customUpdate(
            'UPDATE local_owners '
            'SET is_active = 1, account_state = ?, upgraded_at_utc_ms = ? '
            'WHERE id = ?',
            variables: [
              const Variable<String>('firebaseBound'),
              Variable<int>(upgradedAt),
              Variable<String>(target.id),
            ],
            updates: {_database.localOwners},
          );
          await _database.customUpdate(
            'UPDATE local_owners '
            'SET account_state = ?, upgraded_at_utc_ms = ? WHERE id = ?',
            variables: [
              Variable<String>('mergedInto:${target.id}'),
              Variable<int>(upgradedAt),
              Variable<String>(source.id),
            ],
            updates: {_database.localOwners},
          );
          await _database.customUpdate(
            'UPDATE local_owners '
            'SET account_state = ?, upgraded_at_utc_ms = ? '
            'WHERE account_state = ?',
            variables: [
              Variable<String>('mergedInto:${target.id}'),
              Variable<int>(upgradedAt),
              Variable<String>('mergedInto:${source.id}'),
            ],
            updates: {_database.localOwners},
          );
          await _rebuildLearningProjections(target.id);
          await DriftEconomyCutover(_database).ensureSeparated(target.id);
          await _rebuildAvatarOrQuarantine(
            avatarProgressionEligibility,
            target.id,
            avatarReady: avatarCutoversReady,
          );
          return OwnerUpgradeResult(
            targetOwnerId: target.id,
            mode: OwnerUpgradeMode.mergedExisting,
            conflictCount: conflicts,
          );
        });
      }),
    );
  }

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() {
    return _serialized(
      () => _withOwnerOperationGate((operationToken) {
        return _database.transaction(() async {
          if (!await _fenceOwnerTransition(operationToken)) {
            throw StateError('owner-operation gate was lost');
          }
          final ownerId = 'local:${_requiredId(generateOwnerId(), 'ownerId')}';
          final createdAtUtc = _requireUtc(nowUtc());
          final createdAt = createdAtUtc.millisecondsSinceEpoch;
          await _database.customUpdate(
            'UPDATE local_owners SET is_active = 0 WHERE is_active = 1',
            updates: {_database.localOwners},
          );
          await _database
              .into(_database.localOwners)
              .insert(
                db.LocalOwnersCompanion.insert(
                  id: ownerId,
                  createdAtUtcMs: createdAt,
                ),
              );
          await DriftStreakRepository(
            _database,
          ).establishCutover(ownerId: ownerId, establishedAtUtc: createdAtUtc);
          await DriftAvatarProgressionEligibility(
            _database,
            nowUtc: nowUtc,
          ).establishCutover(ownerId);
          return OwnerUpgradeResult(
            targetOwnerId: ownerId,
            mode: OwnerUpgradeMode.localGuestCreated,
            conflictCount: 0,
          );
        });
      }),
    );
  }

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) {
    final previous = _requiredId(previousOwnerId, 'previousOwnerId');
    final guest = _requiredId(guestOwnerId, 'guestOwnerId');
    return _serialized(
      () => _withOwnerOperationGate((operationToken) {
        return _database.transaction(() async {
          if (!await _fenceOwnerTransition(operationToken)) {
            throw StateError('owner-operation gate was lost');
          }
          final guestRow = await _ownerById(guest);
          final previousRow = await _ownerById(previous);
          if (guestRow == null ||
              previousRow == null ||
              !guestRow.isActive ||
              guestRow.firebaseUid != null) {
            throw StateError('logout rollback state is no longer safe');
          }
          await DriftStreakRepository(_database).rollbackTransitionCutover(
            ownerId: guest,
            establishedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              guestRow.createdAtUtcMs,
              isUtc: true,
            ),
          );
          await DriftAvatarProgressionEligibility(
            _database,
            nowUtc: nowUtc,
          ).rollbackEmptyTransition(guest);
          await (_database.delete(
            _database.localOwners,
          )..where((row) => row.id.equals(guest))).go();
          await (_database.update(_database.localOwners)
                ..where((row) => row.id.equals(previous)))
              .write(const db.LocalOwnersCompanion(isActive: Value(true)));
        });
      }),
    );
  }

  Future<bool> _tryEstablishAvatarCutover(
    DriftAvatarProgressionEligibility eligibility,
    String ownerId,
  ) async {
    try {
      await eligibility.establishCutover(ownerId);
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> _rebuildAvatarOrQuarantine(
    DriftAvatarProgressionEligibility eligibility,
    String ownerId, {
    required bool avatarReady,
  }) async {
    if (avatarReady) {
      try {
        await DriftRewardProjectionRebuilder(
          _database,
          progressionEligibility: eligibility,
        ).rebuild(ownerId);
        return;
      } on StateError {
        // Reward corruption must not roll back authentication or owner merge.
      }
    }
    await (_database.delete(
      _database.ownedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).go();
    await (_database.delete(
      _database.equippedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).go();
  }

  Future<int> _mergeCategories(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.name AS guest_name, target.name AS target_name
      FROM vocabulary_categories guest
      JOIN vocabulary_categories target
        ON target.owner_id = ?
       AND target.normalized_name = guest.normalized_name
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetCategoryId = collision.read<String>('target_id');
      final remappedWords = await (_database.select(
        _database.vocabularyWords,
      )..where((row) => row.categoryId.equals(guestId))).get();
      for (final word in remappedWords) {
        String? remappedChecksum;
        if (!word.isDeleted) {
          ContentQualityPolicy.effectiveVocabularyChecksumSha256(
            categoryId: word.categoryId,
            spelling: word.spelling,
            normalizedSpelling: word.normalizedSpelling,
            meaning: word.meaning,
            normalizedMeaning: word.normalizedMeaning,
            partOfSpeech: word.partOfSpeech,
            cefrLevel: word.cefrLevel,
            source: word.source,
            isGlobal: word.isGlobal,
            storedChecksumSha256: word.contentChecksumSha256,
          );
          remappedChecksum = ContentQualityPolicy.vocabularyChecksumSha256(
            categoryId: targetCategoryId,
            spelling: word.spelling,
            normalizedSpelling: word.normalizedSpelling,
            meaning: word.meaning,
            normalizedMeaning: word.normalizedMeaning,
            partOfSpeech: word.partOfSpeech,
            cefrLevel: word.cefrLevel,
            source: word.source,
            isGlobal: word.isGlobal,
          );
        }
        await (_database.update(
          _database.vocabularyWords,
        )..where((row) => row.id.equals(word.id))).write(
          remappedChecksum == null
              ? db.VocabularyWordsCompanion(categoryId: Value(targetCategoryId))
              : db.VocabularyWordsCompanion(
                  categoryId: Value(targetCategoryId),
                  contentChecksumSha256: Value(remappedChecksum),
                ),
        );
      }
      await _database.customUpdate(
        'UPDATE vocabulary_imports SET category_id = ? WHERE category_id = ?',
        variables: [
          Variable<String>(targetCategoryId),
          Variable<String>(guestId),
        ],
        updates: {_database.vocabularyImports},
      );
      await _retireDuplicateOutbox(sourceId, 'category', guestId);
      await _remapEntityReferences(
        sourceId,
        'category',
        guestId,
        targetCategoryId,
      );
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'category',
        entityId: targetCategoryId,
        localSnapshot: <String, Object?>{
          'id': guestId,
          'name': collision.read<String>('guest_name'),
        },
        targetSnapshot: <String, Object?>{
          'id': targetCategoryId,
          'name': collision.read<String>('target_name'),
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.canonicalTarget,
        outcome: _GuestUpgradeConflictOutcome.targetRetained,
        resolvedAt: resolvedAt,
      );
      await _database.customUpdate(
        'DELETE FROM vocabulary_categories WHERE id = ?',
        variables: [Variable<String>(guestId)],
        updates: {_database.vocabularyCategories},
      );
    }
    return collisions.length;
  }

  Future<int> _mergeWords(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.spelling AS guest_spelling,
             guest.meaning AS guest_meaning,
             guest.normalized_spelling AS guest_normalized_spelling,
             guest.normalized_meaning AS guest_normalized_meaning,
             target.spelling AS target_spelling,
             target.meaning AS target_meaning,
             target.normalized_spelling AS target_normalized_spelling,
             target.normalized_meaning AS target_normalized_meaning,
             guest.content_revision AS guest_content_revision,
             guest.content_checksum_sha256 AS guest_content_checksum,
             guest.content_provenance AS guest_content_provenance,
             guest.content_review_state AS guest_content_review_state,
             guest.content_publication_state AS guest_content_publication_state,
             target.content_revision AS target_content_revision,
             target.content_checksum_sha256 AS target_content_checksum,
             target.content_provenance AS target_content_provenance,
             target.content_review_state AS target_content_review_state,
             target.content_publication_state AS target_content_publication_state
      FROM vocabulary_words guest
      JOIN vocabulary_words target
        ON target.owner_id = ?
       AND target.category_id = guest.category_id
       AND target.normalized_spelling = guest.normalized_spelling
       AND target.normalized_meaning = guest.normalized_meaning
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetWordId = collision.read<String>('target_id');
      await _fenceMatchingSessionsForCollidingWord(
        sourceId: sourceId,
        guestWordId: guestId,
        resolvedAtUtcMs: resolvedAt,
      );
      final preserveHistoricalWord = await _mustPreserveHistoricalWordIdentity(
        sourceId: sourceId,
        guestWordId: guestId,
      );
      if (!preserveHistoricalWord) {
        await _database.customUpdate(
          'UPDATE answer_attempts SET word_id = ? '
          'WHERE owner_id = ? AND word_id = ?',
          variables: [
            Variable<String>(targetWordId),
            Variable<String>(sourceId),
            Variable<String>(guestId),
          ],
          updates: {_database.answerAttempts},
        );
      }
      await _database.customUpdate(
        'UPDATE vocabulary_import_rows SET word_id = ? WHERE word_id = ?',
        variables: [Variable<String>(targetWordId), Variable<String>(guestId)],
        updates: {_database.vocabularyImportRows},
      );
      await _database.customUpdate(
        'UPDATE srs_states SET word_id = ? WHERE owner_id = ? AND word_id = ?',
        variables: [
          Variable<String>(targetWordId),
          Variable<String>(sourceId),
          Variable<String>(guestId),
        ],
        updates: {_database.srsStates},
      );
      await _database.customUpdate(
        'UPDATE speech_evidence SET word_id = ? '
        'WHERE owner_id = ? AND word_id = ?',
        variables: [
          Variable<String>(targetWordId),
          Variable<String>(sourceId),
          Variable<String>(guestId),
        ],
        updates: {_database.speechEvidence},
      );
      await _database.customUpdate(
        'UPDATE association_records SET word_key = ? '
        'WHERE owner_id = ? AND word_key = ?',
        variables: [
          Variable<String>(targetWordId),
          Variable<String>(sourceId),
          Variable<String>(guestId),
        ],
        updates: {_database.associationRecords},
      );
      await _database.customUpdate(
        'UPDATE associative_memory_states SET word_key = ? '
        'WHERE owner_id = ? AND word_key = ?',
        variables: [
          Variable<String>(targetWordId),
          Variable<String>(sourceId),
          Variable<String>(guestId),
        ],
        updates: {_database.associativeMemoryStates},
      );
      await _remapEntityReferences(sourceId, 'srsState', guestId, targetWordId);
      await _retireDuplicateOutbox(sourceId, 'word', guestId);
      await _remapEntityReferences(sourceId, 'word', guestId, targetWordId);
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'word',
        entityId: targetWordId,
        localSnapshot: <String, Object?>{
          'id': guestId,
          'spelling': collision.read<String>('guest_spelling'),
          'meaning': collision.read<String>('guest_meaning'),
          'normalizedSpelling': collision.read<String>(
            'guest_normalized_spelling',
          ),
          'normalizedMeaning': collision.read<String>(
            'guest_normalized_meaning',
          ),
          'contentRevision': collision.read<int>('guest_content_revision'),
          'contentChecksumSha256': collision.readNullable<String>(
            'guest_content_checksum',
          ),
          'contentProvenance': collision.read<String>(
            'guest_content_provenance',
          ),
          'contentReviewState': collision.read<String>(
            'guest_content_review_state',
          ),
          'contentPublicationState': collision.read<String>(
            'guest_content_publication_state',
          ),
          if (preserveHistoricalWord) ...<String, Object?>{
            'projectionAliasVersion': 1,
            'projectionAliasSourceOwnerId': sourceId,
            'projectionAliasTargetWordId': targetWordId,
          },
        },
        targetSnapshot: <String, Object?>{
          'id': targetWordId,
          'spelling': collision.read<String>('target_spelling'),
          'meaning': collision.read<String>('target_meaning'),
          'normalizedSpelling': collision.read<String>(
            'target_normalized_spelling',
          ),
          'normalizedMeaning': collision.read<String>(
            'target_normalized_meaning',
          ),
          'contentRevision': collision.read<int>('target_content_revision'),
          'contentChecksumSha256': collision.readNullable<String>(
            'target_content_checksum',
          ),
          'contentProvenance': collision.read<String>(
            'target_content_provenance',
          ),
          'contentReviewState': collision.read<String>(
            'target_content_review_state',
          ),
          'contentPublicationState': collision.read<String>(
            'target_content_publication_state',
          ),
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.canonicalTarget,
        outcome: _GuestUpgradeConflictOutcome.targetRetained,
        resolvedAt: resolvedAt,
      );
      if (preserveHistoricalWord) {
        final tombstoneIdentity = sha256
            .convert(utf8.encode('$sourceId|$guestId|$targetWordId'))
            .toString();
        await _database.customUpdate(
          'UPDATE vocabulary_words SET normalized_spelling = ?, '
          'normalized_meaning = ?, is_deleted = 1, updated_at_utc_ms = ?, '
          'local_revision = local_revision + 1 '
          'WHERE id = ? AND owner_id = ?',
          variables: [
            Variable<String>('merged-collision-$tombstoneIdentity-spelling'),
            Variable<String>('merged-collision-$tombstoneIdentity-meaning'),
            Variable<int>(resolvedAt),
            Variable<String>(guestId),
            Variable<String>(sourceId),
          ],
          updates: {_database.vocabularyWords},
        );
      } else {
        await _database.customUpdate(
          'DELETE FROM vocabulary_words WHERE id = ?',
          variables: [Variable<String>(guestId)],
          updates: {_database.vocabularyWords},
        );
      }
    }
    return collisions.length;
  }

  Future<bool> _mustPreserveHistoricalWordIdentity({
    required String sourceId,
    required String guestWordId,
  }) async {
    final eventStore = DriftLearningEventStore(
      _database,
      evidencePolicy: evidencePolicy,
      rolloutModeProvider: rolloutModeProvider,
    );
    final attempts =
        await (_database.select(_database.answerAttempts)..where(
              (row) =>
                  row.ownerId.equals(sourceId) & row.wordId.equals(guestWordId),
            ))
            .get();
    var mustPreserve = false;
    for (final attempt in attempts) {
      final evidenceContext = EvidenceContext.fromJson(
        (jsonDecode(attempt.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      final sourceEvent = await eventStore.readValidatedSourceForAttempt(
        attempt: attempt,
      );
      if (sourceEvent == null) {
        if (LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
          evidenceContext,
        )) {
          continue;
        }
        throw StateError('colliding word attempt source identity is invalid');
      }
      if (sourceEvent.eventVersion == 1) continue;
      mustPreserve = true;
    }
    if (mustPreserve) return true;
    return DriftLearningProjectionRebuilder(
      _database,
      evidencePolicy: evidencePolicy,
      rolloutModeProvider: rolloutModeProvider,
    ).hasIncomingProjectionAlias(ownerId: sourceId, wordId: guestWordId);
  }

  Future<void> _fenceMatchingSessionsForCollidingWord({
    required String sourceId,
    required String guestWordId,
    required int resolvedAtUtcMs,
  }) async {
    const maximumActiveMatchingSessions = 16;
    const maximumMatchingCheckpointsPerSession = 64;
    final sessions =
        await (_database.select(_database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(sourceId) &
                    row.activityType.equals('matching') &
                    row.state.equals('active'),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.id)])
              ..limit(maximumActiveMatchingSessions + 1))
            .get();
    if (sessions.length > maximumActiveMatchingSessions) {
      throw StateError('active Matching owner-upgrade fence bound exceeded');
    }
    for (final session in sessions) {
      final checkpoints =
          await (_database.select(_database.eventsV2)
                ..where(
                  (row) =>
                      row.ownerId.equals(sourceId) &
                      row.eventType.equals('LearningActivityCheckpoint') &
                      row.aggregateType.equals('LearningSession') &
                      row.aggregateId.equals(session.id),
                )
                ..limit(maximumMatchingCheckpointsPerSession + 1))
              .get();
      if (checkpoints.isEmpty ||
          checkpoints.length > maximumMatchingCheckpointsPerSession) {
        throw StateError('Matching owner-upgrade checkpoint bound is invalid');
      }
      var latestRevision = 0;
      var latestContainsCollision = false;
      final revisions = <int>{};
      for (final checkpoint in checkpoints) {
        try {
          if (utf8.encode(checkpoint.payloadJson).length > 64 * 1024) {
            throw const FormatException('checkpoint payload is oversized');
          }
          final payload = jsonDecode(checkpoint.payloadJson);
          if (payload is! Map<String, dynamic>) {
            throw const FormatException('checkpoint envelope is invalid');
          }
          final revision = payload['revision'];
          final state = payload['state'];
          final pairs = state is Map<String, dynamic> ? state['pairs'] : null;
          if (revision is! int ||
              revision <= 0 ||
              !revisions.add(revision) ||
              pairs is! List<dynamic>) {
            throw const FormatException('checkpoint state is invalid');
          }
          var containsCollision = false;
          for (final pair in pairs) {
            if (pair is! Map<String, dynamic> || pair['id'] is! String) {
              throw const FormatException('checkpoint pair is invalid');
            }
            containsCollision = containsCollision || pair['id'] == guestWordId;
          }
          if (revision > latestRevision) {
            latestRevision = revision;
            latestContainsCollision = containsCollision;
          }
        } on Object catch (error) {
          throw StateError(
            'Matching owner-upgrade checkpoint cannot be fenced: $error',
          );
        }
      }
      if (!latestContainsCollision) continue;
      final fenced =
          await (_database.update(_database.learningSessions)..where(
                (row) =>
                    row.id.equals(session.id) &
                    row.ownerId.equals(sourceId) &
                    row.state.equals('active'),
              ))
              .write(
                db.LearningSessionsCompanion(
                  state: const Value('abandoned'),
                  endedAtUtcMs: Value(resolvedAtUtcMs),
                ),
              );
      if (fenced != 1) {
        throw StateError('Matching owner-upgrade fence lost its session');
      }
    }
  }

  Future<int> _mergeSavedLearningItems(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.saved_at_utc_ms AS guest_saved_at,
             guest.updated_at_utc_ms AS guest_updated_at,
             guest.local_revision AS guest_local_revision,
             guest.cloud_revision AS guest_cloud_revision,
             guest.is_deleted AS guest_is_deleted,
             target.saved_at_utc_ms AS target_saved_at,
             target.updated_at_utc_ms AS target_updated_at,
             target.local_revision AS target_local_revision,
             target.cloud_revision AS target_cloud_revision,
             target.is_deleted AS target_is_deleted
      FROM saved_learning_items AS guest
      JOIN saved_learning_items AS target
        ON target.owner_id = ?
       AND target.content_type = guest.content_type
       AND target.content_id = guest.content_id
       AND target.content_revision = guest.content_revision
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
          readsFrom: {_database.savedLearningItems},
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetItemId = collision.read<String>('target_id');
      final guestUpdated = collision.read<int>('guest_updated_at');
      final targetUpdated = collision.read<int>('target_updated_at');
      final guestRevision = collision.read<int>('guest_local_revision');
      final targetRevision = collision.read<int>('target_local_revision');
      final guestDeleted = collision.read<bool>('guest_is_deleted');
      final targetDeleted = collision.read<bool>('target_is_deleted');
      final guestWins =
          guestUpdated > targetUpdated ||
          (guestUpdated == targetUpdated && guestRevision > targetRevision) ||
          (guestUpdated == targetUpdated &&
              guestRevision == targetRevision &&
              guestDeleted &&
              !targetDeleted);

      if (guestWins) {
        final targetCloudRevision = collision.read<int>(
          'target_cloud_revision',
        );
        final mergedRevision =
            <int>[
              guestRevision,
              targetRevision,
              targetCloudRevision,
            ].reduce((left, right) => left > right ? left : right) +
            1;
        await (_database.update(
          _database.savedLearningItems,
        )..where((row) => row.id.equals(targetItemId))).write(
          db.SavedLearningItemsCompanion(
            updatedAtUtcMs: Value(guestUpdated),
            localRevision: Value(mergedRevision),
            isDeleted: Value(guestDeleted),
          ),
        );
        await (_database.update(_database.outboxOperations)..where(
              (row) =>
                  row.ownerId.equals(targetId) &
                  row.entityType.equals('savedLearningItem') &
                  row.entityId.equals(targetItemId) &
                  row.state.isNotIn(const <String>[
                    'acknowledged',
                    'superseded',
                    'conflictResolved',
                  ]),
            ))
            .write(
              const db.OutboxOperationsCompanion(
                state: Value('superseded'),
                nextAttemptAtUtcMs: Value(null),
                leaseToken: Value(null),
                leaseExpiresAtUtcMs: Value(null),
                failureCode: Value('guestUpgradeNewerIntent'),
              ),
            );
        await _database
            .into(_database.outboxOperations)
            .insert(
              db.OutboxOperationsCompanion.insert(
                operationId: 'savedLearningItem:$targetItemId:$mergedRevision',
                ownerId: targetId,
                entityType: 'savedLearningItem',
                entityId: targetItemId,
                operationKind: guestDeleted ? 'delete' : 'upsert',
                baseRevision: Value(targetCloudRevision),
                createdAtUtcMs: resolvedAt,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }

      await _retireDuplicateOutbox(sourceId, 'savedLearningItem', guestId);
      await _remapEntityReferences(
        sourceId,
        'savedLearningItem',
        guestId,
        targetItemId,
      );
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'savedLearningItem',
        entityId: targetItemId,
        localSnapshot: <String, Object?>{
          'id': guestId,
          'updatedAtUtcMs': guestUpdated,
          'localRevision': guestRevision,
          'isDeleted': guestDeleted,
        },
        targetSnapshot: <String, Object?>{
          'id': targetItemId,
          'updatedAtUtcMs': targetUpdated,
          'localRevision': targetRevision,
          'isDeleted': targetDeleted,
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.latestSavedIntent,
        outcome: guestWins
            ? _GuestUpgradeConflictOutcome.guestRetained
            : _GuestUpgradeConflictOutcome.targetRetained,
        resolvedAt: resolvedAt,
      );
      await (_database.delete(
        _database.savedLearningItems,
      )..where((row) => row.id.equals(guestId))).go();
    }
    return collisions.length;
  }

  Future<int> _mergeSrsStates(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.word_id AS word_id,
             guest.stability AS guest_stability,
             guest.difficulty AS guest_difficulty,
             guest.interval_days AS guest_interval_days,
             guest.repetitions AS guest_repetitions,
             guest.lapses AS guest_lapses,
             guest.last_review_at_utc_ms AS guest_last_review,
             guest.due_at_utc_ms AS guest_due,
             guest.algorithm_version AS guest_algorithm,
             target.last_review_at_utc_ms AS target_last_review,
             target.due_at_utc_ms AS target_due
      FROM srs_states AS guest
      JOIN srs_states AS target
        ON target.owner_id = ? AND target.word_id = guest.word_id
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetSrsId = collision.read<String>('target_id');
      final wordId = collision.read<String>('word_id');
      final evidenceCount = await _database
          .customSelect(
            'SELECT COUNT(*) AS count FROM answer_attempts '
            'WHERE owner_id IN (?, ?) AND word_id = ?',
            variables: [
              Variable<String>(sourceId),
              Variable<String>(targetId),
              Variable<String>(wordId),
            ],
          )
          .getSingle()
          .then((row) => row.read<int>('count'));
      final guestLast = collision.readNullable<int>('guest_last_review') ?? -1;
      final targetLast =
          collision.readNullable<int>('target_last_review') ?? -1;
      final guestDue = collision.read<int>('guest_due');
      final targetDue = collision.read<int>('target_due');
      final guestWins =
          evidenceCount == 0 &&
          (guestLast > targetLast ||
              (guestLast == targetLast && guestDue > targetDue));
      if (guestWins) {
        await (_database.update(
          _database.srsStates,
        )..where((row) => row.id.equals(targetSrsId))).write(
          db.SrsStatesCompanion(
            stability: Value(collision.read<double>('guest_stability')),
            difficulty: Value(collision.read<double>('guest_difficulty')),
            intervalDays: Value(collision.read<int>('guest_interval_days')),
            repetitions: Value(collision.read<int>('guest_repetitions')),
            lapses: Value(collision.read<int>('guest_lapses')),
            lastReviewAtUtcMs: Value(
              collision.readNullable<int>('guest_last_review'),
            ),
            dueAtUtcMs: Value(guestDue),
            algorithmVersion: Value(collision.read<int>('guest_algorithm')),
          ),
        );
      }
      await _retireDuplicateOutbox(sourceId, 'srsState', wordId);
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'srsState',
        entityId: wordId,
        localSnapshot: <String, Object?>{'id': guestId},
        targetSnapshot: <String, Object?>{'id': targetSrsId},
        resolutionPolicy: evidenceCount > 0
            ? _GuestUpgradeConflictPolicy.combinedAnswerEvidence
            : _GuestUpgradeConflictPolicy.latestSrs,
        outcome: evidenceCount > 0
            ? _GuestUpgradeConflictOutcome.evidenceMerged
            : guestWins
            ? _GuestUpgradeConflictOutcome.guestRetained
            : _GuestUpgradeConflictOutcome.targetRetained,
        resolvedAt: resolvedAt,
      );
      await _database.customUpdate(
        'DELETE FROM srs_states WHERE id = ?',
        variables: [Variable<String>(guestId)],
        updates: {_database.srsStates},
      );
    }
    return collisions.length;
  }

  Future<int> _mergeStreakState(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final guest = await (_database.select(
      _database.streakStates,
    )..where((row) => row.ownerId.equals(sourceId))).getSingleOrNull();
    final target = await (_database.select(
      _database.streakStates,
    )..where((row) => row.ownerId.equals(targetId))).getSingleOrNull();
    if (guest == null || target == null) return 0;
    final guestLast = guest.lastLearnedAtUtcMs ?? -1;
    final targetLast = target.lastLearnedAtUtcMs ?? -1;
    final guestIsNewer =
        guestLast > targetLast ||
        (guestLast == targetLast &&
            guest.updatedAtUtcMs > target.updatedAtUtcMs);
    final current = guestIsNewer
        ? guest.currentStreakDays
        : target.currentStreakDays;
    final longest = <int>[
      guest.longestStreakDays,
      target.longestStreakDays,
      current,
    ].reduce((left, right) => left > right ? left : right);
    final freezeCount = guest.freezeCount > target.freezeCount
        ? guest.freezeCount
        : target.freezeCount;
    final lastLearnedAt = guestLast > targetLast
        ? guest.lastLearnedAtUtcMs
        : target.lastLearnedAtUtcMs;
    final updatedAt = guest.updatedAtUtcMs > target.updatedAtUtcMs
        ? guest.updatedAtUtcMs
        : target.updatedAtUtcMs;
    await (_database.update(
      _database.streakStates,
    )..where((row) => row.ownerId.equals(targetId))).write(
      db.StreakStatesCompanion(
        currentStreakDays: Value(current),
        longestStreakDays: Value(longest),
        freezeCount: Value(freezeCount),
        lastLearnedAtUtcMs: Value(lastLearnedAt),
        updatedAtUtcMs: Value(updatedAt),
      ),
    );
    await (_database.delete(
      _database.streakStates,
    )..where((row) => row.ownerId.equals(sourceId))).go();
    await _recordMergeConflict(
      ownerId: targetId,
      entityType: 'streakState',
      entityId: targetId,
      localSnapshot: _streakSnapshot(guest),
      targetSnapshot: _streakSnapshot(target),
      resolutionPolicy: _GuestUpgradeConflictPolicy.streakReconciliation,
      outcome: _resolvedStreakOutcome(
        guest: guest,
        target: target,
        current: current,
        longest: longest,
        freezeCount: freezeCount,
        lastLearnedAtUtcMs: lastLearnedAt,
        updatedAtUtcMs: updatedAt,
      ),
      resolvedAt: resolvedAt,
    );
    return 1;
  }

  Future<int> _mergeLearningDays(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.learning_day AS learning_day,
             guest.first_session_at_utc_ms AS guest_first,
             target.first_session_at_utc_ms AS target_first
      FROM learning_day_log AS guest
      JOIN learning_day_log AS target
        ON target.owner_id = ? AND target.learning_day = guest.learning_day
      WHERE guest.owner_id = ?
      ORDER BY guest.learning_day
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final targetFirst = collision.read<int>('target_first');
      final guestFirst = collision.read<int>('guest_first');
      await _database.customUpdate(
        'UPDATE learning_day_log SET first_session_at_utc_ms = ? '
        'WHERE id = ?',
        variables: [
          Variable<int>(guestFirst < targetFirst ? guestFirst : targetFirst),
          Variable<String>(collision.read<String>('target_id')),
        ],
        updates: {_database.learningDayLog},
      );
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'learningDay',
        entityId: collision.read<String>('target_id'),
        localSnapshot: <String, Object?>{
          'id': collision.read<String>('guest_id'),
          'learningDay': collision.read<String>('learning_day'),
          'firstSessionAtUtcMs': guestFirst,
        },
        targetSnapshot: <String, Object?>{
          'id': collision.read<String>('target_id'),
          'learningDay': collision.read<String>('learning_day'),
          'firstSessionAtUtcMs': targetFirst,
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.earliestLearningDay,
        outcome: _GuestUpgradeConflictOutcome.evidenceMerged,
        resolvedAt: resolvedAt,
      );
      await _database.customUpdate(
        'DELETE FROM learning_day_log WHERE id = ?',
        variables: [Variable<String>(collision.read<String>('guest_id'))],
        updates: {_database.learningDayLog},
      );
    }
    final remaining = await _database
        .customSelect(
          'SELECT id, learning_day FROM learning_day_log '
          'WHERE owner_id = ? ORDER BY learning_day',
          variables: [Variable<String>(sourceId)],
        )
        .get();
    for (final row in remaining) {
      await _database.customUpdate(
        'UPDATE learning_day_log SET id = ? WHERE id = ?',
        variables: [
          Variable<String>('day:$targetId:${row.read<String>('learning_day')}'),
          Variable<String>(row.read<String>('id')),
        ],
        updates: {_database.learningDayLog},
      );
    }
    return collisions.length;
  }

  Future<int> _mergeAssociativeState(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    var conflictCount = 0;
    final associations = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.content AS guest_content,
             guest.created_at_utc_ms AS guest_created,
             target.content AS target_content,
             target.created_at_utc_ms AS target_created
      FROM association_records AS guest
      JOIN association_records AS target
        ON target.owner_id = ?
       AND target.word_key = guest.word_key
       AND target.type = guest.type
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in associations) {
      final guestCreated = collision.read<int>('guest_created');
      final targetCreated = collision.read<int>('target_created');
      final guestWins = guestCreated > targetCreated;
      if (guestWins) {
        await _database.customUpdate(
          'UPDATE association_records SET content = ?, '
          'created_at_utc_ms = ? WHERE id = ?',
          variables: [
            Variable<String>(collision.read<String>('guest_content')),
            Variable<int>(guestCreated),
            Variable<String>(collision.read<String>('target_id')),
          ],
          updates: {_database.associationRecords},
        );
      }
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'associationRecord',
        entityId: collision.read<String>('target_id'),
        localSnapshot: <String, Object?>{
          'id': collision.read<String>('guest_id'),
          'content': collision.read<String>('guest_content'),
          'createdAtUtcMs': guestCreated,
        },
        targetSnapshot: <String, Object?>{
          'id': collision.read<String>('target_id'),
          'content': collision.read<String>('target_content'),
          'createdAtUtcMs': targetCreated,
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.latestAssociation,
        outcome: guestWins
            ? _GuestUpgradeConflictOutcome.guestRetained
            : _GuestUpgradeConflictOutcome.targetRetained,
        resolvedAt: resolvedAt,
      );
      await _database.customUpdate(
        'DELETE FROM association_records WHERE id = ?',
        variables: [Variable<String>(collision.read<String>('guest_id'))],
        updates: {_database.associationRecords},
      );
      conflictCount += 1;
    }

    final memories = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.stability AS guest_stability,
             guest.difficulty AS guest_difficulty,
             guest.cue_dependency AS guest_cue_dependency,
             guest.lapse_count AS guest_lapse_count,
             guest.last_reviewed_at_utc_ms AS guest_last_reviewed,
             guest.next_due_at_utc_ms AS guest_next_due,
             guest.algorithm_version AS guest_algorithm,
             target.last_reviewed_at_utc_ms AS target_last_reviewed,
             target.next_due_at_utc_ms AS target_next_due
      FROM associative_memory_states AS guest
      JOIN associative_memory_states AS target
        ON target.owner_id = ? AND target.word_key = guest.word_key
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in memories) {
      final guestLast =
          collision.readNullable<int>('guest_last_reviewed') ?? -1;
      final targetLast =
          collision.readNullable<int>('target_last_reviewed') ?? -1;
      final guestDue = collision.read<int>('guest_next_due');
      final targetDue = collision.read<int>('target_next_due');
      final guestWins =
          guestLast > targetLast ||
          (guestLast == targetLast && guestDue > targetDue);
      if (guestWins) {
        await (_database.update(_database.associativeMemoryStates)..where(
              (row) => row.id.equals(collision.read<String>('target_id')),
            ))
            .write(
              db.AssociativeMemoryStatesCompanion(
                stability: Value(collision.read<double>('guest_stability')),
                difficulty: Value(collision.read<double>('guest_difficulty')),
                cueDependency: Value(
                  collision.read<double>('guest_cue_dependency'),
                ),
                lapseCount: Value(collision.read<int>('guest_lapse_count')),
                lastReviewedAtUtcMs: Value(
                  collision.readNullable<int>('guest_last_reviewed'),
                ),
                nextDueAtUtcMs: Value(guestDue),
                algorithmVersion: Value(
                  collision.read<String>('guest_algorithm'),
                ),
              ),
            );
      }
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'associativeMemoryState',
        entityId: collision.read<String>('target_id'),
        localSnapshot: <String, Object?>{
          'id': collision.read<String>('guest_id'),
          'stability': collision.read<double>('guest_stability'),
          'difficulty': collision.read<double>('guest_difficulty'),
          'cueDependency': collision.read<double>('guest_cue_dependency'),
          'lapseCount': collision.read<int>('guest_lapse_count'),
          'lastReviewedAtUtcMs': collision.readNullable<int>(
            'guest_last_reviewed',
          ),
          'nextDueAtUtcMs': guestDue,
          'algorithmVersion': collision.read<String>('guest_algorithm'),
        },
        targetSnapshot: <String, Object?>{
          'id': collision.read<String>('target_id'),
          'lastReviewedAtUtcMs': collision.readNullable<int>(
            'target_last_reviewed',
          ),
          'nextDueAtUtcMs': targetDue,
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.latestMemory,
        outcome: guestWins
            ? _GuestUpgradeConflictOutcome.guestRetained
            : _GuestUpgradeConflictOutcome.targetRetained,
        resolvedAt: resolvedAt,
      );
      await _database.customUpdate(
        'DELETE FROM associative_memory_states WHERE id = ?',
        variables: [Variable<String>(collision.read<String>('guest_id'))],
        updates: {_database.associativeMemoryStates},
      );
      conflictCount += 1;
    }
    return conflictCount;
  }

  Future<int> _mergeQuestState(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    var conflictCount = 0;
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.instance_id AS guest_id, target.instance_id AS target_id,
             guest.catalog_version AS guest_catalog,
             target.catalog_version AS target_catalog,
             guest.assigned_at_utc_ms AS guest_assigned,
             target.assigned_at_utc_ms AS target_assigned,
             guest.state AS guest_state, target.state AS target_state,
             guest.completed_at_utc_ms AS guest_completed,
             target.completed_at_utc_ms AS target_completed,
             guest.expired_at_utc_ms AS guest_expired,
             target.expired_at_utc_ms AS target_expired
      FROM quest_instances AS guest
      JOIN quest_instances AS target
        ON target.owner_id = ? AND target.quest_id = guest.quest_id
      WHERE guest.owner_id = ?
      ORDER BY guest.instance_id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetInstanceId = collision.read<String>('target_id');
      final guestState = collision.read<String>('guest_state');
      final targetState = collision.read<String>('target_state');
      final guestTimestamp =
          collision.readNullable<int>('guest_completed') ??
          collision.readNullable<int>('guest_expired') ??
          collision.read<int>('guest_assigned');
      final targetTimestamp =
          collision.readNullable<int>('target_completed') ??
          collision.readNullable<int>('target_expired') ??
          collision.read<int>('target_assigned');
      final guestWins =
          _compareQuestState(
            state: guestState,
            catalogVersion: collision.read<int>('guest_catalog'),
            timestamp: guestTimestamp,
            stableId: guestId,
            otherState: targetState,
            otherCatalogVersion: collision.read<int>('target_catalog'),
            otherTimestamp: targetTimestamp,
            otherStableId: targetInstanceId,
          ) >
          0;
      if (guestWins) {
        await (_database.update(
          _database.questInstances,
        )..where((row) => row.instanceId.equals(targetInstanceId))).write(
          db.QuestInstancesCompanion(
            catalogVersion: Value(collision.read<int>('guest_catalog')),
            assignedAtUtcMs: Value(collision.read<int>('guest_assigned')),
            state: Value(guestState),
            completedAtUtcMs: Value(
              collision.readNullable<int>('guest_completed'),
            ),
            expiredAtUtcMs: Value(collision.readNullable<int>('guest_expired')),
          ),
        );
      }
      final guestObjectives = await (_database.select(
        _database.questObjectiveProgress,
      )..where((row) => row.instanceId.equals(guestId))).get();
      final targetObjectives = await (_database.select(
        _database.questObjectiveProgress,
      )..where((row) => row.instanceId.equals(targetInstanceId))).get();
      for (final guestObjective in guestObjectives) {
        final targetObjective = targetObjectives
            .where(
              (candidate) =>
                  candidate.objectiveId == guestObjective.objectiveId,
            )
            .firstOrNull;
        if (targetObjective == null) {
          await (_database.update(
            _database.questObjectiveProgress,
          )..where((row) => row.id.equals(guestObjective.id))).write(
            db.QuestObjectiveProgressCompanion(
              id: Value('$targetInstanceId:${guestObjective.objectiveId}'),
              instanceId: Value(targetInstanceId),
            ),
          );
          continue;
        }
        if (guestObjective.targetCount == targetObjective.targetCount) {
          final sourceIds = <String>{
            ..._decodeStringList(targetObjective.sourceEventIdsJson),
            ..._decodeStringList(guestObjective.sourceEventIdsJson),
          }.toList()..sort();
          final maximum =
              guestObjective.currentCount > targetObjective.currentCount
              ? guestObjective.currentCount
              : targetObjective.currentCount;
          await (_database.update(
            _database.questObjectiveProgress,
          )..where((row) => row.id.equals(targetObjective.id))).write(
            db.QuestObjectiveProgressCompanion(
              currentCount: Value(
                maximum > targetObjective.targetCount
                    ? targetObjective.targetCount
                    : maximum,
              ),
              sourceEventIdsJson: Value(jsonEncode(sourceIds)),
            ),
          );
        } else {
          if (guestWins) {
            await (_database.update(
              _database.questObjectiveProgress,
            )..where((row) => row.id.equals(targetObjective.id))).write(
              db.QuestObjectiveProgressCompanion(
                currentCount: Value(
                  guestObjective.currentCount > guestObjective.targetCount
                      ? guestObjective.targetCount
                      : guestObjective.currentCount,
                ),
                targetCount: Value(guestObjective.targetCount),
                sourceEventIdsJson: Value(guestObjective.sourceEventIdsJson),
              ),
            );
          }
          await _recordMergeConflict(
            ownerId: targetId,
            entityType: 'questObjective',
            entityId: targetObjective.id,
            localSnapshot: <String, Object?>{
              'id': guestObjective.id,
              'currentCount': guestObjective.currentCount,
              'targetCount': guestObjective.targetCount,
              'sourceEventIds': _decodeStringList(
                guestObjective.sourceEventIdsJson,
              ),
            },
            targetSnapshot: <String, Object?>{
              'id': targetObjective.id,
              'currentCount': targetObjective.currentCount,
              'targetCount': targetObjective.targetCount,
              'sourceEventIds': _decodeStringList(
                targetObjective.sourceEventIdsJson,
              ),
            },
            resolutionPolicy: _GuestUpgradeConflictPolicy.rankedQuestObjective,
            outcome: guestWins
                ? _GuestUpgradeConflictOutcome.guestRetained
                : _GuestUpgradeConflictOutcome.targetRetained,
            resolvedAt: resolvedAt,
          );
          conflictCount += 1;
        }
        await (_database.delete(
          _database.questObjectiveProgress,
        )..where((row) => row.id.equals(guestObjective.id))).go();
      }
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'questInstance',
        entityId: targetInstanceId,
        localSnapshot: <String, Object?>{'id': guestId, 'state': guestState},
        targetSnapshot: <String, Object?>{
          'id': targetInstanceId,
          'state': targetState,
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.rankedQuest,
        outcome: guestWins
            ? _GuestUpgradeConflictOutcome.guestRetained
            : _GuestUpgradeConflictOutcome.targetRetained,
        resolvedAt: resolvedAt,
      );
      await (_database.delete(
        _database.questInstances,
      )..where((row) => row.instanceId.equals(guestId))).go();
      conflictCount += 1;
    }
    return conflictCount;
  }

  Future<int> _makeEventKeysUnique(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.event_id AS guest_id, target.event_id AS target_id,
             guest.idempotency_key AS idempotency_key
      FROM events_v2 AS guest
      JOIN events_v2 AS target
        ON target.owner_id = ?
       AND target.idempotency_key = guest.idempotency_key
      WHERE guest.owner_id = ?
      ORDER BY guest.event_id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      var suffix = 0;
      var mergedKey = 'merged:$guestId';
      while (await _eventKeyExistsForOtherRow(
        sourceId: sourceId,
        targetId: targetId,
        eventId: guestId,
        idempotencyKey: mergedKey,
      )) {
        suffix += 1;
        mergedKey = 'merged:$guestId:$suffix';
      }
      await _database.customUpdate(
        'UPDATE events_v2 SET idempotency_key = ? WHERE event_id = ?',
        variables: [Variable<String>(mergedKey), Variable<String>(guestId)],
        updates: {_database.eventsV2},
      );
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'eventV2',
        entityId: collision.read<String>('target_id'),
        localSnapshot: <String, Object?>{
          'id': guestId,
          'idempotencyKey': collision.read<String>('idempotency_key'),
        },
        targetSnapshot: <String, Object?>{
          'id': collision.read<String>('target_id'),
          'idempotencyKey': collision.read<String>('idempotency_key'),
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.preserveBoth,
        outcome: _GuestUpgradeConflictOutcome.bothRetained,
        resolvedAt: resolvedAt,
      );
    }
    return collisions.length;
  }

  Future<bool> _eventKeyExistsForOtherRow({
    required String sourceId,
    required String targetId,
    required String eventId,
    required String idempotencyKey,
  }) async {
    final existing = await _database
        .customSelect(
          'SELECT 1 AS present FROM events_v2 '
          'WHERE owner_id IN (?, ?) AND idempotency_key = ? '
          'AND event_id <> ? LIMIT 1',
          variables: [
            Variable<String>(sourceId),
            Variable<String>(targetId),
            Variable<String>(idempotencyKey),
            Variable<String>(eventId),
          ],
          readsFrom: {_database.eventsV2},
        )
        .getSingleOrNull();
    return existing != null;
  }

  Future<void> _makeImportKeysUnique(String sourceId, String targetId) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, guest.category_id AS category_id,
             guest.source_hash AS source_hash
      FROM vocabulary_imports guest
      JOIN vocabulary_imports target
        ON target.owner_id = ?
       AND target.category_id = guest.category_id
       AND target.source_hash = guest.source_hash
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final id = collision.read<String>('guest_id');
      final categoryId = collision.read<String>('category_id');
      final hash = collision.read<String>('source_hash');
      final occupied = await _database
          .customSelect(
            'SELECT source_hash FROM vocabulary_imports '
            'WHERE owner_id IN (?, ?) AND category_id = ? AND id <> ?',
            variables: [
              Variable<String>(sourceId),
              Variable<String>(targetId),
              Variable<String>(categoryId),
              Variable<String>(id),
            ],
            readsFrom: {_database.vocabularyImports},
          )
          .get()
          .then(
            (rows) =>
                rows.map((row) => row.read<String>('source_hash')).toSet(),
          );
      var suffix = 0;
      var mergedHash = '$hash:merged:$id';
      while (occupied.contains(mergedHash)) {
        suffix += 1;
        mergedHash = '$hash:merged:$id:$suffix';
      }
      await _database.customUpdate(
        'UPDATE vocabulary_imports SET source_hash = ? WHERE id = ?',
        variables: [Variable<String>(mergedHash), Variable<String>(id)],
        updates: {_database.vocabularyImports},
      );
    }
  }

  Future<int> _makeRewardKeysUnique(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id, target.id AS target_id,
             guest.idempotency_key AS idempotency_key
      FROM reward_transactions guest
      JOIN reward_transactions target
        ON target.owner_id = ?
       AND target.idempotency_key = guest.idempotency_key
      WHERE guest.owner_id = ?
      ORDER BY guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
        )
        .get();
    for (final collision in collisions) {
      final guestId = collision.read<String>('guest_id');
      final targetTransactionId = collision.read<String>('target_id');
      final key = collision.read<String>('idempotency_key');
      final suffix = guestId.length > 220
          ? guestId.substring(guestId.length - 220)
          : guestId;
      final occupied = await _database
          .customSelect(
            'SELECT idempotency_key FROM reward_transactions '
            'WHERE owner_id IN (?, ?) AND id <> ?',
            variables: [
              Variable<String>(sourceId),
              Variable<String>(targetId),
              Variable<String>(guestId),
            ],
            readsFrom: {_database.rewardTransactions},
          )
          .get()
          .then(
            (rows) =>
                rows.map((row) => row.read<String>('idempotency_key')).toSet(),
          );
      var collisionSuffix = 0;
      var mergedKey = 'merged:$suffix';
      while (occupied.contains(mergedKey)) {
        collisionSuffix += 1;
        mergedKey = 'merged:$suffix:$collisionSuffix';
      }
      final transaction = await (_database.select(
        _database.rewardTransactions,
      )..where((row) => row.id.equals(guestId))).getSingle();
      var reboundSourceEventId = transaction.sourceEventId;
      if (transaction.catalogVersion == RewardCatalog.catalogV1Version &&
          (transaction.transactionType == 'purchase' ||
              transaction.transactionType == 'equip') &&
          transaction.sourceEventId != null) {
        const carry = AvatarLegacyCarryForwardContract();
        if (!carry.isValidPersistedTransaction(
          transactionId: transaction.id,
          idempotencyKey: transaction.idempotencyKey,
          transactionType: transaction.transactionType,
          amount: transaction.amount,
          itemId: transaction.itemId,
          catalogVersion: transaction.catalogVersion,
          sourceEventId: transaction.sourceEventId,
          occurredAtUtcMs: transaction.occurredAtUtcMs,
        )) {
          throw StateError('legacy avatar merge evidence is invalid');
        }
        reboundSourceEventId = carry
            .issue(
              transactionId: transaction.id,
              idempotencyKey: mergedKey,
              transactionType: transaction.transactionType,
              amount: transaction.amount,
              itemId: transaction.itemId!,
              catalogVersion: transaction.catalogVersion,
              occurredAtUtcMs: transaction.occurredAtUtcMs,
            )
            .sourceEventId;
      } else if (transaction.transactionType == 'purchase' &&
          transaction.catalogVersion == RewardCatalog.catalogV2Version) {
        final item = transaction.itemId == null
            ? null
            : RewardCatalog.byIdAtVersion(
                transaction.itemId!,
                transaction.catalogVersion,
              );
        final receipt = item == null
            ? null
            : const AvatarProgressionEligibilityContract()
                  .validatePersistedPurchase(
                    idempotencyKey: transaction.idempotencyKey,
                    itemId: item.id,
                    amount: transaction.amount,
                    catalogVersion: transaction.catalogVersion,
                    sourceEventId: transaction.sourceEventId,
                    occurredAtUtcMs: transaction.occurredAtUtcMs,
                  );
        if (item == null || receipt == null) {
          throw StateError('avatar purchase merge evidence is invalid');
        }
        reboundSourceEventId = const AvatarProgressionEligibilityContract()
            .issue(
              idempotencyKey: mergedKey,
              item: item,
              lifetimeXp: receipt.lifetimeXp,
              occurredAtUtcMs: transaction.occurredAtUtcMs,
            )
            .sourceEventId;
      }
      await (_database.update(
        _database.rewardTransactions,
      )..where((row) => row.id.equals(guestId))).write(
        db.RewardTransactionsCompanion(
          idempotencyKey: Value(mergedKey),
          sourceEventId: Value(reboundSourceEventId),
        ),
      );
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'rewardTransaction',
        entityId: targetTransactionId,
        localSnapshot: <String, Object?>{'id': guestId, 'idempotencyKey': key},
        targetSnapshot: <String, Object?>{
          'id': targetTransactionId,
          'idempotencyKey': key,
        },
        resolutionPolicy: _GuestUpgradeConflictPolicy.preserveBoth,
        outcome: _GuestUpgradeConflictOutcome.bothRetained,
        resolvedAt: resolvedAt,
      );
    }
    return collisions.length;
  }

  Future<int> _mergeResearchConsents(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    final collisions = await _database
        .customSelect(
          '''
      SELECT guest.id AS guest_id,
             guest.consent_version AS guest_version,
             guest.consent_state AS guest_state,
             guest.decided_at_utc_ms AS guest_decided,
             guest.withdrawn_at_utc_ms AS guest_withdrawn,
             target.id AS target_id,
             target.consent_version AS target_version,
             target.consent_state AS target_state,
             target.decided_at_utc_ms AS target_decided,
             target.withdrawn_at_utc_ms AS target_withdrawn
      FROM research_consents AS guest
      JOIN research_consents AS target
        ON target.owner_id = ?
       AND target.consent_version = guest.consent_version
      WHERE guest.owner_id = ?
      ORDER BY guest.consent_version, guest.id
      ''',
          variables: [Variable<String>(targetId), Variable<String>(sourceId)],
          readsFrom: {_database.researchConsents},
        )
        .get();
    for (final collision in collisions) {
      final guest = _ResearchConsentDecision(
        id: collision.read<String>('guest_id'),
        version: collision.read<int>('guest_version'),
        state: collision.read<String>('guest_state'),
        decidedAtUtcMs: collision.read<int>('guest_decided'),
        withdrawnAtUtcMs: collision.readNullable<int>('guest_withdrawn'),
      );
      final target = _ResearchConsentDecision(
        id: collision.read<String>('target_id'),
        version: collision.read<int>('target_version'),
        state: collision.read<String>('target_state'),
        decidedAtUtcMs: collision.read<int>('target_decided'),
        withdrawnAtUtcMs: collision.readNullable<int>('target_withdrawn'),
      );
      final guestWins = _guestConsentDecisionWins(guest, target);
      final winner = guestWins ? guest : target;
      final decidedAt = winner.effectiveDecisionAtUtcMs;
      await (_database.update(
        _database.researchConsents,
      )..where((row) => row.id.equals(target.id))).write(
        db.ResearchConsentsCompanion(
          consentState: Value(winner.isWithdrawn ? 'withdrawn' : 'accepted'),
          decidedAtUtcMs: Value(decidedAt),
          withdrawnAtUtcMs: Value(winner.isWithdrawn ? decidedAt : null),
        ),
      );
      await _recordMergeConflict(
        ownerId: targetId,
        entityType: 'researchConsent',
        entityId: target.id,
        localSnapshot: guest.snapshot,
        targetSnapshot: target.snapshot,
        resolutionPolicy: _GuestUpgradeConflictPolicy.latestConsentDecision,
        outcome: guestWins
            ? _GuestUpgradeConflictOutcome.guestRetained
            : _GuestUpgradeConflictOutcome.targetRetained,
        resolvedAt: resolvedAt,
      );
      await (_database.delete(
        _database.researchConsents,
      )..where((row) => row.id.equals(guest.id))).go();
    }
    return collisions.length;
  }

  Future<int> _discardNaturalKeyDuplicates(
    String sourceId,
    String targetId,
    int resolvedAt,
  ) async {
    var conflicts = 0;
    for (final specification in const <_DuplicateSpecification>[
      _DuplicateSpecification(
        table: 'reading_progress_entries',
        entityType: 'readingProgress',
        join:
            'target.document_id = guest.document_id AND '
            'target.document_revision = guest.document_revision',
      ),
      _DuplicateSpecification(
        table: 'points_ledger_entries',
        entityType: 'pointsLedger',
        join: 'target.idempotency_key = guest.idempotency_key',
      ),
      _DuplicateSpecification(
        table: 'achievement_unlocks',
        entityType: 'achievement',
        join:
            'target.achievement_id = guest.achievement_id AND '
            'target.definition_version = guest.definition_version',
        outboxEntityType: 'achievementUnlock',
      ),
      _DuplicateSpecification(
        table: 'equipped_reward_items',
        entityType: 'equippedReward',
        join: 'target.slot = guest.slot',
      ),
      _DuplicateSpecification(
        table: 'owned_reward_items',
        entityType: 'ownedReward',
        join: 'target.item_id = guest.item_id',
      ),
      _DuplicateSpecification(
        table: 'sync_checkpoints',
        entityType: 'syncCheckpoint',
        join: 'target.collection_name = guest.collection_name',
      ),
    ]) {
      final duplicates = await _database
          .customSelect(
            '''
        SELECT guest.id AS guest_id, target.id AS target_id
               ${specification.outboxEntityType == null ? '' : ', guest.id AS guest_outbox_entity_id'}
        FROM ${specification.table} guest
        JOIN ${specification.table} target
          ON target.owner_id = ? AND ${specification.join}
        WHERE guest.owner_id = ?
        ORDER BY guest.id
        ''',
            variables: [Variable<String>(targetId), Variable<String>(sourceId)],
          )
          .get();
      for (final duplicate in duplicates) {
        final guestId = duplicate.read<String>('guest_id');
        final targetEntityId = duplicate.read<String>('target_id');
        final outboxEntityType = specification.outboxEntityType;
        if (outboxEntityType != null) {
          await _retireDuplicateOutbox(
            sourceId,
            outboxEntityType,
            duplicate.read<String>('guest_outbox_entity_id'),
          );
        }
        await _recordMergeConflict(
          ownerId: targetId,
          entityType: specification.entityType,
          entityId: targetEntityId,
          localSnapshot: <String, Object?>{'id': guestId},
          targetSnapshot: <String, Object?>{'id': targetEntityId},
          resolutionPolicy: _GuestUpgradeConflictPolicy.canonicalTarget,
          outcome: _GuestUpgradeConflictOutcome.targetRetained,
          resolvedAt: resolvedAt,
        );
        await _database.customUpdate(
          'DELETE FROM ${specification.table} WHERE id = ?',
          variables: [Variable<String>(guestId)],
        );
        conflicts += 1;
      }
    }
    return conflicts;
  }

  Future<void> _mergeAssessmentRuns(
    String sourceOwnerId,
    String targetOwnerId,
  ) async {
    final sourceRows = await _database
        .customSelect(
          'SELECT * FROM assessment_runs WHERE owner_id = ? '
          'ORDER BY study_cycle_id, phase, id',
          variables: [Variable<String>(sourceOwnerId)],
          readsFrom: {_database.assessmentRuns},
        )
        .get();

    for (final sourceRow in sourceRows) {
      final sourceRun = _readAssessmentRunOrConflict(sourceRow);
      await _requireAssessmentSessionOwner(sourceRun);
      final sourceAssignment = await _database
          .customSelect(
            'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
            'protocol_version, assigned_at_utc_ms FROM experiment_assignments '
            'WHERE id = ? AND owner_id = ? LIMIT 1',
            variables: [
              Variable<String>(sourceRun.assignmentId),
              Variable<String>(sourceOwnerId),
            ],
            readsFrom: {_database.experimentAssignments},
          )
          .getSingleOrNull();
      if (sourceAssignment == null) {
        throw _assessmentConflict(sourceRun.id, 'source assignment is missing');
      }
      final sourceAssignmentValue = _readExperimentAssignment(sourceAssignment);
      _validateAssessmentAssignment(sourceRun.id, sourceAssignmentValue);
      if (!_runMatchesAssignment(sourceRun, sourceAssignmentValue)) {
        throw _assessmentConflict(
          sourceRun.id,
          'source assignment identity does not match the run',
        );
      }

      final targetAssignmentId =
          DriftExperimentAssignmentRepository.canonicalAssignmentId(
            ownerId: targetOwnerId,
            experimentId: sourceRun.experimentId,
            experimentVersion: sourceRun.experimentVersion,
          );
      final targetAssignmentRow = await _database
          .customSelect(
            'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
            'protocol_version, assigned_at_utc_ms FROM experiment_assignments '
            'WHERE owner_id = ? AND experiment_id = ? '
            'AND experiment_version = ? LIMIT 1',
            variables: [
              Variable<String>(targetOwnerId),
              Variable<String>(sourceRun.experimentId),
              Variable<int>(sourceRun.experimentVersion),
            ],
            readsFrom: {_database.experimentAssignments},
          )
          .getSingleOrNull();

      late final ExperimentAssignment targetAssignment;
      if (targetAssignmentRow == null) {
        final idCollision = await (_database.select(
          _database.experimentAssignments,
        )..where((row) => row.id.equals(targetAssignmentId))).getSingleOrNull();
        if (idCollision != null) {
          throw _assessmentConflict(
            sourceRun.id,
            'target assignment identity collides',
          );
        }
        await _database
            .into(_database.experimentAssignments)
            .insert(
              db.ExperimentAssignmentsCompanion.insert(
                id: targetAssignmentId,
                ownerId: targetOwnerId,
                experimentId: sourceAssignmentValue.experimentId,
                experimentVersion: sourceAssignmentValue.experimentVersion,
                cohort: sourceAssignmentValue.cohort,
                protocolVersion: sourceAssignmentValue.protocolVersion,
                assignedAtUtcMs:
                    sourceAssignmentValue.assignedAtUtc.millisecondsSinceEpoch,
              ),
            );
        targetAssignment = ExperimentAssignment(
          id: targetAssignmentId,
          ownerId: targetOwnerId,
          experimentId: sourceAssignmentValue.experimentId,
          experimentVersion: sourceAssignmentValue.experimentVersion,
          cohort: sourceAssignmentValue.cohort,
          protocolVersion: sourceAssignmentValue.protocolVersion,
          assignedAtUtc: sourceAssignmentValue.assignedAtUtc,
        );
      } else {
        targetAssignment = _readExperimentAssignment(targetAssignmentRow);
        _validateAssessmentAssignment(sourceRun.id, targetAssignment);
        if (!_assignmentsEquivalent(sourceAssignmentValue, targetAssignment)) {
          throw _assessmentConflict(
            sourceRun.id,
            'target assignment payload differs',
          );
        }
      }

      final targetRunRow = await _database
          .customSelect(
            'SELECT * FROM assessment_runs WHERE owner_id = ? '
            'AND study_cycle_id = ? AND phase = ? LIMIT 1',
            variables: [
              Variable<String>(targetOwnerId),
              Variable<String>(sourceRun.studyCycleId),
              Variable<String>(sourceRun.phase.name),
            ],
            readsFrom: {_database.assessmentRuns},
          )
          .getSingleOrNull();

      if (targetRunRow == null) {
        await _rehomeAssessmentEvidence(
          run: sourceRun,
          sourceAssignmentId: sourceAssignmentValue.id,
          targetAssignmentId: targetAssignment.id,
        );
        await (_database.update(
          _database.assessmentRuns,
        )..where((row) => row.id.equals(sourceRun.id))).write(
          db.AssessmentRunsCompanion(
            ownerId: Value(targetOwnerId),
            assignmentId: Value(targetAssignment.id),
          ),
        );
        continue;
      }

      final targetRun = _readAssessmentRunOrConflict(targetRunRow);
      await _requireAssessmentSessionOwner(targetRun);
      if (!_runMatchesAssignment(targetRun, targetAssignment) ||
          !_assessmentRunPayloadEquivalent(sourceRun, targetRun) ||
          !await _assessmentEvidenceEquivalent(
            sourceRun: sourceRun,
            targetRun: targetRun,
            targetAssignmentId: targetAssignment.id,
          )) {
        throw _assessmentConflict(
          sourceRun.id,
          'target assessment run or evidence differs',
        );
      }
      await _retireEquivalentAssessmentRunOutbox(sourceRun);
      await (_database.delete(
        _database.assessmentRuns,
      )..where((row) => row.id.equals(sourceRun.id))).go();
    }
  }

  bool _assignmentsEquivalent(
    ExperimentAssignment source,
    ExperimentAssignment target,
  ) {
    return source.experimentId == target.experimentId &&
        source.experimentVersion == target.experimentVersion &&
        source.cohort == target.cohort &&
        source.protocolVersion == target.protocolVersion &&
        source.assignedAtUtc == target.assignedAtUtc;
  }

  Future<void> _retireEquivalentAssessmentRunOutbox(
    AssessmentRun sourceRun,
  ) async {
    final operations =
        await (_database.select(_database.outboxOperations)..where(
              (row) =>
                  row.ownerId.equals(sourceRun.ownerId) &
                  row.entityType.equals('assessmentRun') &
                  row.entityId.equals(sourceRun.id),
            ))
            .get();
    for (final operation in operations) {
      final revision = operation.baseRevision + 1;
      final expectedCreatedAtUtcMs = switch (revision) {
        1 => sourceRun.startedAtUtc.millisecondsSinceEpoch,
        2 when sourceRun.state == AssessmentRunState.completed =>
          sourceRun.completedAtUtc!.millisecondsSinceEpoch,
        2 when sourceRun.state == AssessmentRunState.abandoned =>
          sourceRun.abandonedAtUtc!.millisecondsSinceEpoch,
        _ => null,
      };
      if (expectedCreatedAtUtcMs == null ||
          operation.operationId !=
              DriftAssessmentRepository.canonicalOutboxOperationId(
                runId: sourceRun.id,
                revision: revision,
              ) ||
          operation.operationKind != 'upsert' ||
          operation.payloadVersion != 1 ||
          operation.createdAtUtcMs != expectedCreatedAtUtcMs) {
        throw _assessmentConflict(
          sourceRun.id,
          'source assessment outbox revision is not canonical',
        );
      }
    }
    if (operations.isNotEmpty) {
      await (_database.delete(_database.outboxOperations)..where(
            (row) => row.operationId.isIn(
              operations.map((operation) => operation.operationId),
            ),
          ))
          .go();
    }
  }

  Future<void> _requireAssessmentSessionOwner(AssessmentRun run) async {
    final session = await _database
        .customSelect(
          'SELECT owner_id FROM learning_sessions WHERE id = ? LIMIT 1',
          variables: [Variable<String>(run.learningSessionId)],
          readsFrom: {_database.learningSessions},
        )
        .getSingleOrNull();
    if (session == null || session.read<String>('owner_id') != run.ownerId) {
      throw _assessmentConflict(
        run.id,
        'assessment learning-session identity is invalid',
      );
    }
  }

  void _validateAssessmentAssignment(
    String runId,
    ExperimentAssignment assignment,
  ) {
    try {
      _validateExperimentAssignmentIdentity(assignment);
    } on Object {
      throw _assessmentConflict(
        runId,
        'assessment assignment identity is malformed',
      );
    }
  }

  bool _runMatchesAssignment(
    AssessmentRun run,
    ExperimentAssignment assignment,
  ) {
    return run.ownerId == assignment.ownerId &&
        run.assignmentId == assignment.id &&
        run.experimentId == assignment.experimentId &&
        run.experimentVersion == assignment.experimentVersion &&
        run.cohort == assignment.cohort &&
        run.protocolVersion == assignment.protocolVersion;
  }

  bool _assessmentRunPayloadEquivalent(
    AssessmentRun source,
    AssessmentRun target,
  ) {
    return source.studyCycleId == target.studyCycleId &&
        source.phase == target.phase &&
        source.state == target.state &&
        source.protocolId == target.protocolId &&
        source.protocolVersion == target.protocolVersion &&
        source.experimentId == target.experimentId &&
        source.experimentVersion == target.experimentVersion &&
        source.cohort == target.cohort &&
        source.consentVersion == target.consentVersion &&
        source.consentDecidedAtUtc == target.consentDecidedAtUtc &&
        source.instrumentId == target.instrumentId &&
        source.instrumentVersion == target.instrumentVersion &&
        source.formId == target.formId &&
        source.formVersion == target.formVersion &&
        source.instrumentChecksumSha256 == target.instrumentChecksumSha256 &&
        source.formChecksumSha256 == target.formChecksumSha256 &&
        source.appVersion == target.appVersion &&
        source.buildId == target.buildId &&
        source.databaseSchemaVersion == target.databaseSchemaVersion &&
        source.contentRevision == target.contentRevision &&
        source.evidencePolicyVersion == target.evidencePolicyVersion &&
        source.featureContractRevision == target.featureContractRevision &&
        source.featureContractHash == target.featureContractHash &&
        source.startedAtUtc == target.startedAtUtc &&
        source.completedAtUtc == target.completedAtUtc &&
        source.abandonedAtUtc == target.abandonedAtUtc;
  }

  Future<bool> _assessmentEvidenceEquivalent({
    required AssessmentRun sourceRun,
    required AssessmentRun targetRun,
    required String targetAssignmentId,
  }) async {
    final source = await _assessmentEvidenceSet(
      sourceRun,
      normalizedAssignmentId: targetAssignmentId,
    );
    final target = await _assessmentEvidenceSet(
      targetRun,
      normalizedAssignmentId: targetAssignmentId,
    );
    if (source.length != target.length) return false;
    for (var index = 0; index < source.length; index += 1) {
      if (source[index] != target[index]) return false;
    }
    return true;
  }

  Future<List<String>> _assessmentEvidenceSet(
    AssessmentRun run, {
    required String normalizedAssignmentId,
  }) async {
    final rows = await _database
        .customSelect(
          'SELECT id, word_id, prompt_mode, is_correct, response_time_ms, '
          'attempt_number, occurred_at_utc_ms, evidence_context_json '
          'FROM answer_attempts WHERE owner_id = ? AND session_id = ? '
          "AND evidence_class = 'assessment' ORDER BY id",
          variables: [
            Variable<String>(run.ownerId),
            Variable<String>(run.learningSessionId),
          ],
          readsFrom: {_database.answerAttempts},
        )
        .get();
    final result = <String>[];
    for (final row in rows) {
      final context = _readAssessmentEvidenceContext(
        row.read<String>('evidence_context_json'),
        run,
      );
      final contextJson = Map<String, Object?>.from(context.toJson())
        ..['assignmentId'] = normalizedAssignmentId;
      result.add(
        jsonEncode(<String, Object?>{
          'id': row.read<String>('id'),
          'wordId': row.read<String>('word_id'),
          'promptMode': row.read<String>('prompt_mode'),
          'isCorrect': row.read<bool>('is_correct'),
          'responseTimeMs': row.readNullable<int>('response_time_ms'),
          'attemptNumber': row.read<int>('attempt_number'),
          'occurredAtUtcMs': row.read<int>('occurred_at_utc_ms'),
          'evidenceContext': contextJson,
        }),
      );
    }
    result.sort();
    return result;
  }

  Future<void> _rehomeAssessmentEvidence({
    required AssessmentRun run,
    required String sourceAssignmentId,
    required String targetAssignmentId,
  }) async {
    final attempts = await _database
        .customSelect(
          'SELECT id, evidence_context_json FROM answer_attempts '
          'WHERE owner_id = ? AND session_id = ? '
          "AND evidence_class = 'assessment' ORDER BY id",
          variables: [
            Variable<String>(run.ownerId),
            Variable<String>(run.learningSessionId),
          ],
          readsFrom: {_database.answerAttempts},
        )
        .get();
    for (final attempt in attempts) {
      final attemptId = attempt.read<String>('id');
      final context = _readAssessmentEvidenceContext(
        attempt.read<String>('evidence_context_json'),
        run,
      );
      if (context.assignmentId != sourceAssignmentId) {
        throw _assessmentConflict(
          run.id,
          'assessment evidence assignment differs',
        );
      }
      final contextJson = Map<String, Object?>.from(context.toJson())
        ..['assignmentId'] = targetAssignmentId;
      final normalized = EvidenceContext.fromJson(contextJson).toJson();
      final encodedContext = jsonEncode(normalized);

      final event = await _database
          .customSelect(
            'SELECT event_id, payload_json FROM events_v2 '
            'WHERE owner_id = ? AND idempotency_key = ? LIMIT 1',
            variables: [
              Variable<String>(run.ownerId),
              Variable<String>(
                LearningEvidenceContract.learningAttemptIdempotencyKey(
                  attemptId,
                ),
              ),
            ],
            readsFrom: {_database.eventsV2},
          )
          .getSingleOrNull();
      if (event == null) {
        throw _assessmentConflict(
          run.id,
          'assessment evidence event is missing',
        );
      }
      final payload = (jsonDecode(event.read<String>('payload_json')) as Map)
          .cast<String, Object?>();
      final payloadContext = payload['evidenceContext'];
      if (payloadContext is! Map ||
          jsonEncode(payloadContext) != jsonEncode(context.toJson())) {
        throw _assessmentConflict(
          run.id,
          'assessment event evidence context differs',
        );
      }
      payload['evidenceContext'] = normalized;
      await (_database.update(
            _database.eventsV2,
          )..where((row) => row.eventId.equals(event.read<String>('event_id'))))
          .write(db.EventsV2Companion(payloadJson: Value(jsonEncode(payload))));
      await (_database.update(
        _database.answerAttempts,
      )..where((row) => row.id.equals(attemptId))).write(
        db.AnswerAttemptsCompanion(evidenceContextJson: Value(encodedContext)),
      );
    }
  }

  EvidenceContext _readAssessmentEvidenceContext(
    String encoded,
    AssessmentRun run,
  ) {
    try {
      final context = EvidenceContext.fromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
      if (context.evidenceClass != EvidenceClass.assessment ||
          context.assignmentId != run.assignmentId ||
          context.experimentId != run.experimentId ||
          context.experimentVersion != run.experimentVersion ||
          context.cohort != run.cohort ||
          context.protocolId != run.protocolId ||
          context.protocolVersion != run.protocolVersion ||
          context.researchConsentVersion != run.consentVersion ||
          context.instrumentId != run.instrumentId ||
          context.instrumentVersion != run.instrumentVersion ||
          context.formId != run.formId ||
          context.formVersion != run.formVersion ||
          context.contentRevision != run.contentRevision ||
          context.policyVersion != run.evidencePolicyVersion ||
          context.featureContractRevision != run.featureContractRevision ||
          context.featureContractHash != run.featureContractHash) {
        throw const FormatException('assessment evidence identity mismatch');
      }
      return context;
    } on Object {
      throw _assessmentConflict(
        run.id,
        'assessment evidence metadata is malformed',
      );
    }
  }

  AssessmentRun _readAssessmentRunOrConflict(QueryRow row) {
    final runId = row.read<String>('id');
    try {
      return AssessmentRun(
        id: runId,
        ownerId: row.read<String>('owner_id'),
        learningSessionId: row.read<String>('learning_session_id'),
        studyCycleId: row.read<String>('study_cycle_id'),
        phase: AssessmentPhase.values.singleWhere(
          (value) => value.name == row.read<String>('phase'),
        ),
        state: AssessmentRunState.values.singleWhere(
          (value) => value.name == row.read<String>('state'),
        ),
        protocolId: row.read<String>('protocol_id'),
        protocolVersion: row.read<String>('protocol_version'),
        experimentId: row.read<String>('experiment_id'),
        experimentVersion: row.read<int>('experiment_version'),
        assignmentId: row.read<String>('assignment_id'),
        cohort: row.read<String>('cohort'),
        consentVersion: row.read<int>('consent_version'),
        consentDecidedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('consent_decided_at_utc_ms'),
          isUtc: true,
        ),
        instrumentId: row.read<String>('instrument_id'),
        instrumentVersion: row.read<String>('instrument_version'),
        formId: row.read<String>('form_id'),
        formVersion: row.read<String>('form_version'),
        instrumentChecksumSha256: row.read<String>(
          'instrument_checksum_sha256',
        ),
        formChecksumSha256: row.read<String>('form_checksum_sha256'),
        appVersion: row.read<String>('app_version'),
        buildId: row.read<String>('build_id'),
        databaseSchemaVersion: row.read<int>('database_schema_version'),
        contentRevision: row.read<String>('content_revision'),
        evidencePolicyVersion: row.read<String>('evidence_policy_version'),
        featureContractRevision: row.read<String>('feature_contract_revision'),
        featureContractHash: row.read<String>('feature_contract_hash'),
        startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('started_at_utc_ms'),
          isUtc: true,
        ),
        completedAtUtc: _nullableAssessmentUtc(
          row.readNullable<int>('completed_at_utc_ms'),
        ),
        abandonedAtUtc: _nullableAssessmentUtc(
          row.readNullable<int>('abandoned_at_utc_ms'),
        ),
      );
    } on Object {
      throw _assessmentConflict(runId, 'assessment run is malformed');
    }
  }

  DateTime? _nullableAssessmentUtc(int? milliseconds) => milliseconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

  AssessmentRunConflict _assessmentConflict(String runId, String reason) {
    return AssessmentRunConflict(runId: runId, reason: reason);
  }

  Future<void> _mergeExperimentAssignments(
    String sourceId,
    String targetId,
  ) async {
    final sourceRows = await _database
        .customSelect(
          'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
          'protocol_version, assigned_at_utc_ms FROM experiment_assignments '
          'WHERE owner_id = ? ORDER BY experiment_id, experiment_version, id',
          variables: [Variable<String>(sourceId)],
          readsFrom: {_database.experimentAssignments},
        )
        .get();

    for (final sourceRow in sourceRows) {
      final source = _readExperimentAssignment(sourceRow);
      _validateExperimentAssignmentIdentity(source);
      final targetAssignmentId =
          DriftExperimentAssignmentRepository.canonicalAssignmentId(
            ownerId: targetId,
            experimentId: source.experimentId,
            experimentVersion: source.experimentVersion,
          );
      final targetRow = await _database
          .customSelect(
            'SELECT id, owner_id, experiment_id, experiment_version, cohort, '
            'protocol_version, assigned_at_utc_ms FROM experiment_assignments '
            'WHERE owner_id = ? AND experiment_id = ? '
            'AND experiment_version = ? LIMIT 1',
            variables: [
              Variable<String>(targetId),
              Variable<String>(source.experimentId),
              Variable<int>(source.experimentVersion),
            ],
            readsFrom: {_database.experimentAssignments},
          )
          .getSingleOrNull();

      if (targetRow != null) {
        final target = _readExperimentAssignment(targetRow);
        _validateExperimentAssignmentIdentity(target);
        if (source.cohort != target.cohort ||
            source.protocolVersion != target.protocolVersion ||
            source.assignedAtUtc != target.assignedAtUtc) {
          throw ExperimentAssignmentConflict(
            ownerId: targetId,
            experimentId: source.experimentId,
            experimentVersion: source.experimentVersion,
          );
        }
        await (_database.delete(
          _database.experimentAssignments,
        )..where((row) => row.id.equals(source.id))).go();
        continue;
      }

      final idCollision = await (_database.select(
        _database.experimentAssignments,
      )..where((row) => row.id.equals(targetAssignmentId))).getSingleOrNull();
      if (idCollision != null) {
        throw ExperimentAssignmentConflict(
          ownerId: targetId,
          experimentId: source.experimentId,
          experimentVersion: source.experimentVersion,
        );
      }
      await (_database.update(
        _database.experimentAssignments,
      )..where((row) => row.id.equals(source.id))).write(
        db.ExperimentAssignmentsCompanion(
          id: Value(targetAssignmentId),
          ownerId: Value(targetId),
        ),
      );
    }
  }

  Future<void> _reconcileExperimentAssignmentOutbox({
    required String ownerId,
    required String firebaseUid,
    required Set<String> historicalOwnerIds,
  }) async {
    final assignments = await (_database.select(
      _database.experimentAssignments,
    )..where((row) => row.ownerId.equals(ownerId))).get();
    final operations =
        await (_database.select(_database.outboxOperations)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.entityType.equals('experimentAssignment'),
            ))
            .get();
    if (operations.isEmpty) return;

    final reconciledOperationIds = <String>{};
    for (final assignment in assignments) {
      final allowedEntityIds = <String>{
        for (final historicalOwnerId in historicalOwnerIds)
          DriftExperimentAssignmentRepository.canonicalAssignmentId(
            ownerId: historicalOwnerId,
            experimentId: assignment.experimentId,
            experimentVersion: assignment.experimentVersion,
          ),
        DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
          firebaseUid: firebaseUid,
          experimentId: assignment.experimentId,
          experimentVersion: assignment.experimentVersion,
        ),
      };
      final matches = operations
          .where((operation) => allowedEntityIds.contains(operation.entityId))
          .toList(growable: false);
      if (matches.isEmpty) continue;

      for (final operation in matches) {
        final canonicalOperationId =
            DriftExperimentAssignmentRepository.canonicalOutboxOperationId(
              operation.entityId,
            );
        if (operation.operationId != canonicalOperationId ||
            operation.operationKind != 'upsert' ||
            operation.payloadVersion != 1 ||
            operation.baseRevision != 0 ||
            operation.createdAtUtcMs != assignment.assignedAtUtcMs) {
          throw ExperimentAssignmentConflict(
            ownerId: ownerId,
            experimentId: assignment.experimentId,
            experimentVersion: assignment.experimentVersion,
          );
        }
        reconciledOperationIds.add(operation.operationId);
      }

      final cloudEntityId =
          DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
            firebaseUid: firebaseUid,
            experimentId: assignment.experimentId,
            experimentVersion: assignment.experimentVersion,
          );
      final cloudOperationId =
          DriftExperimentAssignmentRepository.canonicalOutboxOperationId(
            cloudEntityId,
          );
      db.OutboxOperation? canonicalCloudOperation;
      for (final operation in matches) {
        if (operation.operationId == cloudOperationId &&
            operation.entityId == cloudEntityId) {
          canonicalCloudOperation = operation;
          break;
        }
      }
      if (canonicalCloudOperation != null) {
        final staleOperationIds = matches
            .where((operation) => operation.operationId != cloudOperationId)
            .map((operation) => operation.operationId)
            .toList(growable: false);
        if (staleOperationIds.isNotEmpty) {
          await (_database.delete(
            _database.outboxOperations,
          )..where((row) => row.operationId.isIn(staleOperationIds))).go();
        }
        continue;
      }
      final unrelatedCollision =
          await (_database.select(_database.outboxOperations)
                ..where((row) => row.operationId.equals(cloudOperationId)))
              .getSingleOrNull();
      if (unrelatedCollision != null &&
          !matches.any(
            (operation) => operation.operationId == cloudOperationId,
          )) {
        throw ExperimentAssignmentConflict(
          ownerId: ownerId,
          experimentId: assignment.experimentId,
          experimentVersion: assignment.experimentVersion,
        );
      }

      await (_database.delete(_database.outboxOperations)..where(
            (row) => row.operationId.isIn(
              matches.map((operation) => operation.operationId),
            ),
          ))
          .go();
      await _database
          .into(_database.outboxOperations)
          .insert(
            db.OutboxOperationsCompanion.insert(
              operationId: cloudOperationId,
              ownerId: ownerId,
              entityType: 'experimentAssignment',
              entityId: cloudEntityId,
              operationKind: 'upsert',
              payloadVersion: const Value(1),
              baseRevision: const Value(0),
              createdAtUtcMs: assignment.assignedAtUtcMs,
            ),
          );
    }

    if (reconciledOperationIds.length != operations.length) {
      final assignment = assignments.isEmpty ? null : assignments.first;
      throw ExperimentAssignmentConflict(
        ownerId: ownerId,
        experimentId: assignment?.experimentId ?? 'unknown-assignment',
        experimentVersion: assignment?.experimentVersion ?? 1,
      );
    }
  }

  ExperimentAssignment _readExperimentAssignment(QueryRow row) {
    return ExperimentAssignment(
      id: row.read<String>('id'),
      ownerId: row.read<String>('owner_id'),
      experimentId: row.read<String>('experiment_id'),
      experimentVersion: row.read<int>('experiment_version'),
      cohort: row.read<String>('cohort'),
      protocolVersion: row.read<String>('protocol_version'),
      assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('assigned_at_utc_ms'),
        isUtc: true,
      ),
    );
  }

  void _validateExperimentAssignmentIdentity(ExperimentAssignment assignment) {
    final values = <String>[
      assignment.ownerId,
      assignment.experimentId,
      assignment.cohort,
      assignment.protocolVersion,
    ];
    final isMalformed =
        values.any(
          (value) =>
              value.isEmpty ||
              value != value.trim() ||
              value.runes.length > 256,
        ) ||
        assignment.experimentVersion <= 0 ||
        assignment.assignedAtUtc.millisecondsSinceEpoch < 0 ||
        assignment.id !=
            DriftExperimentAssignmentRepository.canonicalAssignmentId(
              ownerId: assignment.ownerId,
              experimentId: assignment.experimentId,
              experimentVersion: assignment.experimentVersion,
            );
    if (isMalformed) {
      throw ExperimentAssignmentConflict(
        ownerId: assignment.ownerId,
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
      );
    }
  }

  Future<void> _moveOwnerRows(String sourceId, String targetId) async {
    for (final table in ownerUpgradeInventory) {
      if (table == 'learner_preferences') continue;
      await _updateOwner(table, sourceId, targetId);
    }
    await _database.customUpdate(
      "UPDATE sync_checkpoints SET id = owner_id || ':' || collection_name "
      'WHERE owner_id = ?',
      variables: [Variable<String>(targetId)],
      updates: {_database.syncCheckpoints},
    );
    await _database.customUpdate(
      "UPDATE outbox_operations "
      "SET state = 'pending', lease_token = NULL, lease_expires_at_utc_ms = NULL "
      "WHERE owner_id = ? AND state = 'blockedAuth'",
      variables: [Variable<String>(targetId)],
      updates: {_database.outboxOperations},
    );
  }

  Future<void> _mergeSessionConfigurations(
    String sourceId,
    String targetId,
  ) async {
    final sourceRows = await (_database.select(
      _database.sessionConfigurations,
    )..where((row) => row.ownerId.equals(sourceId))).get();
    for (final source in sourceRows) {
      final target =
          await (_database.select(_database.sessionConfigurations)..where(
                (row) =>
                    row.ownerId.equals(targetId) & row.mode.equals(source.mode),
              ))
              .getSingleOrNull();
      final sourceWins =
          target == null || source.updatedAtUtcMs > target.updatedAtUtcMs;
      await (_database.delete(_database.sessionConfigurations)..where(
            (row) =>
                row.ownerId.equals(sourceId) & row.mode.equals(source.mode),
          ))
          .go();
      if (!sourceWins) continue;
      try {
        final decoded = SessionConfiguration.fromStableSerialization(
          source.stableSerialization,
        );
        if (decoded.ownerId != sourceId ||
            decoded.mode.name != source.mode ||
            decoded.contentIdentity != source.contentIdentity) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.tampered,
          );
        }
        final rebound = SessionConfiguration.validated(
          schemaVersion: decoded.schemaVersion,
          policyVersion: decoded.policyVersion,
          ownerId: targetId,
          mode: decoded.mode,
          itemCount: decoded.itemCount,
          direction: decoded.direction,
          difficulty: decoded.difficulty,
          hintBudget: decoded.hintBudget,
          timing: decoded.timing,
          packIdentity: decoded.packIdentity,
          protocolId: decoded.protocolId,
          protocolVersion: decoded.protocolVersion,
          protocolLimitsIdentity: decoded.protocolLimitsIdentity,
        );
        await _database
            .into(_database.sessionConfigurations)
            .insertOnConflictUpdate(
              db.SessionConfigurationsCompanion.insert(
                ownerId: targetId,
                mode: rebound.mode.name,
                contentIdentity: rebound.contentIdentity,
                stableSerialization: rebound.stableSerialization,
                updatedAtUtcMs: source.updatedAtUtcMs,
              ),
            );
      } on SessionConfigurationResetRequired {
        // Configuration is advisory. A corrupt preference cannot block the
        // owner transition or mutate assignment/evidence history.
      }
    }
  }

  Future<void> _rebindLearningSessionConfigurations(
    String sourceId,
    String targetId,
  ) async {
    final rows =
        await (_database.select(_database.learningSessions)..where(
              (row) =>
                  row.ownerId.equals(sourceId) &
                  row.sessionConfigurationIdentity.isNotNull(),
            ))
            .get();
    for (final row in rows) {
      final serialization = row.sessionConfigurationJson;
      final identity = row.sessionConfigurationIdentity;
      if (serialization == null || identity == null) continue;
      try {
        final decoded = SessionConfiguration.fromStableSerialization(
          serialization,
        );
        if (decoded.ownerId != sourceId ||
            decoded.contentIdentity != identity) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.tampered,
          );
        }
        final rebound = SessionConfiguration.validated(
          schemaVersion: decoded.schemaVersion,
          policyVersion: decoded.policyVersion,
          ownerId: targetId,
          mode: decoded.mode,
          itemCount: decoded.itemCount,
          direction: decoded.direction,
          difficulty: decoded.difficulty,
          hintBudget: decoded.hintBudget,
          timing: decoded.timing,
          packIdentity: decoded.packIdentity,
          protocolId: decoded.protocolId,
          protocolVersion: decoded.protocolVersion,
          protocolLimitsIdentity: decoded.protocolLimitsIdentity,
        );
        await (_database.update(
          _database.learningSessions,
        )..where((candidate) => candidate.id.equals(row.id))).write(
          db.LearningSessionsCompanion(
            sessionConfigurationIdentity: Value(rebound.contentIdentity),
            sessionConfigurationJson: Value(rebound.stableSerialization),
          ),
        );
      } on SessionConfigurationResetRequired {
        // Preserve malformed history byte-for-byte. It remains unavailable to
        // lesson restart and surfaces as a typed reset after the transition.
      }
    }
  }

  Future<void> _normalizeLearningProjectionState(
    String sourceId,
    String targetId,
  ) async {
    final sourceHasLearning = await _hasLearningEvents(sourceId);
    final targetHasLearning = await _hasLearningEvents(targetId);
    final cursors =
        await (_database.select(_database.eventsV2)..where(
              (row) =>
                  row.eventType.equals('LearningProjectionCursor') &
                  row.ownerId.isIn([sourceId, targetId]),
            ))
            .get();
    final grouped = <String, List<db.EventsV2Data>>{};
    for (final cursor in cursors) {
      final payload = jsonDecode(cursor.payloadJson) as Map<String, dynamic>;
      final projection = payload['projection'] as String;
      final version = payload['appliedVersion'] as int;
      grouped.putIfAbsent('$projection:v$version', () => []).add(cursor);
    }
    for (final entry in grouped.entries) {
      final parts = entry.key.split(':v');
      final projection = parts.first;
      final version = int.parse(parts.last);
      final sourceCursors = entry.value
          .where((cursor) => cursor.ownerId == sourceId)
          .toList();
      final targetCursors = entry.value
          .where((cursor) => cursor.ownerId == targetId)
          .toList();
      db.EventsV2Data? safe;
      if ((!sourceHasLearning || sourceCursors.isNotEmpty) &&
          (!targetHasLearning || targetCursors.isNotEmpty)) {
        final candidates = <db.EventsV2Data>[
          if (sourceHasLearning) ...sourceCursors,
          if (targetHasLearning) ...targetCursors,
        ];
        if (candidates.isNotEmpty) {
          candidates.sort(_compareProjectionCursor);
          safe = candidates.first;
        }
      }
      for (final cursor in entry.value) {
        if (safe == null || cursor.eventId != safe.eventId) {
          await (_database.delete(
            _database.eventsV2,
          )..where((row) => row.eventId.equals(cursor.eventId))).go();
        }
      }
      if (safe != null) {
        final normalizedKey =
            'learning-projection-cursor:$targetId:$projection:v$version';
        await _database.customUpdate(
          'UPDATE events_v2 SET event_id = ?, idempotency_key = ?, '
          'actor_identity = ? WHERE event_id = ?',
          variables: [
            Variable<String>(normalizedKey),
            Variable<String>(normalizedKey),
            Variable<String>(targetId),
            Variable<String>(safe.eventId),
          ],
          updates: {_database.eventsV2},
        );
      }
    }

    final projectionResults =
        await (_database.select(_database.eventsV2)..where(
              (row) =>
                  row.ownerId.isIn([sourceId, targetId]) &
                  row.aggregateType.equals('LearningProjection') &
                  (row.eventType.equals('LearningProjectionApplied') |
                      row.eventType.equals('LearningProjectionSkipped')),
            ))
            .get();
    for (final receipt in projectionResults) {
      final payload = jsonDecode(receipt.payloadJson) as Map<String, dynamic>;
      if (payload['projection'] == 'streak') {
        final changed = _normalizeStreakReceiptOwner(
          payload: payload,
          sourceId: sourceId,
          targetId: targetId,
        );
        if (changed) {
          await (_database.update(
            _database.eventsV2,
          )..where((row) => row.eventId.equals(receipt.eventId))).write(
            db.EventsV2Companion(payloadJson: Value(jsonEncode(payload))),
          );
        }
        continue;
      }
      if (payload['projection'] != 'quest') continue;
      final result = payload['result'];
      if (result is! Map) continue;
      final grants = result['rewardGrants'];
      if (grants is! List) continue;
      var changed = false;
      for (final value in grants) {
        if (value is Map && value['ownerId'] == sourceId) {
          value['ownerId'] = targetId;
          changed = true;
        }
      }
      if (!changed) continue;
      await (_database.update(_database.eventsV2)
            ..where((row) => row.eventId.equals(receipt.eventId)))
          .write(db.EventsV2Companion(payloadJson: Value(jsonEncode(payload))));
    }

    final streakApplications =
        await (_database.select(_database.eventsV2)..where(
              (row) =>
                  row.ownerId.isIn([sourceId, targetId]) &
                  row.eventType.equals('StreakPolicyApplied'),
            ))
            .get();
    for (final application in streakApplications) {
      final decoded = jsonDecode(application.payloadJson);
      if (decoded is! Map) {
        throw StateError('invalid streak application during owner upgrade');
      }
      final payload = decoded.cast<String, dynamic>();
      final changed = _normalizeStreakReceiptOwner(
        payload: payload,
        sourceId: sourceId,
        targetId: targetId,
      );
      if (!changed) continue;
      await (_database.update(_database.eventsV2)
            ..where((row) => row.eventId.equals(application.eventId)))
          .write(db.EventsV2Companion(payloadJson: Value(jsonEncode(payload))));
    }
  }

  bool _normalizeStreakReceiptOwner({
    required Map<String, dynamic> payload,
    required String sourceId,
    required String targetId,
  }) {
    final rawResult = payload['result'];
    if (rawResult is! Map) return false;
    final result = rawResult.cast<String, dynamic>();
    if (!result.containsKey('ownerId') && !result.containsKey('receiptId')) {
      return false;
    }
    final ownerId = result['ownerId'];
    final learningDay = result['learningDay'];
    final policyVersion = result['policyVersion'];
    final receiptId = result['receiptId'];
    if ((ownerId != sourceId && ownerId != targetId) ||
        learningDay is! String ||
        policyVersion is! int ||
        policyVersion < 1 ||
        receiptId != 'gentle-streak:$ownerId:$learningDay:v$policyVersion') {
      throw StateError('invalid streak receipt during owner upgrade');
    }
    if (ownerId == targetId) return false;
    result['ownerId'] = targetId;
    result['receiptId'] =
        'gentle-streak:$targetId:$learningDay:v$policyVersion';
    payload['result'] = result;
    return true;
  }

  Future<bool> _hasLearningEvents(String ownerId) async {
    final row = await _database
        .customSelect(
          'SELECT 1 AS present FROM events_v2 '
          "WHERE owner_id = ? AND idempotency_key LIKE 'learning-attempt:%' "
          'LIMIT 1',
          variables: [Variable<String>(ownerId)],
          readsFrom: {_database.eventsV2},
        )
        .getSingleOrNull();
    return row != null;
  }

  int _compareProjectionCursor(db.EventsV2Data left, db.EventsV2Data right) {
    final time = left.occurredAtUtc.compareTo(right.occurredAtUtc);
    if (time != 0) return time;
    return left.aggregateId.compareTo(right.aggregateId);
  }

  Future<void> _discardAiUsageDuplicates(
    String sourceId,
    String targetId,
  ) async {
    await _database.customUpdate(
      'DELETE FROM ai_usage_events '
      'WHERE owner_id = ? AND event_id IN ('
      'SELECT event_id FROM ai_usage_events WHERE owner_id = ?'
      ')',
      variables: [Variable<String>(sourceId), Variable<String>(targetId)],
      updates: {_database.aiUsageEvents},
    );
  }

  Future<void> _requeueOwnerForNewCloudNamespace(
    String ownerId,
    int rehomedAtUtcMs,
  ) async {
    await _resetLearnerPreferenceForCloudNamespace(ownerId, rehomedAtUtcMs);
    await (_database.update(
      _database.vocabularyCategories,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.VocabularyCategoriesCompanion(
        cloudRevision: Value(0),
        lastAcknowledgedAtUtcMs: Value(null),
        serverUpdatedAtUtcMs: Value(null),
      ),
    );
    await (_database.update(
      _database.vocabularyWords,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.VocabularyWordsCompanion(
        cloudRevision: Value(0),
        lastAcknowledgedAtUtcMs: Value(null),
        serverUpdatedAtUtcMs: Value(null),
      ),
    );
    await (_database.update(
      _database.savedLearningItems,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.SavedLearningItemsCompanion(
        cloudRevision: Value(0),
        lastAcknowledgedAtUtcMs: Value(null),
        serverUpdatedAtUtcMs: Value(null),
      ),
    );
    await (_database.update(
      _database.learningGoals,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.LearningGoalsCompanion(
        cloudRevision: Value(0),
        lastAcknowledgedAtUtcMs: Value(null),
        serverUpdatedAtUtcMs: Value(null),
      ),
    );
    await (_database.update(
      _database.syncCheckpoints,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.SyncCheckpointsCompanion(
        serverCursor: Value(null),
        lastSuccessAtUtcMs: Value(null),
      ),
    );

    for (final specification in const <_RehomeSpecification>[
      _RehomeSpecification(
        table: 'vocabulary_categories',
        entityType: 'category',
        hasSoftDelete: true,
      ),
      _RehomeSpecification(
        table: 'vocabulary_words',
        entityType: 'word',
        hasSoftDelete: true,
      ),
      _RehomeSpecification(table: 'answer_attempts', entityType: 'attempt'),
      _RehomeSpecification(table: 'reading_events', entityType: 'readingEvent'),
      _RehomeSpecification(
        table: 'reward_transactions',
        entityType: 'rewardTransaction',
      ),
      _RehomeSpecification(
        table: 'srs_states',
        entityType: 'srsState',
        entityIdColumn: 'word_id',
      ),
      _RehomeSpecification(
        table: 'achievement_unlocks',
        entityType: 'achievementUnlock',
      ),
      _RehomeSpecification(
        table: 'saved_learning_items',
        entityType: 'savedLearningItem',
        hasSoftDelete: true,
      ),
      _RehomeSpecification(
        table: 'content_quality_reports',
        entityType: 'contentQualityReport',
        createOutboxWhenMissing: false,
      ),
      _RehomeSpecification(
        table: 'learning_time_segments',
        entityType: 'learningTimeSegment',
      ),
      _RehomeSpecification(
        table: 'learning_goals',
        entityType: 'learningGoal',
        hasSoftDelete: true,
      ),
    ]) {
      final rows = await _database
          .customSelect(
            'SELECT id, ${specification.entityIdColumn} AS entity_id'
            "${specification.hasSoftDelete ? ', is_deleted' : ''} "
            'FROM ${specification.table} WHERE owner_id = ? ORDER BY id',
            variables: [Variable<String>(ownerId)],
          )
          .get();
      for (final row in rows) {
        final entityId = row.read<String>('entity_id');
        final changed = await _database.customUpdate(
          "UPDATE outbox_operations SET base_revision = 0, state = 'pending', "
          'attempt_count = 0, next_attempt_at_utc_ms = NULL, '
          'lease_token = NULL, lease_expires_at_utc_ms = NULL, '
          'last_attempt_at_utc_ms = NULL, acknowledged_at_utc_ms = NULL, '
          'failure_code = NULL '
          'WHERE owner_id = ? AND entity_type = ? AND entity_id = ?',
          variables: [
            Variable<String>(ownerId),
            Variable<String>(specification.entityType),
            Variable<String>(entityId),
          ],
          updates: {_database.outboxOperations},
        );
        if (changed > 0) continue;
        if (!specification.createOutboxWhenMissing) continue;
        var baseRevision = 0;
        late final String operationId;
        if (specification.entityType == 'srsState') {
          final evidence = await _database
              .customSelect(
                'SELECT COUNT(*) AS revision, '
                '(SELECT id FROM answer_attempts '
                ' WHERE owner_id = ? AND word_id = ? '
                ' ORDER BY occurred_at_utc_ms DESC, id DESC LIMIT 1) '
                'AS latest_attempt_id '
                'FROM answer_attempts WHERE owner_id = ? AND word_id = ?',
                variables: [
                  Variable<String>(ownerId),
                  Variable<String>(entityId),
                  Variable<String>(ownerId),
                  Variable<String>(entityId),
                ],
              )
              .getSingle();
          final durableRevision = evidence.read<int>('revision');
          final revision = durableRevision < 1 ? 1 : durableRevision;
          final latestAttemptId =
              evidence.readNullable<String>('latest_attempt_id') ??
              'rehome:${_requiredId(generateConflictId(), 'operationId')}';
          operationId = SrsOperationIdentity.create(
            ownerId: ownerId,
            wordId: entityId,
            answerAttemptId: latestAttemptId,
            revision: revision,
          );
          baseRevision = revision - 1;
        } else if (specification.entityType == 'learningTimeSegment') {
          operationId = LearningTimeSegment.canonicalOperationId(entityId);
        } else {
          final generated = _requiredId(generateConflictId(), 'operationId');
          operationId = _requiredId('rehome:$generated', 'operationId');
        }
        await _database
            .into(_database.outboxOperations)
            .insert(
              db.OutboxOperationsCompanion.insert(
                operationId: operationId,
                ownerId: ownerId,
                entityType: specification.entityType,
                entityId: entityId,
                operationKind:
                    specification.hasSoftDelete &&
                        row.read<int>('is_deleted') != 0
                    ? 'delete'
                    : 'upsert',
                baseRevision: Value(baseRevision),
                createdAtUtcMs: rehomedAtUtcMs,
              ),
            );
      }
    }
  }

  Future<void> _mergeLearnerPreferences(
    String sourceId,
    String targetId,
    int rehomedAtUtcMs,
  ) async {
    final source = await (_database.select(
      _database.learnerPreferences,
    )..where((row) => row.ownerId.equals(sourceId))).getSingleOrNull();
    if (source == null) return;
    final target = await (_database.select(
      _database.learnerPreferences,
    )..where((row) => row.ownerId.equals(targetId))).getSingleOrNull();
    await (_database.delete(
      _database.learnerPreferences,
    )..where((row) => row.ownerId.equals(sourceId))).go();
    if (target != null && source.updatedAtUtcMs <= target.updatedAtUtcMs) {
      await _retireLearnerPreferenceSourceOutbox(
        sourceOwnerId: sourceId,
        targetOwnerId: targetId,
      );
      return;
    }
    final baseRevision = target?.cloudRevision ?? 0;
    final localRevision = baseRevision + 1;
    await _database
        .into(_database.learnerPreferences)
        .insertOnConflictUpdate(
          db.LearnerPreferencesCompanion.insert(
            ownerId: targetId,
            preferenceVersion: source.preferenceVersion,
            goal: source.goal,
            availableMinutesPerDay: source.availableMinutesPerDay,
            activityPreference: source.activityPreference,
            updatedAtUtcMs: source.updatedAtUtcMs,
            localRevision: Value(localRevision),
            cloudRevision: Value(baseRevision),
            lastAcknowledgedAtUtcMs: Value(target?.lastAcknowledgedAtUtcMs),
            serverUpdatedAtUtcMs: Value(target?.serverUpdatedAtUtcMs),
            isDeleted: Value(source.isDeleted),
          ),
        );
    await _replaceLearnerPreferenceOutbox(
      sourceOwnerId: sourceId,
      targetOwnerId: targetId,
      baseRevision: baseRevision,
      localRevision: localRevision,
      rehomedAtUtcMs: rehomedAtUtcMs,
    );
  }

  Future<void> _resetLearnerPreferenceForCloudNamespace(
    String ownerId,
    int rehomedAtUtcMs,
  ) async {
    final preference = await (_database.select(
      _database.learnerPreferences,
    )..where((row) => row.ownerId.equals(ownerId))).getSingleOrNull();
    if (preference == null) return;
    await (_database.update(
      _database.learnerPreferences,
    )..where((row) => row.ownerId.equals(ownerId))).write(
      const db.LearnerPreferencesCompanion(
        localRevision: Value(1),
        cloudRevision: Value(0),
        lastAcknowledgedAtUtcMs: Value(null),
        serverUpdatedAtUtcMs: Value(null),
      ),
    );
    await _replaceLearnerPreferenceOutbox(
      sourceOwnerId: ownerId,
      targetOwnerId: ownerId,
      baseRevision: 0,
      localRevision: 1,
      rehomedAtUtcMs: rehomedAtUtcMs,
    );
  }

  Future<void> _retireLearnerPreferenceSourceOutbox({
    required String sourceOwnerId,
    required String targetOwnerId,
  }) {
    return _database.customUpdate(
      "UPDATE outbox_operations SET owner_id = ?, entity_id = ?, "
      "state = 'superseded', next_attempt_at_utc_ms = NULL, "
      'lease_token = NULL, lease_expires_at_utc_ms = NULL, '
      "failure_code = 'guestUpgradePreferenceReplaced' "
      "WHERE entity_type = 'learnerPreference' AND owner_id = ?",
      variables: [
        Variable<String>(targetOwnerId),
        Variable<String>(targetOwnerId),
        Variable<String>(sourceOwnerId),
      ],
      updates: {_database.outboxOperations},
    );
  }

  Future<void> _replaceLearnerPreferenceOutbox({
    required String sourceOwnerId,
    required String targetOwnerId,
    required int baseRevision,
    required int localRevision,
    required int rehomedAtUtcMs,
  }) async {
    await _database.customUpdate(
      "UPDATE outbox_operations SET owner_id = ?, entity_id = ?, "
      "state = 'superseded', next_attempt_at_utc_ms = NULL, "
      'lease_token = NULL, lease_expires_at_utc_ms = NULL, '
      "failure_code = 'guestUpgradePreferenceReplaced' "
      "WHERE entity_type = 'learnerPreference' "
      "AND (owner_id = ? OR (owner_id = ? AND state NOT IN "
      "('acknowledged', 'superseded', 'conflictResolved')))",
      variables: [
        Variable<String>(targetOwnerId),
        Variable<String>(targetOwnerId),
        Variable<String>(sourceOwnerId),
        Variable<String>(targetOwnerId),
      ],
      updates: {_database.outboxOperations},
    );
    await _database
        .into(_database.outboxOperations)
        .insertOnConflictUpdate(
          db.OutboxOperationsCompanion.insert(
            operationId: 'learnerPreference:$targetOwnerId:$localRevision',
            ownerId: targetOwnerId,
            entityType: 'learnerPreference',
            entityId: targetOwnerId,
            operationKind: 'upsert',
            payloadVersion: const Value(1),
            baseRevision: Value(baseRevision),
            state: const Value('pending'),
            attemptCount: const Value(0),
            nextAttemptAtUtcMs: const Value(null),
            leaseToken: const Value(null),
            leaseExpiresAtUtcMs: const Value(null),
            lastAttemptAtUtcMs: const Value(null),
            createdAtUtcMs: rehomedAtUtcMs,
            acknowledgedAtUtcMs: const Value(null),
            failureCode: const Value(null),
          ),
        );
  }

  Future<void> _reviveConvertedTargetAvatarPermissionFailures({
    required String ownerId,
    required Set<String> transactionIds,
    required int rehomedAtUtcMs,
  }) async {
    if (transactionIds.isEmpty) return;
    await (_database.update(_database.outboxOperations)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entityType.equals('rewardTransaction') &
              row.entityId.isIn(transactionIds) &
              row.state.equals('permanentFailure') &
              row.failureCode.equals(SyncFailureCode.permissionDenied.name) &
              row.attemptCount.isSmallerThanValue(maxSyncSendReservations),
        ))
        .write(
          db.OutboxOperationsCompanion(
            state: const Value('retryWaiting'),
            nextAttemptAtUtcMs: Value(rehomedAtUtcMs),
            leaseToken: const Value(null),
            leaseExpiresAtUtcMs: const Value(null),
            failureCode: const Value(null),
          ),
        );
  }

  Future<void> _rebuildLearningProjections(String ownerId) async {
    final rebuilder = DriftLearningProjectionRebuilder(
      _database,
      evidencePolicy: evidencePolicy,
      rolloutModeProvider: rolloutModeProvider,
    );
    final wordRows = await _database
        .customSelect(
          'SELECT DISTINCT word_id FROM answer_attempts '
          'WHERE owner_id = ? ORDER BY word_id',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    for (final row in wordRows) {
      await rebuilder.rebuildWord(
        ownerId: ownerId,
        wordId: row.read<String>('word_id'),
      );
    }

    final sessionRows = await _database
        .customSelect(
          'SELECT DISTINCT session_id FROM answer_attempts '
          'WHERE owner_id = ? ORDER BY session_id',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    for (final row in sessionRows) {
      await rebuilder.rebuildSession(
        ownerId: ownerId,
        sessionId: row.read<String>('session_id'),
      );
    }
    await rebuilder.rebuildAchievements(ownerId);

    final readingRows = await _database
        .customSelect(
          'SELECT DISTINCT document_id, document_revision FROM reading_events '
          'WHERE owner_id = ? ORDER BY document_id, document_revision',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    for (final row in readingRows) {
      await rebuilder.rebuildReading(
        ownerId: ownerId,
        documentId: row.read<String>('document_id'),
        documentRevision: row.read<int>('document_revision'),
      );
    }
  }

  Future<void> _updateOwner(String table, String sourceId, String targetId) {
    return _database.customUpdate(
      'UPDATE $table SET owner_id = ? WHERE owner_id = ?',
      variables: [Variable<String>(targetId), Variable<String>(sourceId)],
    );
  }

  Future<void> _remapEntityReferences(
    String sourceOwnerId,
    String entityType,
    String sourceEntityId,
    String targetEntityId,
  ) async {
    await _database.customUpdate(
      'UPDATE outbox_operations SET entity_id = ? '
      'WHERE owner_id = ? AND entity_type = ? AND entity_id = ?',
      variables: [
        Variable<String>(targetEntityId),
        Variable<String>(sourceOwnerId),
        Variable<String>(entityType),
        Variable<String>(sourceEntityId),
      ],
      updates: {_database.outboxOperations},
    );
    await _database.customUpdate(
      'UPDATE sync_conflicts SET entity_id = ? '
      'WHERE owner_id = ? AND entity_type = ? AND entity_id = ?',
      variables: [
        Variable<String>(targetEntityId),
        Variable<String>(sourceOwnerId),
        Variable<String>(entityType),
        Variable<String>(sourceEntityId),
      ],
      updates: {_database.syncConflicts},
    );
  }

  Future<void> _retireDuplicateOutbox(
    String ownerId,
    String entityType,
    String entityId,
  ) {
    return (_database.update(_database.outboxOperations)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entityType.equals(entityType) &
              row.entityId.equals(entityId),
        ))
        .write(
          const db.OutboxOperationsCompanion(
            state: Value('superseded'),
            nextAttemptAtUtcMs: Value(null),
            leaseToken: Value(null),
            leaseExpiresAtUtcMs: Value(null),
            failureCode: Value('guestUpgradeDuplicate'),
          ),
        );
  }

  Future<void> _recordMergeConflict({
    required String ownerId,
    required String entityType,
    required String entityId,
    required Map<String, Object?> localSnapshot,
    required Map<String, Object?> targetSnapshot,
    required String resolutionPolicy,
    required String outcome,
    required int resolvedAt,
  }) async {
    final conflictId = _requiredId(generateConflictId(), 'conflictId');
    await _database.customInsert(
      '''
      INSERT INTO sync_conflicts
        (id, owner_id, entity_type, entity_id, local_revision, cloud_revision,
         resolution_policy, outcome, local_snapshot_json,
         cloud_snapshot_json, resolved_at_utc_ms)
      VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable<String>(conflictId),
        Variable<String>(ownerId),
        Variable<String>(entityType),
        Variable<String>(entityId),
        Variable<String>(_requiredId(resolutionPolicy, 'resolutionPolicy')),
        Variable<String>(_requiredId(outcome, 'outcome')),
        Variable<String>(jsonEncode(localSnapshot)),
        Variable<String>(jsonEncode(targetSnapshot)),
        Variable<int>(resolvedAt),
      ],
      updates: {_database.syncConflicts},
    );
  }

  Future<db.LocalOwner?> _ownerById(String id) {
    return (_database.select(
      _database.localOwners,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<db.LocalOwner?> _ownerByFirebaseUid(String uid) {
    return (_database.select(
      _database.localOwners,
    )..where((row) => row.firebaseUid.equals(uid))).getSingleOrNull();
  }

  Future<T> _withOwnerOperationGate<T>(
    Future<T> Function(String operationToken) operation,
  ) async {
    final operationToken = _requiredId(
      generateOwnerOperationToken(),
      'ownerOperationToken',
    );
    final deadline = _requireUtc(nowUtc()).add(ownerGateWaitTimeout);
    while (!await ownerOperationGate.tryAcquire(
      token: operationToken,
      nowUtc: _requireUtc(nowUtc()),
      leaseDuration: ownerGateLeaseDuration,
    )) {
      if (!_requireUtc(nowUtc()).isBefore(deadline)) {
        throw TimeoutException('owner-operation gate wait timed out');
      }
      await ownerGateDelay(ownerGateRetryInterval);
    }

    final stopHeartbeat = Completer<void>();
    final heartbeat = _runOwnerGateHeartbeat(operationToken, stopHeartbeat);
    try {
      return await operation(operationToken);
    } finally {
      if (!stopHeartbeat.isCompleted) stopHeartbeat.complete();
      await heartbeat;
      await ownerOperationGate.release(token: operationToken);
    }
  }

  Future<void> _runOwnerGateHeartbeat(
    String operationToken,
    Completer<void> stop,
  ) async {
    while (true) {
      await Future.any<void>(<Future<void>>[
        ownerGateDelay(ownerGateHeartbeatInterval),
        stop.future,
      ]);
      if (stop.isCompleted) return;
      final renewed = await ownerOperationGate.renew(
        token: operationToken,
        nowUtc: _requireUtc(nowUtc()),
        leaseDuration: ownerGateLeaseDuration,
      );
      if (!renewed) return;
    }
  }

  Future<bool> _fenceOwnerTransition(String operationToken) async {
    final nowMs = _requireUtc(nowUtc()).millisecondsSinceEpoch;
    final changed = await _database.customUpdate(
      '''
      UPDATE runtime_flags
      SET updated_at_utc_ms = updated_at_utc_ms
      WHERE "key" = ?
        AND bool_value = 1
        AND source = ?
        AND expires_at_utc_ms IS NOT NULL
        AND expires_at_utc_ms > ?
      ''',
      variables: [
        const Variable<String>(DriftOwnerOperationGate.gateKey),
        Variable<String>(operationToken),
        Variable<int>(nowMs),
      ],
      updates: {_database.runtimeFlags},
    );
    return changed == 1;
  }

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _writeGate;
    final completer = Completer<void>();
    _writeGate = completer.future;
    try {
      await previous;
      return await operation();
    } finally {
      completer.complete();
    }
  }
}

abstract final class _GuestUpgradeConflictPolicy {
  static const canonicalTarget = 'guestUpgradeCanonicalTarget';
  static const latestConsentDecision = 'guestUpgradeLatestConsentDecision';
  static const combinedAnswerEvidence = 'guestUpgradeCombinedAnswerEvidence';
  static const latestSrs = 'guestUpgradeLatestSrs';
  static const streakReconciliation = 'guestUpgradeStreakReconciliation';
  static const earliestLearningDay = 'guestUpgradeEarliestLearningDay';
  static const latestAssociation = 'guestUpgradeLatestAssociation';
  static const latestMemory = 'guestUpgradeLatestMemory';
  static const rankedQuest = 'guestUpgradeRankedQuest';
  static const rankedQuestObjective = 'guestUpgradeRankedQuestObjective';
  static const preserveBoth = 'guestUpgradePreserveBoth';
  static const latestSavedIntent = 'guestUpgradeLatestSavedIntent';
}

abstract final class _GuestUpgradeConflictOutcome {
  static const targetRetained = 'targetRetained';
  static const guestRetained = 'guestRetained';
  static const evidenceMerged = 'evidenceMerged';
  static const bothRetained = 'bothRetained';
}

Map<String, Object?> _streakSnapshot(db.StreakState value) => <String, Object?>{
  'ownerId': value.ownerId,
  'currentStreakDays': value.currentStreakDays,
  'longestStreakDays': value.longestStreakDays,
  'freezeCount': value.freezeCount,
  'lastLearnedAtUtcMs': value.lastLearnedAtUtcMs,
  'updatedAtUtcMs': value.updatedAtUtcMs,
};

String _resolvedStreakOutcome({
  required db.StreakState guest,
  required db.StreakState target,
  required int current,
  required int longest,
  required int freezeCount,
  required int? lastLearnedAtUtcMs,
  required int updatedAtUtcMs,
}) {
  bool matches(db.StreakState candidate) =>
      candidate.currentStreakDays == current &&
      candidate.longestStreakDays == longest &&
      candidate.freezeCount == freezeCount &&
      candidate.lastLearnedAtUtcMs == lastLearnedAtUtcMs &&
      candidate.updatedAtUtcMs == updatedAtUtcMs;
  if (matches(target)) return _GuestUpgradeConflictOutcome.targetRetained;
  if (matches(guest)) return _GuestUpgradeConflictOutcome.guestRetained;
  return _GuestUpgradeConflictOutcome.evidenceMerged;
}

final class _ResearchConsentDecision {
  const _ResearchConsentDecision({
    required this.id,
    required this.version,
    required this.state,
    required this.decidedAtUtcMs,
    required this.withdrawnAtUtcMs,
  });

  final String id;
  final int version;
  final String state;
  final int decidedAtUtcMs;
  final int? withdrawnAtUtcMs;

  bool get isWithdrawn => state != 'accepted' || withdrawnAtUtcMs != null;

  bool get hasAmbiguousOrdering =>
      (state != 'accepted' && state != 'withdrawn') ||
      (state == 'accepted' && withdrawnAtUtcMs != null) ||
      (state == 'withdrawn' && withdrawnAtUtcMs != decidedAtUtcMs);

  int get effectiveDecisionAtUtcMs {
    final withdrawal = withdrawnAtUtcMs;
    return withdrawal != null && withdrawal > decidedAtUtcMs
        ? withdrawal
        : decidedAtUtcMs;
  }

  Map<String, Object?> get snapshot => <String, Object?>{
    'id': id,
    'consentVersion': version,
    'consentState': state,
    'decidedAtUtcMs': decidedAtUtcMs,
    'withdrawnAtUtcMs': withdrawnAtUtcMs,
  };
}

bool _guestConsentDecisionWins(
  _ResearchConsentDecision guest,
  _ResearchConsentDecision target,
) {
  if ((guest.hasAmbiguousOrdering || target.hasAmbiguousOrdering) &&
      guest.isWithdrawn != target.isWithdrawn) {
    return guest.isWithdrawn;
  }
  final timeComparison = guest.effectiveDecisionAtUtcMs.compareTo(
    target.effectiveDecisionAtUtcMs,
  );
  if (timeComparison != 0) return timeComparison > 0;
  if (guest.isWithdrawn != target.isWithdrawn) return guest.isWithdrawn;
  return false;
}

final class _DuplicateSpecification {
  const _DuplicateSpecification({
    required this.table,
    required this.entityType,
    required this.join,
    this.outboxEntityType,
  });

  final String table;
  final String entityType;
  final String join;
  final String? outboxEntityType;
}

final class _RehomeSpecification {
  const _RehomeSpecification({
    required this.table,
    required this.entityType,
    this.hasSoftDelete = false,
    this.entityIdColumn = 'id',
    this.createOutboxWhenMissing = true,
  });

  final String table;
  final String entityType;
  final bool hasSoftDelete;
  final String entityIdColumn;
  final bool createOutboxWhenMissing;
}

int _compareQuestState({
  required String state,
  required int catalogVersion,
  required int timestamp,
  required String stableId,
  required String otherState,
  required int otherCatalogVersion,
  required int otherTimestamp,
  required String otherStableId,
}) {
  final stateComparison = _questStateRank(
    state,
  ).compareTo(_questStateRank(otherState));
  if (stateComparison != 0) return stateComparison;
  final catalogComparison = catalogVersion.compareTo(otherCatalogVersion);
  if (catalogComparison != 0) return catalogComparison;
  final timestampComparison = timestamp.compareTo(otherTimestamp);
  if (timestampComparison != 0) return timestampComparison;
  return stableId.compareTo(otherStableId);
}

int _questStateRank(String state) => switch (state) {
  'completed' => 4,
  'active' => 3,
  'expired' => 2,
  'abandoned' => 1,
  _ => 0,
};

List<String> _decodeStringList(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! List || decoded.any((value) => value is! String)) {
    throw StateError('quest objective source evidence is invalid');
  }
  return decoded.cast<String>();
}

String _requiredId(String value, String field) {
  final canonical = value.trim();
  if (canonical.isEmpty || canonical.length > 256) {
    throw ArgumentError.value(value, field, 'must contain 1-256 characters');
  }
  return canonical;
}

DateTime _requireUtc(DateTime value) {
  if (!value.isUtc) {
    throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
  }
  return value;
}

Future<void> _defaultOwnerGateDelay(Duration delay) =>
    Future<void>.delayed(delay);
