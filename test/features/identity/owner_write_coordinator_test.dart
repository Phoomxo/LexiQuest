import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';

import '../../support/experiment_assignment_fixture.dart';
import '../../support/measurement_opportunity_fixture.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

final _now = DateTime.utc(2026, 10, 28, 12);
const _owner = 'synthetic-private-owner-a';
const _uid = 'synthetic-private-firebase-a';
const _key = 'delete:00000000-0000-4000-8000-000000000001';

void main() {
  group('owner write admission', () {
    late AppDatabase database;
    late DriftOwnerWriteCoordinator coordinator;
    var nonceSequence = 0;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await _seedOwners(database);
      nonceSequence = 0;
      coordinator = DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => _now,
        nonceGenerator: () => 'synthetic-private-nonce-${nonceSequence++}',
      );
    });

    tearDown(() => database.close());

    test(
      'commits the callback result for the canonical active owner',
      () async {
        final result = await coordinator.writeForActiveOwner(
          expectedOwnerId: _owner,
          write: () async {
            await _insertResearchArtifacts(database);
            return 'admitted';
          },
        );

        expect(result, 'admitted');
        await _expectResearchCounts(database, 1);
        expect(await coordinator.inspect(), isNull);
      },
    );

    test('rechecks the owner after asynchronous authorization', () async {
      final authorized = Completer<void>();
      final admission = authorized.future.then(
        (_) => coordinator.writeForActiveOwner(
          expectedOwnerId: _owner,
          write: () => _insertResearchArtifacts(database),
        ),
      );
      final rejected = expectLater(admission, _failure());
      await database.customStatement(
        'UPDATE local_owners SET is_active = (id = ?)',
        ['owner-b'],
      );
      authorized.complete();

      await rejected;
      await _expectResearchCounts(database, 0);
    });

    for (final activeCount in [0, 2]) {
      test(
        'rejects $activeCount active owners before callback writes',
        () async {
          await database.customStatement(
            'UPDATE local_owners SET is_active = ?',
            [activeCount == 0 ? 0 : 1],
          );

          await expectLater(
            coordinator.writeForActiveOwner(
              expectedOwnerId: _owner,
              write: () => _insertResearchArtifacts(database),
            ),
            _failure(),
          );
          await _expectResearchCounts(database, 0);
        },
      );
    }

    test('rolls back all callback artifacts when the callback fails', () async {
      final failure = StateError('synthetic admission failure');

      await expectLater(
        coordinator.writeForActiveOwner<void>(
          expectedOwnerId: _owner,
          write: () async {
            await _insertResearchArtifacts(database);
            throw failure;
          },
        ),
        throwsA(same(failure)),
      );
      await _expectResearchCounts(database, 0);
    });

    test('late authorization cannot create any research artifact', () async {
      final authorized = Completer<void>();
      final admission = authorized.future.then(
        (_) => coordinator.writeForActiveOwner(
          expectedOwnerId: _owner,
          write: () => _insertResearchArtifacts(database),
        ),
      );
      final rejected = expectLater(admission, _failure());
      await _begin(coordinator);
      authorized.complete();

      await rejected;
      await _expectResearchCounts(database, 0);
      await coordinator.requireOwnerUnfenced('owner-b');
      await _ordinaryWrite(database);
    });

    test('deletion requires the active owner and exact Firebase UID', () async {
      for (final identity in [(_owner, 'wrong-uid'), ('owner-b', 'uid-b')]) {
        await expectLater(
          coordinator.beginDeletion(
            ownerId: identity.$1,
            firebaseUid: identity.$2,
            idempotencyKey: _key,
          ),
          _failure(),
        );
        expect(await coordinator.inspect(), isNull);
      }
    });

    test('pre-cloud storage contains no raw tuple or nonce', () async {
      final token = await _begin(coordinator);
      await _expectPreCloudStorage(database);
      expect(
        (await coordinator.inspect())?.phase,
        DeletionIntentPhase.preparing,
      );

      await coordinator.markPending(token);

      await _expectPreCloudStorage(database);
      expect(
        (await coordinator.inspect())?.phase,
        DeletionIntentPhase.pendingCloud,
      );
      expect(await coordinator.abortPreparing(token), isFalse);
    });

    test(
      'an aborted actor cannot advance a later attempt with the same key',
      () async {
        final stale = await _begin(coordinator);
        expect(await coordinator.abortPreparing(stale), isTrue);
        final current = await _begin(coordinator);

        expect(await coordinator.abortPreparing(stale), isFalse);
        await expectLater(coordinator.markPending(stale), _failure());
        await expectLater(coordinator.markCloud(stale, _cloud()), _failure());
        await expectLater(
          coordinator.markLocal(
            stale,
            _cloud().durableMarker(),
            LocalDeletionReceipt(
              deletedOwnerId: _owner,
              newGuestOwnerId: _replacementGuest,
              completedAtUtc: _now,
            ),
          ),
          _failure(),
        );
        await expectLater(coordinator.clearCompleted(stale), _failure());
        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.preparing,
        );
        await coordinator.markPending(current);
        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.pendingCloud,
        );
      },
    );

    test('a repeated begin preserves the current attempt', () async {
      final first = await _begin(coordinator);
      final replay = await _begin(coordinator);
      await coordinator.markPending(replay);
      await coordinator.markPending(first);

      expect(
        (await coordinator.inspect())?.phase,
        DeletionIntentPhase.pendingCloud,
      );
      await expectLater(
        coordinator.beginDeletion(
          ownerId: _owner,
          firebaseUid: _uid,
          idempotencyKey: 'another-operation',
        ),
        _failure(),
      );
    });

    test(
      'a pending attempt cannot be aborted or cleared as completed',
      () async {
        final token = await _begin(coordinator);
        await coordinator.markPending(token);

        expect(await coordinator.abortPreparing(token), isFalse);
        await expectLater(coordinator.clearCompleted(token), _failure());
        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.pendingCloud,
        );
      },
    );

    test(
      'cloud proof requires the pending phase and matching operation',
      () async {
        final token = await _begin(coordinator);
        await expectLater(coordinator.markCloud(token, _cloud()), _failure());
        await coordinator.markPending(token);
        for (final receipt in [
          _cloud(ownerId: 'owner-b'),
          _cloud(firebaseUid: 'uid-b'),
          _cloud(idempotencyKey: 'another-operation'),
          _cloud(receiptId: ''),
        ]) {
          await expectLater(coordinator.markCloud(token, receipt), _failure());
        }

        await coordinator.markCloud(token, _cloud());
        await coordinator.markCloud(token, _cloud().durableMarker());
        final state = await coordinator.inspect();
        expect(state?.phase, DeletionIntentPhase.cloudConfirmed);
        expect(
          state?.cloudReceipt?.idempotencyKey,
          durableAccountDeletionBinding(_key),
        );
        final serialized = jsonEncode(await _intentRow(database));
        expect(serialized, isNot(contains(_key)));
      },
    );

    test(
      'cloud proof fences the original and exact replacement guest',
      () async {
        final token = await _begin(coordinator);
        await coordinator.markPending(token);
        await coordinator.markCloud(token, _cloud());

        await expectLater(coordinator.requireOwnerUnfenced(_owner), _failure());
        await expectLater(
          coordinator.requireOwnerUnfenced(_replacementGuest),
          _failure(),
        );
        await coordinator.requireOwnerUnfenced('owner-b');
        await _ordinaryWrite(database);
      },
    );

    test(
      'local completion requires matching committed database purge proof',
      () async {
        final token = await _begin(coordinator);
        await coordinator.markPending(token);
        final cloud = _cloud().durableMarker();
        await coordinator.markCloud(token, cloud);
        final fabricated = LocalDeletionReceipt(
          deletedOwnerId: _owner,
          newGuestOwnerId: _replacementGuest,
          completedAtUtc: _now,
        );

        await expectLater(
          coordinator.markLocal(token, cloud, fabricated),
          _failure(),
        );
        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.cloudConfirmed,
        );
        final local = await _purge(database, cloud);
        await expectLater(
          coordinator.markLocal(
            token,
            cloud,
            LocalDeletionReceipt(
              deletedOwnerId: _owner,
              newGuestOwnerId: 'another-guest',
              completedAtUtc: _now,
            ),
          ),
          _failure(),
        );

        await coordinator.markLocal(token, cloud, local);
        await coordinator.markLocal(token, cloud, local);
        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.localCompleted,
        );
        await expectLater(
          coordinator.writeForActiveOwner(
            expectedOwnerId: local.newGuestOwnerId,
            write: () async => 'must remain fenced until journal cleanup',
          ),
          _failure(),
        );
        await coordinator.clearCompleted(token);
        expect(await coordinator.inspect(), isNull);
        expect(
          await coordinator.writeForActiveOwner(
            expectedOwnerId: local.newGuestOwnerId,
            write: () async => 'replacement admitted',
          ),
          'replacement admitted',
        );
        await expectLater(coordinator.markPending(token), _failure());
        expect(await coordinator.inspect(), isNull);
      },
    );

    for (final table in [
      'motivation_measurement_runs',
      'motivation_responses',
      'measurement_opportunities',
    ]) {
      test('purge proof rejects a residual $table fact', () async {
        await _insertResearchArtifacts(database);
        final retained =
            (await database.customSelect('SELECT * FROM $table').getSingle())
                .data;
        final token = await _begin(coordinator);
        await coordinator.markPending(token);
        final cloud = _cloud().durableMarker();
        await coordinator.markCloud(token, cloud);
        final local = await _purge(database, cloud);

        // Reproduce a legacy corrupt orphan after an otherwise complete purge.
        await database.customStatement('PRAGMA foreign_keys = OFF');
        await database.customStatement(
          'INSERT INTO $table (${retained.keys.join(', ')}) '
          'VALUES (${List.filled(retained.length, '?').join(', ')})',
          retained.values.toList(),
        );
        await database.customStatement('PRAGMA foreign_keys = ON');

        await expectLater(
          coordinator.markLocal(token, cloud, local),
          _failure(),
        );
        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.cloudConfirmed,
        );
        await expectLater(coordinator.clearCompleted(token), _failure());

        await database.customStatement('DELETE FROM $table');
        await coordinator.markLocal(token, cloud, local);
        await coordinator.clearCompleted(token);
        expect(await coordinator.inspect(), isNull);
      });
    }

    test('a stale completion cannot clear a later owner operation', () async {
      final stale = await _begin(coordinator);
      await coordinator.markPending(stale);
      final cloud = _cloud().durableMarker();
      await coordinator.markCloud(stale, cloud);
      await coordinator.markLocal(stale, cloud, await _purge(database, cloud));
      await coordinator.clearCompleted(stale);
      await database.customStatement(
        'UPDATE local_owners SET is_active = (id = ?)',
        ['owner-b'],
      );
      final current = await coordinator.beginDeletion(
        ownerId: 'owner-b',
        firebaseUid: 'uid-b',
        idempotencyKey: 'synthetic-second-operation',
      );

      await expectLater(coordinator.clearCompleted(stale), _failure());
      await expectLater(coordinator.markCloud(stale, cloud), _failure());
      await coordinator.markPending(current);
      await expectLater(
        coordinator.requireOwnerUnfenced('owner-b'),
        _failure(),
      );
    });

    test(
      'unbound recovery uncertainty blocks coordinated writes only',
      () async {
        await coordinator.preserveRecoveryUncertainty();
        await coordinator.preserveRecoveryUncertainty();

        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.recoveryUncertain,
        );
        for (final owner in [_owner, 'owner-b', 'unknown-owner']) {
          await expectLater(
            coordinator.requireOwnerUnfenced(owner),
            _failure(),
          );
        }
        await expectLater(_begin(coordinator), _failure());
        await expectLater(
          coordinator.writeForActiveOwner(
            expectedOwnerId: _owner,
            write: () => _insertResearchArtifacts(database),
          ),
          _failure(),
        );
        await _expectResearchCounts(database, 0);
        await _ordinaryWrite(database);
      },
    );

    test(
      'uncertain pending-journal outcomes make preparation irrevocable',
      () async {
        final token = await _begin(coordinator);
        await coordinator.preserveRecoveryUncertainty();

        expect(await coordinator.abortPreparing(token), isFalse);
        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.pendingCloud,
        );
        await coordinator.markCloud(token, _cloud());
      },
    );

    test(
      'recovery uncertainty retains verified cloud and local receipts',
      () async {
        final token = await _begin(coordinator);
        await coordinator.markPending(token);
        final cloud = _cloud().durableMarker();
        await coordinator.markCloud(token, cloud);
        await coordinator.preserveRecoveryUncertainty();
        var state = await coordinator.inspect();
        expect(state?.phase, DeletionIntentPhase.cloudConfirmed);
        expect(state?.cloudReceipt?.receiptId, cloud.receiptId);
        final local = await _purge(database, cloud);
        await coordinator.markLocal(token, cloud, local);
        await coordinator.preserveRecoveryUncertainty();

        state = await coordinator.inspect();
        expect(state?.phase, DeletionIntentPhase.localCompleted);
        expect(state?.cloudReceipt?.receiptId, cloud.receiptId);
        expect(state?.localReceipt?.newGuestOwnerId, local.newGuestOwnerId);
      },
    );

    test(
      'adopts a legacy pending journal and keeps only operation bindings',
      () async {
        final recovered = await coordinator.adoptRecovery(
          AccountDeletionJournalEntry(
            ownerId: _owner,
            firebaseUid: _uid,
            idempotencyKey: _key,
          ),
        );
        expect(recovered.phase, DeletionIntentPhase.pendingCloud);
        expect(
          recovered.casToken?.matchesOperation(
            ownerId: _owner,
            firebaseUid: _uid,
            idempotencyKey: _key,
          ),
          isTrue,
        );
        await _expectPreCloudStorage(database);
        await expectLater(coordinator.requireOwnerUnfenced(_owner), _failure());
      },
    );

    test('legacy pending recovery rejects a different active owner', () async {
      await database.customStatement(
        'UPDATE local_owners SET is_active = (id = ?)',
        ['owner-b'],
      );
      await expectLater(
        coordinator.adoptRecovery(
          AccountDeletionJournalEntry(
            ownerId: _owner,
            firebaseUid: _uid,
            idempotencyKey: _key,
          ),
        ),
        _failure(),
      );
      expect(await coordinator.inspect(), isNull);
    });

    test(
      'adopts cloud proof after SQL purge without inventing secret-purge success',
      () async {
        final cloud = _cloud().durableMarker();
        final local = await _purge(database, cloud);
        final recovered = await coordinator.adoptRecovery(
          AccountDeletionJournalEntry(cloudReceipt: cloud),
        );
        expect(recovered.phase, DeletionIntentPhase.cloudConfirmed);
        expect(recovered.localReceipt, isNull);
        await expectLater(
          coordinator.requireOwnerUnfenced(local.newGuestOwnerId),
          _failure(),
        );
        await expectLater(
          coordinator.clearCompleted(recovered.casToken!),
          _failure(),
        );
      },
    );

    test(
      'legacy completed receipt needs committed purge proof before clearing',
      () async {
        final cloud = _cloud().durableMarker();
        final fabricated = LocalDeletionReceipt(
          deletedOwnerId: _owner,
          newGuestOwnerId: _replacementGuest,
          completedAtUtc: _now,
        );
        await expectLater(
          coordinator.adoptRecovery(
            AccountDeletionJournalEntry(
              cloudReceipt: cloud,
              localReceipt: fabricated,
            ),
          ),
          _failure(),
        );
        expect(await coordinator.inspect(), isNull);
        final local = await _purge(database, cloud);
        final recovered = await coordinator.adoptRecovery(
          AccountDeletionJournalEntry(cloudReceipt: cloud, localReceipt: local),
        );
        expect(recovered.phase, DeletionIntentPhase.localCompleted);
        await coordinator.clearCompleted(recovered.casToken!);
        await coordinator.requireOwnerUnfenced(local.newGuestOwnerId);
      },
    );

    test(
      'recovery keeps the nonce and exact saved completion receipt',
      () async {
        final token = await _begin(coordinator);
        await coordinator.markPending(token);
        final cloud = _cloud().durableMarker();
        await coordinator.markCloud(token, cloud);
        final local = await _purge(database, cloud);
        final exact = LocalDeletionReceipt(
          deletedOwnerId: local.deletedOwnerId,
          newGuestOwnerId: local.newGuestOwnerId,
          completedAtUtc: local.completedAtUtc.add(
            const Duration(microseconds: 321),
          ),
        );
        await coordinator.markLocal(token, cloud, exact);
        final recovered = await coordinator.adoptRecovery(
          AccountDeletionJournalEntry(cloudReceipt: cloud),
        );
        expect(recovered.casToken?.sameAttempt(token), isTrue);
        expect(recovered.localReceipt?.completedAtUtc, exact.completedAtUtc);
        await coordinator.clearCompleted(token);
      },
    );

    test(
      'recovery cannot replace another operation or an unbound uncertainty',
      () async {
        final token = await _begin(coordinator);
        await expectLater(
          coordinator.adoptRecovery(
            AccountDeletionJournalEntry(
              cloudReceipt: _cloud(idempotencyKey: 'another-operation'),
            ),
          ),
          _failure(),
        );
        expect(
          (await coordinator.inspect())?.casToken?.sameAttempt(token),
          isTrue,
        );
        await coordinator.abortPreparing(token);
        await coordinator.preserveRecoveryUncertainty();
        await expectLater(
          coordinator.adoptRecovery(
            AccountDeletionJournalEntry(cloudReceipt: _cloud()),
          ),
          _failure(),
        );
        expect(
          (await coordinator.inspect())?.phase,
          DeletionIntentPhase.recoveryUncertain,
        );
      },
    );

    test('unrelated runtime flags do not become deletion fences', () async {
      await database.customStatement(
        'INSERT INTO runtime_flags '
        '(key, bool_value, source, updated_at_utc_ms, expires_at_utc_ms) '
        'VALUES (?, 1, ?, 1, NULL)',
        ['unrelated-synthetic-setting', 'not-json'],
      );

      expect(await coordinator.inspect(), isNull);
      await coordinator.requireOwnerUnfenced(_owner);
      await coordinator.writeForActiveOwner(
        expectedOwnerId: _owner,
        write: () => _insertResearchArtifacts(database),
      );
      await _expectResearchCounts(database, 1);
    });
  });

  group('persistent independent SQLite connections', () {
    late _FileDatabases fixture;
    var clock = _now;

    setUp(() async {
      clock = _now;
      fixture = await _FileDatabases.open();
    });

    tearDown(() => fixture.close());

    DriftOwnerWriteCoordinator coordinator(
      AppDatabase database,
      String nonce,
    ) => DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => clock,
      nonceGenerator: () => nonce,
    );

    for (final phase in [
      DeletionIntentPhase.preparing,
      DeletionIntentPhase.pendingCloud,
    ]) {
      test('$phase survives other connections, restart, and years', () async {
        final first = coordinator(fixture.first, 'synthetic-nonce-a');
        final token = await _begin(first);
        if (phase == DeletionIntentPhase.pendingCloud) {
          await first.markPending(token);
        }
        clock = DateTime.utc(2040, 1, 1);
        final second = coordinator(fixture.second, 'synthetic-nonce-b');
        await expectLater(second.requireOwnerUnfenced(_owner), _failure());
        await fixture.reopenFirst();
        final reopened = coordinator(fixture.first, 'synthetic-nonce-c');

        expect((await reopened.inspect())?.phase, phase);
        await expectLater(reopened.requireOwnerUnfenced(_owner), _failure());
        expect((await _intentRow(fixture.first))['expires_at_utc_ms'], isNull);
        await reopened.requireOwnerUnfenced('owner-b');
        if (phase == DeletionIntentPhase.pendingCloud) {
          expect(await reopened.abortPreparing(token), isFalse);
        }
      });
    }

    test(
      'cloud and local proof survive reopening before journal cleanup',
      () async {
        var current = coordinator(fixture.first, 'synthetic-nonce-a');
        final token = await _begin(current);
        final cloud = _cloud().durableMarker();
        await current.markPending(token);
        await current.markCloud(token, cloud);
        await fixture.reopenFirst();
        current = coordinator(fixture.first, 'synthetic-nonce-b');
        expect(
          (await current.inspect())?.cloudReceipt?.receiptId,
          cloud.receiptId,
        );
        await expectLater(
          current.requireOwnerUnfenced(_replacementGuest),
          _failure(),
        );
        final local = await _purge(fixture.first, cloud);
        await current.markLocal(token, cloud, local);
        await fixture.reopenFirst();
        current = coordinator(fixture.first, 'synthetic-nonce-c');

        final completed = await current.inspect();
        expect(completed?.phase, DeletionIntentPhase.localCompleted);
        expect(completed?.localReceipt?.newGuestOwnerId, local.newGuestOwnerId);
        await expectLater(
          current.requireOwnerUnfenced(_replacementGuest),
          _failure(),
        );
        await current.clearCompleted(token);
        expect(await current.inspect(), isNull);
      },
    );

    test(
      'restart recovery needs only the stored CAS token and journal tuple',
      () async {
        await () async {
          final original = coordinator(fixture.first, 'synthetic-nonce-a');
          final originalToken = await _begin(original);
          await original.markPending(originalToken);
        }();
        await fixture.reopenFirst();
        final recovered = coordinator(fixture.first, 'synthetic-nonce-b');
        final token = (await recovered.inspect())?.casToken;
        expect(token, isNotNull);
        expect(
          token!.matchesOperation(
            ownerId: _owner,
            firebaseUid: _uid,
            idempotencyKey: _key,
          ),
          isTrue,
        );
        expect(
          token.matchesOperation(
            ownerId: _owner,
            firebaseUid: _uid,
            idempotencyKey: durableAccountDeletionBinding(_key),
          ),
          isTrue,
        );
        expect(
          token.matchesOperation(
            ownerId: 'owner-b',
            firebaseUid: _uid,
            idempotencyKey: _key,
          ),
          isFalse,
        );
        expect(
          token.matchesOperation(
            ownerId: _owner,
            firebaseUid: 'another-uid',
            idempotencyKey: _key,
          ),
          isFalse,
        );
        expect(
          token.matchesOperation(
            ownerId: _owner,
            firebaseUid: _uid,
            idempotencyKey: 'another-operation',
          ),
          isFalse,
        );

        final cloud = _cloud().durableMarker();
        await recovered.markCloud(token, cloud);
        await recovered.markLocal(
          token,
          cloud,
          await _purge(fixture.first, cloud),
        );
        await recovered.clearCompleted(token);
        expect(await recovered.inspect(), isNull);
      },
    );

    test('unbound uncertainty survives restart without an expiry', () async {
      await coordinator(
        fixture.first,
        'synthetic-nonce-a',
      ).preserveRecoveryUncertainty();
      await fixture.reopenFirst();
      clock = DateTime.utc(2040, 1, 1);
      final reopened = coordinator(fixture.first, 'synthetic-nonce-b');

      expect(
        (await reopened.inspect())?.phase,
        DeletionIntentPhase.recoveryUncertain,
      );
      expect((await reopened.inspect())?.casToken, isNull);
      await expectLater(reopened.requireOwnerUnfenced(_owner), _failure());
      expect((await _intentRow(fixture.first))['expires_at_utc_ms'], isNull);
    });

    for (final corrupt in [
      'not-json',
      '{"version":999,"phase":"preparing"}',
      '{"version":1,"phase":"futureUnsupported"}',
    ]) {
      test('corrupt persistent intent fails closed ($corrupt)', () async {
        await _begin(coordinator(fixture.first, 'synthetic-nonce-a'));
        final row = await _intentRow(fixture.first);
        await fixture.first.customStatement(
          'UPDATE runtime_flags SET source = ? WHERE key = ?',
          [corrupt, row['key']],
        );
        await fixture.reopenFirst();
        final reopened = coordinator(fixture.first, 'synthetic-nonce-b');

        await expectLater(reopened.requireOwnerUnfenced(_owner), _failure());
        await expectLater(reopened.requireOwnerUnfenced('owner-b'), _failure());
        await expectLater(_begin(reopened), _failure());
        await expectLater(
          reopened.writeForActiveOwner(
            expectedOwnerId: _owner,
            write: () => _insertResearchArtifacts(fixture.first),
          ),
          _failure(),
        );
        await _expectResearchCounts(fixture.first, 0);
        expect((await _intentRow(fixture.first))['source'], corrupt);
        await _ordinaryWrite(fixture.first);
      });
    }

    test(
      'admission observes deletion committed by an independent writer',
      () async {
        final writerStarted = Completer<void>();
        final releaseWriter = Completer<void>();
        final first = coordinator(fixture.first, 'synthetic-nonce-a');
        final heldWriter = fixture.first.transaction(() async {
          await _begin(first);
          writerStarted.complete();
          await releaseWriter.future;
        });
        try {
          await Future.any<void>([writerStarted.future, heldWriter]);
          fixture.interceptor.handoff = () async {
            releaseWriter.complete();
            await heldWriter;
          };
          await expectLater(
            coordinator(
              fixture.second,
              'synthetic-nonce-b',
            ).writeForActiveOwner(
              expectedOwnerId: _owner,
              write: () => _insertResearchArtifacts(fixture.second),
            ),
            _failure(),
          );
          expect(fixture.interceptor.didHandoff, isTrue);
          await _expectResearchCounts(fixture.second, 0);
        } finally {
          if (!releaseWriter.isCompleted) releaseWriter.complete();
          await heldWriter;
        }
      },
    );

    test(
      'deletion begins after an independent admitted write commits',
      () async {
        final writerStarted = Completer<void>();
        final releaseWriter = Completer<void>();
        final first = coordinator(fixture.first, 'synthetic-nonce-a');
        final heldWriter = first.writeForActiveOwner(
          expectedOwnerId: _owner,
          write: () async {
            await _insertResearchArtifacts(fixture.first);
            writerStarted.complete();
            await releaseWriter.future;
          },
        );
        try {
          await Future.any<void>([writerStarted.future, heldWriter]);
          fixture.interceptor.handoff = () async {
            releaseWriter.complete();
            await heldWriter;
          };
          final second = coordinator(fixture.second, 'synthetic-nonce-b');
          await _begin(second);
          expect(fixture.interceptor.didHandoff, isTrue);
          expect(
            (await second.inspect())?.phase,
            DeletionIntentPhase.preparing,
          );
          await _expectResearchCounts(fixture.second, 1);
        } finally {
          if (!releaseWriter.isCompleted) releaseWriter.complete();
          await heldWriter;
        }
      },
    );
  });
}

Matcher _failure() => throwsA(isA<AccountDeletionException>());

Future<DeletionIntentToken> _begin(DriftOwnerWriteCoordinator coordinator) =>
    coordinator.beginDeletion(
      ownerId: _owner,
      firebaseUid: _uid,
      idempotencyKey: _key,
    );

CloudDeletionReceipt _cloud({
  String ownerId = _owner,
  String firebaseUid = _uid,
  String idempotencyKey = _key,
  String receiptId = 'synthetic-cloud-receipt',
}) => CloudDeletionReceipt(
  receiptId: receiptId,
  ownerId: ownerId,
  firebaseUid: firebaseUid,
  idempotencyKey: idempotencyKey,
  completedAtUtc: _now,
);

const _replacementGuest =
    'local:deleted:3fb811cb5870d4d2c66efd194742c138098562e704f6d02b9b9b9c62a9cb705e';

Future<LocalDeletionReceipt> _purge(
  AppDatabase database,
  CloudDeletionReceipt cloud,
) => DriftLocalAccountDeletionGateway(
  database,
  nowUtc: () => _now,
  purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {},
).deleteAfterCloud(ownerId: _owner, cloudReceipt: cloud);

Future<void> _seedOwners(AppDatabase database) async {
  await database.customStatement('PRAGMA foreign_keys = ON');
  await database.customStatement(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, is_active, created_at_utc_ms) VALUES '
    "(?, ?, 'registered', 1, 1), ('owner-b', 'uid-b', 'registered', 0, 2)",
    [_owner, _uid],
  );
}

Future<void> _insertResearchArtifacts(AppDatabase database) async {
  final assignment = await seedOwnerAssignment(database, _owner);
  final permit = await insertOwnerParticipation(
    database,
    _owner,
    assignmentId: assignment,
  );
  await database.customStatement(
    'INSERT INTO research_consents '
    '(id, owner_id, consent_version, consent_state, decided_at_utc_ms) '
    "VALUES ('synthetic-consent', ?, 1, 'accepted', 1)",
    [_owner],
  );
  final measurement = await insertOwnerMotivationMeasurement(database, permit);
  await insertOwnerMeasurementOpportunity(
    database,
    permit: permit,
    measurement: measurement,
  );
  await database.customStatement(
    'INSERT INTO events_v2 '
    '(event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, '
    'actor_identity, owner_id, aggregate_type, aggregate_id, idempotency_key, '
    'consent_context_json, app_version, build_id, privacy_classification, payload_json) '
    "VALUES ('synthetic-event', 'synthetic_research', 2, 1, 1, ?, ?, 'synthetic', "
    "'synthetic-assignment', 'synthetic-event-key', '{}', 'test', 'test', "
    "'research', '{}')",
    [_owner, _owner],
  );
  await database.customStatement(
    'INSERT INTO outbox_operations '
    '(operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) '
    "VALUES ('synthetic-operation', ?, 'synthetic-research', 'synthetic-event', 'upsert', 1)",
    [_owner],
  );
}

Future<void> _expectResearchCounts(AppDatabase database, int count) async {
  for (final table in [
    'research_consents',
    'experiment_assignments',
    'research_participation_permits',
    'motivation_measurement_runs',
    'motivation_responses',
    'measurement_opportunities',
    'events_v2',
    'outbox_operations',
  ]) {
    final row = await database
        .customSelect('SELECT COUNT(*) AS count FROM $table')
        .getSingle();
    expect(
      row.read<int>('count'),
      table == 'events_v2' ? count * 2 : count,
      reason: table,
    );
  }
}

Future<void> _ordinaryWrite(AppDatabase database) async {
  await database.customStatement(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
    "VALUES ('ordinary-category', ?, 'ordinary', 'ordinary', 1, 1)",
    [_owner],
  );
  final row = await database
      .customSelect(
        "SELECT COUNT(*) AS count FROM vocabulary_categories WHERE id = 'ordinary-category'",
      )
      .getSingle();
  expect(row.read<int>('count'), 1);
}

Future<Map<String, Object?>> _intentRow(AppDatabase database) async =>
    (await database.customSelect('SELECT * FROM runtime_flags').getSingle())
        .data;

Future<void> _expectPreCloudStorage(AppDatabase database) async {
  final row = await _intentRow(database);
  expect(row['expires_at_utc_ms'], isNull);
  final serialized = jsonEncode(row);
  for (final secret in [_owner, _uid, _key, 'synthetic-private-nonce-']) {
    expect(serialized, isNot(contains(secret)));
  }
}

final class _FileDatabases {
  _FileDatabases(
    this.directory,
    this.ownedPath,
    this.file,
    this.first,
    this.second,
    this.interceptor,
  );

  final Directory directory;
  final String ownedPath;
  final File file;
  AppDatabase first;
  final AppDatabase second;
  final _WriterHandoff interceptor;

  static Future<_FileDatabases> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-owner-write-',
    );
    final ownedPath = await directory.resolveSymbolicLinks();
    final file = File('${directory.path}${Platform.pathSeparator}test.sqlite');
    final first = _open(file);
    final interceptor = _WriterHandoff();
    final second = _open(file, interceptor: interceptor);
    final result = _FileDatabases(
      directory,
      ownedPath,
      file,
      first,
      second,
      interceptor,
    );
    try {
      await _seedOwners(first);
      await second
          .customSelect('SELECT COUNT(*) FROM local_owners')
          .getSingle();
      return result;
    } catch (_) {
      await result.close();
      rethrow;
    }
  }

  static AppDatabase _open(File file, {_WriterHandoff? interceptor}) {
    final executor = NativeDatabase.createInBackground(
      file,
      setup: (database) {
        database.execute('PRAGMA foreign_keys = ON');
        database.execute('PRAGMA busy_timeout = 5000');
        database.execute('PRAGMA journal_mode = WAL');
      },
    );
    return AppDatabase(
      interceptor == null ? executor : executor.interceptWith(interceptor),
    );
  }

  Future<void> reopenFirst() async {
    await first.close();
    first = _open(file);
  }

  Future<void> close() async {
    await second.close();
    await first.close();
    if (!await directory.exists()) return;
    final target = await directory.resolveSymbolicLinks();
    final parent = await Directory.systemTemp.resolveSymbolicLinks();
    final separator = Platform.pathSeparator;
    final prefix =
        '$parent${parent.endsWith(separator) ? '' : separator}lexiquest-owner-write-';
    if (target != ownedPath ||
        !target.startsWith(prefix) ||
        Directory(target).parent.path != parent) {
      throw StateError('refusing to remove an unowned temporary directory');
    }
    await Directory(target).delete(recursive: true);
  }
}

final class _WriterHandoff extends drift.QueryInterceptor {
  Future<void> Function()? handoff;
  var didHandoff = false;

  @override
  Future<bool> ensureOpen(
    drift.QueryExecutor executor,
    drift.QueryExecutorUser user,
  ) async {
    final next = handoff;
    if (next == null || executor is! drift.TransactionExecutor) {
      return executor.ensureOpen(user);
    }
    handoff = null;
    // Drift requests BEGIN IMMEDIATE here, before invoking any SQL interceptor.
    final opening = executor.ensureOpen(user);
    didHandoff = true;
    final results = await Future.wait<bool>([
      opening,
      next().then((_) => true),
    ]);
    return results.first;
  }
}
