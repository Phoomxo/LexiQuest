import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 10, 28);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedAnswerEvidenceOwners(database);
    await insertAnswerEvidence(
      database,
      evidence: ordinaryAnswerEvidence(skillId: 'PRIVATE_OWNER_A_CANARY'),
    );
    await insertAnswerEvidence(
      database,
      owner: 'b',
      id: 'attempt-b',
      evidence: ordinaryAnswerEvidence(skillId: 'PRIVATE_OWNER_B_CANARY'),
    );
  });
  tearDown(() => database.close());

  test(
    'full account export preserves complete metadata for exactly its owner',
    () async {
      final snapshot = await DriftAccountSnapshotBuilder(
        database,
        nowUtc: () => now,
      ).build(ownerId: 'owner-a');
      final encoded = utf8.decode(snapshot.bytes);
      final document = jsonDecode(encoded) as Map<String, dynamic>;
      final data = document['data'] as Map<String, dynamic>;
      final attempt =
          (data['answer_attempts'] as List).single as Map<String, dynamic>;
      expect(document['schemaVersion'], 20);
      expect(data['saved_words'], isEmpty);
      expect(data['word_reports'], isEmpty);
      expect(data['assessment_runs'], isEmpty);
      expect(attempt['evidence_class'], 'recognition');
      expect(
        jsonDecode(attempt['evidence_context_json'] as String),
        ordinaryAnswerEvidence(skillId: 'PRIVATE_OWNER_A_CANARY').toJson(),
      );
      expect(encoded, contains('PRIVATE_OWNER_A_CANARY'));
      expect(encoded, isNot(contains('PRIVATE_OWNER_B_CANARY')));
    },
  );

  test(
    'guest merge preserves both contexts without duplicating their answer IDs',
    () async {
      await database.customStatement(
        "UPDATE local_owners SET firebase_uid = NULL, account_state = 'localGuest' WHERE id = 'owner-a'",
      );
      var conflicts = 0;
      final repository = DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => now,
        generateConflictId: () => 'evidence-conflict-${conflicts++}',
        generateOwnerId: () => 'unused-new-owner',
      );
      final result = await repository.upgrade(
        activeOwnerId: 'owner-a',
        firebaseUid: 'uid-b',
      );
      final replay = await repository.upgrade(
        activeOwnerId: result.targetOwnerId,
        firebaseUid: 'uid-b',
      );
      expect(result.targetOwnerId, 'owner-b');
      expect(replay.targetOwnerId, 'owner-b');
      final rows = await database
          .customSelect('SELECT * FROM answer_attempts ORDER BY id')
          .get();
      expect(rows.map((row) => row.read<String>('id')), [
        'attempt-a',
        'attempt-b',
      ]);
      expect(
        rows.every((row) => row.read<String>('owner_id') == 'owner-b'),
        isTrue,
      );
      expect(
        jsonDecode(rows.first.read<String>('evidence_context_json')),
        ordinaryAnswerEvidence(skillId: 'PRIVATE_OWNER_A_CANARY').toJson(),
      );
      expect(
        jsonDecode(rows.last.read<String>('evidence_context_json')),
        ordinaryAnswerEvidence(skillId: 'PRIVATE_OWNER_B_CANARY').toJson(),
      );
    },
  );

  test(
    'cloud-confirmed deletion removes owner metadata and preserves the other owner',
    () async {
      final receipt =
          await DriftLocalAccountDeletionGateway(
            database,
            nowUtc: () => now,
            purgeOwnerSecret:
                ({required ownerId, required firebaseUid}) async {},
          ).deleteAfterCloud(
            ownerId: 'owner-a',
            cloudReceipt: CloudDeletionReceipt(
              receiptId: 'synthetic-deletion-receipt',
              ownerId: 'owner-a',
              firebaseUid: 'uid-a',
              idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
              completedAtUtc: now,
            ),
          );
      expect(receipt.deletedOwnerId, 'owner-a');
      final remaining = await database
          .customSelect('SELECT * FROM answer_attempts')
          .get();
      expect(remaining, hasLength(1));
      expect(remaining.single.read<String>('owner_id'), 'owner-b');
      expect(
        jsonDecode(remaining.single.read<String>('evidence_context_json')),
        ordinaryAnswerEvidence(skillId: 'PRIVATE_OWNER_B_CANARY').toJson(),
      );
    },
  );
}
