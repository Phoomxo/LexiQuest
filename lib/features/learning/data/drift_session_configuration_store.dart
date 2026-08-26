import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../domain/lesson_mode.dart';
import '../domain/session_configuration.dart';

/// Durable owner-scoped selection store. It persists only the signed stable
/// serialization and never reads or writes assignment/cohort/evidence rows.
final class DriftSessionConfigurationStore
    implements SessionConfigurationStore {
  const DriftSessionConfigurationStore(this._database);

  final AppDatabase _database;

  @override
  Future<SessionConfiguration?> read({
    required String ownerId,
    required LessonMode mode,
  }) async {
    final owner = _canonical(ownerId, 'ownerId');
    final row =
        await (_database.select(_database.sessionConfigurations)..where(
              (candidate) =>
                  candidate.ownerId.equals(owner) &
                  candidate.mode.equals(mode.name),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    final configuration = SessionConfiguration.fromStableSerialization(
      row.stableSerialization,
    );
    if (configuration.ownerId != owner ||
        configuration.mode != mode ||
        configuration.contentIdentity != row.contentIdentity) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    return configuration;
  }

  @override
  Future<void> save(
    SessionConfiguration configuration, {
    required DateTime updatedAtUtc,
  }) async {
    if (!updatedAtUtc.isUtc) {
      throw ArgumentError.value(updatedAtUtc, 'updatedAtUtc', 'must be UTC');
    }
    final owner = _canonical(configuration.ownerId, 'ownerId');
    final decoded = SessionConfiguration.fromStableSerialization(
      configuration.stableSerialization,
    );
    if (decoded != configuration) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.tampered,
      );
    }
    await _database
        .into(_database.sessionConfigurations)
        .insertOnConflictUpdate(
          SessionConfigurationsCompanion.insert(
            ownerId: owner,
            mode: configuration.mode.name,
            contentIdentity: configuration.contentIdentity,
            stableSerialization: configuration.stableSerialization,
            updatedAtUtcMs: updatedAtUtc.millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Future<void> clear({
    required String ownerId,
    required LessonMode mode,
  }) async {
    await (_database.delete(_database.sessionConfigurations)..where(
          (candidate) =>
              candidate.ownerId.equals(_canonical(ownerId, 'ownerId')) &
              candidate.mode.equals(mode.name),
        ))
        .go();
  }
}

String _canonical(String value, String name) {
  if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
    throw ArgumentError.value(value, name, 'must be canonical');
  }
  return value;
}
