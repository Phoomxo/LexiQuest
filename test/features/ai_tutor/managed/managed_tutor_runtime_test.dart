import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_runtime.dart';
import 'support.dart';

void main() {
  test(
    'canonical database owner/account changes clear session; disposed watch stops',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final transport = TestTransport();
      var clears = 0;
      final runtime = ManagedTutorRuntime(
        database: db,
        transport: transport,
        network: const Stream.empty(),
        clearSession: () async {
          clears++;
        },
      );
      await db
          .into(db.localOwners)
          .insert(
            LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1),
          );
      await pumpEventQueue();
      expect(runtime.identity.value?.ownerId, 'owner-a');
      final first = runtime.identity.value;
      await db.customUpdate(
        "UPDATE local_owners SET firebase_uid = 'account-a'",
        updates: {db.localOwners},
      );
      await pumpEventQueue();
      expect(runtime.identity.value?.accountId, 'account-a');
      expect(identical(first, runtime.identity.value), isFalse);
      expect(clears, greaterThanOrEqualTo(1));
      await runtime.dispose();
      final before = clears;
      await db.customUpdate(
        "UPDATE local_owners SET is_active = 0",
        updates: {db.localOwners},
      );
      await pumpEventQueue();
      expect(clears, before);
      await db.close();
    },
  );
}
