import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/billing/domain/billing_contracts.dart';

import 'support/billing_fixture.dart';

void main() {
  test(
    'store success grants nothing until server verification acknowledges the same owner',
    () async {
      final f = BillingFixture();
      addTearDown(f.dispose);
      await f.billing.load();
      await f.billing.buy(f.billing.view.offers.single);
      expect(f.store.launchedAccount, 'a' * 64);
      expect(
        f.billing.hasAccess(
          'managedContent',
          ownerId: syntheticAccount.ownerId,
        ),
        isFalse,
      );
      f.repository.verification = Completer<BillingSnapshot>();
      f.store.events.add([syntheticPurchase()]);
      await f.flush();
      expect(f.billing.view.phase, BillingPhase.verifying);
      expect(f.store.completions, 0);
      expect(
        f.billing.hasAccess(
          'managedContent',
          ownerId: syntheticAccount.ownerId,
        ),
        isFalse,
      );
      f.repository.verification!.complete(syntheticSnapshot(active: true));
      await f.flush();
      expect(f.billing.view.phase, BillingPhase.active);
      expect(f.store.completions, 1);
      expect(
        f.billing.hasAccess(
          'managedContent',
          ownerId: syntheticAccount.ownerId,
        ),
        isTrue,
      );
    },
  );

  test(
    'A-B-A during verification retires the command and hides all old rights',
    () async {
      final f = BillingFixture();
      addTearDown(f.dispose);
      await f.billing.load();
      f.repository.verification = Completer<BillingSnapshot>();
      f.store.events.add([syntheticPurchase()]);
      await f.flush();
      f.changeAccount(
        const BillingAccount(
          ownerId: 'synthetic-b',
          firebaseUid: 'synthetic-uid-b',
          isAnonymous: false,
        ),
      );
      f.changeAccount(syntheticAccount);
      f.repository.verification!.complete(syntheticSnapshot(active: true));
      await f.flush();
      expect(f.store.completions, 0);
      expect(f.billing.view.snapshot, isNull);
      expect(
        f.billing.hasAccess(
          'managedContent',
          ownerId: syntheticAccount.ownerId,
        ),
        isFalse,
      );
    },
  );

  test(
    'retry verification reuses the exact original command and request identity',
    () async {
      final f = BillingFixture();
      addTearDown(f.dispose);
      await f.billing.load();
      f.repository.failVerification = true;
      f.store.events.add([syntheticPurchase()]);
      await f.flush();
      final original = f.repository.commands.single;
      expect(f.billing.view.verificationPending, isTrue);
      f.repository.failVerification = false;
      f.repository.snapshot = syntheticSnapshot(active: true);
      await f.billing.retryVerification();
      expect(identical(f.repository.commands.last, original), isTrue);
      expect(f.requestCount, 1);
      expect(f.store.completions, 1);
    },
  );

  test(
    'a different account receipt is ignored before server verification',
    () async {
      final f = BillingFixture();
      addTearDown(f.dispose);
      await f.billing.load();
      f.store.events.add([syntheticPurchase(accountIdentifier: 'b' * 64)]);
      await f.flush();
      expect(f.repository.commands, isEmpty);
      expect(f.store.completions, 0);
      expect(
        f.billing.hasAccess(
          'managedContent',
          ownerId: syntheticAccount.ownerId,
        ),
        isFalse,
      );
    },
  );

  test('pending and cancelled purchases do not become entitlements', () async {
    final f = BillingFixture();
    addTearDown(f.dispose);
    await f.billing.load();
    f.store.events.add([
      syntheticPurchase(status: BillingPurchaseStatus.pending),
    ]);
    await f.flush();
    expect(f.billing.view.phase, BillingPhase.pending);
    f.store.events.add([
      syntheticPurchase(status: BillingPurchaseStatus.cancelled),
    ]);
    await f.flush();
    expect(f.billing.view.failure, BillingFailureCode.cancelled);
    expect(f.repository.commands, isEmpty);
    expect(f.store.completions, 0);
  });

  test(
    'repeated purchase taps cannot launch a second pending transaction',
    () async {
      final f = BillingFixture();
      addTearDown(f.dispose);
      await f.billing.load();
      final offer = f.billing.view.offers.single;
      await f.billing.buy(offer);
      for (var i = 0; i < 2; i++) {
        await expectLater(
          () => f.billing.buy(offer),
          throwsA(_failure(BillingFailureCode.pending)),
        );
      }
      expect(f.store.launches, 1);
    },
  );

  test(
    'server acknowledgement pending retries without completing a native purchase early',
    () async {
      final f = BillingFixture();
      addTearDown(f.dispose);
      await f.billing.load();
      f.repository.snapshot = syntheticSnapshot(
        active: true,
        acknowledgementPending: true,
      );
      f.store.events.add([syntheticPurchase()]);
      await f.flush();
      expect(f.store.completions, 0);
      expect(f.billing.view.verificationPending, isTrue);
      f.repository.snapshot = syntheticSnapshot(active: true);
      await f.billing.retryVerification();
      expect(f.store.completions, 1);
      expect(
        identical(f.repository.commands.first, f.repository.commands.last),
        isTrue,
      );
    },
  );

  test(
    'restoration rechecks a previously completed receipt after freshness expires',
    () async {
      final f = BillingFixture();
      addTearDown(f.dispose);
      await f.billing.load();
      f.repository.snapshot = syntheticSnapshot(active: true);
      f.store.events.add([syntheticPurchase()]);
      await f.flush();
      f.elapsed = const Duration(minutes: 6);
      expect(
        f.billing.hasAccess(
          'managedContent',
          ownerId: syntheticAccount.ownerId,
        ),
        isFalse,
      );
      f.repository.snapshot = syntheticSnapshot(
        active: true,
        now: DateTime.utc(2026, 11, 1, 0, 6),
      );
      await f.billing.restore();
      expect(f.store.restores, 1);
      expect(f.repository.commands, hasLength(2));
      expect(
        identical(f.repository.commands.first, f.repository.commands.last),
        isTrue,
      );
      expect(
        f.billing.hasAccess(
          'managedContent',
          ownerId: syntheticAccount.ownerId,
        ),
        isTrue,
      );
    },
  );

  test(
    'replayed store delivery neither verifies nor completes an accepted receipt twice',
    () async {
      final f = BillingFixture();
      addTearDown(f.dispose);
      await f.billing.load();
      f.repository.snapshot = syntheticSnapshot(active: true);
      f.store.events.add([syntheticPurchase()]);
      await f.flush();
      f.store.events.add([syntheticPurchase()]);
      await f.flush();
      expect(f.repository.commands, hasLength(1));
      expect(f.store.completions, 1);
    },
  );

  test('offline store never offers a guessed purchasable plan', () async {
    final f = BillingFixture();
    addTearDown(f.dispose);
    f.store.available = false;
    await expectLater(
      f.billing.load,
      throwsA(_failure(BillingFailureCode.unavailable)),
    );
    expect(f.billing.view.offers, isEmpty);
    expect(f.store.launches, 0);
  });

  test('a local elapsed-clock reversal cannot extend paid access', () async {
    final f = BillingFixture();
    addTearDown(f.dispose);
    f.elapsed = const Duration(seconds: 10);
    f.repository.snapshot = syntheticSnapshot(active: true);
    await f.billing.load();
    expect(
      f.billing.hasAccess('managedContent', ownerId: 'other-owner'),
      isFalse,
    );
    f.elapsed = Duration.zero;
    expect(
      f.billing.hasAccess('managedContent', ownerId: syntheticAccount.ownerId),
      isFalse,
    );
  });
}

Matcher _failure(BillingFailureCode code) =>
    isA<BillingException>().having((error) => error.code, 'code', code);
