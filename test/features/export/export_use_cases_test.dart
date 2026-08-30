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
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';

import '../../support/current_database_contract.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

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
    expect(artifact.schemaVersion, 1);
  });

  test(
    'saved intent reader exports pinned revision and tombstone state',
    () async {
      final rows = await DriftExportReader(
        database,
      ).loadSavedLearningItems('local:owner');

      expect(rows, hasLength(1));
      expect(rows.single.contentType, 'lexicalMetadata');
      expect(rows.single.contentId, 'word-1');
      expect(rows.single.contentRevision, 1);
      expect(
        rows.single.savedAtUtc,
        DateTime.fromMillisecondsSinceEpoch(4, isUtc: true),
      );
      expect(rows.single.isSaved, isTrue);
    },
  );

  test(
    'learning time export keeps duration and wall audit context separate',
    () async {
      final rows = await DriftExportReader(
        database,
      ).loadLearningTimeSegments('local:owner');

      expect(rows, hasLength(1));
      expect(rows.single.sessionId, 'session-1');
      expect(rows.single.activeStartOffsetMs, 0);
      expect(rows.single.activeDurationMs, 7000);
      expect(
        rows.single.startedAtUtc,
        DateTime.fromMillisecondsSinceEpoch(9000, isUtc: true),
      );
      expect(
        rows.single.endedAtUtc,
        DateTime.fromMillisecondsSinceEpoch(8000, isUtc: true),
      );
      expect(rows.single.timezoneId, 'Asia/Bangkok');
      expect(rows.single.timezoneOffsetMinutes, 420);
      expect(rows.single.captureSource, 'automaticLesson');
    },
  );

  test('learning goal export preserves typed deadline and timezone', () async {
    final rows = await DriftExportReader(
      database,
    ).loadLearningGoals('local:owner');

    expect(rows, hasLength(1));
    expect(rows.single.kind, 'languageTest');
    expect(rows.single.title, 'IELTS practice target');
    expect(rows.single.deadlineAtUtc, DateTime.utc(2026, 9, 1, 5));
    expect(rows.single.timezoneId, 'Asia/Bangkok');
    expect(rows.single.timezoneOffsetMinutes, 420);
    expect(rows.single.status, 'active');
  });

  test(
    'owner archive retains the exact learner preference after consent withdrawal',
    () async {
      await database.customInsert(
        'INSERT INTO learner_preferences '
        '(owner_id, preference_version, goal, available_minutes_per_day, '
        'activity_preference, updated_at_utc_ms) VALUES '
        "('local:owner', 1, 'examPreparation', 45, 'quiz', 20)",
      );
      await consent.withdraw();

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
      final preferenceTable = (content['tables'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((table) => table['alias'] == 'learnerPreferences');

      expect(preferenceTable['records'], [
        {'recordCount': 1},
        {
          'preferenceVersion': 1,
          'goal': 'examPreparation',
          'availableMinutesPerDay': 45,
          'activityPreference': 'quiz',
          'updatedAtUtc': '1970-01-01T00:00:00.020Z',
        },
      ]);
    },
  );

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
    final evidenceContext = EvidenceContext.forNewEvidence(
      evidenceClass: EvidenceClass.assessment,
      skillId: 'assessment-vocabulary-recall',
      hintLevel: 0,
      contentRevision: 'research-pack-v2',
      rolloutMode: EvidencePolicyRolloutMode.shadow,
      protocolId: 'evidence-pilot',
      protocolVersion: '1.0.0',
      experimentId: 'evidence-eligibility',
      experimentVersion: 1,
      assignmentId: 'assignment-1',
      cohort: 'shadow',
      researchConsentVersion: 1,
      instrumentId: 'vocabulary-outcome',
      instrumentVersion: '2.0.0',
      formId: 'post-form-a',
      formVersion: '1.0.0',
      assessmentItemId: 'item-1',
      assessmentResponseCode: 'correct',
      scoringRuleVersion: 'binary-v1',
    );
    await database.customUpdate(
      'UPDATE answer_attempts SET evidence_class = ?, '
      'evidence_context_json = ? WHERE id = ?',
      variables: [
        Variable<String>(evidenceContext.evidenceClass.name),
        Variable<String>(jsonEncode(evidenceContext.toJson())),
        const Variable<String>('attempt-1'),
      ],
      updates: {database.answerAttempts},
    );

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
    final attempt =
        (parsed['attempts'] as List<dynamic>).single as Map<String, dynamic>;
    expect(attempt.keys.toSet(), {
      'evidenceId',
      'sessionId',
      'wordId',
      'spelling',
      'promptMode',
      'isCorrect',
      'responseTimeMs',
      'occurredAtUtc',
      'evidenceClass',
      'skillId',
      'hintLevel',
      'policyVersion',
      'contentRevision',
      'featureContractRevision',
      'featureContractHash',
      'classificationSource',
      'rolloutMode',
      'protocolId',
      'protocolVersion',
      'experimentId',
      'experimentVersion',
      'assignmentId',
      'cohort',
      'researchConsentVersion',
      'instrumentId',
      'instrumentVersion',
      'formId',
      'formVersion',
      'assessmentItemId',
      'assessmentResponseCode',
      'scoringRuleVersion',
    });
    expect(attempt, containsPair('evidenceId', 'attempt-1'));
    expect(attempt, containsPair('evidenceClass', 'assessment'));
    expect(attempt, containsPair('skillId', 'assessment-vocabulary-recall'));
    expect(attempt, containsPair('hintLevel', 0));
    expect(attempt, containsPair('policyVersion', 'learning-evidence-v1'));
    expect(attempt, containsPair('contentRevision', 'research-pack-v2'));
    expect(
      attempt,
      containsPair(
        'featureContractRevision',
        evidenceContext.featureContractRevision,
      ),
    );
    expect(
      attempt,
      containsPair('featureContractHash', evidenceContext.featureContractHash),
    );
    expect(attempt, containsPair('classificationSource', 'declared'));
    expect(attempt, containsPair('rolloutMode', 'shadow'));
    expect(attempt, containsPair('protocolId', 'evidence-pilot'));
    expect(attempt, containsPair('protocolVersion', '1.0.0'));
    expect(attempt, containsPair('experimentId', 'evidence-eligibility'));
    expect(attempt, containsPair('experimentVersion', 1));
    expect(attempt, containsPair('assignmentId', 'assignment-1'));
    expect(attempt, containsPair('cohort', 'shadow'));
    expect(attempt, containsPair('researchConsentVersion', 1));
    expect(attempt, containsPair('instrumentId', 'vocabulary-outcome'));
    expect(attempt, containsPair('instrumentVersion', '2.0.0'));
    expect(attempt, containsPair('formId', 'post-form-a'));
    expect(attempt, containsPair('formVersion', '1.0.0'));
    expect(attempt, containsPair('assessmentItemId', 'item-1'));
    expect(attempt, containsPair('assessmentResponseCode', 'correct'));
    expect(attempt, containsPair('scoringRuleVersion', 'binary-v1'));
  });

  test(
    'participant archive retains active completed and abandoned assessment audits after withdrawal',
    () async {
      const ownerId = 'local:owner';
      const experimentId = 'assessment-study';
      const experimentVersion = 1;
      final assignmentId =
          DriftExperimentAssignmentRepository.canonicalAssignmentId(
            ownerId: ownerId,
            experimentId: experimentId,
            experimentVersion: experimentVersion,
          );
      await database.customInsert(
        'INSERT INTO experiment_assignments '
        '(id, owner_id, experiment_id, experiment_version, cohort, '
        'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(assignmentId),
          const Variable<String>(ownerId),
          const Variable<String>(experimentId),
          const Variable<int>(experimentVersion),
          const Variable<String>('enforced-a'),
          const Variable<String>('assessment-protocol-v1'),
          Variable<int>(DateTime.utc(2026, 7, 30, 1).millisecondsSinceEpoch),
        ],
      );

      for (final state in const ['active', 'completed', 'abandoned']) {
        final sessionId = 'assessment-session-$state';
        final runId = 'assessment-run-$state';
        final startedAt = DateTime.utc(2026, 7, 30, 2).millisecondsSinceEpoch;
        await database.customInsert(
          'INSERT INTO learning_sessions '
          '(id, owner_id, activity_type, state, started_at_utc_ms, '
          'app_version, build_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable<String>(sessionId),
            const Variable<String>(ownerId),
            const Variable<String>('assessment'),
            const Variable<String>('completed'),
            Variable<int>(startedAt),
            const Variable<String>('1.0.0'),
            const Variable<String>('task-12-export'),
          ],
        );
        await _insertAssessmentRunForExport(
          database,
          id: runId,
          ownerId: ownerId,
          sessionId: sessionId,
          assignmentId: assignmentId,
          studyCycleId: 'cycle-$state',
          state: state,
          startedAtUtcMs: startedAt,
          completedAtUtcMs: state == 'completed' ? startedAt + 1000 : null,
          abandonedAtUtcMs: state == 'abandoned' ? startedAt + 1000 : null,
        );
      }

      final assessmentContext = EvidenceContext.forNewEvidence(
        evidenceClass: EvidenceClass.assessment,
        skillId: 'word-1',
        hintLevel: 0,
        contentRevision: 'assessment-content-r1',
        rolloutMode: EvidencePolicyRolloutMode.enforced,
        protocolId: 'assessment-protocol',
        protocolVersion: 'assessment-protocol-v1',
        experimentId: experimentId,
        experimentVersion: experimentVersion,
        assignmentId: assignmentId,
        cohort: 'enforced-a',
        researchConsentVersion: 1,
        instrumentId: 'vocabulary-outcome',
        instrumentVersion: '1.0.0',
        formId: 'form-a',
        formVersion: '1.0.0',
        assessmentItemId: 'item-1',
        assessmentResponseCode: 'choice-b',
        scoringRuleVersion: 'binary-v1',
        engagementAllowed: false,
      );
      await database.customInsert(
        'INSERT INTO answer_attempts '
        '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
        'response_time_ms, attempt_number, occurred_at_utc_ms, '
        'provider_provenance, evidence_class, evidence_context_json) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          const Variable<String>('assessment-evidence-1'),
          const Variable<String>(ownerId),
          const Variable<String>('assessment-session-completed'),
          const Variable<String>('word-1'),
          const Variable<String>('meaningChoice'),
          const Variable<bool>(true),
          const Variable<int>(750),
          const Variable<int>(1),
          Variable<int>(
            DateTime.utc(2026, 7, 30, 2, 0, 1).millisecondsSinceEpoch,
          ),
          const Variable<String>('raw-response-SENTINEL'),
          Variable<String>(assessmentContext.evidenceClass.name),
          Variable<String>(jsonEncode(assessmentContext.toJson())),
        ],
      );
      await consent.withdraw();

      final artifact = await exports.prepare(
        format: ExportFormat.ownerArchiveJson,
        selection: const ExportSelection(
          includeVocabulary: false,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      final archiveText = utf8.decode(artifact.bytes);
      final envelope = jsonDecode(archiveText) as Map<String, dynamic>;
      final content = envelope['content'] as Map<String, dynamic>;
      final tables = (content['tables'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final assessmentRuns = tables.singleWhere(
        (entry) => entry['alias'] == 'assessmentRuns',
      );
      final records = (assessmentRuns['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(records.first, {'recordCount': 3});
      expect(records.skip(1).map((record) => record['state']).toSet(), {
        'active',
        'completed',
        'abandoned',
      });
      final completed = records.singleWhere(
        (record) => record['state'] == 'completed',
      );
      expect(completed, containsPair('studyCycleId', 'cycle-completed'));
      expect(completed, containsPair('phase', 'pre'));
      expect(completed, containsPair('protocolId', 'assessment-protocol'));
      expect(
        completed,
        containsPair('protocolVersion', 'assessment-protocol-v1'),
      );
      expect(completed, containsPair('experimentId', experimentId));
      expect(completed, containsPair('experimentVersion', experimentVersion));
      expect(completed, containsPair('cohort', 'enforced-a'));
      expect(completed, containsPair('consentVersion', 1));
      expect(completed, containsPair('instrumentId', 'vocabulary-outcome'));
      expect(completed, containsPair('instrumentVersion', '1.0.0'));
      expect(completed, containsPair('formId', 'form-a'));
      expect(completed, containsPair('formVersion', '1.0.0'));
      expect(
        completed,
        containsPair('instrumentChecksumSha256', _exportInstrumentHash),
      );
      expect(completed, containsPair('formChecksumSha256', _exportFormHash));
      expect(
        completed,
        containsPair('contentRevision', 'assessment-content-r1'),
      );
      expect(
        completed,
        containsPair(
          'evidencePolicyVersion',
          EvidenceContext.currentPolicyVersion,
        ),
      );
      expect(
        completed,
        containsPair(
          'featureContractRevision',
          currentFeatureContractIdentity.revision,
        ),
      );
      expect(
        completed,
        containsPair(
          'featureContractHash',
          currentFeatureContractIdentity.semanticHash,
        ),
      );
      expect(completed['controlledResponses'], [
        {
          'sourceEvidenceId': 'assessment-evidence-1',
          'itemId': 'item-1',
          'responseCode': 'choice-b',
          'isCorrect': true,
          'responseTimeMs': 750,
          'occurredAtUtc': '2026-07-30T02:00:01.000Z',
          'scoringRuleVersion': 'binary-v1',
        },
      ]);
      for (final forbidden in const [
        'raw-response-SENTINEL',
        'submittedResponse',
        'providerProvenance',
        'deviceId',
        'combinedScore',
        'outcomeLearningEffortEngagement',
      ]) {
        expect(archiveText, isNot(contains(forbidden)));
      }
    },
  );

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
      expect(
        content['tables'],
        hasLength(currentDatabaseTableInventory.length),
      );
      expect(content['archiveSchemaVersion'], 1);
      expect(content['algorithmVersion'], 1);
      expect(
        content['databaseSchemaVersion'],
        AppDatabase.currentSchemaVersion,
      );
      expect(
        content['manifestEntryCount'],
        currentDatabaseTableInventory.length,
      );
      expect(artifact.schemaVersion, content['archiveSchemaVersion']);
      expect(artifact.algorithmVersion, content['algorithmVersion']);
      expect(artifact.recordCount, content['manifestEntryCount']);
      expect(artifact.sha256, isNotEmpty);

      final tables = (content['tables'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final vocabulary = tables.singleWhere(
        (table) => table['alias'] == 'vocabularyWords',
      );
      final word = (vocabulary['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((record) => !record.containsKey('recordCount'))
          .single;
      expect(word['contentRevision'], 1);
      expect(word['contentProvenance'], 'userAuthored');
      expect(word['contentReviewState'], 'unreviewed');
      expect(word['contentPublicationState'], 'private');
      final learningTime = tables.singleWhere(
        (table) => table['alias'] == 'learningTimeSegments',
      );
      final segment = (learningTime['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((record) => !record.containsKey('recordCount'))
          .single;
      expect(segment.keys.toSet(), {
        'sessionId',
        'activeStartOffsetMs',
        'activeDurationMs',
        'startedAtUtc',
        'endedAtUtc',
        'timezoneId',
        'timezoneOffsetMinutes',
        'captureSource',
      });
      expect(segment['activeDurationMs'], 7000);
      expect(segment['startedAtUtc'], '1970-01-01T00:00:09.000Z');
      expect(segment['endedAtUtc'], '1970-01-01T00:00:08.000Z');
      expect(segment['timezoneId'], 'Asia/Bangkok');
      expect(segment['timezoneOffsetMinutes'], 420);
      final learningGoals = tables.singleWhere(
        (table) => table['alias'] == 'learningGoals',
      );
      final goal = (learningGoals['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((record) => !record.containsKey('recordCount'))
          .single;
      expect(goal['kind'], 'languageTest');
      expect(goal['title'], 'IELTS practice target');
      expect(goal['deadlineAtUtc'], '2026-09-01T05:00:00.000Z');
      expect(goal['timezoneId'], 'Asia/Bangkok');
      expect(goal['timezoneOffsetMinutes'], 420);
      expect(goal['status'], 'active');

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

  test('owner archive redacts a noncanonical raw timezone', () async {
    await database.customInsert(
      'INSERT INTO learning_time_segments '
      '(id, owner_id, session_id, active_start_offset_ms, active_duration_ms, '
      'started_at_utc_ms, ended_at_utc_ms, timezone_id, '
      'timezone_offset_minutes, capture_source) VALUES '
      "('invalid-timezone-segment', 'local:owner', 'session-1', 7000, 1, "
      "9000, 8000, 'Mars/Olympus', 0, 'automaticLesson')",
    );

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
    final table = (content['tables'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((entry) => entry['alias'] == 'learningTimeSegments');
    final invalid = (table['records'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((record) => record['activeStartOffsetMs'] == 7000)
        .single;

    expect(invalid['timezoneId'], 'redacted');
    expect(invalid['timezoneOffsetMinutes'], 0);
  });

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

const _exportInstrumentHash =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _exportFormHash =
    '2222222222222222222222222222222222222222222222222222222222222222';
Future<void> _insertAssessmentRunForExport(
  AppDatabase database, {
  required String id,
  required String ownerId,
  required String sessionId,
  required String assignmentId,
  required String studyCycleId,
  required String state,
  required int startedAtUtcMs,
  required int? completedAtUtcMs,
  required int? abandonedAtUtcMs,
}) {
  return database.customInsert(
    'INSERT INTO assessment_runs '
    '(id, owner_id, learning_session_id, study_cycle_id, phase, state, '
    'protocol_id, protocol_version, experiment_id, experiment_version, '
    'assignment_id, cohort, consent_version, consent_decided_at_utc_ms, '
    'instrument_id, instrument_version, form_id, form_version, '
    'instrument_checksum_sha256, form_checksum_sha256, app_version, build_id, '
    'database_schema_version, content_revision, evidence_policy_version, '
    'feature_contract_revision, feature_contract_hash, started_at_utc_ms, '
    'completed_at_utc_ms, abandoned_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
    '?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    variables: [
      Variable<String>(id),
      Variable<String>(ownerId),
      Variable<String>(sessionId),
      Variable<String>(studyCycleId),
      const Variable<String>('pre'),
      Variable<String>(state),
      const Variable<String>('assessment-protocol'),
      const Variable<String>('assessment-protocol-v1'),
      const Variable<String>('assessment-study'),
      const Variable<int>(1),
      Variable<String>(assignmentId),
      const Variable<String>('enforced-a'),
      const Variable<int>(1),
      Variable<int>(DateTime.utc(2026, 7, 30).millisecondsSinceEpoch),
      const Variable<String>('vocabulary-outcome'),
      const Variable<String>('1.0.0'),
      const Variable<String>('form-a'),
      const Variable<String>('1.0.0'),
      const Variable<String>(_exportInstrumentHash),
      const Variable<String>(_exportFormHash),
      const Variable<String>('1.0.0'),
      const Variable<String>('task-12-export'),
      const Variable<int>(15),
      const Variable<String>('assessment-content-r1'),
      const Variable<String>(EvidenceContext.currentPolicyVersion),
      Variable<String>(currentFeatureContractIdentity.revision),
      Variable<String>(currentFeatureContractIdentity.semanticHash),
      Variable<int>(startedAtUtcMs),
      Variable<int>(completedAtUtcMs),
      Variable<int>(abandonedAtUtcMs),
    ],
  );
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
  final segmentId = LearningTimeSegment.canonicalId(
    sessionId: 'session-1',
    activeStartOffsetMs: 0,
    captureSource: LearningTimeCaptureSource.automaticLesson,
  );
  await database.customInsert(
    'INSERT INTO learning_time_segments '
    '(id, owner_id, session_id, active_start_offset_ms, active_duration_ms, '
    'started_at_utc_ms, ended_at_utc_ms, timezone_id, '
    'timezone_offset_minutes, capture_source) VALUES '
    "(?, 'local:owner', 'session-1', 0, 7000, 9000, 8000, "
    "'Asia/Bangkok', 420, 'automaticLesson')",
    variables: [Variable<String>(segmentId)],
  );
  await database.customInsert(
    'INSERT INTO learning_goals '
    '(id, owner_id, kind, title, deadline_at_utc_ms, timezone_id, '
    'timezone_offset_minutes, status, created_at_utc_ms, updated_at_utc_ms) '
    "VALUES ('goal-1', 'local:owner', 'languageTest', "
    "'IELTS practice target', 1788238800000, 'Asia/Bangkok', 420, "
    "'active', 1, 1)",
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
  await database.customInsert(
    'INSERT INTO saved_learning_items '
    '(id, owner_id, content_type, content_id, content_revision, '
    'saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision, '
    'is_deleted) VALUES '
    "('saved-1', 'local:owner', 'lexicalMetadata', 'word-1', 1, "
    '4, 4, 1, 0, 0)',
  );
}
