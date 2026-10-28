import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/data/firebase_account_gateway.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';

void main() {
  for (final anonymous in [false, true]) {
    for (final failure in [false, true]) {
      testWidgets('F05 Firebase registration anonymous=$anonymous emailFailure=$failure', (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final now = DateTime.utc(2026, 9, 20);
        final owners = DriftLocalOwnerRepository(db,
            generateId: () => 'guest', nowUtc: () => now);
        final original = await owners.getOrCreateActiveOwner();
        final auth = _Auth(anonymous: anonymous, failure: failure);
        final entry = _Entry();
        final account = AccountUseCases(
          gateway: FirebaseAccountGateway(auth), owners: owners,
          upgradeGuestOwner: UpgradeGuestOwner(DriftOwnerUpgradeRepository(db,
            nowUtc: () => now, generateConflictId: () => 'conflict',
            generateOwnerId: () => 'replacement', generateOwnerOperationToken: () => 'token',
            deleteOwnerSecrets: (_) async {})),
          entryState: entry,
        );
        await tester.pumpWidget(MaterialApp(
          home: RegisterScreen(account: account),
          routes: {'/email-verification': (_) => const Scaffold(body: Text('verification destination'))},
        ));
        await tester.enterText(find.byType(TextField).first, 'learner@example.com');
        await tester.enterText(find.byType(TextField).last, 'password123');
        await tester.tap(find.byType(Checkbox));
        await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
        // Real SQLite work runs outside FakeAsync.
        await tester.runAsync(() async {
          for (var i = 0; i < 100 && entry.mode != AppEntryMode.signedOut; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect((await tester.runAsync(owners.getOrCreateActiveOwner))!.firebaseUid, auth.user.uid);
        expect((await tester.runAsync(owners.getOrCreateActiveOwner))!.id, original.id);
        expect(entry.mode, AppEntryMode.signedOut);
        expect(auth.creates, anonymous ? 0 : 1);
        expect(auth.user.links, anonymous ? 1 : 0);
        expect(auth.user.sends, 1);
        if (failure) {
          expect(find.byKey(const ValueKey('registration-completion-error')), findsOneWidget);
          expect(find.textContaining('ส่งอีเมลยืนยัน'), findsWidgets);
          expect(find.text('verification destination'), findsNothing);
          // Repeated mail failure keeps the already bound account recoverable.
          await tester.tap(find.byKey(const ValueKey('registration-continue')));
          await tester.pumpAndSettle();
          expect(auth.user.sends, 2);
          expect(find.byKey(const ValueKey('registration-completion-error')), findsOneWidget);
          auth.user.failure = false;
          await tester.tap(find.byKey(const ValueKey('registration-continue')));
          await tester.pumpAndSettle();
          expect(auth.user.sends, 3);
        }
        expect(find.text('verification destination'), findsOneWidget);
        expect(auth.creates, anonymous ? 0 : 1);
        expect(auth.user.links, anonymous ? 1 : 0);
        expect(auth.signouts, 0);
        expect(auth.user.deletes, 0);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(minutes: 3));
      });
    }
  }
}

final class _Auth extends Fake implements FirebaseAuth {
  _Auth({required bool anonymous, required bool failure}) {
    user = _User(anonymous: anonymous, failure: failure);
    current = anonymous ? user : null;
  }
  late final _User user;
  User? current;
  int creates = 0, signouts = 0;
  @override
  User? get currentUser => current;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({required String email, required String password}) async {
    creates++;
    user.anonymous = false;
    current = user;
    return _Credential(user);
  }
  @override
  Future<void> signOut() async { signouts++; current = null; }
}
final class _User extends Fake implements User {
  _User({required this.anonymous, required this.failure});
  bool anonymous, failure;
  int links = 0, sends = 0, deletes = 0;
  @override
  String get uid => 'sdk-user';
  @override
  String? get email => 'learner@example.com';
  @override
  bool get isAnonymous => anonymous;
  @override
  bool get emailVerified => false;
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    links++; anonymous = false; return _Credential(this);
  }
  @override
  Future<void> sendEmailVerification([ActionCodeSettings? actionCodeSettings]) async {
    sends++;
    if (failure) throw FirebaseAuthException(code: 'network-request-failed');
  }
  @override
  Future<void> delete() async { deletes++; }
}
final class _Credential extends Fake implements UserCredential {
  _Credential(this.user);
  @override
  final User user;
}
final class _Entry implements AppEntryStateStore {
  AppEntryMode mode = AppEntryMode.guest;
  @override
  Future<AppEntryMode> read() async => mode;
  @override
  Future<void> clear() async { mode = AppEntryMode.signedOut; }
  @override
  Future<void> markGuest() async { mode = AppEntryMode.guest; }
}
