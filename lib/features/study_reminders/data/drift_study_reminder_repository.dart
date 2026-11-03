import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../data/local/app_database.dart' as db;
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../motivation/data/drift_motivation_scope.dart';
import '../../motivation/domain/motivation_snapshot.dart';
import '../domain/study_reminder.dart';

final class DriftStudyReminderRepository {
  DriftStudyReminderRepository(this.database, this.ownerWrites) {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError(
        'Reminder preferences require the canonical owner database',
      );
    }
  }
  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;

  Future<StudyReminderSetting> readForOwner({
    required String ownerId,
    required bool Function() stillCurrent,
  }) => _guard(
    ownerId,
    stillCurrent,
    (_) async => _setting(ownerId, await _row(ownerId)),
  );

  Future<void> requireCommittedBoundary() async {
    if (await ownerWrites.hasAmbientTransaction()) {
      throw const StudyReminderException(StudyReminderFailureCode.unavailable);
    }
  }

  Future<StudyReminderSetting> writeForOwner({
    required String ownerId,
    required int baseRevision,
    required StudyReminderChoice choice,
    required DateTime updatedAtUtc,
    required bool Function() stillCurrent,
  }) async {
    choice.validate();
    if (baseRevision < 0 ||
        baseRevision >= 9007199254740991 ||
        !updatedAtUtc.isUtc ||
        updatedAtUtc.millisecondsSinceEpoch < 0) {
      throw const StudyReminderException(
        StudyReminderFailureCode.invalidChoice,
      );
    }
    await requireCommittedBoundary();
    return _guard(
      ownerId,
      stillCurrent,
      (current) => ownerWrites.writeForActiveOwner(
        expectedOwnerId: ownerId,
        write: () async {
          final prior = await _row(ownerId);
          final revision = prior?.revision ?? 0;
          final stamp = updatedAtUtc.millisecondsSinceEpoch;
          if (revision == baseRevision + 1 &&
              prior != null &&
              prior.enabled == choice.enabled &&
              prior.minuteOfDay == choice.minuteOfDay &&
              prior.timezoneId == choice.timezoneId &&
              prior.updatedAtUtcMs == stamp) {
            return _setting(ownerId, prior);
          }
          if (revision != baseRevision) {
            throw const StudyReminderException(
              StudyReminderFailureCode.staleRevision,
            );
          }
          if (!current()) {
            throw const StudyReminderException(
              StudyReminderFailureCode.ownerChanged,
            );
          }
          await database
              .into(database.studyReminderPreferences)
              .insertOnConflictUpdate(
                db.StudyReminderPreferencesCompanion.insert(
                  ownerId: ownerId,
                  enabled: Value(choice.enabled),
                  minuteOfDay: choice.minuteOfDay,
                  timezoneId: choice.timezoneId,
                  revision: baseRevision + 1,
                  updatedAtUtcMs: stamp,
                ),
              );
          await requireMotivationOwner(database, ownerWrites, ownerId, current);
          return _setting(ownerId, await _row(ownerId));
        },
      ),
    );
  }

  Future<String?> nativeDatabasePath({
    required String ownerId,
    required bool Function() stillCurrent,
  }) => _guard(ownerId, stillCurrent, (_) async {
    debugPrint('LexiQuestReminder repository nativeDatabasePath query');
    final rows = await database.customSelect('PRAGMA database_list').get();
    final main = rows
        .where((row) => row.read<String>('name') == 'main')
        .singleOrNull;
    final path = main?.read<String>('file');
    return path == null || path.isEmpty ? null : path;
  });

  Future<db.StudyReminderPreference?> _row(String ownerId) => (database.select(
    database.studyReminderPreferences,
  )..where((row) => row.ownerId.equals(ownerId))).getSingleOrNull();

  StudyReminderSetting _setting(String owner, db.StudyReminderPreference? row) {
    if (row == null) return StudyReminderSetting.absent(owner);
    final choice = StudyReminderChoice(
      enabled: row.enabled,
      minuteOfDay: row.minuteOfDay,
      timezoneId: row.timezoneId,
    );
    choice.validate();
    if (row.revision < 1 || row.updatedAtUtcMs < 0) {
      throw const StudyReminderException(StudyReminderFailureCode.unavailable);
    }
    return StudyReminderSetting(
      ownerId: owner,
      enabled: row.enabled,
      minuteOfDay: row.minuteOfDay,
      timezoneId: row.timezoneId,
      revision: row.revision,
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.updatedAtUtcMs,
        isUtc: true,
      ),
    );
  }

  Future<T> _guard<T>(
    String owner,
    bool Function() current,
    Future<T> Function(bool Function()) operation,
  ) async {
    try {
      return await withMotivationOwner(
        database,
        ownerWrites,
        owner,
        current,
        operation,
      );
    } on StudyReminderException catch (error) {
      debugPrint('LexiQuestReminder repository rejected ${error.code.name}');
      rethrow;
    } on MotivationException catch (error) {
      debugPrint(
        'LexiQuestReminder repository MotivationException ${error.code.name}',
      );
      throw StudyReminderException(
        error.code == MotivationFailureCode.ownerChanged
            ? StudyReminderFailureCode.ownerChanged
            : StudyReminderFailureCode.unavailable,
      );
    } on Object catch (error) {
      debugPrint('LexiQuestReminder repository failed ${error.runtimeType}');
      throw const StudyReminderException(StudyReminderFailureCode.unavailable);
    }
  }
}
