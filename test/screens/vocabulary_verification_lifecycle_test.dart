import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'save-owner');
}

// Hold a real post-commit SQLite read to exercise route/session changes.
class _ReadbackFaultRepository implements VocabularyRepository {
  _ReadbackFaultRepository(this.delegate);
  final VocabularyRepository delegate;
  Completer<void>? readGate;
  var readStarted = false;
  var mutationCalls = 0;

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) {
    return delegate.listAllWords(ownerId);
  }

  @override
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  }) async {
    await delegate.deleteWord(ownerId: ownerId, wordId: wordId, nowUtc: nowUtc);
  }

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) =>
      delegate.watchCategories(ownerId);
  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      delegate.watchWords(ownerId, categoryId);
  @override
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> ids) async {
    final records = await delegate.readPinnedByIds(ids);
    final gate = readGate;
    if (gate != null) {
      readStarted = true;
      await gate.future;
    }
    return records;
  }

  @override
  Future<VocabularyCategory> createCategory(VocabularyCategory category) =>
      delegate.createCategory(category);
  @override
  Future<VocabularyCategory> renameCategory({
    required String ownerId,
    required String categoryId,
    required String name,
    required String normalizedName,
    required DateTime nowUtc,
  }) => delegate.renameCategory(
    ownerId: ownerId,
    categoryId: categoryId,
    name: name,
    normalizedName: normalizedName,
    nowUtc: nowUtc,
  );
  @override
  Future<void> deleteCategory({
    required String ownerId,
    required String categoryId,
    required DateTime nowUtc,
  }) => delegate.deleteCategory(
    ownerId: ownerId,
    categoryId: categoryId,
    nowUtc: nowUtc,
  );
  @override
  Future<VocabularyWord> createWord(VocabularyWord word) {
    mutationCalls++;
    return delegate.createWord(word);
  }

  @override
  Future<VocabularyWord> updateWord(VocabularyWord word) {
    mutationCalls++;
    return delegate.updateWord(word);
  }
}

void main() {
  for (final editing in [false, true]) {
    for (final transition in [
      'cover',
      'lease',
      'disconnect',
      'owner',
      'dispose',
      'withdraw',
    ]) {
      testWidgets('late word verification edit=$editing transition=$transition', (
        tester,
      ) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('lexiquest-save-reconcile-'),
        ))!;
        final file = File('${directory.path}/test.sqlite');
        var database = AppDatabase(NativeDatabase(file));
        addTearDown(() async {
          await database.close();
          await directory.delete(recursive: true);
        });
        final now = DateTime.utc(2026, 9, 24);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'save-owner',
          nowUtc: () => now,
        );
        final repository = _ReadbackFaultRepository(
          DriftVocabularyRepository(database),
        );
        var nextId = 0;

        final vocabulary = VocabularyUseCases(
          owners: owners,
          vocabulary: repository,
          generateId: () => 'word-${nextId++}',
          nowUtc: () => now,
        );
        final category = (await tester.runAsync(
          () => vocabulary.createCategory('Reconciliation'),
        ))!;
        Future<VocabularyWord> createWord(String spelling) =>
            vocabulary.createWord(
              CreateWordCommand(
                categoryId: category.id,
                spelling: spelling,
                meaning: spelling,
                partOfSpeech: 'noun',
              ),
            );
        final target = editing
            ? (await tester.runAsync(() => createWord('book')))!
            : null;
        final survivor = (await tester.runAsync(() => createWord('pencil')))!;

        String? connectedOwner = category.ownerId;
        final registry = MenuActionRegistry(currentOwner: () => connectedOwner);
        final research = InertResearchDependencies(database);
        final dependencies = AppDependencies(
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
          experiments: research.experiments,
          consents: research.consents,
          experimentAssignments: research.experimentAssignments,
          assignedLearningEventContext: research.assignedLearningEventContext,
          evidencePolicyRolloutModeProvider:
              research.evidencePolicyRolloutModeProvider,
          vocabulary: vocabulary,
        );
        final navigator = GlobalKey<NavigatorState>();
        final features = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.allEnabled(),
        );
        addTearDown(features.dispose);
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: AppDependenciesScope(
              dependencies: dependencies,
              child: MaterialApp(
                navigatorKey: navigator,
                home: AddWordScreen(
                  categoryId: category.id,
                  word: target,
                  vocabulary: vocabulary,
                  featureRegistry: features,
                ),
              ),
            ),
          ),
        );
        Future<void> settleIo() async {
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          await tester.pump(const Duration(milliseconds: 500));
        }

        await settleIo();
        await tester.enterText(
          find.byKey(const ValueKey('word-field')),
          'book',
        );
        await tester.enterText(
          find.byKey(const ValueKey('meaning-field')),
          'updated meaning',
        );
        await tester.enterText(
          find.byKey(const ValueKey('part-of-speech-field')),
          'noun',
        );
        await tester.pump(const Duration(milliseconds: 500));
        repository.mutationCalls = 0;

        repository.readGate = Completer<void>();
        Map<String, Object?>? result;
        registry
            .execute(
              id: 'vocabulary/word-save',
              owner: category.ownerId,
              revision: registry.snapshot()['revision'] as int,
              requestId: 'late-save',
            )
            .then((value) => result = value);
        await settleIo();
        expect(repository.readStarted, isTrue);
        expect(result, isNull);
        expect(repository.mutationCalls, 1);
        final committed = (await tester.runAsync(
          () => database.select(database.vocabularyWords).get(),
        ))!;
        expect(committed, hasLength(2));
        expect(
          committed.singleWhere((row) => row.id != survivor.id).localRevision,
          editing ? 2 : 1,
        );
        final outbox = (await tester.runAsync(
          () => database
              .customSelect(
                'SELECT * FROM outbox_operations ORDER BY operation_id',
              )
              .get(),
        ))!.map((row) => row.data).toList();
        if (transition == 'cover') {
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Cover route')),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(registry.snapshot()['actions'], isEmpty);
        } else if (transition == 'dispose') {
          await tester.pumpWidget(const SizedBox.shrink());
        } else if (transition == 'withdraw') {
          features.emergencyOff(Feature.vocabulary);
          await tester.pump(const Duration(milliseconds: 500));
        } else if (transition == 'disconnect' || transition == 'owner') {
          connectedOwner = transition == 'disconnect' ? null : 'foreign-owner';
          expect(registry.snapshot()['actions'], isEmpty);
          expect(registry.snapshot()['context'], isEmpty);
        } else {
          registry.invalidateSession(preserveContext: true);
        }
        repository.readGate!.complete();
        repository.readGate = null;
        await settleIo();
        if (transition == 'cover') {
          expect(
            find.text('Cover route'),
            findsOneWidget,
            reason: 'Late read must not pop the covering route',
          );
          navigator.currentState!.pop();
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(result?['status'], 'stale');
        expect(result!.containsKey('record'), isFalse);
        if (transition != 'dispose' && transition != 'withdraw') {
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('word-field')))
                .enabled,
            isFalse,
            reason:
                'Stale completion must retain committed identity for read-only reconciliation',
          );
          connectedOwner = category.ownerId;
          Map<String, Object?>? reconciled;
          registry
              .execute(
                id: 'vocabulary/word-save',
                owner: category.ownerId,
                revision: registry.snapshot()['revision'] as int,
                requestId: 'fresh-reconcile',
              )
              .then((value) => reconciled = value);
          await settleIo();
          expect(reconciled?['status'], 'saved');
          expect(repository.mutationCalls, 1);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await settleIo();
        await tester.runAsync(database.close);
        database = AppDatabase(NativeDatabase(file));
        expect(
          (await tester.runAsync(
            () => database.select(database.vocabularyWords).get(),
          ))!,
          committed,
        );
        expect(
          (await tester.runAsync(
            () => database
                .customSelect(
                  'SELECT * FROM outbox_operations ORDER BY operation_id',
                )
                .get(),
          ))!.map((row) => row.data).toList(),
          outbox,
        );
      });
    }
  }
}
