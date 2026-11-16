import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/cloud_sync_policy.dart';
import '../domain/sync_entity.dart';
import '../domain/sync_failure.dart';
import '../domain/sync_gateway.dart';
import '../domain/sync_result.dart';

typedef UtcClock = DateTime Function();

final class FirestoreSyncGateway implements SyncGateway {
  factory FirestoreSyncGateway({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    UtcClock? utcClock,
  }) => FirestoreSyncGateway._(firestore, auth, utcClock ?? _systemUtcClock);

  FirestoreSyncGateway._(this._firestore, this._auth, this._utcClock);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UtcClock _utcClock;

  @override
  Future<PushResult> push(PushMutation mutation) async {
    if (_auth.currentUser?.uid != mutation.firebaseUid) {
      throw const UnauthenticatedSyncFailure();
    }

    final user = _firestore.collection('field_users').doc(mutation.firebaseUid);
    final operation = user.collection('operations').doc(mutation.operationId);
    final entity = user
        .collection(mutation.collection.wireName)
        .doc(mutation.entityId);

    try {
      final transactionResult = await _firestore
          .runTransaction<_TransactionPushResult>((transaction) async {
            final operationSnapshot = await transaction.get(operation);
            if (operationSnapshot.exists) {
              return _TransactionPushResult.acknowledged(
                FirestoreSyncCodec.decodeAcknowledgement(
                  operationSnapshot.data()!,
                  expectedOperationId: mutation.operationId,
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
          });

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
        expectedOperationId: mutation.operationId,
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

  @override
  Future<CloudSyncPolicy> fetchPolicy() async {
    try {
      final snapshot = await _firestore
          .collection('app_control')
          .doc('field')
          .get(const GetOptions(source: Source.server));
      final data = snapshot.data();
      if (data == null ||
          data['schemaVersion'] != currentSyncPayloadVersion ||
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

final class FirestoreSyncCodec {
  const FirestoreSyncCodec._();

  static Map<String, Object?> encodeEntity(
    PushMutation mutation, {
    required Object serverTimestamp,
  }) => <String, Object?>{
    'schemaVersion': mutation.payloadVersion,
    'entityId': mutation.entityId,
    'payload': mutation.payload,
    'revision': mutation.localRevision,
    'isDeleted': mutation.operationKind == SyncOperationKind.delete,
    'clientUpdatedAtUtcMs': mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
    'serverUpdatedAt': serverTimestamp,
    'lastOperationId': mutation.operationId,
  };

  static Map<String, Object?> encodeOperation(
    PushMutation mutation, {
    required Object acknowledgedAt,
  }) => <String, Object?>{
    'schemaVersion': mutation.payloadVersion,
    'operationId': mutation.operationId,
    'entityType': mutation.collection.entityType,
    'entityId': mutation.entityId,
    'operationKind': mutation.operationKind.name,
    'baseRevision': mutation.baseRevision,
    'resultingRevision': mutation.localRevision,
    'acknowledgedAt': acknowledgedAt,
  };

  static SyncEntity decodeEntity({
    required SyncCollection collection,
    required String documentId,
    required Map<String, Object?> data,
  }) {
    final schemaVersion = _requiredInt(data, 'schemaVersion');
    if (schemaVersion != currentSyncPayloadVersion) {
      throw const UnsupportedSyncSchemaFailure();
    }
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
        payload: Map<String, Object?>.from(payload),
      );
    } on SyncFailure {
      rethrow;
    } catch (_) {
      throw const InvalidSyncPayloadFailure();
    }
  }

  static PushAcknowledged decodeAcknowledgement(
    Map<String, Object?> data, {
    required String expectedOperationId,
  }) {
    if (_requiredInt(data, 'schemaVersion') != currentSyncPayloadVersion ||
        _requiredString(data, 'operationId') != expectedOperationId) {
      throw const InvalidSyncPayloadFailure();
    }
    final timestamp = data['acknowledgedAt'];
    if (timestamp is! Timestamp) {
      throw const InvalidSyncPayloadFailure();
    }
    return PushAcknowledged(
      operationId: expectedOperationId,
      resultingRevision: _requiredInt(data, 'resultingRevision'),
      acknowledgedAtUtc: timestamp.toDate().toUtc(),
    );
  }
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

DateTime _systemUtcClock() => DateTime.now().toUtc();
