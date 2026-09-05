import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';

void main() {
  test(
    'process-local evaluation accepts clock precision without changing payload',
    () {
      final milliseconds = DateTime.utc(2026, 9, 5);
      final request = ResearchSyncRequest(
        phase: ResearchSyncPhase.push,
        ownerId: 'owner:synthetic',
        firebaseUid: 'uid',
        collection: SyncCollection.motivationResponses,
        entityId: 'response:synthetic',
        payload: {'answeredAtUtcMs': milliseconds.millisecondsSinceEpoch},
        evaluatedAtUtc: milliseconds.add(const Duration(microseconds: 321)),
      );
      expect(request.evaluatedAtUtc, milliseconds);
      expect(request.payload, {
        'answeredAtUtcMs': milliseconds.millisecondsSinceEpoch,
      });
    },
  );
  SyncEntity entity({int revision = 1, Map<String, Object?>? payload}) =>
      SyncEntity(
        collection: SyncCollection.motivationResponses,
        entityId: 'response:synthetic',
        revision: revision,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: DateTime.utc(2026, 9, 5),
        serverUpdatedAtUtc: DateTime.utc(2026, 9, 5, 1),
        payload:
            payload ??
            {
              'ownerId': 'owner:synthetic',
              'nested': {'a': 1},
            },
      );

  test('only an explicit server-read boundary creates provenance', () {
    final decoded = entity();
    expect(decoded.serverReadProvenance, isNull);
    final trusted = decoded.withServerReadProvenance(firebaseUid: 'uid');
    expect(
      trusted.serverReadProvenance!.matchesEntity(
        firebaseUid: 'uid',
        entity: trusted,
      ),
      isTrue,
    );
    expect(decoded.serverReadProvenance, isNull);
  });

  test('server-read provenance cannot be transplanted to another entity', () {
    final trusted = entity().withServerReadProvenance(firebaseUid: 'uid');
    final proof = trusted.serverReadProvenance!;
    expect(proof.matchesEntity(firebaseUid: 'other', entity: trusted), isFalse);
    expect(
      proof.matchesEntity(firebaseUid: 'uid', entity: entity(revision: 2)),
      isFalse,
    );
    expect(
      proof.matchesPayload(
        firebaseUid: 'uid',
        collection: SyncCollection.motivationResponses,
        entityId: 'different',
        payload: trusted.payload,
      ),
      isFalse,
    );
    expect(
      proof.matchesPayload(
        firebaseUid: 'uid',
        collection: SyncCollection.measurementOpportunities,
        entityId: trusted.entityId,
        payload: trusted.payload,
      ),
      isFalse,
    );
    expect(
      proof.matchesEntity(
        firebaseUid: 'uid',
        entity: entity(payload: {'ownerId': 'other'}),
      ),
      isFalse,
    );
  });

  test(
    'provenance fingerprints nested content, independent of map ordering',
    () {
      final payload = <String, Object?>{
        'ownerId': 'owner:synthetic',
        'nested': <String, Object?>{'a': 1, 'b': 2},
      };
      final trusted = entity(
        payload: payload,
      ).withServerReadProvenance(firebaseUid: 'uid');
      final proof = trusted.serverReadProvenance!;
      expect(
        proof.matchesEntity(
          firebaseUid: 'uid',
          entity: entity(
            payload: {
              'nested': {'b': 2, 'a': 1},
              'ownerId': 'owner:synthetic',
            },
          ),
        ),
        isTrue,
      );
      (payload['nested']! as Map<String, Object?>)['a'] = 9;
      expect(proof.matchesEntity(firebaseUid: 'uid', entity: trusted), isFalse);
    },
  );
}
