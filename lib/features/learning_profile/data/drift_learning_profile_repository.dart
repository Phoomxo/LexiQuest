import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' hide LearningProfile;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../progress/data/drift_review_center_queries.dart';
import '../../progress/domain/review_center_models.dart';
import '../domain/learning_profile.dart';
import '../domain/learning_profile_repository.dart';

final class DriftLearningProfileRepository
    implements LearningProfileRepository {
  DriftLearningProfileRepository({
    required this.database,
    required this.ownerWrites,
  }) {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError(
        'Learning profiles require the same owner-write database',
      );
    }
  }

  final AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;

  @override
  Future<LearningProfileSnapshot> read({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => _guard(expectedOwnerId, stillCurrent, (current) async {
    await _requireOwner(expectedOwnerId, current);
    final result = await _read(expectedOwnerId);
    await _requireOwner(expectedOwnerId, current);
    return result;
  });

  @override
  Stream<LearningProfileSnapshot> watch({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => database
      .customSelect(
        'SELECT revision FROM learning_profiles WHERE owner_id=?',
        variables: [Variable<String>(expectedOwnerId)],
        readsFrom: {
          database.localOwners,
          database.runtimeFlags,
          database.learningProfiles,
        },
      )
      .watch()
      .asyncMap(
        (_) =>
            read(expectedOwnerId: expectedOwnerId, stillCurrent: stillCurrent),
      );

  @override
  Future<LearningProfile> save(
    LearningProfileChange change,
  ) => _guard(change.expectedOwnerId, change.stillCurrent, (current) async {
    await _requireOwner(change.expectedOwnerId, current);
    if (await ownerWrites.hasAmbientTransaction()) _unavailable();
    return ownerWrites.writeForActiveOwner(
      expectedOwnerId: change.expectedOwnerId,
      write: () async {
        await _requireOwner(change.expectedOwnerId, current);
        final stored = await _read(change.expectedOwnerId);
        final previous = stored.profile;
        if (previous != null &&
            previous.revision == change.expectedRevision + 1 &&
            previous.draft.sameFacts(change.draft) &&
            previous.updatedAtUtc == change.updatedAtUtc) {
          return previous;
        }
        if (stored.revision != change.expectedRevision) {
          throw const LearningProfileException(
            LearningProfileFailureCode.conflict,
          );
        }
        final next = LearningProfile(
          ownerId: change.expectedOwnerId,
          revision: change.expectedRevision + 1,
          draft: change.draft,
          updatedAtUtc: change.updatedAtUtc,
        );
        final values = <Variable>[
          Variable<String>(next.draft.onboardingState.name),
          Variable<String>(next.draft.goalText),
          Variable<String>(next.draft.targetDate?.toString()),
          Variable<int>(next.draft.dailyMinutes),
          Variable<String>(next.draft.interestCodesJson),
          Variable<int>(next.updatedAtUtc.millisecondsSinceEpoch),
          Variable<int>(next.revision),
          Variable<String>(next.ownerId),
        ];
        final table = database.learningProfiles;
        if (previous == null) {
          await database.customInsert(
            'INSERT INTO learning_profiles '
            '(onboarding_state,goal_text,target_date,daily_minutes,interest_codes_json,updated_at_utc_ms,revision,owner_id) '
            'VALUES (?,?,?,?,?,?,?,?)',
            variables: values,
            updates: {table},
          );
        } else {
          final count = await database.customUpdate(
            'UPDATE learning_profiles SET onboarding_state=?,goal_text=?,target_date=?,daily_minutes=?,'
            'interest_codes_json=?,updated_at_utc_ms=?,revision=? WHERE owner_id=? AND revision=?',
            variables: [...values, Variable<int>(change.expectedRevision)],
            updates: {table},
          );
          if (count != 1) {
            throw const LearningProfileException(
              LearningProfileFailureCode.conflict,
            );
          }
        }
        await _requireOwner(change.expectedOwnerId, current);
        final acknowledged = (await _read(change.expectedOwnerId)).profile;
        if (acknowledged == null ||
            acknowledged.revision != next.revision ||
            acknowledged.updatedAtUtc != next.updatedAtUtc ||
            !acknowledged.draft.sameFacts(next.draft)) {
          _unavailable();
        }
        await _requireOwner(change.expectedOwnerId, current);
        return acknowledged;
      },
    );
  });

  @override
  Stream<String?> watchActiveOwnerId() => Stream<String?>.multi((events) {
    final changes = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen((_) => events.add(null), onError: events.addError);
    final rows =
        (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .watch()
            .listen(
              (owners) =>
                  events.add(owners.length == 1 ? owners.single.id : null),
              onError: events.addError,
              onDone: events.close,
            );
    events.onCancel = () async {
      await Future.wait([changes.cancel(), rows.cancel()]);
    };
  }, isBroadcast: true).distinct();

  Future<LearningProfileSnapshot> _read(String ownerId) async {
    final row = await database
        .customSelect(
          'SELECT owner_id,revision,onboarding_state,goal_text,target_date,daily_minutes,'
          'interest_codes_json,updated_at_utc_ms FROM learning_profiles WHERE owner_id=?',
          variables: [Variable<String>(ownerId)],
        )
        .getSingleOrNull();
    if (row == null) return LearningProfileSnapshot(ownerId: ownerId);
    final revision = row.read<int>('revision');
    final updated = row.read<int>('updated_at_utc_ms');
    final interestJson = row.read<String>('interest_codes_json');
    final decoded = jsonDecode(interestJson);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['schemaVersion'] != 1 ||
        decoded['codes'] is! List ||
        (decoded['codes'] as List).any((value) => value is! String) ||
        revision < 1 ||
        revision > learningProfileMaxRevision ||
        updated < 0 ||
        updated > 8640000000000000) {
      _unavailable();
    }
    final state = LearningOnboardingState.values.where(
      (state) => state.name == row.read<String>('onboarding_state'),
    );
    if (state.length != 1) _unavailable();
    final target = row.readNullable<String>('target_date');
    final draft = LearningProfileDraft(
      onboardingState: state.single,
      goalText: row.readNullable<String>('goal_text'),
      targetDate: target == null ? null : LearningCivilDate.parse(target),
      dailyMinutes: row.readNullable<int>('daily_minutes'),
      interestCodes: List<String>.from(decoded['codes'] as List),
    );
    if (draft.interestCodesJson != interestJson ||
        draft.goalText != row.readNullable<String>('goal_text')) {
      _unavailable();
    }
    return LearningProfileSnapshot(
      ownerId: ownerId,
      profile: LearningProfile(
        ownerId: ownerId,
        revision: revision,
        draft: draft,
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(updated, isUtc: true),
      ),
    );
  }

  Future<T> _guard<T>(
    String owner,
    bool Function() stillCurrent,
    Future<T> Function(bool Function() current) action,
  ) async {
    var valid = true;
    final changes = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen(
          (_) => valid = false,
          onError: (Object _) => valid = false,
          onDone: () => valid = false,
        );
    bool current() => valid && stillCurrent();
    try {
      final result = await action(current);
      if (!current()) _ownerChanged();
      return result;
    } on LearningProfileException {
      rethrow;
    } on ReviewCenterReadException {
      _ownerChanged();
    } on AccountDeletionException {
      _unavailable();
    } on Object {
      _unavailable();
    } finally {
      await changes.cancel();
    }
  }

  Future<void> _requireOwner(String owner, bool Function() current) async {
    requireLearningProfileOwner(owner);
    await requireReviewReadOwner(
      database,
      expectedOwnerId: owner,
      stillCurrent: current,
    );
    final fence = await ownerWrites.inspect();
    if (fence != null &&
        (fence.casToken == null ||
            fence.casToken!.matchesOwner(owner) ||
            (fence.cloudReceipt != null &&
                owner ==
                    accountDeletionReplacementGuestOwnerId(
                      fence.cloudReceipt!,
                    )))) {
      _unavailable();
    }
    if (!current()) _ownerChanged();
  }

  Never _ownerChanged() => throw const LearningProfileException(
    LearningProfileFailureCode.ownerChanged,
  );
  Never _unavailable() => throw const LearningProfileException(
    LearningProfileFailureCode.unavailable,
  );
}
