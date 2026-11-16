import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
  for (final accountState in ['absent', 'anonymous', 'authenticated']) {
    testWidgets(
      'W02 account controls follow $accountState app account independently of AI',
      (tester) async {
        final session = accountState == 'absent'
            ? null
            : AccountSession(
                uid: 'app-account',
                email: 'fixture@example.test',
                isAnonymous: accountState == 'anonymous',
                emailVerified: true,
              );
        final gateway = _Gateway(session);
        final owners = _Owners();
        final account = AccountUseCases(
          gateway: gateway,
          owners: owners,
          upgradeGuestOwner: UpgradeGuestOwner(_Upgrade()),
          entryState: _Entry(),
        );
        String? aiOwner;
        final registry = MenuActionRegistry(currentOwner: () => aiOwner);
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: MaterialApp(
              home: SettingScreen(account: account, localOwners: owners),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final connected in [false, true, false, true]) {
          aiOwner = connected ? 'app-owner' : null;
          registry.invalidateSession(preserveContext: true);
          await tester.pumpAndSettle();
          final signedIn = accountState == 'authenticated';
          expect(
            find.text('เปลี่ยนรหัสผ่าน'),
            signedIn ? findsOneWidget : findsNothing,
          );
          final actions = (registry.snapshot()['actions'] as List)
              .map((a) => a['id'])
              .toList();
          expect(
            actions.contains('settings/change-password'),
            signedIn && connected,
          );
          expect(
            actions,
            isNot(contains('settings/logout')),
            reason: 'App logout is manual-only even with AI attached',
          );
          expect(gateway.currentSession, same(session));
          expect(gateway.unexpectedCalls, isEmpty);
        }
        if (accountState == 'authenticated') {
          final snapshot = registry.snapshot();
          aiOwner = null;
          registry.invalidateSession(preserveContext: true);
          final rejected = await registry.execute(
            id: 'settings/change-password',
            owner: 'app-owner',
            revision: snapshot['revision'] as int,
            requestId: 'retained-disconnected-action',
          );
          expect(rejected['status'], isNot('invoked'));
          expect(find.byType(AlertDialog), findsNothing);
          // Native/manual account controls remain usable when optional AI is off.
          final password = find.text('เปลี่ยนรหัสผ่าน');
          await tester.ensureVisible(password);
          await tester.tap(password);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.byType(TextField), findsNWidgets(2));
          await tester.tap(find.text('ยกเลิก'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(gateway.unexpectedCalls, isEmpty);
          expect(gateway.currentSession, same(session));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _Gateway implements AccountGateway {
  _Gateway(this.currentSession);
  @override
  final AccountSession? currentSession;
  final unexpectedCalls = <String>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls.add(invocation.memberName.toString());
    throw StateError('Account mutation not authorized by this fixture');
  }
}

class _Owners implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'app-owner', createdAtUtc: DateTime.utc(2026));
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw StateError('Unexpected account binding');
}

class _Upgrade implements OwnerUpgradeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected owner mutation');
}

class _Entry implements AppEntryStateStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected entry mutation');
}
