import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide AssociationRecord, AssociativeMemoryState;
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_associative_learning_adapter.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _GuestEntryStateStore implements AppEntryStateStore {
  @override
  Future<void> clear() async {}

  @override
  Future<void> markGuest() async {}

  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

const _flutterTtsChannel = MethodChannel('flutter_tts');

AppBootstrap _bootstrap(String databasePath) {
  return AppBootstrap(
    initializeFirebase: () async => throw StateError('firebase unavailable'),
    initializeSupabase: () async => throw StateError('supabase unavailable'),
    loadConfig: () => throw StateError('backend config unavailable'),
    guestSessionService: _GuestSession(),
    createDatabase: () => AppDatabase(NativeDatabase(File(databasePath))),
    createEntryStateStore: () async => _GuestEntryStateStore(),
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 150,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Widget did not appear after $maxPumps bounded pumps: $finder');
}

Future<void> _pumpUntilContinueEnabled(
  WidgetTester tester, {
  int maxPumps = 100,
}) async {
  final finder = find.widgetWithText(FilledButton, 'Complete & Continue');
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) {
      final button = tester.widget<FilledButton>(finder);
      if (button.onPressed != null) return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Continue action did not re-enable after $maxPumps bounded pumps.');
}

Future<({int associations, int memory})> _pairCounts(
  AppDatabase database,
) async {
  final row = await database.customSelect('''
SELECT
  (SELECT COUNT(*) FROM association_records) AS association_count,
  (SELECT COUNT(*) FROM associative_memory_states) AS memory_count
''').getSingle();
  return (
    associations: row.read<int>('association_count'),
    memory: row.read<int>('memory_count'),
  );
}

Future<({int associations, int memory})> _pairCountsForWord(
  AppDatabase database,
  String wordKey,
) async {
  final row = await database
      .customSelect(
        '''
SELECT
  (SELECT COUNT(*) FROM association_records WHERE word_key = ?) AS association_count,
  (SELECT COUNT(*) FROM associative_memory_states WHERE word_key = ?) AS memory_count
''',
        variables: [Variable.withString(wordKey), Variable.withString(wordKey)],
      )
      .getSingle();
  return (
    associations: row.read<int>('association_count'),
    memory: row.read<int>('memory_count'),
  );
}

void main() {
  testWidgets(
    'production associative reading survives file reopen for active owner only',
    (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      binaryMessenger.setMockMethodCallHandler(
        _flutterTtsChannel,
        (_) async => 1,
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp(
          'lexiquest-associative-reading-restart-',
        ),
      ))!;
      final databasePath =
          '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      AppDependencies? first;
      AppDependencies? reopened;

      try {
        first = (await tester.runAsync(
          () => _bootstrap(databasePath).initialize(),
        ))!;
        expect(first.initialRoute, AppRoute.home);
        expect(
          first.associativeLearning,
          isA<DriftAssociativeLearningAdapter>(),
        );
        final activeOwner = (await tester.runAsync(
          first.localOwners!.getOrCreateActiveOwner,
        ))!;
        final category = (await tester.runAsync(
          () => first!.vocabulary!.createCategory('Reading'),
        ))!;
        final word = (await tester.runAsync(
          () => first!.vocabulary!.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'resilient',
              meaning: 'able to recover',
              partOfSpeech: 'adjective',
              cefrLevel: 'B2',
            ),
          ),
        ))!;

        await tester.pumpWidget(MyApp(dependencies: first));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        final learnDestination = find
            .descendant(
              of: find.byType(MainNavigationScreen),
              matching: find.byType(NavigationDestination),
            )
            .at(1);
        await tester.tap(learnDestination);
        await _pumpUntilFound(tester, find.byType(ChooseModeScreen));
        await tester.tap(find.text('Associative Reading'));
        await _pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await _pumpUntilFound(
          tester,
          find.byType(AssociativeReadingSessionScreen),
        );
        await _pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));

        const stageTitles = <String>[
          'Stage 2: Cue Fading',
          'Stage 3: Active Recall',
          'Stage 4: Memory Association',
        ];
        for (var index = 0; index < stageTitles.length; index++) {
          await tester.tap(find.text('Complete & Continue'));
          await _pumpUntilFound(tester, find.text(stageTitles[index]));
        }
        await tester.enterText(find.byType(TextField).first, 'spring back');
        await tester.tap(find.text('Complete & Continue'));
        await _pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));

        final database = first.database!;
        const foreignOwnerId = 'local:foreign-associative-owner';
        final foreignAdapter = DriftAssociativeLearningAdapter(database);
        await tester.runAsync(() async {
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: foreignOwnerId,
                  createdAtUtcMs: DateTime.utc(
                    2026,
                    8,
                    9,
                    12,
                  ).millisecondsSinceEpoch,
                  isActive: const Value(false),
                ),
              );
          await foreignAdapter.saveAssociation(
            AssociationRecord(
              associationId: 'association:foreign',
              ownerId: foreignOwnerId,
              wordKey: word.id,
              type: 'keyword',
              content: 'foreign private cue',
              createdAtUtc: DateTime.utc(2026, 8, 9, 12),
            ),
          );
          await foreignAdapter.updateMemoryState(
            AssociativeMemoryState(
              ownerId: foreignOwnerId,
              wordKey: word.id,
              stability: 9,
              difficulty: 1,
              cueDependency: 0,
              lapseCount: 0,
              lastReviewedAtUtc: DateTime.utc(2026, 8, 9, 12),
              nextDueAtUtc: DateTime.utc(2026, 9, 9, 12),
              algorithmVersion: 'foreign-v1',
            ),
          );
        });

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() => first!.dispose());
        first = null;

        reopened = (await tester.runAsync(
          () => _bootstrap(databasePath).initialize(),
        ))!;
        final reopenedOwner = (await tester.runAsync(
          reopened.localOwners!.getOrCreateActiveOwner,
        ))!;
        final adapter = reopened.associativeLearning!;
        final associations = (await tester.runAsync(
          () => adapter.getAssociationsForWord(reopenedOwner.id, word.id),
        ))!;
        final memory = (await tester.runAsync(
          () => adapter.getAllMemoryStates(reopenedOwner.id),
        ))!;
        final associationRows = (await tester.runAsync(
          () => reopened!.database!
              .customSelect(
                'SELECT owner_id FROM association_records ORDER BY owner_id',
              )
              .get(),
        ))!;
        final memoryRows = (await tester.runAsync(
          () => reopened!.database!
              .customSelect(
                'SELECT owner_id FROM associative_memory_states ORDER BY owner_id',
              )
              .get(),
        ))!;

        expect(reopenedOwner.id, activeOwner.id);
        expect(associations, hasLength(1));
        expect(associations.single.content, 'spring back');
        expect(associations.single.ownerId, activeOwner.id);
        expect(memory, hasLength(1));
        expect(memory.single.wordKey, word.id);
        expect(memory.single.ownerId, activeOwner.id);
        expect(associationRows, hasLength(2));
        expect(memoryRows, hasLength(2));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() async {
          await reopened?.dispose();
          await first?.dispose();
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });
        await tester.pump(const Duration(milliseconds: 1));
        binaryMessenger.setMockMethodCallHandler(_flutterTtsChannel, null);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'partial association failure survives reopen without advancing an empty retry',
    (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      binaryMessenger.setMockMethodCallHandler(
        _flutterTtsChannel,
        (_) async => 1,
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp(
          'lexiquest-associative-pair-restart-',
        ),
      ))!;
      final databasePath =
          '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      AppDependencies? first;
      AppDependencies? reopened;

      try {
        first = (await tester.runAsync(
          () => _bootstrap(databasePath).initialize(),
        ))!;
        final category = (await tester.runAsync(
          () => first!.vocabulary!.createCategory('Atomic association'),
        ))!;
        final word = (await tester.runAsync(
          () => first!.vocabulary!.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'anchor',
              meaning: 'a stable point',
              partOfSpeech: 'noun',
            ),
          ),
        ))!;

        Widget session(AppDependencies dependencies) {
          return MaterialApp(
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'B1',
              targetWords: const ['anchor'],
              targetWordIds: {'anchor': word.id},
              passageText: 'An anchor keeps the vessel stable.',
              documentId: 'associative-reading:atomic-review',
              documentRevision: 1,
              learning: dependencies.learning,
              associativeLearning: dependencies.associativeLearning,
            ),
          );
        }

        await tester.pumpWidget(session(first));
        await _pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        for (final title in const [
          'Stage 2: Cue Fading',
          'Stage 3: Active Recall',
          'Stage 4: Memory Association',
        ]) {
          await tester.tap(find.text('Complete & Continue'));
          await _pumpUntilFound(tester, find.text(title));
        }
        await tester.runAsync(
          () => first!.database!.customStatement('''
CREATE TRIGGER fail_associative_memory_insert
BEFORE INSERT ON associative_memory_states
BEGIN
  SELECT RAISE(ABORT, 'injected associative memory failure');
END
'''),
        );
        await tester.enterText(find.byType(TextField).first, 'keeps me steady');
        await tester.tap(find.text('Complete & Continue'));
        await _pumpUntilFound(
          tester,
          find.text('Could not save the memory association. Try again.'),
        );
        await _pumpUntilContinueEnabled(tester);
        final afterFailure = (await tester.runAsync(
          () => _pairCounts(first!.database!),
        ))!;

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() => first!.dispose());
        first = null;

        reopened = (await tester.runAsync(
          () => _bootstrap(databasePath).initialize(),
        ))!;
        await tester.pumpWidget(session(reopened));
        await _pumpUntilFound(tester, find.text('Stage 4: Memory Association'));
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          isEmpty,
        );
        await tester.tap(find.text('Complete & Continue'));
        await _pumpUntilContinueEnabled(tester);
        final emptyRetryStayed =
            find.text('Stage 4: Memory Association').evaluate().isNotEmpty &&
            find.text('Stage 5: Context Transfer').evaluate().isEmpty;
        final afterEmptyRetry = (await tester.runAsync(
          () => _pairCounts(reopened!.database!),
        ))!;
        var afterRecovery = afterEmptyRetry;

        if (emptyRetryStayed) {
          await tester.runAsync(
            () => reopened!.database!.customStatement(
              'DROP TRIGGER fail_associative_memory_insert',
            ),
          );
          await tester.enterText(
            find.byType(TextField).first,
            'keeps me steady',
          );
          await tester.tap(find.text('Complete & Continue'));
          await _pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));
          afterRecovery = (await tester.runAsync(
            () => _pairCounts(reopened!.database!),
          ))!;
        }

        expect(
          (
            afterFailure: afterFailure,
            emptyRetryStayed: emptyRetryStayed,
            afterEmptyRetry: afterEmptyRetry,
            afterRecovery: afterRecovery,
          ),
          equals((
            afterFailure: (associations: 0, memory: 0),
            emptyRetryStayed: true,
            afterEmptyRetry: (associations: 0, memory: 0),
            afterRecovery: (associations: 1, memory: 1),
          )),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() async {
          await reopened?.dispose();
          await first?.dispose();
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });
        await tester.pump(const Duration(milliseconds: 1));
        binaryMessenger.setMockMethodCallHandler(_flutterTtsChannel, null);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'multi-target retry keeps exactly one durable pair per target',
    (tester) async {
      final binaryMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      binaryMessenger.setMockMethodCallHandler(
        _flutterTtsChannel,
        (_) async => 1,
      );
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp(
          'lexiquest-associative-multi-target-',
        ),
      ))!;
      final databasePath =
          '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      AppDependencies? dependencies;

      try {
        final initialized = (await tester.runAsync(
          () => _bootstrap(databasePath).initialize(),
        ))!;
        dependencies = initialized;
        final category = (await tester.runAsync(
          () => initialized.vocabulary!.createCategory('Retry pairs'),
        ))!;
        final words = (await tester.runAsync(() async {
          final anchor = await initialized.vocabulary!.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'anchor',
              meaning: 'a stable point',
              partOfSpeech: 'noun',
            ),
          );
          final beacon = await initialized.vocabulary!.createWord(
            CreateWordCommand(
              categoryId: category.id,
              spelling: 'beacon',
              meaning: 'a guiding light',
              partOfSpeech: 'noun',
            ),
          );
          return (anchor: anchor, beacon: beacon);
        }))!;

        await tester.pumpWidget(
          MaterialApp(
            home: AssociativeReadingSessionScreen(
              cefrLevel: 'B1',
              targetWords: const ['anchor', 'beacon'],
              targetWordIds: {
                'anchor': words.anchor.id,
                'beacon': words.beacon.id,
              },
              passageText: 'An anchor steadies us while a beacon guides us.',
              documentId: 'associative-reading:multi-target-review',
              documentRevision: 1,
              learning: initialized.learning,
              associativeLearning: initialized.associativeLearning,
            ),
          ),
        );
        await _pumpUntilFound(tester, find.text('Stage 1: Supported Reading'));
        for (final title in const [
          'Stage 2: Cue Fading',
          'Stage 3: Active Recall',
          'Stage 4: Memory Association',
        ]) {
          await tester.tap(find.text('Complete & Continue'));
          await _pumpUntilFound(tester, find.text(title));
        }
        await tester.runAsync(
          () => initialized.database!.customStatement('''
CREATE TRIGGER fail_second_associative_memory_insert
BEFORE INSERT ON associative_memory_states
WHEN (SELECT COUNT(*) FROM associative_memory_states) = 1
BEGIN
  SELECT RAISE(ABORT, 'injected second-target memory failure');
END
'''),
        );
        await tester.enterText(find.byType(TextField).at(0), 'keeps me steady');
        await tester.enterText(find.byType(TextField).at(1), 'shows the way');
        await tester.tap(find.text('Complete & Continue'));
        await _pumpUntilFound(
          tester,
          find.text('Could not save the memory association. Try again.'),
        );
        await _pumpUntilContinueEnabled(tester);

        final afterFailure = (await tester.runAsync(() async {
          return (
            anchor: await _pairCountsForWord(
              initialized.database!,
              words.anchor.id,
            ),
            beacon: await _pairCountsForWord(
              initialized.database!,
              words.beacon.id,
            ),
          );
        }))!;
        expect(
          afterFailure,
          equals((
            anchor: (associations: 1, memory: 1),
            beacon: (associations: 0, memory: 0),
          )),
        );

        await tester.runAsync(
          () => initialized.database!.customStatement(
            'DROP TRIGGER fail_second_associative_memory_insert',
          ),
        );
        await tester.tap(find.text('Complete & Continue'));
        await _pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));

        final afterRetry = (await tester.runAsync(() async {
          return (
            anchor: await _pairCountsForWord(
              initialized.database!,
              words.anchor.id,
            ),
            beacon: await _pairCountsForWord(
              initialized.database!,
              words.beacon.id,
            ),
            total: await _pairCounts(initialized.database!),
          );
        }))!;
        expect(
          afterRetry,
          equals((
            anchor: (associations: 1, memory: 1),
            beacon: (associations: 1, memory: 1),
            total: (associations: 2, memory: 2),
          )),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(() async {
          await dependencies?.dispose();
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        });
        await tester.pump(const Duration(milliseconds: 1));
        binaryMessenger.setMockMethodCallHandler(_flutterTtsChannel, null);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
