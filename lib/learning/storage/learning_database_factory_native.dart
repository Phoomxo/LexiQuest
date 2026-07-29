import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'learning_database.dart';
import 'learning_database_open_exception.dart';

export 'learning_database_open_exception.dart';

typedef LearningDatabaseDirectoryProvider = Future<Directory> Function();

final class LearningDatabaseFactory {
  LearningDatabaseFactory({
    this.fileName = 'learning.sqlite',
    LearningDatabaseDirectoryProvider? directoryProvider,
  }) : directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _requireAndroid = true;

  LearningDatabaseFactory.nativeForTesting({
    this.fileName = 'learning.sqlite',
    required this.directoryProvider,
  }) : _requireAndroid = false;

  final String fileName;
  final LearningDatabaseDirectoryProvider directoryProvider;
  final bool _requireAndroid;

  Future<LearningDatabase> open() async {
    if (_requireAndroid && !Platform.isAndroid) {
      throw const LearningDatabaseOpenException(
        LearningDatabaseOpenErrorCode.unsupportedPlatform,
        'Durable learning storage is available on Android only.',
      );
    }

    final directory = await directoryProvider();
    await directory.create(recursive: true);
    final databaseFile = File(path.join(directory.path, fileName));
    _preflight(databaseFile);

    final database = LearningDatabase(
      NativeDatabase.createInBackground(
        databaseFile,
        setup: _configureDatabase,
      ),
    );
    try {
      await database.customSelect('SELECT 1 AS ready').getSingle();
      return database;
    } on LearningDatabaseMigrationException {
      await database.close();
      throw const LearningDatabaseOpenException(
        LearningDatabaseOpenErrorCode.incompatibleSchema,
        'The local learning schema is not supported by this build.',
      );
    } on Object {
      await database.close();
      throw const LearningDatabaseOpenException(
        LearningDatabaseOpenErrorCode.corruptOrUnreadable,
        'The local learning database cannot be opened safely.',
      );
    }
  }
}

void _preflight(File databaseFile) {
  if (!databaseFile.existsSync() || databaseFile.lengthSync() == 0) {
    return;
  }

  Database? database;
  try {
    database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
    final integrity = database.select('PRAGMA quick_check');
    if (integrity.length != 1 || integrity.first.values.first != 'ok') {
      throw const LearningDatabaseOpenException(
        LearningDatabaseOpenErrorCode.corruptOrUnreadable,
        'The local learning database failed its integrity check.',
      );
    }
    final versionRows = database.select('PRAGMA user_version');
    final version = versionRows.first.values.first as int;
    if (version != 0 && version != 1) {
      throw const LearningDatabaseOpenException(
        LearningDatabaseOpenErrorCode.incompatibleSchema,
        'The local learning schema is not supported by this build.',
      );
    }
  } on LearningDatabaseOpenException {
    rethrow;
  } on Object {
    throw const LearningDatabaseOpenException(
      LearningDatabaseOpenErrorCode.corruptOrUnreadable,
      'The local learning database cannot be opened safely.',
    );
  } finally {
    database?.close();
  }
}

void _configureDatabase(Database database) {
  database.execute('PRAGMA foreign_keys = ON');
  database.execute('PRAGMA journal_mode = WAL');
  database.execute('PRAGMA busy_timeout = 5000');
}
