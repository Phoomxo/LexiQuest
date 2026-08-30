import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as domain;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/display_preferences_controller.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';

void main() {
  group('f39 display preference authority', () {
    test(
      'persists theme and reduced motion across restart without cloud intent',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'lexiquest-f39-display-',
        );
        final file = File('${directory.path}/display.sqlite');
        AppDatabase? first;
        AppDatabase? second;
        try {
          first = AppDatabase(NativeDatabase(file));
          final firstUseCases = _useCases(first);
          await firstUseCases.save(
            goal: LearnerPreferenceGoal.examPreparation,
            availableMinutesPerDay: 45,
            activityPreference: LearnerActivityPreference.quiz,
          );
          await _seedAssignment(first);
          final learningBefore = await _learningFields(first);
          final assignmentBefore = await _assignment(first);
          final outboxBefore = await _outboxCount(first);
          final controller = DisplayPreferencesController(firstUseCases);
          addTearDown(controller.dispose);
          await controller.initialize();

          await controller.selectThemeMode(ThemeMode.dark);
          await controller.setReducedMotion(true);

          expect(controller.themeMode, ThemeMode.dark);
          expect(controller.reducedMotionEnabled, isTrue);
          expect(await _learningFields(first), learningBefore);
          expect(await _assignment(first), assignmentBefore);
          expect(await _outboxCount(first), outboxBefore);
          await first.close();
          first = null;

          second = AppDatabase(NativeDatabase(file));
          final reopened = DisplayPreferencesController(_useCases(second));
          addTearDown(reopened.dispose);
          await reopened.initialize();

          expect(reopened.themeMode, ThemeMode.dark);
          expect(reopened.reducedMotionEnabled, isTrue);
          expect(await _outboxCount(second), outboxBefore);
        } finally {
          await first?.close();
          await second?.close();
          await directory.delete(recursive: true);
        }
      },
    );

    test(
      'corrupt display values fall back to system and platform motion',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final useCases = _useCases(database);
        await useCases.save(
          goal: LearnerPreferenceGoal.balancedGrowth,
          availableMinutesPerDay: 20,
          activityPreference: LearnerActivityPreference.mixedPractice,
        );
        await database.customUpdate(
          "UPDATE learner_preferences SET theme_mode = 'sepia', "
          "motion_mode = 'hyperactive'",
        );
        final controller = DisplayPreferencesController(useCases);
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(controller.themeMode, ThemeMode.system);
        expect(controller.reducedMotionEnabled, isFalse);
      },
    );

    test(
      'identical display replay is silent and does not rewrite learning',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final useCases = _useCases(database);
        final controller = DisplayPreferencesController(useCases);
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.selectThemeMode(ThemeMode.light);
        final first = await _displayFields(database);
        await controller.selectThemeMode(ThemeMode.light);
        final replay = await _displayFields(database);

        expect(replay, first);
        expect(await _outboxCount(database), 0);
      },
    );

    test('owner-transition refresh failure resets to safe defaults', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final controller = DisplayPreferencesController(_useCases(database));
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.selectThemeMode(ThemeMode.dark);
      await controller.setReducedMotion(true);
      await database.close();

      await controller.refreshAfterOwnerTransition();

      expect(controller.themeMode, ThemeMode.system);
      expect(controller.reducedMotionEnabled, isFalse);
    });

    test(
      'queued display edit cannot carry a prior owner field across transition',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        await _seedDisplayOwner(
          database,
          ownerId: 'display-owner-a',
          active: true,
          themeMode: 'light',
          motionMode: 'reduced',
        );
        await _seedDisplayOwner(
          database,
          ownerId: 'display-owner-b',
          active: false,
          themeMode: 'system',
          motionMode: 'system',
        );
        final owners = _ControllableOwners(
          domain.LocalOwner(
            id: 'display-owner-a',
            createdAtUtc: DateTime.utc(2026, 8, 30),
          ),
        );
        final controller = DisplayPreferencesController(
          LearnerPreferencesUseCases(
            repository: DriftLearnerPreferencesRepository(database),
            owners: owners,
            nowUtc: () => DateTime.utc(2026, 8, 30, 12),
          ),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        owners.blockNextResolution();

        final mutation = controller.selectThemeMode(ThemeMode.dark);
        await owners.resolutionBlocked;
        await database.transaction(() async {
          await database.customUpdate(
            'UPDATE local_owners SET is_active = 0 WHERE id = ?',
            variables: [const Variable<String>('display-owner-a')],
            updates: {database.localOwners},
          );
          await database.customUpdate(
            'UPDATE local_owners SET is_active = 1 WHERE id = ?',
            variables: [const Variable<String>('display-owner-b')],
            updates: {database.localOwners},
          );
        });
        owners.activeOwner = domain.LocalOwner(
          id: 'display-owner-b',
          createdAtUtc: DateTime.utc(2026, 8, 30),
        );
        final refresh = controller.refreshAfterOwnerTransition();
        owners.releaseResolution();

        await expectLater(
          mutation,
          throwsA(isA<LearnerPreferencesMutationUnavailable>()),
        );
        await refresh;
        final persisted = await database
            .customSelect(
              'SELECT theme_mode, motion_mode FROM learner_preferences '
              "WHERE owner_id = 'display-owner-b'",
            )
            .getSingle();
        expect(persisted.read<String>('theme_mode'), 'system');
        expect(persisted.read<String>('motion_mode'), 'system');
        expect(controller.themeMode, ThemeMode.system);
        expect(controller.reducedMotionEnabled, isFalse);
      },
    );
  });
}

final class _ControllableOwners implements LocalOwnerRepository {
  _ControllableOwners(this.activeOwner);

  domain.LocalOwner activeOwner;
  Completer<void>? _blocked;
  Completer<void>? _release;

  Future<void> get resolutionBlocked => _blocked!.future;

  void blockNextResolution() {
    _blocked = Completer<void>();
    _release = Completer<void>();
  }

  void releaseResolution() => _release!.complete();

  @override
  Future<domain.LocalOwner> getOrCreateActiveOwner() async {
    final release = _release;
    if (release != null) {
      _blocked!.complete();
      await release.future;
      _release = null;
      _blocked = null;
    }
    return activeOwner;
  }

  @override
  Future<domain.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => activeOwner;
}

Future<void> _seedDisplayOwner(
  AppDatabase database, {
  required String ownerId,
  required bool active,
  required String themeMode,
  required String motionMode,
}) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, account_state, created_at_utc_ms, is_active) '
    'VALUES (?, ?, ?, ?)',
    variables: [
      Variable<String>(ownerId),
      const Variable<String>('localGuest'),
      const Variable<int>(1),
      Variable<int>(active ? 1 : 0),
    ],
  );
  await database.customInsert(
    'INSERT INTO learner_preferences '
    '(owner_id, preference_version, goal, available_minutes_per_day, '
    'activity_preference, updated_at_utc_ms, theme_mode, motion_mode, '
    'display_updated_at_utc_ms, local_revision, cloud_revision, is_deleted) '
    'VALUES (?, 1, ?, 20, ?, 0, ?, ?, 1, 0, 0, 0)',
    variables: [
      Variable<String>(ownerId),
      Variable<String>(LearnerPreferenceGoal.balancedGrowth.name),
      Variable<String>(LearnerActivityPreference.mixedPractice.name),
      Variable<String>(themeMode),
      Variable<String>(motionMode),
    ],
  );
}

LearnerPreferencesUseCases _useCases(AppDatabase database) =>
    LearnerPreferencesUseCases(
      repository: DriftLearnerPreferencesRepository(database),
      owners: DriftLocalOwnerRepository(
        database,
        generateId: () => 'display-owner',
        nowUtc: () => DateTime.utc(2026, 8, 30),
      ),
      nowUtc: () => DateTime.utc(2026, 8, 30, 12),
    );

Future<void> _seedAssignment(AppDatabase database) => database.customInsert(
  'INSERT INTO experiment_assignments '
  '(id, owner_id, experiment_id, experiment_version, cohort, '
  'protocol_version, assigned_at_utc_ms) VALUES '
  "('assignment:f39', 'local:display-owner', 'experiment:f39', 1, "
  "'control', '1.0.0', 1)",
);

Future<Map<String, Object?>> _learningFields(AppDatabase database) => database
    .customSelect(
      'SELECT preference_version, goal, available_minutes_per_day, '
      'activity_preference, updated_at_utc_ms, local_revision, cloud_revision '
      'FROM learner_preferences',
    )
    .map((row) => row.data)
    .getSingle();

Future<Map<String, Object?>> _displayFields(AppDatabase database) => database
    .customSelect(
      'SELECT theme_mode, motion_mode, display_updated_at_utc_ms '
      'FROM learner_preferences',
    )
    .map((row) => row.data)
    .getSingle();

Future<Map<String, Object?>> _assignment(AppDatabase database) => database
    .customSelect(
      "SELECT * FROM experiment_assignments WHERE id = 'assignment:f39'",
    )
    .map((row) => row.data)
    .getSingle();

Future<int> _outboxCount(AppDatabase database) => database
    .customSelect(
      "SELECT COUNT(*) AS count FROM outbox_operations "
      "WHERE entity_type = 'learnerPreference'",
    )
    .map((row) => row.read<int>('count'))
    .getSingle();
