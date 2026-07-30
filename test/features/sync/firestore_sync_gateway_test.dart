import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';

void main() {
  group('FirestoreSyncCodec', () {
    final clientUpdatedAt = DateTime.utc(2026, 7, 30, 8, 15);
    final serverUpdatedAt = DateTime.utc(2026, 7, 30, 8, 16);

    test('encodes a mutation with immutable operation linkage', () {
      final mutation = PushMutation(
        operationId: 'operation-1',
        firebaseUid: 'firebase-user-1',
        collection: SyncCollection.categories,
        entityId: 'category-1',
        operationKind: SyncOperationKind.upsert,
        payloadVersion: 1,
        baseRevision: 2,
        localRevision: 4,
        clientUpdatedAtUtc: clientUpdatedAt,
        payload: const <String, Object?>{
          'name': 'Travel',
          'normalizedName': 'travel',
          'sortOrder': 3,
          'isDeleted': false,
          'createdAtUtcMs': 1000,
          'updatedAtUtcMs': 2000,
        },
      );

      final encoded = FirestoreSyncCodec.encodeEntity(
        mutation,
        serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
      );

      expect(encoded['schemaVersion'], 1);
      expect(encoded['entityId'], 'category-1');
      expect(encoded['revision'], 4);
      expect(encoded['lastOperationId'], 'operation-1');
      expect(encoded['payload'], mutation.payload);
      expect(encoded['serverUpdatedAt'], Timestamp.fromDate(serverUpdatedAt));
    });

    test('decodes a word without losing nullable payload fields', () {
      final entity = FirestoreSyncCodec.decodeEntity(
        collection: SyncCollection.words,
        documentId: 'word-1',
        data: <String, Object?>{
          'schemaVersion': 1,
          'entityId': 'word-1',
          'revision': 7,
          'isDeleted': false,
          'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
          'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
          'lastOperationId': 'operation-7',
          'payload': <String, Object?>{
            'categoryId': 'category-1',
            'spelling': 'station',
            'normalizedSpelling': 'station',
            'meaning': 'สถานี',
            'normalizedMeaning': 'สถานี',
            'partOfSpeech': 'noun',
            'cefrLevel': null,
            'source': 'manual',
            'isGlobal': false,
            'isDeleted': false,
            'createdAtUtcMs': 1000,
            'updatedAtUtcMs': 2000,
          },
        },
      );

      expect(entity.entityId, 'word-1');
      expect(entity.revision, 7);
      expect(entity.payload['cefrLevel'], isNull);
      expect(entity.serverUpdatedAtUtc, serverUpdatedAt);
    });

    test('rejects unknown schemas and mismatched document IDs', () {
      final base = <String, Object?>{
        'schemaVersion': 2,
        'entityId': 'category-1',
        'revision': 1,
        'isDeleted': false,
        'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
        'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
        'lastOperationId': 'operation-1',
        'payload': <String, Object?>{'name': 'Travel'},
      };

      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.categories,
          documentId: 'category-1',
          data: base,
        ),
        throwsA(isA<UnsupportedSyncSchemaFailure>()),
      );
      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.categories,
          documentId: 'different-id',
          data: <String, Object?>{...base, 'schemaVersion': 1},
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });

    test('rejects a missing server timestamp', () {
      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.categories,
          documentId: 'category-1',
          data: <String, Object?>{
            'schemaVersion': 1,
            'entityId': 'category-1',
            'revision': 1,
            'isDeleted': false,
            'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
            'serverUpdatedAt': null,
            'lastOperationId': 'operation-1',
            'payload': <String, Object?>{'name': 'Travel'},
          },
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });
  });

  group('FirestoreSyncErrorMapper', () {
    test(
      'maps retry and terminal provider codes without retaining details',
      () {
        expect(
          FirestoreSyncErrorMapper.fromCode('unavailable'),
          isA<ProviderUnavailableSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('deadline-exceeded'),
          isA<ProviderUnavailableSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('resource-exhausted'),
          isA<QuotaSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('permission-denied'),
          isA<PermissionDeniedSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('unauthenticated'),
          isA<UnauthenticatedSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('invalid-argument'),
          isA<InvalidSyncPayloadFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('anything-else').toString(),
          'SyncFailure(providerUnavailable)',
        );
      },
    );
  });
}
