import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'app_database_open_policy.dart';

/// Same documents/lexiquest.sqlite path used by drift_flutter's default.
Future<String?> resolveAppDatabasePath(int supportedVersion) async {
  try {
    return await _resolveCheckedPath(supportedVersion);
  } on AppDatabaseOpenException {
    rethrow;
  } catch (_) {
    throw const AppDatabaseOpenException(AppDatabaseOpenError.corruptOrUnreadable);
  }
}

Future<String> _resolveCheckedPath(int supportedVersion) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(
    '${directory.path}${Platform.pathSeparator}lexiquest.sqlite',
  );
  final legacy = File(
    '${directory.path}${Platform.pathSeparator}learning.sqlite',
  );
  if (!file.existsSync() && legacy.existsSync() && legacy.lengthSync() > 0) {
    throw const AppDatabaseOpenException(
      AppDatabaseOpenError.legacyImportRequired,
    );
  }
  if (file.existsSync() && file.lengthSync() > 0) {
    Database? probe;
    try {
      probe = sqlite3.open(file.path, mode: OpenMode.readOnly);
      validateAppDatabase(probe, supportedVersion);
    } on AppDatabaseOpenException {
      rethrow;
    } catch (_) {
      throw const AppDatabaseOpenException(
        AppDatabaseOpenError.corruptOrUnreadable,
      );
    } finally {
      probe?.close();
    }
  }
  return file.path;
}
