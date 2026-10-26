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
    expect(parsed['schemaVersion'], 1);
    expect(parsed['timeZone'], 'UTC');
    expect((parsed['attempts'] as List).single['evidenceId'], 'attempt-1');
  });

  test('research JSON includes owner A data and excludes owner B', () async {
    await _seedOwnerWord(database, ownerId: 'owner-a', spelling: 'alpha');
    await _seedOwnerWord(database, ownerId: 'owner-b', spelling: 'bravo');
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
    expect((vocabulary.single as Map<String, dynamic>)['spelling'], 'alpha');
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
}

const _all = ExportSelection(
  includeVocabulary: true,
  includeAttempts: true,
  includeReading: true,
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
