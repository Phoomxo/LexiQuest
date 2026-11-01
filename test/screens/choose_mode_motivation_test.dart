import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/motivation/presentation/quest_screen.dart';
import 'package:vocab_learning_app/features/motivation/presentation/today_motivation_panel.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/motivation_runtime.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../features/quest/support/quest_repository_harness.dart';
import '../support/populated_owner_migration_fixture.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets(
    'Today opens actual Quest despite failed aggregate Progress without any table changes',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.open))!;
      addTearDown(() => _close(tester, fixture));
      final before = (await tester.runAsync(
        () => ownerMigrationRows(fixture.h.database),
      ))!;
      expect(before, hasLength(45));
      await tester.pumpWidget(_app(fixture));
      expect(
        await _revealToday(tester),
        isTrue,
        reason: 'Today must remain available when aggregate Progress fails',
      );
      final entry = find.byKey(const ValueKey('today-open-quests'));
      await _until(
        tester,
        () =>
            entry.evaluate().isNotEmpty &&
            tester.widget<OutlinedButton>(entry).onPressed != null,
      );
      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 16));
      await _until(tester, () => entry.hitTestable().evaluate().isNotEmpty);
      await tester.tap(entry);
      await _until(
        tester,
        () =>
            find.byType(QuestScreen).evaluate().length == 1 &&
            find.byKey(const ValueKey('quest-activate')).evaluate().isNotEmpty,
      );
      await _until(
        tester,
        () =>
            tester
                .widget<OutlinedButton>(
                  find.byKey(const ValueKey('quest-activate')),
                )
                .onPressed !=
            null,
      );
      expect(find.text('ภารกิจและวันพัก'), findsOneWidget);
      expect(
        await _real(tester, () => ownerMigrationRows(fixture.h.database)),
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained Today navigation callback is inert after actual coalesced owner A-B-A',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.open))!;
      addTearDown(() => _close(tester, fixture));
      await tester.pumpWidget(_app(fixture));
      expect(
        await _revealToday(tester),
        isTrue,
        reason: 'A captured-owner Today entry must be available',
      );
      final retained = tester
          .widget<TodayMotivationPanel>(find.byType(TodayMotivationPanel))
          .onOpenQuests;
      await _real(tester, () async {
        await fixture.h.storage.switchOwner(configuredOtherOwnerId);
        fixture.h.database.notifyUpdates({
          TableUpdate.onTable(fixture.h.database.localOwners),
        });
        await fixture.h.storage.switchOwner(configuredOwnerId);
        fixture.h.database.notifyUpdates({
          TableUpdate.onTable(fixture.h.database.localOwners),
        });
      });
      await _until(
        tester,
        () =>
            fixture.runtime.currentOwnerId == configuredOwnerId &&
            !fixture.runtime.isActivating,
      );
      await _real(
        tester,
        () => fixture.runtime.activate(
          ownerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
      );
      final before = await _real(
        tester,
        () => ownerMigrationRows(fixture.h.database),
      );
      retained();
      await _flush(tester, 12);
      expect(find.byType(QuestScreen), findsNothing);
      expect(
        await _real(tester, () => ownerMigrationRows(fixture.h.database)),
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden Quest flag omits the Today entry with the runtime present',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => _Fixture.open(hidden: true),
      ))!;
      addTearDown(() => _close(tester, fixture));
      final before = (await tester.runAsync(
        () => ownerMigrationRows(fixture.h.database),
      ))!;
      await tester.pumpWidget(_app(fixture));
      expect(await _revealToday(tester), isFalse);
      expect(find.byType(TodayMotivationPanel), findsNothing);
      expect(find.byKey(const ValueKey('today-open-quests')), findsNothing);
      expect(
        await _real(tester, () => ownerMigrationRows(fixture.h.database)),
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<ProgressSnapshot> _failedProgress() => Future<ProgressSnapshot>.error(
  StateError('synthetic aggregate unavailable'),
);

Widget _app(_Fixture fixture) => AppDependenciesScope(
  dependencies: fixture.dependencies,
  child: MaterialApp(
    theme: M3Theme.lightTheme,
    home: ChooseModeScreen(
      loader: _failedProgress,
      ownerChanges: fixture.ownerChanges,
    ),
  ),
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await _flush(tester, 1);
    if (ready()) return;
  }
  fail(
    'The actual owner-bound motivation entry did not become ready. '
    'Rendered: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().take(24).join(' | ')}',
  );
}

Future<bool> _revealToday(WidgetTester tester) async {
  await _flush(tester, 6);
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 16));
  for (var step = 0; step < 45; step++) {
    final panel = find.byType(TodayMotivationPanel);
    if (panel.evaluate().isNotEmpty) {
      await tester.ensureVisible(panel);
      return true;
    }
    await tester.drag(scrollable, const Offset(0, -200));
    await _flush(tester, 1);
  }
  return false;
}

Future<void> _flush(WidgetTester tester, int count) async {
  for (var index = 0; index < count; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _close(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 16));
  var stage = 'runtime.dispose';
  await _real(tester, () async {
    await fixture.runtime.dispose();
    stage = 'database.close';
    await fixture.h.close();
    stage = 'closed';
  }, stage: () => stage);
}

Future<T> _real<T>(
  WidgetTester tester,
  Future<T> Function() operation, {
  String Function()? stage,
}) async {
  var done = false;
  T? value;
  Object? error;
  StackTrace? stack;
  await tester.runAsync(() async {
    unawaited(
      Future<T>.sync(operation).then<void>(
        (result) {
          value = result;
          done = true;
        },
        onError: (Object failure, StackTrace trace) {
          error = failure;
          stack = trace;
          done = true;
        },
      ),
    );
  });
  for (var frame = 0; frame < 240 && !done; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  if (!done) {
    fail(
      'Synthetic ChooseMode IO did not finish: ${stage?.call() ?? 'operation'}',
    );
  }
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value as T;
}

final class _Fixture {
  _Fixture(this.h, this.runtime, this.dependencies, this.ownerChanges);
  final QuestHarness h;
  final MotivationRuntime runtime;
  final AppDependencies dependencies;
  final Stream<String?> ownerChanges;

  static Future<_Fixture> open({bool hidden = false}) async {
    final h = await QuestHarness.open();
    var id = 0;
    final runtime = MotivationRuntime(
      database: h.database,
      ownerWrites: h.storage.ownerWrites,
      owners: h.storage.owners,
      nowUtc: () => h.now,
      generateId: () => 'synthetic-entry-${++id}',
    );
    runtime.setForeground(true);
    await runtime.activate(
      ownerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    final progress = ProgressUseCases(
      owners: h.storage.owners,
      queries: DriftProgressQueries(h.database),
      nowUtc: () => h.now,
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _NoGuest(),
      database: h.database,
      localOwners: h.storage.owners,
      progress: progress,
      motivation: runtime,
      quest: runtime.quest,
      streak: runtime.streak,
      features: hidden
          ? const BuildFeatureRegistry({Feature.questV2: FeatureState.hidden})
          : const BuildFeatureRegistry.fieldDefaults(),
    );
    final io = Zone.current;
    final ownerChanges = Stream<String?>.multi((events) {
      final source = io.run(
        () => progress.watchActiveOwnerId().listen(
          events.add,
          onError: events.addError,
          onDone: events.close,
        ),
      );
      events.onCancel = () => io.run(source.cancel);
    }, isBroadcast: true);
    return _Fixture(h, runtime, dependencies, ownerChanges);
  }
}

final class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('This local entry must not authenticate');
}
