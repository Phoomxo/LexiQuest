import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_detail.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as vocabulary_domain;
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/learning_pack_catalog_screen.dart';
import 'package:vocab_learning_app/screens/learning_pack_detail_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets(
    'renders catalog results with accessible pinned-revision labels',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(database),
          child: const MaterialApp(home: LearningPackCatalogScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'ชุดเนื้อหาการเรียน'), findsOneWidget);
      expect(find.text('Travel basics'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Travel basics, A1, travel, revision 1'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'opens only the catalog item pinned identity and keeps the live parent gate',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(registry.dispose);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(database, features: registry),
          child: const MaterialApp(home: LearningPackCatalogScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('learning-pack/open/pack:travel/1')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LearningPackDetailScreen), findsOneWidget);
      expect(
        find.bySemanticsLabel('Travel basics, A1, revision 1'),
        findsOneWidget,
      );
      registry.emergencyOff(Feature.studyPlanning);
      await tester.pump();

      expect(find.byType(LearningPackDetailScreen), findsNothing);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    },
  );
}

AppDependencies _dependencies(
  AppDatabase database, {
  FeatureRegistry features = const BuildFeatureRegistry.allEnabled(),
}) {
  final research = InertResearchDependencies(database);
  final owner = _Owner();
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
    features: features,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    vocabulary: VocabularyUseCases(
      owners: owner,
      vocabulary: _PinnedVocabulary(),
      generateId: () => 'unused-catalog-vocabulary-id',
      nowUtc: () => DateTime.utc(2026, 8, 24),
    ),
    studyPlanning: StudyPlanningUseCases(
      packs: _Packs(),
      progress: ProgressUseCases(
        owners: owner,
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 8, 24),
      ),
    ),
  );
}

final class _Packs implements LearningPackRepository {
  @override
  Future<LearningPackDetail> getVersion(String packId, int revision) async =>
      LearningPackDetail(
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
        vocabularyWordIds: const ['word:station'],
      );

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async => [
    LearningPackSummary(
      packId: 'pack:travel',
      revision: 1,
      title: 'Travel basics',
      cefrLevel: 'A1',
      topic: 'travel',
      skill: 'vocabulary',
      goal: 'recognition',
      contentIdentity: ContentIdentity(
        type: ContentType.learningPack,
        id: 'pack:travel',
        revision: 1,
      ),
    ),
  ];
}

final class _Owner implements LocalOwnerRepository {
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner:catalog',
        createdAtUtc: DateTime.utc(2026, 8, 24),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _PinnedVocabulary implements VocabularyRepository {
  @override
  Future<List<vocabulary_domain.VocabularyWord>> readPinnedByIds(
    Iterable<String> wordIds,
  ) async {
    final ids = wordIds.toList(growable: false);
    if (ids.any((id) => id != 'word:station')) {
      throw StateError('Unknown pinned vocabulary identity.');
    }
    return ids
        .map(
          (id) => vocabulary_domain.VocabularyWord(
            id: id,
            ownerId: 'packaged-owner',
            categoryId: 'category:pack',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            cefrLevel: 'A1',
            source: 'pack:v1',
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

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'catalog');
}
