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
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'delete-owner');
}

// Only the verification read fails. Mutations and streams use real SQLite.
class _ReadbackFaultRepository implements VocabularyRepository {
  _ReadbackFaultRepository(this.delegate);
  final VocabularyRepository delegate;
  var failReadback = false;
  var deleteCalls = 0;

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) {
    if (failReadback) throw StateError('injected post-commit read failure');
    return delegate.listAllWords(ownerId);
  }

  @override
  Future<void> deleteWord({
    required String ownerId,
    required String wordId,
    required DateTime nowUtc,
  }) async {
    deleteCalls++;
    await delegate.deleteWord(ownerId: ownerId, wordId: wordId, nowUtc: nowUtc);
  }

  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) =>
      delegate.watchCategories(ownerId);
  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      delegate.watchWords(ownerId, categoryId);
  @override
  Future<List<VocabularyWord>> readPinnedByIds(Iterable<String> ids) =>
      delegate.readPinnedByIds(ids);
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
  Future<VocabularyWord> createWord(VocabularyWord word) =>
      delegate.createWord(word);
  @override
  Future<VocabularyWord> updateWord(VocabularyWord word) =>
      delegate.updateWord(word);
}

void main() {
  for (final notificationFails in [false, true]) {
    group(
      'notificationFails: $notificationFails',
      () => _cases(notificationFails),
    );
  }
}

void _cases(bool notificationFails) {
  for (final reconcileBeforeRestart in [true, false]) {
    testWidgets(
      'post-commit read failure survives restart (reconcile first: $reconcileBeforeRestart)',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('lexiquest-delete-reconcile-'),
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
          generateId: () => 'delete-owner',
          nowUtc: () => now,
        );
        final repository = _ReadbackFaultRepository(
          DriftVocabularyRepository(database),
        );
        var nextId = 0;
        var notificationsArmed = false;
        final vocabulary = VocabularyUseCases(
          owners: owners,
          vocabulary: repository,
          generateId: () => 'word-${nextId++}',
          nowUtc: () => now,
          onLocalMutation: () {
            if (notificationsArmed && notificationFails) {
              throw StateError('injected optional sync notification failure');
            }
          },
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
        notificationsArmed = true;
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
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: AppDependenciesScope(
              dependencies: dependencies,
              child: MaterialApp(
                home: VocabListScreen(
                  categoryId: category.id,
                  categoryName: category.name,
                  vocabulary: vocabulary,
                  featureRegistry: const BuildFeatureRegistry.allEnabled(),
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
          await tester.pumpAndSettle();
        }

        await settleIo();
        expect(find.widgetWithText(ListTile, 'book'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(ListTile, 'book'),
            matching: find.byIcon(Icons.delete_outline),
          ),
        );
        await settleIo();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        var request = 0;
        Future<Map<String, Object?>> confirm() async {
          Map<String, Object?>? result;
          registry
              .execute(
                id: 'vocabulary/word-delete-confirm',
                owner: category.ownerId,
                revision: registry.snapshot()['revision'] as int,
                requestId: 'confirm-${request++}',
                values: {'wordId': target.id},
              )
              .then((value) => result = value);
          await settleIo();
          expect(result, isNotNull);
          return result!;
        }

        repository.failReadback = true;
        final first = await confirm();
        final committed = (await tester.runAsync(
          () => database.select(database.vocabularyWords).get(),
        ))!;
        expect(
          committed.singleWhere((row) => row.id == target.id).isDeleted,
          isTrue,
        );
        expect(
          committed.singleWhere((row) => row.id == survivor.id).isDeleted,
          isFalse,
        );
        final outbox = (await tester.runAsync(
          () => database
              .customSelect(
                'SELECT * FROM outbox_operations ORDER BY operation_id',
              )
              .get(),
        ))!.map((row) => row.data).toList();
        expect(
          outbox.where((row) => row['operation_kind'] == 'delete'),
          hasLength(1),
        );
        expect(first['status'], 'outcome_unknown');
        expect(repository.deleteCalls, 1);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลบ'))
              .onPressed,
          isNull,
        );
        expect(find.widgetWithText(TextButton, 'ปิด'), findsOneWidget);
        connectedOwner = null;
        expect(registry.snapshot()['actions'], isEmpty);
        connectedOwner = 'foreign-owner';
        expect(registry.snapshot()['actions'], isEmpty);
        expect(registry.snapshot()['context'], isEmpty);
        connectedOwner = category.ownerId;
        expect((await confirm())['status'], 'outcome_unknown');
        expect(
          repository.deleteCalls,
          1,
          reason: 'A new request must only reconcile the committed mutation',
        );
        if (reconcileBeforeRestart) {
          repository.failReadback = false;
          expect((await confirm())['status'], 'deleted');
          expect(repository.deleteCalls, 1);
          expect(find.byType(AlertDialog), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await settleIo();
        await tester.runAsync(database.close);
        database = AppDatabase(NativeDatabase(file));
        final restarted = (await tester.runAsync(
          () => database.select(database.vocabularyWords).get(),
        ))!;
        expect(restarted, committed);
        final restartedOutbox = (await tester.runAsync(
          () => database
              .customSelect(
                'SELECT * FROM outbox_operations ORDER BY operation_id',
              )
              .get(),
        ))!.map((row) => row.data).toList();
        expect(restartedOutbox, outbox);
      },
    );
  }
}
