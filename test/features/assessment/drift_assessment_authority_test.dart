import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';

import '../../support/assessment_authority_harness.dart';

void main() {
  late AssessmentAuthorityFixture fixture;
  setUp(() async => fixture = await AssessmentAuthorityFixture.open());
  tearDown(() => fixture.close());

  test(
    'real Ed/P256 authority binds distinct Assessment numeric and string pins without writes',
    () async {
      expect(await fixture.cache.refresh(), isTrue);
      final before = await fixture.study.researchRows();
      final receipt = await fixture.require();
      expect(receipt.mapping.instrumentId, 'synthetic-assessment-instrument');
      expect(receipt.mapping.instrumentVersion, 'artifact-v2');
      expect(receipt.mapping.instrumentRevision, 41);
      expect(
        receipt.operation.permit.instrumentId,
        fixture.definition.instrumentId,
      );
      expect(receipt.operation.permit.instrumentRevision, 41);
      expect(receipt.assignment.experimentId, 'synthetic-experiment');
      expect(receipt.assignment.experimentVersion, 2);
      expect(receipt.participationPermitId, 'synthetic-participation');
      expect(receipt.participationPermitRevision, 1);
      expect(
        receipt.participationPermitPayloadSha256,
        participationPermit().payloadSha256,
      );
      expect(receipt.verifiedAtUtc, participationStart);
      expect(
        receipt.validUntilUtc,
        participationStart.add(const Duration(minutes: 10)),
      );
      expect(await fixture.study.researchRows(), before);
      expect(fixture.gateway.calls, 1);
      expect(fixture.gateway.transactionCalls, [false]);
    },
  );

  test('no snapshot denies without gateway IO or research writes', () async {
    final before = await fixture.study.researchRows();
    await expectLater(() => fixture.require(), throwsStateError);
    expect(fixture.gateway.calls, 0);
    expect(await fixture.study.researchRows(), before);
  });

  for (final kind in ['Ed', 'P256', 'Motivation grant']) {
    test('real verification rejects $kind packet for Assessment', () async {
      fixture.gateway.corruptEd = kind == 'Ed';
      fixture.gateway.corruptP256 = kind == 'P256';
      fixture.gateway.motivationGrant = kind == 'Motivation grant';
      expect(await fixture.cache.refresh(), isFalse);
      await expectLater(() => fixture.require(), throwsStateError);
    });
  }

  for (final kind in ['operation', 'receipt']) {
    test(
      'fresh signed $kind revocation denies an earlier allowed snapshot',
      () async {
        expect(await fixture.cache.refresh(), isTrue);
        await fixture.require();
        fixture.gateway.revision = 2;
        fixture.gateway.revoked = kind == 'operation';
        fixture.gateway.receiptActive = kind != 'receipt';
        expect(await fixture.cache.refresh(), isTrue);
        final before = await fixture.study.researchRows();
        await expectLater(() => fixture.require(), throwsStateError);
        expect(await fixture.study.researchRows(), before);
      },
    );
  }

  for (final update in <String, String>{
    'actual UID':
        "UPDATE local_owners SET firebase_uid = 'changed-uid' WHERE id = 'owner-a'",
    'withdrawn consent':
        "UPDATE research_consents SET consent_state = 'declined', withdrawn_at_utc_ms = decided_at_utc_ms WHERE owner_id = 'owner-a'",
    'consent decision':
        "UPDATE research_consents SET decided_at_utc_ms = decided_at_utc_ms + 1 WHERE owner_id = 'owner-a'",
    'assignment':
        "UPDATE experiment_assignments SET cohort = 'adventure' WHERE owner_id = 'owner-a'",
    'local signed document':
        "UPDATE research_participation_permits SET age_band_code = 'tampered' WHERE owner_id = 'owner-a'",
    'local permit revision':
        "UPDATE research_participation_permits SET local_revision = 2, cloud_revision = 2 WHERE owner_id = 'owner-a'",
  }.entries) {
    test(
      '${update.key} changed after refresh cannot use stale authority',
      () async {
        expect(await fixture.cache.refresh(), isTrue);
        await fixture.study.database.customStatement(update.value);
        final before = await fixture.study.researchRows();
        await expectLater(() => fixture.require(), throwsStateError);
        expect(await fixture.study.researchRows(), before);
      },
    );
  }

  test('inactive owner, auth ABA, expiry and deletion fence deny', () async {
    expect(await fixture.cache.refresh(), isTrue);
    final original = fixture.scope!;
    fixture.scope = fixture.scopeFor(
      owner: 'owner-b',
      uid: 'uid-b',
      generation: 2,
    );
    fixture.scope = fixture.scopeFor(generation: 3);
    await expectLater(
      () => fixture.require(expectedScope: original),
      throwsStateError,
    );
    fixture.scope = original;
    await fixture.study.switchOwner();
    await expectLater(() => fixture.require(), throwsA(anything));
    await fixture.study.database.customStatement(
      "UPDATE local_owners SET is_active = CASE WHEN id = 'owner-a' THEN 1 ELSE 0 END",
    );
    fixture.advance(const Duration(minutes: 11));
    await expectLater(() => fixture.require(), throwsStateError);
    expect(await fixture.cache.refresh(), isTrue);
    await fixture.study.participation.ownerWrites.beginDeletion(
      ownerId: 'owner-a',
      firebaseUid: 'uid-a',
      idempotencyKey: 'synthetic-assessment-delete',
    );
    await expectLater(() => fixture.require(), throwsA(anything));
  });

  test(
    'stored numeric assignment and original P256 pins cannot rotate',
    () async {
      expect(await fixture.cache.refresh(), isTrue);
      final view = await fixture.study.baseline();
      for (final run in <AssessmentRun>[
        fixture.run(cycleId: view.run!.id, assignmentRevision: 12),
        fixture.run(cycleId: view.run!.id, protocolRevision: 6),
        fixture.run(cycleId: view.run!.id, permitHash: 'b' * 64),
        fixture.run(cycleId: view.run!.id, permitRevision: 2),
      ]) {
        await expectLater(
          () => fixture.require(pinnedRun: run),
          throwsStateError,
        );
      }
    },
  );

  test(
    'receipt expiry caps the snapshot and crossing it during final SQL denies',
    () async {
      fixture.gateway.receiptLifetime = const Duration(seconds: 1);
      expect(await fixture.cache.refresh(), isTrue);
      final receipt = await fixture.require();
      expect(
        receipt.validUntilUtc,
        participationStart.add(const Duration(seconds: 1)),
      );
      final hold = _HeldAssignmentRead(atRead: 2);
      final before = await fixture.study.researchRows();
      final check = fixture.study.database.runWithInterceptor(
        () => fixture.require(),
        interceptor: hold,
      );
      final denied = expectLater(check, throwsStateError);
      await hold.reached.future;
      fixture.advance(const Duration(seconds: 2));
      hold.release.complete();
      await denied;
      expect(await fixture.study.researchRows(), before);
    },
  );

  test(
    'same-scope revoked refresh while a real SQL read waits invalidates the full check',
    () async {
      expect(await fixture.cache.refresh(), isTrue);
      final hold = _HeldAssignmentRead();
      final check = fixture.study.database.runWithInterceptor(
        () => fixture.require(),
        interceptor: hold,
      );
      final denied = expectLater(check, throwsStateError);
      await hold.reached.future;
      final previousGeneration = fixture.cache.readGeneration;
      fixture.gateway.revision = 2;
      fixture.gateway.revoked = true;
      final refresh = fixture.cache.refresh();
      expect(fixture.cache.readGeneration, greaterThan(previousGeneration));
      hold.release.complete();
      await denied;
      expect(await refresh, isTrue);
      await expectLater(() => fixture.require(), throwsStateError);
      expect(fixture.gateway.transactionCalls, everyElement(isFalse));
    },
  );
}

final class _HeldAssignmentRead extends QueryInterceptor {
  _HeldAssignmentRead({this.atRead = 1});
  final int atRead;
  final reached = Completer<void>();
  final release = Completer<void>();
  int reads = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.startsWith('SELECT * FROM experiment_assignments') &&
        ++reads == atRead) {
      reached.complete();
      await release.future;
    }
    return rows;
  }
}
