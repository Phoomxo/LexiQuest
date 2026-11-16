import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';

void main() {
  testWidgets('verification screen fails closed without an account provider', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OTPScreen(email: 'test@example.com')),
    );

    expect(find.text('ยืนยันอีเมล'), findsOneWidget);
    expect(find.textContaining('test@example.com'), findsOneWidget);
    await tester.tap(find.text('ฉันยืนยันอีเมลแล้ว'));
    await tester.pump();
    expect(find.text('ระบบยืนยันอีเมลไม่พร้อมใช้งาน'), findsOneWidget);

    ScaffoldMessenger.of(
      tester.element(find.byType(OTPScreen)),
    ).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('ระบบยืนยันอีเมลไม่พร้อมใช้งาน'), findsNothing);
    await tester.tap(find.text('ส่งอีเมลยืนยันใหม่'));
    await tester.pump();
    expect(find.text('ระบบยืนยันอีเมลไม่พร้อมใช้งาน'), findsOneWidget);
  });

  testWidgets('verification copy explains how to recover a missing email', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OTPScreen(email: 'learner@example.test')),
    );

    expect(
      find.text(
        'ตรวจอีเมลยืนยันที่\nlearner@example.test\n'
        'หากยังไม่พบ ให้กดส่งอีเมลยืนยันใหม่',
      ),
      findsOneWidget,
    );
  });

  testWidgets('resend reports failure and waits for another explicit tap', (
    tester,
  ) async {
    final gateway = _ResendGateway()
      ..failure = const AccountException(AccountFailureCode.unavailable);
    await tester.pumpWidget(
      MaterialApp(
        home: OTPScreen(
          email: 'learner@example.test',
          account: _account(gateway),
        ),
      ),
    );

    await tester.tap(find.text('ส่งอีเมลยืนยันใหม่'));
    await tester.pump();
    expect(find.text('ส่งอีเมลยืนยันไม่สำเร็จ'), findsOneWidget);
    expect(gateway.sendCalls, 1);

    await tester.pump(const Duration(seconds: 2));
    expect(gateway.sendCalls, 1);
  });

  testWidgets('resend reports success after one provider dispatch', (
    tester,
  ) async {
    final pending = Completer<void>();
    final gateway = _ResendGateway()..pending = pending;
    await tester.pumpWidget(
      MaterialApp(
        home: OTPScreen(
          email: 'learner@example.test',
          account: _account(gateway),
        ),
      ),
    );

    await tester.tap(find.text('ส่งอีเมลยืนยันใหม่'));
    await tester.pump();

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังส่งอีเมลยืนยันใหม่',
    );
    pending.complete();
    await tester.pump();

    expect(find.text('ส่งอีเมลยืนยันอีกครั้งแล้ว'), findsOneWidget);
    expect(gateway.sendCalls, 1);
  });
}

AccountUseCases _account(AccountGateway gateway) => AccountUseCases(
  gateway: gateway,
  owners: _UnusedOwners(),
  upgradeGuestOwner: UpgradeGuestOwner(_UnusedUpgrades()),
);

final class _ResendGateway implements AccountGateway {
  int sendCalls = 0;
  Object? failure;
  Completer<void>? pending;

  @override
  AccountSession? get currentSession => null;

  @override
  Future<void> sendVerification() async {
    sendCalls++;
    await pending?.future;
    if (failure case final error?) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _UnusedOwners implements LocalOwnerRepository {
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();

  @override
  Future<LocalOwner> getOrCreateActiveOwner() => throw UnimplementedError();
}

final class _UnusedUpgrades implements OwnerUpgradeRepository {
  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() =>
      throw UnimplementedError();

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) => throw UnimplementedError();

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) => throw UnimplementedError();
}
