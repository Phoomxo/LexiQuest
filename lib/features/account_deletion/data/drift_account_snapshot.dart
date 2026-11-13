import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../domain/account_deletion_contracts.dart';

final class LocalAccountSnapshot {
  const LocalAccountSnapshot({
    required this.bytes,
    required this.sha256,
    required this.coveredScopes,
    required this.generatedAtUtc,
  });

  final Uint8List bytes;
  final String sha256;
  final Set<String> coveredScopes;
  final DateTime generatedAtUtc;
}

/// Creates the complete owner-scoped local snapshot used before account deletion.
final class DriftAccountSnapshotBuilder {
  const DriftAccountSnapshotBuilder(this.database, {required this.nowUtc});

  final AppDatabase database;
  final DateTime Function() nowUtc;

  Future<LocalAccountSnapshot> build({required String ownerId}) async {
    final owner = ownerId.trim();
    if (owner.isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    final generatedAt = nowUtc();
    if (!generatedAt.isUtc) {
      throw ArgumentError.value(generatedAt, 'nowUtc', 'must be UTC');
    }

    final scopes = requiredFullAccountExportScopes.toList()..sort();
    final data = <String, Object?>{};
    await database.transaction(() async {
      for (final scope in scopes) {
        final rows = await database
            .customSelect(
              _queryFor(scope),
              variables: [Variable<String>(owner)],
            )
            .get();
        data[scope] = rows.map((row) => _canonicalRow(row.data)).toList();
      }
    });

    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': database.schemaVersion,
          'generatedAtUtc': generatedAt.toIso8601String(),
          'ownerId': owner,
          'coveredScopes': scopes,
          'exclusions': const [
            'cloud-only records',
            'authentication credentials',
            'API keys and tokens',
          ],
          'data': data,
        }),
      ),
    );
    return LocalAccountSnapshot(
      bytes: bytes,
      sha256: sha256.convert(bytes).toString(),
      coveredScopes: Set.unmodifiable(scopes),
      generatedAtUtc: generatedAt,
    );
  }

  String _queryFor(String scope) => switch (scope) {
    'local_owners' => 'SELECT * FROM local_owners WHERE id = ? ORDER BY id',
    'vocabulary_import_rows' =>
      'SELECT r.* FROM vocabulary_import_rows r '
          'INNER JOIN vocabulary_imports i ON i.id = r.import_id '
          'WHERE i.owner_id = ? ORDER BY r.row_number, r.id',
    'quest_objective_progress' =>
      'SELECT p.* FROM quest_objective_progress p '
          'INNER JOIN quest_instances i ON i.instance_id = p.instance_id '
          'WHERE i.owner_id = ? ORDER BY p.instance_id, p.objective_id',
    _ => 'SELECT * FROM $scope WHERE owner_id = ? ORDER BY rowid',
  };

  Map<String, Object?> _canonicalRow(Map<String, Object?> row) {
    final keys = row.keys.toList()..sort();
    return {for (final key in keys) key: _jsonValue(row[key])};
  }

  Object? _jsonValue(Object? value) => switch (value) {
    Uint8List bytes => base64Encode(bytes),
    _ => value,
  };
}
