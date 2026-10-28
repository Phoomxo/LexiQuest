import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_lifecycle_manifest.dart';

void main() {
  test('audio exposure checkpoints have an owned durable table', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    expect(
      rows.map((r) => r.read<String>('name')),
      contains('audio_lesson_checkpoints'),
    );
    expect(
      ownerLifecycleManifest.where(
        (d) => d.tableName == 'audio_lesson_checkpoints',
      ),
      hasLength(1),
    );
  });
}
