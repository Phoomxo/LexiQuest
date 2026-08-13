import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_credential_version_index.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';

void main() {
  test(
    'profiles and consent are isolated by the current active owner',
    () async {
      final values = <String, String>{};
      var activeOwner = 'owner-a';
      final store = SecureAiTutorSettingsStore(
        _MemorySecureStore(values),
        activeOwnerId: () async => activeOwner,
      );
      await store.writeCredential(_credential('key-a', 'model-a'));

      activeOwner = 'owner-b';
      expect(await store.readCredential(), isNull);
      await store.writeCredential(_credential('key-b', 'model-b'));

      activeOwner = 'owner-a';
      expect((await store.readCredential())?.key, 'key-a');
      activeOwner = 'owner-b';
      expect((await store.readCredential())?.key, 'key-b');
    },
  );

  test('unattributable device-global legacy profile is discarded', () async {
    final values = <String, String>{
      'ai_active_profile_v1': jsonEncode({
        'version': 1,
        'key': 'legacy-secret',
        'providerId': 'gemini',
        'model': 'legacy-model',
        'providerConsent': true,
        'shareLearningSummary': true,
      }),
      'gemini_api_key': 'legacy-gemini-secret',
      'gemini_provider_consent': 'true',
      'gemini_learning_summary_consent': 'true',
    };
    final store = SecureAiTutorSettingsStore(
      _MemorySecureStore(values),
      activeOwnerId: () async => 'owner-a',
    );

    expect(await store.readCredential(), isNull);
    expect(values, isNot(contains('ai_active_profile_v1')));
    expect(values.values.join(), isNot(contains('legacy-secret')));
    expect(values, isNot(contains('gemini_api_key')));
    expect(values, isNot(contains('gemini_provider_consent')));
    expect(values, isNot(contains('gemini_learning_summary_consent')));
  });

  test('unowned fenced erasure cannot mutate unscoped legacy values', () async {
    final values = <String, String>{
      'ai_active_profile_v1': 'legacy-profile',
      'ai_api_key': 'legacy-ai-key',
      'gemini_api_key': 'legacy-gemini-key',
      'gemini_provider_consent': 'true',
      'gemini_learning_summary_consent': 'true',
      'ai_provider_consent': 'true',
      'ai_learning_summary_consent': 'true',
      'ai_provider_id': 'gemini',
      'ai_model': 'legacy-model',
      'ai_custom_base_url': 'https://private.invalid',
    };
    final before = Map<String, String>.of(values);
    final store = SecureAiTutorSettingsStore(
      _MemorySecureStore(values),
      activeOwnerId: () async => 'owner-a',
    );

    await expectLater(
      store.eraseOwnerCredentialsFenced(
        'owner-a',
        leaseToken: 'stale-token',
        leaseIsOwned: () async => false,
        nowUtc: () => DateTime.utc(2026, 8, 11, 1),
      ),
      throwsA(_aiFailure(AiFailureCode.cancelled)),
    );

    expect(values, before);
  });

  test(
    'explicit owner deletion removes every scoped value only for that owner',
    () async {
      final values = <String, String>{};
      var activeOwner = 'owner-a';
      final store = SecureAiTutorSettingsStore(
        _MemorySecureStore(values),
        activeOwnerId: () async => activeOwner,
      );
      await store.writeCredential(_credential('key-a', 'model-a'));
      await store.writeProviderConsent(true);
      activeOwner = 'owner-b';
      await store.writeCredential(_credential('key-b', 'model-b'));

      await store.deleteCredentialForOwner('owner-a');

      expect(await store.readCredentialForOwner('owner-a'), isNull);
      expect((await store.readCredentialForOwner('owner-b'))?.key, 'key-b');
      expect(values.values.join(), isNot(contains('key-a')));
    },
  );

  test(
    'credential metadata erase treats wildcard and case tokens literally',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final gate = DriftOwnerOperationGate(database);
      final index = DriftAiCredentialVersionIndex(database);
      final now = DateTime.utc(2026, 8, 11, 0, 30);
      const leaseToken = 'owner-metadata-lease';
      expect(
        await gate.tryAcquire(
          token: leaseToken,
          nowUtc: now,
          leaseDuration: const Duration(minutes: 5),
        ),
        isTrue,
      );
      await index.prepareMutation(
        ownerToken: 'owner_a',
        operationVersion: 'operation-a',
        kind: AiCredentialMutationKind.replace,
        legacyBlobExists: false,
        leaseToken: leaseToken,
        nowUtc: now,
      );
      await index.prepareMutation(
        ownerToken: 'ownerXa',
        operationVersion: 'operation-b',
        kind: AiCredentialMutationKind.replace,
        legacyBlobExists: false,
        leaseToken: leaseToken,
        nowUtc: now,
      );
      await database.customInsert(
        'INSERT INTO runtime_flags '
        '("key", bool_value, source, updated_at_utc_ms) VALUES (?, 1, ?, ?)',
        variables: const <Variable<Object>>[
          Variable<String>('AICREDENTIALINTENT:operator'),
          Variable<String>('opaque-global-source'),
          Variable<int>(1),
        ],
      );
      final unknownBefore =
          (await database
                  .customSelect(
                    'SELECT * FROM runtime_flags WHERE "key" = ?',
                    variables: const <Variable<Object>>[
                      Variable<String>('AICREDENTIALINTENT:operator'),
                    ],
                  )
                  .getSingle())
              .data
              .toString();
      expect(
        await index.pendingMutations(leaseToken: leaseToken, nowUtc: now),
        hasLength(2),
      );

      await index.eraseOwnerMetadata(
        ownerToken: 'owner_a',
        leaseToken: leaseToken,
        nowUtc: now,
      );

      final keys = await database
          .customSelect(
            'SELECT "key" FROM runtime_flags '
            'WHERE "key" >= ? AND "key" < ? ORDER BY "key"',
            variables: const <Variable<Object>>[
              Variable<String>('aiCredentialIntent:'),
              Variable<String>('aiCredentialIntent;'),
            ],
          )
          .map((row) => row.read<String>('key'))
          .get();
      expect(keys, const ['aiCredentialIntent:ownerXa:operation-b']);

      await index.prepareMutation(
        ownerToken: 'YWFh',
        operationVersion: 'operation-c',
        kind: AiCredentialMutationKind.replace,
        legacyBlobExists: false,
        leaseToken: leaseToken,
        nowUtc: now,
      );
      await index.prepareMutation(
        ownerToken: 'YWFH',
        operationVersion: 'operation-d',
        kind: AiCredentialMutationKind.replace,
        legacyBlobExists: false,
        leaseToken: leaseToken,
        nowUtc: now,
      );
      final foreignBefore = await database
          .customSelect(
            'SELECT source FROM runtime_flags WHERE "key" = ?',
            variables: const <Variable<Object>>[
              Variable<String>('aiCredentialIntent:YWFH:operation-d'),
            ],
          )
          .map((row) => row.read<String>('source'))
          .getSingle();

      await index.eraseOwnerMetadata(
        ownerToken: 'YWFh',
        leaseToken: leaseToken,
        nowUtc: now,
      );

      expect(
        await database
            .customSelect(
              'SELECT source FROM runtime_flags WHERE "key" = ?',
              variables: const <Variable<Object>>[
                Variable<String>('aiCredentialIntent:YWFH:operation-d'),
              ],
            )
            .map((row) => row.read<String>('source'))
            .getSingle(),
        foreignBefore,
      );
      expect(
        (await database
                .customSelect(
                  'SELECT * FROM runtime_flags WHERE "key" = ?',
                  variables: const <Variable<Object>>[
                    Variable<String>('AICREDENTIALINTENT:operator'),
                  ],
                )
                .getSingle())
            .data
            .toString(),
        unknownBefore,
      );
    },
  );

  test('stale version writer cannot replace a takeover credential', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final gate = DriftOwnerOperationGate(database);
    final values = <String, String>{};
    final storage = _MemorySecureStore(values);
    final store = SecureAiTutorSettingsStore(
      storage,
      activeOwnerId: () async => 'owner-a',
      versionIndex: DriftAiCredentialVersionIndex(database),
    );
    var now = DateTime.utc(2026, 8, 11, 1);
    await store.writeCredential(_credential('legacy-key', 'legacy-model'));
    expect(
      await gate.tryAcquire(
        token: 'token-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    final writeStarted = Completer<void>();
    final allowWrite = Completer<void>();
    storage.beforeWrite = (key, _) async {
      if (!key.endsWith(':version:token-a')) return;
      writeStarted.complete();
      await allowWrite.future;
    };

    final staleWrite = store.replaceCredentialForOwnerFenced(
      'owner-a',
      _credential('stale-key', 'stale-model'),
      operationVersion: 'token-a',
      leaseIsOwned: () => gate.isOwned(token: 'token-a', nowUtc: now),
      nowUtc: () => now,
    );
    final staleExpectation = expectLater(
      staleWrite,
      throwsA(_aiFailure(AiFailureCode.cancelled)),
    );
    await writeStarted.future;
    now = now.add(const Duration(minutes: 2));
    expect(
      await gate.tryAcquire(
        token: 'token-b',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    allowWrite.complete();
    await staleExpectation;
    storage.beforeWrite = null;

    await store.replaceCredentialForOwnerFenced(
      'owner-a',
      _credential('takeover-key', 'takeover-model'),
      operationVersion: 'token-b',
      leaseIsOwned: () => gate.isOwned(token: 'token-b', nowUtc: now),
      nowUtc: () => now,
    );
    await store.recoverCredentialMutations(
      leaseToken: 'token-b',
      nowUtc: () => now,
    );

    final active = await store.readCredentialForOwner('owner-a');
    expect(active?.key, 'takeover-key');
    expect(values.values.join(), isNot(contains('stale-key')));
  });

  test(
    'cleanup intent survives failure and recovery never stores secrets in SQLite',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final gate = DriftOwnerOperationGate(database);
      final values = <String, String>{};
      final storage = _MemorySecureStore(values);
      final store = SecureAiTutorSettingsStore(
        storage,
        activeOwnerId: () async => 'owner-a',
        versionIndex: DriftAiCredentialVersionIndex(database),
      );
      final now = DateTime.utc(2026, 8, 11, 2);
      await gate.tryAcquire(
        token: 'token-a',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      );
      await store.replaceCredentialForOwnerFenced(
        'owner-a',
        _credential('first-secret', 'model-a'),
        operationVersion: 'token-a',
        leaseIsOwned: () => gate.isOwned(token: 'token-a', nowUtc: now),
        nowUtc: () => now,
      );
      await gate.release(token: 'token-a');
      await gate.tryAcquire(
        token: 'token-b',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      );
      storage.failDeleteOnceSuffix = ':version:token-a';

      await store.replaceCredentialForOwnerFenced(
        'owner-a',
        _credential('second-secret', 'model-b'),
        operationVersion: 'token-b',
        leaseIsOwned: () => gate.isOwned(token: 'token-b', nowUtc: now),
        nowUtc: () => now,
      );
      expect((await store.readCredential())?.key, 'second-secret');
      expect(
        await database
            .customSelect(
              'SELECT COUNT(*) AS count FROM runtime_flags '
              'WHERE "key" LIKE ?',
              variables: const [Variable<String>('aiCredentialIntent:%')],
            )
            .map((row) => row.read<int>('count'))
            .getSingle(),
        1,
      );

      expect(
        await store.recoverCredentialMutations(
          leaseToken: 'token-b',
          nowUtc: () => now,
        ),
        1,
      );
      final metadata = await database
          .customSelect('SELECT "key", source FROM runtime_flags')
          .get();
      final serialized = metadata
          .expand(
            (row) => <String>[
              row.read<String>('key'),
              row.read<String>('source'),
            ],
          )
          .join('|');
      expect(database.schemaVersion, 12);
      expect(serialized, isNot(contains('first-secret')));
      expect(serialized, isNot(contains('second-secret')));
      expect(serialized, isNot(contains('model-a')));
      expect(serialized, isNot(contains('model-b')));
    },
  );

  test(
    'recovery removes both links of a superseded committed cleanup chain',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final gate = DriftOwnerOperationGate(database);
      final values = <String, String>{};
      final storage = _MemorySecureStore(values);
      final store = SecureAiTutorSettingsStore(
        storage,
        activeOwnerId: () async => 'owner-a',
        versionIndex: DriftAiCredentialVersionIndex(database),
      );
      final now = DateTime.utc(2026, 8, 11, 2, 20);
      await gate.tryAcquire(
        token: 'version-0',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      );
      await store.replaceCredentialForOwnerFenced(
        'owner-a',
        _credential('secret-0', 'model-0'),
        operationVersion: 'version-0',
        leaseIsOwned: () => gate.isOwned(token: 'version-0', nowUtc: now),
        nowUtc: () => now,
      );
      await gate.release(token: 'version-0');
      await gate.tryAcquire(
        token: 'version-1',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      );
      storage.failDeleteOnceSuffix = ':version:version-0';
      await store.replaceCredentialForOwnerFenced(
        'owner-a',
        _credential('secret-1', 'model-1'),
        operationVersion: 'version-1',
        leaseIsOwned: () => gate.isOwned(token: 'version-1', nowUtc: now),
        nowUtc: () => now,
      );
      await gate.release(token: 'version-1');
      await gate.tryAcquire(
        token: 'version-2',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      );
      await store.replaceCredentialForOwnerFenced(
        'owner-a',
        _credential('secret-2', 'model-2'),
        operationVersion: 'version-2',
        leaseIsOwned: () => gate.isOwned(token: 'version-2', nowUtc: now),
        nowUtc: () => now,
      );

      expect(
        await store.recoverCredentialMutations(
          leaseToken: 'version-2',
          nowUtc: () => now,
        ),
        1,
      );
      expect((await store.readCredential())?.key, 'secret-2');
      expect(values.values.join(), isNot(contains('secret-0')));
      expect(values.values.join(), isNot(contains('secret-1')));
    },
  );

  test(
    'prepared delete retries physical erasure before tombstone recovery',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final gate = DriftOwnerOperationGate(database);
      final values = <String, String>{};
      final storage = _MemorySecureStore(values);
      final store = SecureAiTutorSettingsStore(
        storage,
        activeOwnerId: () async => 'owner-a',
        versionIndex: DriftAiCredentialVersionIndex(database),
      );
      final now = DateTime.utc(2026, 8, 11, 2, 30);
      await gate.tryAcquire(
        token: 'write-token',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      );
      await store.replaceCredentialForOwnerFenced(
        'owner-a',
        _credential('delete-me', 'model-a'),
        operationVersion: 'write-token',
        leaseIsOwned: () => gate.isOwned(token: 'write-token', nowUtc: now),
        nowUtc: () => now,
      );
      await gate.release(token: 'write-token');
      await gate.tryAcquire(
        token: 'delete-token',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      );
      storage.failDeleteOnceSuffix = ':version:write-token';

      await expectLater(
        store.replaceCredentialForOwnerFenced(
          'owner-a',
          null,
          operationVersion: 'delete-token',
          leaseIsOwned: () => gate.isOwned(token: 'delete-token', nowUtc: now),
          nowUtc: () => now,
        ),
        throwsA(_aiFailure(AiFailureCode.secureStorage)),
      );
      expect((await store.readCredential())?.key, 'delete-me');

      expect(
        await store.recoverCredentialMutations(
          leaseToken: 'delete-token',
          nowUtc: () => now,
        ),
        1,
      );
      expect(await store.readCredential(), isNull);
      expect(values.values.join(), isNot(contains('delete-me')));
    },
  );

  test(
    'strict owner erasure removes active, candidate, intents and pointer',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final gate = DriftOwnerOperationGate(database);
      final values = <String, String>{};
      final storage = _MemorySecureStore(values);
      final store = SecureAiTutorSettingsStore(
        storage,
        activeOwnerId: () async => 'owner-a',
        versionIndex: DriftAiCredentialVersionIndex(database),
      );
      final now = DateTime.utc(2026, 8, 11, 2, 45);
      await gate.tryAcquire(
        token: 'erase-token',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      );
      await store.replaceCredentialForOwnerFenced(
        'owner-a',
        _credential('active-secret', 'model-a'),
        operationVersion: 'erase-token',
        leaseIsOwned: () => gate.isOwned(token: 'erase-token', nowUtc: now),
        nowUtc: () => now,
      );
      await store.eraseOwnerCredentialsFenced(
        'owner-a',
        leaseToken: 'erase-token',
        leaseIsOwned: () => gate.isOwned(token: 'erase-token', nowUtc: now),
        nowUtc: () => now,
      );

      expect(await store.readCredential(), isNull);
      expect(values.values.join(), isNot(contains('active-secret')));
      final metadataCount = await database
          .customSelect(
            'SELECT COUNT(*) AS count FROM runtime_flags '
            'WHERE "key" LIKE ? OR "key" LIKE ?',
            variables: const [
              Variable<String>('aiCredentialPointer:%'),
              Variable<String>('aiCredentialIntent:%'),
            ],
          )
          .map((row) => row.read<int>('count'))
          .getSingle();
      expect(metadataCount, 0);
    },
  );

  test('file reopen recovers a prepared non-current immutable blob', () async {
    final root = await Directory.systemTemp.createTemp('ai-credential-index-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}${Platform.pathSeparator}index.sqlite');
    final values = <String, String>{};
    final storage = _MemorySecureStore(values);
    var database = AppDatabase(NativeDatabase(file));
    var gate = DriftOwnerOperationGate(database);
    final ownerToken = base64Url
        .encode(utf8.encode('owner-a'))
        .replaceAll('=', '');
    var now = DateTime.utc(2026, 8, 11, 3);
    await gate.tryAcquire(
      token: 'crashed-token',
      nowUtc: now,
      leaseDuration: const Duration(minutes: 1),
    );
    final index = DriftAiCredentialVersionIndex(database);
    await index.prepareMutation(
      ownerToken: ownerToken,
      operationVersion: 'crashed-token',
      kind: AiCredentialMutationKind.replace,
      legacyBlobExists: false,
      leaseToken: 'crashed-token',
      nowUtc: now,
    );
    values['ai_active_profile_v2:$ownerToken:version:crashed-token'] =
        jsonEncode({
          'version': 1,
          'key': 'orphan-secret',
          'providerId': 'gemini',
          'model': 'orphan-model',
          'providerConsent': true,
          'shareLearningSummary': false,
        });
    await database.close();

    database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    gate = DriftOwnerOperationGate(database);
    now = now.add(const Duration(minutes: 2));
    await gate.tryAcquire(
      token: 'recovery-token',
      nowUtc: now,
      leaseDuration: const Duration(minutes: 1),
    );
    final reopened = SecureAiTutorSettingsStore(
      storage,
      activeOwnerId: () async => 'owner-a',
      versionIndex: DriftAiCredentialVersionIndex(database),
    );

    expect(
      await reopened.recoverCredentialMutations(
        leaseToken: 'recovery-token',
        nowUtc: () => now,
      ),
      1,
    );
    expect(values.values.join(), isNot(contains('orphan-secret')));
    expect(database.schemaVersion, 12);
  });
}

Matcher _aiFailure(AiFailureCode code) =>
    isA<AiTutorException>().having((error) => error.code, 'code', code);

AiTutorCredential _credential(String key, String model) => AiTutorCredential(
  key: key,
  providerId: AiProviderId.gemini,
  model: model,
  providerConsent: true,
  shareLearningSummary: false,
);

final class _MemorySecureStore implements SecureValueStore {
  _MemorySecureStore(this.values);

  final Map<String, String> values;
  Future<void> Function(String key, String value)? beforeWrite;
  String? failDeleteOnceSuffix;

  @override
  Future<void> delete(String key) async {
    final suffix = failDeleteOnceSuffix;
    if (suffix != null && key.endsWith(suffix)) {
      failDeleteOnceSuffix = null;
      throw StateError('simulated secure cleanup failure');
    }
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call(key, value);
    values[key] = value;
  }
}
