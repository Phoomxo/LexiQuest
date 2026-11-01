import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/assessment/application/study_assessment.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/research/application/controlled_study_archive_use_cases.dart';
import 'package:vocab_learning_app/features/research/application/controlled_study_upload_use_cases.dart';
import 'package:vocab_learning_app/features/research/application/local_study_runtime.dart';
import 'package:vocab_learning_app/features/research/application/research_authority_lifecycle.dart';
import 'package:vocab_learning_app/features/research/data/drift_study_archive_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/data/local_research_authority_cache.dart';
import 'package:vocab_learning_app/features/research/data/http_research_authority_gateway.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_permit_json_codec.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/study_archive.dart';
import 'package:vocab_learning_app/features/research/domain/research_transport_contracts.dart';
import 'package:vocab_learning_app/features/research/presentation/study_archive_screen.dart';

import '../../support/research_admission_signing.dart';
import '../../support/research_authority_cache_harness.dart';
import '../../support/research_transport_wire.dart';
import '../../support/assessment_study_harness.dart';
import '../../support/study_runtime_harness.dart' show StudyRuntimeFixture;
import '../../support/research_participation_harness.dart'
    show participationDocument;

void main() {
  testWidgets(
    'actual SQLite Study archive screen saves only its authorized cycle',
    (tester) async {
      final fixture = (await tester.runAsync(_openArchive))!;
      final owners = StreamController<String?>.broadcast();
      final store = _PausedStore(-1, () async {});
      final before = (await tester.runAsync(
        () => _allRows(fixture.authority.study.database),
      ))!;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: StudyArchiveScreen(
              archives: ControlledStudyArchiveUseCases(
                repository: fixture.repository,
                store: store,
              ),
              ownerChanges: owners.stream,
            ),
          ),
        );
        owners.add('owner-a');
        await _pumpArchiveUntil(
          tester,
          () => find
              .byKey(const ValueKey('study-archive-save'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.textContaining(fixture.target.studyCycleId), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('study-archive-save')),
        );
        await tester.tap(find.byKey(const ValueKey('study-archive-save')));
        await _pumpArchiveUntil(
          tester,
          () => find.textContaining('บันทึกไฟล์แล้ว').evaluate().isNotEmpty,
        );
        expect(store.externalWrites, 1);
        final payload = jsonDecode(utf8.decode(store.artifact!.bytes)) as Map;
        expect(payload['schema'], 'lexiquest.controlled-study-archive.v1');
        expect(
          (await tester.runAsync(
            () => _allRows(fixture.authority.study.database),
          ))!,
          before,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await owners.close();
        await tester.runAsync(fixture.authority.close);
      }
    },
  );

  test(
    'assignment A export cannot read same-owner cycle B or mutate any table',
    () async {
      final fixture = await AuthorityCacheFixture.open();
      addTearDown(fixture.close);
      final cycle = (await fixture.study.baseline()).run!;
      final gateway = _ExportGateway(fixture);
      fixture.cache.dispose();
      fixture.cache = LocalResearchAuthorityCache(
        ownerWrites: fixture.study.participation.ownerWrites,
        currentScope: () => fixture.scope,
        gateway: gateway,
        operationSignatures: fixture.study.authorities.operationSignatures,
        participationSignatures:
            fixture.study.authorities.participationSignatures,
        generateRequestId: () => 'synthetic-archive-refresh',
        maximumAcceptedAge: const Duration(minutes: 10),
        initiallyForeground: true,
        monotonicElapsed: () => fixture.elapsed,
      );
      fixture.bindRuntime();
      expect(await fixture.cache.refresh(), isTrue);
      await _copyRow(
        fixture.study.database,
        'experiment_assignments',
        cycle.assignmentId,
        {
          'id': 'synthetic-assignment-b',
          'experiment_id': 'synthetic-experiment-b',
        },
      );
      await _copyRow(
        fixture.study.database,
        'motivation_measurement_runs',
        cycle.id,
        {'id': 'synthetic-cycle-b', 'assignment_id': 'synthetic-assignment-b'},
      );
      final before = await _allRows(fixture.study.database);
      expect(before.length, greaterThanOrEqualTo(40));
      final repository = DriftStudyArchiveRepository(
        study: fixture.study.runtime,
        motivationAuthority: fixture.cache,
      );
      await expectLater(
        repository.prepare(
          const StudyArchiveTarget(
            expectedOwnerId: 'owner-a',
            studyCycleId: 'synthetic-cycle-b',
          ),
          stillCurrent: () => true,
        ),
        throwsA(isA<ExportException>()),
      );
      final accepted = await repository.prepare(
        StudyArchiveTarget(expectedOwnerId: 'owner-a', studyCycleId: cycle.id),
        stillCurrent: () => true,
      );
      final payload = utf8.decode(accepted.artifact.bytes);
      expect(
        jsonDecode(payload)['schema'],
        'lexiquest.controlled-study-archive.v1',
      );
      for (final forbidden in [
        'owner-a',
        'uid-a',
        cycle.id,
        cycle.assignmentId,
        'synthetic-cycle-b',
        'synthetic-assignment-b',
      ]) {
        expect(payload, isNot(contains(forbidden)));
      }
      expect(await _allRows(fixture.study.database), before);
    },
  );

  test(
    'lists only signed assignment cycles without creating or changing facts',
    () async {
      final f = await _openArchive();
      addTearDown(f.authority.close);
      await _copyRow(
        f.authority.study.database,
        'motivation_measurement_runs',
        f.target.studyCycleId,
        {
          'id': 'synthetic-other-protocol-cycle',
          'protocol_version': 'synthetic-other-protocol-version',
        },
      );
      final before = await _allRows(f.authority.study.database);
      final listed = await f.repository.listCycles(
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      expect(listed.map((row) => row.target.studyCycleId), [
        f.target.studyCycleId,
      ]);
      expect(listed.single.motivationResponseCount, 1);
      expect(listed.single.missingPhases, contains('motivation-post'));
      expect(await _allRows(f.authority.study.database), before);
      await expectLater(
        f.repository.listCycles(
          expectedOwnerId: 'owner-b',
          stillCurrent: () => true,
        ),
        throwsA(isA<ExportException>()),
      );
    },
  );

  test('collect permission cannot replace an export permission', () async {
    final f = await _openArchive(includeExport: false);
    addTearDown(f.authority.close);
    await expectLater(
      f.repository.prepare(f.target, stillCurrent: () => true),
      throwsA(isA<ExportException>()),
    );
  });

  test(
    'valid export does not require collection permission or mutate rows',
    () async {
      final f = await _openArchive(includeCollect: false);
      addTearDown(f.authority.close);
      final before = await _allRows(f.authority.study.database);
      final archive = await f.repository.prepare(
        f.target,
        stillCurrent: () => true,
      );
      expect(archive.preview.motivationResponseCount, 1);
      expect(await _allRows(f.authority.study.database), before);
    },
  );

  test(
    'expired collect grant does not prevent a current signed export grant',
    () async {
      final f = await _openArchive(expiredCollect: true);
      addTearDown(f.authority.close);
      final collect = await f.authority.cache.loadPermit(
        ownerId: 'owner-a',
        operation: ResearchOperation.collect,
      );
      expect(collect!.expiresAtUtc.isBefore(participationStart), isTrue);
      final before = await _allRows(f.authority.study.database);
      expect(
        (await f.repository.prepare(
          f.target,
          stillCurrent: () => true,
        )).preview.motivationResponseCount,
        1,
      );
      expect(await _allRows(f.authority.study.database), before);
    },
  );

  test(
    'genuine abandoned Motivation cycle retains missing post without invented results',
    () async {
      final f = await _openArchive();
      addTearDown(f.authority.close);
      await f.authority.study.runtime
          .measurementsFor('owner-a')
          .close(
            MotivationMeasurementClose(
              ownerId: 'owner-a',
              runId: f.target.studyCycleId,
              state: MotivationMeasurementRunState.abandoned,
            ),
          );
      final before = await _allRows(f.authority.study.database);
      final prepared = await f.repository.prepare(
        f.target,
        stillCurrent: () => true,
      );
      final payload = jsonDecode(utf8.decode(prepared.artifact.bytes));
      expect(payload['state'], 'abandoned');
      expect(payload['missingPhases'], contains('motivation-post'));
      expect(payload['motivation']['primaryAnalysisEligible'], isFalse);
      expect(payload['assessments'], isEmpty);
      expect(await _allRows(f.authority.study.database), before);
    },
  );

  test(
    'genuine v21 upgrade archives historical Study pins without rewriting them',
    () async {
      final captured =
          jsonDecode(
                File(
                  'test/fixtures/populated_schema_v21.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final rows = captured['rows'] as Map<String, dynamic>;
      expect(captured['schemaVersion'], 21);
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute(
              File('test/fixtures/schema_v21.sql').readAsStringSync(),
            );
            sqlite.execute('PRAGMA foreign_keys = ON');
            sqlite.execute('BEGIN');
            sqlite.execute('PRAGMA defer_foreign_keys = ON');
            for (final entry in rows.entries) {
              if (!const {
                'local_owners',
                'research_consents',
                'experiment_assignments',
                'research_participation_permits',
                'motivation_measurement_runs',
                'motivation_responses',
              }.contains(entry.key)) {
                continue;
              }
              for (final value in entry.value as List) {
                final row = Map<String, Object?>.from(value as Map);
                if ((entry.key == 'local_owners'
                        ? row['id']
                        : row['owner_id']) !=
                    'owner-a') {
                  continue;
                }
                sqlite.execute(
                  'INSERT INTO "${entry.key}" (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
                  row.values.toList(),
                );
              }
            }
            sqlite.execute('COMMIT');
            sqlite.execute('PRAGMA user_version = 21');
          },
        ),
      );
      final study = await StudyRuntimeFixture.open(
        database: database,
        seed: false,
      );
      study.participation.clock.now = participationStart.add(
        const Duration(seconds: 2),
      );
      final authority = AuthorityCacheFixture(study);
      authority.scope = authority.scopeFor('owner-a', 'uid-a', 1);
      authority.gateway = SyntheticAuthorityGateway(authority);
      authority.cache = _cache(
        authority,
        _ExportGateway(authority)
          ..participationOverride = participationDocument(
            participationPermit(
              treatment: TodayExperiencePresentation.adventure,
            ),
          ),
      );
      addTearDown(authority.close);
      authority.bindRuntime();
      expect(await authority.cache.refresh(), isTrue);
      final original = Map<String, Object?>.from(
        (rows['motivation_measurement_runs'] as List).first as Map,
      );
      final before = await _allRows(database);
      final repository = DriftStudyArchiveRepository(
        study: study.runtime,
        motivationAuthority: authority.cache,
      );
      final currentCollection =
          study.runtime.measurementsFor('owner-a')
              as DriftMotivationMeasurementRepository;
      await expectLater(
        currentCollection.inspect('owner-a', original['id']! as String),
        throwsA(
          isA<ResearchCaptureDenied>().having(
            (error) => error.reason,
            'reason',
            ResearchCaptureReason.versionConflict,
          ),
        ),
      );
      final prepared = await repository.prepare(
        StudyArchiveTarget(
          expectedOwnerId: 'owner-a',
          studyCycleId: original['id']! as String,
        ),
        stillCurrent: () => true,
      );
      final payload = jsonDecode(utf8.decode(prepared.artifact.bytes));
      expect(database.schemaVersion, 25);
      expect(
        payload['databaseSchemaVersion'],
        original['database_schema_version'],
      );
      expect(await _allRows(database), before);
      for (final schema in [13, database.schemaVersion + 1, 999]) {
        await database.customStatement(
          'UPDATE motivation_measurement_runs SET database_schema_version = ? WHERE id = ?',
          [schema, original['id']],
        );
        final incompatible = await _allRows(database);
        await expectLater(
          repository.prepare(
            StudyArchiveTarget(
              expectedOwnerId: 'owner-a',
              studyCycleId: original['id']! as String,
            ),
            stillCurrent: () => true,
          ),
          throwsA(isA<ExportException>()),
        );
        expect(await _allRows(database), incompatible);
      }
      await database.customStatement(
        'UPDATE motivation_measurement_runs SET database_schema_version = ? WHERE id = ?',
        [original['database_schema_version'], original['id']],
      );
      expect(await _allRows(database), before);
    },
  );

  test(
    'issued artifact bytes are detached and another repository cannot reuse the receipt',
    () async {
      final f = await _openArchive();
      addTearDown(f.authority.close);
      final prepared = await f.repository.prepare(
        f.target,
        stillCurrent: () => true,
      );
      final bytes = prepared.artifact.bytes;
      bytes.fillRange(0, bytes.length, 0);
      expect(utf8.decode(prepared.artifact.bytes), startsWith('{'));
      final second = DriftStudyArchiveRepository(
        study: f.authority.study.runtime,
        motivationAuthority: f.authority.cache,
      );
      await expectLater(
        second.requireCurrent(prepared, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
    },
  );

  test('foreign-owner child is rejected before owner filtering', () async {
    final f = await _openArchive();
    addTearDown(f.authority.close);
    final db = f.authority.study.database;
    expect(
      (await db
              .customSelect("SELECT id FROM local_owners WHERE id = 'owner-b'")
              .get())
          .length,
      1,
    );
    final response =
        (await db
                .customSelect('SELECT id FROM motivation_responses')
                .getSingle())
            .read<String>('id');
    await _copyRow(db, 'motivation_responses', response, {
      'id': 'foreign-child',
      'owner_id': 'owner-b',
    });
    final before = await _allRows(db);
    await expectLater(
      f.repository.prepare(f.target, stillCurrent: () => true),
      throwsA(isA<ExportException>()),
    );
    expect(await _allRows(db), before);
  });

  test(
    'corrupted controlled response is rejected without creating an archive',
    () async {
      final f = await _openArchive();
      addTearDown(f.authority.close);
      await f.authority.study.database.customStatement(
        'UPDATE motivation_responses SET ordinal_value = 0',
      );
      await expectLater(
        f.repository.prepare(f.target, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
    },
  );

  test(
    'an expired cache or A-B-A auth transition retires a prepared export',
    () async {
      final f = await _openArchive();
      addTearDown(f.authority.close);
      final prepared = await f.repository.prepare(
        f.target,
        stillCurrent: () => true,
      );
      f.authority.advance(const Duration(minutes: 11));
      await expectLater(
        f.repository.requireCurrent(prepared, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      expect(await f.authority.cache.refresh(), isTrue);
      final next = await f.repository.prepare(
        f.target,
        stillCurrent: () => true,
      );
      f.authority.scope = f.authority.scopeFor('owner-b', 'uid-b', 2);
      f.authority.scope = f.authority.scopeFor('owner-a', 'uid-a', 3);
      await expectLater(
        f.repository.requireCurrent(next, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
    },
  );

  for (final boundary in [0, 1]) {
    for (final mutation in [
      'withdraw',
      'revoke',
      'suspend',
      'owner',
      'cancel',
      'fence',
    ]) {
      test(
        '$mutation at picker/write boundary $boundary prevents external write',
        () async {
          final f = await _openArchive();
          addTearDown(f.authority.close);
          final cancellation = ExportCancellation();
          final store = _PausedStore(boundary, () async {
            switch (mutation) {
              case 'withdraw':
                await f.authority.study.participation.consent.decide(
                  ownerId: 'owner-a',
                  version: f
                      .authority
                      .study
                      .authorities
                      .binding
                      .study
                      .consentVersion,
                  accepted: false,
                  decidedAtUtc: participationStart,
                );
              case 'revoke':
                f.gateway.revokeExport = true;
                f.authority.gateway.snapshotRevision++;
                expect(await f.authority.cache.refresh(), isTrue);
              case 'suspend':
                f.authority.cache.suspend();
              case 'owner':
                f.authority.scope = f.authority.scopeFor('owner-a', 'uid-a', 3);
              case 'cancel':
                cancellation.cancel();
              case 'fence':
                await f.authority.study.participation.ownerWrites.beginDeletion(
                  ownerId: 'owner-a',
                  firebaseUid: 'uid-a',
                  idempotencyKey: 'synthetic-archive-deletion',
                );
            }
          });
          final useCases = ControlledStudyArchiveUseCases(
            repository: f.repository,
            store: store,
          );
          await expectLater(
            useCases.exportCycle(
              target: f.target,
              cancellation: cancellation,
              stillCurrent: () => true,
            ),
            throwsA(isA<ExportException>()),
          );
          expect(store.externalWrites, 0);
        },
      );
    }
  }

  test(
    'a valid incomplete cycle saves deterministic allowlisted bytes through the store',
    () async {
      final f = await _openArchive();
      addTearDown(f.authority.close);
      final store = _PausedStore(-1, () async {});
      final cases = ControlledStudyArchiveUseCases(
        repository: f.repository,
        store: store,
      );
      final before = await _allRows(f.authority.study.database);
      final first = await f.repository.prepare(
        f.target,
        stillCurrent: () => true,
      );
      final second = await f.repository.prepare(
        f.target,
        stillCurrent: () => true,
      );
      expect(first.artifact.bytes, second.artifact.bytes);
      final result = await cases.exportCycle(
        target: f.target,
        cancellation: ExportCancellation(),
        stillCurrent: () => true,
      );
      expect(store.externalWrites, 1);
      expect(result.bytesWritten, first.artifact.bytes.length);
      final payload =
          jsonDecode(utf8.decode(store.artifact!.bytes))
              as Map<String, dynamic>;
      expect(payload['state'], 'started');
      expect(
        payload['missingPhases'],
        containsAll(['motivation-post', 'first-exposure', 'index-completion']),
      );
      expect(payload.keys, isNot(contains('learningTime')));
      expect(await _allRows(f.authority.study.database), before);
    },
  );

  test(
    'combined archive requires distinct current export grants and preserves pre/post linkage',
    () async {
      final combined = await AssessmentStudyFixture.open();
      addTearDown(combined.close);
      combined.attach();
      await combined.completeAssessment(AssessmentPhase.pre);
      await combined.recordMotivation(MotivationTimepoint.baseline);
      await combined.finishIndex();
      await combined.completeAssessment(AssessmentPhase.post);
      await combined.recordMotivation(MotivationTimepoint.post);
      final live = await _combinedArchive(combined);
      final study = live.study;
      final motivation = live.motivation;
      final motivationGateway = live.motivationGateway;
      final assessmentGateway = live.assessmentGateway;
      final assessmentCache = live.assessmentCache;
      final archive = live.repository;
      final target = live.target;
      final before = await _allRows(study.database);
      final prepared = await archive.prepare(target, stillCurrent: () => true);
      await _emitSyntheticArchiveIfRequested(prepared.artifact.bytes);
      final payload =
          jsonDecode(utf8.decode(prepared.artifact.bytes))
              as Map<String, dynamic>;
      expect((payload['assessments'] as List).map((phase) => phase['phase']), [
        'pre',
        'post',
      ]);
      expect(
        (payload['assessments'] as List).every(
          (phase) =>
              phase['state'] == 'completed' &&
              (phase['outcomes'] as List).isNotEmpty,
        ),
        isTrue,
      );
      expect(payload['index']['state'], 'completed');
      expect(payload['firstExposureEvent'], isNotNull);
      expect(
        payload['motivation']['instrumentId'],
        isNot(payload['assessments'][0]['instrumentId']),
      );
      final indexSessionId =
          (await study.database
                  .customSelect(
                    'SELECT learning_session_id FROM measurement_opportunities WHERE is_index_session = 1',
                  )
                  .getSingle())
              .read<String>('learning_session_id');
      final originalIndexAnswer =
          (await study.database
                  .customSelect(
                    'SELECT * FROM answer_attempts WHERE session_id = ?',
                    variables: [Variable<String>(indexSessionId)],
                  )
                  .getSingle())
              .data;
      await study.database.customStatement(
        'UPDATE answer_attempts SET occurred_at_utc_ms = occurred_at_utc_ms + 60000 WHERE id = ?',
        [originalIndexAnswer['id']],
      );
      final corrupt = await _allRows(study.database);
      await expectLater(
        archive.prepare(target, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      expect(await _allRows(study.database), corrupt);
      await study.database.customStatement(
        'UPDATE answer_attempts SET occurred_at_utc_ms = ? WHERE id = ?',
        [originalIndexAnswer['occurred_at_utc_ms'], originalIndexAnswer['id']],
      );
      final mission =
          (await study.database
                  .customSelect(
                    "SELECT event_id FROM events_v2 WHERE event_type = 'TodayExperienceMissionCompleted'",
                  )
                  .getSingle())
              .read<String>('event_id');
      await study.database.customStatement(
        'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
        ['{}', mission],
      );
      final corruptMission = await _allRows(study.database);
      await expectLater(
        archive.prepare(target, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      expect(await _allRows(study.database), corruptMission);
      final originalMission = before['events_v2']!.singleWhere(
        (row) => row['event_id'] == mission,
      );
      await study.database.customStatement(
        'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
        [originalMission['payload_json'], mission],
      );
      assessmentGateway.includeExport = false;
      combined.authorities.gateway.revision++;
      expect(await assessmentCache.refresh(), isTrue);
      await expectLater(
        archive.prepare(target, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      assessmentGateway.includeExport = true;
      combined.authorities.gateway.revision++;
      expect(await assessmentCache.refresh(), isTrue);
      motivationGateway.includeExport = false;
      motivation.gateway.snapshotRevision++;
      expect(await motivation.cache.refresh(), isTrue);
      await expectLater(
        archive.prepare(target, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      expect(await _allRows(study.database), before);
    },
  );

  test(
    'abandoned Assessment retains real responses and rejects corrupt class or duration',
    () async {
      final combined = await AssessmentStudyFixture.open();
      addTearDown(combined.close);
      combined.attach();
      await combined.recordMotivation(MotivationTimepoint.baseline);
      final command = combined.command(AssessmentPhase.pre);
      final presentation = await combined.assessment.useCases.beginPresentation(
        command,
        ownerId: 'owner-a',
        stillVisible: () => true,
      );
      final item = presentation.items.single;
      await combined.assessment.useCases.submitPresentedResponse(
        ownerId: 'owner-a',
        runId: command.runId,
        itemId: item.itemId,
        option: item.options.first,
        responseTimeMs: 25,
        stillVisible: () => true,
      );
      await combined.assessment.useCases.abandonPresentation(
        ownerId: 'owner-a',
        runId: command.runId,
        stillVisible: () => true,
      );
      final live = await _combinedArchive(combined);
      final db = live.study.database;
      final prepared = await live.repository.prepare(
        live.target,
        stillCurrent: () => true,
      );
      final payload = jsonDecode(utf8.decode(prepared.artifact.bytes));
      expect(payload['assessments'].single['state'], 'abandoned');
      expect(payload['assessments'].single['outcomes'], hasLength(1));
      expect(payload['missingPhases'], contains('assessment-pre'));
      final original =
          (await db
                  .customSelect(
                    'SELECT * FROM answer_attempts WHERE session_id = ?',
                    variables: [Variable<String>(command.learningSessionId)],
                  )
                  .getSingle())
              .data;
      final before = await _allRows(db);
      for (final change in <(String, Object)>[
        ('evidence_class', 'independentRecall'),
        ('response_time_ms', 2147483648),
      ]) {
        await db.customStatement(
          'UPDATE answer_attempts SET ${change.$1} = ? WHERE id = ?',
          [change.$2, original['id']],
        );
        final corrupt = await _allRows(db);
        await expectLater(
          live.repository.prepare(live.target, stillCurrent: () => true),
          throwsA(isA<ExportException>()),
        );
        expect(await _allRows(db), corrupt);
        await db.customStatement(
          'UPDATE answer_attempts SET ${change.$1} = ? WHERE id = ?',
          [original[change.$1], original['id']],
        );
      }
      expect(await _allRows(db), before);
    },
  );

  test(
    'upload requires both upload grants and retries the exact acknowledged snapshot',
    () async {
      final combined = await AssessmentStudyFixture.open();
      addTearDown(combined.close);
      combined.attach();
      await combined.completeAssessment(AssessmentPhase.pre);
      await combined.recordMotivation(MotivationTimepoint.baseline);
      await combined.finishIndex();
      await combined.completeAssessment(AssessmentPhase.post);
      await combined.recordMotivation(MotivationTimepoint.post);
      final live = await _combinedArchive(combined);
      final before = await _allRows(live.study.database);
      final exported = await live.repository.prepare(
        live.target,
        stillCurrent: () => true,
      );
      await expectLater(
        live.repository.prepareUpload(live.target, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      live.motivationGateway.includeUpload = true;
      live.motivation.gateway.snapshotRevision++;
      expect(await live.motivation.cache.refresh(), isTrue);
      await expectLater(
        live.repository.prepareUpload(live.target, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      live.assessmentGateway.includeUpload = true;
      combined.authorities.gateway.revision++;
      expect(await live.assessmentCache.refresh(), isTrue);
      final uploaded = await live.repository.prepareUpload(
        live.target,
        stillCurrent: () => true,
      );
      expect(uploaded.artifact.bytes, exported.artifact.bytes);
      expect(
        uploaded.motivationScope.requirements.instrumentId,
        isNot(uploaded.assessmentScope.requirements.instrumentId),
      );
      await expectLater(
        live.repository.requireCurrent(uploaded, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      await expectLater(
        live.repository.requireCurrentUpload(
          exported as PreparedStudyUploadArchive,
          stillCurrent: () => true,
        ),
        throwsA(isA<ExportException>()),
      );
      final gateway = _SyntheticUploadGateway()..failOnce = true;
      final cases = ControlledStudyUploadUseCases(
        repository: live.repository,
        gateway: gateway,
      );
      final intent = await cases.prepareCycle(
        target: live.target,
        cancellation: ExportCancellation(),
        stillCurrent: () => true,
      );
      await expectLater(
        cases.submit(
          intent,
          cancellation: ExportCancellation(),
          stillCurrent: () => true,
        ),
        throwsA(isA<ResearchTransportException>()),
      );
      final receipt = await cases.submit(
        intent,
        cancellation: ExportCancellation(),
        stillCurrent: () => true,
      );
      expect(gateway.requests, hasLength(2));
      expect(gateway.requests.first.cycleKey, live.target.studyCycleId);
      expect(gateway.requests.first.bytes, gateway.requests.last.bytes);
      expect(gateway.requests.first.payloadSha256, receipt.payloadSha256);
      expect(await _allRows(live.study.database), before);
      final another = await cases.prepareCycle(
        target: live.target,
        cancellation: ExportCancellation(),
        stillCurrent: () => true,
      );
      final response =
          (await live.study.database
                  .customSelect(
                    'SELECT id,answered_at_utc_ms FROM motivation_responses ORDER BY answered_at_utc_ms LIMIT 1',
                  )
                  .getSingle())
              .data;
      await live.study.database.customStatement(
        'UPDATE motivation_responses SET answered_at_utc_ms = answered_at_utc_ms + 1 WHERE id = ?',
        [response['id']],
      );
      await expectLater(
        cases.submit(
          another,
          cancellation: ExportCancellation(),
          stillCurrent: () => true,
        ),
        throwsA(
          isA<ResearchTransportException>().having(
            (error) => error.code,
            'code',
            ResearchTransportFailureCode.conflict,
          ),
        ),
      );
      expect(gateway.requests, hasLength(2));
      await live.study.database.customStatement(
        'UPDATE motivation_responses SET answered_at_utc_ms = ? WHERE id = ?',
        [response['answered_at_utc_ms'], response['id']],
      );
      expect(await _allRows(live.study.database), before);
      expect(
        await live.study.runtime.consent.withdraw(
          expectedOwnerId: 'owner-a',
          expectedVersion: live.motivation.scope!.consentVersion,
        ),
        isTrue,
      );
      await expectLater(
        cases.submit(
          intent,
          cancellation: ExportCancellation(),
          stillCurrent: () => true,
        ),
        throwsA(isA<ExportException>()),
      );
      expect(gateway.requests, hasLength(2));
    },
  );

  test(
    'HTTP pair refresh permits upload with expired collect and revoked export but rejects retired upload',
    () async {
      final combined = await AssessmentStudyFixture.open();
      addTearDown(combined.close);
      combined.attach();
      await combined.completeAssessment(AssessmentPhase.pre);
      await combined.recordMotivation(MotivationTimepoint.baseline);
      await combined.finishIndex();
      await combined.completeAssessment(AssessmentPhase.post);
      await combined.recordMotivation(MotivationTimepoint.post);
      final gate = ResearchAuthorityReadGate();
      final live = await _combinedArchive(
        combined,
        httpBoundary: true,
        readGate: gate,
      );
      final lifecycle = ResearchAuthorityLifecycle(
        caches: [live.motivation.cache, live.assessmentCache],
        readGate: gate,
        initiallyForeground: true,
      );
      addTearDown(lifecycle.dispose);
      live.motivationGateway
        ..includeUpload = true
        ..expiredCollect = true
        ..revokeExport = true;
      live.assessmentGateway.includeUpload = true;
      live.motivation.gateway.snapshotRevision++;
      live.motivation.gateway.operationRevision++;
      live.motivation.gateway.stateRevision++;
      combined.authorities.gateway.revision++;
      expect(await lifecycle.refresh(stillCurrent: () => true), isTrue);
      await expectLater(
        live.repository.prepare(live.target, stillCurrent: () => true),
        throwsA(isA<ExportException>()),
      );
      final before = await _allRows(live.study.database);
      var uploadRequests = 0;
      final client = MockClient((request) async {
        expect(request.url.path, '/v1/research/study-archives');
        uploadRequests++;
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        final payload = base64Decode(data['payloadBase64'] as String);
        final document = jsonDecode(utf8.decode(payload)) as Map;
        expect(document['schema'], 'lexiquest.controlled-study-archive.v1');
        expect(data['cycleKey'], live.target.studyCycleId);
        final digest = sha256.convert(payload).toString();
        expect(data['payloadSha256'], digest);
        return http.Response(
          jsonEncode({
            'schemaVersion': 1,
            'uploadId': 'a' * 64,
            'receiptId': 'research-upload:${'a' * 64}',
            'payloadSha256': digest,
            'acceptedAtUtc': participationStart.toIso8601String(),
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final cases = ControlledStudyUploadUseCases(
        repository: live.repository,
        gateway: HttpResearchTransport(
          client: client,
          baseUri: Uri.https('synthetic-research.invalid'),
          currentBinding: () => live.motivation.scope?.binding,
          loadIdToken: (_) async => 'synthetic-test-token',
        ),
      );
      final intent = await cases.prepareCycle(
        target: live.target,
        cancellation: ExportCancellation(),
        stillCurrent: () => true,
      );
      final receipt = await cases.submit(
        intent,
        cancellation: ExportCancellation(),
        stillCurrent: () => true,
      );
      expect(receipt.uploadId, 'a' * 64);
      expect(uploadRequests, 1);
      expect(await _allRows(live.study.database), before);
      live.assessmentGateway.revokeUpload = true;
      combined.authorities.gateway.revision++;
      expect(await lifecycle.refresh(stillCurrent: () => true), isTrue);
      await expectLater(
        cases.submit(
          intent,
          cancellation: ExportCancellation(),
          stillCurrent: () => true,
        ),
        throwsA(isA<ExportException>()),
      );
      expect(uploadRequests, 1);
      expect(await _allRows(live.study.database), before);
    },
  );

  test(
    'lazy Assessment waits for canonical learning and rejects an unproven owner binding',
    () async {
      final combined = await AssessmentStudyFixture.open();
      addTearDown(combined.close);
      final live = await _combinedArchive(combined);
      final original = live.study.runtime;
      final before = await _allRows(live.study.database);
      var ready = false;
      var calls = 0;
      final lazy = LocalStudyRuntime(
        context: original.context,
        authorities: original.authorities,
        catalog: original.catalog,
        assessmentFactory: () {
          calls++;
          if (!ready) {
            throw StateError(
              'Synthetic canonical learning has not initialized',
            );
          }
          return original.assessment;
        },
      );
      expect(calls, 0);
      expect(lazy.assessment, isNull);
      ready = true;
      expect(lazy.assessment, same(original.assessment));
      expect(calls, 2);
      expect(
        () => LocalStudyRuntime(
          context: original.context,
          authorities: original.authorities,
          catalog: original.catalog,
          assessment: original.assessment,
          assessmentFactory: () => original.assessment,
        ),
        throwsArgumentError,
      );
      live.motivation.scope = live.motivation.scopeFor('owner-b', 'uid-b', 2);
      expect(lazy.assessment, isNull);
      expect((await lazy.load('owner-a')).phase.name, 'unavailable');
      expect(await _allRows(live.study.database), before);
    },
  );

  testWidgets(
    'actual combined SQLite archive screen uploads only after its explicit action',
    (tester) async {
      final combined = (await tester.runAsync(AssessmentStudyFixture.open))!;
      final owners = StreamController<String?>.broadcast();
      final gateway = _SyntheticUploadGateway();
      try {
        final live = (await tester.runAsync(() async {
          combined.attach();
          await combined.completeAssessment(AssessmentPhase.pre);
          await combined.recordMotivation(MotivationTimepoint.baseline);
          await combined.finishIndex();
          await combined.completeAssessment(AssessmentPhase.post);
          await combined.recordMotivation(MotivationTimepoint.post);
          final live = await _combinedArchive(combined);
          live.motivationGateway.includeUpload = true;
          live.motivation.gateway.snapshotRevision++;
          live.assessmentGateway.includeUpload = true;
          combined.authorities.gateway.revision++;
          expect(await live.motivation.cache.refresh(), isTrue);
          expect(await live.assessmentCache.refresh(), isTrue);
          return live;
        }))!;
        final before = (await tester.runAsync(
          () => _allRows(live.study.database),
        ))!;
        await tester.pumpWidget(
          MaterialApp(
            home: StudyArchiveScreen(
              archives: ControlledStudyArchiveUseCases(
                repository: live.repository,
                store: _PausedStore(-1, () async {}),
              ),
              uploads: ControlledStudyUploadUseCases(
                repository: live.repository,
                gateway: gateway,
              ),
              ownerChanges: owners.stream,
            ),
          ),
        );
        owners.add('owner-a');
        final button = find.byKey(const ValueKey('study-archive-upload'));
        await _pumpArchiveUntil(tester, () => button.evaluate().isNotEmpty);
        expect(gateway.requests, isEmpty);
        expect(
          (await tester.runAsync(() => _allRows(live.study.database)))!,
          before,
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await _pumpArchiveUntil(
          tester,
          () => find
              .text('เซิร์ฟเวอร์ยืนยันรับข้อมูลรอบนี้แล้ว')
              .evaluate()
              .isNotEmpty,
        );
        expect(gateway.requests, hasLength(1));
        final payload =
            jsonDecode(utf8.decode(gateway.requests.single.bytes)) as Map;
        expect(payload['missingPhases'], isEmpty);
        expect(
          (payload['assessments'] as List).map((value) => value['phase']),
          ['pre', 'post'],
        );
        expect(
          (await tester.runAsync(() => _allRows(live.study.database)))!,
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await owners.close();
        await tester.runAsync(combined.close);
      }
    },
  );
}

Future<void> _emitSyntheticArchiveIfRequested(List<int> bytes) async {
  const path = String.fromEnvironment('LEXIQUEST_SYNTHETIC_ARCHIVE_PATH');
  if (path.isEmpty) return;
  final file = File(path).absolute;
  expect(
    await file.parent.resolveSymbolicLinks(),
    await Directory(
      r'D:\LexiQuest-Storage\maintenance\2026-11-01',
    ).resolveSymbolicLinks(),
  );
  if (await file.exists()) {
    expect(
      await file.readAsBytes(),
      bytes,
      reason: 'Never replace captured evidence',
    );
  } else {
    await file.writeAsBytes(bytes, flush: true);
  }
}

final class _SyntheticUploadGateway implements StudyUploadGateway {
  final requests = <StudyUploadRequest>[];
  bool failOnce = false;
  @override
  Future<StudyUploadReceipt> upload(
    StudyUploadRequest request, {
    required bool Function() stillCurrent,
    required Future<void> Function() revalidateBeforeSubmit,
  }) async {
    await revalidateBeforeSubmit();
    expect(stillCurrent(), isTrue);
    requests.add(request);
    if (failOnce) {
      failOnce = false;
      throw const ResearchTransportException(
        ResearchTransportFailureCode.unavailable,
      );
    }
    final id = List.filled(64, 'a').join();
    return StudyUploadReceipt(
      uploadId: id,
      receiptId: 'research-upload:$id',
      payloadSha256: request.payloadSha256,
      acceptedAtUtc: participationStart,
    );
  }
}

Future<void> _pumpArchiveUntil(
  WidgetTester tester,
  bool Function() complete,
) async {
  for (var attempt = 0; attempt < 600; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    if (complete()) return;
  }
  fail('Actual Study archive UI did not acknowledge its authorized operation');
}

typedef _CombinedArchiveFixture = ({
  StudyRuntimeFixture study,
  AuthorityCacheFixture motivation,
  _ExportGateway motivationGateway,
  LocalResearchAuthorityCache assessmentCache,
  _AdditionalExportGateway assessmentGateway,
  DriftStudyArchiveRepository repository,
  StudyArchiveTarget target,
});

Future<_CombinedArchiveFixture> _combinedArchive(
  AssessmentStudyFixture combined, {
  bool httpBoundary = false,
  ResearchAuthorityReadGate? readGate,
}) async {
  final study = combined.authorities.study;
  final motivation = AuthorityCacheFixture(study);
  motivation.scope = motivation.scopeFor('owner-a', 'uid-a', 1);
  motivation.gateway = SyntheticAuthorityGateway(motivation);
  final motivationGateway = _ExportGateway(motivation);
  motivation.cache = _cache(
    motivation,
    httpBoundary
        ? SyntheticHttpResearchAuthorityGateway(
            inner: motivationGateway,
            currentBinding: () => motivation.scope?.binding,
          )
        : motivationGateway,
    readGate: readGate,
  );
  addTearDown(motivation.cache.dispose);
  motivation.bindRuntime();
  expect(await motivation.cache.refresh(), isTrue);
  final assessmentGateway = _AdditionalExportGateway(
    combined.authorities.gateway,
  );
  final assessmentCache = LocalResearchAuthorityCache(
    ownerWrites: study.participation.ownerWrites,
    currentScope: () => combined.authorities.scope,
    gateway: httpBoundary
        ? SyntheticHttpResearchAuthorityGateway(
            inner: assessmentGateway,
            currentBinding: () => combined.authorities.scope?.binding,
          )
        : assessmentGateway,
    readGate: readGate,
    operationSignatures: study.authorities.operationSignatures,
    participationSignatures: study.authorities.participationSignatures,
    generateRequestId: () => 'synthetic-combined-export',
    maximumAcceptedAge: const Duration(minutes: 10),
    initiallyForeground: true,
    monotonicElapsed: () => combined.authorities.elapsed,
  );
  addTearDown(assessmentCache.dispose);
  expect(await assessmentCache.refresh(), isTrue);
  final repository = DriftAssessmentRepository(
    study.database,
    authority: DriftAssessmentAuthority(
      cache: assessmentCache,
      mapping: combined.assessment.mapping,
    ),
    cycleReader: combined.repository.cycleReader,
    catalog: AssessmentInstrumentCatalog(
      entries: [combined.assessment.definition],
    ),
    contentAuthority: combined.assessment.contentAuthority,
    buildInfo: study.runtime.context.buildInfo,
    participationPermitId: 'synthetic-participation',
  );
  final assessment = StudyAssessment(
    repository: repository,
    definition: combined.assessment.definition,
    mapping: combined.assessment.mapping,
    contentAuthority: combined.assessment.contentAuthority,
    cycleReader: combined.assessment.cycleReader,
    trustedTime: assessmentCache,
  );
  study.runtime = LocalStudyRuntime(
    context: study.runtime.context,
    authorities: study.authorities,
    catalog: study.catalog,
    assessment: assessment,
  );
  study.bindLearning();
  return (
    study: study,
    motivation: motivation,
    motivationGateway: motivationGateway,
    assessmentCache: assessmentCache,
    assessmentGateway: assessmentGateway,
    repository: DriftStudyArchiveRepository(
      study: study.runtime,
      motivationAuthority: motivation.cache,
    ),
    target: StudyArchiveTarget(
      expectedOwnerId: 'owner-a',
      studyCycleId: combined.cycleId,
    ),
  );
}

typedef _ArchiveFixture = ({
  AuthorityCacheFixture authority,
  _ExportGateway gateway,
  DriftStudyArchiveRepository repository,
  StudyArchiveTarget target,
});

Future<_ArchiveFixture> _openArchive({
  bool includeExport = true,
  bool includeCollect = true,
  bool expiredCollect = false,
}) async {
  final authority = await AuthorityCacheFixture.open();
  final run = (await authority.study.baseline()).run!;
  final gateway = _ExportGateway(authority)
    ..includeExport = includeExport
    ..includeCollect = includeCollect
    ..expiredCollect = expiredCollect;
  authority.cache.dispose();
  authority.cache = _cache(authority, gateway);
  authority.bindRuntime();
  expect(await authority.cache.refresh(), isTrue);
  return (
    authority: authority,
    gateway: gateway,
    repository: DriftStudyArchiveRepository(
      study: authority.study.runtime,
      motivationAuthority: authority.cache,
    ),
    target: StudyArchiveTarget(
      expectedOwnerId: 'owner-a',
      studyCycleId: run.id,
    ),
  );
}

LocalResearchAuthorityCache _cache(
  AuthorityCacheFixture authority,
  ResearchAuthorityGateway gateway, {
  ResearchAuthorityReadGate? readGate,
}) => LocalResearchAuthorityCache(
  ownerWrites: authority.study.participation.ownerWrites,
  currentScope: () => authority.scope,
  gateway: gateway,
  readGate: readGate,
  operationSignatures: authority.study.authorities.operationSignatures,
  participationSignatures: authority.study.authorities.participationSignatures,
  generateRequestId: () => 'synthetic-archive-refresh',
  maximumAcceptedAge: const Duration(minutes: 10),
  initiallyForeground: true,
  monotonicElapsed: () => authority.elapsed,
);

final class _PausedStore implements ExportArtifactStore {
  _PausedStore(this.boundary, this.mutate);
  final int boundary;
  final Future<void> Function() mutate;
  int externalWrites = 0;
  ExportArtifact? artifact;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required ExportWriteRevalidator revalidateBeforeWrite,
  }) async {
    for (var index = 0; index < 2; index++) {
      if (boundary == index) await mutate();
      cancellation.throwIfCancelled();
      await revalidateBeforeWrite();
    }
    this.artifact = artifact;
    externalWrites++;
    return ExportSaveResult(
      path: 'synthetic-private-archive.json',
      bytesWritten: artifact.bytes.length,
    );
  }
}

Future<void> _copyRow(
  AppDatabase database,
  String table,
  String id,
  Map<String, Object?> overrides,
) async {
  final original =
      (await database
              .customSelect(
                'SELECT * FROM "$table" WHERE id = ?',
                variables: [Variable<String>(id)],
              )
              .getSingle())
          .data;
  final row = {...original, ...overrides};
  await database.customStatement(
    'INSERT INTO "$table" (${row.keys.map((key) => '"$key"').join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
    row.values.toList(),
  );
}

Future<Map<String, List<Map<String, Object?>>>> _allRows(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName:
        (await database
                .customSelect('SELECT * FROM "${table.actualTableName}"')
                .get())
            .map((row) => row.data)
            .toList(),
};

final class _ExportGateway implements ResearchAuthorityGateway {
  _ExportGateway(this.fixture);
  final AuthorityCacheFixture fixture;
  bool includeExport = true;
  bool includeUpload = false;
  bool includeCollect = true;
  bool revokeExport = false;
  bool expiredCollect = false;
  String? participationOverride;

  @override
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  ) async {
    final original = fixture.gateway.build(request);
    final source = participationOperation();
    final permit = signAdmissionOperation(
      ResearchPermit(
        formatVersion: source.formatVersion,
        permitId: 'synthetic-export-permit',
        issuerId: source.issuerId,
        issuerKeyId: source.issuerKeyId,
        signatureAlgorithm: source.signatureAlgorithm,
        ownerId: source.ownerId,
        operation: ResearchOperation.export,
        assignmentId: source.assignmentId,
        assignmentRevision: source.assignmentRevision,
        protocolId: source.protocolId,
        protocolRevision: source.protocolRevision,
        instrumentId: source.instrumentId,
        instrumentRevision: source.instrumentRevision,
        revision: 1,
        issuedAtUtc: source.issuedAtUtc,
        expiresAtUtc: source.expiresAtUtc,
        signature: const [1],
      ),
    );
    final upload = _uploadPermit(permit);
    return ServerAttestedResearchAuthorityPacket(
      scope: original.scope,
      requestId: original.requestId,
      clockSessionId: original.clockSessionId,
      monotonicEpoch: original.monotonicEpoch,
      snapshotRevision: original.snapshotRevision,
      anchorUtc: original.anchorUtc,
      ageAtObservation: original.ageAtObservation,
      observedAtMonotonic: original.observedAtMonotonic,
      validUntilUtc: original.validUntilUtc,
      maximumAge: original.maximumAge,
      operationDocuments: [
        if (includeCollect)
          ...(expiredCollect
              ? [
                  const ResearchPermitJsonCodec().encode(
                    participationOperation(
                      revision: fixture.gateway.operationRevision,
                      expiresAtUtc: participationStart.subtract(
                        const Duration(minutes: 1),
                      ),
                    ),
                  ),
                ]
              : original.operationDocuments),
        if (includeExport) const ResearchPermitJsonCodec().encode(permit),
        if (includeUpload) const ResearchPermitJsonCodec().encode(upload),
      ],
      operationStates: {
        if (includeCollect) ...original.operationStates,
        if (includeExport)
          permit.permitId: ResearchPermitState(
            currentRevision: revokeExport ? 2 : 1,
            revoked: revokeExport,
          ),
        if (includeUpload)
          upload.permitId: const ResearchPermitState(
            currentRevision: 1,
            revoked: false,
          ),
      },
      participationDocuments: participationOverride == null
          ? original.participationDocuments
          : [participationOverride!],
      receipts: original.receipts,
    );
  }
}

final class _AdditionalExportGateway implements ResearchAuthorityGateway {
  _AdditionalExportGateway(this.inner);
  final ResearchAuthorityGateway inner;
  bool includeExport = true;
  bool includeUpload = false;
  bool revokeUpload = false;

  @override
  Future<ServerAttestedResearchAuthorityPacket?> fetchCurrent(
    ResearchAuthorityRefreshRequest request,
  ) async {
    final original = (await inner.fetchCurrent(request))!;
    final pins = request.scope.requirements;
    final source = participationOperation();
    final permit = signAdmissionOperation(
      ResearchPermit(
        formatVersion: pins.supportedFormatVersion,
        permitId: 'synthetic-assessment-export',
        issuerId: pins.trustedIssuerId,
        issuerKeyId: pins.trustedIssuerKeyId,
        signatureAlgorithm: pins.signatureAlgorithm,
        ownerId: request.scope.binding.ownerId,
        operation: ResearchOperation.export,
        assignmentId: pins.assignmentId,
        assignmentRevision: pins.assignmentRevision,
        protocolId: pins.protocolId,
        protocolRevision: pins.protocolRevision,
        instrumentId: pins.instrumentId,
        instrumentRevision: pins.instrumentRevision,
        revision: 1,
        issuedAtUtc: source.issuedAtUtc,
        expiresAtUtc: source.expiresAtUtc,
        signature: const [1],
      ),
    );
    final upload = _uploadPermit(permit);
    return ServerAttestedResearchAuthorityPacket(
      scope: original.scope,
      requestId: original.requestId,
      clockSessionId: original.clockSessionId,
      monotonicEpoch: original.monotonicEpoch,
      snapshotRevision: original.snapshotRevision,
      anchorUtc: original.anchorUtc,
      ageAtObservation: original.ageAtObservation,
      observedAtMonotonic: original.observedAtMonotonic,
      validUntilUtc: original.validUntilUtc,
      maximumAge: original.maximumAge,
      operationDocuments: [
        ...original.operationDocuments,
        if (includeExport) const ResearchPermitJsonCodec().encode(permit),
        if (includeUpload) const ResearchPermitJsonCodec().encode(upload),
      ],
      operationStates: {
        ...original.operationStates,
        if (includeExport)
          permit.permitId: const ResearchPermitState(
            currentRevision: 1,
            revoked: false,
          ),
        if (includeUpload)
          upload.permitId: ResearchPermitState(
            currentRevision: revokeUpload ? 2 : 1,
            revoked: revokeUpload,
          ),
      },
      participationDocuments: original.participationDocuments,
      receipts: original.receipts,
    );
  }
}

ResearchPermit _uploadPermit(ResearchPermit source) => signAdmissionOperation(
  ResearchPermit(
    formatVersion: source.formatVersion,
    permitId: '${source.permitId}-upload',
    issuerId: source.issuerId,
    issuerKeyId: source.issuerKeyId,
    signatureAlgorithm: source.signatureAlgorithm,
    ownerId: source.ownerId,
    operation: ResearchOperation.upload,
    assignmentId: source.assignmentId,
    assignmentRevision: source.assignmentRevision,
    protocolId: source.protocolId,
    protocolRevision: source.protocolRevision,
    instrumentId: source.instrumentId,
    instrumentRevision: source.instrumentRevision,
    revision: source.revision,
    issuedAtUtc: source.issuedAtUtc,
    expiresAtUtc: source.expiresAtUtc,
    signature: const [1],
  ),
);
