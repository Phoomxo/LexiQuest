import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/billing/billing_runtime.dart';
import 'package:vocab_learning_app/features/content_reports/data/http_content_report_transport.dart';
import 'package:vocab_learning_app/features/content_reports/data/registered_content_report_identity.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';

import 'content_report_test_support.dart';

void main() {
  late AppDatabase database;
  late StreamController<void> authEvents;
  late DriftBillingAccountBinding accounts;
  BillingAuthIdentity? identity;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement(
      "INSERT INTO local_owners (id,firebase_uid,account_state,created_at_utc_ms,is_active) "
      "VALUES ('synthetic-owner','synthetic-uid','firebaseBound',1,1)",
    );
    authEvents = StreamController<void>.broadcast(sync: true);
    identity = const BillingAuthIdentity(
      uid: 'synthetic-uid',
      isAnonymous: false,
    );
    accounts = DriftBillingAccountBinding(
      database: database,
      currentIdentity: () => identity,
      authInvalidations: authEvents.stream,
    );
  });
  tearDown(() async {
    await accounts.dispose();
    await authEvents.close();
    await database.close();
  });

  test(
    'registered report identity reads real owner without automatic token or row writes',
    () async {
      final before = await _rows(database);
      var tokens = 0;
      final ports = await createRegisteredContentReportIdentity(
        accounts: accounts,
        loadIdToken: (account) async {
          tokens++;
          expect(account.ownerId, 'synthetic-owner');
          expect(account.firebaseUid, 'synthetic-uid');
          return 'synthetic-token';
        },
      );
      addTearDown(ports.dispose);
      final binding = ports.currentBinding()!;
      expect(binding.ownerId, 'synthetic-owner');
      expect(binding.firebaseUid, 'synthetic-uid');
      expect(tokens, 0);
      await ports.requireCurrent(binding);
      expect(tokens, 0);
      expect(await ports.loadIdToken(binding), 'synthetic-token');
      expect(tokens, 1);
      expect(await _rows(database), before);
      final disposal = ports.dispose();
      expect(ports.dispose(), same(disposal));
      await disposal;
      expect(ports.currentBinding(), isNull);
    },
  );

  for (final rejected in ['anonymous', 'guest', 'different UID']) {
    test('$rejected cannot acquire registered report authority', () async {
      if (rejected == 'guest') {
        await database.customStatement(
          "UPDATE local_owners SET account_state='localGuest' WHERE id='synthetic-owner'",
        );
      } else {
        identity = BillingAuthIdentity(
          uid: rejected == 'anonymous'
              ? 'synthetic-uid'
              : 'different-synthetic-uid',
          isAnonymous: rejected == 'anonymous',
        );
      }
      final before = await _rows(database);
      var tokens = 0;
      final ports = await createRegisteredContentReportIdentity(
        accounts: accounts,
        loadIdToken: (_) async {
          tokens++;
          return 'synthetic-token';
        },
      );
      addTearDown(ports.dispose);
      expect(ports.currentBinding(), isNull);
      expect(tokens, 0);
      expect(await _rows(database), before);
    });
  }

  test(
    'real auth ABA during token acquisition prevents HTTP submission',
    () async {
      final token = Completer<String?>();
      final started = Completer<void>();
      var tokens = 0;
      var requests = 0;
      final ports = await createRegisteredContentReportIdentity(
        accounts: accounts,
        loadIdToken: (_) {
          tokens++;
          started.complete();
          return token.future;
        },
      );
      addTearDown(ports.dispose);
      final original = ports.currentBinding()!;
      final transport = HttpContentReportTransport(
        enabled: true,
        identity: ports,
        client: MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
        baseUri: Uri.parse('https://synthetic.invalid'),
      );
      final assertion = expectLater(
        transport.submit(original, syntheticReport()),
        throwsA(
          isA<ContentReportException>().having(
            (e) => e.code,
            'code',
            ContentReportFailureCode.ownerChanged,
          ),
        ),
      );
      await started.future.timeout(const Duration(seconds: 2));
      identity = null;
      authEvents.add(null);
      expect(ports.currentBinding(), isNull);
      identity = const BillingAuthIdentity(
        uid: 'synthetic-uid',
        isAnonymous: false,
      );
      authEvents.add(null);
      await accounts.refresh();
      expect(
        ports.currentBinding()!.generation,
        greaterThan(original.generation),
      );
      token.complete('synthetic-retired-token');
      await assertion;
      await expectLater(
        ports.loadIdToken(original),
        throwsA(isA<ContentReportException>()),
      );
      expect(tokens, 1);
      expect(requests, 0);
      expect(await database.select(database.researchConsents).get(), isEmpty);
    },
  );

  test(
    'real deletion intent fences report token acquisition without extra writes',
    () async {
      var tokens = 0;
      final ports = await createRegisteredContentReportIdentity(
        accounts: accounts,
        loadIdToken: (_) async {
          tokens++;
          return 'synthetic-token';
        },
      );
      addTearDown(ports.dispose);
      final original = ports.currentBinding()!;
      await DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => DateTime.utc(2026, 11, 1),
        nonceGenerator: () => 'synthetic-nonce',
      ).beginDeletion(
        ownerId: 'synthetic-owner',
        firebaseUid: 'synthetic-uid',
        idempotencyKey: 'synthetic-deletion',
      );
      final before = await _rows(database);
      await expectLater(
        ports.loadIdToken(original),
        throwsA(isA<ContentReportException>()),
      );
      expect(tokens, 0);
      expect(await _rows(database), before);
    },
  );

  test('failed real account observer cannot revive a report binding', () async {
    final ports = await createRegisteredContentReportIdentity(
      accounts: accounts,
      loadIdToken: (_) async => 'synthetic-token',
    );
    addTearDown(ports.dispose);
    expect(ports.currentBinding(), isNotNull);
    authEvents.addError(StateError('Synthetic observer failure'));
    expect(ports.currentBinding(), isNull);
    await accounts.refresh();
    expect(ports.currentBinding(), isNull);
  });
}

Future<Map<String, Object?>> _rows(AppDatabase database) async => {
  for (final table in database.allTables)
    table.actualTableName: [
      for (final row
          in await database
              .customSelect(
                'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
              )
              .get())
        Map<String, Object?>.from(row.data),
    ],
};
