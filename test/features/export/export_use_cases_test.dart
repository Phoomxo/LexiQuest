import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late _MemoryStore store;
  late ExportUseCases exports;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = _MemoryStore();
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    await owners.getOrCreateActiveOwner();
    exports = ExportUseCases(
      owners: owners,
      reader: DriftExportReader(database),
      store: store,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
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

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
  }) async {
    if (failure case final error?) throw error;
    cancellation.throwIfCancelled();
    return ExportSaveResult(
      path: artifact.suggestedFileName,
      bytesWritten: artifact.bytes.length,
    );
  }
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
