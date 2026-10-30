import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart';

final class SrsReviewHarness {
  SrsReviewHarness._(this.storage, this.wordIds) {
    repository = DriftLearningRepository(
      database,
      ownerWrites: storage.ownerWrites,
    );
    ownerChanges = ProgressUseCases(
      owners: storage.owners,
      queries: DriftProgressQueries(database),
      nowUtc: () => now,
    ).watchActiveOwnerId();
  }

  final ConfiguredQuizHarness storage;
  final List<String> wordIds;
  late final DriftLearningRepository repository;
  late LearningUseCases learning;
  late final Stream<String?> ownerChanges;
  bool current = true;
  int notifications = 0;
  int questEvents = 0;
  int streakEvents = 0;
  int _sequence = 0;
  final notificationTransactions = <bool?>[];
  final _notificationProbes = <Future<void>>[];

  AppDatabase get database => storage.database;
  DateTime get now => storage.now;
  set now(DateTime value) => storage.now = value;

  static Future<SrsReviewHarness> open({
    int wordCount = 2,
    bool due = true,
    LearningRepository Function(DriftLearningRepository)? decorate,
  }) async {
    if (wordCount < 1 || wordCount > 20) {
      throw ArgumentError.value(wordCount, 'wordCount');
    }
    final storage = await ConfiguredQuizHarness.open();
    final ids = configuredWordIds.take(wordCount).toList();
    for (var i = ids.length; i < wordCount; i++) {
      final id = 'synthetic-srs-word-${(i + 1).toString().padLeft(2, '0')}';
      await storage.addWord(
        id: id,
        spelling: 'syntheticword${i + 1}',
        meaning: 'synthetic meaning ${i + 1}',
      );
      ids.add(id);
    }
    ids.sort();
    final result = SrsReviewHarness._(storage, List<String>.unmodifiable(ids));
    if (due) {
      for (var i = 0; i < ids.length; i++) {
        await result.database.customStatement(
          'INSERT INTO srs_states '
          '(id,owner_id,word_id,due_at_utc_ms,algorithm_version) '
          'VALUES (?,?,?,?,1)',
          [
            'synthetic-due:${ids[i]}',
            configuredOwnerId,
            ids[i],
            configuredStart.millisecondsSinceEpoch - 1000 + i,
          ],
        );
      }
    }
    result.learning = result.useCases(
      repository: decorate?.call(result.repository),
    );
    return result;
  }

  LearningUseCases useCases({LearningRepository? repository}) {
    final ioZone = Zone.current;
    return LearningUseCases(
      owners: storage.owners,
      repository: repository ?? this.repository,
      generateId: () => 'synthetic-srs-${++_sequence}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'srs-test'),
      eventAdapter: const EventV1ToV2Adapter(
        appVersion: '1.0.0',
        buildId: 'srs-test',
      ),
      onLocalMutation: () {
        final probeZone = Zone.current.fork(
          specification: ZoneSpecification(
            scheduleMicrotask: (self, parent, zone, callback) =>
                ioZone.scheduleMicrotask(zone.bindCallback(callback)),
            createTimer: (self, parent, zone, duration, callback) =>
                ioZone.createTimer(duration, zone.bindCallback(callback)),
            createPeriodicTimer: (self, parent, zone, duration, callback) =>
                ioZone.createPeriodicTimer(
                  duration,
                  zone.bindUnaryCallback(callback),
                ),
          ),
        );
        probeZone.run(() {
          notifications++;
          final probe = SrsExecutorProbe();
          _notificationProbes.add(
            database.runWithInterceptor(() async {
              await database
                  .customSelect('SELECT 1 AS srs_notification')
                  .getSingle();
              notificationTransactions.add(probe.insideTransaction);
            }, interceptor: probe),
          );
        });
      },
      questEventSink: (_) async {
        questEvents++;
      },
      streakEventSink: () async {
        streakEvents++;
      },
    );
  }

  Future<SrsReviewSession?> prepare({
    bool source = false,
    Iterable<String>? sourceWordIds,
    String ownerId = configuredOwnerId,
    int limit = 20,
  }) => learning.prepareSrsReview(
    expectedOwnerId: ownerId,
    sourceWordIds: sourceWordIds ?? (source ? wordIds : null),
    limit: limit,
    stillCurrent: () => current,
  );

  Future<SrsReviewSession> ready({
    bool source = false,
    Iterable<String>? sourceWordIds,
  }) async {
    final review = await prepare(source: source, sourceWordIds: sourceWordIds);
    if (review == null) throw StateError('Synthetic SRS deck unavailable');
    return learning.startSrsReview(review, stillCurrent: () => current);
  }

  SrsReviewAnswerIntent answer(
    SrsReviewSession review, {
    int cardIndex = 0,
    bool recalled = true,
    int? responseTimeMs = 1234,
  }) => learning.prepareSrsRating(
    review: review,
    cardIndex: cardIndex,
    recalled: recalled,
    responseTimeMs: responseTimeMs,
  );

  Future<void> settleNotifications() async {
    while (_notificationProbes.isNotEmpty) {
      final pending = List<Future<void>>.of(_notificationProbes);
      _notificationProbes.clear();
      await Future.wait(pending);
    }
  }

  Future<void> close() async {
    await settleNotifications();
    await storage.close();
  }
}

final class SrsExecutorProbe extends drift.QueryInterceptor {
  bool? insideTransaction;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    insideTransaction = executor is drift.TransactionExecutor;
    return executor.runSelect(statement, args);
  }
}
