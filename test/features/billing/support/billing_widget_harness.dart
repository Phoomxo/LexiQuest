import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'billing_fixture.dart';

Future<void> pumpBillingUntil(WidgetTester tester, bool Function() done) async {
  for (var frame = 0; frame < 120; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  fail(
    'Billing widget did not acknowledge its expected state within 120 frames',
  );
}

Future<void> disposeBillingFixture(
  WidgetTester tester,
  BillingFixture fixture,
) async {
  var complete = false;
  Object? failure;
  unawaited(
    fixture.dispose().then<void>(
      (_) => complete = true,
      onError: (Object error) {
        failure = error;
        complete = true;
      },
    ),
  );
  await pumpBillingUntil(tester, () => complete);
  if (failure != null) throw failure!;
}
