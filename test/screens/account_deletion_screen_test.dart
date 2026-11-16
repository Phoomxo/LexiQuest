import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/application/account_deletion_use_cases.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/screens/account_deletion_screen.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24, 12);

  testWidgets('requires exact Thai confirmation before deleting', (
    tester,
  ) async {
    final harness = _Harness(now);
    final exportGate = Completer<void>();
    harness.exporter.gate = exportGate;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDeletionScreen(
          useCases: harness.useCases,
          idempotencyKey: 'delete:synthetic-operation-0001',
        ),
      ),
    );

    final submit = find.byKey(const ValueKey('delete-account-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-confirmation')),
      'ลบบัญชี ',
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-confirmation')),
      'ลบบัญชี',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pump();
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังส่งออกสำเนาและลบบัญชี',
    );
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.byKey(const ValueKey('delete-account-status')),
              matching: find.byType(Semantics),
            ),
          )
          .any((widget) => widget.properties.liveRegion == true),
      isTrue,
    );
    exportGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('ลบบัญชีเรียบร้อย'), findsOneWidget);
    expect(harness.cloud.calls, 1);
    expect(harness.local.calls, 1);
  });

  testWidgets('after cloud success retry resumes local cleanup only', (
    tester,
  ) async {
    final harness = _Harness(now)..local.failOnce = true;
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDeletionScreen(
          useCases: harness.useCases,
          idempotencyKey: 'delete:synthetic-operation-0002',
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-confirmation')),
      'ลบบัญชี',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('delete-account-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('ลบบัญชีออนไลน์แล้ว'), findsOneWidget);
    expect(harness.exporter.calls, 1);
    expect(harness.cloud.calls, 1);

    await tester.tap(find.byKey(const ValueKey('delete-account-submit')));
    await tester.pumpAndSettle();

    expect(find.text('ลบบัญชีเรียบร้อย'), findsOneWidget);
    expect(harness.exporter.calls, 1);
    expect(harness.cloud.calls, 1);
    expect(harness.local.calls, 2);
  });

  testWidgets('stays usable at 360x800 with 200 percent text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final harness = _Harness(now);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: AccountDeletionScreen(useCases: harness.useCases),
        ),
      ),
    );

    final submit = find.byType(FilledButton).first;
    await tester.ensureVisible(submit);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(submit).height, greaterThanOrEqualTo(48));
  });
}

final class _Harness {
  _Harness(this.now) {
    useCases = AccountDeletionUseCases(
      enabled: true,
      owners: _Owners(now),
      currentSession: () => const AccountSession(
        uid: 'firebase-user',
        email: 'learner@example.test',
        isAnonymous: false,
        emailVerified: true,
      ),
      exporter: exporter,
      reauthenticator: _Reauth(now),
      cloud: cloud = _Cloud(now),
      local: local = _Local(now),
      journal: _Journal(),
      nowUtc: () => now,
    );
  }

  final DateTime now;
  final _Exporter exporter = _Exporter();
  late final _Cloud cloud;
  late final _Local local;
  late final AccountDeletionUseCases useCases;
}

final class _Owners implements LocalOwnerRepository {
  const _Owners(this.now);
  final DateTime now;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => LocalOwner(
    id: 'owner-1',
    firebaseUid: 'firebase-user',
    createdAtUtc: now,
  );

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _Exporter implements FullAccountExporter {
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<FullAccountExportReceipt> export({required String ownerId}) async {
    calls++;
    await gate?.future;
    return FullAccountExportReceipt(
      ownerId: ownerId,
      artifactId: 'artifact-1',
      artifactSha256: 'a' * 64,
      bytesWritten: 10,
      schemaVersion: 10,
      coveredScopes: requiredFullAccountExportScopes,
      completedAtUtc: DateTime.utc(2026, 10, 24, 11, 59),
    );
  }
}

final class _Reauth implements AccountDeletionReauthenticator {
  const _Reauth(this.now);
  final DateTime now;

  @override
  Future<RecentAuthenticationReceipt> reauthenticate({
    required String firebaseUid,
  }) async => RecentAuthenticationReceipt(
    firebaseUid: firebaseUid,
    authenticatedAtUtc: now,
  );
}

final class _Cloud implements PrivilegedAccountDeletionGateway {
  _Cloud(this.now);
  final DateTime now;
  int calls = 0;

  @override
  Future<CloudDeletionReceipt> deleteRecursively({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) async {
    calls++;
    return CloudDeletionReceipt(
      receiptId: 'receipt-1',
      ownerId: ownerId,
      firebaseUid: firebaseUid,
      idempotencyKey: idempotencyKey,
      completedAtUtc: now,
    );
  }
}

final class _Local implements LocalAccountDeletionGateway {
  _Local(this.now);
  final DateTime now;
  bool failOnce = false;
  int calls = 0;

  @override
  Future<LocalDeletionReceipt> deleteAfterCloud({
    required String ownerId,
    required CloudDeletionReceipt cloudReceipt,
  }) async {
    calls++;
    if (failOnce) {
      failOnce = false;
      throw StateError('synthetic local failure');
    }
    return LocalDeletionReceipt(
      deletedOwnerId: ownerId,
      newGuestOwnerId: 'guest-1',
      completedAtUtc: now,
    );
  }
}

final class _Journal implements AccountDeletionJournal {
  AccountDeletionJournalEntry? entry;

  @override
  Future<AccountDeletionJournalEntry?> load() async => entry;

  @override
  Future<void> saveCloudReceipt(CloudDeletionReceipt receipt) async {
    entry = AccountDeletionJournalEntry(cloudReceipt: receipt);
  }

  @override
  Future<void> saveLocalReceipt({
    required CloudDeletionReceipt cloudReceipt,
    required LocalDeletionReceipt localReceipt,
  }) async {
    entry = AccountDeletionJournalEntry(
      cloudReceipt: cloudReceipt,
      localReceipt: localReceipt,
    );
  }
}
