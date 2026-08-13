import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late _MemoryStore store;
  late ExportUseCases exports;
  late ResearchConsentUseCases consent;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = _MemoryStore();
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    await owners.getOrCreateActiveOwner();
    consent = ResearchConsentUseCases(
      owners: owners,
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    await consent.accept();
    exports = ExportUseCases(
      reader: DriftExportReader(database),
      store: store,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      lifecycleArchive: OwnerLifecycleArchiveExporter(
        database: database,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      ),
    );
    await _seed(database);
  });

  tearDown(() => database.close());

  test('CSV reconciles immutable evidence ids and metadata', () async {
    final artifact = await exports.prepare(
      format: ExportFormat.csv,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    final text = utf8.decode(artifact.bytes).replaceFirst('\uFEFF', '');

    expect(text, contains('sample_size=3'));
    expect(text, contains('word-1'));
    expect(text, contains('attempt-1'));
    expect(text, contains('doc-1@1'));
    expect(artifact.recordCount, 3);
  });

  test('CSV and Anki neutralize spreadsheet formulas', () async {
    await database.customUpdate(
      "UPDATE vocabulary_words SET spelling = '=2+2', meaning = '@SUM(1,1)' "
      "WHERE id = 'word-1'",
    );
    await database.customUpdate(
      "UPDATE vocabulary_categories SET name = '@CATEGORY' "
      "WHERE id = 'category-1'",
    );

    final csv = await exports.prepare(
      format: ExportFormat.csv,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    final anki = await exports.prepare(
      format: ExportFormat.anki,
      selection: const ExportSelection(
        includeVocabulary: true,
        includeAttempts: false,
        includeReading: false,
      ),
      cancellation: ExportCancellation(),
    );

    expect(utf8.decode(csv.bytes), contains("\"'=2+2\""));
    expect(utf8.decode(csv.bytes), contains("\"'@CATEGORY|@SUM(1,1)"));
    expect(utf8.decode(anki.bytes), contains("'=2+2\t'@SUM(1,1)"));
  });

  test('research JSON parses independently and reports exact counts', () async {
    final artifact = await exports.prepare(
      format: ExportFormat.researchJson,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    final parsed =
        jsonDecode(utf8.decode(artifact.bytes)) as Map<String, dynamic>;

    expect(parsed['sampleSize'], 3);
    expect(parsed['schemaVersion'], 1);
    expect(parsed['timeZone'], 'UTC');
    expect((parsed['attempts'] as List).single['evidenceId'], 'attempt-1');
  });

  test('every artifact omits raw provider provenance secrets', () async {
    const sentinel = 'provider-token-SENTINEL-DO-NOT-EXPORT';
    await database.customUpdate(
      'UPDATE answer_attempts SET provider_provenance = ? WHERE id = ?',
      variables: const [
        Variable<String>(sentinel),
        Variable<String>('attempt-1'),
      ],
    );

    for (final format in ExportFormat.values) {
      final artifact = await exports.prepare(
        format: format,
        selection: _all,
        cancellation: ExportCancellation(),
      );
      expect(
        utf8.decode(artifact.bytes, allowMalformed: true),
        isNot(contains(sentinel)),
        reason: '$format must use an explicit non-secret allowlist',
      );
    }
  });

  test(
    'complete owner archive is reachable and saved through export facade',
    () async {
      final artifact = await exports.prepare(
        format: ExportFormat.ownerArchiveJson,
        selection: const ExportSelection(
          includeVocabulary: false,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      final envelope =
          jsonDecode(utf8.decode(artifact.bytes)) as Map<String, dynamic>;
      final content = envelope['content'] as Map<String, dynamic>;
      expect(content['tables'], hasLength(31));
      expect(content['archiveSchemaVersion'], 1);
      expect(content['algorithmVersion'], 1);
      expect(content['databaseSchemaVersion'], 12);
      expect(content['manifestEntryCount'], 31);
      expect(artifact.schemaVersion, content['archiveSchemaVersion']);
      expect(artifact.algorithmVersion, content['algorithmVersion']);
      expect(artifact.recordCount, content['manifestEntryCount']);
      expect(artifact.sha256, isNotEmpty);

      final saved = await exports.export(
        format: ExportFormat.ownerArchiveJson,
        selection: const ExportSelection(
          includeVocabulary: false,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      expect(saved.bytesWritten, artifact.bytes.length);
    },
  );

  test(
    'owner archive maps missing active owner to typed unavailable',
    () async {
      await database.customUpdate('UPDATE local_owners SET is_active = 0');

      await expectLater(
        exports.prepare(
          format: ExportFormat.ownerArchiveJson,
          selection: const ExportSelection(
            includeVocabulary: false,
            includeAttempts: false,
            includeReading: false,
          ),
          cancellation: ExportCancellation(),
        ),
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.unavailable,
          ),
        ),
      );
    },
  );

  test('research dataset export stops after consent withdrawal', () async {
    await consent.withdraw();

    await expectLater(
      exports.prepare(
        format: ExportFormat.researchJson,
        selection: _all,
        cancellation: ExportCancellation(),
      ),
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.consentRequired,
        ),
      ),
    );
    final personal = await exports.prepare(
      format: ExportFormat.csv,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    expect(personal.recordCount, 3);
  });

  test(
    'research export rejects accepted state with withdrawal evidence',
    () async {
      await database.customUpdate(
        'UPDATE research_consents SET withdrawn_at_utc_ms = 200 '
        "WHERE owner_id = 'local:owner' AND consent_version = 1",
      );

      await expectLater(
        exports.export(
          format: ExportFormat.researchJson,
          selection: _all,
          cancellation: ExportCancellation(),
        ),
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.consentRequired,
          ),
        ),
      );
      expect(store.bytesWritten, 0);
    },
  );

  test(
    'research export never mixes source consent with upgraded owner data',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-export-owner-race-',
      );
      final path = '${directory.path}${Platform.pathSeparator}export.sqlite';
      final consentReadInterceptor = _ConsentReadInterceptor();
      AppDatabase openExportDatabase() => AppDatabase(
        NativeDatabase(File(path)).interceptWith(consentReadInterceptor),
      );
      AppDatabase openUpgradeDatabase() =>
          AppDatabase(NativeDatabase(File(path)));

      AppDatabase? exportDatabase;
      AppDatabase? upgradeDatabase;
      try {
        exportDatabase = openExportDatabase();
        await exportDatabase.customSelect('SELECT 1').getSingle();
        await exportDatabase.customSelect('PRAGMA journal_mode = WAL').get();
        upgradeDatabase = openUpgradeDatabase();
        await upgradeDatabase.customSelect('SELECT 1').getSingle();
        await upgradeDatabase.customSelect('PRAGMA journal_mode = WAL').get();
        await _seedResearchExportOwnerRace(exportDatabase);

        var upgradeId = 0;
        final upgrade = UpgradeGuestOwner(
          DriftOwnerUpgradeRepository(
            upgradeDatabase,
            nowUtc: () => DateTime.utc(2026, 8, 11, 12),
            generateConflictId: () => 'export-race-${upgradeId++}',
            generateOwnerId: () => 'unexpected-upgrade-owner',
            generateOwnerOperationToken: () => 'export-race-owner-operation',
            deleteOwnerSecrets: (_) async {},
          ),
        );
        OwnerUpgradeResult? interleavedUpgrade;
        SqliteException? serializedUpgrade;
        consentReadInterceptor.afterFirstConsentRead = () async {
          try {
            interleavedUpgrade = await upgrade(
              activeOwnerId: 'owner-a',
              firebaseUid: 'firebase-b',
            );
          } on SqliteException catch (error) {
            if (error.resultCode != 5) rethrow;
            serializedUpgrade = error;
          }
        };
        final raceStore = _MemoryStore();
        final raceExports = ExportUseCases(
          reader: DriftExportReader(exportDatabase),
          store: raceStore,
          nowUtc: () => DateTime.utc(2026, 8, 11, 12),
          loadThaiFont: () =>
              rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
        );
        const selection = ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        );

        final artifact = await raceExports.prepare(
          format: ExportFormat.researchJson,
          selection: selection,
          cancellation: ExportCancellation(),
        );
        final payload =
            jsonDecode(utf8.decode(artifact.bytes)) as Map<String, dynamic>;
        final spellings = (payload['vocabulary'] as List<dynamic>)
            .map((row) => (row as Map<String, dynamic>)['spelling'] as String)
            .toList(growable: false);
        expect(spellings, const ['source-only']);
        expect(consentReadInterceptor.didInterleave, isTrue);

        final completedUpgrade =
            interleavedUpgrade ??
            await upgrade(activeOwnerId: 'owner-a', firebaseUid: 'firebase-b');
        if (interleavedUpgrade == null) {
          expect(serializedUpgrade?.resultCode, 5);
        }
        expect(completedUpgrade.mode, OwnerUpgradeMode.mergedExisting);
        expect(completedUpgrade.targetOwnerId, 'owner-b');

        final denialStore = _MemoryStore();
        final postUpgradeExports = ExportUseCases(
          reader: DriftExportReader(exportDatabase),
          store: denialStore,
          nowUtc: () => DateTime.utc(2026, 8, 11, 12),
          loadThaiFont: () =>
              rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
        );
        await expectLater(
          postUpgradeExports.export(
            format: ExportFormat.researchJson,
            selection: selection,
            cancellation: ExportCancellation(),
          ),
          throwsA(
            isA<ExportException>().having(
              (error) => error.code,
              'code',
              ExportFailureCode.consentRequired,
            ),
          ),
        );
        expect(denialStore.bytesWritten, 0);
      } finally {
        await exportDatabase?.close();
        await upgradeDatabase?.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test('Anki exports only real vocabulary and stable evidence id', () async {
    final artifact = await exports.prepare(
      format: ExportFormat.anki,
      selection: const ExportSelection(
        includeVocabulary: true,
        includeAttempts: false,
        includeReading: false,
      ),
      cancellation: ExportCancellation(),
    );
    final text = utf8.decode(artifact.bytes);
    expect(text, contains('station\tสถานี\tTravel\tword-1'));
    expect(text, isNot(contains('perseverance')));
  });

  test('PDF has a valid signature and real sample size', () async {
    final artifact = await exports.prepare(
      format: ExportFormat.pdf,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    expect(ascii.decode(artifact.bytes.take(4).toList()), '%PDF');
    expect(artifact.recordCount, 3);
  });

  test(
    'no data, empty selection, cancellation, and write failure are typed',
    () async {
      await expectLater(
        exports.prepare(
          format: ExportFormat.csv,
          selection: const ExportSelection(
            includeVocabulary: false,
            includeAttempts: false,
            includeReading: false,
          ),
          cancellation: ExportCancellation(),
        ),
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.noSelection,
          ),
        ),
      );
      final cancellation = ExportCancellation()..cancel();
      await expectLater(
        exports.prepare(
          format: ExportFormat.csv,
          selection: _all,
          cancellation: cancellation,
        ),
        throwsA(isA<ExportException>()),
      );
      store.failure = const ExportException(ExportFailureCode.writeFailed);
      await expectLater(
        exports.export(
          format: ExportFormat.csv,
          selection: _all,
          cancellation: ExportCancellation(),
        ),
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.writeFailed,
          ),
        ),
      );
    },
  );
}

const _all = ExportSelection(
  includeVocabulary: true,
  includeAttempts: true,
  includeReading: true,
);

final class _MemoryStore implements ExportArtifactStore {
  ExportException? failure;
  int bytesWritten = 0;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
  }) async {
    if (failure case final error?) throw error;
    cancellation.throwIfCancelled();
    bytesWritten += artifact.bytes.length;
    return ExportSaveResult(
      path: artifact.suggestedFileName,
      bytesWritten: artifact.bytes.length,
    );
  }
}

final class _ConsentReadInterceptor extends QueryInterceptor {
  Future<void> Function()? afterFirstConsentRead;
  bool _didInterleave = false;

  bool get didInterleave => _didInterleave;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (!_didInterleave && statement.contains('research_consents')) {
      _didInterleave = true;
      await afterFirstConsentRead?.call();
    }
    return rows;
  }
}

Future<void> _seedResearchExportOwnerRace(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('owner-a', NULL, 'localGuest', 1, 1), "
    "('owner-b', 'firebase-b', 'firebaseBound', 2, 0)",
  );
  await database.customInsert(
    "INSERT INTO research_consents VALUES "
    "('consent-a', 'owner-a', 1, 'accepted', 100, NULL), "
    "('consent-b', 'owner-b', 1, 'withdrawn', 200, 200)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES '
    "('category-a', 'owner-a', 'Source', 'source', 1, 1), "
    "('category-b', 'owner-b', 'Target', 'target', 2, 2)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES '
    "('word-a', 'owner-a', 'category-a', 'source-only', 'source-only', "
    "'source', 'source', 'noun', 1, 1), "
    "('word-b', 'owner-b', 'category-b', 'target-private', "
    "'target-private', 'target', 'target', 'noun', 2, 2)",
  );
}

Future<void> _seed(AppDatabase database) async {
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('category-1', 'local:owner', 'Travel', 'travel', 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_words "
    "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
    "normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('word-1', 'local:owner', 'category-1', 'station', 'station', "
    "'สถานี', 'สถานี', 'noun', 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions "
    "(id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) "
    "VALUES ('session-1', 'local:owner', 'quiz', 'completed', 1, '1', 'test')",
  );
  await database.customInsert(
    "INSERT INTO answer_attempts "
    "(id, owner_id, session_id, word_id, prompt_mode, is_correct, "
    "response_time_ms, attempt_number, occurred_at_utc_ms) "
    "VALUES ('attempt-1', 'local:owner', 'session-1', 'word-1', "
    "'meaningChoice', 1, 900, 1, 2)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries "
    "(id, owner_id, document_id, document_revision, last_position, "
    "is_completed, updated_at_utc_ms) "
    "VALUES ('reading-1', 'local:owner', 'doc-1', 1, 5, 0, 3)",
  );
}
