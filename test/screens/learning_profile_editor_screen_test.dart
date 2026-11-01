import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LearningProfile;
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning_profile/data/drift_learning_profile_repository.dart';
import 'package:vocab_learning_app/features/learning_profile/application/learning_profile_use_cases.dart';
import 'package:vocab_learning_app/features/learning_profile/domain/learning_profile.dart';
import 'package:vocab_learning_app/features/learning_profile/domain/learning_profile_repository.dart';
import 'package:vocab_learning_app/features/learning_profile/presentation/learning_profile_editor_screen.dart';

void main() {
  testWidgets(
    'actual editor acknowledges a durable profile and reloads it after reopening SQLite',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lexiquest-profile-ui-'),
      ))!;
      final file = File('${directory.path}/profile.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      await tester.runAsync(() async {
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: 'synthetic-profile-owner',
                createdAtUtcMs: 1,
                isActive: const Value(true),
              ),
            );
      });
      LearningProfileUseCases createProfile() => LearningProfileUseCases(
        repository: DriftLearningProfileRepository(
          database: database,
          ownerWrites: DriftOwnerWriteCoordinator(
            database,
            nowUtc: () => DateTime.utc(2026, 11, 1),
          ),
        ),
        nowUtc: () => DateTime.utc(2026, 11, 1),
      );
      var profile = createProfile();
      try {
        await tester.pumpWidget(
          MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
        );
        await _until(
          tester,
          find.byKey(const ValueKey('learning-profile-goal')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('learning-profile-goal')),
          'Synthetic retained goal',
        );
        await tester.enterText(
          find.byKey(const ValueKey('learning-profile-date')),
          '2026-12-31',
        );
        final zone = find.byKey(const ValueKey('learning-profile-timezone-0'));
        await tester.ensureVisible(zone);
        await tester.tap(zone);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Asia/Bangkok'),
          250,
          scrollable: find.byType(Scrollable).last,
          maxScrolls: 80,
        );
        await tester.tap(find.text('Asia/Bangkok').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('learning-profile-save')),
        );
        await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
        await _until(tester, find.text('บันทึกแผนการเรียนแล้ว'));
        final stored = (await tester.runAsync(
          () => database
              .customSelect('SELECT * FROM learning_profiles')
              .getSingle(),
        ))!;
        expect(stored.read<String>('goal_text'), 'Synthetic retained goal');
        expect(stored.read<String>('target_date'), '2026-12-31');
        expect(stored.read<String>('learning_timezone_id'), 'Asia/Bangkok');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await profile.dispose();
          await database.close();
        });
        database = AppDatabase(NativeDatabase(file));
        profile = createProfile();
        await tester.pumpWidget(
          MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
        );
        await _until(tester, find.text('Synthetic retained goal'));
        expect(find.text('2026-12-31'), findsOneWidget);
        final counts = (await tester.runAsync(() async {
          final result = <String, int>{};
          for (final table in database.allTables) {
            final count = await database
                .customSelect(
                  'SELECT COUNT(*) AS n FROM "${table.actualTableName}"',
                )
                .getSingle();
            result[table.actualTableName] = count.read<int>('n');
          }
          return result;
        }))!;
        for (final entry in counts.entries) {
          expect(
            entry.value,
            const {'local_owners', 'learning_profiles'}.contains(entry.key)
                ? 1
                : 0,
            reason: entry.key,
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await profile.dispose();
          await database.close();
          if (await file.exists()) await file.delete();
          await directory.delete();
        });
      }
    },
  );

  testWidgets(
    'editor saves preferences and a civil target only after acknowledgement',
    (tester) async {
      final repository = _Repository();
      final profile = _useCases(repository);
      addTearDown(profile.dispose);
      addTearDown(repository.close);
      await tester.pumpWidget(
        MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('learning-profile-goal')),
        'Read a book',
      );
      await tester.enterText(
        find.byKey(const ValueKey('learning-profile-date')),
        '2026-12-31',
      );
      await tester.enterText(
        find.byKey(const ValueKey('learning-profile-minutes')),
        '25',
      );
      final pending = Completer<LearningProfile>();
      repository.saveResult = pending.future;
      await tester.ensureVisible(
        find.byKey(const ValueKey('learning-profile-save')),
      );
      await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
      await tester.pump();
      expect(find.text('กำลังบันทึกแผนการเรียน'), findsOneWidget);
      expect(find.text('บันทึกแผนการเรียนแล้ว'), findsNothing);
      expect(
        repository.changes.single.draft.targetDate,
        LearningCivilDate(2026, 12, 31),
      );
      expect(repository.changes.single.draft.dailyMinutes, 25);
      pending.complete(_saved(repository.changes.single));
      await tester.pumpAndSettle();
      expect(find.text('บันทึกแผนการเรียนแล้ว'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit reload replaces unsaved and previously stored interests',
    (tester) async {
      LearningProfileSnapshot stored(List<String> interests) =>
          LearningProfileSnapshot(
            ownerId: 'a',
            profile: LearningProfile(
              ownerId: 'a',
              revision: 1,
              draft: LearningProfileDraft(
                onboardingState: LearningOnboardingState.completed,
                goalText: 'Stored goal',
                interestCodes: interests,
              ),
              updatedAtUtc: DateTime.utc(2026, 11, 1),
            ),
          );
      final repository = _Repository()..snapshot = stored(['work']);
      final profile = _useCases(repository);
      addTearDown(profile.dispose);
      addTearDown(repository.close);
      await tester.pumpWidget(
        MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
      );
      await tester.pumpAndSettle();
      final work = find.widgetWithText(FilterChip, 'การทำงาน');
      final travel = find.widgetWithText(FilterChip, 'การเดินทาง');
      final study = find.widgetWithText(FilterChip, 'การเรียน');
      expect(tester.widget<FilterChip>(work).selected, isTrue);
      await tester.ensureVisible(travel);
      await tester.tap(travel);
      await tester.pump();
      expect(tester.widget<FilterChip>(travel).selected, isTrue);
      repository.snapshot = stored(['study']);
      await tester.ensureVisible(find.text('โหลดแผนล่าสุด'));
      await tester.tap(find.text('โหลดแผนล่าสุด'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(study).selected, isTrue);
      expect(tester.widget<FilterChip>(work).selected, isFalse);
      expect(tester.widget<FilterChip>(travel).selected, isFalse);
      expect(repository.changes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('late resume load preserves a newly typed draft through saving', (
    tester,
  ) async {
    final stored = LearningProfileSnapshot(
      ownerId: 'a',
      profile: LearningProfile(
        ownerId: 'a',
        revision: 1,
        draft: LearningProfileDraft(
          onboardingState: LearningOnboardingState.completed,
          goalText: 'Stored goal',
        ),
        updatedAtUtc: DateTime.utc(2026, 11, 1),
      ),
    );
    final repository = _Repository()..snapshot = stored;
    final profile = _useCases(repository);
    addTearDown(profile.dispose);
    addTearDown(repository.close);
    await tester.pumpWidget(
      MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
    );
    await tester.pumpAndSettle();
    final pending = Completer<LearningProfileSnapshot>();
    repository.readResult = pending.future;
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    final goal = find.byKey(const ValueKey('learning-profile-goal'));
    await tester.enterText(goal, 'Fresh draft typed after resume');
    pending.complete(stored);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(goal).controller!.text,
      'Fresh draft typed after resume',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-profile-save')),
    );
    await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
    await tester.pumpAndSettle();
    expect(
      repository.changes.single.draft.goalText,
      'Fresh draft typed after resume',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid target date stays in the editor and writes nothing', (
    tester,
  ) async {
    final repository = _Repository();
    final profile = _useCases(repository);
    addTearDown(profile.dispose);
    addTearDown(repository.close);
    await tester.pumpWidget(
      MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('learning-profile-date')),
      '2026-02-29',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-profile-save')),
    );
    await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
    await tester.pumpAndSettle();
    expect(find.text('ใส่วันที่ที่มีจริงในรูปแบบ YYYY-MM-DD'), findsOneWidget);
    expect(repository.changes, isEmpty);
  });

  testWidgets('retry reuses the original immutable save command', (
    tester,
  ) async {
    final repository = _Repository()..failNext = true;
    final profile = _useCases(repository);
    addTearDown(profile.dispose);
    addTearDown(repository.close);
    await tester.pumpWidget(
      MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('learning-profile-goal')),
      'First intent',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-profile-save')),
    );
    await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
    await tester.pumpAndSettle();
    final original = repository.changes.single;
    expect(find.text('ลองบันทึกเดิมอีกครั้ง'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-profile-save')),
    );
    expect(
      find.byKey(const ValueKey('learning-profile-save')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
    await tester.pumpAndSettle();
    expect(repository.changes.length, 2);
    expect(identical(repository.changes.last, original), isTrue);
    expect(find.text('บันทึกแผนการเรียนแล้ว'), findsOneWidget);
  });

  testWidgets('failed reload retains the original uncertain save for retry', (
    tester,
  ) async {
    final repository = _Repository()..failNext = true;
    final profile = _useCases(repository);
    addTearDown(profile.dispose);
    addTearDown(repository.close);
    await tester.pumpWidget(
      MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('learning-profile-goal')),
      'Original uncertain intent',
    );
    final save = find.byKey(const ValueKey('learning-profile-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final original = repository.changes.single;
    final pending = Completer<LearningProfileSnapshot>();
    repository.readResult = pending.future;
    await tester.ensureVisible(find.text('โหลดแผนล่าสุด'));
    await tester.tap(find.text('โหลดแผนล่าสุด'));
    await tester.pump();
    pending.completeError(StateError('synthetic read failure'));
    await tester.pumpAndSettle();
    expect(find.text('ลองบันทึกเดิมอีกครั้ง'), findsOneWidget);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.changes.length, 2);
    expect(identical(repository.changes.last, original), isTrue);
    expect(find.text('บันทึกแผนการเรียนแล้ว'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('optional onboarding can be skipped without filling a form', (
    tester,
  ) async {
    final repository = _Repository();
    final profile = _useCases(repository);
    addTearDown(profile.dispose);
    addTearDown(repository.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LearningProfileEditorScreen(
                    profile: profile,
                    onboarding: true,
                  ),
                ),
              ),
              child: const Text('Open optional setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open optional setup'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('learning-profile-skip')),
    );
    await tester.tap(find.byKey(const ValueKey('learning-profile-skip')));
    await tester.pumpAndSettle();
    expect(
      repository.changes.single.draft.onboardingState,
      LearningOnboardingState.skipped,
    );
    expect(repository.changes.single.draft.goalText, isNull);
    expect(find.text('Open optional setup'), findsOneWidget);
  });

  testWidgets(
    'owner invalidation hides the previous learner draft during a pending save',
    (tester) async {
      final repository = _Repository();
      final profile = _useCases(repository);
      addTearDown(profile.dispose);
      addTearDown(repository.close);
      await tester.pumpWidget(
        MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('learning-profile-goal')),
        'Private draft A',
      );
      final pending = Completer<LearningProfile>();
      repository.saveResult = pending.future;
      await tester.ensureVisible(
        find.byKey(const ValueKey('learning-profile-save')),
      );
      await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
      await tester.pump();
      repository.owner = 'b';
      repository.owners.add(null);
      repository.owners.add('b');
      await tester.pumpAndSettle();
      expect(find.text('Private draft A'), findsNothing);
      pending.complete(_saved(repository.changes.single));
      await tester.pumpAndSettle();
      expect(find.text('บันทึกแผนการเรียนแล้ว'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'editor action remains reachable at320px200percent with keyboard ${brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _Repository();
        final profile = _useCases(repository);
        addTearDown(profile.dispose);
        addTearDown(repository.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 260),
              ),
              child: child!,
            ),
            home: LearningProfileEditorScreen(profile: profile),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('learning-profile-goal')),
          'แผนการเรียน',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('learning-profile-save')),
        );
        await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
        await tester.pumpAndSettle();
        expect(repository.changes.single.draft.goalText, 'แผนการเรียน');
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

LearningProfileUseCases _useCases(_Repository repository) =>
    LearningProfileUseCases(
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 11, 1),
    );

LearningProfile _saved(LearningProfileChange change) => LearningProfile(
  ownerId: change.expectedOwnerId,
  revision: change.expectedRevision + 1,
  draft: change.draft,
  updatedAtUtc: change.updatedAtUtc,
);

final class _Repository implements LearningProfileRepository {
  String? owner = 'a';
  final owners = StreamController<String?>.broadcast(sync: true);
  final changes = <LearningProfileChange>[];
  Future<LearningProfile>? saveResult;
  Future<LearningProfileSnapshot>? readResult;
  LearningProfileSnapshot? snapshot;
  bool failNext = false;
  @override
  Future<LearningProfileSnapshot> read({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    if (readResult case final result?) return result;
    return snapshot ?? LearningProfileSnapshot(ownerId: expectedOwnerId);
  }

  @override
  Future<LearningProfile> save(LearningProfileChange change) async {
    changes.add(change);
    if (failNext) {
      failNext = false;
      throw const LearningProfileException(
        LearningProfileFailureCode.unavailable,
      );
    }
    return saveResult ?? _saved(change);
  }

  @override
  Stream<String?> watchActiveOwnerId() => Stream<String?>.multi((controller) {
    controller.add(owner);
    final subscription = owners.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);
  @override
  Stream<LearningProfileSnapshot> watch({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => Stream.value(LearningProfileSnapshot(ownerId: expectedOwnerId));
  Future<void> close() => owners.close();
}
