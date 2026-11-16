import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  group('SyncCursor', () {
    test('JSON round-trip preserves timestamp and document id', () {
      final cursor = SyncCursor(
        serverUpdatedAtUtc: DateTime.utc(2026, 7, 30, 6, 7, 8, 9, 10),
        documentId: 'word:station',
      );

      final restored = SyncCursor.parse(cursor.toJsonString());

      expect(restored, cursor);
    });

    test('malformed or non-UTC cursor values fail closed', () {
      expect(
        () => SyncCursor.parse('not-json'),
        throwsA(isA<InvalidSyncCursorFailure>()),
      );
      expect(
        () => SyncCursor(
          serverUpdatedAtUtc: DateTime(2026, 7, 30),
          documentId: 'word:station',
        ),
        throwsArgumentError,
      );
      expect(
        () => SyncCursor(
          serverUpdatedAtUtc: DateTime.utc(2026, 7, 30),
          documentId: '  ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('sync entity contracts', () {
    test('push mutation rejects unsupported payload versions', () {
      expect(
        () => PushMutation(
          operationId: 'operation:1',
          firebaseUid: 'uid-a',
          collection: SyncCollection.words,
          entityId: 'word:station',
          operationKind: SyncOperationKind.upsert,
          payloadVersion: 2,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: DateTime.utc(2026, 7, 30),
          payload: const <String, Object?>{'spelling': 'station'},
        ),
        throwsA(isA<UnsupportedSyncSchemaFailure>()),
      );
    });

    test('push mutation accepts only recursively JSON-safe payloads', () {
      expect(
        () => PushMutation(
          operationId: 'operation:1',
          firebaseUid: 'uid-a',
          collection: SyncCollection.words,
          entityId: 'word:station',
          operationKind: SyncOperationKind.upsert,
          payloadVersion: 1,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: DateTime.utc(2026, 7, 30),
          payload: <String, Object?>{'unsupported': Object()},
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });

    test('push mutation can collapse consecutive local revisions', () {
      final mutation = PushMutation(
        operationId: 'operation:3',
        firebaseUid: 'uid-a',
        collection: SyncCollection.words,
        entityId: 'word:station',
        operationKind: SyncOperationKind.upsert,
        payloadVersion: 1,
        baseRevision: 0,
        localRevision: 3,
        clientUpdatedAtUtc: DateTime.utc(2026, 7, 30),
        payload: const <String, Object?>{'spelling': 'station'},
      );

      expect(mutation.baseRevision, 0);
      expect(mutation.localRevision, 3);
    });

    test('push acknowledgement requires UTC time and valid revisions', () {
      expect(
        () => PushAcknowledged(
          operationId: 'operation:1',
          resultingRevision: -1,
          acknowledgedAtUtc: DateTime.utc(2026, 7, 30),
        ),
        throwsArgumentError,
      );
      expect(
        () => PushAcknowledged(
          operationId: 'operation:1',
          resultingRevision: 1,
          acknowledgedAtUtc: DateTime(2026, 7, 30),
        ),
        throwsArgumentError,
      );
    });

    test('pull page rejects a cursor that regresses behind its changes', () {
      final change = SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'category:travel',
        revision: 2,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: DateTime.utc(2026, 7, 30, 1),
        serverUpdatedAtUtc: DateTime.utc(2026, 7, 30, 2),
        payload: const <String, Object?>{'name': 'Travel'},
      );

      expect(
        () => PullPage(
          changes: <SyncEntity>[change],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: DateTime.utc(2026, 7, 30, 1),
            documentId: change.entityId,
          ),
          hasMore: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('privacy-safe failures and policy', () {
    test('failure strings expose only stable codes', () {
      const failures = <SyncFailure>[
        OfflineSyncFailure(),
        UnauthenticatedSyncFailure(),
        PermissionDeniedSyncFailure(),
        InvalidSyncPayloadFailure(),
        QuotaSyncFailure(),
        ProviderUnavailableSyncFailure(),
      ];

      for (final failure in failures) {
        expect(failure.toString(), 'SyncFailure(${failure.code.name})');
        expect(failure.toString(), isNot(contains('token')));
        expect(failure.toString(), isNot(contains('email')));
      }
    });

    test('cloud policy expiration uses an injected UTC clock', () {
      final policy = CloudSyncPolicy(
        enabled: true,
        source: CloudSyncPolicySource.remote,
        fetchedAtUtc: DateTime.utc(2026, 7, 30, 1),
        expiresAtUtc: DateTime.utc(2026, 7, 30, 2),
      );

      expect(policy.isExpiredAt(DateTime.utc(2026, 7, 30, 1, 59)), isFalse);
      expect(policy.isExpiredAt(DateTime.utc(2026, 7, 30, 2)), isTrue);
      expect(
        () => policy.isExpiredAt(DateTime(2026, 7, 30, 2)),
        throwsArgumentError,
      );
    });
  });
}
