import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/add_vocab_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _fallback = 'รอบนี้ยังไม่มีความหมายอื่นให้เลือก';
const _add = ValueKey('quiz-add-word');

void main() {
  for (final duplicate in [false, true]) {
    testWidgets(
      'one meaning duplicate=$duplicate offers no automatic assessment or reward',
      (tester) async {
        final f = await tester.runAsync(
          () => _Fixture.create(duplicate: duplicate),
        );
        final fixture = f!;
        try {
          final before = await tester.runAsync(fixture.evidence);
          await _open(tester, fixture);
          await _pumpUntil(tester, find.text(_fallback));
          expect(find.text('ชุด A'), findsOneWidget);
          expect(find.text('เฉลยคำตอบ'), findsNothing);
          expect(find.widgetWithText(FilledButton, 'สถานี'), findsNothing);
          expect(find.text('ดูผลการเรียน'), findsNothing);
          expect(find.byType(ScoreScreen), findsNothing);
          expect(await tester.runAsync(fixture.evidence), before);
          final sessions = await tester.runAsync(
            () => fixture.database
                .select(fixture.database.learningSessions)
                .get(),
          );
          // The existing Back contract permits an active zero-attempt session.
          expect(sessions, hasLength(1));
          expect(sessions!.single.state, 'active');
          expect(sessions.single.correctCount, 0);
          expect(sessions.single.wrongCount, 0);
        } finally {
          await _dispose(tester, fixture);
        }
      },
    );
  }

  testWidgets(
    'canceling Add Word keeps the same fallback and creates no rows',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      try {
        await _open(tester, f);
        await _pumpUntil(tester, find.text(_fallback));
        final before = await tester.runAsync(
          () => f.evidence(includeActive: true),
        );
        await tester.tap(find.byKey(_add));
        await _pumpUntil(tester, find.byType(AddWordScreen));
        expect(find.text('เพิ่มคำศัพท์'), findsOneWidget);
        expect(find.text('ตรวจคำจากภาพ'), findsNothing);
        await tester.pageBack();
        await _pumpUntil(tester, find.text(_fallback));
        await tester.pumpAndSettle();
        expect(
          await tester.runAsync(() => f.evidence(includeActive: true)),
          before,
        );
      } finally {
        await _dispose(tester, f);
      }
    },
  );

  testWidgets(
    'adding a distinct meaning resumes exact A and preserves old result and B',
    (tester) async {
      final f = (await tester.runAsync(_Fixture.create))!;
      try {
        final oldId = (await tester.runAsync(f.seedOldResult))!;
        final oldResult = (await tester.runAsync(
          () => f.database
              .customSelect(
                "SELECT * FROM learning_sessions WHERE id = '$oldId'",
              )
              .get(),
        ));
        final bBefore = await tester.runAsync(f.wordsB);
        await _open(tester, f);
        await _pumpUntil(tester, find.text(_fallback));
        await tester.tap(find.byKey(_add));
        await _pumpUntil(tester, find.byKey(const ValueKey('word-field')));
        await _fillWord(tester);
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntil(tester, find.text('เลือกคำแปลที่ตรงกับคำศัพท์'));
        await tester.pumpAndSettle();
        expect(find.text('ชุด A'), findsOneWidget);
        expect(find.text('banana'), findsNothing);
        expect(find.text('กล้วย'), findsNothing);
        expect(find.byType(AddWordScreen), findsNothing);
        for (final answer in ['สถานี', 'ตั๋ว']) {
          await tester.ensureVisible(find.widgetWithText(FilledButton, answer));
          await tester.tap(find.widgetWithText(FilledButton, answer));
          await _pumpUntil(
            tester,
            find.text(answer == 'สถานี' ? 'คำถามถัดไป' : 'ดูผลการเรียน'),
          );
          await tester.ensureVisible(
            find.text(answer == 'สถานี' ? 'คำถามถัดไป' : 'ดูผลการเรียน'),
          );
          await tester.tap(
            find.text(answer == 'สถานี' ? 'คำถามถัดไป' : 'ดูผลการเรียน'),
          );
          await tester.pump();
        }
        await _pumpUntil(tester, find.byType(ScoreScreen));
        await tester.pumpAndSettle();
        final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
        expect(score.correctAnswers, 2);
        expect(score.wrongAnswers, 0);
        expect(score.sessionId, isNot(oldId));
        expect(score.categoryName, 'ชุด A');
        expect(find.text('กลับไปที่ชุดคำ'), findsOneWidget);
        final latest = (await tester.runAsync(
          () => DriftProgressQueries(f.database).loadLatestSessionForCategory(
            ownerId: f.ownerId,
            categoryId: f.categoryA,
          ),
        ))!;
        expect(latest.summary.id, score.sessionId);
        expect(latest.summary.correctCount, 2);
        expect(await tester.runAsync(f.wordsB), bBefore);
        final oldAfter = await tester.runAsync(
          () => f.database
              .customSelect(
                "SELECT * FROM learning_sessions WHERE id = '$oldId'",
              )
              .get(),
        );
        expect(
          oldAfter!.map((row) => row.data).toList(),
          oldResult!.map((row) => row.data).toList(),
        );
        final words = (await tester.runAsync(
          () => f.database.select(f.database.vocabularyWords).get(),
        ))!;
        final added = words.singleWhere((word) => word.spelling == 'ticket');
        expect(added.categoryId, f.categoryA);
        expect(added.ownerId, f.ownerId);
        expect(added.source, 'manual');
      } finally {
        await _dispose(tester, f);
      }
    },
  );

  for (final changeScope in [false, true]) {
    testWidgets(
      'fallback normal Add Word rejects ${changeScope ? 'Scope' : 'owner'} change before Save',
      (tester) async {
        final f = (await tester.runAsync(_Fixture.create))!;
        final other = changeScope
            ? (await tester.runAsync(() => _Fixture.create(prefix: 'x')))!
            : null;
        final app = MaterialApp(
          home: QuizScreen(
            categoryId: f.categoryA,
            categoryName: 'ชุด A',
            learning: f.learning,
          ),
        );
        try {
          await tester.pumpWidget(
            AppDependenciesScope(dependencies: f.dependencies, child: app),
          );
          await _pumpUntil(tester, find.text(_fallback));
          await tester.tap(find.byKey(_add));
          await _pumpUntil(tester, find.byKey(const ValueKey('word-field')));
          final editorState = tester.state(find.byType(AddWordScreen));
          final before = await tester.runAsync(
            () => f.evidence(includeActive: true),
          );
          final otherBefore = other == null
              ? null
              : await tester.runAsync(
                  () => other.evidence(includeActive: true),
                );
          if (changeScope) {
            await tester.pumpWidget(
              AppDependenciesScope(
                dependencies: other!.dependencies,
                child: app,
              ),
            );
            expect(tester.state(find.byType(AddWordScreen)), same(editorState));
          } else {
            await tester.runAsync(() async {
              await f.database.customStatement(
                'UPDATE local_owners SET is_active = 0',
              );
              await f.database
                  .into(f.database.localOwners)
                  .insert(
                    LocalOwnersCompanion.insert(
                      id: 'owner-switched',
                      createdAtUtcMs: 2,
                    ),
                  );
            });
          }
          await _fillWord(tester);
          await tester.tap(find.byKey(const ValueKey('save-word')));
          await _pumpUntil(
            tester,
            find.text('บัญชีหรือชุดคำเปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่'),
          );
          expect(find.byType(AddWordScreen), findsOneWidget);
          expect(
            await tester.runAsync(() => f.evidence(includeActive: true)),
            before,
          );
          if (other != null) {
            expect(
              await tester.runAsync(() => other.evidence(includeActive: true)),
              otherBefore,
            );
          }
        } finally {
          await _dispose(tester, f);
          if (other != null) await tester.runAsync(other.database.close);
        }
      },
    );
  }

  testWidgets('hidden vocabulary offers no Add Word route from the fallback', (
    tester,
  ) async {
    final f = (await tester.runAsync(_Fixture.create))!;
    try {
      await _open(
        tester,
        f,
        features: const BuildFieldFeatureRegistry({
          FieldFeature.quiz: FieldFeatureState.enabled,
          FieldFeature.vocabulary: FieldFeatureState.hidden,
        }),
      );
      await _pumpUntil(tester, find.text(_fallback));
      expect(find.byKey(_add), findsNothing);
      expect(find.byType(AddWordScreen), findsNothing);
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.answerAttempts).get(),
        ),
        isEmpty,
      );
    } finally {
      await _dispose(tester, f);
    }
  });

  for (final replacement in ['B', 'removed']) {
    testWidgets(
      'edit Word A without an explicit owner rejects Scope $replacement before Save',
      (tester) async {
        final a = (await tester.runAsync(_Fixture.create))!;
        final b = (await tester.runAsync(() => _Fixture.create(prefix: 'x')))!;
        final word = (await tester.runAsync(
          () => a.vocabulary.watchWords(a.categoryA).first,
        ))!.single;
        final app = MaterialApp(
          key: GlobalKey(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddWordScreen(
                      categoryId: a.categoryA,
                      vocabulary: a.vocabulary,
                      word: word,
                    ),
                  ),
                ),
                child: const Text('แก้คำ A'),
              ),
            ),
          ),
        );
        try {
          await tester.pumpWidget(
            AppDependenciesScope(dependencies: a.dependencies, child: app),
          );
          await tester.tap(find.text('แก้คำ A'));
          await _pumpUntil(tester, find.byType(AddWordScreen));
          await tester.pumpAndSettle();
          final state = tester.state(find.byType(AddWordScreen));
          final beforeA = await tester.runAsync(
            () => a.evidence(includeActive: true),
          );
          final beforeB = await tester.runAsync(
            () => b.evidence(includeActive: true),
          );
          await tester.pumpWidget(
            replacement == 'B'
                ? AppDependenciesScope(dependencies: b.dependencies, child: app)
                : SizedBox(child: app),
          );
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(AddWordScreen)), same(state));
          await _fillWord(tester);
          await tester.tap(find.byKey(const ValueKey('save-word')));
          await _pumpUntil(
            tester,
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  (widget.data == 'แก้คำ A' ||
                      widget.data ==
                          'บัญชีหรือชุดคำเปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่'),
            ),
          );
          expect(
            await tester.runAsync(() => a.evidence(includeActive: true)),
            beforeA,
          );
          expect(
            await tester.runAsync(() => b.evidence(includeActive: true)),
            beforeB,
          );
          expect(find.byType(AddWordScreen), findsOneWidget);
          expect(
            find.text('บัญชีหรือชุดคำเปลี่ยนแล้ว กรุณากลับไปเลือกชุดใหม่'),
            findsOneWidget,
          );
        } finally {
          await _dispose(tester, a);
          await tester.runAsync(b.database.close);
        }
      },
    );
  }

  testWidgets(
    'replacing Scope drops private A even while the route retains injected learning A',
    (tester) async {
      final a = (await tester.runAsync(() => _Fixture.create(contrast: true)))!;
      final b = (await tester.runAsync(() => _Fixture.create(prefix: 'x')))!;
      final app = MaterialApp(
        home: QuizScreen(
          categoryId: a.categoryA,
          categoryName: 'ชุด A',
          learning: a.learning,
        ),
      );
      try {
        await tester.pumpWidget(
          AppDependenciesScope(dependencies: a.dependencies, child: app),
        );
        await _pumpUntil(tester, find.text('station-a'));
        final state = tester.state(find.byType(QuizScreen));
        await tester.pumpWidget(
          AppDependenciesScope(dependencies: b.dependencies, child: app),
        );
        await tester.pump();
        expect(tester.state(find.byType(QuizScreen)), same(state));
        expect(find.text('station-a'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'สถานี'), findsNothing);
        expect(find.text('ชุด A'), findsNothing);
        expect(
          await tester.runAsync(
            () => a.database.select(a.database.answerAttempts).get(),
          ),
          isEmpty,
        );
        expect(
          await tester.runAsync(
            () => b.database.select(b.database.answerAttempts).get(),
          ),
          isEmpty,
        );
      } finally {
        await _dispose(tester, a);
        await tester.runAsync(b.database.close);
      }
    },
  );

  for (final replacement in ['B', 'removed']) {
    testWidgets(
      'saved Quiz Score rejects Scope $replacement and its captured repair action',
      (tester) async {
        final a = (await tester.runAsync(
          () => _Fixture.create(contrast: true),
        ))!;
        final b = (await tester.runAsync(() => _Fixture.create(prefix: 'x')))!;
        final app = MaterialApp(
          key: GlobalKey(),
          home: QuizScreen(
            categoryId: a.categoryA,
            categoryName: 'ชุด A',
            learning: a.learning,
          ),
        );
        try {
          await tester.pumpWidget(
            AppDependenciesScope(dependencies: a.dependencies, child: app),
          );
          await _pumpUntil(tester, find.text('station-a'));
          await tester.tap(find.widgetWithText(FilledButton, 'ตั๋ว'));
          await _pumpUntil(tester, find.text('คำถามถัดไป'));
          await tester.tap(find.text('คำถามถัดไป'));
          await tester.pump();
          await tester.tap(find.widgetWithText(FilledButton, 'ตั๋ว'));
          await _pumpUntil(tester, find.text('ดูผลการเรียน'));
          await tester.tap(find.text('ดูผลการเรียน'));
          await _pumpUntil(tester, find.byType(ScoreScreen));
          await tester.pumpAndSettle();
          final score = tester.widget<ScoreScreen>(find.byType(ScoreScreen));
          final repair = score.onPracticeMistakes!;
          final sessionId = score.sessionId!;
          expect(score.mistakes.single.spelling, 'station-a');
          expect(score.correctAnswers, 1);
          expect(score.wrongAnswers, 1);
          final beforeA = await tester.runAsync(
            () => a.evidence(includeActive: true),
          );
          final beforeB = await tester.runAsync(
            () => b.evidence(includeActive: true),
          );
          await tester.pumpWidget(
            replacement == 'B'
                ? AppDependenciesScope(dependencies: b.dependencies, child: app)
                : SizedBox(child: app),
          );
          await tester.pump();
          repair();
          await tester.pump();
          await _pumpUntil(
            tester,
            find.text(
              replacement == 'B'
                  ? 'ยังไม่มีคำศัพท์สำหรับแบบทดสอบ กรุณาเพิ่มคำศัพท์ก่อน'
                  : 'เปิดแบบทดสอบไม่สำเร็จ ข้อมูลในเครื่องยังไม่ถูกเปลี่ยนแปลง',
              skipOffstage: false,
            ),
          );

          expect(
            find.byType(QuizScreen, skipOffstage: false),
            findsOneWidget,
            reason:
                'a captured A repair action must not launch a B practice route',
          );
          expect(
            find.byKey(
              ValueKey('score-session:$sessionId'),
              skipOffstage: false,
            ),
            findsNothing,
          );
          expect(
            find.textContaining('station-a', skipOffstage: false),
            findsNothing,
          );
          expect(find.text('ชุด A', skipOffstage: false), findsNothing);
          expect(
            await tester.runAsync(() => a.evidence(includeActive: true)),
            beforeA,
          );
          expect(
            await tester.runAsync(() => b.evidence(includeActive: true)),
            beforeB,
          );
        } finally {
          await _dispose(tester, a);
          await tester.runAsync(b.database.close);
        }
      },
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  _Fixture f, {
  FieldFeatureRegistry? features,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: f.dependencies,
      child: MaterialApp(
        home: QuizScreen(
          categoryId: f.categoryA,
          categoryName: 'ชุด A',
          learning: f.learning,
          featureRegistry: features,
        ),
      ),
    ),
  );
}

Future<void> _fillWord(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('word-field')), 'ticket');
  await tester.enterText(find.byKey(const ValueKey('meaning-field')), 'ตั๋ว');
  await tester.enterText(
    find.byKey(const ValueKey('part-of-speech-field')),
    'noun',
  );
  await tester.ensureVisible(find.byKey(const ValueKey('save-word')));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 80; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _dispose(WidgetTester tester, _Fixture f) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(f.database.close);
  await tester.pump(const Duration(milliseconds: 1));
}

final class _Fixture {
  late final AppDatabase database;
  late final DriftLocalOwnerRepository owners;
  late final VocabularyUseCases vocabulary;
  late final LearningUseCases learning;
  late final AppDependencies dependencies;
  late final String ownerId;
  late final String categoryA;
  late final String categoryB;

  static Future<_Fixture> create({
    bool duplicate = false,
    bool contrast = false,
    String prefix = 'a',
  }) async {
    final f = _Fixture();
    var id = 0;
    var tick = 0;
    f.database = AppDatabase(NativeDatabase.memory());
    f.owners = DriftLocalOwnerRepository(
      f.database,
      generateId: () => prefix,
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    f.ownerId = (await f.owners.getOrCreateActiveOwner()).id;
    f.vocabulary = VocabularyUseCases(
      owners: f.owners,
      vocabulary: DriftVocabularyRepository(f.database),
      generateId: () => '$prefix:${++id}',
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    f.categoryA = (await f.vocabulary.createCategory(
      'ชุด ${prefix.toUpperCase()}',
    )).id;
    f.categoryB = (await f.vocabulary.createCategory('ชุด B')).id;
    for (final word in [
      (f.categoryA, 'station-$prefix', 'สถานี'),
      if (duplicate) (f.categoryA, 'terminal-$prefix', 'สถานี'),
      if (contrast) (f.categoryA, 'ticket', 'ตั๋ว'),
      (f.categoryB, 'banana', 'กล้วย'),
    ]) {
      await f.vocabulary.createWord(
        CreateWordCommand(
          categoryId: word.$1,
          spelling: word.$2,
          meaning: word.$3,
          partOfSpeech: 'noun',
        ),
      );
    }
    f.learning = LearningUseCases(
      owners: f.owners,
      repository: DriftLearningRepository(f.database),
      generateId: () => '$prefix:learning:${++id}',
      nowUtc: () =>
          DateTime.utc(2026, 11, 14, 1).add(Duration(seconds: tick++)),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    f.dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _Guest(),
      database: f.database,
      localOwners: f.owners,
      vocabulary: f.vocabulary,
      learning: f.learning,
    );
    return f;
  }

  Future<String> seedOldResult() async {
    final old = await learning.startQuiz(categoryId: categoryA);
    await learning.recordAnswer(
      sessionId: old.id,
      wordId: old.questions.single.word.id,
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 50,
      attemptNumber: 1,
    );
    await learning.finishSession(old.id);
    return old.id;
  }

  Future<List<Map<String, Object?>>> wordsB() async =>
      (await database
              .customSelect(
                "SELECT * FROM vocabulary_words WHERE category_id = '$categoryB' ORDER BY id",
              )
              .get())
          .map((row) => row.data)
          .toList();

  Future<Map<String, Object?>> evidence({bool includeActive = false}) async {
    final result = <String, Object?>{};
    for (final table in [
      'vocabulary_words',
      'answer_attempts',
      'points_ledger_entries',
      'reward_transactions',
      'srs_states',
      'outbox_operations',
      'learning_sessions',
    ]) {
      final where = table == 'learning_sessions' && !includeActive
          ? "WHERE state = 'completed'"
          : '';
      final key = table == 'outbox_operations' ? 'operation_id' : 'id';
      result[table] =
          (await database
                  .customSelect('SELECT * FROM $table $where ORDER BY $key')
                  .get())
              .map((row) => row.data)
              .toList();
    }
    return result;
  }
}

final class _Guest extends Fake implements GuestSessionService {}
