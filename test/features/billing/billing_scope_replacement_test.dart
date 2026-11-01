import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/billing/domain/billing_contracts.dart';
import 'package:vocab_learning_app/features/billing/presentation/subscription_screen.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import 'support/billing_fixture.dart';

void main() {
  testWidgets(
    'replacing the dependency scope retires an open subscription offer before purchase',
    (tester) async {
      final first = BillingFixture();
      final second = BillingFixture(
        initialAccount: const BillingAccount(
          ownerId: 'synthetic-second-owner',
          firebaseUid: 'synthetic-second-uid',
          isAnonymous: false,
        ),
      );
      final firstDependencies = _dependencies(first);
      final secondDependencies = _dependencies(second);
      final navigator = GlobalKey<NavigatorState>();
      Widget app(AppDependencies dependencies) => AppDependenciesScope(
        dependencies: dependencies,
        child: MaterialApp(
          navigatorKey: navigator,
          home: SubscriptionScreen(billing: first.billing),
        ),
      );
      try {
        await tester.pumpWidget(app(firstDependencies));
        const buyKey = ValueKey('billing-buy-synthetic-offer');
        await _pumpUntil(
          tester,
          () => find.byKey(buyKey).evaluate().isNotEmpty,
        );
        expect(find.byKey(buyKey), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byKey(buyKey)).onPressed,
          isNotNull,
        );
        expect(first.store.launches, 0);

        await tester.pumpWidget(app(secondDependencies));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final oldOffer = find.byKey(buyKey);
        if (oldOffer.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(oldOffer).onPressed != null) {
          await tester.ensureVisible(oldOffer);
          await tester.tap(oldOffer);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(
          first.store.launches,
          0,
          reason:
              'An old open offer must not purchase through a replaced runtime',
        );
        expect(
          second.store.launches,
          0,
          reason:
              'A retired offer must not transfer to the replacement account',
        );
        expect(first.repository.commands, isEmpty);
        expect(second.repository.commands, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await _disposeFixture(tester, first);
        await _disposeFixture(tester, second);
      }
    },
  );

  test(
    'fresh account invalidation at launch notification prevents a native purchase',
    () async {
      final fixture = BillingFixture();
      final observer = fixture.billing.changes.listen((view) {
        if (view.phase == BillingPhase.launching) fixture.account = null;
      });
      try {
        await fixture.billing.load();
        await expectLater(
          fixture.billing.buy(fixture.billing.view.offers.single),
          throwsA(
            isA<BillingException>().having(
              (error) => error.code,
              'code',
              BillingFailureCode.ownerChanged,
            ),
          ),
        );
        expect(
          fixture.store.launches,
          0,
          reason:
              'Fresh account identity must be checked at the native purchase boundary',
        );
      } finally {
        await observer.cancel();
        await fixture.dispose();
      }
    },
  );

  test(
    'fresh account invalidation at restore notification prevents native restore',
    () async {
      final fixture = BillingFixture();
      final observer = fixture.billing.changes.listen((view) {
        if (view.phase == BillingPhase.restoring) fixture.account = null;
      });
      try {
        await fixture.billing.load();
        await expectLater(
          fixture.billing.restore(),
          throwsA(
            isA<BillingException>().having(
              (error) => error.code,
              'code',
              BillingFailureCode.ownerChanged,
            ),
          ),
        );
        expect(
          fixture.store.restores,
          0,
          reason:
              'Fresh account identity must be checked before the native restore boundary',
        );
      } finally {
        await observer.cancel();
        await fixture.dispose();
      }
    },
  );

  test(
    'fresh account invalidation at grant notification prevents native completion',
    () async {
      final fixture = BillingFixture();
      final observer = fixture.billing.changes.listen((view) {
        if (view.phase == BillingPhase.active) fixture.account = null;
      });
      try {
        await fixture.billing.load();
        fixture.repository.snapshot = syntheticSnapshot(active: true);
        fixture.store.events.add([syntheticPurchase()]);
        await fixture.flush();
        expect(fixture.repository.commands, hasLength(1));
        expect(
          fixture.store.completions,
          0,
          reason:
              'A published grant cannot substitute for a current native completion authority',
        );
        expect(
          fixture.billing.hasAccess(
            'managedContent',
            ownerId: syntheticAccount.ownerId,
          ),
          isFalse,
        );
      } finally {
        await observer.cancel();
        await fixture.dispose();
      }
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var frame = 0; frame < 120; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  fail('Synthetic subscription did not reach its expected visible state');
}

Future<void> _disposeFixture(
  WidgetTester tester,
  BillingFixture fixture,
) async {
  var complete = false;
  Object? failure;
  unawaited(
    fixture.dispose().then<void>(
      (_) {
        complete = true;
      },
      onError: (Object error) {
        failure = error;
        complete = true;
      },
    ),
  );
  await _pumpUntil(tester, () => complete);
  if (failure != null) throw failure!;
}

AppDependencies _dependencies(BillingFixture fixture) => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _UnusedGuest(),
  billing: fixture.billing,
);

final class _UnusedGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw StateError(
    'No authentication request belongs in this synthetic subscription route',
  );
}
