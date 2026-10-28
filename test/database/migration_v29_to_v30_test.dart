import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/goals/data/drift_study_plan_repository.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late DriftStudyPlanRepository repo;
  final now = DateTime.utc(2026, 9, 20);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('study-plan-migration-');
    db = AppDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    repo = DriftStudyPlanRepository(db, nowUtc: () => now);
    await db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES('a',1,1),('b',1,0)",
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test(
    'v29 upgrade retains existing owner and goal while adding empty plans',
    () async {
      await db.customStatement(
        "INSERT INTO learning_goals(id,owner_id,kind,title,deadline_at_utc_ms,timezone_id,timezone_offset_minutes,status,created_at_utc_ms,updated_at_utc_ms) VALUES('g','a','personal','Keep',1,'UTC',0,'active',1,1)",
      );
      await db.customStatement('DROP TABLE active_plan_pointers');
      await db.customStatement('DROP TABLE study_plan_revisions');
      await db.customStatement('PRAGMA user_version=29');
      await db.close();
      db = AppDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
      repo = DriftStudyPlanRepository(db, nowUtc: () => now);
      expect(await repo.history('a'), isEmpty);
      expect((await db.select(db.learningGoals).get()).single.title, 'Keep');
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        AppDatabase.currentSchemaVersion,
      );
    },
  );
  test(
    'failed v29 upgrade rolls back new tables and recovers after obstruction removed',
    () async {
      await db.customStatement('DROP TABLE active_plan_pointers');
      await db.customStatement('DROP TABLE study_plan_revisions');
      await db.customStatement('PRAGMA user_version=29');
      await db.close();
      final raw = sqlite.sqlite3.open('${dir.path}/db.sqlite');
      raw.execute('CREATE INDEX active_plan_pointers ON local_owners(id)');
      raw.close();
      db = AppDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      await db.close();
      final inspect = sqlite.sqlite3.open('${dir.path}/db.sqlite');
      try {
        expect(
          inspect.select('PRAGMA user_version').single['user_version'],
          29,
        );
        expect(
          inspect.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='study_plan_revisions'",
          ),
          isEmpty,
        );
        inspect.execute('DROP INDEX active_plan_pointers');
      } finally {
        inspect.close();
      }
      db = AppDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
      repo = DriftStudyPlanRepository(db, nowUtc: () => now);
      expect(await repo.history('a'), isEmpty);
      expect((await db.select(db.localOwners).get()).length, 2);
    },
  );
}
