import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';

void main() {
  testWidgets('announces profile loading state', (tester) async {
    final pending = Completer<ProgressSnapshot>();
    await tester.pumpWidget(
      MaterialApp(home: ProfileSettingsScreen(loader: () => pending.future)),
    );
    await tester.pump();

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังอ่านข้อมูลโปรไฟล์',
    );
  });

  testWidgets('profile renders only evidence-derived progress', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ProfileSettingsScreen(loader: () async => _progress)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('7 วัน'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('ระดับจากคะแนนประสบการณ์'), findsOneWidget);
    expect(find.text('แสดงเฉพาะคะแนนจากคำตอบที่บันทึกจริง'), findsOneWidget);
    expect(find.textContaining('วิธีคำนวณรุ่น'), findsNothing);
    expect(find.textContaining('Khun Phet'), findsNothing);
  });

  testWidgets('profile retries one failed local read and recovers', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSettingsScreen(
          loader: () {
            loads++;
            return loads == 1
                ? Future.error(StateError('synthetic profile read failure'))
                : Future.value(_progress);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsAtLeastNWidgets(1),
    );
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('authenticated learner can update the displayed profile name', (
    tester,
  ) async {
    final gateway = _ProfileGateway();
    final account = AccountUseCases(
      gateway: gateway,
      owners: _Owners(),
      upgradeGuestOwner: UpgradeGuestOwner(_Upgrades()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSettingsScreen(
          loader: () async => _progress,
          account: account,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผู้เรียน A'), findsOneWidget);
    await tester.tap(find.text('แก้ไขชื่อที่แสดง'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  ผู้เรียน B  ');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();

    expect(gateway.updatedDisplayName, 'ผู้เรียน B');
    expect(find.text('ผู้เรียน B'), findsOneWidget);
  });

  testWidgets('cancel leaves the provider and displayed name unchanged', (
    tester,
  ) async {
    final gateway = _ProfileGateway();
    await _openProfile(tester, gateway);
    await tester.tap(find.text('แก้ไขชื่อที่แสดง'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved name');
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();

    expect(gateway.updateCalls, 0);
    expect(find.text('ผู้เรียน A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider failure retains the draft and permits retry', (
    tester,
  ) async {
    final gateway = _ProfileGateway()
      ..failure = const AccountException(AccountFailureCode.network);
    await _openProfile(tester, gateway);
    await tester.tap(find.text('แก้ไขชื่อที่แสดง'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ผู้เรียน B');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();

    expect(find.text('บันทึกชื่อไม่สำเร็จ กรุณาลองใหม่'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ผู้เรียน B',
    );
    expect(gateway.currentSession?.displayName, 'ผู้เรียน A');
    gateway.failure = null;
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(find.text('ผู้เรียน B'), findsOneWidget);
  });

  testWidgets('pending profile save cannot submit twice or leave by Back', (
    tester,
  ) async {
    final pending = Completer<void>();
    final gateway = _ProfileGateway()..pending = pending;
    await _openProfile(tester, gateway);
    await tester.tap(find.text('แก้ไขชื่อที่แสดง'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ผู้เรียน B');
    await tester.tap(find.text('บันทึก'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(gateway.updateCalls, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'profile editor remains usable with 200 percent text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _openProfile(tester, _ProfileGateway(), largeText: true);
      await tester.tap(find.text('แก้ไขชื่อที่แสดง'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();

      expect(find.text('กรอกชื่อ 1–50 ตัวอักษรในบรรทัดเดียว'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('ยกเลิก'));
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}

Future<void> _openProfile(
  WidgetTester tester,
  _ProfileGateway gateway, {
  bool largeText = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(largeText ? 2 : 1),
          viewInsets: EdgeInsets.only(bottom: largeText ? 300 : 0),
        ),
        child: child!,
      ),
      home: ProfileSettingsScreen(
        loader: () async => _progress,
        account: AccountUseCases(
          gateway: gateway,
          owners: _Owners(),
          upgradeGuestOwner: UpgradeGuestOwner(_Upgrades()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _progress = ProgressSnapshot(
  sampleSize: 10,
  correctCount: 8,
  wrongCount: 2,
  accuracy: .8,
  totalXp: 42,
  completedSessions: 2,
  streakDays: 7,
  dueReviewCount: 1,
  masteredWordCount: 2,
  achievementCount: 1,
  gameLevel: 3,
  skills: [],
  weaknesses: [],
  recommendations: [],
);

final class _ProfileGateway implements AccountGateway {
  String? updatedDisplayName;
  Object? failure;
  Completer<void>? pending;
  int updateCalls = 0;

  @override
  AccountSession? currentSession = const AccountSession(
    uid: 'synthetic-user',
    email: 'learner@example.test',
    displayName: 'ผู้เรียน A',
    isAnonymous: false,
    emailVerified: true,
  );

  @override
  Future<AccountSession> updateDisplayName(String displayName) async {
    updateCalls++;
    await pending?.future;
    if (failure case final error?) throw error;
    updatedDisplayName = displayName;
    return currentSession = AccountSession(
      uid: 'synthetic-user',
      email: 'learner@example.test',
      displayName: displayName,
      isAnonymous: false,
      emailVerified: true,
    );
  }

  @override
  Future<void> applyEmailVerificationCode(String code) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession> reload() => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> sendVerification() => throw UnimplementedError();

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}

final class _Owners implements LocalOwnerRepository {
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => LocalOwner(
    id: 'synthetic-owner',
    firebaseUid: 'synthetic-user',
    createdAtUtc: DateTime.utc(2026, 10, 20),
  );
}

final class _Upgrades implements OwnerUpgradeRepository {
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
