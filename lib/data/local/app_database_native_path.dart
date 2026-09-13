import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'app_database_open_policy.dart';
import 'legacy_learning_import.dart';

/// Same documents/lexiquest.sqlite path used by drift_flutter's default.
Future<String?> resolveAppDatabasePath(int supportedVersion) async {
  try {
    return await _resolveCheckedPath(supportedVersion);
  } on AppDatabaseOpenException {
    rethrow;
  } catch (_) {
    throw const AppDatabaseOpenException(
      AppDatabaseOpenError.corruptOrUnreadable,
    );
  }
}

Future<String> _resolveCheckedPath(int supportedVersion) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(
    '${directory.path}${Platform.pathSeparator}lexiquest.sqlite',
  );
  if (!file.existsSync() || file.lengthSync() == 0) {
    final support = await getApplicationSupportDirectory();
    final paths = <String>{
      '${directory.path}${Platform.pathSeparator}learning.sqlite',
      '${support.path}${Platform.pathSeparator}learning.sqlite',
    };
    final sources = paths
        .map(File.new)
        .where(
          (candidate) => candidate.existsSync() && candidate.lengthSync() > 0,
        )
        .toList();
    if (sources.isNotEmpty) {
      if (file.existsSync()) {
        // Preserve an interrupted/unknown destination instead of silently
        // creating a fresh owner and hiding the supported legacy history.
        throw const AppDatabaseOpenException(
          AppDatabaseOpenError.legacyImportRequired,
        );
      }
      await importLegacyLearningFiles(sources, file);
    }
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
