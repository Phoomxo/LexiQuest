import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';

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
    final consent = ResearchConsentUseCases(
      owners: owners,
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    await consent.accept();
    exports = ExportUseCases(
      owners: owners,
      reader: DriftExportReader(database),
      store: store,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: consent,
      researchAuthorizer: const _AllowResearchOperationAuthorizer(),
    );
    await _seed(database);
  });

  tearDown(() => database.close());

  test(
    'scoped Study transport disables the legacy owner-wide Research payload',
    () async {
      final scoped = ExportUseCases(
        owners: exports.owners,
        reader: exports.reader,
        store: store,
        nowUtc: exports.nowUtc,
        loadThaiFont: exports.loadThaiFont,
        researchConsent: exports.researchConsent,
        researchAuthorizer: exports.researchAuthorizer,
        ownerWideResearchEnabled: false,
      );
      const selection = ExportSelection(
        includeVocabulary: true,
        includeAttempts: true,
        includeReading: false,
      );
      await expectLater(
        scoped.prepare(
          format: ExportFormat.researchJson,
          selection: selection,
          cancellation: ExportCancellation(),
        ),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.unavailable,
          ),
        ),
      );
      expect(
        (await scoped.prepare(
          format: ExportFormat.csv,
          selection: selection,
          cancellation: ExportCancellation(),
        )).bytes,
        isNotEmpty,
      );
    },
  );

  test('personal time export is an explicit opt-in independent selection', () {
    const selection = ExportSelection(
      includeVocabulary: false,
      includeAttempts: false,
      includeReading: false,
      includeLearningTime: true,
    );
    expect(selection.isEmpty, isFalse);
    expect(_all.includeLearningTime, isFalse);
  });

  test('time export cannot enter Research JSON or Anki', () async {
    for (final format in [ExportFormat.researchJson, ExportFormat.anki]) {
      await expectLater(
        exports.prepare(
          format: format,
          selection: const ExportSelection(
            includeVocabulary: true,
            includeAttempts: false,
            includeReading: false,
            includeLearningTime: true,
          ),
          cancellation: ExportCancellation(),
        ),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.unavailable,
          ),
        ),
      );
    }
    expect(store.saved, isNull);
  });

  test(
    'personal time CSV preserves microseconds and distinct time records',
    () async {
      final reader = _FixedExportReader(
        const ExportDataSet(
          vocabulary: [],
          attempts: [],
          reading: [],
          learningTime: [
            ExportLearningTimeRow(
              recordType: 'learning_time_preference',
              id: 'synthetic-owner',
              detail: {'enabled': 0, 'revision': 2},
            ),
            ExportLearningTimeRow(
              recordType: 'learning_time_scope',
              id: 'time-scope:synthetic-export',
              detail: {'source_kind': 'reading', 'linked_session_id': null},
            ),
            ExportLearningTimeRow(
              recordType: 'learning_time_segment',
              id: 'time-segment:synthetic-export',
              detail: {
                'scope_id': 'time-scope:synthetic-export',
                'active_duration_us': 1234567,
                'capture_policy_revision': 'confirmed-interaction-v1',
              },
            ),
          ],
        ),
      );
      final scoped = ExportUseCases(
        owners: exports.owners,
        reader: reader,
        store: store,
        nowUtc: exports.nowUtc,
        loadThaiFont: exports.loadThaiFont,
        researchConsent: exports.researchConsent,
      );
      final artifact = await scoped.prepare(
        format: ExportFormat.csv,
        selection: const ExportSelection(
          includeVocabulary: false,
          includeAttempts: false,
          includeReading: false,
          includeLearningTime: true,
        ),
        cancellation: ExportCancellation(),
      );
      final text = utf8.decode(artifact.bytes);
      expect(artifact.schemaVersion, 3);
      expect(artifact.recordCount, 3);
      expect(text, contains('"learning_time_preference","synthetic-owner"'));
      expect(
        text,
        contains('"learning_time_scope","time-scope:synthetic-export"'),
      );
      expect(
        text,
        contains('"learning_time_segment","time-segment:synthetic-export"'),
      );
      expect(text, contains('""active_duration_us"":1234567'));
      expect(text, contains('""linked_session_id"":null'));
      expect(text, contains('""enabled"":0'));
      expect(text, contains('confirmed-interaction-v1'));
      expect(text, isNot(contains('response_time_ms=1234567')));
    },
  );

  test(
    'real personal time reader preserves all19 stored fields and isolates two owners',
    () async {
      final expected = await _seedPersonalTimeExportPair(database);
      expect(database.schemaVersion, 25);
      expect(database.allTables, hasLength(45));
      final before = await _personalTimeExportSnapshot(database);
      final data = await DriftExportReader(database).load(
        ownerId: 'local:owner',
        vocabulary: false,
        attempts: false,
        reading: false,
        learningTime: true,
      );
      expect(data.recordCount, 3);
      expect(data.learningTime.map((row) => row.recordType).toList(), [
        'learning_time_preference',
        'learning_time_scope',
        'learning_time_segment',
      ]);
      expect(data.learningTime.map((row) => row.id).toList(), [
        'local:owner',
        'time-scope:synthetic-personal-export-a',
        'time-segment:synthetic-personal-export-a-0',
      ]);
      final detail = {
        for (final row in data.learningTime) row.recordType: row.detail,
      };
      expect(
        detail['learning_time_preference'],
        expected['learning_time_preferences'],
      );
      expect(detail['learning_time_scope'], expected['learning_time_scopes']);
      expect(
        detail['learning_time_segment'],
        expected['learning_time_segments'],
      );
      expect(detail['learning_time_preference'], hasLength(4));
      expect(detail['learning_time_scope'], hasLength(7));
      expect(detail['learning_time_segment'], hasLength(8));
      expect(detail.values.fold(0, (sum, row) => sum + row.length), 19);
      expect(detail['learning_time_preference']!['enabled'], 0);
      expect(detail['learning_time_segment']!['active_duration_us'], 1);
      expect(detail['learning_time_segment']!['owner_id'], isNull);
      final foreign = await DriftExportReader(database).load(
        ownerId: 'synthetic-personal-export-owner-b',
        vocabulary: false,
        attempts: false,
        reading: false,
        learningTime: true,
      );
      expect(foreign.recordCount, 3);
      expect(
        foreign.learningTime.last.id,
        'time-segment:synthetic-personal-export-b-0',
      );
      expect(foreign.learningTime.last.detail['active_duration_us'], 9876543);
      expect(
        jsonEncode(detail),
        isNot(contains('synthetic-personal-export-b')),
      );
      expect(jsonEncode(detail), isNot(contains('9876543')));
      expect(await _personalTimeExportSnapshot(database), before);
    },
  );

  test(
    'real time CSV has exact8 columns and metadata while default selection remains three ordinary records',
    () async {
      final expected = await _seedPersonalTimeExportPair(database);
      final before = await _personalTimeExportSnapshot(database);
      const selected = ExportSelection(
        includeVocabulary: false,
        includeAttempts: false,
        includeReading: false,
        includeLearningTime: true,
      );
      final artifact = await exports.prepare(
        format: ExportFormat.csv,
        selection: selected,
        cancellation: ExportCancellation(),
      );
      expect(artifact.schemaVersion, 3);
      expect(artifact.algorithmVersion, 1);
      expect(artifact.recordCount, 3);
      expect(artifact.timeZone, 'UTC');
      expect(artifact.generatedAtUtc, DateTime.utc(2026, 7, 30, 12));
      expect(artifact.bytes.take(3), [0xef, 0xbb, 0xbf]);
      final lines = const LineSplitter().convert(utf8.decode(artifact.bytes));
      expect(lines, hasLength(7));
      expect(lines[0], '# LexiQuest export schema=3 algorithm=1 timezone=UTC');
      expect(
        lines[1],
        '# generated_at=${artifact.generatedAtUtc.toIso8601String()}',
      );
      expect(lines[2], '# sample_size=3');
      expect(lines[3].split(','), [
        'record_type',
        'evidence_id',
        'subject',
        'prompt_mode',
        'is_correct',
        'response_time_ms',
        'occurred_at_utc',
        'detail',
      ]);
      final parsed = lines.skip(4).map(_personalTimeCsvCells).toList();
      final detail = <String, Map<String, Object?>>{};
      for (final cells in parsed) {
        expect(cells, hasLength(8));
        expect(cells.sublist(2, 7), everyElement(''));
        detail[cells[0]] = (jsonDecode(cells[7]) as Map)
            .cast<String, Object?>();
      }
      expect(detail, {
        'learning_time_preference': expected['learning_time_preferences'],
        'learning_time_scope': expected['learning_time_scopes'],
        'learning_time_segment': expected['learning_time_segments'],
      });
      expect(detail['learning_time_segment']!['active_duration_us'], 1);
      final text = utf8.decode(artifact.bytes);
      expect(text, isNot(contains('synthetic-personal-export-owner-b')));
      expect(
        text,
        isNot(contains('time-segment:synthetic-personal-export-b-0')),
      );
      expect(text, isNot(contains('9876543')));
      final ordinary = await exports.prepare(
        format: ExportFormat.csv,
        selection: _all,
        cancellation: ExportCancellation(),
      );
      expect(_all.includeLearningTime, isFalse);
      expect(ordinary.schemaVersion, 1);
      expect(ordinary.recordCount, 3);
      expect(utf8.decode(ordinary.bytes), isNot(contains('learning_time_')));
      final combined = await exports.prepare(
        format: ExportFormat.csv,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: true,
          includeReading: true,
          includeLearningTime: true,
        ),
        cancellation: ExportCancellation(),
      );
      expect(combined.schemaVersion, 3);
      expect(combined.recordCount, 6);
      expect(await _personalTimeExportSnapshot(database), before);
    },
  );

  test(
    'real disabled-owner time history renders and saves a personal PDF without Research consent',
    () async {
      await _seedPersonalTimeExportPair(database);
      await exports.researchConsent.withdraw();
      final before = await _personalTimeExportSnapshot(database);
      final saved = await exports.export(
        format: ExportFormat.pdf,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: true,
          includeReading: true,
          includeLearningTime: true,
        ),
        cancellation: ExportCancellation(),
      );
      final artifact = store.saved;
      expect(artifact, isNotNull);
      expect(artifact!.format, ExportFormat.pdf);
      expect(artifact.mimeType, 'application/pdf');
      expect(artifact.schemaVersion, 3);
      expect(artifact.algorithmVersion, 1);
      expect(artifact.recordCount, 6);
      expect(ascii.decode(artifact.bytes.take(4).toList()), '%PDF');
      expect(saved.bytesWritten, artifact.bytes.length);
      expect(await _personalTimeExportSnapshot(database), before);
    },
  );

  test(
    'personal reward CSV explicitly opts in to the shared effective ledger',
    () async {
      await database.customInsert(
        "INSERT INTO points_ledger_entries VALUES ('legacy-export', 'local:owner', 'legacy-export', 'learning', 199, NULL, 1)",
      );
      for (final id in ['buy-1', 'buy-2']) {
        await database.customInsert(
          "INSERT INTO reward_transactions VALUES ('$id', 'local:owner', '$id', 'purchase', -80, 'theme_ocean', 1, NULL, 2)",
        );
      }
      final artifact = await exports.prepare(
        format: ExportFormat.csv,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
          includeRewards: true,
        ),
        cancellation: ExportCancellation(),
      );
      final text = utf8.decode(artifact.bytes);
      expect(text, contains('coin_balance=120'));
      expect(text, contains('effectiveAmount'));
      expect(text, contains('duplicate'));
      expect(text, contains('creditLegacyCarryV1'));
      expect(text, contains('localOnly'));
      expect(text, contains('sourceEventId'));
      expect(text, contains('""itemId"":""theme_ocean""'));
      expect(text, contains('""occurredAtUtcMs"":2'));
      expect(artifact.schemaVersion, 2);
      final ordinary = await exports.prepare(
        format: ExportFormat.csv,
        selection: _all,
        cancellation: ExportCancellation(),
      );
      expect(ordinary.recordCount, 3);
      expect(utf8.decode(ordinary.bytes), isNot(contains('coin_balance')));
    },
  );

  test('reward opt-in is rejected for research JSON', () async {
    await expectLater(
      exports.prepare(
        format: ExportFormat.researchJson,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
          includeRewards: true,
        ),
        cancellation: ExportCancellation(),
      ),
      throwsA(
        isA<ExportException>().having(
          (e) => e.code,
          'code',
          ExportFailureCode.unavailable,
        ),
      ),
    );
  });

  test(
    'research JSON stays unavailable when consent is the only authority',
    () async {
      final reader = _FixedExportReader(_oneWordData);
      final deniedStore = _MemoryStore();
      final consentOnlyExports = ExportUseCases(
        owners: exports.owners,
        reader: reader,
        store: deniedStore,
        nowUtc: exports.nowUtc,
        loadThaiFont: exports.loadThaiFont,
        researchConsent: exports.researchConsent,
      );

      Object? failure;
      try {
        await consentOnlyExports.export(
          format: ExportFormat.researchJson,
          selection: const ExportSelection(
            includeVocabulary: true,
            includeAttempts: false,
            includeReading: false,
          ),
          cancellation: ExportCancellation(),
        );
      } catch (error) {
        failure = error;
      }

      expect(
        failure,
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.unavailable,
        ),
      );
      expect(failure.toString(), isNot(contains('local:owner')));
      expect(reader.ownerIds, isEmpty);
      expect(deniedStore.saved, isNull);
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test('research authority failure is typed without leaking details', () async {
    const privateDetail = 'private-authority-sentinel';
    final reader = _FixedExportReader(_oneWordData);
    final deniedStore = _MemoryStore();
    final authorizer = _MutableResearchOperationAuthorizer()
      ..failure = StateError(privateDetail);
    final guardedExports = ExportUseCases(
      owners: exports.owners,
      reader: reader,
      store: deniedStore,
      nowUtc: exports.nowUtc,
      loadThaiFont: exports.loadThaiFont,
      researchConsent: exports.researchConsent,
      researchAuthorizer: authorizer,
    );

    Object? failure;
    try {
      await guardedExports.export(
        format: ExportFormat.researchJson,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
    } catch (error) {
      failure = error;
    }

    expect(
      failure,
      isA<ExportException>().having(
        (error) => error.code,
        'code',
        ExportFailureCode.unavailable,
      ),
    );
    expect(failure.toString(), isNot(contains(privateDetail)));
    expect(failure.toString(), isNot(contains('local:owner')));
    expect(reader.ownerIds, isEmpty);
    expect(deniedStore.saved, isNull);
  });

  test(
    'missing signed permit creates no research read write event or outbox',
    () async {
      final reader = _FixedExportReader(_oneWordData);
      final deniedStore = _MemoryStore();
      final researchRowsBefore = await database
          .select(database.researchConsents)
          .get();
      final guardedExports = ExportUseCases(
        owners: exports.owners,
        reader: reader,
        store: deniedStore,
        nowUtc: exports.nowUtc,
        loadThaiFont: exports.loadThaiFont,
        researchConsent: exports.researchConsent,
        researchAuthorizer: _signedAuthorizer(
          permitSource: _SyntheticPermitSource(null),
        ),
      );

      await expectLater(
        guardedExports.export(
          format: ExportFormat.researchJson,
          selection: const ExportSelection(
            includeVocabulary: true,
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
      expect(reader.ownerIds, isEmpty);
      expect(deniedStore.saved, isNull);
      expect(
        await database.select(database.researchConsents).get(),
        hasLength(researchRowsBefore.length),
      );
      expect(await database.select(database.eventsV2).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'reward-only personal export is owner-scoped and supports PDF without research consent',
    () async {
      await database.customInsert(
        "INSERT INTO local_owners (id, created_at_utc_ms) VALUES ('other', 1)",
      );
      await database.customInsert(
        "INSERT INTO points_ledger_entries VALUES ('foreign-secret', 'other', 'foreign-secret', 'learning', 999, NULL, 1)",
      );
      await exports.researchConsent.withdraw();
      const selected = ExportSelection(
        includeVocabulary: false,
        includeAttempts: false,
        includeReading: false,
        includeRewards: true,
      );
      final csv = await exports.prepare(
        format: ExportFormat.csv,
        selection: selected,
        cancellation: ExportCancellation(),
      );
      expect(utf8.decode(csv.bytes), contains('coin_balance=1'));
      expect(utf8.decode(csv.bytes), isNot(contains('foreign-secret')));
      final pdf = await exports.prepare(
        format: ExportFormat.pdf,
        selection: selected,
        cancellation: ExportCancellation(),
      );
      expect(pdf.schemaVersion, 2);
      expect(pdf.recordCount, 1);
      expect(ascii.decode(pdf.bytes.take(4).toList()), '%PDF');
      final projection = await exports.reader.load(
        ownerId: 'local:owner',
        vocabulary: false,
        attempts: false,
        reading: false,
        rewards: true,
      );
      expect(projection.rewards!.balance, 1);
      expect(
        projection.rewards!.effects.single.entry.sourceEventId,
        'attempt-1',
      );
    },
  );

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
    expect(parsed['schemaVersion'], 2);
    expect(artifact.schemaVersion, 2);
    expect(parsed['timeZone'], 'UTC');
    expect((parsed['attempts'] as List).single['evidenceId'], 'answer-1');
  });

  ExportUseCases privateDataExports({String promptMode = 'meaningChoice'}) =>
      ExportUseCases(
        owners: exports.owners,
        reader: _FixedExportReader(_privateResearchData(promptMode)),
        store: store,
        nowUtc: exports.nowUtc,
        loadThaiFont: exports.loadThaiFont,
        researchConsent: exports.researchConsent,
        researchAuthorizer: exports.researchAuthorizer,
      );

  test('research JSON excludes private content and raw identifiers', () async {
    final artifact = await privateDataExports().prepare(
      format: ExportFormat.researchJson,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    final encoded = utf8.decode(artifact.bytes);
    final parsed = jsonDecode(encoded) as Map<String, dynamic>;

    expect(parsed['schemaVersion'], 2);
    expect(artifact.schemaVersion, parsed['schemaVersion']);
    expect(parsed['identityScope'], 'archive-local');
    expect(parsed['sampleSize'], 7);
    for (final marker in _privateResearchMarkers) {
      expect(encoded, isNot(contains(marker)), reason: marker);
    }
    final vocabulary = parsed['vocabulary'] as List<dynamic>;
    final attempts = parsed['attempts'] as List<dynamic>;
    expect(vocabulary, hasLength(2));
    expect(attempts, hasLength(3));
    expect((vocabulary.first as Map).keys, unorderedEquals(['evidenceId']));
    expect(
      (attempts.first as Map).keys,
      unorderedEquals([
        'evidenceId',
        'sessionId',
        'wordId',
        'promptMode',
        'isCorrect',
        'responseTimeMs',
        'occurredAtUtc',
      ]),
    );
    expect(attempts.first['isCorrect'], isTrue);
    expect(attempts.first['responseTimeMs'], 900);
    expect(attempts[1]['responseTimeMs'], isNull);
    expect(attempts.first['promptMode'], 'meaningChoice');
  });

  test(
    'research archive aliases retain word session and document links',
    () async {
      final artifact = await privateDataExports().prepare(
        format: ExportFormat.researchJson,
        selection: _all,
        cancellation: ExportCancellation(),
      );
      final parsed =
          jsonDecode(utf8.decode(artifact.bytes)) as Map<String, dynamic>;
      final words = parsed['vocabulary'] as List<dynamic>;
      final attempts = parsed['attempts'] as List<dynamic>;
      final reading = parsed['reading'] as List<dynamic>;

      expect(attempts[0]['wordId'], words[0]['evidenceId']);
      expect(attempts[1]['wordId'], words[0]['evidenceId']);
      expect(attempts[2]['wordId'], words[1]['evidenceId']);
      expect(attempts[0]['sessionId'], attempts[1]['sessionId']);
      expect(attempts[2]['sessionId'], isNot(attempts[0]['sessionId']));
      expect(attempts.map((row) => row['evidenceId']).toSet(), hasLength(3));
      expect(reading[0]['documentId'], reading[1]['documentId']);
      expect(reading[0]['documentRevision'], 1);
      expect(reading[1]['documentRevision'], 2);
    },
  );

  test(
    'research JSON does not export an unrecognised free-text prompt mode',
    () async {
      final artifact =
          await privateDataExports(
            promptMode: 'private-prompt-mode@example.invalid',
          ).prepare(
            format: ExportFormat.researchJson,
            selection: _all,
            cancellation: ExportCancellation(),
          );
      final encoded = utf8.decode(artifact.bytes);
      final parsed = jsonDecode(encoded) as Map<String, dynamic>;
      expect(encoded, isNot(contains('private-prompt-mode@example.invalid')));
      expect((parsed['attempts'] as List).first['promptMode'], isNull);
      expect((parsed['attempts'] as List).first['responseTimeMs'], 900);
    },
  );

  for (final format in [ExportFormat.csv, ExportFormat.anki]) {
    test(
      'personal ${format.name} retains the requested word content',
      () async {
        final artifact = await privateDataExports().prepare(
          format: format,
          selection: _all,
          cancellation: ExportCancellation(),
        );
        final encoded = utf8.decode(artifact.bytes);
        expect(encoded, contains('learner@example.invalid'));
        expect(encoded, contains('guardian-private-response-canary'));
        expect(artifact.schemaVersion, 1);
      },
    );
  }

  test('research JSON includes owner A data and excludes owner B', () async {
    await _seedOwnerWord(database, ownerId: 'owner-a', spelling: 'alpha');
    await _seedOwnerWord(database, ownerId: 'owner-b', spelling: 'bravo');
    await database.customInsert(
      'INSERT INTO vocabulary_words '
      '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
      'normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) '
      "VALUES ('word-owner-b-extra', 'owner-b', 'category-owner-b', 'charlie', "
      "'charlie', 'charlie', 'charlie', 'noun', 1, 1)",
    );
    final owners = _MutableOwners(_owner('owner-a'));
    final ownerScopedExports = ExportUseCases(
      owners: owners,
      reader: DriftExportReader(database),
      store: store,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: const _OwnerConsentRepository(
          acceptedOwnerIds: {'owner-a'},
        ),
        nowUtc: () => DateTime.utc(2026, 7, 30),
      ),
      researchAuthorizer: const _AllowResearchOperationAuthorizer(),
    );

    final artifact = await ownerScopedExports.prepare(
      format: ExportFormat.researchJson,
      selection: const ExportSelection(
        includeVocabulary: true,
        includeAttempts: false,
        includeReading: false,
      ),
      cancellation: ExportCancellation(),
    );
    final encoded = utf8.decode(artifact.bytes);
    final parsed = jsonDecode(encoded) as Map<String, dynamic>;
    final vocabulary = parsed['vocabulary'] as List<dynamic>;

    expect(vocabulary, hasLength(1));
    expect(
      (vocabulary.single as Map<String, dynamic>).keys,
      unorderedEquals(['evidenceId']),
    );
    expect(encoded, isNot(contains('alpha')));
    expect(encoded, isNot(contains('bravo')));
    expect(encoded, isNot(contains('word-owner-b')));
  });

  for (final bAccepted in [true, false]) {
    test('research prepare rejects owner B after consent from A '
        '(${bAccepted ? 'accepted' : 'never-participant'} B)', () async {
      await _seedOwnerWord(database, ownerId: 'owner-a', spelling: 'alpha');
      await _seedOwnerWord(database, ownerId: 'owner-b', spelling: 'bravo');
      final owners = _ScriptedOwners([
        _owner('owner-a'),
        _owner('owner-a'),
        _owner('owner-b'),
        _owner('owner-b'),
      ]);
      final consent = ResearchConsentUseCases(
        owners: owners,
        repository: _OwnerConsentRepository(
          acceptedOwnerIds: {'owner-a', if (bAccepted) 'owner-b'},
        ),
        nowUtc: () => DateTime.utc(2026, 7, 30),
      );
      final ownerPinnedExports = ExportUseCases(
        owners: owners,
        reader: DriftExportReader(database),
        store: store,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        loadThaiFont: () =>
            rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
        researchConsent: consent,
        researchAuthorizer: const _AllowResearchOperationAuthorizer(),
      );

      await expectLater(
        ownerPinnedExports.prepare(
          format: ExportFormat.researchJson,
          selection: const ExportSelection(
            includeVocabulary: true,
            includeAttempts: false,
            includeReading: false,
          ),
          cancellation: ExportCancellation(),
        ),
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
    });
  }

  test(
    'owner switch during delayed data read never reaches the store',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final consent = ResearchConsentUseCases(
        owners: owners,
        repository: const _OwnerConsentRepository(
          acceptedOwnerIds: {'owner-a', 'owner-b'},
        ),
        nowUtc: () => DateTime.utc(2026, 7, 30),
      );
      final reader = _DelayedExportReader();
      final delayedStore = _MemoryStore();
      final ownerPinnedExports = ExportUseCases(
        owners: owners,
        reader: reader,
        store: delayedStore,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        loadThaiFont: () =>
            rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
        researchConsent: consent,
        researchAuthorizer: const _AllowResearchOperationAuthorizer(),
      );

      final pending = ownerPinnedExports.export(
        format: ExportFormat.researchJson,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      await reader.started.future;
      expect(reader.ownerIds, ['owner-a']);
      owners.current = _owner('owner-b');
      reader.result.complete(_oneWordData);

      await expectLater(
        pending,
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(delayedStore.saved, isNull);
    },
  );

  test('withdrawal during delayed data read never reaches the store', () async {
    final owners = _MutableOwners(_owner('owner-a'));
    final consentRepository = _OwnerConsentRepository(
      acceptedOwnerIds: {'owner-a'},
    );
    final reader = _DelayedExportReader();
    final delayedStore = _MemoryStore();
    final ownerPinnedExports = ExportUseCases(
      owners: owners,
      reader: reader,
      store: delayedStore,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: consentRepository,
        nowUtc: () => DateTime.utc(2026, 7, 30),
      ),
      researchAuthorizer: const _AllowResearchOperationAuthorizer(),
    );

    final pending = ownerPinnedExports.export(
      format: ExportFormat.researchJson,
      selection: const ExportSelection(
        includeVocabulary: true,
        includeAttempts: false,
        includeReading: false,
      ),
      cancellation: ExportCancellation(),
    );
    await reader.started.future;
    consentRepository.acceptedOwnerIds.remove('owner-a');
    reader.result.complete(_oneWordData);

    await expectLater(
      pending,
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.consentRequired,
        ),
      ),
    );
    expect(reader.ownerIds, ['owner-a']);
    expect(delayedStore.saved, isNull);
  });

  test(
    'cancellation during delayed data read never reaches the store',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final reader = _DelayedExportReader();
      final delayedStore = _MemoryStore();
      final cancellation = ExportCancellation();
      final ownerPinnedExports = ExportUseCases(
        owners: owners,
        reader: reader,
        store: delayedStore,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        loadThaiFont: () =>
            rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
        researchConsent: ResearchConsentUseCases(
          owners: owners,
          repository: const _OwnerConsentRepository(
            acceptedOwnerIds: {'owner-a'},
          ),
          nowUtc: () => DateTime.utc(2026, 7, 30),
        ),
        researchAuthorizer: const _AllowResearchOperationAuthorizer(),
      );

      final pending = ownerPinnedExports.export(
        format: ExportFormat.researchJson,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: cancellation,
      );
      await reader.started.future;
      cancellation.cancel();
      reader.result.complete(_oneWordData);

      await expectLater(
        pending,
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(delayedStore.saved, isNull);
    },
  );

  test(
    'owner switch during delayed consent load is typed and reads no data',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final consentRepository = _DelayedConsentRepository();
      final reader = _FixedExportReader(_oneWordData);
      final ownerPinnedExports = ExportUseCases(
        owners: owners,
        reader: reader,
        store: store,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        loadThaiFont: () =>
            rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
        researchConsent: ResearchConsentUseCases(
          owners: owners,
          repository: consentRepository,
          nowUtc: () => DateTime.utc(2026, 7, 30),
        ),
        researchAuthorizer: const _AllowResearchOperationAuthorizer(),
      );

      final pending = ownerPinnedExports.prepare(
        format: ExportFormat.researchJson,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      await consentRepository.started.future;
      owners.current = _owner('owner-b');
      consentRepository.result.complete(
        const ResearchConsentStatus(
          ownerId: 'owner-a',
          version: 1,
          accepted: true,
        ),
      );

      await expectLater(
        pending,
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(reader.ownerIds, isEmpty);
    },
  );

  test('cancellation during delayed consent load reads no data', () async {
    final owners = _MutableOwners(_owner('owner-a'));
    final consentRepository = _DelayedConsentRepository();
    final reader = _FixedExportReader(_oneWordData);
    final cancellation = ExportCancellation();
    final ownerPinnedExports = ExportUseCases(
      owners: owners,
      reader: reader,
      store: store,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: consentRepository,
        nowUtc: () => DateTime.utc(2026, 7, 30),
      ),
      researchAuthorizer: const _AllowResearchOperationAuthorizer(),
    );

    final pending = ownerPinnedExports.prepare(
      format: ExportFormat.researchJson,
      selection: const ExportSelection(
        includeVocabulary: true,
        includeAttempts: false,
        includeReading: false,
      ),
      cancellation: cancellation,
    );
    await consentRepository.started.future;
    cancellation.cancel();
    consentRepository.result.complete(
      const ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: false,
      ),
    );

    await expectLater(
      pending,
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.cancelled,
        ),
      ),
    );
    expect(reader.ownerIds, isEmpty);
  });

  test(
    'research consent read failure is unavailable and reads no data',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final reader = _FixedExportReader(_oneWordData);
      final ownerPinnedExports = ExportUseCases(
        owners: owners,
        reader: reader,
        store: store,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        loadThaiFont: () =>
            rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
        researchConsent: ResearchConsentUseCases(
          owners: owners,
          repository: const _FailingConsentRepository(),
          nowUtc: () => DateTime.utc(2026, 7, 30),
        ),
        researchAuthorizer: const _AllowResearchOperationAuthorizer(),
      );

      await expectLater(
        ownerPinnedExports.prepare(
          format: ExportFormat.researchJson,
          selection: const ExportSelection(
            includeVocabulary: true,
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
      expect(reader.ownerIds, isEmpty);
    },
  );

  test('export data read failure is typed unavailable', () async {
    final owners = _MutableOwners(_owner('owner-a'));
    final ownerPinnedExports = ExportUseCases(
      owners: owners,
      reader: const _FailingExportReader(),
      store: store,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: const _FailingConsentRepository(),
        nowUtc: () => DateTime.utc(2026, 7, 30),
      ),
    );

    await expectLater(
      ownerPinnedExports.prepare(
        format: ExportFormat.csv,
        selection: const ExportSelection(
          includeVocabulary: true,
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
  });

  test('personal owner read failure is typed unavailable', () async {
    final reader = _FixedExportReader(_oneWordData);
    const owners = _FailingOwners();
    final ownerPinnedExports = ExportUseCases(
      owners: owners,
      reader: reader,
      store: store,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: const _FailingConsentRepository(),
        nowUtc: () => DateTime.utc(2026, 7, 30),
      ),
    );

    await expectLater(
      ownerPinnedExports.prepare(
        format: ExportFormat.csv,
        selection: const ExportSelection(
          includeVocabulary: true,
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
    expect(reader.ownerIds, isEmpty);
  });

  test(
    'research withdrawal while save destination is open blocks write',
    () async {
      final delayedStore = _DelayedStore();
      final guardedExports = ExportUseCases(
        owners: exports.owners,
        reader: exports.reader,
        store: delayedStore,
        nowUtc: exports.nowUtc,
        loadThaiFont: exports.loadThaiFont,
        researchConsent: exports.researchConsent,
        researchAuthorizer: const _AllowResearchOperationAuthorizer(),
      );

      final pending = guardedExports.export(
        format: ExportFormat.researchJson,
        selection: _all,
        cancellation: ExportCancellation(),
      );
      await delayedStore.destinationOpen.future;
      await exports.researchConsent.withdraw();
      delayedStore.destination.complete();

      await expectLater(
        pending,
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.consentRequired,
          ),
        ),
      );
      expect(delayedStore.saved, isNull);
    },
  );

  test('research authority is rechecked immediately before write', () async {
    final delayedStore = _DelayedStore();
    final authorizer = _MutableResearchOperationAuthorizer();
    final guardedExports = ExportUseCases(
      owners: exports.owners,
      reader: exports.reader,
      store: delayedStore,
      nowUtc: exports.nowUtc,
      loadThaiFont: exports.loadThaiFont,
      researchConsent: exports.researchConsent,
      researchAuthorizer: authorizer,
    );

    final pending = guardedExports.export(
      format: ExportFormat.researchJson,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    await delayedStore.destinationOpen.future;
    final checksBeforeWrite = authorizer.calls;
    authorizer.allowed = false;
    delayedStore.destination.complete();

    await expectLater(
      pending,
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.unavailable,
        ),
      ),
    );
    expect(authorizer.calls, checksBeforeWrite + 1);
    expect(delayedStore.saved, isNull);
  });

  test('signed permit revocation is rechecked before write', () async {
    final delayedStore = _DelayedStore();
    final permitSource = _SyntheticPermitSource(_syntheticPermit());
    final stateSource = _SyntheticPermitStateSource(
      const ResearchPermitState(currentRevision: 2, revoked: false),
    );
    final guardedExports = ExportUseCases(
      owners: exports.owners,
      reader: exports.reader,
      store: delayedStore,
      nowUtc: exports.nowUtc,
      loadThaiFont: exports.loadThaiFont,
      researchConsent: exports.researchConsent,
      researchAuthorizer: _signedAuthorizer(
        permitSource: permitSource,
        stateSource: stateSource,
      ),
    );

    final pending = guardedExports.export(
      format: ExportFormat.researchJson,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    await delayedStore.destinationOpen.future;
    final checksBeforeWrite = stateSource.calls;
    stateSource.state = const ResearchPermitState(
      currentRevision: 2,
      revoked: true,
    );
    delayedStore.destination.complete();

    await expectLater(
      pending,
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.unavailable,
        ),
      ),
    );
    expect(stateSource.calls, checksBeforeWrite + 1);
    expect(delayedStore.saved, isNull);
    expect(await database.select(database.eventsV2).get(), isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  test('owner switch while save destination is open blocks write', () async {
    final owners = _MutableOwners(_owner('owner-a'));
    final delayedStore = _DelayedStore();
    final ownerPinnedExports = ExportUseCases(
      owners: owners,
      reader: _FixedExportReader(_oneWordData),
      store: delayedStore,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: const _OwnerConsentRepository(
          acceptedOwnerIds: {'owner-a', 'owner-b'},
        ),
        nowUtc: () => DateTime.utc(2026, 7, 30),
      ),
      researchAuthorizer: const _AllowResearchOperationAuthorizer(),
    );

    final pending = ownerPinnedExports.export(
      format: ExportFormat.researchJson,
      selection: const ExportSelection(
        includeVocabulary: true,
        includeAttempts: false,
        includeReading: false,
      ),
      cancellation: ExportCancellation(),
    );
    await delayedStore.destinationOpen.future;
    owners.current = _owner('owner-b');
    delayedStore.destination.complete();

    await expectLater(
      pending,
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.cancelled,
        ),
      ),
    );
    expect(delayedStore.saved, isNull);
  });

  test(
    'personal owner switch while save destination is open blocks write',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final delayedStore = _DelayedStore();
      final ownerPinnedExports = ExportUseCases(
        owners: owners,
        reader: _FixedExportReader(_oneWordData),
        store: delayedStore,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        loadThaiFont: () =>
            rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
        researchConsent: ResearchConsentUseCases(
          owners: owners,
          repository: const _FailingConsentRepository(),
          nowUtc: () => DateTime.utc(2026, 7, 30),
        ),
      );

      final pending = ownerPinnedExports.export(
        format: ExportFormat.csv,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      await delayedStore.destinationOpen.future;
      owners.current = _owner('owner-b');
      delayedStore.destination.complete();

      await expectLater(
        pending,
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(delayedStore.saved, isNull);
    },
  );

  test(
    'owner switch during delayed PDF render never reaches the store',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final reader = _FixedExportReader(_oneWordData);
      final delayedStore = _MemoryStore();
      final font = _DelayedFontLoader();
      final fontData = await rootBundle.load(
        'assets/fonts/NotoSansThai-Variable.ttf',
      );
      final ownerPinnedExports = ExportUseCases(
        owners: owners,
        reader: reader,
        store: delayedStore,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        loadThaiFont: font.load,
        researchConsent: ResearchConsentUseCases(
          owners: owners,
          repository: const _FailingConsentRepository(),
          nowUtc: () => DateTime.utc(2026, 7, 30),
        ),
      );

      final pending = ownerPinnedExports.export(
        format: ExportFormat.pdf,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      await font.started.future;
      owners.current = _owner('owner-b');
      font.result.complete(fontData);

      await expectLater(
        pending,
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(delayedStore.saved, isNull);
    },
  );

  test(
    'cancellation during delayed PDF render never reaches the store',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final font = _DelayedFontLoader();
      final fontData = await rootBundle.load(
        'assets/fonts/NotoSansThai-Variable.ttf',
      );
      final delayedStore = _MemoryStore();
      final cancellation = ExportCancellation();
      final ownerPinnedExports = ExportUseCases(
        owners: owners,
        reader: _FixedExportReader(_oneWordData),
        store: delayedStore,
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        loadThaiFont: font.load,
        researchConsent: ResearchConsentUseCases(
          owners: owners,
          repository: const _FailingConsentRepository(),
          nowUtc: () => DateTime.utc(2026, 7, 30),
        ),
      );

      final pending = ownerPinnedExports.export(
        format: ExportFormat.pdf,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: cancellation,
      );
      await font.started.future;
      cancellation.cancel();
      font.result.complete(fontData);

      await expectLater(
        pending,
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(delayedStore.saved, isNull);
    },
  );

  test('delayed personal PDF still saves after research withdrawal', () async {
    await exports.researchConsent.withdraw();
    final font = _DelayedFontLoader();
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSansThai-Variable.ttf',
    );
    final delayedStore = _MemoryStore();
    final personalExports = ExportUseCases(
      owners: exports.owners,
      reader: exports.reader,
      store: delayedStore,
      nowUtc: exports.nowUtc,
      loadThaiFont: font.load,
      researchConsent: exports.researchConsent,
    );

    final pending = personalExports.export(
      format: ExportFormat.pdf,
      selection: _all,
      cancellation: ExportCancellation(),
    );
    await font.started.future;
    font.result.complete(fontData);

    final result = await pending;
    expect(result.bytesWritten, greaterThan(0));
    expect(delayedStore.saved?.format, ExportFormat.pdf);
    expect((await exports.researchConsent.load()).accepted, isFalse);
  });

  test('PDF font read failure is typed unavailable before save', () async {
    final owners = _MutableOwners(_owner('owner-a'));
    final failedStore = _MemoryStore();
    final ownerPinnedExports = ExportUseCases(
      owners: owners,
      reader: _FixedExportReader(_oneWordData),
      store: failedStore,
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      loadThaiFont: () => throw StateError('synthetic font read failure'),
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: const _FailingConsentRepository(),
        nowUtc: () => DateTime.utc(2026, 7, 30),
      ),
    );

    await expectLater(
      ownerPinnedExports.export(
        format: ExportFormat.pdf,
        selection: const ExportSelection(
          includeVocabulary: true,
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
    expect(failedStore.saved, isNull);
  });

  test('research dataset export stops after consent withdrawal', () async {
    await exports.researchConsent.withdraw();

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
    final anki = await exports.prepare(
      format: ExportFormat.anki,
      selection: const ExportSelection(
        includeVocabulary: true,
        includeAttempts: false,
        includeReading: false,
      ),
      cancellation: ExportCancellation(),
    );
    expect(anki.recordCount, 1);
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

  test(
    'research export cancels when the consent owner changes during load',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final consentRepository = _DelayedConsentRepository();
      final reader = _FixedExportReader(_oneWordData);
      final target = _MemoryStore();
      final pinned = ExportUseCases(
        owners: owners,
        reader: reader,
        store: target,
        nowUtc: exports.nowUtc,
        loadThaiFont: exports.loadThaiFont,
        researchConsent: ResearchConsentUseCases(
          owners: owners,
          repository: consentRepository,
          nowUtc: exports.nowUtc,
          version: 4,
        ),
        researchAuthorizer: const _AllowResearchOperationAuthorizer(),
      );
      final pending = pinned.export(
        format: ExportFormat.researchJson,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      await consentRepository.started.future;
      owners.current = _owner('owner-b');
      consentRepository.result.complete(
        const ResearchConsentStatus(
          ownerId: 'owner-a',
          version: 4,
          accepted: true,
        ),
      );
      await expectLater(
        pending,
        throwsA(
          isA<ExportException>()
              .having(
                (error) => error.code,
                'code',
                ExportFailureCode.cancelled,
              )
              .having(
                (error) => error.cause,
                'cause',
                isA<StateError>().having(
                  (error) => error.message,
                  'message',
                  'active owner changed while loading research consent',
                ),
              ),
        ),
      );
      expect(reader.ownerIds, isEmpty);
      expect(target.saved, isNull);
    },
  );

  test(
    'research export treats a wrong consent version as unavailable, not cancellation',
    () async {
      final owners = _MutableOwners(_owner('owner-a'));
      final consentRepository = _DelayedConsentRepository();
      final reader = _FixedExportReader(_oneWordData);
      final target = _MemoryStore();
      final pinned = ExportUseCases(
        owners: owners,
        reader: reader,
        store: target,
        nowUtc: exports.nowUtc,
        loadThaiFont: exports.loadThaiFont,
        researchConsent: ResearchConsentUseCases(
          owners: owners,
          repository: consentRepository,
          nowUtc: exports.nowUtc,
          version: 4,
        ),
        researchAuthorizer: const _AllowResearchOperationAuthorizer(),
      );
      final pending = pinned.export(
        format: ExportFormat.researchJson,
        selection: const ExportSelection(
          includeVocabulary: true,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      await consentRepository.started.future;
      consentRepository.result.complete(
        const ResearchConsentStatus(
          ownerId: 'owner-a',
          version: 1,
          accepted: true,
        ),
      );
      await expectLater(
        pending,
        throwsA(
          isA<ExportException>()
              .having(
                (error) => error.code,
                'code',
                ExportFailureCode.unavailable,
              )
              .having(
                (error) => error.cause,
                'cause',
                isA<StateError>().having(
                  (error) => error.message,
                  'message',
                  'research consent version does not match requested version',
                ),
              ),
        ),
      );
      expect(reader.ownerIds, isEmpty);
      expect(target.saved, isNull);
    },
  );
}

const _all = ExportSelection(
  includeVocabulary: true,
  includeAttempts: true,
  includeReading: true,
);

const _privateResearchMarkers = [
  'local:owner',
  'raw-word-person-alpha',
  'raw-word-person-beta',
  'raw-answer-person-alpha',
  'raw-answer-person-beta',
  'raw-answer-person-gamma',
  'raw-session-person-alpha',
  'raw-session-person-beta',
  'raw-document-person-alpha',
  'guardian@example.invalid',
  'learner@example.invalid',
  'guardian-private-response-canary',
  'private-pos-canary',
  'private-cefr-canary',
  'file:///guardian/private-source.pdf',
  'private-provider-trace-canary',
];

ExportDataSet _privateResearchData(String promptMode) => ExportDataSet(
  vocabulary: [
    for (final id in ['raw-word-person-alpha', 'raw-word-person-beta'])
      ExportVocabularyRow(
        id: id,
        category: 'guardian@example.invalid',
        spelling: 'learner@example.invalid',
        meaning: 'guardian-private-response-canary',
        partOfSpeech: 'private-pos-canary',
        cefrLevel: 'private-cefr-canary',
        source: 'file:///guardian/private-source.pdf',
      ),
  ],
  attempts: [
    ExportAttemptRow(
      id: 'raw-answer-person-alpha',
      sessionId: 'raw-session-person-alpha',
      wordId: 'raw-word-person-alpha',
      spelling: 'learner@example.invalid',
      promptMode: promptMode,
      isCorrect: true,
      responseTimeMs: 900,
      occurredAtUtc: DateTime.utc(2026, 10, 28),
      providerProvenance: 'private-provider-trace-canary',
    ),
    ExportAttemptRow(
      id: 'raw-answer-person-beta',
      sessionId: 'raw-session-person-alpha',
      wordId: 'raw-word-person-alpha',
      spelling: 'learner@example.invalid',
      promptMode: 'meaningChoice',
      isCorrect: false,
      responseTimeMs: null,
      occurredAtUtc: DateTime.utc(2026, 10, 28),
      providerProvenance: null,
    ),
    ExportAttemptRow(
      id: 'raw-answer-person-gamma',
      sessionId: 'raw-session-person-beta',
      wordId: 'raw-word-person-beta',
      spelling: 'learner@example.invalid',
      promptMode: 'srsRecall',
      isCorrect: true,
      responseTimeMs: 700,
      occurredAtUtc: DateTime.utc(2026, 10, 28),
      providerProvenance: null,
    ),
  ],
  reading: [
    for (final revision in [1, 2])
      ExportReadingRow(
        documentId: 'raw-document-person-alpha',
        documentRevision: revision,
        lastPosition: 5,
        isCompleted: revision == 2,
        updatedAtUtc: DateTime.utc(2026, 10, 28),
      ),
  ],
);

final class _MemoryStore implements ExportArtifactStore {
  ExportException? failure;
  ExportArtifact? saved;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    if (failure case final error?) throw error;
    cancellation.throwIfCancelled();
    await revalidateBeforeWrite();
    saved = artifact;
    return ExportSaveResult(
      path: artifact.suggestedFileName,
      bytesWritten: artifact.bytes.length,
    );
  }
}

final class _AllowResearchOperationAuthorizer
    implements ResearchOperationAuthorizer {
  const _AllowResearchOperationAuthorizer();

  @override
  Future<bool> authorize({
    required String ownerId,
    required ResearchOperation operation,
  }) async => true;
}

final class _MutableResearchOperationAuthorizer
    implements ResearchOperationAuthorizer {
  bool allowed = true;
  Object? failure;
  int calls = 0;

  @override
  Future<bool> authorize({
    required String ownerId,
    required ResearchOperation operation,
  }) async {
    calls++;
    if (failure case final error?) throw error;
    return allowed;
  }
}

SignedPermitResearchOperationAuthorizer _signedAuthorizer({
  required _SyntheticPermitSource permitSource,
  _SyntheticPermitStateSource? stateSource,
}) => SignedPermitResearchOperationAuthorizer(
  permits: permitSource,
  states:
      stateSource ??
      _SyntheticPermitStateSource(
        const ResearchPermitState(currentRevision: 2, revoked: false),
      ),
  verifier: const _SyntheticPermitVerifier(),
  requirements: const ResearchPermitRequirements(
    supportedFormatVersion: 1,
    trustedIssuerId: 'issuer-1',
    trustedIssuerKeyId: 'issuer-key-1',
    signatureAlgorithm: 'synthetic-signature-v1',
    assignmentId: 'assignment-1',
    assignmentRevision: 3,
    protocolId: 'protocol-1',
    protocolRevision: 5,
    instrumentId: 'instrument-1',
    instrumentRevision: 7,
  ),
  nowUtc: () => DateTime.utc(2026, 7, 30, 12),
);

ResearchPermit _syntheticPermit() => ResearchPermit(
  formatVersion: 1,
  permitId: 'permit-1',
  issuerId: 'issuer-1',
  issuerKeyId: 'issuer-key-1',
  signatureAlgorithm: 'synthetic-signature-v1',
  ownerId: 'local:owner',
  operation: ResearchOperation.export,
  assignmentId: 'assignment-1',
  assignmentRevision: 3,
  protocolId: 'protocol-1',
  protocolRevision: 5,
  instrumentId: 'instrument-1',
  instrumentRevision: 7,
  revision: 2,
  issuedAtUtc: DateTime.utc(2026, 7, 30),
  expiresAtUtc: DateTime.utc(2026, 7, 31),
  signature: const [1, 2, 3, 4],
);

final class _SyntheticPermitSource implements ResearchPermitSource {
  _SyntheticPermitSource(this.permit);

  ResearchPermit? permit;

  @override
  Future<ResearchPermit?> loadPermit({
    required String ownerId,
    required ResearchOperation operation,
  }) async => permit;
}

final class _SyntheticPermitStateSource implements ResearchPermitStateSource {
  _SyntheticPermitStateSource(this.state);

  ResearchPermitState? state;
  int calls = 0;

  @override
  Future<ResearchPermitState?> loadState({required String permitId}) async {
    calls++;
    return state;
  }
}

final class _SyntheticPermitVerifier
    implements ResearchPermitSignatureVerifier {
  const _SyntheticPermitVerifier();

  @override
  Future<bool> verify({
    required String algorithm,
    required String issuerKeyId,
    required Uint8List message,
    required Uint8List signature,
  }) async => true;
}

final class _DelayedStore implements ExportArtifactStore {
  final destinationOpen = Completer<void>();
  final destination = Completer<void>();
  ExportArtifact? saved;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    destinationOpen.complete();
    await destination.future;
    cancellation.throwIfCancelled();
    await revalidateBeforeWrite();
    cancellation.throwIfCancelled();
    saved = artifact;
    return ExportSaveResult(
      path: artifact.suggestedFileName,
      bytesWritten: artifact.bytes.length,
    );
  }
}

final class _DelayedFontLoader {
  final started = Completer<void>();
  final result = Completer<ByteData>();

  Future<ByteData> load() {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

const _oneWordData = ExportDataSet(
  vocabulary: [
    ExportVocabularyRow(
      id: 'word-a',
      category: 'category-a',
      spelling: 'alpha',
      meaning: 'alpha',
      partOfSpeech: 'noun',
      cefrLevel: null,
      source: 'manual',
    ),
  ],
  attempts: [],
  reading: [],
);

final class _DelayedExportReader implements ExportReader {
  final started = Completer<void>();
  final result = Completer<ExportDataSet>();
  final ownerIds = <String>[];

  @override
  Future<ExportDataSet> load({
    required String ownerId,
    required bool vocabulary,
    required bool attempts,
    required bool reading,
    bool rewards = false,
    bool learningTime = false,
  }) {
    ownerIds.add(ownerId);
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

final class _FixedExportReader implements ExportReader {
  _FixedExportReader(this.data);

  final ExportDataSet data;
  final ownerIds = <String>[];

  @override
  Future<ExportDataSet> load({
    required String ownerId,
    required bool vocabulary,
    required bool attempts,
    required bool reading,
    bool rewards = false,
    bool learningTime = false,
  }) async {
    ownerIds.add(ownerId);
    return data;
  }
}

final class _FailingExportReader implements ExportReader {
  const _FailingExportReader();

  @override
  Future<ExportDataSet> load({
    required String ownerId,
    required bool vocabulary,
    required bool attempts,
    required bool reading,
    bool rewards = false,
    bool learningTime = false,
  }) => throw StateError('synthetic export read failure');
}

identity.LocalOwner _owner(String id) =>
    identity.LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 7, 30));

final class _ScriptedOwners implements LocalOwnerRepository {
  _ScriptedOwners(this._owners);

  final List<identity.LocalOwner> _owners;
  var _index = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    final index = _index < _owners.length ? _index++ : _owners.length - 1;
    return _owners[index];
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}

final class _MutableOwners implements LocalOwnerRepository {
  _MutableOwners(this.current);

  identity.LocalOwner current;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async => current;

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}

final class _FailingOwners implements LocalOwnerRepository {
  const _FailingOwners();

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() =>
      throw StateError('synthetic owner storage failure');

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}

final class _OwnerConsentRepository implements ResearchConsentRepository {
  const _OwnerConsentRepository({required this.acceptedOwnerIds});

  final Set<String> acceptedOwnerIds;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async => ResearchConsentStatus(
    ownerId: ownerId,
    version: version,
    accepted: acceptedOwnerIds.contains(ownerId),
  );

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) => throw UnimplementedError();
}

final class _DelayedConsentRepository implements ResearchConsentRepository {
  final started = Completer<void>();
  final result = Completer<ResearchConsentStatus>();

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) => throw UnimplementedError();
}

final class _FailingConsentRepository implements ResearchConsentRepository {
  const _FailingConsentRepository();

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) => throw StateError('synthetic consent storage failure');

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) => throw UnimplementedError();
}

Future<Map<String, Map<String, Object?>>> _seedPersonalTimeExportPair(
  AppDatabase database,
) async {
  await _seedOwnerWord(
    database,
    ownerId: 'synthetic-personal-export-owner-b',
    spelling: 'synthetic-personal-export-foreign-word',
  );
  Map<String, Map<String, Object?>>? expectedA;
  for (final (owner, suffix, enabled) in [
    ('local:owner', 'a', 0),
    ('synthetic-personal-export-owner-b', 'b', 1),
  ]) {
    final source = ReadingTimeSource(
      documentId: 'synthetic-personal-export-doc-$suffix',
      documentRevision: 1,
      snapshotSha256: (suffix == 'a' ? 'a' : 'c') * 64,
      targetPinsSha256: (suffix == 'a' ? 'b' : 'd') * 64,
      readingStage: 1,
      callerContext: LearningTimeCallerContext.ordinary,
    );
    final scopeId = 'time-scope:synthetic-personal-export-$suffix';
    final rows = <String, Map<String, Object?>>{
      'learning_time_preferences': {
        'owner_id': owner,
        'enabled': enabled,
        'revision': suffix == 'a' ? 3 : 8,
        'updated_at_utc_ms': 1000,
      },
      'learning_time_scopes': {
        'id': scopeId,
        'owner_id': owner,
        'source_kind': 'reading',
        'source_binding_json': source.sourceBindingJson,
        'created_at_utc_ms': 1000,
        'linked_session_id': null,
        'session_link_binding_json': null,
      },
      'learning_time_segments': {
        'id': 'time-segment:synthetic-personal-export-$suffix-0',
        'scope_id': scopeId,
        'ordinal': 0,
        'eligibility_context_json': source.contextBindingJson,
        'started_at_utc_ms': 1000,
        'ended_at_utc_ms': suffix == 'a' ? 1000 : 10876,
        'active_duration_us': suffix == 'a' ? 1 : 9876543,
        'capture_policy_revision': 'confirmed-interaction-v1',
      },
    };
    for (final entry in rows.entries) {
      await database.customStatement(
        'INSERT INTO "${entry.key}" (${entry.value.keys.join(',')}) '
        'VALUES (${List.filled(entry.value.length, '?').join(',')})',
        entry.value.values.toList(),
      );
    }
    if (suffix == 'a') expectedA = rows;
  }
  expect(
    await database.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
  return expectedA!;
}

List<String> _personalTimeCsvCells(String line) {
  final matches = RegExp(r'"((?:""|[^"])*)"(?:,|$)').allMatches(line).toList();
  expect(matches.map((match) => match.group(0)).join(), line);
  return [for (final match in matches) match.group(1)!.replaceAll('""', '"')];
}

Future<Map<String, List<String>>> _personalTimeExportSnapshot(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName: [
      for (final row
          in await database
              .customSelect(
                'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
              )
              .get())
        jsonEncode(row.data),
    ],
};

Future<void> _seedOwnerWord(
  AppDatabase database, {
  required String ownerId,
  required String spelling,
}) async {
  await database.customInsert(
    "INSERT INTO local_owners (id, created_at_utc_ms, is_active) "
    "VALUES ('$ownerId', 1, 0)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('category-$ownerId', '$ownerId', '$ownerId', '$ownerId', 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_words "
    "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
    "normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('word-$ownerId', '$ownerId', 'category-$ownerId', '$spelling', "
    "'$spelling', '$spelling', '$spelling', 'noun', 1, 1)",
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
