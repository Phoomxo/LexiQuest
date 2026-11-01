import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/billing/billing_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/research_transport_contracts.dart';
import 'package:vocab_learning_app/runtime/firebase_research_identity.dart';

void main() {
  late AppDatabase database;
  late StreamController<void> authEvents;
  late DriftBillingAccountBinding accounts;
  BillingAuthIdentity? identity;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement(
      "INSERT INTO local_owners (id,firebase_uid,account_state,created_at_utc_ms,is_active) VALUES ('synthetic-owner','synthetic-uid','firebaseBound',1,1)",
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
    'registered identity reads real owner without Research writes',
    () async {
      final before = await _rows(database);
      var tokens = 0;
      final ports = await createRegisteredResearchIdentity(
        accounts: accounts,
        loadIdToken: (account) async {
          tokens++;
          expect(account.ownerId, 'synthetic-owner');
          return 'synthetic-token';
        },
      );
      addTearDown(ports.dispose);
      final binding = ports.currentBinding()!;
      expect(binding.ownerId, 'synthetic-owner');
      expect(binding.authSubjectId, 'synthetic-uid');
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

  test('auth A-B-A retires token acquisition and old generations', () async {
    final token = Completer<String?>();
    final started = Completer<void>();
    var loads = 0;
    final ports = await createRegisteredResearchIdentity(
      accounts: accounts,
      loadIdToken: (_) {
        loads++;
        started.complete();
        return token.future;
      },
    );
    addTearDown(ports.dispose);
    final original = ports.currentBinding()!;
    final pending = ports.loadIdToken(original);
    final assertion = expectLater(
      pending,
      throwsA(isA<ResearchTransportException>()),
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
    final current = ports.currentBinding()!;
    expect(current.generation, greaterThan(original.generation));
    expect(current.ownerId, original.ownerId);
    token.complete('synthetic-retired-token');
    await assertion;
    await expectLater(
      ports.loadIdToken(original),
      throwsA(isA<ResearchTransportException>()),
    );
    expect(loads, 1);
    expect(await database.select(database.researchConsents).get(), isEmpty);
  });

  test('failed account observer leaves Research unavailable', () async {
    final ports = await createRegisteredResearchIdentity(
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
        row.data,
    ],
};
