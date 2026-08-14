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
    test(
      'payload-version policy is exhaustive and defaults every write to v1',
      () {
        const expected = <SyncCollection, Set<int>>{
          SyncCollection.categories: <int>{1},
          SyncCollection.words: <int>{1},
          SyncCollection.attempts: <int>{1, 2},
          SyncCollection.readingEvents: <int>{1},
          SyncCollection.rewardTransactions: <int>{1},
          SyncCollection.srsStates: <int>{1},
          SyncCollection.achievementUnlocks: <int>{1},
        };

        expect(expected.keys.toSet(), SyncCollection.values.toSet());
        for (final collection in SyncCollection.values) {
          expect(
            collection.supportedPayloadVersions,
            expected[collection],
            reason: collection.name,
          );
          expect(
            const SyncPayloadRollout.productionDefault().writeVersionFor(
              collection,
            ),
            1,
            reason: collection.name,
          );
        }
        expect(
          const SyncPayloadRollout.answerAttemptV2().writeVersionFor(
            SyncCollection.attempts,
          ),
          2,
        );
        expect(
          const SyncPayloadRollout.answerAttemptV2().writeVersionFor(
            SyncCollection.words,
          ),
          1,
        );
      },
    );

    test(
      'attempts accept payload v1 and v2 while legacy collections reject v2',
      () {
        PushMutation mutation(SyncCollection collection, int payloadVersion) =>
            PushMutation(
              operationId: 'operation:${collection.name}:$payloadVersion',
              firebaseUid: 'uid-a',
              collection: collection,
              entityId: '${collection.entityType}:entity',
              operationKind: SyncOperationKind.upsert,
              payloadVersion: payloadVersion,
              baseRevision: 0,
              localRevision: 1,
              clientUpdatedAtUtc: DateTime.utc(2026, 7, 30),
              payload: const <String, Object?>{'value': 'safe'},
            );

        expect(mutation(SyncCollection.attempts, 1).payloadVersion, 1);
        expect(mutation(SyncCollection.attempts, 2).payloadVersion, 2);
        for (final collection in SyncCollection.values.where(
          (value) => value != SyncCollection.attempts,
        )) {
          expect(
            () => mutation(collection, 2),
            throwsA(isA<UnsupportedSyncSchemaFailure>()),
            reason: collection.name,
          );
        }
      },
    );

    test('sync entity rejects unsupported payload versions per collection', () {
      expect(
        () => SyncEntity(
          collection: SyncCollection.words,
          entityId: 'word:station',
          revision: 1,
          isDeleted: false,
          payloadVersion: 2,
          clientUpdatedAtUtc: DateTime.utc(2026, 7, 30),
          serverUpdatedAtUtc: DateTime.utc(2026, 7, 30, 0, 1),
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

    test('pull page cursor equals the final delivered tuple exactly', () {
      final timestamp = DateTime.utc(2026, 7, 30, 2);
      final change = SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'a',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: timestamp,
        serverUpdatedAtUtc: timestamp,
        payload: const <String, Object?>{'name': 'A'},
      );

      expect(
        () => PullPage(
          changes: <SyncEntity>[change],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: timestamp,
            documentId: 'z',
          ),
          hasMore: false,
        ),
        throwsArgumentError,
      );
    });

    test('pull page changes are strictly ordered by cursor tuple', () {
      final timestamp = DateTime.utc(2026, 7, 30, 2);
      final later = SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'z',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: timestamp,
        serverUpdatedAtUtc: timestamp,
        payload: const <String, Object?>{'name': 'Later'},
      );
      final earlier = SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'a',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: timestamp,
        serverUpdatedAtUtc: timestamp,
        payload: const <String, Object?>{'name': 'Earlier'},
      );

      expect(
        () => PullPage(
          changes: <SyncEntity>[later, earlier],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: timestamp,
            documentId: earlier.entityId,
          ),
          hasMore: false,
        ),
        throwsArgumentError,
      );
    });

    test('pull page changes contain unique entity ids', () {
      final firstTimestamp = DateTime.utc(2026, 7, 30, 2);
      final secondTimestamp = firstTimestamp.add(const Duration(seconds: 1));
      SyncEntity change(DateTime timestamp, String name) => SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'category:duplicate',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: timestamp,
        serverUpdatedAtUtc: timestamp,
        payload: <String, Object?>{'name': name},
      );

      expect(
        () => PullPage(
          changes: <SyncEntity>[
            change(firstTimestamp, 'First'),
            change(secondTimestamp, 'Second'),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: secondTimestamp,
            documentId: 'category:duplicate',
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
