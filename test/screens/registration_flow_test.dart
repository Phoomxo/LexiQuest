import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/features/research/domain/research_runtime_availability.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';

void main() {
  testWidgets('registration explains unavailable account service up front', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));

    expect(find.text('สร้างบัญชี'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.textContaining('ยังสร้างบัญชีไม่ได้'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enabled, isFalse);
    }
  });

  testWidgets('pending registration announces account creation', (
    tester,
  ) async {
    final harness = _RegistrationHarness();
    final pending = Completer<void>();
    harness.gateway.pending = pending;
    await _pumpRegistration(tester, harness);
    await _fillRegistration(tester);

    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await tester.pump();

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังสร้างบัญชี',
    );
    pending.complete();
    await _pumpFrames(tester);
    await tester.tap(find.text('ยังไม่ยินยอม'));
    await _pumpFrames(tester);
  });

  testWidgets('registration rejects mismatched passwords before provider use', (
    tester,
  ) async {
    final harness = _RegistrationHarness();
    await _pumpRegistration(tester, harness);
    await tester.tap(find.byType(Checkbox));
    await tester.enterText(find.byType(TextField).first, 'student@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.enterText(find.byType(TextField).last, 'password456');
    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await tester.pump();

    expect(find.text('รหัสผ่านและการยืนยันไม่ตรงกัน'), findsOneWidget);
    expect(find.text('ระบบบัญชีออนไลน์ไม่พร้อม'), findsNothing);
    expect(harness.gateway.registerCalls, 0);
  });

  testWidgets(
    'registration identifies every invalid field before provider use',
    (tester) async {
      final harness = _RegistrationHarness();
      await _pumpRegistration(tester, harness);
      await tester.tap(find.byType(Checkbox));
      await tester.enterText(find.byType(TextField).first, 'not-an-email');
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester.enterText(find.byType(TextField).last, 'different');

      await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
      await tester.pump();

      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList(growable: false);
      expect(fields[0].decoration?.errorText, 'ตรวจสอบรูปแบบอีเมล');
      expect(
        fields[1].decoration?.errorText,
        'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร',
      );
      expect(fields[2].decoration?.errorText, 'รหัสผ่านและการยืนยันไม่ตรงกัน');
      expect(harness.gateway.registerCalls, 0);
    },
  );

  testWidgets('initial research decline creates no decision and still routes', (
    tester,
  ) async {
    final harness = _RegistrationHarness();
    await _pumpRegistration(tester, harness);
    await _fillRegistration(tester);

    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await _pumpFrames(tester);
    expect(find.text('เลือกเข้าร่วมการวิจัย'), findsOneWidget);
    await tester.tap(find.text('ยังไม่ยินยอม'));
    await _pumpFrames(tester);

    expect(harness.consentRepository.decisions, isEmpty);
    expect(find.text('EMAIL_VERIFICATION_REACHED'), findsOneWidget);
  });

  testWidgets('production-style default skips the research prompt', (
    tester,
  ) async {
    final harness = _RegistrationHarness();
    await _pumpRegistration(
      tester,
      harness,
      researchAvailability: ResearchRuntimeAvailability.disabled,
    );
    await _fillRegistration(tester);

    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await _pumpFrames(tester);

    expect(find.text('เลือกเข้าร่วมการวิจัย'), findsNothing);
    expect(harness.consentRepository.decisions, isEmpty);
    expect(find.text('EMAIL_VERIFICATION_REACHED'), findsOneWidget);
  });

  testWidgets('withdrawn current version does not reopen research consent', (
    tester,
  ) async {
    final harness = _RegistrationHarness(initialResearchWithdrawn: true);
    await _pumpRegistration(tester, harness);
    await _fillRegistration(tester);

    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await _pumpFrames(tester);

    expect(find.text('เลือกเข้าร่วมการวิจัย'), findsNothing);
    expect(harness.consentRepository.decisions, isEmpty);
    expect(find.text('EMAIL_VERIFICATION_REACHED'), findsOneWidget);
  });

  testWidgets('declining fresh prompt withdraws current accepted consent', (
    tester,
  ) async {
    final harness = _RegistrationHarness(initialResearchAccepted: true);
    await _pumpRegistration(tester, harness);
    await _fillRegistration(tester);

    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await _pumpFrames(tester);
    await tester.tap(find.text('ยังไม่ยินยอม'));
    await _pumpFrames(tester);

    expect(harness.consentRepository.decisions, [('owner-a', false)]);
    expect(find.text('EMAIL_VERIFICATION_REACHED'), findsOneWidget);
  });

  testWidgets('system back does not withdraw current accepted consent', (
    tester,
  ) async {
    final harness = _RegistrationHarness(initialResearchAccepted: true);
    await _pumpRegistration(tester, harness);
    await _fillRegistration(tester);

    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await _pumpFrames(tester);
    expect(find.text('เลือกเข้าร่วมการวิจัย'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _pumpFrames(tester);

    expect(harness.consentRepository.decisions, isEmpty);
    expect(find.text('EMAIL_VERIFICATION_REACHED'), findsOneWidget);
  });

  testWidgets('research read failure is fail closed and still routes', (
    tester,
  ) async {
    final harness = _RegistrationHarness(
      consentLoadError: StateError('private-sentinel'),
    );
    await _pumpRegistration(tester, harness);
    await _fillRegistration(tester);

    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await _pumpFrames(tester);

    expect(harness.consentRepository.decisions, isEmpty);
    expect(find.text('EMAIL_VERIFICATION_REACHED'), findsOneWidget);
    expect(
      find.textContaining('ไม่ได้บันทึกความยินยอมการวิจัย'),
      findsOneWidget,
    );
    expect(find.textContaining('private-sentinel'), findsNothing);
  });

  testWidgets('privacy notice does not grant optional research consent', (
    tester,
  ) async {
    final harness = _RegistrationHarness();
    await _pumpRegistration(tester, harness);

    await tester.tap(find.text('อ่านประกาศความเป็นส่วนตัว'));
    await tester.pumpAndSettle();

    expect(
      find.text('ประกาศความเป็นส่วนตัวและเงื่อนไขทดลองใช้'),
      findsOneWidget,
    );
    expect(find.text('เลือกเข้าร่วมการวิจัย'), findsNothing);
    expect(
      find.textContaining('การเข้าร่วมงานวิจัยเป็นทางเลือก'),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(harness.consentRepository.decisions, isEmpty);

    await tester.tap(find.text('รับทราบ'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('default-off privacy notice does not advertise research', (
    tester,
  ) async {
    final harness = _RegistrationHarness();
    await _pumpRegistration(
      tester,
      harness,
      researchAvailability: ResearchRuntimeAvailability.disabled,
    );

    await tester.tap(find.text('อ่านประกาศความเป็นส่วนตัว'));
    await tester.pumpAndSettle();

    expect(find.textContaining('การเข้าร่วมงานวิจัย'), findsNothing);
    expect(find.textContaining('ส่งออกหรือลบบัญชีและข้อมูล'), findsOneWidget);
  });

  testWidgets('fresh post-registration acceptance records the bound owner', (
    tester,
  ) async {
    final harness = _RegistrationHarness(switchOwnerOnRegister: true);
    await _pumpRegistration(tester, harness);
    await _fillRegistration(tester);

    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await _pumpFrames(tester);
    await tester.tap(find.text('ยินยอมเข้าร่วม'));
    await _pumpFrames(tester);

    expect(harness.consentRepository.decisions, [('owner-b', true)]);
    expect(find.text('EMAIL_VERIFICATION_REACHED'), findsOneWidget);
  });
}

Future<void> _pumpRegistration(
  WidgetTester tester,
  _RegistrationHarness harness, {
  ResearchRuntimeAvailability researchAvailability =
      ResearchRuntimeAvailability.syntheticComplete,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: RegisterScreen(
        account: harness.account,
        researchConsent: harness.consent,
        researchAvailability: researchAvailability,
      ),
      routes: {
        AppRoute.emailVerification.path: (_) =>
            const Scaffold(body: Text('EMAIL_VERIFICATION_REACHED')),
      },
    ),
  );
}

Future<void> _fillRegistration(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox));
  await tester.enterText(find.byType(TextField).first, 'student@example.com');
  await tester.enterText(find.byType(TextField).at(1), 'password123');
  await tester.enterText(find.byType(TextField).last, 'password123');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final class _RegistrationHarness {
  _RegistrationHarness({
    bool switchOwnerOnRegister = false,
    bool initialResearchAccepted = false,
    bool initialResearchWithdrawn = false,
    Object? consentLoadError,
  }) : owners = _RegistrationOwners(),
       consentRepository = _RecordingConsentRepository(
         accepted: initialResearchAccepted,
         withdrawn: initialResearchWithdrawn,
         loadError: consentLoadError,
       ) {
    final upgrades = _RegistrationUpgrades(
      owners,
      switchOwnerOnRegister: switchOwnerOnRegister,
    );
    account = AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(upgrades),
    );
    consent = ResearchConsentUseCases(
      owners: owners,
      repository: consentRepository,
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );
  }

  final _RegistrationOwners owners;
  final _RecordingConsentRepository consentRepository;
  final _RegistrationGateway gateway = _RegistrationGateway();
  late final AccountUseCases account;
  late final ResearchConsentUseCases consent;
}

final class _RecordingConsentRepository implements ResearchConsentRepository {
  _RecordingConsentRepository({
    this.accepted = false,
    this.withdrawn = false,
    this.loadError,
  });

  final List<(String, bool)> decisions = [];
  bool accepted;
  final bool withdrawn;
  final Object? loadError;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async {
    if (loadError case final error?) throw error;
    return ResearchConsentStatus(
      ownerId: ownerId,
      version: version,
      accepted: accepted,
      decidedAtUtc: accepted || withdrawn ? DateTime.utc(2026, 10, 20) : null,
      withdrawnAtUtc: withdrawn ? DateTime.utc(2026, 10, 20) : null,
    );
  }

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) async {
    decisions.add((ownerId, accepted));
    this.accepted = accepted;
    return true;
  }
}

final class _RegistrationOwners implements LocalOwnerRepository {
  LocalOwner current = LocalOwner(
    id: 'owner-a',
    createdAtUtc: DateTime.utc(2026, 10, 21),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => current;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _RegistrationUpgrades implements OwnerUpgradeRepository {
  _RegistrationUpgrades(this.owners, {required this.switchOwnerOnRegister});

  final _RegistrationOwners owners;
  final bool switchOwnerOnRegister;

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) async {
    if (switchOwnerOnRegister) {
      owners.current = LocalOwner(
        id: 'owner-b',
        firebaseUid: firebaseUid,
        createdAtUtc: DateTime.utc(2026, 10, 21),
      );
    }
    return OwnerUpgradeResult(
      targetOwnerId: owners.current.id,
      mode: OwnerUpgradeMode.anonymousBound,
      conflictCount: 0,
    );
  }

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() =>
      throw UnimplementedError();

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) => throw UnimplementedError();
}

final class _RegistrationGateway implements AccountGateway {
  Completer<void>? pending;
  int registerCalls = 0;

  @override
  AccountSession? currentSession;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    registerCalls++;
    await pending?.future;
    currentSession = AccountSession(
      uid: 'registered-user',
      email: email,
      isAnonymous: false,
      emailVerified: false,
    );
    return currentSession!;
  }

  @override
  Future<void> signOut() async {}

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
  Future<AccountSession> updateDisplayName(String displayName) =>
      throw UnimplementedError();
}
