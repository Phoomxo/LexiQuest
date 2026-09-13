import 'package:sqlite3/common.dart';

enum AppDatabaseOpenError {
  corruptOrUnreadable,
  incompatibleSchema,
  legacyImportRequired,
}

final class AppDatabaseOpenException implements Exception {
  const AppDatabaseOpenException(this.code);
  final AppDatabaseOpenError code;
  @override
  String toString() => 'AppDatabaseOpenException(${code.name})';
}

/// Read-only SQL checks, run before any migration or connection-setting write.
void validateAppDatabase(CommonDatabase database, int supportedVersion) {
  try {
    final integrity = database.select('PRAGMA quick_check');
    if (integrity.length != 1 || integrity.single.values.single != 'ok') {
      throw const AppDatabaseOpenException(
        AppDatabaseOpenError.corruptOrUnreadable,
      );
    }
    final version =
        database.select('PRAGMA user_version').single.values.single as int;
    final unversionedData =
        version == 0 &&
        database
            .select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' LIMIT 1",
            )
            .isNotEmpty;
    if (version < 0 || version > supportedVersion || unversionedData) {
      throw const AppDatabaseOpenException(
        AppDatabaseOpenError.incompatibleSchema,
      );
    }
  } on AppDatabaseOpenException {
    rethrow;
  } catch (_) {
    throw const AppDatabaseOpenException(
      AppDatabaseOpenError.corruptOrUnreadable,
    );
  }
}

void configureAppDatabase(CommonDatabase database, int supportedVersion) {
  validateAppDatabase(database, supportedVersion);
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA journal_mode = WAL');
  database.execute('PRAGMA busy_timeout = 5000');
}
