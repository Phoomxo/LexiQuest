import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import '../../support/motivation_measurement_harness.dart';

Matcher denied([ResearchCaptureReason? reason]) => throwsA(
  reason == null
      ? isA<ResearchCaptureDenied>()
      : isA<ResearchCaptureDenied>().having(
          (error) => error.reason,
          'reason',
          reason,
        ),
);

void main() {
  test('canonical identifiers preserve the archived JSON tuple and prefixes', () {
    expect(
      motivationMeasurementRunId(
        ownerId: 'owner-a',
        permitId: 'permit-a',
        protocolId: 'protocol-a',
        protocolVersion: 'v1',
        instrumentChecksumSha256: 'a' * 64,
      ),
      'motivation:4e7688600de838b27bf7825d6a170322fa33699fce50f9f93d13923cfa662360',
    );
    expect(
      motivationResponseId(runId: 'run-a', itemId: 'item-a'),
      'response:c1eb47e9a148509e3592d81ac50d9dd54ce8d5430421ffba449b4d6db1f7f484',
    );
  });

  group('authorized motivation measurement', () {
    late MeasurementFixture fixture;
    late MeasurementQueries queries;
    setUp(() async {
      queries = MeasurementQueries();
      fixture = await MeasurementFixture.open(queries: queries);
    });
    tearDown(() => fixture.database.close());

    test(
      'start persists full signed pins without requiring timing evidence',
      () async {
        final run = await fixture.start();
        final row = await fixture.storedRun();
        expect(run.id, fixture.runId);
        expect(run.state, MotivationMeasurementRunState.started);
        expect(run.startedAtUtc, participationStart);
        expect(run.localRevision, 1);
        expect(run.responses, isEmpty);
        expect(run.timing, isNull);
        expect(row['permit_id'], fixture.permitId);
        expect(
          row['permit_payload_sha256'],
          fixture.participation.current.payloadSha256,
        );
        expect(row['assignment_id'], fixture.assignmentId);
        expect(row['consent_version'], 4);
        expect(row['assignment_revision'], 11);
        expect(row['protocol_revision'], 5);
        expect(row['instrument_revision'], 9);
        expect(
          row['instrument_checksum_sha256'],
          run.instrument.checksumSha256,
        );
        expect(row['scoring_rule_version'], 'normalized-score-v1');
        expect(row['database_schema_version'], fixture.database.schemaVersion);
        expect(row.keys, hasLength(30));
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'a new repository resumes the same run without rewriting time or revision',
      () async {
        await fixture.start();
        final before = await fixture.storedRun();
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 1),
        );
        final result = await fixture.newRepository().start(
          MotivationMeasurementStart(
            ownerId: 'owner-a',
            permitId: fixture.permitId,
          ),
        );
        expect(result.startedAtUtc, participationStart);
        expect(await fixture.storedRun(), before);
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test('missing current issuer authority cannot create a run', () async {
      fixture.participation.documents.available = false;
      await expectLater(fixture.start(), denied());
      await fixture.expectArtifacts(runs: 0, responses: 0);
    });

    test('a forged Ed25519 collect permit cannot create a run', () async {
      fixture.participation.operations.current = participationOperation(
        corruptSignature: true,
      );
      await expectLater(fixture.start(), denied());
      await fixture.expectArtifacts(runs: 0, responses: 0);
    });

    test('unavailable trusted research time cannot create a run', () async {
      fixture.participation.clock.available = false;
      await expectLater(fixture.start(), denied());
      await fixture.expectArtifacts(runs: 0, responses: 0);
    });

    test(
      'constructor rejects a participation repository bound to another database',
      () async {
        final other = await MeasurementFixture.open();
        try {
          expect(
            () => DriftMotivationMeasurementRepository(
              fixture.database,
              participation: other.participation.repository,
              timing: fixture.timing,
              consentNowUtc: () => participationStart,
            ),
            throwsArgumentError,
          );
          await fixture.expectArtifacts(runs: 0, responses: 0);
          await other.expectArtifacts(runs: 0, responses: 0);
        } finally {
          await other.database.close();
        }
      },
    );

    test(
      'unavailable timing never counts as proof that baseline is unexposed',
      () async {
        await fixture.start();
        await expectLater(
          fixture.answer(),
          denied(ResearchCaptureReason.timingUnavailable),
        );
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'baseline derives ordinal and score from the catalog without closing the run',
      () async {
        final run = await fixture.baseline();
        expect(run.responses, hasLength(1));
        expect(run.responses.single.responseCode, 'high');
        expect(run.responses.single.ordinalValue, 1);
        expect(run.responses.single.answeredAtUtc, participationStart);
        expect(run.responses.single.localRevision, 1);
        expect(run.score(MotivationTimepoint.baseline), 100);
        expect(run.score(MotivationTimepoint.post), isNull);
        expect(run.state, MotivationMeasurementRunState.started);
        expect(run.closedAtUtc, isNull);
        expect(run.localRevision, 2);
        final response = (await fixture.storedResponses()).single;
        expect(response.keys, hasLength(9));
        expect(response['ordinal_value'], 1);
        await fixture.expectArtifacts(runs: 1, responses: 1);
      },
    );

    for (final invalid in [
      (item: 'unknown-item', code: 'high'),
      (item: 'synthetic-baseline', code: 'free text answer'),
    ]) {
      test(
        'unknown catalog item or response code creates no answer ${invalid.item}',
        () async {
          await fixture.start();
          fixture.before();
          await expectLater(
            () => fixture.answer(item: invalid.item, code: invalid.code),
            denied(ResearchCaptureReason.invalidInput),
          );
          await fixture.expectArtifacts(runs: 1, responses: 0);
        },
      );
    }

    test('known exposure prevents a new baseline response', () async {
      await fixture.start();
      fixture.exposed();
      fixture.participation.clock.now = participationStart.add(
        const Duration(minutes: 3),
      );
      await expectLater(
        fixture.answer(),
        denied(ResearchCaptureReason.outsideWindow),
      );
      await fixture.expectArtifacts(runs: 1, responses: 0);
    });

    test(
      'timing facts for another cycle cannot authorize a response',
      () async {
        await fixture.start();
        fixture.timing.facts = MotivationBeforeExposure(
          ownerId: 'owner-a',
          runId: 'different-run',
          permitId: fixture.permitId,
          assignmentId: fixture.assignmentId,
        );
        await expectLater(
          fixture.answer(),
          denied(ResearchCaptureReason.identityConflict),
        );
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'exposure appearing after the answer insert rolls back answer and revision',
      () async {
        await fixture.start();
        fixture.before();
        final before = await fixture.storedRun();
        queries.afterResponseWrite = () async {
          fixture.participation.clock.now = participationStart.add(
            const Duration(minutes: 3),
          );
          fixture.exposed();
        };
        await expectLater(fixture.answer(), denied());
        expect(queries.didResponseWrite, isTrue);
        expect(await fixture.storedRun(), before);
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'exact response replay preserves the original answer time and both revisions',
      () async {
        final first = await fixture.baseline();
        final beforeRun = await fixture.storedRun();
        final beforeResponses = await fixture.storedResponses();
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 1),
        );
        final replay = await fixture.answer();
        expect(replay.responses.single.id, first.responses.single.id);
        expect(replay.responses.single.answeredAtUtc, participationStart);
        expect(await fixture.storedRun(), beforeRun);
        expect(await fixture.storedResponses(), beforeResponses);
      },
    );

    test(
      'changing an accepted response code is an immutable conflict',
      () async {
        await fixture.baseline();
        final before = await fixture.storedResponses();
        await expectLater(
          fixture.answer(code: 'low'),
          denied(ResearchCaptureReason.identityConflict),
        );
        expect(await fixture.storedResponses(), before);
        await fixture.expectArtifacts(runs: 1, responses: 1);
      },
    );

    for (final state in <MotivationIndexSessionState?>[
      null,
      MotivationIndexSessionState.active,
      MotivationIndexSessionState.abandoned,
    ]) {
      test(
        'post requires the canonical index to be completed ${state?.name ?? 'missing'}',
        () async {
          await fixture.baseline();
          fixture.exposed(state: state);
          fixture.participation.clock.now = participationStart.add(
            const Duration(minutes: 3),
          );
          await expectLater(
            fixture.answer(item: 'synthetic-post'),
            denied(ResearchCaptureReason.sessionUnavailable),
          );
          await fixture.expectArtifacts(runs: 1, responses: 1);
        },
      );
    }

    test('post accepts the inclusive thirty minute boundary', () async {
      await fixture.baseline();
      fixture.exposed();
      fixture.participation.clock.now = participationStart.add(
        const Duration(minutes: 33),
      );
      final run = await fixture.answer(item: 'synthetic-post', code: 'low');
      expect(run.state, MotivationMeasurementRunState.completed);
      expect(
        run.closedAtUtc,
        participationStart.add(const Duration(minutes: 33)),
      );
      expect(run.primaryAnalysisEligible, isTrue);
    });

    test(
      'post rejects one microsecond beyond the thirty minute boundary',
      () async {
        await fixture.baseline();
        fixture.exposed();
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 33, microseconds: 1),
        );
        await expectLater(
          fixture.answer(item: 'synthetic-post'),
          denied(ResearchCaptureReason.outsideWindow),
        );
        await fixture.expectArtifacts(runs: 1, responses: 1);
      },
    );

    test(
      'post expiry during the final timing read rolls back the inserted response',
      () async {
        await fixture.baseline();
        fixture.exposed();
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 33),
        );
        final before = await fixture.storedRun();
        queries.afterResponseWrite = () async {
          fixture.timing.afterNextRead = () async {
            fixture.participation.clock.now = participationStart.add(
              const Duration(minutes: 33, microseconds: 1),
            );
          };
        };
        await expectLater(
          fixture.answer(item: 'synthetic-post'),
          denied(ResearchCaptureReason.outsideWindow),
        );
        expect(fixture.timing.didFire, isTrue);
        expect(await fixture.storedRun(), before);
        await fixture.expectArtifacts(runs: 1, responses: 1);
      },
    );

    test(
      'a session starting before first exposure cannot authorize post',
      () async {
        await fixture.baseline();
        fixture.exposed(sessionStart: participationStart);
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 3),
        );
        await expectLater(
          fixture.answer(item: 'synthetic-post'),
          denied(ResearchCaptureReason.outsideWindow),
        );
        await fixture.expectArtifacts(runs: 1, responses: 1);
      },
    );

    test(
      'both valid forms complete one run using existing normalized scoring',
      () async {
        final run = await fixture.complete();
        expect(run.state, MotivationMeasurementRunState.completed);
        expect(run.responses, hasLength(2));
        expect(run.localRevision, 3);
        expect(
          run.closedAtUtc,
          participationStart.add(const Duration(minutes: 3)),
        );
        expect(run.score(MotivationTimepoint.baseline), 100);
        expect(run.score(MotivationTimepoint.post), 0);
        expect(run.primaryAnalysisEligible, isTrue);
        await fixture.expectArtifacts(runs: 1, responses: 2);
      },
    );

    test('caller completion cannot close an incomplete run', () async {
      await fixture.baseline();
      final before = await fixture.storedRun();
      await expectLater(
        fixture.close(MotivationMeasurementRunState.completed),
        denied(ResearchCaptureReason.identityConflict),
      );
      expect(await fixture.storedRun(), before);
    });

    test(
      'terminal close replay keeps the first close time and prevents another terminal state',
      () async {
        await fixture.start();
        final first = await fixture.close(
          MotivationMeasurementRunState.skipped,
        );
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 1),
        );
        final before = await fixture.storedRun();
        final replay = await fixture.close(
          MotivationMeasurementRunState.skipped,
        );
        expect(replay.closedAtUtc, first.closedAtUtc);
        expect(replay.localRevision, first.localRevision);
        await expectLater(
          fixture.close(MotivationMeasurementRunState.abandoned),
          denied(ResearchCaptureReason.identityConflict),
        );
        expect(await fixture.storedRun(), before);
      },
    );

    test(
      'historical exact replay after completion ignores the current new-answer window',
      () async {
        await fixture.complete();
        final before = await fixture.storedRun();
        final beforeResponses = await fixture.storedResponses();
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 45),
        );
        final replay = await fixture.answer(
          item: 'synthetic-post',
          code: 'low',
        );
        expect(replay.state, MotivationMeasurementRunState.completed);
        expect(await fixture.storedRun(), before);
        expect(await fixture.storedResponses(), beforeResponses);
        await expectLater(
          fixture.answer(item: 'synthetic-post', code: 'high'),
          denied(ResearchCaptureReason.identityConflict),
        );
      },
    );

    test('an inactive owner cannot create a run', () async {
      await expectLater(
        fixture.start(ownerId: 'owner-b'),
        denied(ResearchCaptureReason.ownerConflict),
      );
      await fixture.expectArtifacts(runs: 0, responses: 0);
    });

    test(
      'same instrument version with a different persisted checksum cannot resume',
      () async {
        await fixture.start();
        await fixture.database.customStatement(
          'UPDATE motivation_measurement_runs SET instrument_checksum_sha256 = ?',
          ['f' * 64],
        );
        await expectLater(
          fixture.start(),
          denied(ResearchCaptureReason.versionConflict),
        );
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'a newly signed permit payload cannot silently rewrite an existing run pin',
      () async {
        await fixture.start();
        final before = await fixture.storedRun();
        fixture.participation.use(
          participationPermit(
            revision: 2,
            expiresAtUtc: participationStart.add(const Duration(hours: 2)),
          ),
        );
        expect(await fixture.participation.importCurrent(), isTrue);
        await expectLater(
          fixture.start(),
          denied(ResearchCaptureReason.versionConflict),
        );
        expect(await fixture.storedRun(), before);
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'a persistent deletion intent fences collection from another repository instance',
      () async {
        await fixture.start();
        fixture.before();
        await fixture.participation.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'synthetic-measurement-deletion',
        );
        await expectLater(
          fixture.newRepository().record(
            MotivationResponse(
              ownerId: 'owner-a',
              runId: fixture.runId,
              itemId: 'synthetic-baseline',
              responseCode: 'high',
            ),
          ),
          denied(ResearchCaptureReason.ownerConflict),
        );
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'consent withdrawn after insert causes the whole answer transaction to roll back',
      () async {
        await fixture.start();
        fixture.before();
        final before = await fixture.storedRun();
        queries.afterResponseWrite = () => fixture.participation.withdraw();
        await expectLater(fixture.answer(), denied());
        expect(queries.didResponseWrite, isTrue);
        expect(await fixture.storedRun(), before);
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'owner change during final timing read cannot commit a response',
      () async {
        await fixture.start();
        fixture.before();
        final before = await fixture.storedRun();
        queries.afterResponseWrite = () async {
          fixture.timing.afterNextRead = () async {
            await fixture.database.customStatement(
              "UPDATE local_owners SET is_active = 0 WHERE id = 'owner-a'",
            );
            await fixture.database.customStatement(
              "UPDATE local_owners SET is_active = 1 WHERE id = 'owner-b'",
            );
          };
        };
        await expectLater(
          fixture.answer(),
          denied(ResearchCaptureReason.ownerConflict),
        );
        expect(fixture.timing.didFire, isTrue);
        expect(await fixture.storedRun(), before);
        expect(
          (await fixture.database
                  .customSelect(
                    "SELECT id FROM local_owners WHERE is_active = 1",
                  )
                  .getSingle())
              .read<String>('id'),
          'owner-a',
        );
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'actual Ed25519 expiry after final authorization and a local read rolls back response',
      () async {
        fixture.participation.operations.current = participationOperation(
          expiresAtUtc: participationStart.add(const Duration(minutes: 10)),
        );
        await fixture.start();
        fixture.before();
        final before = await fixture.storedRun();
        fixture.participation.states.onRead = (_) async {
          if (queries.didResponseWrite) queries.readArmed = true;
        };
        queries.afterArmedRead = () async {
          fixture.participation.clock.now = participationStart.add(
            const Duration(minutes: 10),
          );
        };
        await expectLater(
          fixture.answer(),
          denied(ResearchCaptureReason.expiredPermit),
        );
        expect(queries.didRead, isTrue);
        expect(
          fixture.participation.clock.now.isBefore(
            fixture.participation.current.expiresAtUtc,
          ),
          isTrue,
        );
        expect(await fixture.storedRun(), before);
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'P256 expiry after final authorization and a local read rolls back response',
      () async {
        await fixture.start();
        fixture.before();
        final before = await fixture.storedRun();
        fixture.participation.states.onRead = (_) async {
          if (queries.didResponseWrite) queries.readArmed = true;
        };
        queries.afterArmedRead = () async {
          fixture.participation.clock.now =
              fixture.participation.current.expiresAtUtc;
        };
        await expectLater(
          fixture.answer(),
          denied(ResearchCaptureReason.expiredPermit),
        );
        expect(queries.didRead, isTrue);
        expect(await fixture.storedRun(), before);
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'SQL failure after response insert cannot leave an orphan answer or revision',
      () async {
        await fixture.start();
        fixture.before();
        final before = await fixture.storedRun();
        await fixture.database.customStatement(
          "CREATE TEMP TRIGGER fail_measurement_update BEFORE UPDATE ON motivation_measurement_runs BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
        );
        await expectLater(fixture.answer(), throwsA(anything));
        expect(queries.didResponseWrite, isTrue);
        expect(await fixture.storedRun(), before);
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'issuer authority lost after run insert rolls the new run back',
      () async {
        queries.afterRunWrite = () async {
          fixture.participation.documents.available = false;
        };
        await expectLater(fixture.start(), denied());
        expect(queries.didRunWrite, isTrue);
        await fixture.expectArtifacts(runs: 0, responses: 0);
      },
    );

    test(
      'load returns historical facts without granting collection when authority is unavailable',
      () async {
        await fixture.baseline();
        fixture.participation.documents.available = false;
        fixture.participation.clock.available = false;
        fixture.timing.facts = null;
        final run = await fixture.repository.load('owner-a', fixture.runId);
        expect(run, isNotNull);
        expect(run!.responses, hasLength(1));
        expect(run.timing, isNull);
        expect(run.primaryAnalysisEligible, isFalse);
        await expectLater(fixture.answer(), denied());
        await fixture.expectArtifacts(runs: 1, responses: 1);
      },
    );

    for (final futureField in ['answer', 'closure']) {
      test(
        'load preserves future $futureField history without eligible timing',
        () async {
          if (futureField == 'answer') {
            await fixture.baseline();
            await fixture.database.customStatement(
              'UPDATE motivation_responses SET answered_at_utc_ms = ?',
              [
                fixture.participation.clock.now
                    .add(const Duration(minutes: 1))
                    .millisecondsSinceEpoch,
              ],
            );
          } else {
            await fixture.complete();
            await fixture.database.customStatement(
              'UPDATE motivation_measurement_runs SET closed_at_utc_ms = ?',
              [
                fixture.participation.clock.now
                    .add(const Duration(minutes: 1))
                    .millisecondsSinceEpoch,
              ],
            );
          }
          final beforeRun = await fixture.storedRun();
          final beforeResponses = await fixture.storedResponses();
          final run = await fixture.repository.load('owner-a', fixture.runId);
          expect(run, isNotNull);
          expect(run!.timing, isNull);
          expect(run.primaryAnalysisEligible, isFalse);
          expect(await fixture.storedRun(), beforeRun);
          expect(await fixture.storedResponses(), beforeResponses);
        },
      );
    }

    test('a skipped close replay rejects a future stored closure', () async {
      await fixture.start();
      await fixture.close(MotivationMeasurementRunState.skipped);
      await fixture.database.customStatement(
        'UPDATE motivation_measurement_runs SET closed_at_utc_ms = ?',
        [
          fixture.participation.clock.now
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        ],
      );
      final before = await fixture.storedRun();
      await expectLater(
        fixture.close(MotivationMeasurementRunState.skipped),
        denied(ResearchCaptureReason.outsideWindow),
      );
      expect(await fixture.storedRun(), before);
      await fixture.expectArtifacts(runs: 1, responses: 0);
    });

    test(
      'withdrawal persists canonical deny even while trusted research time is unavailable',
      () async {
        await fixture.start();
        final before = await fixture.storedRun();
        fixture.privacyNow = participationStart.add(const Duration(minutes: 1));
        fixture.participation.clock.available = false;
        await expectLater(
          fixture.close(MotivationMeasurementRunState.withdrawn),
          denied(),
        );
        final consent = await fixture.participation.consent.load(
          ownerId: 'owner-a',
          version: 4,
        );
        expect(consent.accepted, isFalse);
        expect(consent.withdrawnAtUtc, fixture.privacyNow);
        expect(await fixture.storedRun(), before);
        fixture.participation.clock.available = true;
        fixture.participation.clock.now = fixture.privacyNow;
        final retried = await fixture.close(
          MotivationMeasurementRunState.withdrawn,
        );
        expect(retried.state, MotivationMeasurementRunState.withdrawn);
        expect(retried.closedAtUtc, fixture.privacyNow);
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'run SQL failure cannot restore canonical consent after withdrawal',
      () async {
        await fixture.start();
        final signedBefore = await fixture.participation.stored();
        await fixture.database.customStatement(
          "CREATE TEMP TRIGGER fail_withdrawal BEFORE UPDATE ON motivation_measurement_runs WHEN NEW.state = 'withdrawn' BEGIN SELECT RAISE(ABORT, 'synthetic withdrawal failure'); END",
        );
        await expectLater(
          fixture.close(MotivationMeasurementRunState.withdrawn),
          throwsA(anything),
        );
        final consent = await fixture.participation.consent.load(
          ownerId: 'owner-a',
          version: 4,
        );
        expect(consent.accepted, isFalse);
        expect((await fixture.storedRun())['state'], 'started');
        expect(await fixture.participation.stored(), signedBefore);
        await fixture.database.customStatement('DROP TRIGGER fail_withdrawal');
        expect(
          (await fixture.close(MotivationMeasurementRunState.withdrawn)).state,
          MotivationMeasurementRunState.withdrawn,
        );
        await fixture.expectArtifacts(runs: 1, responses: 0);
      },
    );

    test(
      'future run history cannot undo the separately committed consent withdrawal',
      () async {
        await fixture.baseline();
        await fixture.database.customStatement(
          'UPDATE motivation_responses SET answered_at_utc_ms = ?',
          [
            participationStart
                .add(const Duration(minutes: 1))
                .millisecondsSinceEpoch,
          ],
        );
        final beforeRun = await fixture.storedRun();
        final beforeResponses = await fixture.storedResponses();
        await expectLater(
          fixture.close(MotivationMeasurementRunState.withdrawn),
          denied(ResearchCaptureReason.outsideWindow),
        );
        final consent = await fixture.participation.consent.load(
          ownerId: 'owner-a',
          version: 4,
        );
        expect(consent.accepted, isFalse);
        expect(await fixture.storedRun(), beforeRun);
        expect(await fixture.storedResponses(), beforeResponses);
      },
    );

    test(
      'withdrawal narrows an existing run without collect authority or a forged permit change',
      () async {
        await fixture.baseline();
        final signedBefore = await fixture.participation.stored();
        fixture.participation.operations.available = false;
        fixture.participation.documents.available = false;
        final run = await fixture.close(
          MotivationMeasurementRunState.withdrawn,
        );
        final before = await fixture.storedRun();
        expect(run.state, MotivationMeasurementRunState.withdrawn);
        expect(await fixture.participation.stored(), signedBefore);
        final replay = await fixture.close(
          MotivationMeasurementRunState.withdrawn,
        );
        expect(replay.localRevision, run.localRevision);
        expect(await fixture.storedRun(), before);
        await expectLater(
          fixture.answer(),
          denied(ResearchCaptureReason.withdrawn),
        );
        await fixture.expectArtifacts(runs: 1, responses: 1);
      },
    );
  });

  test(
    'baseline older than twenty four hours is preserved while primary eligibility stays false',
    () async {
      final fixture = await MeasurementFixture.open(longLived: true);
      try {
        await fixture.baseline();
        final baselineBefore = (await fixture.storedResponses()).single;
        final exposure = participationStart.add(const Duration(hours: 25));
        final completion = exposure.add(const Duration(minutes: 2));
        fixture.exposed(exposure: exposure, completion: completion);
        fixture.participation.clock.now = completion;
        final run = await fixture.answer(item: 'synthetic-post', code: 'low');
        expect(run.state, MotivationMeasurementRunState.completed);
        expect(run.primaryAnalysisEligible, isFalse);
        expect(
          (await fixture.storedResponses()).firstWhere(
            (row) => row['item_id'] == 'synthetic-baseline',
          ),
          baselineBefore,
        );
        expect(
          run.responses
              .firstWhere((response) => response.itemId == 'synthetic-baseline')
              .answeredAtUtc,
          participationStart,
        );
        await fixture.expectArtifacts(runs: 1, responses: 2);
      } finally {
        await fixture.database.close();
      }
    },
  );
}
