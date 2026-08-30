import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';

void main() {
  group('f35 learner preference authority', () {
    test(
      'exposes typed editable defaults without a learning-style label',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final useCases = _useCases(database);

        final preferences = await useCases.read();

        expect(preferences.preferenceVersion, 1);
        expect(preferences.goal, LearnerPreferenceGoal.balancedGrowth);
        expect(preferences.availableMinutesPerDay, 20);
        expect(
          preferences.activityPreference,
          LearnerActivityPreference.mixedPractice,
        );
        expect(preferences.ownerId, 'local:preferences-owner');
        expect(
          preferences.toJson().keys,
          unorderedEquals({
            'preferenceVersion',
            'goal',
            'availableMinutesPerDay',
            'activityPreference',
            'updatedAtUtcMs',
          }),
        );
        expect(preferences.toJson().keys, isNot(contains('learningStyle')));
        expect(preferences.toJson().keys, isNot(contains('personality')));
        expect(await _count(database, 'learner_preferences'), 0);
      },
    );

    test(
      'validates bounded editable values and rejects unknown storage',
      () async {
        expect(
          () => LearnerPreferences(
            ownerId: 'local:owner',
            preferenceVersion: 1,
            goal: LearnerPreferenceGoal.examPreparation,
            availableMinutesPerDay: 0,
            activityPreference: LearnerActivityPreference.quiz,
            updatedAtUtc: DateTime.utc(2026, 8, 30),
          ),
          throwsArgumentError,
        );
        expect(
          () => LearnerPreferences(
            ownerId: 'local:owner',
            preferenceVersion: 1,
            goal: LearnerPreferenceGoal.examPreparation,
            availableMinutesPerDay: 241,
            activityPreference: LearnerActivityPreference.quiz,
            updatedAtUtc: DateTime.utc(2026, 8, 30),
          ),
          throwsArgumentError,
        );
        expect(
          () => LearnerPreferenceGoalCodec.parse('visual-learner'),
          throwsA(isA<LearnerPreferencesValidationFailure>()),
        );
        expect(
          () => LearnerActivityPreferenceCodec.parse('personality-driven'),
          throwsA(isA<LearnerPreferencesValidationFailure>()),
        );

        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final owner = await _owners(database).getOrCreateActiveOwner();
        await database.customStatement(
          'INSERT INTO learner_preferences '
          '(owner_id, preference_version, goal, available_minutes_per_day, '
          'activity_preference, updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
          [owner.id, 1, 'visual-learner', 20, 'quiz', 1788048000000],
        );

        await expectLater(
          DriftLearnerPreferencesRepository(database).read(owner.id),
          throwsA(isA<LearnerPreferencesValidationFailure>()),
        );
      },
    );

    test(
      'save restart identical replay and explicit override are local first',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'lexiquest-f35-preferences-',
        );
        final file = File('${directory.path}/preferences.sqlite');
        AppDatabase? first;
        AppDatabase? second;
        try {
          first = AppDatabase(NativeDatabase(file));
          final initialUseCases = _useCases(first);
          final saved = await initialUseCases.save(
            goal: LearnerPreferenceGoal.examPreparation,
            availableMinutesPerDay: 45,
            activityPreference: LearnerActivityPreference.quiz,
          );
          expect(saved.availableMinutesPerDay, 45);
          expect(await _count(first, 'learner_preferences'), 1);
          expect(await _outboxCount(first), 1);
          await first.close();
          first = null;

          second = AppDatabase(NativeDatabase(file));
          final reopened = _useCases(second);
          expect(await reopened.read(), saved);
          expect(
            await reopened.save(
              goal: LearnerPreferenceGoal.examPreparation,
              availableMinutesPerDay: 45,
              activityPreference: LearnerActivityPreference.quiz,
            ),
            saved,
          );
          expect(await _outboxCount(second), 1);

          final overridden = await reopened.save(
            goal: LearnerPreferenceGoal.conversationConfidence,
            availableMinutesPerDay: 30,
            activityPreference: LearnerActivityPreference.speaking,
          );
          expect(overridden.goal, LearnerPreferenceGoal.conversationConfidence);
          expect(overridden.availableMinutesPerDay, 30);
          expect(await _outboxCount(second), 2);
          final operations = await second
              .customSelect(
                "SELECT operation_id, entity_type, base_revision, state "
                "FROM outbox_operations WHERE entity_type = 'learnerPreference' "
                'ORDER BY base_revision, operation_id',
              )
              .get();
          expect(
            operations.map((row) => row.read<String>('operation_id')).toSet(),
            hasLength(2),
          );
          expect(operations.map((row) => row.read<int>('base_revision')), [
            0,
            0,
          ]);
          expect(
            operations.map((row) => row.read<String>('state')).toList(),
            ['superseded', 'pending'],
            reason:
                'a newer offline singleton edit replaces rather than chains '
                'an unacknowledged cloud revision',
          );
          final row = await second
              .customSelect(
                'SELECT local_revision, cloud_revision FROM learner_preferences '
                "WHERE owner_id = 'local:preferences-owner'",
              )
              .getSingle();
          expect(row.read<int>('local_revision'), 1);
          expect(row.read<int>('cloud_revision'), 0);
        } finally {
          await first?.close();
          await second?.close();
          await directory.delete(recursive: true);
        }
      },
    );

    test(
      'committed semantic mutation notifies sync once and replay stays silent',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        var notifications = 0;
        final useCases = LearnerPreferencesUseCases(
          repository: DriftLearnerPreferencesRepository(
            database,
            onLocalMutation: () async => notifications += 1,
          ),
          owners: _owners(database),
          nowUtc: () => DateTime.utc(2026, 8, 30, 12),
        );

        await useCases.save(
          goal: LearnerPreferenceGoal.examPreparation,
          availableMinutesPerDay: 45,
          activityPreference: LearnerActivityPreference.quiz,
        );
        expect(notifications, 1);
        expect(await _outboxCount(database), 1);

        await useCases.save(
          goal: LearnerPreferenceGoal.examPreparation,
          availableMinutesPerDay: 45,
          activityPreference: LearnerActivityPreference.quiz,
        );
        expect(notifications, 1, reason: 'semantic replay is not a mutation');
        expect(await _outboxCount(database), 1);

        await expectLater(
          useCases.save(
            goal: LearnerPreferenceGoal.conversationConfidence,
            availableMinutesPerDay: 30,
            activityPreference: LearnerActivityPreference.speaking,
            mutationAllowed: () => false,
          ),
          throwsA(isA<LearnerPreferencesMutationUnavailable>()),
        );
        expect(notifications, 1, reason: 'failed transaction cannot notify');
        expect(await _outboxCount(database), 1);
      },
    );

    test(
      'protocol clamp changes only the effective view and never assignment',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final useCases = _useCases(database);
        await useCases.save(
          goal: LearnerPreferenceGoal.conversationConfidence,
          availableMinutesPerDay: 60,
          activityPreference: LearnerActivityPreference.speaking,
        );
        final owner = await _owners(database).getOrCreateActiveOwner();
        await database.customStatement(
          'INSERT INTO experiment_assignments '
          '(id, owner_id, experiment_id, experiment_version, cohort, '
          'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            'assignment:f35',
            owner.id,
            'experiment:f35',
            1,
            'control',
            '1.0.0',
            1788048000000,
          ],
        );
        final assignmentBefore =
            (await database
                    .customSelect(
                      "SELECT * FROM experiment_assignments WHERE id = 'assignment:f35'",
                    )
                    .getSingle())
                .data;

        final effective = await useCases.readEffective(
          protocolClamp: const LearnerPreferenceProtocolClamp(
            maximumAvailableMinutesPerDay: 20,
            activityPreference: LearnerActivityPreference.reading,
          ),
        );

        expect(effective.wasClamped, isTrue);
        expect(effective.availableMinutesPerDay, 20);
        expect(effective.activityPreference, LearnerActivityPreference.reading);
        final saved = await useCases.read();
        expect(saved.availableMinutesPerDay, 60);
        expect(saved.activityPreference, LearnerActivityPreference.speaking);
        final assignmentAfter =
            (await database
                    .customSelect(
                      "SELECT * FROM experiment_assignments WHERE id = 'assignment:f35'",
                    )
                    .getSingle())
                .data;
        expect(assignmentAfter, assignmentBefore);
      },
    );

    test(
      'feature rollback blocks mutation but preserves the durable preference',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final useCases = _useCases(database);
        final saved = await useCases.save(
          goal: LearnerPreferenceGoal.vocabularyGrowth,
          availableMinutesPerDay: 25,
          activityPreference: LearnerActivityPreference.vocabulary,
        );

        await expectLater(
          useCases.save(
            goal: LearnerPreferenceGoal.examPreparation,
            availableMinutesPerDay: 40,
            activityPreference: LearnerActivityPreference.quiz,
            mutationAllowed: () => false,
          ),
          throwsA(isA<LearnerPreferencesMutationUnavailable>()),
        );
        expect(await useCases.read(), saved);
        expect(await _count(database, 'learner_preferences'), 1);
        expect(await _outboxCount(database), 1);
      },
    );
  });
}

LearnerPreferencesUseCases _useCases(AppDatabase database) =>
    LearnerPreferencesUseCases(
      repository: DriftLearnerPreferencesRepository(database),
      owners: _owners(database),
      nowUtc: () => DateTime.utc(2026, 8, 30, 12),
    );

DriftLocalOwnerRepository _owners(AppDatabase database) =>
    DriftLocalOwnerRepository(
      database,
      generateId: () => 'preferences-owner',
      nowUtc: () => DateTime.utc(2026, 8, 30),
    );

Future<int> _count(AppDatabase database, String tableName) => database
    .customSelect('SELECT COUNT(*) AS count FROM $tableName')
    .map((row) => row.read<int>('count'))
    .getSingle();

Future<int> _outboxCount(AppDatabase database) => database
    .customSelect(
      "SELECT COUNT(*) AS count FROM outbox_operations "
      "WHERE entity_type = 'learnerPreference'",
    )
    .map((row) => row.read<int>('count'))
    .getSingle();
