import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import '../../support/research_authority_cache_harness.dart';

void main() {
  late AuthorityCacheFixture fixture;
  setUp(() async => fixture = await AuthorityCacheFixture.open());
  tearDown(() => fixture.close());

  Future<void> expectDenied() async {
    expect(await fixture.cache.read(), isNull);
    expect(
      await fixture.cache.loadPermit(
        ownerId: 'owner-a',
        operation: ResearchOperation.collect,
      ),
      isNull,
    );
    expect(
      await fixture.cache.loadState(permitId: 'synthetic-operation-permit'),
      isNull,
    );
    expect(
      await fixture.cache.loadCurrent(
        ownerId: 'owner-a',
        permitId: 'synthetic-participation',
      ),
      isNull,
    );
    expect(
      await fixture.cache.isActive(
        ownerId: 'owner-a',
        receiptId: 'synthetic-consent-receipt',
        kind: ResearchReceiptKind.consent,
        evaluatedAtUtc: participationStart,
      ),
      isFalse,
    );
  }

  test(
    'unconfigured memory and restarted instances grant no authority',
    () async {
      await expectDenied();
      expect(fixture.gateway.calls, 0);
      expect(await fixture.cache.refresh(), isTrue);
      final restarted = fixture.newCache();
      addTearDown(restarted.dispose);
      expect(await restarted.read(), isNull);
      expect(
        await restarted.loadPermit(
          ownerId: 'owner-a',
          operation: ResearchOperation.collect,
        ),
        isNull,
      );
      expect(fixture.gateway.calls, 1);
    },
  );

  test('real Ed and P256 packet exposes all five scoped local ports', () async {
    expect(await fixture.cache.refresh(), isTrue);
    expect((await fixture.cache.read())!.effectiveNowUtc, participationStart);
    expect(
      (await fixture.cache.loadPermit(
        ownerId: 'owner-a',
        operation: ResearchOperation.collect,
      ))!.signature,
      participationOperation().signature,
    );
    expect(
      (await fixture.cache.loadState(
        permitId: 'synthetic-operation-permit',
      ))!.currentRevision,
      1,
    );
    expect(
      (await fixture.cache.loadCurrent(
        ownerId: 'owner-a',
        permitId: 'synthetic-participation',
      ))!.signature,
      participationPermit().signature,
    );
    expect(
      await fixture.cache.isActive(
        ownerId: 'owner-a',
        receiptId: 'synthetic-consent-receipt',
        kind: ResearchReceiptKind.consent,
        evaluatedAtUtc: participationStart,
      ),
      isTrue,
    );
    expect(
      await fixture.cache.isActive(
        ownerId: 'owner-a',
        receiptId: 'synthetic-consent-receipt',
        kind: ResearchReceiptKind.guardianPermission,
        evaluatedAtUtc: participationStart,
      ),
      isFalse,
    );
    expect(
      await fixture.cache.loadPermit(
        ownerId: 'owner-b',
        operation: ResearchOperation.collect,
      ),
      isNull,
    );
    expect(fixture.gateway.calls, 1);
    expect(fixture.gateway.transactionCalls, [false]);
  });

  test(
    'unknown initial lifecycle does not fetch or grant until resumed and refreshed',
    () async {
      final unknown = fixture.newCache(initiallyForeground: false);
      addTearDown(unknown.dispose);
      expect(await unknown.refresh(), isFalse);
      expect(await unknown.read(), isNull);
      expect(fixture.gateway.calls, 0);
      unknown.resume();
      expect(await unknown.read(), isNull);
      expect(await unknown.refresh(), isTrue);
    },
  );

  test(
    'production Stopwatch ages the real signed packet without a wall clock seed',
    () async {
      final cache = fixture.newCache(realMonotonicClock: true);
      addTearDown(cache.dispose);
      expect(await cache.refresh(), isTrue);
      final before = (await cache.read())!;
      await Future<void>.delayed(const Duration(milliseconds: 3));
      final after = (await cache.read())!;
      expect(after.age, greaterThan(before.age));
      expect(after.isFresh, isTrue);
      expect(after.effectiveNowUtc.microsecond, 0);
    },
  );

  test(
    'all port reads remain local inside actual SQLite owner transaction',
    () async {
      expect(await fixture.cache.refresh(), isTrue);
      final before = await fixture.study.researchRows();
      await fixture.study.participation.ownerWrites.writeForActiveOwner(
        expectedOwnerId: 'owner-a',
        write: () async {
          expect(await fixture.cache.read(), isNotNull);
          expect(
            await fixture.cache.loadPermit(
              ownerId: 'owner-a',
              operation: ResearchOperation.collect,
            ),
            isNotNull,
          );
          expect(
            await fixture.cache.loadState(
              permitId: 'synthetic-operation-permit',
            ),
            isNotNull,
          );
          expect(
            await fixture.cache.loadCurrent(
              ownerId: 'owner-a',
              permitId: 'synthetic-participation',
            ),
            isNotNull,
          );
          expect(
            await fixture.cache.isActive(
              ownerId: 'owner-a',
              receiptId: 'synthetic-consent-receipt',
              kind: ResearchReceiptKind.consent,
              evaluatedAtUtc: participationStart,
            ),
            isTrue,
          );
        },
      );
      expect(fixture.gateway.calls, 1);
      expect(await fixture.study.researchRows(), before);
    },
  );

  test(
    'refresh in an inherited SQLite transaction never invokes gateway',
    () async {
      expect(await fixture.cache.refresh(), isTrue);
      await fixture.study.database.transaction(() async {
        expect(await fixture.cache.refresh(), isFalse);
      });
      expect(fixture.gateway.calls, 1);
      await expectDenied();
    },
  );

  for (final invalid in [
    'Ed signature',
    'P256 signature',
    'request',
    'clock session',
    'future observation',
    'old observation',
    'receipt version',
    'receipt decision',
    'maximum age',
    'gateway failure',
    'unavailable gateway',
  ]) {
    test('$invalid refresh cannot retain an earlier grant', () async {
      expect(await fixture.cache.refresh(), isTrue);
      switch (invalid) {
        case 'Ed signature':
          fixture.gateway.corruptEd = true;
        case 'P256 signature':
          fixture.gateway.corruptP256 = true;
        case 'request':
          fixture.gateway.wrongRequest = true;
        case 'clock session':
          fixture.gateway.wrongClockSession = true;
        case 'future observation':
          fixture.gateway.futureObservation = true;
        case 'old observation':
          fixture.gateway.oldObservation = true;
        case 'receipt version':
          fixture.gateway.wrongReceiptVersion = true;
        case 'receipt decision':
          fixture.gateway.wrongReceiptDecision = true;
        case 'maximum age':
          fixture.gateway.maximumAge = const Duration(hours: 1);
        case 'gateway failure':
          fixture.gateway.fail = true;
        case 'unavailable gateway':
          fixture.gateway.unavailable = true;
      }
      expect(await fixture.cache.refresh(), isFalse);
      await expectDenied();
    });
  }

  test(
    'monotonic age expires inclusively without consulting wall clock',
    () async {
      expect(await fixture.cache.refresh(), isTrue);
      fixture.study.participation.clock.now = DateTime.utc(2099);
      expect((await fixture.cache.read())!.effectiveNowUtc, participationStart);
      fixture.elapsed = const Duration(minutes: 10);
      expect((await fixture.cache.read())!.isFresh, isTrue);
      fixture.elapsed += const Duration(microseconds: 1);
      await expectDenied();
    },
  );

  test(
    'monotonic regression and unproven suspend intervals deny all reads',
    () async {
      fixture.elapsed = const Duration(seconds: 1);
      expect(await fixture.cache.refresh(), isTrue);
      fixture.elapsed = const Duration(seconds: 2);
      expect(await fixture.cache.read(), isNotNull);
      fixture.elapsed = const Duration(seconds: 1);
      await expectDenied();
      fixture.elapsed = const Duration(seconds: 3);
      expect(await fixture.cache.refresh(), isTrue);
      fixture.cache.suspend();
      await expectDenied();
      final calls = fixture.gateway.calls;
      expect(await fixture.cache.refresh(), isFalse);
      expect(fixture.gateway.calls, calls);
      fixture.cache.resume();
      await expectDenied();
      expect(await fixture.cache.refresh(), isTrue);
    },
  );

  test(
    'newer refresh wins and late older acknowledgement cannot restore receipt',
    () async {
      final reached = Completer<void>();
      final release = Completer<void>();
      fixture.gateway.onFetch = (call) async {
        if (call == 1) {
          reached.complete();
          await release.future;
        }
      };
      final old = fixture.cache.refresh();
      await reached.future;
      fixture.gateway.snapshotRevision = 2;
      fixture.gateway.receiptRevision = 2;
      fixture.gateway.receiptActive = false;
      expect(await fixture.cache.refresh(), isTrue);
      release.complete();
      expect(await old, isFalse);
      expect(
        await fixture.cache.isActive(
          ownerId: 'owner-a',
          receiptId: 'synthetic-consent-receipt',
          kind: ResearchReceiptKind.consent,
          evaluatedAtUtc: participationStart,
        ),
        isFalse,
      );
      expect(await fixture.cache.read(), isNotNull);
    },
  );

  test(
    'binding change during refresh rejects late A and never serves it to B',
    () async {
      final reached = Completer<void>();
      final release = Completer<void>();
      fixture.gateway.onFetch = (_) async {
        reached.complete();
        await release.future;
      };
      final pending = fixture.cache.refresh();
      await reached.future;
      await fixture.study.switchOwner();
      fixture.scope = fixture.scopeFor('owner-b', 'uid-b', 2);
      release.complete();
      expect(await pending, isFalse);
      await expectDenied();
      expect(
        await fixture.cache.loadPermit(
          ownerId: 'owner-b',
          operation: ResearchOperation.collect,
        ),
        isNull,
      );
    },
  );

  test('auth ABA generation fences a delayed same-owner packet', () async {
    final reached = Completer<void>();
    final release = Completer<void>();
    fixture.gateway.onFetch = (_) async {
      reached.complete();
      await release.future;
    };
    final pending = fixture.cache.refresh();
    await reached.future;
    fixture.scope = fixture.scopeFor('owner-a', 'uid-a', 3);
    release.complete();
    expect(await pending, isFalse);
    await expectDenied();
  });

  test(
    'valid signatures cannot authorize different configured instrument pins',
    () async {
      fixture.scope = fixture.scopeFor(
        'owner-a',
        'uid-a',
        1,
        instrumentRevision: 10,
      );
      expect(await fixture.cache.refresh(), isFalse);
      await expectDenied();
    },
  );

  test(
    'withdrawal during gateway await remains durable and denies installation',
    () async {
      fixture.gateway.onFetch = (_) async {
        expect(
          await fixture.study.runtime.consent.withdraw(
            expectedOwnerId: 'owner-a',
            expectedVersion: 4,
          ),
          isTrue,
        );
      };
      expect(await fixture.cache.refresh(), isFalse);
      await expectDenied();
      expect((await fixture.study.runtime.consent.load()).accepted, isFalse);
      expect(fixture.gateway.transactionCalls, [false]);
    },
  );

  test(
    'suspend and resume during refresh cannot adopt the earlier acknowledgement',
    () async {
      final reached = Completer<void>();
      final release = Completer<void>();
      fixture.gateway.onFetch = (call) async {
        if (call == 1) {
          reached.complete();
          await release.future;
        }
      };
      final pending = fixture.cache.refresh();
      await reached.future;
      fixture.cache.suspend();
      fixture.cache.resume();
      release.complete();
      expect(await pending, isFalse);
      await expectDenied();
      expect(await fixture.cache.refresh(), isTrue);
    },
  );

  test(
    'higher snapshot revision cannot downgrade a signed operation',
    () async {
      fixture.gateway.operationRevision = 2;
      fixture.gateway.stateRevision = 2;
      expect(await fixture.cache.refresh(), isTrue);
      fixture.gateway.snapshotRevision = 2;
      fixture.gateway.operationRevision = 1;
      fixture.gateway.stateRevision = 1;
      expect(await fixture.cache.refresh(), isFalse);
      await expectDenied();
    },
  );

  test(
    'a valid newly signed document cannot rewrite the same participation revision',
    () async {
      expect(await fixture.cache.refresh(), isTrue);
      fixture.gateway.snapshotRevision = 2;
      fixture.gateway.ageBandCode = 'different-synthetic-band';
      expect(await fixture.cache.refresh(), isFalse);
      await expectDenied();
    },
  );

  test(
    'unchanged documents cannot hide a snapshot revision downgrade',
    () async {
      fixture.gateway.snapshotRevision = 2;
      expect(await fixture.cache.refresh(), isTrue);
      fixture.gateway.snapshotRevision = 1;
      expect(await fixture.cache.refresh(), isFalse);
      await expectDenied();
    },
  );

  test(
    'revoked state and inactive receipt cannot resurrect their existing IDs',
    () async {
      fixture.gateway.revoked = true;
      fixture.gateway.receiptActive = false;
      expect(await fixture.cache.refresh(), isTrue);
      fixture.gateway.snapshotRevision = 2;
      fixture.gateway.stateRevision = 2;
      fixture.gateway.receiptRevision = 2;
      fixture.gateway.revoked = false;
      fixture.gateway.receiptActive = true;
      expect(await fixture.cache.refresh(), isFalse);
      await expectDenied();
    },
  );

  test(
    'signed participation revocation is readable but cannot be removed later',
    () async {
      fixture.gateway.participationRevision = 2;
      fixture.gateway.participationRevokedAt = participationStart;
      expect(await fixture.cache.refresh(), isTrue);
      expect(
        (await fixture.cache.loadCurrent(
          ownerId: 'owner-a',
          permitId: 'synthetic-participation',
        ))!.revokedAtUtc,
        participationStart,
      );
      fixture.gateway.snapshotRevision = 2;
      fixture.gateway.participationRevision = 3;
      fixture.gateway.participationRevokedAt = null;
      expect(await fixture.cache.refresh(), isFalse);
      await expectDenied();
    },
  );
}
