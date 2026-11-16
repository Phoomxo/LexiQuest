import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 10, 24, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.customStatement(
      "INSERT INTO local_owners "
      "(id, firebase_uid, account_state, is_active, created_at_utc_ms) "
      "VALUES ('owner-a', 'uid-a', 'registered', 1, 1), "
      "('owner-b', 'uid-b', 'registered', 0, 2)",
    );
    await database.customStatement(
      "INSERT INTO vocabulary_categories "
      "(id, owner_id, name, normalized_name, sort_order, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
      "VALUES ('cat-a', 'owner-a', 'A', 'a', 0, 0, 1, 1), "
      "('cat-b', 'owner-b', 'B', 'b', 0, 0, 1, 1)",
    );
  });

  tearDown(() => database.close());

  test(
    'covers every required local scope and isolates the requested owner',
    () async {
      final snapshot = await DriftAccountSnapshotBuilder(
        database,
        nowUtc: () => now,
      ).build(ownerId: 'owner-a');

      expect(snapshot.coveredScopes, requiredFullAccountExportScopes);
      expect(snapshot.sha256, sha256.convert(snapshot.bytes).toString());
      final json =
          jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, dynamic>;
      expect(json['schemaVersion'], 10);
      expect(json['ownerId'], 'owner-a');
      final data = json['data'] as Map<String, dynamic>;
      expect(data.keys.toSet(), requiredFullAccountExportScopes);
      expect((data['vocabulary_categories'] as List).single['id'], 'cat-a');
      expect(utf8.decode(snapshot.bytes), isNot(contains('cat-b')));
      expect(utf8.decode(snapshot.bytes), isNot(contains('uid-b')));
    },
  );
}
