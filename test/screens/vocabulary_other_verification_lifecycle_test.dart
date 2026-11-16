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
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/screens/add_multiple_words_screen.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
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
  Future<void> pause(Completer<void>? gate) async {
    if (gate != null) {
      readStarted = true;
      await gate.future;
    }
  }

  var mutationCalls = 0;

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) async {
    final records = await delegate.listAllWords(ownerId);
    await pause(mutationCalls > 0 ? readGate : null);
    return records;
  }

  @override
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  }) async {
    mutationCalls++;
    await delegate.deleteWord(ownerId: ownerId, wordId: wordId, nowUtc: nowUtc);
  }

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) {
    final gate = mutationCalls > 0
        ? readGate
        : null; // Only post-commit verification is delayed.
    return delegate.watchCategories(ownerId).asyncMap((records) async {
      await pause(gate);
      return records;
    });
  }

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
  Future<VocabularyCategory> createCategory(VocabularyCategory category) {
    mutationCalls++;
    return delegate.createCategory(category);
  }

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

class _DelayedImportRepository implements VocabularyImportRepository {
  _DelayedImportRepository(this.delegate, this.control);
  final VocabularyImportRepository delegate;
  final _ReadbackFaultRepository control;
  @override
  Future<VocabularyImportResult> persist(
    PreparedVocabularyImport import, {
    required bool Function() isCancelled,
  }) {
    control.mutationCalls++;
    return delegate.persist(import, isCancelled: isCancelled);
  }

  @override
  Future<VocabularyImportResult?> readResult({
    required String importId,
    required String ownerId,
    required String categoryId,
  }) async {
    final result = await delegate.readResult(
      importId: importId,
      ownerId: ownerId,
      categoryId: categoryId,
    );
    await control.pause(control.readGate);
    return result;
  }
}

void main() {
  for (final route in ['category', 'import', 'delete']) {
    for (final transition in [
      'cover',
      'lease',
      'disconnect',
      'owner',
      'dispose',
      'withdraw',
    ]) {
      testWidgets(
        'late route verification route=$route transition=$transition',
        (tester) async {
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
          final target = (await tester.runAsync(() => createWord('book')))!;
          final survivor = (await tester.runAsync(() => createWord('pencil')))!;

          String? connectedOwner = category.ownerId;
          final registry = MenuActionRegistry(
            currentOwner: () => connectedOwner,
          );
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
          final importer = ImportVocabulary(
            owners: owners,
            repository: _DelayedImportRepository(
              DriftVocabularyImportRepository(database),
              repository,
            ),
            generateId: () => 'import-${nextId++}',
            nowUtc: () => now,
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
                  home: switch (route) {
                    'category' => CategoriesPage(
                      vocabulary: vocabulary,
                      featureRegistry: features,
                    ),
                    'import' => AddMultipleWordsScreen(
                      categoryId: category.id,
                      categoryName: category.name,
                      importer: importer,
                      featureRegistry: features,
                    ),
                    _ => VocabListScreen(
                      categoryId: category.id,
                      categoryName: category.name,
                      vocabulary: vocabulary,
                      featureRegistry: features,
                    ),
                  },
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
          if (route == 'category') {
            await tester.tap(find.byKey(const ValueKey('add-category')));
            await settleIo();
            await tester.enterText(
              find.byKey(const ValueKey('category-name-field')),
              'Created category',
            );
          } else if (route == 'import') {
            await tester.enterText(
              find.byKey(const ValueKey('import-rows-field')),
              'imported,Book,noun\nimported,Book,noun\ninvalid,,noun',
            );
          } else {
            await tester.tap(
              find.descendant(
                of: find.widgetWithText(ListTile, 'book'),
                matching: find.byIcon(Icons.delete_outline),
              ),
            );
          }
          await settleIo();
          final actionId = route == 'delete'
              ? 'vocabulary/word-delete-confirm'
              : 'vocabulary/$route-save';
          final values = route == 'delete'
              ? {'wordId': target.id}
              : <String, String>{};
          Future<Map<String, Object?>> snapshot() async => {
            for (final table in [
              'vocabulary_categories',
              'vocabulary_words',
              'vocabulary_imports',
              'vocabulary_import_rows',
              'outbox_operations',
            ])
              table:
                  (await database
                          .customSelect('SELECT * FROM $table ORDER BY rowid')
                          .get())
                      .map((r) => r.data)
                      .toList(),
          };
          repository.mutationCalls = 0;

          repository.readGate = Completer<void>();
          Map<String, Object?>? result;
          registry
              .execute(
                id: actionId,
                values: values,
                owner: category.ownerId,
                revision: registry.snapshot()['revision'] as int,
                requestId: 'late-save',
              )
              .then((value) => result = value);
          await settleIo();
          expect(repository.readStarted, isTrue);
          expect(result, isNull);
          expect(repository.mutationCalls, 1);
          final committed = (await tester.runAsync(snapshot))!;
          final words = (await tester.runAsync(
            () => database.select(database.vocabularyWords).get(),
          ))!;
          expect(
            words.singleWhere((w) => w.id == survivor.id).isDeleted,
            isFalse,
          );
          if (route == 'delete') {
            expect(
              words.singleWhere((w) => w.id == target.id).isDeleted,
              isTrue,
            );
          }
          if (route == 'import') {
            expect(words.any((w) => w.spelling == 'imported'), isTrue);
          }
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
            connectedOwner = transition == 'disconnect'
                ? null
                : 'foreign-owner';
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
            if (route == 'delete') {
              expect(
                find.byType(AlertDialog),
                findsOneWidget,
                reason: 'Stale result must retain the pending deletion dialog',
              );
            } else {
              expect(
                find.byKey(
                  ValueKey(
                    route == 'category'
                        ? 'category-name-field'
                        : 'import-rows-field',
                  ),
                ),
                findsOneWidget,
              );
              expect(
                tester
                    .widget<TextField>(
                      find.byKey(
                        ValueKey(
                          route == 'category'
                              ? 'category-name-field'
                              : 'import-rows-field',
                        ),
                      ),
                    )
                    .enabled,
                isFalse,
                reason: 'Stale completion must retain committed identity',
              );
            }
            connectedOwner = category.ownerId;
            Map<String, Object?>? reconciled;
            registry
                .execute(
                  id: actionId,
                  values: values,
                  owner: category.ownerId,
                  revision: registry.snapshot()['revision'] as int,
                  requestId: 'fresh-reconcile',
                )
                .then((value) => reconciled = value);
            await settleIo();
            expect(
              reconciled?['status'],
              route == 'delete' ? 'deleted' : 'saved',
            );
            expect(repository.mutationCalls, 1);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await settleIo();
          await tester.runAsync(database.close);
          database = AppDatabase(NativeDatabase(file));
          expect((await tester.runAsync(snapshot))!, committed);
        },
      );
    }
  }
}
