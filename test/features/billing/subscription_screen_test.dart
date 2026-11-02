import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/billing/domain/billing_contracts.dart';
import 'package:vocab_learning_app/features/billing/presentation/subscription_screen.dart';

import 'support/billing_fixture.dart';
import 'support/billing_widget_harness.dart';

void main() {
  testWidgets('unconfigured payments have no purchase action', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SubscriptionScreen()));
    expect(find.text('ยังไม่เปิดรับชำระเงินในแอปรุ่นนี้'), findsOneWidget);
    expect(find.text('สมัครผ่าน Google Play'), findsNothing);
  });

  testWidgets('managed AI quota and free offline scope precede purchase', (
    tester,
  ) async {
    final f = BillingFixture();
    try {
      await tester.pumpWidget(
        MaterialApp(home: SubscriptionScreen(billing: f.billing)),
      );
      await pumpBillingUntil(
        tester,
        () => f.billing.view.phase == BillingPhase.ready,
      );
      expect(find.text('สร้างเนื้อหา AI ได้ 10 หน่วยต่อวัน'), findsOneWidget);
      expect(find.text('โควตาเริ่มรอบใหม่เวลา 00:00 UTC'), findsOneWidget);
      expect(
        find.text('ฝึกออฟไลน์พื้นฐานได้โดยไม่ต้องสมัครสมาชิก'),
        findsOneWidget,
      );
      expect(f.store.launches, 0);
      expect(f.repository.commands, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await disposeBillingFixture(tester, f);
    }
  });

  testWidgets(
    'localized price and renewal terms precede the real purchase command',
    (tester) async {
      final f = BillingFixture();
      try {
        await tester.pumpWidget(
          MaterialApp(home: SubscriptionScreen(billing: f.billing)),
        );
        await pumpBillingUntil(
          tester,
          () => f.billing.view.phase == BillingPhase.ready,
        );
        expect(find.text('฿99.00 ต่อ 1 เดือน'), findsOneWidget);
        expect(find.textContaining('ต่ออายุอัตโนมัติ'), findsOneWidget);
        final buy = find.byKey(const ValueKey('billing-buy-synthetic-offer'));
        await tester.scrollUntilVisible(
          buy,
          200,
          scrollable: find.byType(Scrollable),
        );
        await tester.pump();
        expect(buy.hitTestable(), findsOneWidget);
        await tester.tap(buy.hitTestable());
        await pumpBillingUntil(
          tester,
          () => f.billing.view.phase == BillingPhase.pending,
        );
        expect(f.store.launches, 1);
        expect(f.repository.commands, isEmpty);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('billing-status')),
          -200,
          scrollable: find.byType(Scrollable),
        );
        await tester.pump();
        expect(find.textContaining('การซื้อรอดำเนินการ'), findsOneWidget);
        f.repository.verification = Completer<BillingSnapshot>();
        f.store.events.add([syntheticPurchase()]);
        await pumpBillingUntil(
          tester,
          () => f.billing.view.phase == BillingPhase.verifying,
        );
        expect(find.text('กำลังยืนยันการซื้อกับเซิร์ฟเวอร์'), findsOneWidget);
        expect(find.text('ตรวจสอบสิทธิ์แพ็กเกจแล้ว'), findsNothing);
        f.repository.verification!.complete(syntheticSnapshot(active: true));
        await pumpBillingUntil(
          tester,
          () => f.billing.view.phase == BillingPhase.active,
        );
        expect(find.text('ตรวจสอบสิทธิ์แพ็กเกจแล้ว'), findsOneWidget);
        expect(f.store.completions, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await disposeBillingFixture(tester, f);
      }
    },
  );

  testWidgets(
    'changing owner during verification hides old offers and never confirms success',
    (tester) async {
      final f = BillingFixture();
      try {
        await tester.pumpWidget(
          MaterialApp(home: SubscriptionScreen(billing: f.billing)),
        );
        await pumpBillingUntil(
          tester,
          () => f.billing.view.phase == BillingPhase.ready,
        );
        f.repository.verification = Completer<BillingSnapshot>();
        f.store.events.add([syntheticPurchase()]);
        await pumpBillingUntil(
          tester,
          () => f.billing.view.phase == BillingPhase.verifying,
        );
        f.changeAccount(null);
        await pumpBillingUntil(
          tester,
          () => f.billing.view.phase == BillingPhase.unavailable,
        );
        expect(find.text('฿99.00 ต่อ 1 เดือน'), findsNothing);
        f.repository.verification!.complete(syntheticSnapshot(active: true));
        await tester.pumpAndSettle();
        expect(find.text('ตรวจสอบสิทธิ์แพ็กเกจแล้ว'), findsNothing);
        expect(f.store.completions, 0);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await disposeBillingFixture(tester, f);
      }
    },
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'purchase and restore remain reachable at320px200percent with keyboard $brightness',
      (tester) async {
        final f = BillingFixture();
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness, useMaterial3: true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: SubscriptionScreen(billing: f.billing),
            ),
          );
          await pumpBillingUntil(
            tester,
            () => f.billing.view.phase == BillingPhase.ready,
          );
          final buy = find.byKey(const ValueKey('billing-buy-synthetic-offer'));
          await tester.scrollUntilVisible(buy, 180);
          await tester.pumpAndSettle();
          expect(tester.getRect(buy).height, greaterThanOrEqualTo(48));
          final restore = find.byKey(const ValueKey('billing-restore'));
          await tester.scrollUntilVisible(restore, 180);
          await tester.pumpAndSettle();
          await tester.tap(restore);
          await pumpBillingUntil(
            tester,
            () =>
                f.store.restores == 1 &&
                f.billing.view.phase == BillingPhase.ready,
          );
          expect(f.store.restores, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await disposeBillingFixture(tester, f);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetViewInsets();
        }
      },
    );
  }
}
