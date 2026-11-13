import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('B replaces A immediately while the B query is still pending', (
    tester,
  ) async {
    final a = (await tester.runAsync(() => _Fixture.create('A')))!;
    final b = (await tester.runAsync(() => _Fixture.create('B', hold: true)))!;
    final app = _app(a);
    try {
      await tester.pumpWidget(_scope(a.dependencies, app));
      await _pumpUntil(tester, find.text('private-A'));
      final state = tester.state(find.byType(WeaknessClinicScreen));
      await tester.pumpWidget(_scope(b.dependencies, app));
      await tester.pump();
      expect(tester.state(find.byType(WeaknessClinicScreen)), same(state));
      expect(find.text('private-A'), findsNothing);
      expect(find.text('private-B'), findsNothing);
      b.gate.complete();
      await _pumpUntil(tester, find.text('private-B'));
      expect(find.text('private-A'), findsNothing);
    } finally {
      await _dispose(tester, [a, b]);
    }
  });

  for (final removed in [false, true]) {
    testWidgets(
      'A cannot revive injected sources when scope is ${removed ? 'removed' : 'missing progress'}',
      (tester) async {
        final a = (await tester.runAsync(() => _Fixture.create('A')))!;
        final app = _app(a);
        try {
          await tester.pumpWidget(_scope(a.dependencies, app));
          await _pumpUntil(tester, find.text('private-A'));
          final state = tester.state(find.byType(WeaknessClinicScreen));
          await tester.pumpWidget(removed ? app : _scope(_dependencies(), app));
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(WeaknessClinicScreen)), same(state));
          expect(find.text('private-A'), findsNothing);
          expect(find.text('อ่านข้อมูลจุดอ่อนไม่สำเร็จ'), findsOneWidget);
          expect(find.text('ฝึกคำที่ผิด (1)'), findsNothing);
          expect(a.repository.calls, 0);
        } finally {
          await _dispose(tester, [a]);
        }
      },
    );
  }

  testWidgets('late A data cannot restore A after switching to B', (
    tester,
  ) async {
    final a = (await tester.runAsync(() => _Fixture.create('A', hold: true)))!;
    final b = (await tester.runAsync(() => _Fixture.create('B')))!;
    final app = _app(a);
    try {
      await tester.pumpWidget(_scope(a.dependencies, app));
      await _pumpUntil(
        tester,
        null,
        condition: () => a.gate.started.isCompleted,
      );
      final state = tester.state(find.byType(WeaknessClinicScreen));
      await tester.pumpWidget(_scope(b.dependencies, app));
      a.gate.complete();
      await _pumpUntil(
        tester,
        null,
        condition: () =>
            find.text('private-A').evaluate().isNotEmpty ||
            find.text('private-B').evaluate().isNotEmpty,
      );
      expect(tester.state(find.byType(WeaknessClinicScreen)), same(state));
      expect(find.text('private-A'), findsNothing);
      expect(find.text('private-B'), findsOneWidget);
    } finally {
      await _dispose(tester, [a, b]);
    }
  });

  for (final review in [false, true]) {
    testWidgets(
      'old ${review ? 'review' : 'quiz'} callback cannot launch after scope replacement',
      (tester) async {
        final a = (await tester.runAsync(() => _Fixture.create('A')))!;
        final b = (await tester.runAsync(() => _Fixture.create('B')))!;
        final app = _app(a);
        try {
          await tester.pumpWidget(_scope(a.dependencies, app));
          await _pumpUntil(tester, find.text('private-A'));
          final button = find.widgetWithText(
            review ? OutlinedButton : FilledButton,
            review ? 'ทบทวนคำที่ถึงกำหนด (1)' : 'ฝึกคำที่ผิด (1)',
          );
          final callback = tester.widget<ButtonStyleButton>(button).onPressed!;
          final state = tester.state(find.byType(WeaknessClinicScreen));
          await tester.pumpWidget(_scope(b.dependencies, app));
          await tester.pump();
          expect(tester.state(find.byType(WeaknessClinicScreen)), same(state));
          callback();
          await tester.pumpAndSettle();
          expect(find.byType(QuizScreen), findsNothing);
          expect(find.byType(SrsFlashcardsScreen), findsNothing);
          expect(a.repository.calls, 0);
          expect(b.repository.calls, 0);
        } finally {
          await _dispose(tester, [a, b]);
        }
      },
    );
  }

  testWidgets('standalone injected progress and learning remain usable', (
    tester,
  ) async {
    final a = (await tester.runAsync(() => _Fixture.create('A')))!;
    try {
      await tester.pumpWidget(_app(a));
      await _pumpUntil(tester, find.text('private-A'));
      await tester.tap(find.text('ฝึกคำที่ผิด (1)'));
      await tester.pumpAndSettle();
      final quiz = tester.widget<QuizScreen>(find.byType(QuizScreen));
      expect(quiz.wordIds, ['word-A']);
      expect(quiz.learning, same(a.learning));
      expect(a.repository.calls, greaterThan(0));
    } finally {
      await _dispose(tester, [a]);
    }
  });
}

Widget _app(_Fixture fixture) => MaterialApp(
  key: GlobalKey(),
  home: WeaknessClinicScreen(
    loader: fixture.progress.load,
    learning: fixture.learning,
  ),
);

Widget _scope(AppDependencies dependencies, Widget app) =>
    AppDependenciesScope(dependencies: dependencies, child: app);

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder? finder, {
  bool Function()? condition,
}) async {
  for (var i = 0; i < 80; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (condition?.call() ?? finder!.evaluate().isNotEmpty) return;
  }
  fail('Synthetic weakness query did not settle: ${tester.takeException()}');
}

Future<void> _dispose(WidgetTester tester, List<_Fixture> fixtures) async {
  for (final fixture in fixtures) {
    fixture.gate.complete();
  }
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(() async {
    for (final fixture in fixtures) {
      await fixture.database.close();
    }
  });
  await tester.pump(const Duration(milliseconds: 1));
}

AppDependencies _dependencies({
  ProgressUseCases? progress,
  LearningUseCases? learning,
}) => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _UnusedGuest(),
  progress: progress,
  learning: learning,
);

final class _Fixture {
  _Fixture(this.id, this.gate)
    : database = AppDatabase(NativeDatabase.memory().interceptWith(gate));
  final String id;
  final _HeldQuery gate;
  final AppDatabase database;
  late final ProgressUseCases progress;
  late final LearningUseCases learning;
  late final _LearningRepository repository;
  late final AppDependencies dependencies;

  static Future<_Fixture> create(String id, {bool hold = false}) async {
    final f = _Fixture(id, _HeldQuery());
    await f.database.customStatement(
      'INSERT INTO local_owners (id, created_at_utc_ms) VALUES (?, 1)',
      ['owner-$id'],
    );
    await f.database.customStatement(
      'INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
      'VALUES (?, ?, ?, ?, 1, 1)',
      ['category-$id', 'owner-$id', 'Set $id', 'set $id'],
    );
    await f.database.customStatement(
      'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, '
      'meaning, normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, 'noun', 1, 1)",
      [
        'word-$id',
        'owner-$id',
        'category-$id',
        'private-$id',
        'private-$id',
        'คำส่วนตัว $id',
        'คำส่วนตัว $id',
      ],
    );
    await f.database.customStatement(
      'INSERT INTO learning_sessions (id, owner_id, activity_type, state, started_at_utc_ms, '
      'ended_at_utc_ms, wrong_count, score, app_version, build_id) '
      "VALUES (?, ?, 'quiz', 'completed', 1, 2, 1, 0, 'synthetic', 'scope-test')",
      ['session-$id', 'owner-$id'],
    );
    await f.database.customStatement(
      'INSERT INTO answer_attempts (id, owner_id, session_id, word_id, prompt_mode, is_correct, '
      'attempt_number, occurred_at_utc_ms) VALUES (?, ?, ?, ?, ?, 0, 1, 1)',
      ['attempt-$id', 'owner-$id', 'session-$id', 'word-$id', 'meaningChoice'],
    );
    await f.database.customStatement(
      'INSERT INTO srs_states (id, owner_id, word_id, due_at_utc_ms, algorithm_version) '
      'VALUES (?, ?, ?, 1, 1)',
      ['srs-$id', 'owner-$id', 'word-$id'],
    );
    final owners = _Owners(id);
    f.progress = ProgressUseCases(
      owners: owners,
      queries: DriftProgressQueries(f.database),
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
    f.repository = _LearningRepository();
    f.learning = LearningUseCases(
      owners: owners,
      repository: f.repository,
      generateId: () => 'synthetic-$id',
      nowUtc: () => DateTime.utc(2026, 11, 14),
      buildInfo: const AppBuildInfo.fromEnvironment(),
    );
    f.dependencies = _dependencies(progress: f.progress, learning: f.learning);
    f.gate.armed = hold;
    return f;
  }
}

final class _HeldQuery extends QueryInterceptor {
  bool armed = false;
  final started = Completer<void>();
  final release = Completer<void>();
  void complete() {
    if (!release.isCompleted) release.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (armed && statement.contains('answer_attempts')) {
      armed = false;
      started.complete();
      await release.future;
    }
    return executor.runSelect(statement, args);
  }
}

final class _Owners extends Fake implements LocalOwnerRepository {
  _Owners(this.id);
  final String id;
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner-$id',
        createdAtUtc: DateTime.utc(2026, 11, 14),
      );
}

final class _LearningRepository extends Fake implements LearningRepository {
  var calls = 0;
  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    required int limit,
  }) async {
    calls++;
    return const [];
  }

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async {
    calls++;
    return const [];
  }
}

final class _UnusedGuest extends Fake implements GuestSessionService {}
