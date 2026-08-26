import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/boss_battle_screen.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/screens/game_launcher_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  test('production launcher calls the bounded vocabulary API explicitly', () {
    final source = File(
      'lib/screens/game_launcher_screen.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'getGameWords\(limit: 10\)').allMatches(source),
      hasLength(1),
    );
  });

  testWidgets('injected vocabulary cannot bypass missing shell authority', (
    tester,
  ) async {
    final repository = _VocabularyRepositoryFake();
    final pending = Completer<List<VocabularyWord>>();
    repository.pending = pending;
    final hostKey = GlobalKey<_DependenciesHostState>();

    await tester.pumpWidget(
      _DependenciesHost(
        key: hostKey,
        vocabulary: _useCases(repository),
        gameMode: GameMode.wordScramble,
      ),
    );
    await tester.pump();
    expect(repository.listCalls, 1);

    hostKey.currentState!.notifyDependencyChange();
    await tester.pump();
    hostKey.currentState!.notifyDependencyChange();
    await tester.pump();

    expect(repository.listCalls, 1);
    pending.complete([_word('alpha')]);
    await tester.pumpAndSettle();
    expect(find.byType(WordScrambleScreen), findsNothing);
    expect(
      tester
          .widget<GameLauncherUnavailable>(find.byType(GameLauncherUnavailable))
          .reason,
      GameLauncherUnavailableReason.missingDependency,
    );
  });

  testWidgets('multiple resolved builds schedule at most one game route', (
    tester,
  ) async {
    final repository = _VocabularyRepositoryFake();
    final pending = Completer<List<VocabularyWord>>();
    repository.pending = pending;
    final observer = _RouteObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: GameLauncherScreen(
          gameMode: GameMode.wordScramble,
          vocabulary: _useCases(repository),
        ),
      ),
    );
    await tester.pump();
    pending.complete([_word('alpha')]);
    await tester.idle();

    final dynamic state = tester.state(find.byType(GameLauncherScreen));
    state.build(tester.element(find.byType(GameLauncherScreen)));
    state.build(tester.element(find.byType(GameLauncherScreen)));
    await tester.pumpAndSettle();

    expect(
      observer.namedRoutes.where((routeName) => routeName != '/'),
      isEmpty,
    );
    expect(find.byType(WordScrambleScreen), findsNothing);
    expect(find.byType(GameLauncherUnavailable), findsOneWidget);
  });

  testWidgets('missing dependency is a typed unavailable state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameLauncherScreen(gameMode: GameMode.wordScramble),
      ),
    );
    await tester.pump();

    final state = tester.widget<GameLauncherUnavailable>(
      find.byType(GameLauncherUnavailable),
    );
    expect(state.reason, GameLauncherUnavailableReason.missingDependency);
  });

  testWidgets('empty inventory and load failure are distinct typed states', (
    tester,
  ) async {
    final empty = _VocabularyRepositoryFake();
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey<String>('empty-app'),
        home: GameLauncherScreen(
          key: const ValueKey<String>('empty-launcher'),
          gameMode: GameMode.dictation,
          vocabulary: _useCases(empty),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<GameLauncherUnavailable>(find.byType(GameLauncherUnavailable))
          .reason,
      GameLauncherUnavailableReason.emptyInventory,
    );

    final failing = _VocabularyRepositoryFake()
      ..failure = StateError('inventory-secret');
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey<String>('failing-app'),
        home: GameLauncherScreen(
          key: const ValueKey<String>('failing-launcher'),
          gameMode: GameMode.dictation,
          vocabulary: _useCases(failing),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<GameLauncherUnavailable>(find.byType(GameLauncherUnavailable))
          .reason,
      GameLauncherUnavailableReason.loadFailure,
    );
    expect(find.textContaining('inventory-secret'), findsNothing);
  });

  testWidgets(
    'native games fail closed without registered shell dependencies',
    (tester) async {
      final repository = _VocabularyRepositoryFake()
        ..words = [_word('alpha'), _word('beta')];
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey<String>('scramble-app'),
          home: GameLauncherScreen(
            key: const ValueKey<String>('scramble-launcher'),
            gameMode: GameMode.wordScramble,
            vocabulary: _useCases(repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WordScrambleScreen), findsNothing);
      expect(find.byType(GameLauncherUnavailable), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey<String>('dictation-app'),
          home: GameLauncherScreen(
            key: const ValueKey<String>('dictation-launcher'),
            gameMode: GameMode.dictation,
            vocabulary: _useCases(repository),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DictationQuizScreen), findsNothing);
      expect(find.byType(GameLauncherUnavailable), findsOneWidget);
    },
  );

  testWidgets('boss receives at most ten words from owned inventory', (
    tester,
  ) async {
    final repository = _VocabularyRepositoryFake()
      ..words = List.generate(12, (index) => _word('owned-$index'));
    final owned = repository.words.map((word) => word.spelling).toSet();

    await tester.pumpWidget(
      MaterialApp(
        home: GameLauncherScreen(
          gameMode: GameMode.bossBattle,
          vocabulary: _useCases(repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boss = tester.widget<BossBattleScreen>(find.byType(BossBattleScreen));
    expect(boss.questions, hasLength(10));
    expect(
      boss.questions.map((question) => question['word']),
      everyElement(isIn(owned)),
    );
  });
}

VocabularyUseCases _useCases(_VocabularyRepositoryFake repository) {
  return VocabularyUseCases(
    owners: _OwnerRepository(),
    vocabulary: repository,
    generateId: () => 'unused',
    nowUtc: () => DateTime.utc(2026, 8, 11),
  );
}

VocabularyWord _word(String spelling) {
  return VocabularyWord(
    id: 'word:$spelling',
    ownerId: _OwnerRepository.owner.id,
    categoryId: 'category:test',
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: '$spelling meaning',
    normalizedMeaning: '$spelling meaning',
    partOfSpeech: 'noun',
    source: 'manual',
    isGlobal: false,
    localRevision: 1,
    isDeleted: false,
    createdAtUtc: DateTime.utc(2026, 8, 11),
    updatedAtUtc: DateTime.utc(2026, 8, 11),
  );
}

final class _OwnerRepository implements LocalOwnerRepository {
  static final owner = LocalOwner(
    id: 'local:game-owner',
    createdAtUtc: DateTime.utc(2026, 8, 11),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) async {
    return owner;
  }
}

final class _VocabularyRepositoryFake implements VocabularyRepository {
  List<VocabularyWord> words = [];
  Completer<List<VocabularyWord>>? pending;
  Object? failure;
  int listCalls = 0;

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) {
    listCalls += 1;
    final error = failure;
    if (error != null) return Future<List<VocabularyWord>>.error(error);
    final wait = pending;
    if (wait != null) return wait.future;
    return Future<List<VocabularyWord>>.value(words);
  }

  @override
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> wordIds) =>
      Future<List<VocabularyWord>>.error(UnimplementedError());

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) =>
      const Stream.empty();

  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      const Stream.empty();

  @override
  Future<VocabularyCategory> createCategory(VocabularyCategory category) =>
      throw UnimplementedError();

  @override
  Future<VocabularyCategory> renameCategory({
    required String ownerId,
    required String categoryId,
    required String name,
    required String normalizedName,
    required DateTime nowUtc,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteCategory({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
  }) => throw UnimplementedError();

  @override
  Future<VocabularyWord> createWord(VocabularyWord word) =>
      throw UnimplementedError();

  @override
  Future<VocabularyWord> updateWord(VocabularyWord word) =>
      throw UnimplementedError();

  @override
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  }) => throw UnimplementedError();
}

final class _DependenciesHost extends StatefulWidget {
  const _DependenciesHost({
    super.key,
    required this.vocabulary,
    required this.gameMode,
  });

  final VocabularyUseCases vocabulary;
  final GameMode gameMode;

  @override
  State<_DependenciesHost> createState() => _DependenciesHostState();
}

final class _DependenciesHostState extends State<_DependenciesHost> {
  final db.AppDatabase _researchDatabase = db.AppDatabase(
    NativeDatabase.memory(),
  );
  late final InertResearchDependencies _research = InertResearchDependencies(
    _researchDatabase,
  );

  void notifyDependencyChange() => setState(() {});

  @override
  void dispose() {
    unawaited(_researchDatabase.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDependenciesScope(
      dependencies: AppDependencies(
        initialRoute: AppRoute.home,
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _GuestSessionService(),
        quest: testQuestUseCases(),
        experiments: _research.experiments,
        consents: _research.consents,
        experimentAssignments: _research.experimentAssignments,
        assignedLearningEventContext: _research.assignedLearningEventContext,
        evidencePolicyRolloutModeProvider:
            _research.evidencePolicyRolloutModeProvider,
        vocabulary: widget.vocabulary,
      ),
      child: MaterialApp(home: GameLauncherScreen(gameMode: widget.gameMode)),
    );
  }
}

final class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionStarted(uid: 'game-owner');
  }
}

final class _RouteObserver extends NavigatorObserver {
  final List<String?> namedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    namedRoutes.add(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    namedRoutes.add(newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
