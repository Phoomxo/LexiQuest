import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../research/data/drift_experiment_assignment_repository.dart';
import '../domain/cloud_sync_policy.dart';
import '../domain/sync_entity.dart';
import '../domain/sync_failure.dart';
import '../domain/sync_gateway.dart';
import '../domain/sync_result.dart';

typedef UtcClock = DateTime Function();
typedef ContentQualityReportPushAuthorizer =
    Future<bool> Function(PushMutation mutation);

final class FirestoreSyncGateway
    implements
        SyncGateway,
        LearningTimeSegmentSyncRolloutGateway,
        LearningGoalSyncRolloutGateway,
        LearnerPreferenceSyncRolloutGateway {
  factory FirestoreSyncGateway({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    UtcClock? utcClock,
    SavedLearningItemSyncRollout savedLearningItemRollout =
        const SavedLearningItemSyncRollout.off(),
    ContentQualityReportSyncRollout contentQualityReportRollout =
        const ContentQualityReportSyncRollout.off(),
    LearningTimeSegmentSyncRollout learningTimeSegmentRollout =
        const LearningTimeSegmentSyncRollout.off(),
    LearningGoalSyncRollout learningGoalRollout =
        const LearningGoalSyncRollout.off(),
    LearnerPreferenceSyncRollout learnerPreferenceRollout =
        const LearnerPreferenceSyncRollout.off(),
    ContentQualityReportPushAuthorizer contentQualityReportPushAuthorizer =
        _denyContentQualityReportPush,
  }) => FirestoreSyncGateway._(
    firestore,
    auth,
    utcClock ?? _systemUtcClock,
    const FirestoreSyncPreflight(),
    savedLearningItemRollout,
    contentQualityReportRollout,
    learningTimeSegmentRollout,
    learningGoalRollout,
    learnerPreferenceRollout,
    contentQualityReportPushAuthorizer,
  );

  FirestoreSyncGateway._(
    this._firestore,
    this._auth,
    this._utcClock,
    this._preflight,
    this._savedLearningItemRollout,
    this._contentQualityReportRollout,
    this._learningTimeSegmentRollout,
    this._learningGoalRollout,
    this._learnerPreferenceRollout,
    this._contentQualityReportPushAuthorizer,
  );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UtcClock _utcClock;
  final FirestoreSyncPreflight _preflight;
  final SavedLearningItemSyncRollout _savedLearningItemRollout;
  final ContentQualityReportSyncRollout _contentQualityReportRollout;
  final LearningTimeSegmentSyncRollout _learningTimeSegmentRollout;
  final LearningGoalSyncRollout _learningGoalRollout;
  final LearnerPreferenceSyncRollout _learnerPreferenceRollout;
  final ContentQualityReportPushAuthorizer _contentQualityReportPushAuthorizer;

  @override
  LearningTimeSegmentSyncRollout get learningTimeSegmentSyncRollout =>
      _learningTimeSegmentRollout;

  @override
  LearningGoalSyncRollout get learningGoalSyncRollout => _learningGoalRollout;

  @override
  LearnerPreferenceSyncRollout get learnerPreferenceSyncRollout =>
      _learnerPreferenceRollout;

  @override
  Future<PushResult> push(PushMutation mutation) async {
    if (_auth.currentUser?.uid != mutation.firebaseUid) {
      throw const UnauthenticatedSyncFailure();
    }
    if (mutation.collection == SyncCollection.savedLearningItems &&
        !_savedLearningItemRollout.allowsClaims) {
      throw const PermissionDeniedSyncFailure();
    }
    if (mutation.collection == SyncCollection.contentQualityReports &&
        !_contentQualityReportRollout.allowsClaims) {
      throw const PermissionDeniedSyncFailure();
    }
    if (mutation.collection == SyncCollection.learningTimeSegments &&
        !_learningTimeSegmentRollout.allowsClaims) {
      throw const PermissionDeniedSyncFailure();
    }
    if (mutation.collection == SyncCollection.learningGoals &&
        !_learningGoalRollout.allowsClaims) {
      throw const PermissionDeniedSyncFailure();
    }
    if (mutation.collection == SyncCollection.learnerPreferences &&
        !_learnerPreferenceRollout.allowsClaims) {
      throw const PermissionDeniedSyncFailure();
    }

    final user = _firestore.collection('field_users').doc(mutation.firebaseUid);
    final operation = user.collection('operations').doc(mutation.operationId);
    final entity = user
        .collection(mutation.collection.wireName)
        .doc(mutation.entityId);

    try {
      final transactionResult = await _preflight
          .beforeTransaction<_TransactionPushResult>(
            collection: mutation.collection,
            payloadVersion: mutation.payloadVersion,
            payload: mutation.payload,
            entityId: mutation.entityId,
            firebaseUid: mutation.firebaseUid,
            isDeleted: mutation.operationKind == SyncOperationKind.delete,
            clientUpdatedAtUtcMs:
                mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
            authorizeContentQualityReportPush: () =>
                _contentQualityReportPushAuthorizer(mutation),
            beginTransaction: () => _firestore
                .runTransaction<_TransactionPushResult>((transaction) async {
                  final operationSnapshot = await transaction.get(operation);
                  if (operationSnapshot.exists) {
                    return _TransactionPushResult.acknowledged(
                      FirestoreSyncCodec.decodeAcknowledgement(
                        operationSnapshot.data()!,
                        expectedMutation: mutation,
                      ),
                    );
                  }

                  final entitySnapshot = await transaction.get(entity);
                  final currentRevision = entitySnapshot.exists
                      ? _requiredInt(entitySnapshot.data()!, 'revision')
                      : 0;
                  if (currentRevision != mutation.baseRevision) {
                    if (!entitySnapshot.exists) {
                      throw const InvalidSyncPayloadFailure();
                    }
                    return _TransactionPushResult.conflict(
                      FirestoreSyncCodec.decodeEntity(
                        collection: mutation.collection,
                        documentId: entitySnapshot.id,
                        data: entitySnapshot.data()!,
                        expectedFirebaseUid: mutation.firebaseUid,
                      ),
                    );
                  }

                  transaction.set(
                    entity,
                    FirestoreSyncCodec.encodeEntity(
                      mutation,
                      serverTimestamp: FieldValue.serverTimestamp(),
                    ),
                  );
                  transaction.set(
                    operation,
                    FirestoreSyncCodec.encodeOperation(
                      mutation,
                      acknowledgedAt: FieldValue.serverTimestamp(),
                    ),
                  );
                  return const _TransactionPushResult.pendingAcknowledgement();
                }),
          );

      final immediate = transactionResult.result;
      if (immediate != null) return immediate;

      final acknowledgement = await operation.get(
        const GetOptions(source: Source.server),
      );
      if (!acknowledgement.exists) {
        throw const ProviderUnavailableSyncFailure();
      }
      return FirestoreSyncCodec.decodeAcknowledgement(
        acknowledgement.data()!,
        expectedMutation: mutation,
      );
    } on SyncFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw FirestoreSyncErrorMapper.fromCode(error.code);
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    if (_auth.currentUser?.uid != firebaseUid) {
      throw const UnauthenticatedSyncFailure();
    }
    if (limit < 1 || limit > 100) {
      throw const InvalidSyncPayloadFailure();
    }
    if (collection == SyncCollection.savedLearningItems &&
        !_savedLearningItemRollout.allowsClaims) {
      return PullPage(changes: const [], nextCursor: after, hasMore: false);
    }
    if (collection == SyncCollection.contentQualityReports &&
        !_contentQualityReportRollout.allowsClaims) {
      return PullPage(changes: const [], nextCursor: after, hasMore: false);
    }
    if (collection == SyncCollection.learningTimeSegments &&
        !_learningTimeSegmentRollout.allowsClaims) {
      return PullPage(changes: const [], nextCursor: after, hasMore: false);
    }
    if (collection == SyncCollection.learningGoals &&
        !_learningGoalRollout.allowsClaims) {
      return PullPage(changes: const [], nextCursor: after, hasMore: false);
    }
    if (collection == SyncCollection.learnerPreferences &&
        !_learnerPreferenceRollout.allowsClaims) {
      return PullPage(changes: const [], nextCursor: after, hasMore: false);
    }

    if (collection == SyncCollection.learnerPreferences) {
      try {
        return await pullLearnerPreferenceSingleton(
          firebaseUid: firebaseUid,
          after: after,
          readDocument: (documentPath) async =>
              (await _firestore
                      .doc(documentPath)
                      .get(const GetOptions(source: Source.server)))
                  .data(),
        );
      } on SyncFailure {
        rethrow;
      } on FirebaseException catch (error) {
        throw FirestoreSyncErrorMapper.fromCode(error.code);
      } catch (_) {
        throw const InvalidSyncPayloadFailure();
      }
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('field_users')
        .doc(firebaseUid)
        .collection(collection.wireName)
        .orderBy('serverUpdatedAt')
        .orderBy(FieldPath.documentId)
        .limit(limit);
    if (after != null) {
      query = query.startAfter(<Object>[
        Timestamp.fromDate(after.serverUpdatedAtUtc),
        after.documentId,
      ]);
    }

    try {
      final snapshot = await query.get(const GetOptions(source: Source.server));
      final changes = snapshot.docs
          .map(
            (document) => FirestoreSyncCodec.decodeEntity(
              collection: collection,
              documentId: document.id,
              data: document.data(),
              expectedFirebaseUid: firebaseUid,
            ),
          )
          .toList(growable: false);
      final last = changes.isEmpty ? null : changes.last;
      return PullPage(
        changes: changes,
        nextCursor: last == null
            ? after
            : SyncCursor(
                serverUpdatedAtUtc: last.serverUpdatedAtUtc,
                documentId: last.entityId,
              ),
        hasMore: snapshot.docs.length == limit,
      );
    } on SyncFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw FirestoreSyncErrorMapper.fromCode(error.code);
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static Future<PullPage> pullLearnerPreferenceSingleton({
    required String firebaseUid,
    required SyncCursor? after,
    required Future<Map<String, Object?>?> Function(String documentPath)
    readDocument,
  }) async {
    final documentPath =
        'field_users/$firebaseUid/${SyncCollection.learnerPreferences.wireName}/'
        '${LearnerPreferenceSyncPayloadContract.canonicalEntityId}';
    final data = await readDocument(documentPath);
    if (data == null) {
      return PullPage(changes: const [], nextCursor: after, hasMore: false);
    }
    final entity = FirestoreSyncCodec.decodeEntity(
      collection: SyncCollection.learnerPreferences,
      documentId: LearnerPreferenceSyncPayloadContract.canonicalEntityId,
      data: data,
      expectedFirebaseUid: firebaseUid,
    );
    final cursor = SyncCursor(
      serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
      documentId: entity.entityId,
    );
    if (after != null && _compareSyncCursors(cursor, after) <= 0) {
      return PullPage(changes: const [], nextCursor: after, hasMore: false);
    }
    return PullPage(
      changes: <SyncEntity>[entity],
      nextCursor: cursor,
      hasMore: false,
    );
  }

  @override
  Future<CloudSyncPolicy> fetchPolicy() async {
    try {
      final snapshot = await _firestore
          .collection('app_control')
          .doc('field')
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (data == null ||
          data['schemaVersion'] != currentCloudSyncPolicySchemaVersion ||
          data['cloudSyncEnabled'] is! bool) {
        throw const InvalidSyncPayloadFailure();
      }
      final fetchedAt = _utcClock().toUtc();
      return CloudSyncPolicy(
        enabled: data['cloudSyncEnabled']! as bool,
        source: CloudSyncPolicySource.remote,
        fetchedAtUtc: fetchedAt,
        expiresAtUtc: fetchedAt.add(const Duration(minutes: 15)),
      );
    } on SyncFailure {
      rethrow;
    } on FirebaseException catch (error) {
      throw FirestoreSyncErrorMapper.fromCode(error.code);
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }
}

int _compareSyncCursors(SyncCursor left, SyncCursor right) {
  final timestamp = left.serverUpdatedAtUtc.compareTo(right.serverUpdatedAtUtc);
  if (timestamp != 0) return timestamp;
  return left.documentId.compareTo(right.documentId);
}

final class FirestoreSyncPreflight {
  const FirestoreSyncPreflight();

  Future<T> beforeTransaction<T>({
    required SyncCollection collection,
    required int payloadVersion,
    Map<String, Object?>? payload,
    String? entityId,
    String? firebaseUid,
    bool? isDeleted,
    int? clientUpdatedAtUtcMs,
    Future<bool> Function()? authorizeContentQualityReportPush,
    required Future<T> Function() beginTransaction,
  }) async {
    collection.requireSupportedPayloadVersion(payloadVersion);
    if (collection == SyncCollection.words) {
      final wordPayload = payload;
      final payloadIsDeleted = wordPayload?['isDeleted'];
      if (wordPayload == null ||
          clientUpdatedAtUtcMs == null ||
          payloadIsDeleted is! bool) {
        throw const InvalidSyncPayloadFailure();
      }
      VocabularyWordSyncPayloadContract.requireCanonical(
        payloadVersion: payloadVersion,
        payload: wordPayload,
        isDeleted: isDeleted ?? payloadIsDeleted,
        clientUpdatedAtUtcMs: clientUpdatedAtUtcMs,
      );
    } else if (collection == SyncCollection.attempts) {
      final attemptPayload = payload;
      if (attemptPayload == null) {
        throw const InvalidSyncPayloadFailure();
      }
      AnswerAttemptSyncPayloadContract.requireEvidenceContext(
        payloadVersion: payloadVersion,
        payload: attemptPayload,
      );
    } else if (collection == SyncCollection.experimentAssignments) {
      final assignmentPayload = payload;
      if (assignmentPayload == null || entityId == null) {
        throw const InvalidSyncPayloadFailure();
      }
      ExperimentAssignmentSyncPayloadContract.requireCanonical(
        payload: assignmentPayload,
        expectedEntityId: entityId,
        expectedOwnerId: firebaseUid,
        expectedAssignedAtUtcMs: clientUpdatedAtUtcMs,
      );
      _requireCanonicalExperimentAssignmentId(
        payload: assignmentPayload,
        entityId: entityId,
      );
    } else if (collection == SyncCollection.assessmentRuns) {
      final runPayload = payload;
      if (runPayload == null ||
          entityId == null ||
          clientUpdatedAtUtcMs == null) {
        throw const InvalidSyncPayloadFailure();
      }
      final state = runPayload['state'];
      final revision = state == 'active' ? 1 : 2;
      AssessmentRunSyncPayloadContract.requireCanonical(
        payload: runPayload,
        expectedEntityId: entityId,
        expectedOwnerId: firebaseUid,
        revision: revision,
        isDeleted: false,
        clientUpdatedAtUtcMs: clientUpdatedAtUtcMs,
      );
      _requireCanonicalAssessmentAssignmentId(runPayload);
    } else if (collection == SyncCollection.savedLearningItems) {
      final savedPayload = payload;
      if (savedPayload == null ||
          entityId == null ||
          isDeleted == null ||
          clientUpdatedAtUtcMs == null) {
        throw const InvalidSyncPayloadFailure();
      }
      SavedLearningItemSyncPayloadContract.requireCanonical(
        payload: savedPayload,
        isDeleted: isDeleted,
        clientUpdatedAtUtcMs: clientUpdatedAtUtcMs,
        expectedEntityId: entityId,
      );
    } else if (collection == SyncCollection.contentQualityReports) {
      final reportPayload = payload;
      if (reportPayload == null ||
          entityId == null ||
          isDeleted == null ||
          clientUpdatedAtUtcMs == null) {
        throw const InvalidSyncPayloadFailure();
      }
      ContentQualityReportSyncPayloadContract.requireCanonical(
        payload: reportPayload,
        isDeleted: isDeleted,
        clientUpdatedAtUtcMs: clientUpdatedAtUtcMs,
        expectedEntityId: entityId,
      );
      if (authorizeContentQualityReportPush == null ||
          !await authorizeContentQualityReportPush()) {
        throw const ContentReportConsentWithdrawnSyncFailure();
      }
    } else if (collection == SyncCollection.learningTimeSegments) {
      final timePayload = payload;
      if (timePayload == null ||
          entityId == null ||
          isDeleted == null ||
          clientUpdatedAtUtcMs == null) {
        throw const InvalidSyncPayloadFailure();
      }
      LearningTimeSegmentSyncPayloadContract.requireCanonical(
        payload: timePayload,
        isDeleted: isDeleted,
        clientUpdatedAtUtcMs: clientUpdatedAtUtcMs,
        expectedEntityId: entityId,
      );
    } else if (collection == SyncCollection.learningGoals) {
      final goalPayload = payload;
      if (goalPayload == null ||
          entityId == null ||
          isDeleted == null ||
          clientUpdatedAtUtcMs == null) {
        throw const InvalidSyncPayloadFailure();
      }
      LearningGoalSyncPayloadContract.requireCanonical(
        payload: goalPayload,
        isDeleted: isDeleted,
        clientUpdatedAtUtcMs: clientUpdatedAtUtcMs,
        expectedEntityId: entityId,
      );
    } else if (collection == SyncCollection.learnerPreferences) {
      final preferencePayload = payload;
      if (preferencePayload == null ||
          entityId == null ||
          firebaseUid == null ||
          isDeleted == null ||
          clientUpdatedAtUtcMs == null) {
        throw const InvalidSyncPayloadFailure();
      }
      LearnerPreferenceSyncPayloadContract.requireCanonical(
        payload: preferencePayload,
        expectedEntityId: entityId,
        expectedOwnerId: firebaseUid,
        isDeleted: isDeleted,
        clientUpdatedAtUtcMs: clientUpdatedAtUtcMs,
      );
    }
    return beginTransaction();
  }
}

Future<bool> _denyContentQualityReportPush(PushMutation _) async => false;

final class FirestoreSyncCodec {
  const FirestoreSyncCodec._();

  static Map<String, Object?> encodeEntity(
    PushMutation mutation, {
    required Object serverTimestamp,
  }) {
    _requireValidPayload(mutation);
    return <String, Object?>{
      'schemaVersion': mutation.payloadVersion,
      'entityId': mutation.entityId,
      'payload': mutation.payload,
      'revision': mutation.localRevision,
      'isDeleted': mutation.operationKind == SyncOperationKind.delete,
      'clientUpdatedAtUtcMs':
          mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
      'serverUpdatedAt': serverTimestamp,
      'lastOperationId': mutation.operationId,
    };
  }

  static Map<String, Object?> encodeOperation(
    PushMutation mutation, {
    required Object acknowledgedAt,
  }) {
    _requireValidPayload(mutation);
    return <String, Object?>{
      'schemaVersion': mutation.payloadVersion,
      'operationId': mutation.operationId,
      'entityType': mutation.collection.entityType,
      'entityId': mutation.entityId,
      'operationKind': mutation.operationKind.name,
      'baseRevision': mutation.baseRevision,
      'resultingRevision': mutation.localRevision,
      'acknowledgedAt': acknowledgedAt,
    };
  }

  static SyncEntity decodeEntity({
    required SyncCollection collection,
    required String documentId,
    required Map<String, Object?> data,
    String? expectedFirebaseUid,
  }) {
    final schemaVersion = _requiredInt(data, 'schemaVersion');
    collection.requireSupportedPayloadVersion(schemaVersion);
    final entityId = _requiredString(data, 'entityId');
    if (entityId != documentId) {
      throw const InvalidSyncPayloadFailure();
    }
    _requiredString(data, 'lastOperationId');
    final timestamp = data['serverUpdatedAt'];
    final payload = data['payload'];
    if (timestamp is! Timestamp || payload is! Map) {
      throw const InvalidSyncPayloadFailure();
    }
    try {
      final canonicalPayload = Map<String, Object?>.from(payload);
      if (collection == SyncCollection.words) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        VocabularyWordSyncPayloadContract.requireCanonical(
          payloadVersion: schemaVersion,
          payload: canonicalPayload,
          isDeleted: _requiredBool(data, 'isDeleted'),
          clientUpdatedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
        );
      } else if (collection == SyncCollection.attempts) {
        AnswerAttemptSyncPayloadContract.requireEvidenceContext(
          payloadVersion: schemaVersion,
          payload: canonicalPayload,
        );
      } else if (collection == SyncCollection.achievementUnlocks) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        final revision = _requiredInt(data, 'revision');
        final deleted = _requiredBool(data, 'isDeleted');
        AchievementUnlockSyncPayloadContract.requireCompatible(
          payload: canonicalPayload,
          entityId: entityId,
          clientUpdatedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
        );
        if (revision != 1 || deleted) {
          throw const InvalidSyncPayloadFailure();
        }
      } else if (collection == SyncCollection.experimentAssignments) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        ExperimentAssignmentSyncPayloadContract.requireCanonical(
          payload: canonicalPayload,
          expectedEntityId: entityId,
          expectedOwnerId: expectedFirebaseUid,
          expectedAssignedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
        );
        _requireCanonicalExperimentAssignmentId(
          payload: canonicalPayload,
          entityId: entityId,
        );
        if (_requiredInt(data, 'revision') != 1 ||
            _requiredBool(data, 'isDeleted')) {
          throw const InvalidSyncPayloadFailure();
        }
      } else if (collection == SyncCollection.assessmentRuns) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        AssessmentRunSyncPayloadContract.requireCanonical(
          payload: canonicalPayload,
          expectedEntityId: entityId,
          expectedOwnerId: expectedFirebaseUid,
          revision: _requiredInt(data, 'revision'),
          isDeleted: _requiredBool(data, 'isDeleted'),
          clientUpdatedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
        );
        _requireCanonicalAssessmentAssignmentId(canonicalPayload);
      } else if (collection == SyncCollection.savedLearningItems) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        SavedLearningItemSyncPayloadContract.requireCanonical(
          payload: canonicalPayload,
          isDeleted: _requiredBool(data, 'isDeleted'),
          clientUpdatedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
          expectedEntityId: entityId,
        );
      } else if (collection == SyncCollection.contentQualityReports) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        final revision = _requiredInt(data, 'revision');
        final deleted = _requiredBool(data, 'isDeleted');
        ContentQualityReportSyncPayloadContract.requireCanonical(
          payload: canonicalPayload,
          isDeleted: deleted,
          clientUpdatedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
          expectedEntityId: entityId,
        );
        if (revision != 1 || deleted) {
          throw const InvalidSyncPayloadFailure();
        }
      } else if (collection == SyncCollection.learningTimeSegments) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        final revision = _requiredInt(data, 'revision');
        final deleted = _requiredBool(data, 'isDeleted');
        LearningTimeSegmentSyncPayloadContract.requireCanonical(
          payload: canonicalPayload,
          isDeleted: deleted,
          clientUpdatedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
          expectedEntityId: entityId,
        );
        if (revision != 1 || deleted) {
          throw const InvalidSyncPayloadFailure();
        }
      } else if (collection == SyncCollection.learningGoals) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        LearningGoalSyncPayloadContract.requireCanonical(
          payload: canonicalPayload,
          isDeleted: _requiredBool(data, 'isDeleted'),
          clientUpdatedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
          expectedEntityId: entityId,
        );
      } else if (collection == SyncCollection.learnerPreferences) {
        _requireExactKeys(data, _entityEnvelopeKeys);
        if (expectedFirebaseUid == null) {
          throw const InvalidSyncPayloadFailure();
        }
        LearnerPreferenceSyncPayloadContract.requireCanonical(
          payload: canonicalPayload,
          expectedEntityId: entityId,
          expectedOwnerId: expectedFirebaseUid,
          isDeleted: _requiredBool(data, 'isDeleted'),
          clientUpdatedAtUtcMs: _requiredInt(data, 'clientUpdatedAtUtcMs'),
        );
      }
      return SyncEntity(
        collection: collection,
        entityId: entityId,
        revision: _requiredInt(data, 'revision'),
        isDeleted: _requiredBool(data, 'isDeleted'),
        payloadVersion: schemaVersion,
        clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          _requiredInt(data, 'clientUpdatedAtUtcMs'),
          isUtc: true,
        ),
        serverUpdatedAtUtc: timestamp.toDate().toUtc(),
        payload: canonicalPayload,
      );
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static PushAcknowledged decodeAcknowledgement(
    Map<String, Object?> data, {
    required PushMutation expectedMutation,
  }) {
    _requireValidPayload(expectedMutation);
    if (expectedMutation.collection == SyncCollection.achievementUnlocks ||
        expectedMutation.collection == SyncCollection.experimentAssignments ||
        expectedMutation.collection == SyncCollection.assessmentRuns ||
        expectedMutation.collection == SyncCollection.savedLearningItems ||
        expectedMutation.collection == SyncCollection.contentQualityReports ||
        expectedMutation.collection == SyncCollection.learningTimeSegments ||
        expectedMutation.collection == SyncCollection.learningGoals ||
        expectedMutation.collection == SyncCollection.learnerPreferences) {
      _requireExactKeys(data, _operationEnvelopeKeys);
    }
    if (_requiredInt(data, 'schemaVersion') !=
            expectedMutation.payloadVersion ||
        _requiredString(data, 'operationId') != expectedMutation.operationId ||
        _requiredString(data, 'entityType') !=
            expectedMutation.collection.entityType ||
        _requiredString(data, 'entityId') != expectedMutation.entityId ||
        _requiredString(data, 'operationKind') !=
            expectedMutation.operationKind.name ||
        _requiredInt(data, 'baseRevision') != expectedMutation.baseRevision ||
        _requiredInt(data, 'resultingRevision') !=
            expectedMutation.localRevision) {
      throw const InvalidSyncPayloadFailure();
    }
    final timestamp = data['acknowledgedAt'];
    if (timestamp is! Timestamp) {
      throw const InvalidSyncPayloadFailure();
    }
    return PushAcknowledged(
      operationId: expectedMutation.operationId,
      resultingRevision: expectedMutation.localRevision,
      acknowledgedAtUtc: timestamp.toDate().toUtc(),
    );
  }

  static void _requireValidPayload(PushMutation mutation) {
    if (mutation.collection == SyncCollection.words) {
      VocabularyWordSyncPayloadContract.requireCanonical(
        payloadVersion: mutation.payloadVersion,
        payload: mutation.payload,
        isDeleted: mutation.operationKind == SyncOperationKind.delete,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
      );
      return;
    }
    if (mutation.collection == SyncCollection.attempts) {
      AnswerAttemptSyncPayloadContract.requireEvidenceContext(
        payloadVersion: mutation.payloadVersion,
        payload: mutation.payload,
      );
      return;
    }
    if (mutation.collection == SyncCollection.achievementUnlocks) {
      if (mutation.payloadVersion != 1 ||
          mutation.operationKind != SyncOperationKind.upsert ||
          mutation.baseRevision != 0 ||
          mutation.localRevision != 1) {
        throw const InvalidSyncPayloadFailure();
      }
      AchievementUnlockSyncPayloadContract.requireCompatible(
        payload: mutation.payload,
        entityId: mutation.entityId,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
      );
      final achievementId = mutation.payload['achievementId']! as String;
      final definitionVersion = mutation.payload['definitionVersion']! as int;
      final sourceEventId = mutation.payload['sourceEventId']! as String;
      final unlockedAtUtcMs = mutation.payload['unlockedAtUtcMs']! as int;
      if (!AchievementUnlockSyncPayloadContract.isCanonicalEntityId(
            entityId: mutation.entityId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
          ) ||
          mutation.operationId !=
              AchievementUnlockSyncPayloadContract.canonicalOperationId(
                achievementId: achievementId,
                definitionVersion: definitionVersion,
                sourceEventId: sourceEventId,
                unlockedAtUtcMs: unlockedAtUtcMs,
              )) {
        throw const InvalidSyncPayloadFailure();
      }
      return;
    }
    if (mutation.collection == SyncCollection.assessmentRuns) {
      if (mutation.payloadVersion != 1 ||
          mutation.operationKind != SyncOperationKind.upsert ||
          !((mutation.baseRevision == 0 && mutation.localRevision == 1) ||
              (mutation.baseRevision == 1 && mutation.localRevision == 2))) {
        throw const InvalidSyncPayloadFailure();
      }
      AssessmentRunSyncPayloadContract.requireCanonical(
        payload: mutation.payload,
        expectedEntityId: mutation.entityId,
        expectedOwnerId: mutation.firebaseUid,
        revision: mutation.localRevision,
        isDeleted: false,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
      );
      _requireCanonicalAssessmentAssignmentId(mutation.payload);
      return;
    }
    if (mutation.collection == SyncCollection.savedLearningItems) {
      if (mutation.payloadVersion != 1) {
        throw const InvalidSyncPayloadFailure();
      }
      SavedLearningItemSyncPayloadContract.requireCanonical(
        payload: mutation.payload,
        isDeleted: mutation.operationKind == SyncOperationKind.delete,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
        expectedEntityId: mutation.entityId,
      );
      return;
    }
    if (mutation.collection == SyncCollection.contentQualityReports) {
      if (mutation.payloadVersion != 1 ||
          mutation.operationKind != SyncOperationKind.upsert ||
          mutation.baseRevision != 0 ||
          mutation.localRevision != 1) {
        throw const InvalidSyncPayloadFailure();
      }
      ContentQualityReportSyncPayloadContract.requireCanonical(
        payload: mutation.payload,
        isDeleted: false,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
        expectedEntityId: mutation.entityId,
      );
      final reportId = mutation.payload['reportId']! as String;
      final submittedAtUtcMs = mutation.payload['submittedAtUtcMs']! as int;
      if (mutation.operationId !=
          ContentQualityReportSyncPayloadContract.canonicalOperationId(
            localOperationId: mutation.operationId,
            reportId: reportId,
            submittedAtUtcMs: submittedAtUtcMs,
          )) {
        throw const InvalidSyncPayloadFailure();
      }
      return;
    }
    if (mutation.collection == SyncCollection.learningTimeSegments) {
      if (mutation.payloadVersion != 1 ||
          mutation.operationKind != SyncOperationKind.upsert ||
          mutation.baseRevision != 0 ||
          mutation.localRevision != 1) {
        throw const InvalidSyncPayloadFailure();
      }
      LearningTimeSegmentSyncPayloadContract.requireCanonical(
        payload: mutation.payload,
        isDeleted: false,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
        expectedEntityId: mutation.entityId,
      );
      if (mutation.operationId !=
          LearningTimeSegmentSyncPayloadContract.canonicalOperationId(
            mutation.entityId,
          )) {
        throw const InvalidSyncPayloadFailure();
      }
      return;
    }
    if (mutation.collection == SyncCollection.learningGoals) {
      if (mutation.payloadVersion != 1) {
        throw const InvalidSyncPayloadFailure();
      }
      LearningGoalSyncPayloadContract.requireCanonical(
        payload: mutation.payload,
        isDeleted: mutation.operationKind == SyncOperationKind.delete,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
        expectedEntityId: mutation.entityId,
      );
      return;
    }
    if (mutation.collection == SyncCollection.learnerPreferences) {
      if (mutation.payloadVersion != 1 ||
          mutation.operationKind != SyncOperationKind.upsert ||
          mutation.localRevision != mutation.baseRevision + 1 ||
          mutation.operationId !=
              LearnerPreferenceSyncPayloadContract.canonicalOperationId(
                payload: mutation.payload,
                baseRevision: mutation.baseRevision,
                resultingRevision: mutation.localRevision,
              )) {
        throw const InvalidSyncPayloadFailure();
      }
      LearnerPreferenceSyncPayloadContract.requireCanonical(
        payload: mutation.payload,
        expectedEntityId: mutation.entityId,
        expectedOwnerId: mutation.firebaseUid,
        isDeleted: false,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
      );
      return;
    }
    if (mutation.collection != SyncCollection.experimentAssignments) return;
    if (mutation.payloadVersion != 1 ||
        mutation.operationKind != SyncOperationKind.upsert ||
        mutation.baseRevision != 0 ||
        mutation.localRevision != 1) {
      throw const InvalidSyncPayloadFailure();
    }
    ExperimentAssignmentSyncPayloadContract.requireCanonical(
      payload: mutation.payload,
      expectedEntityId: mutation.entityId,
      expectedOwnerId: mutation.firebaseUid,
      expectedAssignedAtUtcMs:
          mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
    );
    _requireCanonicalExperimentAssignmentId(
      payload: mutation.payload,
      entityId: mutation.entityId,
    );
  }

  static const Set<String> _entityEnvelopeKeys = <String>{
    'schemaVersion',
    'entityId',
    'payload',
    'revision',
    'isDeleted',
    'clientUpdatedAtUtcMs',
    'serverUpdatedAt',
    'lastOperationId',
  };

  static const Set<String> _operationEnvelopeKeys = <String>{
    'schemaVersion',
    'operationId',
    'entityType',
    'entityId',
    'operationKind',
    'baseRevision',
    'resultingRevision',
    'acknowledgedAt',
  };
}

final class FirestoreSyncErrorMapper {
  const FirestoreSyncErrorMapper._();

  static SyncFailure fromCode(String code) => switch (code) {
    'unauthenticated' => const UnauthenticatedSyncFailure(),
    'permission-denied' => const PermissionDeniedSyncFailure(),
    'invalid-argument' ||
    'failed-precondition' => const InvalidSyncPayloadFailure(),
    'resource-exhausted' => const QuotaSyncFailure(),
    'cancelled' ||
    'deadline-exceeded' ||
    'unavailable' ||
    'aborted' => const ProviderUnavailableSyncFailure(),
    _ => const ProviderUnavailableSyncFailure(),
  };
}

final class _TransactionPushResult {
  const _TransactionPushResult._(this.result);

  const _TransactionPushResult.acknowledged(PushAcknowledged acknowledgement)
    : this._(acknowledgement);

  _TransactionPushResult.conflict(SyncEntity entity)
    : this._(PushConflict(entity));

  const _TransactionPushResult.pendingAcknowledgement() : this._(null);

  final PushResult? result;
}

int _requiredInt(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! int) throw const InvalidSyncPayloadFailure();
  return value;
}

String _requiredString(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! String || value.trim().isEmpty || value.length > 256) {
    throw const InvalidSyncPayloadFailure();
  }
  return value;
}

bool _requiredBool(Map<String, Object?> data, String field) {
  final value = data[field];
  if (value is! bool) throw const InvalidSyncPayloadFailure();
  return value;
}

void _requireExactKeys(Map<String, Object?> data, Set<String> expectedKeys) {
  if (data.length != expectedKeys.length ||
      !data.keys.every(expectedKeys.contains)) {
    throw const InvalidSyncPayloadFailure();
  }
}

void _requireCanonicalExperimentAssignmentId({
  required Map<String, Object?> payload,
  required String entityId,
}) {
  final canonicalId =
      DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
        firebaseUid: payload['ownerId']! as String,
        experimentId: payload['experimentId']! as String,
        experimentVersion: payload['experimentVersion']! as int,
      );
  if (entityId != canonicalId || payload['assignmentId'] != canonicalId) {
    throw const InvalidSyncPayloadFailure();
  }
}

void _requireCanonicalAssessmentAssignmentId(Map<String, Object?> payload) {
  final canonicalId =
      DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
        firebaseUid: payload['ownerId']! as String,
        experimentId: payload['experimentId']! as String,
        experimentVersion: payload['experimentVersion']! as int,
      );
  if (payload['assignmentId'] != canonicalId) {
    throw const InvalidSyncPayloadFailure();
  }
}

DateTime _systemUtcClock() => DateTime.now().toUtc();
