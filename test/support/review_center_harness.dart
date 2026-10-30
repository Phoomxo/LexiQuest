import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/data/drift_review_center_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/review_center_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/saved_words_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/application/word_report_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_saved_words_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart';
export 'package:vocab_learning_app/features/progress/domain/review_center_models.dart';

final class ReviewCenterHarness {
  ReviewCenterHarness._(this.database) : _ioZone = Zone.current {
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-review-created-owner',
      nowUtc: () => now,
    );
    ownerWrites = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => now,
      nonceGenerator: () => 'synthetic-review-nonce-${++_sequence}',
    );
    progressQueries = DriftProgressQueries(database);
    progress = ProgressUseCases(
      owners: owners,
      queries: progressQueries,
      nowUtc: () => now,
    );
    savedWords = SavedWordsUseCases(
      repository: DriftSavedWordsRepository(database, ownerWrites: ownerWrites),
      generateId: () => 'synthetic-review-save-${++_sequence}',
      nowUtc: () => now,
    );
    wordReports = WordReportUseCases(
      repository: DriftWordReportRepository(
        database: database,
        ownerWriteCoordinator: ownerWrites,
      ),
      generateId: () => 'synthetic-review-report-${++_sequence}',
      nowUtc: () => now,
    );
    queries = DriftReviewCenterQueries(database);
    learningRepository = DriftLearningRepository(
      database,
      ownerWrites: ownerWrites,
    );
    learning = LearningUseCases(
      owners: owners,
      repository: learningRepository,
      generateId: () => 'synthetic-review-learning-${++_sequence}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'review-test'),
    );
    ownerChanges = _inZone(_ioZone, progress.watchActiveOwnerId);
    reviewCenter = compose();
  }

  static Future<ReviewCenterHarness> open({
    drift.QueryInterceptor? interceptor,
    bool seed = true,
  }) async {
    final executor = NativeDatabase.memory();
    final result = ReviewCenterHarness._(
      db.AppDatabase(
        interceptor == null ? executor : executor.interceptWith(interceptor),
      ),
    );
    if (seed) await result._seed();
    return result;
  }

  final db.AppDatabase database;
  final Zone _ioZone;
  late final DriftLocalOwnerRepository owners;
  late final DriftOwnerWriteCoordinator ownerWrites;
  late final DriftProgressQueries progressQueries;
  late final ProgressUseCases progress;
  late final SavedWordsUseCases savedWords;
  late final WordReportUseCases wordReports;
  late final DriftReviewCenterQueries queries;
  late final ReviewCenterUseCases reviewCenter;
  late final DriftLearningRepository learningRepository;
  late final LearningUseCases learning;
  late final Stream<String?> ownerChanges;
  DateTime now = configuredStart;
  bool current = true;
  int _sequence = 0;
  bool _closed = false;

  ReviewCenterUseCases compose({
    DriftReviewCenterQueries? queries,
    SavedWordsUseCases? savedWords,
    WordReportUseCases? wordReports,
  }) => _IoReviewCenterUseCases(
    ioZone: _ioZone,
    queries: queries ?? this.queries,
    progress: progress,
    savedWords: savedWords ?? this.savedWords,
    wordReports: wordReports ?? this.wordReports,
    nowUtc: () => now,
  );

  Future<void> switchOwner(String ownerId) => database
      .customUpdate(
        'UPDATE local_owners SET is_active = (id = ?)',
        variables: [drift.Variable<String>(ownerId)],
        updates: {database.localOwners},
      )
      .then((_) {});

  Future<void> seedDue(
    String wordId, {
    String ownerId = configuredOwnerId,
    DateTime? dueAtUtc,
  }) => database
      .customInsert(
        'INSERT INTO srs_states '
        '(id,owner_id,word_id,due_at_utc_ms,algorithm_version) VALUES (?,?,?,?,1) '
        'ON CONFLICT(owner_id,word_id) DO UPDATE SET due_at_utc_ms=excluded.due_at_utc_ms',
        variables: [
          drift.Variable<String>('synthetic-review-due:$wordId'),
          drift.Variable<String>(ownerId),
          drift.Variable<String>(wordId),
          drift.Variable<int>(
            (dueAtUtc ?? now.subtract(const Duration(seconds: 1)))
                .millisecondsSinceEpoch,
          ),
        ],
        updates: {database.srsStates},
      )
      .then((_) {});

  Future<void> seedWrong({
    String? wordId,
    String ownerId = configuredOwnerId,
    String? sessionId,
    String promptMode = 'meaningChoice',
    String evidenceClass = 'independentRecall',
    String? evidenceContextJson,
    String activityType = 'quiz',
    DateTime? occurredAtUtc,
    bool isCorrect = false,
  }) async {
    final id = sessionId ?? 'synthetic-historical-session-${++_sequence}';
    final at = occurredAtUtc ?? now;
    await database.customInsert(
      'INSERT OR IGNORE INTO learning_sessions '
      '(id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) '
      "VALUES (?,?,?,'completed',?,?,'synthetic','historical-review-fixture')",
      variables: [
        drift.Variable<String>(id),
        drift.Variable<String>(ownerId),
        drift.Variable<String>(activityType),
        drift.Variable<int>(at.millisecondsSinceEpoch),
        drift.Variable<int>(at.millisecondsSinceEpoch),
      ],
      updates: {database.learningSessions},
    );
    final context =
        evidenceContextJson ??
        jsonEncode(
          EvidenceContext.forNewEvidence(
            evidenceClass: EvidenceClass.values.byName(evidenceClass),
            skillId: 'synthetic-review-history',
            hintLevel: 0,
            contentRevision: 'synthetic-review-r1',
            rolloutMode: EvidencePolicyRolloutMode.legacy,
            engagementAllowed: evidenceClass != 'recreational',
          ).toJson(),
        );
    await database.customInsert(
      'INSERT INTO answer_attempts '
      '(id,owner_id,session_id,word_id,prompt_mode,is_correct,attempt_number,occurred_at_utc_ms,evidence_class,evidence_context_json) '
      'VALUES (?,?,?,?,?,?,1,?,?,?)',
      variables: [
        drift.Variable<String>('synthetic-historical-answer-${++_sequence}'),
        drift.Variable<String>(ownerId),
        drift.Variable<String>(id),
        drift.Variable<String>(wordId ?? configuredWordIds.first),
        drift.Variable<String>(promptMode),
        drift.Variable<bool>(isCorrect),
        drift.Variable<int>(at.millisecondsSinceEpoch),
        drift.Variable<String>(evidenceClass),
        drift.Variable<String>(context),
      ],
      updates: {database.answerAttempts},
    );
  }

  Future<void> addWord({
    required String id,
    required String spelling,
    required String meaning,
    String ownerId = configuredOwnerId,
    String categoryId = configuredCategoryId,
  }) => database
      .into(database.vocabularyWords)
      .insert(
        db.VocabularyWordsCompanion.insert(
          id: id,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: spelling,
          normalizedSpelling: spelling.toLowerCase(),
          meaning: meaning,
          normalizedMeaning: meaning.toLowerCase(),
          partOfSpeech: 'noun',
          createdAtUtcMs: now.millisecondsSinceEpoch,
          updatedAtUtcMs: now.millisecondsSinceEpoch,
        ),
      )
      .then((_) {});

  Future<VocabularyWord> word(String id) async {
    final row = await (database.select(
      database.vocabularyWords,
    )..where((row) => row.id.equals(id))).getSingle();
    return VocabularyWord(
      id: row.id,
      ownerId: row.ownerId,
      categoryId: row.categoryId,
      spelling: row.spelling,
      normalizedSpelling: row.normalizedSpelling,
      meaning: row.meaning,
      normalizedMeaning: row.normalizedMeaning,
      partOfSpeech: row.partOfSpeech,
      cefrLevel: row.cefrLevel,
      source: row.source,
      isGlobal: row.isGlobal,
      localRevision: row.localRevision,
      isDeleted: row.isDeleted,
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.createdAtUtcMs,
        isUtc: true,
      ),
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.updatedAtUtcMs,
        isUtc: true,
      ),
    );
  }

  Future<StoredSavedWordState> save(
    String wordId, {
    bool isSaved = true,
  }) async {
    final snapshot = await savedWords.watchOwner(configuredOwnerId).first;
    final result = await savedWords.apply(
      savedWords.prepareSet(
        state: snapshot.stateFor(wordId),
        desiredIsSaved: isSaved,
      ),
    );
    return result.state as StoredSavedWordState;
  }

  Future<StoredWordReport> report(
    String wordId, {
    ReportReason reason = ReportReason.incorrectMeaning,
    String? comment,
  }) async => (await wordReports.submit(
    wordReports.prepareSubmit(
      expectedOwnerId: configuredOwnerId,
      target: WordReportTarget.fromWord(await word(wordId)),
      reason: reason,
      comment: comment,
    ),
  )).report;

  Future<Map<String, List<String>>> snapshotAllTables() async {
    final result = <String, List<String>>{};
    for (final table in database.allTables) {
      final rows = await database
          .customSelect('SELECT * FROM ${table.actualTableName}')
          .get();
      result[table.actualTableName] =
          rows.map((row) => jsonEncode(row.data)).toList()..sort();
    }
    return result;
  }

  Future<void> _seed() async {
    for (final pair in const [
      (configuredOwnerId, configuredCategoryId),
      (configuredOtherOwnerId, configuredOtherCategoryId),
    ]) {
      await database
          .into(database.localOwners)
          .insert(
            db.LocalOwnersCompanion.insert(
              id: pair.$1,
              isActive: drift.Value(pair.$1 == configuredOwnerId),
              createdAtUtcMs: now.millisecondsSinceEpoch,
            ),
          );
      await database
          .into(database.vocabularyCategories)
          .insert(
            db.VocabularyCategoriesCompanion.insert(
              id: pair.$2,
              ownerId: pair.$1,
              name: pair.$1 == configuredOwnerId
                  ? 'Synthetic travel'
                  : 'Synthetic other',
              normalizedName: pair.$1 == configuredOwnerId
                  ? 'synthetic travel'
                  : 'synthetic other',
              createdAtUtcMs: now.millisecondsSinceEpoch,
              updatedAtUtcMs: now.millisecondsSinceEpoch,
            ),
          );
    }
    for (var i = 0; i < configuredWordIds.length; i++) {
      await addWord(
        id: configuredWordIds[i],
        spelling: const ['station', 'ticket', 'platform', 'journey'][i],
        meaning: const ['สถานี', 'ตั๋ว', 'ชานชาลา', 'การเดินทาง'][i],
      );
    }
    await addWord(
      id: 'synthetic-configured-other-word',
      spelling: 'unrelated',
      meaning: 'ไม่เกี่ยวข้อง',
      ownerId: configuredOtherOwnerId,
      categoryId: configuredOtherCategoryId,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await database.close();
  }
}

final class _IoReviewCenterUseCases extends ReviewCenterUseCases {
  _IoReviewCenterUseCases({
    required this.ioZone,
    required super.queries,
    required super.progress,
    required super.savedWords,
    required super.wordReports,
    required super.nowUtc,
  });
  final Zone ioZone;
  @override
  Stream<ReviewCenterSnapshot> watchOwner({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => _inZone(
    ioZone,
    () => super.watchOwner(
      expectedOwnerId: expectedOwnerId,
      stillCurrent: stillCurrent,
    ),
  );
}

Stream<T> _inZone<T>(Zone zone, Stream<T> Function() create) =>
    Stream<T>.multi((events) {
      final subscription = zone.run(
        () => create().listen(
          events.add,
          onError: events.addError,
          onDone: events.close,
        ),
      );
      events.onCancel = () => zone.run(subscription.cancel);
    }, isBroadcast: true);
