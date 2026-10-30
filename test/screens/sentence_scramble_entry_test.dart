import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/sentence_scramble_native_harness.dart';

void main() {
  for (final correct in [true, false]) {
    testWidgets(
      'Sentence Scramble owned entry finishes one real answer into P23 ($correct)',
      (tester) async {
        final h = (await tester.runAsync(SentenceScrambleNativeHarness.open))!;
        try {
          await _pumpEntry(tester, h);
          await _openCategory(tester);
          expect(h.provider.requests, isEmpty);
          expect(
            await tester.runAsync(() => h.storage.count('learning_sessions')),
            0,
          );
          expect(
            await tester.runAsync(() => h.storage.count('answer_attempts')),
            0,
          );
          await tester.tap(find.text('Synthetic travel'));
          await _ready(tester);
          final screen = tester.widget<SentenceScrambleScreen>(
            find.byType(SentenceScrambleScreen),
          );
          expect(screen.session.ownerId, configuredOwnerId);
          expect(screen.session.word.categoryId, configuredCategoryId);
          expect(screen.languageCode, 'th');
          expect(h.provider.requests, hasLength(1));
          expect(h.provider.requests.single.text, screen.session.word.spelling);
          expect(h.provider.transactionStates, [false]);
          expect(
            await tester.runAsync(() => h.storage.count('learning_sessions')),
            1,
          );
          expect(
            await tester.runAsync(() => h.storage.count('answer_attempts')),
            0,
          );
          expect(find.byType(ScoreScreen), findsNothing);

          await _finish(tester, h, screen, correct: correct);
          final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
          final persisted = (await tester.runAsync(
            () => h.storage.session(screen.session.id),
          ))!;
          expect(score.correctAnswers, persisted['correct_count']);
          expect(score.wrongAnswers, persisted['wrong_count']);
          expect(score.score, persisted['score']);
          expect(score.correctAnswers, correct ? 1 : 0);
          expect(score.wrongAnswers, correct ? 0 : 1);
          expect(score.score, correct ? 100 : 0);
          expect(persisted['state'], 'completed');
          expect(find.text(correct ? '100%' : '0%'), findsOneWidget);
          await _assertOneRecreationalAnswer(tester, h, screen);

          await tester.tap(find.text('กลับไปเลือกกิจกรรม'));
          await tester.pumpAndSettle();
          expect(find.byType(ChooseModeScreen), findsOneWidget);
          expect(find.byType(ScoreScreen), findsNothing);
          expect(h.provider.requests, hasLength(1));
          await _assertOneRecreationalAnswer(tester, h, screen);
        } finally {
          await _close(tester, h);
        }
      },
    );
  }

  testWidgets(
    'Sentence Scramble preparation cannot survive an actual owner null-to-same transition',
    (tester) async {
      final h = (await tester.runAsync(SentenceScrambleNativeHarness.open))!;
      final release = Completer<void>();
      StreamSubscription<String?>? ownerProbe;
      var providerWaiting = false;
      var returned = false;
      h.provider.beforeResponse = (_) async {
        providerWaiting = true;
        await release.future;
        returned = true;
      };
      try {
        final dependencies = await _pumpEntry(tester, h);
        final owners = <String?>[];
        await tester.runAsync(() async {
          ownerProbe = dependencies.progress!.watchActiveOwnerId().listen(
            owners.add,
          );
        });
        await _until(
          tester,
          () => owners.isNotEmpty && owners.last == configuredOwnerId,
        );
        await _openCategory(tester);
        await tester.tap(find.text('Synthetic travel'));
        await _until(tester, () => providerWaiting);
        expect(h.provider.requests, hasLength(1));
        expect(h.provider.transactionStates, [false]);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );

        owners.clear();
        await _sameOwnerUpdate(tester, h);
        await _until(
          tester,
          () => owners.contains(null) && owners.last == configuredOwnerId,
        );
        release.complete();
        await _until(tester, () => returned);
        await tester.pumpAndSettle();
        expect(find.byType(SentenceScrambleScreen), findsNothing);
        expect(find.byType(ScoreScreen), findsNothing);
        expect(h.provider.requests, hasLength(1));
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );
        expect(
          await tester.runAsync(() => h.storage.count('answer_attempts')),
          0,
        );
        expect(
          await tester.runAsync(() => h.storage.count('outbox_operations')),
          0,
        );
      } finally {
        if (!release.isCompleted) release.complete();
        await tester.runAsync(() async {
          await ownerProbe?.cancel().timeout(const Duration(seconds: 3));
        });
        await _close(tester, h);
      }
    },
  );

  testWidgets(
    'Sentence Scramble P23 hides old counts after owner invalidation and stale Back cannot pop another route',
    (tester) async {
      final h = (await tester.runAsync(SentenceScrambleNativeHarness.open))!;
      final navigator = GlobalKey<NavigatorState>();
      StreamSubscription<String?>? ownerProbe;
      try {
        final dependencies = await _pumpEntry(tester, h, navigator: navigator);
        final owners = <String?>[];
        await tester.runAsync(() async {
          ownerProbe = dependencies.progress!.watchActiveOwnerId().listen(
            owners.add,
          );
        });
        await _until(
          tester,
          () => owners.isNotEmpty && owners.last == configuredOwnerId,
        );
        await _openCategory(tester);
        await tester.tap(find.text('Synthetic travel'));
        await _ready(tester);
        final screen = tester.widget<SentenceScrambleScreen>(
          find.byType(SentenceScrambleScreen),
        );
        await _finish(tester, h, screen, correct: true);
        final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        final staleBack = score.onBack;
        expect(staleBack, isNotNull);
        expect(find.text('100%'), findsOneWidget);
        final before = await tester.runAsync(h.storage.snapshot);

        owners.clear();
        await _sameOwnerUpdate(tester, h);
        await _until(
          tester,
          () => owners.contains(null) && owners.last == configuredOwnerId,
        );
        await tester.pumpAndSettle();
        expect(find.byType(ScoreScreen), findsNothing);
        expect(find.text('100%'), findsNothing);

        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('Synthetic foreign route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        staleBack!();
        await tester.pumpAndSettle();
        expect(find.text('Synthetic foreign route'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byType(ScoreScreen), findsNothing);
        expect(find.text('100%'), findsNothing);
        expect(await tester.runAsync(h.storage.snapshot), before);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(ChooseModeScreen), findsOneWidget);
        await _assertOneRecreationalAnswer(tester, h, screen);
      } finally {
        await tester.runAsync(() async {
          await ownerProbe?.cancel().timeout(const Duration(seconds: 3));
        });
        await _close(tester, h);
      }
    },
  );

  testWidgets('Sentence Scramble entry stays hidden when quiz is disabled', (
    tester,
  ) async {
    final h = (await tester.runAsync(SentenceScrambleNativeHarness.open))!;
    try {
      await _pumpEntry(
        tester,
        h,
        features: const BuildFieldFeatureRegistry({
          FieldFeature.reading: FieldFeatureState.enabled,
        }),
      );
      expect(
        find.byKey(const ValueKey('sentence-scramble-entry')),
        findsNothing,
      );
      expect(h.provider.requests, isEmpty);
      expect(
        await tester.runAsync(() => h.storage.count('learning_sessions')),
        0,
      );
    } finally {
      await _close(tester, h);
    }
  });
}

Future<AppDependencies> _pumpEntry(
  WidgetTester tester,
  SentenceScrambleNativeHarness h, {
  GlobalKey<NavigatorState>? navigator,
  FieldFeatureRegistry features = const BuildFieldFeatureRegistry.allEnabled(),
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final progress = ProgressUseCases(
    owners: h.storage.owners,
    queries: DriftProgressQueries(h.database),
    nowUtc: () => h.now,
  );
  final initialProgress = (await tester.runAsync(progress.load))!;
  final dependencies = AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _EntryGuestService(),
    database: h.database,
    localOwners: h.storage.owners,
    learning: h.learning,
    progress: progress,
    fieldFeatures: features,
    vocabulary: VocabularyUseCases(
      owners: h.storage.owners,
      vocabulary: DriftVocabularyRepository(h.database),
      generateId: () => 'synthetic-sentence-entry',
      nowUtc: () => h.now,
    ),
  );
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        navigatorKey: navigator,
        home: ChooseModeScreen(loader: () async => initialProgress),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(h.storage.owners.getOrCreateActiveOwner);
  await tester.pump();
  return dependencies;
}

Future<void> _openCategory(WidgetTester tester) async {
  final entry = find
      .byKey(const ValueKey('sentence-scramble-entry'))
      .hitTestable();
  await tester.scrollUntilVisible(
    entry,
    160,
    scrollable: find.byType(Scrollable).last,
  );
  expect(entry, findsOneWidget);
  expect(ModalRoute.of(tester.element(entry))?.isCurrent, isTrue);
  await tester.tap(entry);
  await _until(
    tester,
    () => find.text('Synthetic travel').evaluate().isNotEmpty,
  );
}

Finder get _sentenceScroll => find
    .descendant(
      of: find.byType(SentenceScrambleScreen),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

Future<void> _ready(WidgetTester tester) async {
  await _until(
    tester,
    () => find.byType(SentenceScrambleScreen).evaluate().isNotEmpty,
  );
  await _until(
    tester,
    () =>
        ModalRoute.of(
          tester.element(find.byType(SentenceScrambleScreen)),
        )?.animation?.status ==
        AnimationStatus.completed,
  );
  final input = find.byKey(const ValueKey('sentence-response'));
  await tester.scrollUntilVisible(input, 160, scrollable: _sentenceScroll);
  await _until(tester, () => tester.widget<TextField>(input).enabled == true);
}

Future<void> _finish(
  WidgetTester tester,
  SentenceScrambleNativeHarness h,
  SentenceScrambleScreen screen, {
  required bool correct,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('sentence-response')),
    correct ? screen.session.content.sentence : 'Synthetic wrong sentence.',
  );
  await tester.pump();
  final scrollable = _sentenceScroll;
  final save = find.byKey(const ValueKey('sentence-save'));
  await tester.scrollUntilVisible(save, 160, scrollable: scrollable);
  await _until(
    tester,
    () => tester.widget<FilledButton>(save).onPressed != null,
  );
  await tester.ensureVisible(save);
  await tester.pump();
  await tester.tap(save);
  var persistedAnswers = 0;
  for (var i = 0; i < 150 && persistedAnswers != 1; i++) {
    persistedAnswers = (await tester.runAsync(
      () => h.storage.count('answer_attempts'),
    ))!;
    await tester.pump(const Duration(milliseconds: 20));
    if (persistedAnswers != 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
  }
  expect(
    persistedAnswers,
    1,
    reason: 'Save must commit exactly one real answer',
  );
  final feedback = find.byKey(const ValueKey('sentence-feedback'));
  await tester.scrollUntilVisible(feedback, 160, scrollable: scrollable);
  expect(feedback, findsOneWidget);
  expect(find.byType(ScoreScreen), findsNothing);
  final finish = find.byKey(const ValueKey('sentence-finish'));
  await tester.scrollUntilVisible(finish, 160, scrollable: scrollable);
  expect(tester.widget<FilledButton>(finish).onPressed, isNotNull);
  await tester.tap(finish);
  await _until(tester, () => find.byType(ScoreScreen).evaluate().isNotEmpty);
  await tester.pumpAndSettle();
}

Future<void> _sameOwnerUpdate(
  WidgetTester tester,
  SentenceScrambleNativeHarness h,
) async {
  final changed = await tester.runAsync(
    () =>
        (h.database.update(h.database.localOwners)
              ..where((row) => row.id.equals(configuredOwnerId)))
            .write(
              const db.LocalOwnersCompanion(
                accountState: Value('firebaseBound'),
              ),
            )
            .timeout(const Duration(seconds: 3)),
  );
  expect(changed, 1, reason: 'The actual active owner row must be updated');
  await tester.pump();
}

Future<void> _assertOneRecreationalAnswer(
  WidgetTester tester,
  SentenceScrambleNativeHarness h,
  SentenceScrambleScreen screen,
) async {
  final snapshot = (await tester.runAsync(h.storage.snapshot))!;
  expect(snapshot['learning_sessions'], hasLength(1));
  expect(snapshot['answer_attempts'], hasLength(1));
  expect(snapshot['outbox_operations'], hasLength(1));
  final attempt = jsonDecode(snapshot['answer_attempts']!.single) as Map;
  expect(attempt['owner_id'], configuredOwnerId);
  expect(attempt['session_id'], screen.session.id);
  expect(attempt['word_id'], screen.session.word.id);
  expect(attempt['prompt_mode'], 'sentenceScramble');
  expect(attempt['evidence_class'], 'recreational');
  expect(attempt['provider_provenance'], screen.session.providerProvenance);
  final operation = jsonDecode(snapshot['outbox_operations']!.single) as Map;
  expect(operation['entity_type'], 'attempt');
  expect(operation['entity_id'], attempt['id']);
  expect(operation['payload_version'], 2);
  for (final table in [
    'srs_states',
    'points_ledger_entries',
    'achievement_unlocks',
    'reward_transactions',
    'quest_instances',
    'quest_objective_progress',
    'streak_states',
    'research_consents',
    'experiment_assignments',
    'research_participation_permits',
    'motivation_measurement_runs',
    'motivation_responses',
    'measurement_opportunities',
    'assessment_runs',
    'events_v2',
  ]) {
    expect(snapshot[table], isEmpty, reason: table);
  }
  expect(
    jsonEncode(snapshot),
    isNot(contains(screen.session.content.sentence)),
  );
  expect(h.questEvents, 0);
  expect(h.streakEvents, 0);
  expect(h.provider.requests, hasLength(1));
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Sentence Scramble entry did not reach expected state',
  );
}

Future<void> _close(
  WidgetTester tester,
  SentenceScrambleNativeHarness h,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(() => h.close().timeout(const Duration(seconds: 3)));
}

final class _EntryGuestService extends Fake implements GuestSessionService {}
