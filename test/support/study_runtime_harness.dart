import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/local_study_runtime.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/ed25519_research_permit_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_runtime_availability.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import 'research_participation_harness.dart';

export 'research_participation_harness.dart'
    show participationStart, participationPermit, participationOperation;

const studyEntryId = '00000000-0000-4000-8000-000000000091';
const otherStudyEntryId = '00000000-0000-4000-8000-000000000092';
const studyCategoryId = 'synthetic-study-category';
const studyWordId = 'synthetic-study-word';

final class StudyRuntimeFixture {
  StudyRuntimeFixture(this.participation);
  final ParticipationFixture participation;
  late LocalStudyRuntime runtime;
  late LearningUseCases learning;
  late DriftLearningRepository repository;
  late DriftLocalOwnerRepository owners;
  late StudyLocalAuthorities authorities;
  late StudyPresentationCatalog catalog;
  int _nextId = 0;
  int learningGetterCalls = 0;
  void Function()? onLocalMutation;

  AppDatabase get database => participation.database;
  String get ownerId => 'owner-a';

  static Future<StudyRuntimeFixture> open({
    AppDatabase? database,
    bool seed = true,
    bool admitted = true,
    bool longLived = false,
    bool enabled = true,
    TodayExperiencePresentation treatment =
        TodayExperiencePresentation.standard,
    Set<TodayExperiencePresentation> presentations = const {
      TodayExperiencePresentation.standard,
      TodayExperiencePresentation.adventure,
    },
  }) async {
    final p = await ParticipationFixture.open(database: database, seed: seed);
    if (longLived || treatment != TodayExperiencePresentation.standard) {
      p.use(
        participationPermit(
          treatment: treatment,
          expiresAtUtc: longLived
              ? participationStart.add(const Duration(days: 2))
              : null,
        ),
      );
    }
    if (longLived) {
      p.operations.current = participationOperation(
        expiresAtUtc: participationStart.add(const Duration(days: 2)),
      );
    }
    if (seed) {
      await p.database.customStatement(
        'INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) '
        'VALUES (?, ?, ?, ?, 1, 1)',
        [studyCategoryId, 'owner-a', 'Synthetic study', 'synthetic study'],
      );
      for (final word in [
        (studyWordId, 'station', 'สถานี'),
        ('synthetic-study-distractor', 'river', 'แม่น้ำ'),
      ]) {
        await p.database.customStatement(
          'INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
          [
            word.$1,
            'owner-a',
            studyCategoryId,
            word.$2,
            word.$2,
            word.$3,
            word.$3,
            'noun',
          ],
        );
      }
      if (admitted && !await p.importCurrent()) {
        throw StateError('Signed synthetic admission failed');
      }
    }
    final result = StudyRuntimeFixture(p);
    final study = p.assignments.binding.study;
    final pins = p.assignments.authorizer.requirements;
    result.authorities = StudyLocalAuthorities(
      binding: p.assignments.binding,
      permits: p.operations,
      states: p.states,
      operationSignatures:
          p.assignments.authorizer.verifier
              as Ed25519ResearchPermitSignatureVerifier,
      participationDocuments: p.documents,
      participationSignatures:
          p.assignments.participationValidator.signatures
              as ResearchP256SignatureVerifier,
      receipts: p.receipts,
      trustedTime: p.clock,
      supportedFormatVersion: pins.supportedFormatVersion,
      trustedIssuerId: pins.trustedIssuerId,
      trustedIssuerKeyId: pins.trustedIssuerKeyId,
      availability: enabled
          ? ResearchRuntimeAvailability.syntheticComplete
          : ResearchRuntimeAvailability.disabled,
      supportedPresentations: presentations,
    );
    result.catalog = StudyPresentationCatalog(
      version: study.catalogVersion,
      missionId: 'synthetic-meaning-mission',
      titles: const {'th': 'ภารกิจสังเคราะห์', 'en': 'Synthetic mission'},
      descriptions: const {
        'th': 'แบบฝึกทดสอบสังเคราะห์',
        'en': 'Synthetic practice',
      },
      configuration: QuizConfiguration.sourcePractice(
        wordIds: [studyWordId],
        limit: 1,
      ),
    );
    result.owners = DriftLocalOwnerRepository(
      p.database,
      generateId: () => 'owner-fixture-${result._nextId++}',
      nowUtc: () => p.clock.now,
    );
    result.runtime = result.newRuntime();
    result.bindLearning();
    return result;
  }

  LocalStudyRuntime newRuntime() => LocalStudyRuntime(
    context: StudyRuntimeContext(
      database: database,
      owners: owners,
      ownerWrites: participation.ownerWrites,
      consentRepository: participation.consent,
      generateId: () => 'study-${_nextId++}',
      nowUtc: () => participation.clock.now,
      buildInfo: AppBuildInfo(
        version: participation.assignments.binding.study.appVersion,
        buildId: participation.assignments.binding.study.buildId,
      ),
      getLearning: () {
        learningGetterCalls++;
        return learning;
      },
    ),
    authorities: authorities,
    catalog: catalog,
  );

  void bindLearning() {
    repository = DriftLearningRepository(
      database,
      ownerWrites: participation.ownerWrites,
      lifecycleObserver: runtime.lifecycleObserver,
    );
    learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'study-${_nextId++}',
      nowUtc: () => participation.clock.now,
      buildInfo: runtime.context.buildInfo,
      onLocalMutation: () => onLocalMutation?.call(),
    );
  }

  void restartRuntime() {
    runtime = newRuntime();
    bindLearning();
  }

  Future<StudyView> baseline() async {
    final opened = await runtime.begin(ownerId);
    await runtime
        .measurementsFor(ownerId)
        .record(
          MotivationResponse(
            ownerId: ownerId,
            runId: opened.run!.id,
            itemId: 'synthetic-baseline',
            responseCode: 'high',
          ),
        );
    return runtime.load(ownerId);
  }

  Future<StudyView> ready() async {
    await baseline();
    participation.clock.now = participationStart.add(
      const Duration(minutes: 1),
    );
    final opened = await runtime.openPresentation(
      ownerId,
      entryAttemptId: studyEntryId,
      stillCurrent: () => true,
    );
    runtime.markPresentationMayRender(
      ownerId,
      opened.opportunity!.id,
      entryAttemptId: studyEntryId,
    );
    return runtime.recordPresented(
      ownerId,
      opened.opportunity!.id,
      entryAttemptId: studyEntryId,
      stillVisible: () => true,
    );
  }

  Future<ConfiguredQuizState> start() async {
    final view = await ready();
    participation.clock.now = participationStart.add(
      const Duration(minutes: 2),
    );
    return runtime.startIndex(
      ownerId,
      view.opportunity!.id,
      stillVisible: () => true,
    );
  }

  Future<ConfiguredQuizState> finish(ConfiguredQuizState state) async {
    participation.clock.now = participationStart.add(
      const Duration(minutes: 3),
    );
    final question = state.plan.questions.single;
    final wrong = question.options.indexWhere(
      (option) => option != question.correctAnswer,
    );
    var saved = await learning.prepareQuizAnswer(
      sessionId: state.sessionId,
      expectedOwnerId: ownerId,
      expectedRevision: state.checkpointRevision,
      selectedOptionOrdinal: wrong,
      responseTimeMs: 25,
    );
    saved = (await learning.commitQuizAnswer(
      sessionId: saved.sessionId,
      expectedOwnerId: ownerId,
      expectedRevision: saved.checkpointRevision,
    )).state;
    saved = await learning.prepareQuizFinish(
      sessionId: saved.sessionId,
      expectedOwnerId: ownerId,
      expectedRevision: saved.checkpointRevision,
    );
    return (await learning.finishConfiguredQuiz(
      sessionId: saved.sessionId,
      expectedOwnerId: ownerId,
      expectedRevision: saved.checkpointRevision,
    )).state;
  }

  Future<void> switchOwner() async {
    await database.customStatement(
      "UPDATE local_owners SET is_active = CASE WHEN id = 'owner-b' THEN 1 ELSE 0 END",
    );
  }

  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row
        in await database.customSelect('SELECT * FROM $table ORDER BY 1').get())
      row.data,
  ];

  Future<Map<String, List<Map<String, Object?>>>> researchRows() async => {
    for (final table in [
      'local_owners',
      'research_consents',
      'experiment_assignments',
      'research_participation_permits',
      'motivation_measurement_runs',
      'motivation_responses',
      'measurement_opportunities',
      'events_v2',
      'learning_sessions',
      'answer_attempts',
      'outbox_operations',
      'runtime_flags',
    ])
      table: await rows(table),
  };
}

final class StudyReadQueries extends drift.QueryInterceptor {
  bool rejectWrites = false;
  Future<void> Function()? afterOpportunityInsert;
  void Function(drift.QueryExecutor executor, String statement)? afterSelect;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    afterSelect?.call(executor, statement);
    return rows;
  }

  @override
  Future<void> runCustom(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    _check(statement);
    await executor.runCustom(statement, args);
    if (RegExp(
      r'^\s*INSERT INTO measurement_opportunities\b',
      caseSensitive: false,
    ).hasMatch(statement)) {
      await afterOpportunityInsert?.call();
    }
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(statement);
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(statement);
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _check(statement);
    return executor.runDelete(statement, args);
  }

  void _check(String statement) {
    if (rejectWrites &&
        RegExp(
          r'^\s*(INSERT|UPDATE|DELETE|REPLACE)\b',
          caseSensitive: false,
        ).hasMatch(statement)) {
      throw StateError('Read-only study load attempted SQL mutation');
    }
  }
}
