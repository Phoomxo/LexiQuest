import 'package:drift/drift.dart' show Value;
import 'dart:async';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
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
import '../support/r15_visual_capture.dart';

void main() {
  _catalogRecoveryTests();
  testWidgets(
    'mounted catalog pack contexts remain fenced across owner changes',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      String? owner;
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: AppDependenciesScope(
            dependencies: _dependencies(database),
            child: const MaterialApp(home: LearningPackCatalogScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Travel basics'), findsOneWidget);
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'owner:catalog';
      expect(registry.snapshot()['context'], hasLength(2));
      owner = null;
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'owner:catalog';
      expect(registry.snapshot()['context'], hasLength(2));
      owner = 'another-owner';
      expect(registry.snapshot()['context'], isEmpty);
      expect(find.text('Travel basics'), findsOneWidget);
    },
  );
  for (final empty in [true, false]) {
    testWidgets('catalog assistance reflects filter and empty state $empty', (
      tester,
    ) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      String? owner;
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: AppDependenciesScope(
            dependencies: _dependencies(database, emptyCatalog: empty),
            child: const MaterialApp(home: LearningPackCatalogScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(registry.snapshot()['context'], isEmpty);
      owner = 'owner:catalog';
      Map summary() =>
          jsonDecode(
                (registry.snapshot()['context'] as List).singleWhere(
                      (dynamic x) =>
                          x['id'] == 'study-planning/catalog-summary',
                    )['value']
                    as String,
              )
              as Map;
      expect(summary()['catalogCount'], empty ? 0 : 1);
      expect(summary()['matchingCount'], empty ? 0 : 1);
      expect(summary()['state'], empty ? 'empty-catalog' : 'matches');
      expect(summary()['interpretation'], contains('not-learner-proficiency'));
      expect(registry.snapshot()['actions'], isEmpty);
      if (!empty) {
        final entries = registry.snapshot()['context'] as List;
        final pack = jsonDecode(
          entries.singleWhere(
                (dynamic x) => (x['id'] as String).startsWith(
                  'study-planning/catalog-pack/',
                ),
              )['value']
              as String,
        );
        expect(pack['title'], 'Travel basics');
        expect(pack['revision'], 1);
        await tester.enterText(find.byType(TextField), 'no-match-113');
        await tester.pumpAndSettle();
        expect(summary()['catalogCount'], 1);
        expect(summary()['matchingCount'], 0);
        expect(summary()['state'], 'no-matches');
        expect(
          (registry.snapshot()['context'] as List).where(
            (dynamic x) =>
                (x['id'] as String).startsWith('study-planning/catalog-pack/'),
          ),
          isEmpty,
        );
        expect(find.text('ไม่พบชุดบทเรียนที่ตรงกับการค้นหา'), findsOneWidget);
      }
      owner = null;
      expect(registry.snapshot()['context'], isEmpty);
      expect(find.byType(LearningPackCatalogScreen), findsOneWidget);
      owner = 'owner:catalog';
      expect(summary()['matchingCount'], 0);
      owner = 'another-owner';
      expect(registry.snapshot()['context'], isEmpty);
    });
  }
  testWidgets('personal sets entry remains reachable from an empty catalog', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, emptyCatalog: true),
        child: const MaterialApp(home: LearningPackCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ชุดคำส่วนตัว'));
    await tester.pumpAndSettle();
    expect(find.text('ชุดคำส่วนตัวยังไม่พร้อมใช้งาน'), findsOneWidget);
  });
  testWidgets('B07 skill and goal filters combine and clear independently', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, extraPack: true),
        child: const MaterialApp(home: LearningPackCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'reading'));
    await tester.pumpAndSettle();
    expect(find.text('Health basics'), findsOneWidget);
    expect(find.text('Travel basics'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'recognition'));
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบชุดบทเรียนที่ตรงกับตัวกรอง'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'recognition'));
    await tester.tap(find.widgetWithText(FilterChip, 'reading'));
    await tester.pumpAndSettle();
    expect(find.text('Health basics'), findsOneWidget);
    expect(find.text('Travel basics'), findsOneWidget);
  });

  testWidgets('A-NAV-04 empty catalog has no start or search result claim', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, emptyCatalog: true),
        child: const MaterialApp(home: LearningPackCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีชุดบทเรียนที่ผ่านการตรวจสอบ'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });
  testWidgets('A-NAV-04 incompatible filters recover independently of search', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, extraPack: true),
        child: const MaterialApp(home: LearningPackCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'A1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'health'));
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบชุดบทเรียนที่ตรงกับตัวกรอง'), findsOneWidget);
    expect(find.text('ยังไม่มีชุดบทเรียนที่ผ่านการตรวจสอบ'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'health'));
    await tester.pumpAndSettle();
    expect(find.text('Travel basics'), findsOneWidget);
  });
  setUpAll(loadR15Fonts);
  for (final width in [320.0, 840.0]) {
    testWidgets('visual catalog $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('synthetic-r15-surface'),
          child: AppDependenciesScope(
            dependencies: _dependencies(database),
            child: MaterialApp(
              theme: M3Theme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const LearningPackCatalogScreen(),
            ),
          ),
        ),
      );
      await captureR15Surface(tester, 'A-UI-01-T02-w${width.toInt()}-s2-dark');
    });
  }

  for (final width in [320.0, 390.0, 840.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final dark in [false, true]) {
        testWidgets('A-UI catalog w$width s$scale dark$dark keyboard', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final database = AppDatabase(NativeDatabase.memory());
          addTearDown(database.close);
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: _dependencies(database),
              child: MaterialApp(
                theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: const LearningPackCatalogScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.enterText(find.byType(TextField), 'Travel');
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          final tile = find.byKey(
            const ValueKey('learning-pack/open/pack:travel/1'),
          );
          expect(
            tester.getSize(find.byTooltip('ล้างการค้นหา')).height,
            greaterThanOrEqualTo(48),
          );
          await tester.ensureVisible(tile);
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(
                      of: find.byType(ListView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              )
              .position;
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getRect(tile).bottom, lessThanOrEqualTo(500));
        });
      }
    }
  }

  testWidgets('A-NAV-04 search miss clears back to catalog', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database),
        child: const MaterialApp(home: LearningPackCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'synthetic-r15-no-match');
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบชุดบทเรียนที่ตรงกับการค้นหา'), findsOneWidget);
    expect(find.text('ยังไม่มีชุดบทเรียนที่ผ่านการตรวจสอบ'), findsNothing);
    expect(find.text('Travel basics'), findsNothing);
    await tester.tap(find.byTooltip('ล้างการค้นหา'));
    await tester.pumpAndSettle();
    expect(find.text('Travel basics'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a1');
    await tester.pumpAndSettle();
    expect(find.text('Travel basics'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'A1'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'travel'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'A1'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'A1')).selected,
      isTrue,
    );
    expect(find.text('Travel basics'), findsOneWidget);
  });

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
        find.bySemanticsLabel('Travel basics, A1, travel, รุ่น 1'),
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
        find.bySemanticsLabel('Travel basics, A1, รุ่น 1'),
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
  bool emptyCatalog = false,
  bool extraPack = false,
  LearningPackRepository? packs,
  LocalOwnerRepository? owners,
}) {
  final research = InertResearchDependencies(database);
  final owner = owners ?? _Owner();
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
      packs: packs ?? _Packs(empty: emptyCatalog, extra: extraPack),
      progress: ProgressUseCases(
        owners: owner,
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 8, 24),
      ),
    ),
  );
}

final class _Packs implements LearningPackRepository {
  _Packs({this.empty = false, this.extra = false});
  final bool empty;
  final bool extra;
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
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async =>
      empty
      ? []
      : [
          if (extra)
            LearningPackSummary(
              packId: 'synthetic-r15-health',
              revision: 1,
              title: 'Health basics',
              cefrLevel: 'B1',
              topic: 'health',
              skill: 'reading',
              goal: 'comprehension',
              contentIdentity: ContentIdentity(
                type: ContentType.learningPack,
                id: 'synthetic-r15-health',
                revision: 1,
              ),
            ),
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

final class _ControlledPacks implements LearningPackRepository {
  int reads = 0;
  Future<List<LearningPackSummary>> Function(int)? read;
  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) {
    reads++;
    return read?.call(reads) ?? _Packs().list(filter);
  }

  @override
  Future<LearningPackDetail> getVersion(String id, int revision) =>
      _Packs().getVersion(id, revision);
}

void _catalogRecoveryTests() {
  testWidgets('S01-AP media changes do not refetch unchanged catalog', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final packs = _ControlledPacks();
    final deps = _dependencies(db, packs: packs);
    late StateSetter update;
    var scale = 1.0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (_, set) {
          update = set;
          return AppDependenciesScope(
            dependencies: deps,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const LearningPackCatalogScreen(),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    final before = packs.reads;
    update(() => scale = 2);
    await tester.pumpAndSettle();
    expect(packs.reads, before);
    await tester.enterText(find.byType(TextField), 'Travel');
    await tester.pumpAndSettle();
    expect(packs.reads, before);
  });
  testWidgets(
    'S01-AP retry retains search and independent filters after cover failure',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final packs = _ControlledPacks();
      packs.read = (n) => n == 2
          ? Future.error(StateError('offline'))
          : _Packs(extra: true).list(LearningPackFilter());
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(db, packs: packs),
          child: MaterialApp(
            navigatorKey: nav,
            home: const LearningPackCatalogScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Travel');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'A1'));
      await tester.pump();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('ลองอีกครั้ง'), findsOneWidget);
      await tester.tap(find.text('ลองอีกครั้ง'));
      await tester.pumpAndSettle();
      expect(packs.reads, 3);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Travel',
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'A1'))
            .selected,
        isTrue,
      );
      expect(find.text('Travel basics'), findsOneWidget);
      expect(find.text('Health basics'), findsNothing);
    },
  );
  testWidgets('S01-AP retry remains bounded while deferred read is pending', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pending = Completer<List<LearningPackSummary>>();
    final packs = _ControlledPacks()
      ..read = (n) =>
          n == 1 ? Future.error(StateError('offline')) : pending.future;
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(db, packs: packs),
        child: const MaterialApp(home: LearningPackCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final retry = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลองอีกครั้ง'))
        .onPressed!;
    retry();
    await tester.pump();
    retry();
    retry();
    expect(packs.reads, 2);
    pending.complete(await _Packs().list(LearningPackFilter()));
    await tester.pumpAndSettle();
    expect(find.text('Travel basics'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    retry();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'S01-AP returned owner revalidation rejects raced catalog context',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = _RacingCatalogOwner();
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(db, owners: owners),
          child: const MaterialApp(home: LearningPackCatalogScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Travel basics'), findsNothing);
      expect(find.text('ลองอีกครั้ง'), findsOneWidget);
      expect(
        tester
            .widgetList<MenuActionBinding>(find.byType(MenuActionBinding))
            .where((x) => x.ownerId != null),
        isEmpty,
      );
    },
  );
  testWidgets(
    'S01-AP removed parent leaves child live and independently gated',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final nav = GlobalKey<NavigatorState>();
      late StateSetter update;
      var deps = _dependencies(db);
      final replacement = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(replacement.dispose);
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (_, set) {
            update = set;
            return AppDependenciesScope(
              dependencies: deps,
              child: MaterialApp(
                navigatorKey: nav,
                home: const Scaffold(body: Text('root')),
              ),
            );
          },
        ),
      );
      final parent = MaterialPageRoute<void>(
        builder: (_) => const LearningPackCatalogScreen(),
      );
      nav.currentState!.push(parent);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      nav.currentState!.removeRoute(parent);
      await tester.pumpAndSettle();
      update(() => deps = _dependencies(db, features: replacement));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LearningPackDetailScreen), findsOneWidget);
      replacement.emergencyOff(Feature.studyPlanning);
      await tester.pumpAndSettle();
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('root'), findsOneWidget);
    },
  );
  testWidgets('S01-AP personal sets shares single admission with detail', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final observer = _CatalogObserver();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(db),
        child: MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [observer],
          home: const LearningPackCatalogScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sets = tester
        .widget<IconButton>(
          find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == 'ชุดคำส่วนตัว',
          ),
        )
        .onPressed!;
    final detail = tester.widget<ListTile>(find.byType(ListTile)).onTap!;
    final before = observer.pushes;
    sets();
    sets();
    detail();
    await tester.pumpAndSettle();
    expect(observer.pushes, before + 1);
    expect(find.text('ชุดคำส่วนตัวยังไม่พร้อมใช้งาน'), findsOneWidget);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Travel basics'), findsOneWidget);
  });
  testWidgets(
    'S01-AP Thai failure at 360px 200 percent has reachable semantic retry',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final handle = tester.ensureSemantics();
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final packs = _ControlledPacks()
        ..read = (_) => Future.error(StateError('offline'));
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(db, packs: packs),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const LearningPackCatalogScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('ลองอีกครั้ง'));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('ลองอีกครั้ง'), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'ลองอีกครั้ง')).height,
        greaterThanOrEqualTo(48),
      );
      handle.dispose();
    },
  );

  for (final synchronous in [false, true]) {
    testWidgets(
      'S01-AP bounded retry observes repeated failure sync $synchronous',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final packs = _ControlledPacks();
        packs.read = (n) {
          if (n > 2) return _Packs().list(LearningPackFilter());
          if (synchronous) throw StateError('catalog read failed');
          return Future.error(StateError('catalog read failed'));
        };
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: _dependencies(db, packs: packs),
            child: const MaterialApp(home: LearningPackCatalogScreen()),
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
        expect(find.text('Travel basics'), findsOneWidget);
      },
    );
  }
  testWidgets('S01-AP standalone useCases replacement retires pending result', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pending = Completer<List<LearningPackSummary>>();
    final oldPacks = _ControlledPacks()..read = (_) => pending.future;
    final old = _dependencies(db, packs: oldPacks).studyPlanning!;
    final next = _dependencies(db, emptyCatalog: true).studyPlanning!;
    await tester.pumpWidget(
      MaterialApp(home: LearningPackCatalogScreen(useCases: old)),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: LearningPackCatalogScreen(useCases: next)),
    );
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีชุดบทเรียนที่ผ่านการตรวจสอบ'), findsOneWidget);
    pending.complete(await _Packs().list(LearningPackFilter()));
    await tester.pumpAndSettle();
    expect(find.text('Travel basics'), findsNothing);
  });
  testWidgets('S01-AP standalone ignores unrelated dependency replacement', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final packs = _ControlledPacks();
    final useCases = _dependencies(db, packs: packs).studyPlanning!;
    Widget app() => AppDependenciesScope(
      dependencies: _dependencies(db),
      child: MaterialApp(home: LearningPackCatalogScreen(useCases: useCases)),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(packs.reads, 1);
  });
  testWidgets('S01-AP current filters retire detached actions', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(db, extraPack: true),
        child: const MaterialApp(home: LearningPackCatalogScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final old = tester
        .widget<FilterChip>(find.widgetWithText(FilterChip, 'reading'))
        .onSelected!;
    await tester.tap(find.widgetWithText(FilterChip, 'A1'));
    await tester.pump();
    old(true);
    await tester.pumpAndSettle();
    expect(find.text('Travel basics'), findsOneWidget);
    expect(find.text('ไม่พบชุดบทเรียนที่ตรงกับตัวกรอง'), findsNothing);
  });
  for (final boundary in ['tab', 'cover', 'inactive', 'dispose', 'pop']) {
    testWidgets('S01-AP retired filter and detail actions after $boundary', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deps = _dependencies(db);
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
                child: const LearningPackCatalogScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chip = tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'A1'))
          .onSelected!;
      final search = tester
          .widget<TextField>(find.byType(TextField))
          .onChanged!;
      final open = tester.widget<ListTile>(find.byType(ListTile)).onTap!;
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
      if (boundary == 'dispose') await tester.pumpWidget(const SizedBox());
      if (boundary == 'pop') nav.currentState!.pop();
      await tester.pumpAndSettle();
      chip(true);
      search('stale');
      open();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LearningPackDetailScreen), findsNothing);
      if (boundary == 'inactive')
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      if (boundary == 'tab') update(() => active = true);
      if (boundary == 'cover') nav.currentState!.pop();
      await tester.pumpAndSettle();
      if (['tab', 'cover', 'inactive'].contains(boundary)) {
        expect(
          tester
              .widget<FilterChip>(find.widgetWithText(FilterChip, 'A1'))
              .selected,
          isFalse,
        );
        expect(find.text('Travel basics'), findsOneWidget);
      }
    });
  }
  testWidgets('S01-AP repeated detail action opens one usable pinned child', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final nav = GlobalKey<NavigatorState>();
    final observer = _CatalogObserver();
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(db),
        child: MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [observer],
          home: const LearningPackCatalogScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final open = tester.widget<ListTile>(find.byType(ListTile)).onTap!;
    final before = observer.pushes;
    open();
    open();
    await tester.pumpAndSettle();
    expect(observer.pushes, before + 1);
    expect(find.byType(LearningPackDetailScreen), findsOneWidget);
    expect(find.bySemanticsLabel('Travel basics, A1, รุ่น 1'), findsOneWidget);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(LearningPackCatalogScreen), findsOneWidget);
    open();
    await tester.pumpAndSettle();
    expect(observer.pushes, before + 1);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(observer.pushes, before + 2);
  });
  testWidgets('S01-AP detail follows replacement live registry', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final replacement = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    addTearDown(replacement.dispose);
    late StateSetter update;
    var deps = _dependencies(db);
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (_, set) {
          update = set;
          return AppDependenciesScope(
            dependencies: deps,
            child: const MaterialApp(home: LearningPackCatalogScreen()),
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    replacement.emergencyOff(Feature.studyPlanning);
    update(() => deps = _dependencies(db, features: replacement));
    await tester.pumpAndSettle();
    expect(find.byType(LearningPackDetailScreen), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
  });
  testWidgets(
    'S01-AP isolated committed owner refreshes optional catalog context',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var id = 0;
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'owner:ap-${id++}',
        nowUtc: () => DateTime.utc(2026, 9, 24),
      );
      final first = await owners.getOrCreateActiveOwner();
      final registry = MenuActionRegistry(currentOwner: () => null);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: AppDependenciesScope(
            dependencies: _dependencies(db, owners: owners),
            child: const MaterialApp(home: LearningPackCatalogScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      String? displayedOwner() => tester
          .widgetList<MenuActionBinding>(find.byType(MenuActionBinding))
          .singleWhere((x) => x.id == 'study-planning/catalog-summary')
          .ownerId;
      expect(displayedOwner(), first.id);
      await db.transaction(() async {
        await db
            .update(db.localOwners)
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await owners.getOrCreateActiveOwner();
      });
      await tester.pump(const Duration(minutes: 3));
      await tester.pumpAndSettle();
      final next = await owners.getOrCreateActiveOwner();
      expect(next.id, isNot(first.id));
      expect(displayedOwner(), next.id);
    },
  );
}

class _CatalogObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

final class _RacingCatalogOwner implements LocalOwnerRepository {
  int reads = 0;
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: ++reads <= 2 ? 'owner:old' : 'owner:replacement',
        createdAtUtc: DateTime.utc(2026, 9, 24),
      );
  @override
  Future<identity.LocalOwner> bindFirebaseUid(String ownerId, String uid) =>
      getOrCreateActiveOwner();
}
