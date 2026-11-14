import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets(
    'Quiz hides its prompts and rejects a retained choice on owner switch',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      try {
        await fixture.open(
          tester,
          const QuizScreen(
            categoryId: 'category-a',
            categoryName: 'ชุดคำส่วนตัว A',
            expectedOwnerId: _ownerA,
          ),
        );
        await _wait(
          tester,
          () => find.text('synthetic-station-a').evaluate().isNotEmpty,
          'original prompt',
        );
        final choose = find.widgetWithText(FilledButton, 'สถานีเดิม');
        final stale = tester.widget<FilledButton>(choose).onPressed!;

        await fixture.switchOwner(tester);
        await _wait(
          tester,
          () => find.text('synthetic-station-a').evaluate().isEmpty,
          'old prompt removal',
        );
        expect(find.byType(QuizScreen), findsOneWidget);
        expect(find.text('ชุดคำส่วนตัว A'), findsNothing);
        expect(choose, findsNothing);
        stale();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(ScoreScreen), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final session = await fixture.database
              .select(fixture.database.learningSessions)
              .getSingle();
          expect(session.ownerId, _ownerA);
          expect((session.correctCount, session.wrongCount), (0, 0));
          expect(
            await fixture.database
                .select(fixture.database.answerAttempts)
                .get(),
            isEmpty,
          );
          expect(
            await fixture.database
                .select(fixture.database.outboxOperations)
                .get(),
            isEmpty,
          );
        });
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'saved Score hides original wording and rejects stale repair on owner switch',
    (tester) async {
      final fixture = await _Fixture.create(tester);
      var repairs = 0;
      try {
        await fixture.open(
          tester,
          ScoreScreen(
            correctAnswers: 0,
            wrongAnswers: 1,
            sessionId: 'private-round',
            categoryName: 'ชุดคำส่วนตัว A',
            expectedOwnerId: _ownerA,
            showOriginalHistory: true,
            originalAnswers: const [
              (
                question: QuizQuestion(
                  word: _station,
                  options: ['สถานีเดิม', 'ตั๋วเดิม'],
                ),
                chosenAnswer: 'ตั๋วเดิม',
                isCorrect: false,
              ),
            ],
            mistakes: const [_station],
            onPracticeMistakes: () => repairs++,
          ),
        );
        final originalResponse = find.text('ครั้งก่อนเลือก ตั๋วเดิม');
        await _wait(
          tester,
          () => originalResponse.evaluate().isNotEmpty,
          'original response',
        );
        final repair = find.widgetWithText(FilledButton, 'ฝึกคำที่ผิด (1)');
        final stale = tester.widget<FilledButton>(repair).onPressed!;

        await fixture.switchOwner(tester);
        await _wait(
          tester,
          () => originalResponse.evaluate().isEmpty,
          'old response removal',
        );
        expect(find.byType(ScoreScreen), findsOneWidget);
        expect(
          find.byKey(const ValueKey('score-session:private-round')),
          findsNothing,
        );
        expect(find.text('ชุดคำส่วนตัว A'), findsNothing);
        expect(find.text('synthetic-station-a'), findsNothing);
        expect(find.text('คำตอบจากรอบเดิม'), findsNothing);
        expect(repair, findsNothing);
        stale();
        await tester.pump(const Duration(milliseconds: 500));
        expect(repairs, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}

const _ownerA = 'synthetic-owner-a';
const _ownerB = 'synthetic-owner-b';
const _station = QuizWord(
  id: 'word-1',
  categoryId: 'category-a',
  spelling: 'synthetic-station-a',
  meaning: 'สถานีเดิม',
  partOfSpeech: 'noun',
);
const _ticket = QuizWord(
  id: 'word-2',
  categoryId: 'category-a',
  spelling: 'synthetic-ticket-a',
  meaning: 'ตั๋วเดิม',
  partOfSpeech: 'noun',
);

final class _Fixture {
  _Fixture(this.database, this.dependencies);
  final AppDatabase database;
  final AppDependencies dependencies;

  static Future<_Fixture> create(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final database = AppDatabase(NativeDatabase.memory());
        final now = DateTime.utc(2026, 11, 14);
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(id: _ownerA, createdAtUtcMs: 1),
            );
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: _ownerB,
                createdAtUtcMs: 1,
                isActive: const Value(false),
              ),
            );
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'category-a',
                ownerId: _ownerA,
                name: 'ชุดคำส่วนตัว A',
                normalizedName: 'ชุดคำส่วนตัว a',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        for (final word in [_station, _ticket]) {
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: word.id,
                  ownerId: _ownerA,
                  categoryId: word.categoryId,
                  spelling: word.spelling,
                  normalizedSpelling: word.spelling,
                  meaning: word.meaning,
                  normalizedMeaning: word.meaning,
                  partOfSpeech: word.partOfSpeech,
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
        }
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => throw StateError('Synthetic owner missing'),
          nowUtc: () => now,
        );
        return _Fixture(
          database,
          AppDependencies(
            runtimeStatus: const AppRuntimeStatus(
              localData: RuntimeAvailability.ready,
              firebase: RuntimeAvailability.unavailable,
              supabase: RuntimeAvailability.unavailable,
              backends: RuntimeAvailability.unavailable,
            ),
            config: null,
            guestSessionService: _GuestSession(),
            database: database,
            localOwners: owners,
            learning: LearningUseCases(
              owners: owners,
              repository: DriftLearningRepository(database),
              generateId: () => 'synthetic-owner-switch-round',
              nowUtc: () => now,
              buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
            ),
          ),
        );
      }))!;

  Future<void> open(WidgetTester tester, Widget page) => tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(home: page),
    ),
  );

  Future<void> switchOwner(WidgetTester tester) => _drive(
    tester,
    database.transaction(() async {
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals(_ownerA)))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals(_ownerB)))
          .write(const LocalOwnersCompanion(isActive: Value(true)));
    }),
    'active owner switch',
  );

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _drive(tester, database.close(), 'database close');
  }
}

Future<void> _drive(
  WidgetTester tester,
  Future<void> operation,
  String stage,
) async {
  var done = false;
  final pending = operation.whenComplete(() => done = true);
  unawaited(pending.then<void>((_) {}, onError: (Object _) {}));
  await _wait(tester, () => done, stage);
  await pending;
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  String stage,
) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  fail('Timed out waiting for $stage');
}

final class _GuestSession extends Fake implements GuestSessionService {}
