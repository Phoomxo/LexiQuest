import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_progress_reader.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_progress_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

final _at = DateTime.utc(2027, 1, 5, 12);
final _asOf = _at.add(const Duration(seconds: 1));

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'progress binds the exact owner and asOf even without a Quest section',
    () async {
      final database = _memory();
      await _seed(database);
      final snapshot = await DriftProgressQueries(
        database,
      ).load(ownerId: 'owner-a', nowUtc: _asOf);
      expect(snapshot.ownerId, 'owner-a');
      expect(snapshot.asOfUtc, _asOf);
      expect(snapshot.quests, isNull);
      expect(snapshot.sampleSize, 0);
    },
  );

  test(
    'fresh current Quest cards and repeated progress loads create no rows',
    () async {
      final database = _memory();
      final catalog = await _seed(database);
      final queries = DriftProgressQueries(
        database,
        questReader: DriftQuestProgressReader(database, catalog: catalog),
        questVisible: () => true,
      );
      final before = await _rows(database);
      for (var i = 0; i < 2; i++) {
        final view = await queries.load(ownerId: 'owner-a', nowUtc: _asOf);
        expect(view.ownerId, 'owner-a');
        expect(view.asOfUtc, _asOf);
        expect(view.quests!.current.map((card) => card.cadence).toSet(), {
          QuestType.daily,
          QuestType.weekly,
        });
        expect(
          view.quests!.current.every(
            (card) =>
                card.correctCount == 0 &&
                card.state == QuestProgressState.active,
          ),
          isTrue,
        );
      }
      expect(await _rows(database), before);
      expect(
        await database.select(database.ownerCalendarEpochs).get(),
        isEmpty,
      );
      expect(await database.select(database.questInstances).get(), isEmpty);
    },
  );

  test(
    'hidden section stays absent while unavailable catalog is explicit',
    () async {
      final database = _memory();
      final catalog = await _seed(database);
      final before = await _rows(database);
      final hidden = await DriftProgressQueries(
        database,
        questReader: DriftQuestProgressReader(database, catalog: catalog),
        questVisible: () => false,
      ).load(ownerId: 'owner-a', nowUtc: _asOf);
      expect(hidden.quests, isNull);
      final unavailable = await DriftProgressQueries(
        database,
        questReader: DriftQuestProgressReader(database),
        questVisible: () => true,
      ).load(ownerId: 'owner-a', nowUtc: _asOf);
      expect(
        unavailable.quests!.issues,
        contains(QuestProgressIssue.unavailableCatalog),
      );
      expect(unavailable.ownerId, 'owner-a');
      expect(await _rows(database), before);
    },
  );

  test(
    'progress exposes actual completed then claimed Quest with the same XP authority',
    () async {
      final database = _memory();
      final catalog = await _seed(database);
      final learning = DriftLearningRepository(
        database,
        questCatalog: catalog,
        questVisible: () => true,
      );
      for (var i = 0; i < 5; i++) {
        await learning.recordAnswer(_answer('answer-$i', i));
      }
      final queries = DriftProgressQueries(
        database,
        questReader: DriftQuestProgressReader(database, catalog: catalog),
        questVisible: () => true,
      );
      final completed = await queries.load(ownerId: 'owner-a', nowUtc: _asOf);
      final card = completed.quests!.current.singleWhere(
        (card) => card.cadence == QuestType.daily,
      );
      expect(
        (completed.totalXp, card.correctCount, card.state),
        (5, 5, QuestProgressState.completedUnclaimed),
      );
      final rewards = DriftRewardRepository(
        database,
        questCatalog: catalog,
        questVisible: () => true,
        nowUtc: () => _asOf,
      );
      await rewards.claimQuest(
        expectedOwnerId: completed.ownerId!,
        instanceId: card.instanceId,
      );
      final afterClaim = await _rows(database);
      final claimed = await queries.load(ownerId: 'owner-a', nowUtc: _asOf);
      expect(claimed.totalXp, 55);
      expect(
        claimed.quests!.current
            .singleWhere((card) => card.cadence == QuestType.daily)
            .state,
        QuestProgressState.claimed,
      );
      expect(await _rows(database), afterClaim);
      expect((await rewards.load('owner-a')).balance, 5);
    },
  );

  test(
    'one progress load cannot mix old answer count with a concurrently committed XP grant',
    () async {
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-snapshot-',
      );
      final ownedPath = await directory.resolveSymbolicLinks();
      final boundary = _AfterAnswerRead();
      final file = File('$ownedPath${Platform.pathSeparator}progress.sqlite');
      final reader = AppDatabase(NativeDatabase(file).interceptWith(boundary));
      final writer = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await reader.close();
        await writer.close();
        expect(
          ownedPath.startsWith(
            '$tempRoot${Platform.pathSeparator}lexiquest-snapshot-',
          ),
          isTrue,
        );
        await Directory(ownedPath).delete(recursive: true);
      });
      await _seed(reader);
      await writer.customSelect('SELECT 1').get();
      Future<AnswerRecordResult>? pending;
      boundary.afterRead = () async {
        pending = DriftLearningRepository(
          writer,
        ).recordAnswer(_answer('concurrent', 0));
        await Future.any<void>([
          pending!.then((_) {}),
          Future<void>.delayed(const Duration(milliseconds: 150)),
        ]);
      };
      boundary.armed = true;
      final queries = DriftProgressQueries(reader);
      final first = await queries.load(ownerId: 'owner-a', nowUtc: _asOf);
      expect(
        boundary.fired,
        isTrue,
        reason: 'The concurrent write must actually overlap a progress read',
      );
      await pending!;
      expect((first.sampleSize, first.totalXp), (0, 0));
      final second = await queries.load(ownerId: 'owner-a', nowUtc: _asOf);
      expect((second.sampleSize, second.totalXp), (1, 1));
    },
  );
}

AppDatabase _memory() {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<TrustedQuestAnswerCatalog> _seed(AppDatabase database) async {
  await database.customStatement(
    "INSERT INTO local_owners(id,account_state,created_at_utc_ms,is_active) VALUES ('owner-a','localGuest',1,1)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('category','owner-a','Synthetic','synthetic',1,1)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,source,created_at_utc_ms,updated_at_utc_ms) VALUES ('word','owner-a','category','station','station','สถานี','สถานี','noun','manual',1,1)",
  );
  await DriftLearningRepository(database).startSession(
    LearningSessionDraft(
      id: 'session',
      ownerId: 'owner-a',
      activityType: 'quiz',
      startedAtUtc: _at,
      appVersion: 'test',
      buildId: 'synthetic',
    ),
  );
  return DriftQuestRepository(database).installAnswerCatalog();
}

RecordAnswerCommand _answer(String id, int index) => RecordAnswerCommand(
  id: id,
  ownerId: 'owner-a',
  sessionId: 'session',
  wordId: 'word',
  promptMode: 'meaningChoice',
  isCorrect: true,
  responseTimeMs: 10,
  attemptNumber: index + 1,
  occurredAtUtc: _at.add(Duration(milliseconds: index)),
);

Future<Map<String, List<Map<String, Object?>>>> _rows(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName: [
      for (final row
          in await database
              .customSelect(
                'SELECT * FROM ${table.actualTableName} ORDER BY rowid',
              )
              .get())
        Map<String, Object?>.from(row.data),
    ],
};

final class _AfterAnswerRead extends QueryInterceptor {
  bool armed = false, fired = false;
  Future<void> Function()? afterRead;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (armed &&
        !fired &&
        statement.toLowerCase().contains('answer_attempts')) {
      fired = true;
      await afterRead!();
    }
    return rows;
  }
}
