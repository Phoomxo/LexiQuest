import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_store.dart';

import '../../support/motivation_research_fixture.dart';

void main() {
  test(
    'withdrawal before enqueue survives file reopen, reaccept, retry and ACK',
    () async {
      const owner = 'owner:a';
      const uid = 'synthetic-file-research-uid';
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-denial-reopen-',
      );
      final temporaryRoot = directory.resolveSymbolicLinksSync();
      final file = File('$temporaryRoot${Platform.pathSeparator}denial.sqlite');
      final fixture = MotivationResearchFixture();
      var fixtureClosed = false;
      AppDatabase? opened;
      try {
        await fixture
            .initialize(); // Genuine synthetic permit; no run or answers.
        await (fixture.database.update(fixture.database.localOwners)
              ..where((row) => row.id.equals(owner)))
            .write(const LocalOwnersCompanion(firebaseUid: Value(uid)));
        var now = fixture.now;
        final consent = DriftResearchConsentRepository(fixture.database);
        await consent.decide(
          ownerId: owner,
          version: 1,
          accepted: false,
          decidedAtUtc: now,
        );
        final operationId =
            'research-sync:${ResearchSyncContract.fingerprint({
              'collection': 'research_withdrawals',
              'id': 'permit:a',
              'payload': {'permitId': 'permit:a', 'ownerId': owner},
            })}:1';
        final original = await fixture.database
            .select(fixture.database.outboxOperations)
            .getSingle();
        expect(original.operationId, operationId);
        now = now.add(const Duration(seconds: 1));
        await consent.decide(
          ownerId: owner,
          version: 1,
          accepted: true,
          decidedAtUtc: now,
        );
        // VACUUM INTO copies the real schema and immutable signed fixture without
        // teaching the shared in-memory fixture a second persistence interface.
        // The target is bound as a SQL parameter, never interpolated into SQL.
        await fixture.database.customStatement('VACUUM INTO ?', [file.path]);
        await fixture.database.close();
        fixtureClosed = true;
        expect(file.existsSync(), isTrue);

        final first = AppDatabase(NativeDatabase(file));
        opened = first;
        expect(
          (await first.select(first.researchConsents).getSingle()).consentState,
          'accepted',
        );
        expect(
          (await first.select(first.researchParticipationPermits).getSingle())
              .payloadSha256,
          fixture.permit().payloadSha256,
        );
        expect(
          (await first.select(first.outboxOperations).getSingle()).toJson(),
          original.toJson(),
        );
        final gate = DriftOwnerOperationGate(first);
        expect(
          await gate.tryAcquire(
            token: 'file-first',
            nowUtc: now,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final store = DriftSyncStore(
          first,
          researchMeasurementRollout:
              const ResearchMeasurementSyncRollout.localEmulatorV1(
                deployedRulesRevision: researchMeasurementV1RulesRevision,
              ),
        ); // No authorizer: only the durable deny operation is permitted.
        Future<List<ClaimedSyncOperation>> claim() => store.claimPending(
          ownerId: owner,
          firebaseUid: uid,
          limit: 5,
          leaseToken: 'file-claim',
          ownerGateToken: 'file-first',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: now,
        );
        final initial = (await claim()).single;
        expect(initial.mutation.operationId, operationId);
        expect(initial.mutation.payload, {
          'permitId': 'permit:a',
          'ownerId': owner,
        });
        expect(
          await store.beginAttempt(
            claim: initial,
            ownerGateToken: 'file-first',
            nowUtc: now,
          ),
          isNotNull,
        );
        final retryAt = now.add(const Duration(seconds: 2));
        expect(
          await store.markRetry(
            operationId: initial.localOperationId,
            leaseToken: initial.leaseToken,
            ownerGateToken: 'file-first',
            nowUtc: now,
            nextAttemptAtUtc: retryAt,
            failure: const OfflineSyncFailure(),
          ),
          isTrue,
        );
        expect(await claim(), isEmpty);
        now = retryAt;
        final retry = (await claim()).single;
        expect(retry.localOperationId, initial.localOperationId);
        expect(retry.mutation.operationId, initial.mutation.operationId);
        expect(retry.mutation.payload, initial.mutation.payload);
        final attempt = (await store.beginAttempt(
          claim: retry,
          ownerGateToken: 'file-first',
          nowUtc: now,
        ))!;
        expect(
          await store.acknowledge(
            operationId: attempt.localOperationId,
            leaseToken: attempt.leaseToken,
            ownerGateToken: 'file-first',
            nowUtc: now,
            acknowledgement: PushAcknowledged(
              operationId: attempt.localOperationId,
              resultingRevision: 1,
              acknowledgedAtUtc: now,
            ),
          ),
          isTrue,
        );
        final acknowledged = await first
            .select(first.outboxOperations)
            .getSingle();
        expect(acknowledged.state, 'acknowledged');
        expect(acknowledged.attemptCount, 2);
        await gate.release(token: 'file-first');
        await first.close();
        opened = null;

        final second = AppDatabase(NativeDatabase(file));
        opened = second;
        now = now.add(const Duration(seconds: 1));
        final secondGate = DriftOwnerOperationGate(second);
        expect(
          await secondGate.tryAcquire(
            token: 'file-second',
            nowUtc: now,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final restarted = DriftSyncStore(
          second,
          researchMeasurementRollout:
              const ResearchMeasurementSyncRollout.localEmulatorV1(
                deployedRulesRevision: researchMeasurementV1RulesRevision,
              ),
        );
        expect(
          await restarted.enqueueResearchChanges(
            ownerId: owner,
            firebaseUid: uid,
            ownerGateToken: 'file-second',
            nowUtc: now,
          ),
          0,
        );
        expect(
          await restarted.claimPending(
            ownerId: owner,
            firebaseUid: uid,
            limit: 5,
            leaseToken: 'file-second-claim',
            ownerGateToken: 'file-second',
            leaseDuration: const Duration(minutes: 1),
            nowUtc: now,
          ),
          isEmpty,
        );
        expect(
          (await second.select(second.outboxOperations).getSingle()).toJson(),
          acknowledged.toJson(),
        );
        expect(
          (await second.select(second.researchConsents).getSingle())
              .consentState,
          'accepted',
        );
        expect(
          await second.select(second.motivationMeasurementRuns).get(),
          isEmpty,
        );
        await secondGate.release(token: 'file-second');
      } finally {
        if (opened != null) await opened.close();
        if (!fixtureClosed) await fixture.database.close();
        // Delete only the exact directory this test created, after every DB closes.
        if (directory.existsSync()) {
          if (directory.resolveSymbolicLinksSync() != temporaryRoot ||
              file.parent.resolveSymbolicLinksSync() != temporaryRoot) {
            throw StateError('Temporary database cleanup path changed');
          }
          await directory.delete(recursive: true);
        }
      }
    },
  );
}
