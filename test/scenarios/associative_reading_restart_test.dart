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
}
