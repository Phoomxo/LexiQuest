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
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';

void main() {
  for (final accepted in [false, true]) {
    for (final ownerFailure in [false, true]) {
      testWidgets(
        'local consent failure retries without registration ownerFailure=$ownerFailure accepted=$accepted',
        (tester) async {
          final gateway = _Gateway();
          final owners = _Owners();
          final consentOwners = _Owners()..fail = ownerFailure;
          final consent = _Consent()..fail = !ownerFailure;
          final account = AccountUseCases(
            gateway: gateway,
            owners: owners,
            upgradeGuestOwner: UpgradeGuestOwner(_Upgrade()),
            entryState: _Entry(),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: RegisterScreen(
                account: account,
                researchConsent: ResearchConsentUseCases(
                  owners: consentOwners,
                  repository: consent,
                  nowUtc: () => DateTime.utc(2026, 9, 19),
                ),
              ),
              routes: {
                '/email-verification': (_) =>
                    const Scaffold(body: Text('verification destination')),
              },
            ),
          );
          await tester.enterText(
            find.byType(TextField).first,
            'learner@example.com',
          );
          await tester.enterText(find.byType(TextField).last, 'password123');
          await tester.tap(find.byType(Checkbox));
          await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(
            find.text(accepted ? 'ยินยอมเข้าร่วม' : 'ยังไม่ยินยอม'),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(gateway.registrations, 1);
          expect(consent.decisions, isEmpty);
          expect(find.textContaining('สร้างบัญชีแล้ว'), findsWidgets);
          expect(find.text('verification destination'), findsNothing);
          consent.fail = false;
          consentOwners.fail = false;
          // Continue the existing account, preserving the explicitly chosen decline.
          await tester.tap(find.byKey(const ValueKey('registration-continue')));
          await tester.pumpAndSettle();
          expect(gateway.registrations, 1);
          expect(consent.decisions, [accepted]);
          expect(find.text('verification destination'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

final class _Gateway implements AccountGateway {
  int registrations = 0;
  @override
  AccountSession? currentSession;
  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    registrations++;
    return currentSession = AccountSession(
      uid: 'synthetic-account',
      email: email,
      isAnonymous: false,
      emailVerified: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Owners implements LocalOwnerRepository {
  bool fail = false;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    if (fail) throw StateError('synthetic owner lookup failure');
    return LocalOwner(id: 'synthetic-owner', createdAtUtc: DateTime.utc(2026));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Upgrade implements OwnerUpgradeRepository {
  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) async => OwnerUpgradeResult(
    targetOwnerId: activeOwnerId,
    mode: OwnerUpgradeMode.anonymousBound,
    conflictCount: 0,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Entry implements AppEntryStateStore {
  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
  @override
  Future<void> clear() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Consent implements ResearchConsentRepository {
  bool fail = true;
  final decisions = <bool>[];
  @override
  Future<void> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) async {
    if (fail) throw StateError('synthetic local decision failure');
    decisions.add(accepted);
  }

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async => ResearchConsentStatus(
    version: version,
    accepted: decisions.lastOrNull ?? false,
  );
}
