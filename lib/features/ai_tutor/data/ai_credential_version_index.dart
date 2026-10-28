import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../../runtime/runtime_flag_namespaces.dart';
import '../../sync/data/drift_owner_operation_gate.dart';

enum AiCredentialMutationKind { replace, delete }

final class AiCredentialPointer {
  const AiCredentialPointer._(this.source, this.version, this.isDeleted);

  factory AiCredentialPointer.version(String version) => AiCredentialPointer._(
    'version:${_requiredToken(version)}',
    version,
    false,
  );

  factory AiCredentialPointer.deleted(String operationVersion) =>
      AiCredentialPointer._(
        'deleted:${_requiredToken(operationVersion)}',
        null,
        true,
      );

  factory AiCredentialPointer.fromSource(String source) {
    if (source.startsWith('version:')) {
      return AiCredentialPointer.version(source.substring('version:'.length));
    }
    if (source.startsWith('deleted:')) {
      return AiCredentialPointer.deleted(source.substring('deleted:'.length));
    }
    throw const FormatException('Invalid AI credential pointer.');
  }

  final String source;
  final String? version;
  final bool isDeleted;
}

final class AiCredentialPreparedMutation {
  const AiCredentialPreparedMutation({
    required this.expectedPointer,
    required this.obsoleteBlobVersion,
  });

  final AiCredentialPointer? expectedPointer;
  final String? obsoleteBlobVersion;
}

final class AiCredentialMutationIntent {
  const AiCredentialMutationIntent({
    required this.ownerToken,
    required this.operationVersion,
    required this.kind,
    required this.expectedPointer,
    required this.committed,
    required this.obsoleteBlobVersion,
  });

  final String ownerToken;
  final String operationVersion;
  final AiCredentialMutationKind kind;
  final AiCredentialPointer? expectedPointer;
  final bool committed;
  final String? obsoleteBlobVersion;
}

abstract interface class AiCredentialVersionIndex {
  Future<AiCredentialPointer?> readPointer(String ownerToken);

  Future<AiCredentialPreparedMutation> prepareMutation({
    required String ownerToken,
    required String operationVersion,
    required AiCredentialMutationKind kind,
    required bool legacyBlobExists,
    required String leaseToken,
    required DateTime nowUtc,
  });

  Future<void> commitMutation({
    required String ownerToken,
    required String operationVersion,
    required AiCredentialMutationKind kind,
    required AiCredentialPointer? expectedPointer,
    required String leaseToken,
    required DateTime nowUtc,
  });

  Future<List<AiCredentialMutationIntent>> pendingMutations({
    required String leaseToken,
    required DateTime nowUtc,
  });

  Future<void> completeMutation({
    required String ownerToken,
    required String operationVersion,
    required String leaseToken,
    required DateTime nowUtc,
  });

  Future<void> eraseOwnerMetadata({
    required String ownerToken,
    required String leaseToken,
    required DateTime nowUtc,
  });
}

/// Schema-12 credential metadata. API keys never enter SQLite: runtime flags
/// contain only opaque owner/version tokens, CAS expectations and cleanup
/// intent state.
final class DriftAiCredentialVersionIndex implements AiCredentialVersionIndex {
  const DriftAiCredentialVersionIndex(this.database);

  static const _pointerPrefix = RuntimeFlagNamespaces.aiCredentialPointerPrefix;
  static const _intentPrefix = RuntimeFlagNamespaces.aiCredentialIntentPrefix;

  final AppDatabase database;

  @override
  Future<AiCredentialPointer?> readPointer(String ownerToken) async {
    final row = await database
        .customSelect(
          'SELECT source FROM runtime_flags WHERE "key" = ? LIMIT 1',
          variables: <Variable<Object>>[
            Variable<String>(_pointerKey(ownerToken)),
          ],
          readsFrom: <ResultSetImplementation<Table, Object?>>{
            database.runtimeFlags,
          },
        )
        .getSingleOrNull();
    if (row == null) return null;
    return AiCredentialPointer.fromSource(row.read<String>('source'));
  }

  @override
  Future<AiCredentialPreparedMutation> prepareMutation({
    required String ownerToken,
    required String operationVersion,
    required AiCredentialMutationKind kind,
    required bool legacyBlobExists,
    required String leaseToken,
    required DateTime nowUtc,
  }) {
    final owner = _requiredToken(ownerToken);
    final operation = _requiredToken(operationVersion);
    return database.transaction(() async {
      await _requireLease(leaseToken, nowUtc);
      final expected = await readPointer(owner);
      final obsoleteBlobVersion =
          expected?.version ??
          (expected == null && legacyBlobExists ? 'legacy' : null);
      await database.customInsert(
        '''
        INSERT INTO runtime_flags
          ("key", bool_value, source, updated_at_utc_ms, expires_at_utc_ms)
        VALUES (?, 1, ?, ?, NULL)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(_intentKey(owner, operation)),
          Variable<String>(
            _encodeIntent(
              ownerToken: owner,
              operationVersion: operation,
              kind: kind,
              expectedPointer: expected,
              committed: false,
              obsoleteBlobVersion: obsoleteBlobVersion,
            ),
          ),
          Variable<int>(nowUtc.millisecondsSinceEpoch),
        ],
        updates: <TableInfo<Table, Object?>>{database.runtimeFlags},
      );
      return AiCredentialPreparedMutation(
        expectedPointer: expected,
        obsoleteBlobVersion: obsoleteBlobVersion,
      );
    });
  }

  @override
  Future<void> eraseOwnerMetadata({
    required String ownerToken,
    required String leaseToken,
    required DateTime nowUtc,
  }) {
    final owner = _requiredToken(ownerToken);
    final intentPrefix = '$_intentPrefix$owner:';
    return database.transaction(() async {
      await _requireLease(leaseToken, nowUtc);
      await database.customUpdate(
        '''
        DELETE FROM runtime_flags
        WHERE "key" = ? OR ("key" >= ? AND "key" < ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(_pointerKey(owner)),
          Variable<String>(intentPrefix),
          Variable<String>(
            RuntimeFlagNamespaces.prefixUpperBound(intentPrefix),
          ),
        ],
        updates: <TableInfo<Table, Object?>>{database.runtimeFlags},
      );
    });
  }

  @override
  Future<void> commitMutation({
    required String ownerToken,
    required String operationVersion,
    required AiCredentialMutationKind kind,
    required AiCredentialPointer? expectedPointer,
    required String leaseToken,
    required DateTime nowUtc,
  }) {
    final owner = _requiredToken(ownerToken);
    final operation = _requiredToken(operationVersion);
    return database.transaction(() async {
      await _requireLease(leaseToken, nowUtc);
      final current = await readPointer(owner);
      if (!_samePointer(current, expectedPointer)) {
        throw StateError('AI credential pointer changed before commit.');
      }
      final intentKey = _intentKey(owner, operation);
      final intent = await _readIntent(intentKey);
      if (intent == null ||
          intent.kind != kind ||
          intent.committed ||
          !_samePointer(intent.expectedPointer, expectedPointer)) {
        throw StateError('AI credential mutation intent is invalid.');
      }
      final nextPointer = kind == AiCredentialMutationKind.replace
          ? AiCredentialPointer.version(operation)
          : AiCredentialPointer.deleted(operation);
      await database.customInsert(
        '''
        INSERT INTO runtime_flags
          ("key", bool_value, source, updated_at_utc_ms, expires_at_utc_ms)
        VALUES (?, 1, ?, ?, NULL)
        ON CONFLICT("key") DO UPDATE SET
          bool_value = 1,
          source = excluded.source,
          updated_at_utc_ms = excluded.updated_at_utc_ms,
          expires_at_utc_ms = NULL
        ''',
        variables: <Variable<Object>>[
          Variable<String>(_pointerKey(owner)),
          Variable<String>(nextPointer.source),
          Variable<int>(nowUtc.millisecondsSinceEpoch),
        ],
        updates: <TableInfo<Table, Object?>>{database.runtimeFlags},
      );
      final changed = await database.customUpdate(
        'UPDATE runtime_flags SET source = ?, updated_at_utc_ms = ? '
        'WHERE "key" = ?',
        variables: <Variable<Object>>[
          Variable<String>(
            _encodeIntent(
              ownerToken: owner,
              operationVersion: operation,
              kind: kind,
              expectedPointer: expectedPointer,
              committed: true,
              obsoleteBlobVersion: intent.obsoleteBlobVersion,
            ),
          ),
          Variable<int>(nowUtc.millisecondsSinceEpoch),
          Variable<String>(intentKey),
        ],
        updates: <TableInfo<Table, Object?>>{database.runtimeFlags},
      );
      if (changed != 1) {
        throw StateError('AI credential intent disappeared during commit.');
      }
    });
  }

  @override
  Future<List<AiCredentialMutationIntent>> pendingMutations({
    required String leaseToken,
    required DateTime nowUtc,
  }) {
    final intentUpperBound = RuntimeFlagNamespaces.prefixUpperBound(
      _intentPrefix,
    );
    return database.transaction(() async {
      await _requireLease(leaseToken, nowUtc);
      final rows = await database
          .customSelect(
            'SELECT source FROM runtime_flags '
            'WHERE "key" >= ? AND "key" < ?',
            variables: <Variable<Object>>[
              const Variable<String>(_intentPrefix),
              Variable<String>(intentUpperBound),
            ],
            readsFrom: <ResultSetImplementation<Table, Object?>>{
              database.runtimeFlags,
            },
          )
          .get();
      return rows
          .map((row) => _decodeIntent(row.read<String>('source')))
          .toList(growable: false);
    });
  }

  @override
  Future<void> completeMutation({
    required String ownerToken,
    required String operationVersion,
    required String leaseToken,
    required DateTime nowUtc,
  }) {
    final owner = _requiredToken(ownerToken);
    final operation = _requiredToken(operationVersion);
    return database.transaction(() async {
      await _requireLease(leaseToken, nowUtc);
      await database.customUpdate(
        'DELETE FROM runtime_flags WHERE "key" = ?',
        variables: <Variable<Object>>[
          Variable<String>(_intentKey(owner, operation)),
        ],
        updates: <TableInfo<Table, Object?>>{database.runtimeFlags},
      );
    });
  }

  Future<AiCredentialMutationIntent?> _readIntent(String key) async {
    final row = await database
        .customSelect(
          'SELECT source FROM runtime_flags WHERE "key" = ? LIMIT 1',
          variables: <Variable<Object>>[Variable<String>(key)],
          readsFrom: <ResultSetImplementation<Table, Object?>>{
            database.runtimeFlags,
          },
        )
        .getSingleOrNull();
    return row == null ? null : _decodeIntent(row.read<String>('source'));
  }

  Future<void> _requireLease(String leaseToken, DateTime nowUtc) async {
    final lease = _requiredToken(leaseToken);
    _requireUtc(nowUtc);
    final changed = await database.customUpdate(
      '''
      UPDATE runtime_flags
      SET updated_at_utc_ms = updated_at_utc_ms
      WHERE "key" = ?
        AND bool_value = 1
        AND source = ?
        AND expires_at_utc_ms IS NOT NULL
        AND expires_at_utc_ms > ?
      ''',
      variables: <Variable<Object>>[
        const Variable<String>(DriftOwnerOperationGate.gateKey),
        Variable<String>(lease),
        Variable<int>(nowUtc.millisecondsSinceEpoch),
      ],
      updates: <TableInfo<Table, Object?>>{database.runtimeFlags},
    );
    if (changed != 1) throw StateError('Owner-operation lease was lost.');
  }

  static String _pointerKey(String ownerToken) =>
      '$_pointerPrefix${_requiredToken(ownerToken)}';

  static String _intentKey(String ownerToken, String operationVersion) =>
      '$_intentPrefix${_requiredToken(ownerToken)}:${_requiredToken(operationVersion)}';
}

/// Test/headless fallback. Production bootstrap always supplies the Drift
/// implementation so pointer commits share the Task 5 database fence.
final class VolatileAiCredentialVersionIndex
    implements AiCredentialVersionIndex {
  final Map<String, AiCredentialPointer> _pointers =
      <String, AiCredentialPointer>{};
  final Map<String, AiCredentialMutationIntent> _intents =
      <String, AiCredentialMutationIntent>{};

  @override
  Future<AiCredentialPointer?> readPointer(String ownerToken) async =>
      _pointers[_requiredToken(ownerToken)];

  @override
  Future<AiCredentialPreparedMutation> prepareMutation({
    required String ownerToken,
    required String operationVersion,
    required AiCredentialMutationKind kind,
    required bool legacyBlobExists,
    required String leaseToken,
    required DateTime nowUtc,
  }) async {
    final owner = _requiredToken(ownerToken);
    final operation = _requiredToken(operationVersion);
    final expected = _pointers[owner];
    final obsoleteBlobVersion =
        expected?.version ??
        (expected == null && legacyBlobExists ? 'legacy' : null);
    final key = '$owner/$operation';
    if (_intents.containsKey(key)) throw StateError('Duplicate mutation.');
    _intents[key] = AiCredentialMutationIntent(
      ownerToken: owner,
      operationVersion: operation,
      kind: kind,
      expectedPointer: expected,
      committed: false,
      obsoleteBlobVersion: obsoleteBlobVersion,
    );
    return AiCredentialPreparedMutation(
      expectedPointer: expected,
      obsoleteBlobVersion: obsoleteBlobVersion,
    );
  }

  @override
  Future<void> commitMutation({
    required String ownerToken,
    required String operationVersion,
    required AiCredentialMutationKind kind,
    required AiCredentialPointer? expectedPointer,
    required String leaseToken,
    required DateTime nowUtc,
  }) async {
    final owner = _requiredToken(ownerToken);
    final operation = _requiredToken(operationVersion);
    final key = '$owner/$operation';
    final intent = _intents[key];
    if (intent == null ||
        intent.kind != kind ||
        intent.committed ||
        !_samePointer(_pointers[owner], expectedPointer)) {
      throw StateError('Invalid credential mutation commit.');
    }
    _pointers[owner] = kind == AiCredentialMutationKind.replace
        ? AiCredentialPointer.version(operation)
        : AiCredentialPointer.deleted(operation);
    _intents[key] = AiCredentialMutationIntent(
      ownerToken: owner,
      operationVersion: operation,
      kind: kind,
      expectedPointer: expectedPointer,
      committed: true,
      obsoleteBlobVersion: intent.obsoleteBlobVersion,
    );
  }

  @override
  Future<List<AiCredentialMutationIntent>> pendingMutations({
    required String leaseToken,
    required DateTime nowUtc,
  }) async => List<AiCredentialMutationIntent>.unmodifiable(_intents.values);

  @override
  Future<void> completeMutation({
    required String ownerToken,
    required String operationVersion,
    required String leaseToken,
    required DateTime nowUtc,
  }) async {
    _intents.remove(
      '${_requiredToken(ownerToken)}/${_requiredToken(operationVersion)}',
    );
  }

  @override
  Future<void> eraseOwnerMetadata({
    required String ownerToken,
    required String leaseToken,
    required DateTime nowUtc,
  }) async {
    final owner = _requiredToken(ownerToken);
    _pointers.remove(owner);
    _intents.removeWhere((key, _) => key.startsWith('$owner/'));
  }
}

String _encodeIntent({
  required String ownerToken,
  required String operationVersion,
  required AiCredentialMutationKind kind,
  required AiCredentialPointer? expectedPointer,
  required bool committed,
  required String? obsoleteBlobVersion,
}) => jsonEncode(<String, Object?>{
  'schema': 1,
  'ownerToken': ownerToken,
  'operationVersion': operationVersion,
  'kind': kind.name,
  'expectedPointer': expectedPointer?.source,
  'committed': committed,
  'obsoleteBlobVersion': obsoleteBlobVersion,
});

AiCredentialMutationIntent _decodeIntent(String source) {
  final value = jsonDecode(source);
  if (value is! Map<String, dynamic> || value['schema'] != 1) {
    throw const FormatException('Invalid AI credential intent.');
  }
  final owner = value['ownerToken'];
  final operation = value['operationVersion'];
  final kind = AiCredentialMutationKind.values
      .where((candidate) => candidate.name == value['kind'])
      .firstOrNull;
  final expectedSource = value['expectedPointer'];
  final committed = value['committed'];
  final obsolete = value['obsoleteBlobVersion'];
  if (owner is! String ||
      operation is! String ||
      kind == null ||
      (expectedSource != null && expectedSource is! String) ||
      committed is! bool ||
      (obsolete != null && obsolete is! String)) {
    throw const FormatException('Invalid AI credential intent.');
  }
  return AiCredentialMutationIntent(
    ownerToken: _requiredToken(owner),
    operationVersion: _requiredToken(operation),
    kind: kind,
    expectedPointer: expectedSource == null
        ? null
        : AiCredentialPointer.fromSource(expectedSource),
    committed: committed,
    obsoleteBlobVersion: obsolete as String?,
  );
}

bool _samePointer(AiCredentialPointer? left, AiCredentialPointer? right) =>
    left?.source == right?.source;

String _requiredToken(String value) {
  final token = value.trim();
  if (token.isEmpty ||
      token.length > 256 ||
      !RegExp(r'^[A-Za-z0-9_.:-]+$').hasMatch(token)) {
    throw ArgumentError.value(value, 'token', 'must be an opaque safe token');
  }
  return token;
}

void _requireUtc(DateTime value) {
  if (!value.isUtc) throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
}
