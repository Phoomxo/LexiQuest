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
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
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

// The transaction remains real; inject faults only into independent readback.
class _ReadbackFaultRepository implements VocabularyImportRepository {
  _ReadbackFaultRepository(this.delegate);
  final VocabularyImportRepository delegate;
  var readFault = 'none';
  var mutationCalls = 0;
  @override
  Future<VocabularyImportResult> persist(
    PreparedVocabularyImport import, {
    required bool Function() isCancelled,
  }) {
    mutationCalls++;
    return delegate.persist(import, isCancelled: isCancelled);
  }

  @override
  Future<VocabularyImportResult?> readResult({
    required String importId,
    required String ownerId,
    required String categoryId,
  }) async {
    if (readFault == 'throw') {
      throw StateError('injected import verification read failure');
    }
    if (readFault == 'missing') return null;
    final result = await delegate.readResult(
      importId: importId,
      ownerId: ownerId,
      categoryId: categoryId,
    );
    if (readFault == 'mismatch' && result != null) {
      return VocabularyImportResult(
        importId: result.importId,
        accepted: result.accepted + 1,
        duplicates: result.duplicates,
        rejected: result.rejected,
      );
    }
    return result;
  }
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
  for (final reconcile in [true, false]) {
    testWidgets('import post-commit readback (reconcile: $reconcile)', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lexiquest-import-reconcile-'),
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
        DriftVocabularyImportRepository(database),
      );
      var nextId = 0;
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: () => 'category-${nextId++}',
        nowUtc: () => now,
      );
      final survivor = (await tester.runAsync(
        () => vocabulary.createCategory('Survivor'),
      ))!;
      var notificationsArmed = false;
      final importer = ImportVocabulary(
        owners: owners,
        repository: repository,
        generateId: () => 'import-${nextId++}',
        nowUtc: () => now,
        onLocalMutation: () {
          if (notificationsArmed && notificationFails) {
            throw StateError('injected optional sync notification failure');
          }
        },
      );
      notificationsArmed = true;
      String? connectedOwner = survivor.ownerId;
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
              home: AddMultipleWordsScreen(
                importer: importer,
                categoryId: survivor.id,
                categoryName: survivor.name,
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
      await tester.enterText(
        find.byKey(const ValueKey('import-rows-field')),
        'book,Book,noun\nbook,Book,noun\ninvalid,,noun',
      );
      await tester.pumpAndSettle();
      repository.mutationCalls = 0;
      var request = 0;
      Future<Map<String, Object?>> execute(
        String id, [
        Map<String, String> values = const {},
      ]) async {
        Map<String, Object?>? result;
        registry
            .execute(
              id: id,
              owner: survivor.ownerId,
              revision: registry.snapshot()['revision'] as int,
              requestId: 'request-${request++}',
              values: values,
            )
            .then((value) => result = value);
        await settleIo();
        expect(result, isNotNull);
        return result!;
      }

      repository.readFault = 'throw';
      final first = await execute('vocabulary/import-save');
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
                  .map((row) => row.data)
                  .toList(),
      };
      final committed = (await tester.runAsync(snapshot))!;
      expect(committed['vocabulary_words'] as List, hasLength(1));
      expect(committed['vocabulary_imports'] as List, hasLength(1));
      expect(committed['vocabulary_import_rows'] as List, hasLength(3));
      final target = (committed['vocabulary_imports'] as List).single as Map;
      Future<List<Map<String, Object?>>> outbox() async =>
          (await database
                  .customSelect(
                    'SELECT * FROM outbox_operations ORDER BY operation_id',
                  )
                  .get())
              .map((row) => row.data)
              .toList();
      final beforeOutbox = (await tester.runAsync(outbox))!;
      expect(beforeOutbox, hasLength(2));
      expect(first['status'], 'outcome_unknown');
      expect(repository.mutationCalls, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('import-rows-field')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('import-words')))
            .onPressed,
        isNull,
      );
      expect(
        (await execute('vocabulary/import-fill', {
          'rows': 'replacement,Replacement,noun',
        }))['status'],
        'busy',
      );
      connectedOwner = null;
      expect(registry.snapshot()['actions'], isEmpty);
      connectedOwner = 'foreign-owner';
      final foreignActions = registry.snapshot()['actions'] as List;
      expect(
        foreignActions.where(
          (dynamic a) => a['id'] == 'vocabulary/import-save',
        ),
        isEmpty,
      );
      connectedOwner = survivor.ownerId;
      expect(
        (await execute('vocabulary/import-save'))['status'],
        'outcome_unknown',
      );
      repository.readFault = 'missing';
      expect(
        (await execute('vocabulary/import-save'))['status'],
        'outcome_unknown',
      );
      repository.readFault = 'mismatch';
      expect(
        (await execute('vocabulary/import-save'))['status'],
        'outcome_unknown',
      );
      expect(repository.mutationCalls, 1);
      if (reconcile) {
        repository.readFault = 'none';
        final verified = await execute('vocabulary/import-save');
        expect(verified['status'], 'saved');
        expect((verified['record'] as Map)['importId'], target['id']);
        expect((verified['record'] as Map)['accepted'], 1);
        expect((verified['record'] as Map)['duplicates'], 1);
        expect((verified['record'] as Map)['rejectedCount'], 1);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('import-rows-field')),
              )
              .enabled,
          isTrue,
        );
        expect(repository.mutationCalls, 1);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await settleIo();
      await tester.runAsync(database.close);
      database = AppDatabase(NativeDatabase(file));
      expect((await tester.runAsync(snapshot))!, committed);
      expect((await tester.runAsync(outbox))!, beforeOutbox);
    });
  }
}
