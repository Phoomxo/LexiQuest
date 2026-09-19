import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:vocab_learning_app/data/local/app_database_open_policy.dart';
import 'package:vocab_learning_app/data/local/legacy_learning_import.dart';
import 'legacy_learning_import_test.dart' show seedLegacy;

void main() {
  test('F02 WAL budget rejects before transferring any payload rows', () {
    final dir = Directory.systemTemp.createTempSync('f02-wal-budget-');
    final file = File('${dir.path}/source.sqlite');
    seedLegacy(file);
    final writer = sqlite3.open(file.path);
    try {
      writer.execute('PRAGMA journal_mode=WAL');
      writer.execute('PRAGMA wal_autocheckpoint=0');
      // Bounded 65 MiB fixture remains in WAL while the main file is tiny.
      writer.execute('UPDATE associations SET cue_text=zeroblob(65*1024*1024)');
      expect(file.lengthSync(), lessThan(64 * 1024 * 1024));
      final mainBefore = file.readAsBytesSync();
      final wal = File('${file.path}-wal');
      final walLength = wal.lengthSync();
      var payloadReads = 0;
      expect(
        () => LegacyLearningSnapshot.read(
          file,
          openReadOnly: (path) => _ObservedDatabase(
            sqlite3.open(path, mode: OpenMode.readOnly),
            () {
              payloadReads++;
              throw StateError('payload transfer before budget admission');
            },
          ),
        ),
        throwsA(isA<AppDatabaseOpenException>()),
      );
      expect(payloadReads, 0);
      expect(file.readAsBytesSync(), mainBefore);
      expect(wal.lengthSync(), walLength);
      expect(
        dir.listSync().whereType<File>().map((f) => f.path),
        isNot(contains('${dir.path}/destination.sqlite')),
      );
    } finally {
      writer.close();
      dir.deleteSync(recursive: true);
    }
  });
}

class _ObservedDatabase implements Database {
  _ObservedDatabase(this.delegate, this.payloadRead);
  final Database delegate;
  final void Function() payloadRead;
  @override
  void execute(String sql, [List<Object?> parameters = const []]) =>
      delegate.execute(sql, parameters);
  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) {
    if (sql.startsWith('SELECT * FROM')) payloadRead();
    return delegate.select(sql, parameters);
  }

  @override
  void close() => delegate.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
