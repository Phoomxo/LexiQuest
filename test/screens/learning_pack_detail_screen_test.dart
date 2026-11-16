import 'package:drift/drift.dart' show Value;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
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
  _aqTests();
  testWidgets(
    'pack detail context follows canonical owner without AI rebuild',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      String? owner;
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
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
      expect(find.text('คำศัพท์ในชุด: 2'), findsOneWidget);
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'owner:detail-screen';
      Map summary() =>
          jsonDecode(
                (registry.snapshot()['context'] as List).singleWhere(
                      (dynamic row) =>
                          row['id'] == 'study-planning/pack-detail-summary',
                    )['value']
                    as String,
              )
              as Map;
      expect(summary()['title'], 'Travel basics');
      expect(summary()['revision'], 2);
      expect(summary()['wordCount'], 2);
      expect(summary()['sampleSize'], 0);
      expect(summary()['completedSessions'], 0);
      expect(summary()['interpretation'], contains('not-learner-proficiency'));
      expect(registry.snapshot()['actions'], isEmpty);
      owner = null;
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'owner:detail-screen';
      expect(summary()['revision'], 2);
      owner = 'another-owner';
      expect(registry.snapshot()['context'], isEmpty);
      expect(find.text('คำศัพท์ในชุด: 2'), findsOneWidget);
    },
  );
  for (final invalid in ['empty', 'wrong-identity', 'missing-word']) {
    testWidgets('B07 detail fails closed for $invalid content', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: _useCases(database, invalid: invalid),
            vocabulary: _vocabulary(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LearningPackDetailUnavailable), findsOneWidget);
      expect(find.byType(RichLexicalCard), findsNothing);
    });
  }

  testWidgets('B07 detail reloads when selected revision changes', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final useCases = _useCases(database);
    final vocabulary = _vocabulary();
    Future<void> show(int revision) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: revision,
            useCases: useCases,
            vocabulary: vocabulary,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(2);
    expect(find.bySemanticsLabel('Travel basics, A1, รุ่น 2'), findsOneWidget);
    await show(3);
    expect(find.bySemanticsLabel('Travel basics, A1, รุ่น 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Travel basics, A1, รุ่น 2'), findsNothing);
    expect(find.text('คำศัพท์ในชุด: 2'), findsOneWidget);
  });

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
        find.bySemanticsLabel('Travel basics, A1, รุ่น 2'),
        findsOneWidget,
      );
      expect(find.text('station'), findsOneWidget);
      expect(
        tester
            .widget<RichLexicalCard>(find.byType(RichLexicalCard).first)
            .word
            .id,
        'word:station',
      );
      expect(find.text('กิจกรรมที่เรียนจบ: 0'), findsOneWidget);
      final scrollable = find.byType(Scrollable);
      await tester.scrollUntilVisible(
        find.text('market'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('market'), findsOneWidget);
      final marketCard = find.ancestor(
        of: find.text('market'),
        matching: find.byType(RichLexicalCard),
      );
      expect(tester.widget<RichLexicalCard>(marketCard).word.id, 'word:market');
      await tester.scrollUntilVisible(
        find.text('แบบทดสอบจากคลังคำศัพท์'),
        200,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel('แบบทดสอบจากคลังคำศัพท์: พร้อมใช้งาน'),
        findsOneWidget,
      );
      expect(find.text('จับคู่คำศัพท์'), findsNothing);
      expect(
        find.bySemanticsLabel('จับคู่คำศัพท์: ยังไม่พร้อมใช้งาน'),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('ทบทวนคำศัพท์'),
        -200,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel('ทบทวนคำศัพท์: พร้อมใช้งาน'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('อ่านเชื่อมโยงความจำ'),
        -200,
        scrollable: scrollable,
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel('อ่านเชื่อมโยงความจำ: พร้อมใช้งาน'),
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
              useCases: _useCases(database, owners: owners),
              vocabulary: _vocabulary(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('บันทึกไว้ทบทวน').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('บันทึกไว้ทบทวน').first);
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
      final pointsBefore = await database
          .select(database.pointsLedgerEntries)
          .get();
      final stationUnsave = find.descendant(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is RichLexicalCard && widget.word.id == 'word:station',
        ),
        matching: find.text('นำออกจากรายการที่บันทึก'),
      );
      await tester.ensureVisible(stationUnsave);
      await tester.pumpAndSettle();
      expect(stationUnsave.hitTestable(), findsOneWidget);
      await tester.tap(stationUnsave);
      await tester.pumpAndSettle();
      await tester.ensureVisible(stationUnsave);
      await tester.pumpAndSettle();
      await tester.tap(stationUnsave);
      await tester.pumpAndSettle();
      final removed = await database
          .select(database.savedLearningItems)
          .getSingle();
      expect(removed.isDeleted, isTrue);
      final deleteOutbox =
          await (database.select(database.outboxOperations)
                ..where((row) => row.entityType.equals('savedLearningItem'))
                ..where((row) => row.operationKind.equals('delete')))
              .get();
      expect(deleteOutbox, hasLength(1));
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        pointsBefore,
      );
      expect(
        await database
            .select(database.srsStates)
            .get()
            .then((rows) => rows.length),
        weaknessCountBefore,
      );
      expect(find.text('นำออกจากรายการในเครื่องแล้ว'), findsOneWidget);
    },
  );

  testWidgets(
    'S01-AR standalone detail owner cannot borrow unrelated mutation owner',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 9, 25);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'unrelated-writer',
        nowUtc: () => now,
      );
      await owners.getOrCreateActiveOwner();
      final intents = DriftLearnerIntentRepository(
        database,
        owners: owners,
        nowUtc: () => now,
      );
      final reports = DriftContentQualityReportRepository(
        database,
        owners: owners,
      );
      final bookmark = LearnerIntentUseCases(
        repository: intents,
        generateId: () => 'stale-save',
        nowUtc: () => now,
      ).bookmark;
      final report = ContentReportUseCases(
        repository: reports,
        generateId: () => 'stale-report',
        nowUtc: () => now,
      ).report;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(
            database,
            learnerIntents: intents,
            bookmarkLearningItem: bookmark,
            contentQualityReports: reports,
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
      await tester.tap(find.text('บันทึกไว้ทบทวน').first);
      await tester.pumpAndSettle();
      expect(find.text('ยังยืนยันการบันทึกไม่ได้ ลองอีกครั้ง'), findsOneWidget);
      await tester.ensureVisible(find.text('รายงานเนื้อหา').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(find.text('รายงานเนื้อหา').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ปัญหาข้อความ'));
      await tester.pump();
      await tester.tap(find.text('ส่งรายงาน'));
      await tester.pumpAndSettle();
      expect(find.text('ยังยืนยันการส่งรายงานไม่ได้'), findsOneWidget);
      expect(await database.select(database.savedLearningItems).get(), isEmpty);
      expect(
        await database.select(database.contentQualityReports).get(),
        isEmpty,
      );
      expect(await database.select(database.outboxOperations).get(), isEmpty);
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
              useCases: _useCases(database, owners: owners),
              vocabulary: _vocabulary(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('รายงานเนื้อหา').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ปัญหาข้อความ'));
      await tester.pump();
      await tester.tap(find.text('ส่งรายงาน'));
      await tester.tap(find.text('ส่งรายงาน'), warnIfMissed: false);
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
  VocabularyUseCases? vocabulary,
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
    vocabulary: vocabulary,
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
  String? invalid,
  LearningPackRepository? packs,
  LocalOwnerRepository? owners,
}) => LearningPackDetailUseCases(
  packs: packs ?? _Packs(failure: failure, invalid: invalid),
  progress: ProgressUseCases(
    owners: owners ?? _Owner(),
    queries: DriftProgressQueries(database),
    nowUtc: () => DateTime.utc(2026, 8, 24),
  ),
  lessonModes: buildLessonModeRegistry(),
  features: const BuildFeatureRegistry.allEnabled(),
  hasComposedDependency: (_) => true,
);

final class _Packs implements LearningPackRepository {
  const _Packs({this.failure, this.invalid});

  final String? invalid;

  final ContentQualityFailure? failure;

  @override
  Future<LearningPackDetail> getVersion(String packId, int revision) async {
    final error = failure;
    if (error != null) throw error;
    return LearningPackDetail(
      summary: LearningPackSummary(
        packId: invalid == 'wrong-identity' ? 'pack:other' : packId,
        revision: revision,
        title: 'Travel basics',
        cefrLevel: 'A1',
        topic: 'travel',
        skill: 'vocabulary',
        goal: 'recognition',
        contentIdentity: ContentIdentity(
          type: ContentType.learningPack,
          id: invalid == 'wrong-identity' ? 'pack:other' : packId,
          revision: revision,
        ),
      ),
      vocabularyWordIds: invalid == 'empty'
          ? const []
          : invalid == 'missing-word'
          ? const ['word:missing']
          : const ['word:station', 'word:market'],
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

final class _AqPacks implements LearningPackRepository {
  int reads = 0;
  Future<LearningPackDetail> Function(String, int, int)? read;
  @override
  Future<LearningPackDetail> getVersion(String id, int revision) {
    final n = ++reads;
    return read?.call(id, revision, n) ??
        const _Packs().getVersion(id, revision);
  }

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async => [];
}

final class _AqOwner implements LocalOwnerRepository {
  String id = 'owner:detail-screen';
  bool fail = false;
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    if (fail) throw StateError('owner unavailable');
    return identity.LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 9, 24));
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(String ownerId, String uid) =>
      getOrCreateActiveOwner();
}

final class _AqVocabulary implements VocabularyRepository {
  final pending = Completer<List<VocabularyWord>>();
  int reads = 0;
  @override
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> ids) {
    reads++;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _aqTests() {
  _aqMoreTests();
  _aqAdmissionTests();
  for (final sync in [false, true]) {
    testWidgets('S01-AQ repeated failure retry is bounded sync $sync', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final packs = _AqPacks()
        ..read = (id, rev, n) {
          if (n > 2) return const _Packs().getVersion(id, rev);
          if (sync) throw StateError('offline');
          return Future.error(StateError('offline'));
        };
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: _useCases(db, packs: packs),
            vocabulary: _vocabulary(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final retry = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'ลองอีกครั้ง'),
          )
          .onPressed!;
      retry();
      retry();
      await tester.pumpAndSettle();
      expect(packs.reads, 2);
      expect(tester.takeException(), isNull);
      retry();
      await tester.pumpAndSettle();
      expect(packs.reads, 2);
      await tester.tap(find.text('ลองอีกครั้ง'));
      await tester.pumpAndSettle();
      expect(packs.reads, 3);
      expect(
        find.bySemanticsLabel('Travel basics, A1, รุ่น 2'),
        findsOneWidget,
      );
    });
  }
  testWidgets(
    'S01-AQ standalone ignores unrelated scope and does not borrow vocabulary',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final packs = _AqPacks();
      final cases = _useCases(db, packs: packs);
      final vocabulary = _vocabulary();
      Widget app() => AppDependenciesScope(
        dependencies: _dependencies(db),
        child: MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: cases,
            vocabulary: vocabulary,
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(packs.reads, 1);
    },
  );
  testWidgets('S01-AQ revalidates current owner after pending vocabulary', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final owners = _AqOwner();
    final repo = _AqVocabulary();
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: repo,
      generateId: () => 'unused',
      nowUtc: () => DateTime.utc(2026),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LearningPackDetailScreen(
          packId: 'pack:travel',
          revision: 2,
          useCases: _useCases(db, owners: owners),
          vocabulary: vocabulary,
        ),
      ),
    );
    for (var i = 0; i < 15 && repo.reads == 0; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(repo.reads, 1);
    owners.id = 'replacement';
    repo.pending.complete(
      await _PinnedVocabulary().readPinnedByIds([
        'word:station',
        'word:market',
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('จำนวนครั้งที่ฝึก: 0'), findsNothing);
    expect(find.byType(LearningPackDetailUnavailable), findsOneWidget);
  });
  testWidgets('S01-AQ committed isolated owner refreshes detail menu context', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var id = 0;
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'aq-${id++}',
      nowUtc: () => DateTime.utc(2026),
    );
    final first = await owners.getOrCreateActiveOwner();
    await tester.pumpWidget(
      MaterialApp(
        home: LearningPackDetailScreen(
          packId: 'pack:travel',
          revision: 2,
          useCases: _useCases(db, owners: owners),
          vocabulary: _vocabulary(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    String? owner() => tester
        .widget<MenuActionBinding>(find.byType(MenuActionBinding))
        .ownerId;
    expect(owner(), first.id);
    await db.transaction(() async {
      await db
          .update(db.localOwners)
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await owners.getOrCreateActiveOwner();
    });
    await tester.pump(const Duration(minutes: 3));
    await tester.pumpAndSettle();
    expect(owner(), (await owners.getOrCreateActiveOwner()).id);
    expect(owner(), isNot(first.id));
  });
  for (final boundary in ['tab', 'cover', 'inactive', 'pop', 'dispose']) {
    testWidgets(
      'S01-AQ private snapshot and retained bookmark retire on $boundary',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        var saves = 0;
        final deps = _dependencies(
          db,
          bookmarkLearningItem: (_) async {
            saves++;
          },
        );
        final cases = _useCases(db);
        final vocabulary = _vocabulary();
        final nav = GlobalKey<NavigatorState>();
        late StateSetter update;
        var active = true;
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: MaterialApp(
              navigatorKey: nav,
              home: const Scaffold(body: Text('root')),
            ),
          ),
        );
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => StatefulBuilder(
              builder: (_, set) {
                update = set;
                return TickerMode(
                  enabled: active,
                  child: LearningPackDetailScreen(
                    packId: 'pack:travel',
                    revision: 2,
                    useCases: cases,
                    vocabulary: vocabulary,
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('บันทึกไว้ทบทวน').first);
        final save = tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'บันทึกไว้ทบทวน').first,
            )
            .onPressed!;
        if (boundary == 'tab') update(() => active = false);
        if (boundary == 'cover')
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
        if (boundary == 'inactive')
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        if (boundary == 'pop') nav.currentState!.pop();
        if (boundary == 'dispose') await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        save();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(saves, 0);
        expect(
          find.text('จำนวนครั้งที่ฝึก: 0', skipOffstage: false),
          findsNothing,
        );
        if (boundary == 'tab') update(() => active = true);
        if (boundary == 'cover') nav.currentState!.pop();
        if (boundary == 'inactive')
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        await tester.pumpAndSettle();
        if (['tab', 'cover', 'inactive'].contains(boundary))
          expect(find.text('จำนวนครั้งที่ฝึก: 0'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'S01-AQ report is owned single route and stays explicitly usable',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var reports = 0;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(
            db,
            reportContent:
                ({required identity, required reason, comment}) async {
                  reports++;
                },
          ),
          child: MaterialApp(
            home: LearningPackDetailScreen(
              packId: 'pack:travel',
              revision: 2,
              useCases: _useCases(db),
              vocabulary: _vocabulary(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('รายงานเนื้อหา').first);
      final open = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'รายงานเนื้อหา').first,
          )
          .onPressed!;
      open();
      open();
      await tester.pumpAndSettle();
      await tester.tap(find.text('ปัญหาข้อความ'));
      await tester.pump();
      await tester.tap(find.text('ส่งรายงาน'));
      await tester.pumpAndSettle();
      expect(reports, 1);
      expect(find.text('ส่งรายงาน'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('จำนวนครั้งที่ฝึก: 0'), findsOneWidget);
    },
  );
  testWidgets('S01-AQ retired report cannot submit after app inactive', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var reports = 0;
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(
          db,
          reportContent: ({required identity, required reason, comment}) async {
            reports++;
          },
        ),
        child: MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: _useCases(db),
            vocabulary: _vocabulary(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('รายงานเนื้อหา').first);
    await tester.tap(find.text('รายงานเนื้อหา').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปัญหาข้อความ'));
    await tester.pump();
    final submit = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'ส่งรายงาน'))
        .onPressed!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    submit();
    await tester.pumpAndSettle();
    expect(reports, 0);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  });
}

void _aqMoreTests() {
  testWidgets(
    'S01-AQ extra absent standalone vocabulary fails closed despite unrelated scope vocabulary',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(db, vocabulary: _vocabulary()),
          child: MaterialApp(
            home: LearningPackDetailScreen(
              packId: 'pack:travel',
              revision: 2,
              useCases: _useCases(db),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LearningPackDetailUnavailable), findsOneWidget);
      expect(find.byType(RichLexicalCard), findsNothing);
    },
  );
  for (final kind in ['pack', 'revision', 'useCases', 'vocabulary']) {
    testWidgets('S01-AQ extra replacement $kind retires pending pinned read', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final pending = Completer<LearningPackDetail>();
      final packs = _AqPacks()
        ..read = (id, rev, n) =>
            n == 1 ? pending.future : const _Packs().getVersion(id, rev);
      final old = _useCases(db, packs: packs);
      final next = _useCases(db, packs: _AqPacks());
      final vocabulary = _vocabulary();
      Widget app(bool replacement) => MaterialApp(
        home: LearningPackDetailScreen(
          packId: replacement && kind == 'pack'
              ? 'pack:replacement'
              : 'pack:travel',
          revision: replacement && kind == 'revision' ? 3 : 2,
          useCases: replacement && kind == 'useCases' ? next : old,
          vocabulary: replacement && kind == 'vocabulary'
              ? _vocabulary()
              : vocabulary,
        ),
      );
      await tester.pumpWidget(app(false));
      for (var i = 0; i < 15 && packs.reads == 0; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(packs.reads, 1);
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          'Travel basics, A1, รุ่น ${kind == 'revision' ? 3 : 2}',
        ),
        findsOneWidget,
      );
      pending.completeError(StateError('old read failed late'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LearningPackDetailUnavailable), findsNothing);
    });
  }
  testWidgets(
    'S01-AQ extra owner observation failure is explicitly recoverable',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = _AqOwner()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: _useCases(db, owners: owners),
            vocabulary: _vocabulary(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LearningPackDetailUnavailable), findsOneWidget);
      owners.fail = false;
      await tester.tap(find.text('ลองอีกครั้ง'));
      await tester.pumpAndSettle();
      expect(find.text('จำนวนครั้งที่ฝึก: 0'), findsOneWidget);
    },
  );
  testWidgets(
    'S01-AQ extra bookmark revalidates owner before and after await without false success',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = _AqOwner();
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(
            db,
            bookmarkLearningItem: (_) {
              calls++;
              return pending.future;
            },
          ),
          child: MaterialApp(
            home: LearningPackDetailScreen(
              packId: 'pack:travel',
              revision: 2,
              useCases: _useCases(db, owners: owners),
              vocabulary: _vocabulary(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('บันทึกไว้ทบทวน').first);
      await tester.tap(find.text('บันทึกไว้ทบทวน').first);
      await tester.pump();
      expect(calls, 1);
      owners.id = 'replacement';
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('บันทึกไว้ในเครื่องแล้ว'), findsNothing);
      await tester.tap(find.text('บันทึกไว้ทบทวน').first);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'S01-AQ extra returned report owner change cannot acknowledge success',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = _AqOwner();
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(
            db,
            reportContent: ({required identity, required reason, comment}) {
              calls++;
              return pending.future;
            },
          ),
          child: MaterialApp(
            home: LearningPackDetailScreen(
              packId: 'pack:travel',
              revision: 2,
              useCases: _useCases(db, owners: owners),
              vocabulary: _vocabulary(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('รายงานเนื้อหา').first);
      await tester.tap(find.text('รายงานเนื้อหา').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ปัญหาข้อความ'));
      await tester.pump();
      await tester.tap(find.text('ส่งรายงาน'));
      await tester.pump();
      expect(calls, 1);
      owners.id = 'replacement';
      pending.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('บันทึกรายงานในเครื่องแล้ว ยังไม่ยืนยันการส่งถึงปลายทาง'),
        findsNothing,
      );
      expect(find.text('ยังยืนยันการส่งรายงานไม่ได้'), findsOneWidget);
      await tester.tap(find.text('ส่งรายงาน'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );
  testWidgets(
    'S01-AQ extra Thai retry 360px 200 percent is reachable with semantics',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: _useCases(
              db,
              packs: _AqPacks()
                ..read = (_, __, ___) => Future.error(StateError('offline')),
            ),
            vocabulary: _vocabulary(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ลองอีกครั้ง'));
      expect(find.bySemanticsLabel('ลองอีกครั้ง'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'ลองอีกครั้ง')).height,
        greaterThanOrEqualTo(48),
      );
      semantics.dispose();
    },
  );
}

final class _AqIntents implements LearnerIntentRepository {
  int saves = 0;
  int removals = 0;
  @override
  Future<void> save(SaveLearningItemCommand command) async {
    saves++;
  }

  @override
  Future<void> unsave(ContentIdentity identity) async {
    removals++;
  }
}

void _aqAdmissionTests() {
  testWidgets('S01-AQ sheet detached close and reason callbacks retire', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(
          db,
          reportContent:
              ({required identity, required reason, comment}) async {},
        ),
        child: MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: _useCases(db),
            vocabulary: _vocabulary(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('รายงานเนื้อหา').first);
    await tester.tap(find.text('รายงานเนื้อหา').first);
    await tester.pumpAndSettle();
    final close = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
        .onPressed!;
    final change = tester
        .widget<RadioGroup<ContentReportReason>>(
          find.byType(RadioGroup<ContentReportReason>),
        )
        .onChanged;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    change(ContentReportReason.text);
    close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(LearningPackDetailScreen), findsOneWidget);
  });

  testWidgets(
    'S01-AQ admission removal of standalone useCases retires old data',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final vocabulary = _vocabulary();
      final cases = _useCases(db);
      Widget app(LearningPackDetailUseCases? useCases) => MaterialApp(
        home: LearningPackDetailScreen(
          packId: 'pack:travel',
          revision: 2,
          useCases: useCases,
          vocabulary: vocabulary,
        ),
      );
      await tester.pumpWidget(app(cases));
      await tester.pumpAndSettle();
      expect(find.text('จำนวนครั้งที่ฝึก: 0'), findsOneWidget);
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      expect(find.byType(LearningPackDetailUnavailable), findsOneWidget);
      expect(find.text('จำนวนครั้งที่ฝึก: 0'), findsNothing);
    },
  );

  testWidgets(
    'S01-AQ admission repository replacement retires retained removal',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final old = _AqIntents();
      final next = _AqIntents();
      final BookmarkLearningItemAction save = (_) async {};
      final cases = _useCases(db);
      final vocabulary = _vocabulary();
      Widget app(LearnerIntentRepository repository) => AppDependenciesScope(
        dependencies: _dependencies(
          db,
          learnerIntents: repository,
          bookmarkLearningItem: save,
        ),
        child: MaterialApp(
          home: LearningPackDetailScreen(
            packId: 'pack:travel',
            revision: 2,
            useCases: cases,
            vocabulary: vocabulary,
          ),
        ),
      );
      await tester.pumpWidget(app(old));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('นำออกจากรายการที่บันทึก').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      final remove = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'นำออกจากรายการที่บันทึก').first,
          )
          .onPressed!;
      await tester.pumpWidget(app(next));
      await tester.pumpAndSettle();
      remove();
      await tester.pumpAndSettle();
      expect(old.removals, 0);
      expect(next.removals, 0);
      await tester.ensureVisible(find.text('นำออกจากรายการที่บันทึก').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester.tap(find.text('นำออกจากรายการที่บันทึก').first);
      await tester.pumpAndSettle();
      expect(next.removals, 1);
      expect(find.text('นำออกจากรายการในเครื่องแล้ว'), findsOneWidget);
    },
  );
}
