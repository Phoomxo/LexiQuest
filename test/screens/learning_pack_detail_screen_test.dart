import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_detail_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_detail.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/review/application/learner_intent_use_cases.dart';
import 'package:vocab_learning_app/features/review/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/review/data/drift_content_quality_report_repository.dart';
import 'package:vocab_learning_app/features/review/data/drift_learner_intent_repository.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report_repository.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent_repository.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/learning_pack_detail_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/widgets/rich_lexical_card.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  test(
    'runtime quiz delivery requires the canonical evidence gateway',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final learning = LearningUseCases(
        owners: _Owner(),
        repository: DriftLearningRepository(database),
        generateId: () => 'unused-learning-id',
        nowUtc: () => DateTime.utc(2026, 8, 25),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'pack-detail'),
      );

      final missingGateway = _dependencies(database, learning: learning);
      final complete = _dependencies(
        database,
        learning: learning,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
      );
      final otherLearning = LearningUseCases(
        owners: _Owner(),
        repository: DriftLearningRepository(database),
        generateId: () => 'other-learning-id',
        nowUtc: () => DateTime.utc(2026, 8, 25),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'pack-detail-other',
        ),
      );
      final mismatchedGateway = _dependencies(
        database,
        learning: learning,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: otherLearning,
        ),
      );

      expect(missingGateway.hasComposedDependencyFor(Feature.quiz), isFalse);
      expect(mismatchedGateway.hasComposedDependencyFor(Feature.quiz), isFalse);
      expect(complete.hasComposedDependencyFor(Feature.quiz), isTrue);
    },
  );

  testWidgets(
    'renders pinned content, canonical progress, and accessible activity availability',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: _useCases(database),
            vocabulary: _vocabulary(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel('Travel basics, A1, revision 2'),
        findsOneWidget,
      );
      expect(find.byType(RichLexicalCard), findsNWidgets(2));
      expect(find.text('station'), findsOneWidget);
      expect(find.text('market'), findsOneWidget);
      expect(find.text('Completed sessions: 0'), findsOneWidget);
      final scrollable = find.byType(Scrollable);
      await tester.scrollUntilVisible(
        find.text('Meaning quiz'),
        200,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Meaning quiz: Available'), findsOneWidget);
      expect(find.text('Matching'), findsNothing);
      expect(find.bySemanticsLabel('Matching: Unavailable'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Flashcards'),
        -200,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Flashcards: Available'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Associative reading'),
        -200,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel('Associative reading: Available'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'renders a typed unavailable state for an invalid pinned revision',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 99,
            useCases: _useCases(
              database,
              failure: const ContentQualityFailure(
                ContentQualityFailureCode.checksumMismatch,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LearningPackDetailUnavailable), findsOneWidget);
      expect(find.text('word:station'), findsNothing);
    },
  );

  testWidgets(
    'fails closed when canonical vocabulary authority is unavailable',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: _useCases(database),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LearningPackDetailUnavailable), findsOneWidget);
      expect(find.byType(RichLexicalCard), findsNothing);
    },
  );

  testWidgets(
    'production pack detail save is idempotent and does not mutate weakness',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 24, 10);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'detail-save-owner',
        nowUtc: () => now,
      );
      await owners.getOrCreateActiveOwner();
      final repository = DriftLearnerIntentRepository(
        database,
        owners: owners,
        nowUtc: () => now,
      );
      var nextId = 0;
      final bookmark = LearnerIntentUseCases(
        repository: repository,
        generateId: () => 'detail-save-${++nextId}',
        nowUtc: () => now,
      ).bookmark;
      final weaknessCountBefore = await database
          .select(database.srsStates)
          .get()
          .then((rows) => rows.length);

      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(
            database,
            learnerIntents: repository,
            bookmarkLearningItem: bookmark,
          ),
          child: MaterialApp(
            home: LearningPackDetailScreen(
              packId: 'pack:travel',
              revision: 2,
              useCases: _useCases(database),
              vocabulary: _vocabulary(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save for review').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save for review').first);
      await tester.pumpAndSettle();

      final saved = await database.select(database.savedLearningItems).get();
      final outbox = await (database.select(
        database.outboxOperations,
      )..where((row) => row.entityType.equals('savedLearningItem'))).get();
      final weaknessCountAfter = await database
          .select(database.srsStates)
          .get()
          .then((rows) => rows.length);
      expect(saved, hasLength(1));
      expect(saved.single.contentType, ContentType.lexicalMetadata.name);
      expect(saved.single.contentId, 'word:station');
      expect(saved.single.contentRevision, 1);
      expect(outbox, hasLength(1));
      expect(weaknessCountAfter, weaknessCountBefore);
    },
  );

  testWidgets(
    'production pack detail report is single-flight and does not mutate learning',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 24, 10);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'detail-report-owner',
        nowUtc: () => now,
      );
      final owner = await owners.getOrCreateActiveOwner();
      await DriftResearchConsentRepository(database).decide(
        ownerId: owner.id,
        version: 1,
        accepted: true,
        decidedAtUtc: now.subtract(const Duration(minutes: 1)),
      );
      final repository = DriftContentQualityReportRepository(
        database,
        owners: owners,
        consentRegistry: DriftConsentRegistry(database),
        uploadPolicy: const ContentReportUploadPolicy.v1(
          deployedRulesRevision: contentQualityReportV1RulesRevision,
          consentVersion: 1,
        ),
      );
      var nextId = 0;
      final report = ContentReportUseCases(
        repository: repository,
        generateId: () => 'detail-report-${++nextId}',
        nowUtc: () => now,
      ).report;
      final before = (
        content: await database.select(database.vocabularyWords).get(),
        weakness: await database.select(database.srsStates).get(),
      );

      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(
            database,
            contentQualityReports: repository,
            reportContent: report,
          ),
          child: MaterialApp(
            home: LearningPackDetailScreen(
              packId: 'pack:travel',
              revision: 2,
              useCases: _useCases(database),
              vocabulary: _vocabulary(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Report content').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Text problem'));
      await tester.pump();
      await tester.tap(find.text('Submit report'));
      await tester.tap(find.text('Submit report'), warnIfMissed: false);
      await tester.pumpAndSettle();

      final reports = await database
          .select(database.contentQualityReports)
          .get();
      final outbox = await (database.select(
        database.outboxOperations,
      )..where((row) => row.entityType.equals('contentQualityReport'))).get();
      expect(reports, hasLength(1));
      expect(reports.single.contentType, ContentType.lexicalMetadata.name);
      expect(reports.single.contentId, 'word:station');
      expect(reports.single.contentRevision, 1);
      expect(outbox, hasLength(1));
      expect(
        await database.select(database.vocabularyWords).get(),
        before.content,
      );
      expect(await database.select(database.srsStates).get(), before.weakness);
    },
  );
}

AppDependencies _dependencies(
  AppDatabase database, {
  LearningUseCases? learning,
  CurrentActivityEvidenceAdapter? currentActivityEvidence,
  LearnerIntentRepository? learnerIntents,
  BookmarkLearningItemAction? bookmarkLearningItem,
  ContentQualityReportRepository? contentQualityReports,
  ReportContentAction? reportContent,
}) {
  final research = InertResearchDependencies(database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _GuestSession(),
    quest: testQuestUseCases(),
    features: const BuildFeatureRegistry.allEnabled(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    learnerIntents: learnerIntents,
    bookmarkLearningItem: bookmarkLearningItem,
    contentQualityReports: contentQualityReports,
    reportContent: reportContent,
    learning: learning,
    currentActivityEvidence: currentActivityEvidence,
  );
}

VocabularyUseCases _vocabulary() => VocabularyUseCases(
  owners: _Owner(),
  vocabulary: _PinnedVocabulary(),
  generateId: () => 'unused',
  nowUtc: () => DateTime.utc(2026, 8, 24),
);

LearningPackDetailUseCases _useCases(
  AppDatabase database, {
  ContentQualityFailure? failure,
}) => LearningPackDetailUseCases(
  packs: _Packs(failure: failure),
  progress: ProgressUseCases(
    owners: _Owner(),
    queries: DriftProgressQueries(database),
    nowUtc: () => DateTime.utc(2026, 8, 24),
  ),
  lessonModes: buildLessonModeRegistry(),
  features: const BuildFeatureRegistry.allEnabled(),
  hasComposedDependency: (_) => true,
);

final class _Packs implements LearningPackRepository {
  const _Packs({this.failure});

  final ContentQualityFailure? failure;

  @override
  Future<LearningPackDetail> getVersion(String packId, int revision) async {
    final error = failure;
    if (error != null) throw error;
    return LearningPackDetail(
      summary: LearningPackSummary(
        packId: packId,
        revision: revision,
        title: 'Travel basics',
        cefrLevel: 'A1',
        topic: 'travel',
        skill: 'vocabulary',
        goal: 'recognition',
        contentIdentity: ContentIdentity(
          type: ContentType.learningPack,
          id: packId,
          revision: revision,
        ),
      ),
      vocabularyWordIds: const ['word:station', 'word:market'],
    );
  }

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async =>
      const [];
}

final class _Owner implements LocalOwnerRepository {
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner:detail-screen',
        createdAtUtc: DateTime.utc(2026, 8, 24),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'detail-save');
}

final class _PinnedVocabulary implements VocabularyRepository {
  @override
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> wordIds) async {
    final ids = wordIds.toList(growable: false);
    if (ids.any((id) => id != 'word:station' && id != 'word:market')) {
      throw StateError('Unknown pinned vocabulary identity.');
    }
    return ids
        .map(
          (id) => VocabularyWord(
            id: id,
            ownerId: 'packaged-owner',
            categoryId: 'category:pack',
            spelling: id == 'word:station' ? 'station' : 'market',
            normalizedSpelling: id == 'word:station' ? 'station' : 'market',
            meaning: id == 'word:station' ? 'สถานี' : 'ตลาด',
            normalizedMeaning: id == 'word:station' ? 'สถานี' : 'ตลาด',
            partOfSpeech: 'noun',
            cefrLevel: 'A1',
            source: 'pack:v2',
            isGlobal: true,
            localRevision: 1,
            isDeleted: false,
            createdAtUtc: DateTime.utc(2026, 8, 24),
            updatedAtUtc: DateTime.utc(2026, 8, 24),
          ),
        )
        .toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
