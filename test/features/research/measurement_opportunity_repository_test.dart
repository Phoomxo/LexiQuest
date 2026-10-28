import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_timing_reader.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';

import '../../support/measurement_opportunity_harness.dart';

Matcher captureDenied([ResearchCaptureReason? reason]) => throwsA(
  reason == null
      ? isA<ResearchCaptureDenied>()
      : isA<ResearchCaptureDenied>().having(
          (error) => error.reason,
          'reason',
          reason,
        ),
);

void main() {
  test(
    'opportunity and Presented identities retain the archived canonical tuples',
    () {
      expect(
        measurementOpportunityId(
          ownerId: 'owner-a',
          measurementRunId: 'run-a',
          permitId: 'permit-a',
          entryAttemptId: opportunityEntryId,
        ),
        'opportunity:9b49db4a3db6dcf64da09d8dd2ff3c795b91d32b96d2b304dc4526f2c06158ce',
      );
      expect(
        measurementPresentedIdentity('opportunity-a'),
        'research:dddc856b022478357c8abe6bed0273580cde9c0a5bb40a684d12f93fbb7991fd',
      );
    },
  );

  group('canonical measurement opportunity', () {
    late OpportunityFixture fixture;
    late OpportunityQueries queries;
    setUp(() async {
      queries = OpportunityQueries();
      fixture = await OpportunityFixture.open(queries: queries);
    });
    tearDown(() => fixture.database.close());

    test(
      'known unexposed differs from an unavailable or mismatched cycle',
      () async {
        expect(await fixture.facts(), isNull);
        await fixture.startRun();
        expect(await fixture.facts(), isA<MotivationBeforeExposure>());
        expect(
          await fixture.timing.read(
            ownerId: 'owner-a',
            runId: fixture.runId,
            permitId: 'wrong-permit',
            assignmentId: fixture.participation.current.assignmentId,
          ),
          isNull,
        );
        await fixture.expectArtifacts(opportunities: 0, events: 0);
      },
    );

    test(
      'open creates one local opportunity without exposure or learning side effects',
      () async {
        await fixture.startRun();
        final result = await fixture.openOpportunity();
        final row = await fixture.storedOpportunity();
        expect(result.id, fixture.opportunityId);
        expect(result.localRevision, 1);
        expect(result.presentation, isNull);
        expect(result.indexLink, isNull);
        expect(row.keys, hasLength(15));
        expect(row['permit_id'], fixture.participation.current.id);
        expect(row['assigned_treatment'], 'standard');
        expect(row['effective_presentation'], 'standard');
        expect(await fixture.facts(), isA<MotivationBeforeExposure>());
        await fixture.expectArtifacts(opportunities: 1, events: 0, sessions: 0);
      },
    );

    test(
      'open replay preserves the first time and revision across repository instances',
      () async {
        await fixture.startRun();
        await fixture.openOpportunity();
        final before = await fixture.storedOpportunity();
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 1),
        );
        final result = await fixture.newRepository().open(
          ownerId: 'owner-a',
          measurementRunId: fixture.runId,
          entryAttemptId: opportunityEntryId,
          effectivePresentation: TodayExperiencePresentation.standard,
        );
        expect(result.openedAtUtc, participationStart);
        expect(await fixture.storedOpportunity(), before);
        await fixture.expectArtifacts(opportunities: 1, events: 0);
      },
    );

    test('the same entry cannot change its persisted presentation', () async {
      await fixture.startRun();
      await fixture.openOpportunity();
      final before = await fixture.storedOpportunity();
      await expectLater(
        () => fixture.openOpportunity(
          presentation: TodayExperiencePresentation.adventure,
        ),
        captureDenied(ResearchCaptureReason.identityConflict),
      );
      expect(await fixture.storedOpportunity(), before);
    });

    test('an invalid entry UUID creates no opportunity', () async {
      await fixture.startRun();
      await expectLater(
        () => fixture.openOpportunity(entryId: 'not-a-uuid'),
        throwsFormatException,
      );
      await fixture.expectArtifacts(opportunities: 0, events: 0);
    });

    test(
      'constructor rejects other-database timing and measurement dependencies',
      () async {
        final other = await OpportunityFixture.open();
        try {
          expect(
            () => DriftMeasurementOpportunityRepository(
              fixture.database,
              measurements: other.measurements,
              timing: other.timing,
            ),
            throwsArgumentError,
          );
          expect(
            () => DriftMeasurementOpportunityRepository(
              fixture.database,
              measurements: fixture.measurements,
              timing: DriftMotivationMeasurementTimingReader(other.database),
            ),
            throwsArgumentError,
          );
          await fixture.expectArtifacts(opportunities: 0, events: 0);
        } finally {
          await other.database.close();
        }
      },
    );

    test(
      'Presented requires a complete baseline and keeps an already opened opportunity',
      () async {
        await fixture.startRun();
        await fixture.openOpportunity();
        final before = await fixture.storedOpportunity();
        await expectLater(
          () => fixture.present(),
          captureDenied(ResearchCaptureReason.incomplete),
        );
        expect(await fixture.storedOpportunity(), before);
        await fixture.expectArtifacts(opportunities: 1, events: 0);
      },
    );

    test(
      'Presented persists exactly the approved envelope and four-field payload',
      () async {
        final at = participationStart.add(const Duration(milliseconds: 123));
        final result = await fixture.ready(at: at);
        final event = (await fixture.events()).single;
        expect(result.presentation!.occurredAtUtc, at);
        expect(event.keys, hasLength(22));
        expect(event['event_type'], 'TodayExperiencePresented');
        expect(event['event_version'], 1);
        expect(
          event['event_id'],
          researchEventId(measurementPresentedIdentity(result.id), at),
        );
        expect(
          event['idempotency_key'],
          measurementPresentedIdentity(result.id),
        );
        expect(event['occurred_at_utc'], at.millisecondsSinceEpoch ~/ 1000);
        expect(event['recorded_at_utc'], event['occurred_at_utc']);
        expect(event['actor_identity'], 'owner-a');
        expect(event['owner_id'], 'owner-a');
        expect(event['aggregate_type'], 'MeasurementOpportunity');
        expect(event['aggregate_id'], result.id);
        expect(event['correlation_id'], result.id);
        expect(event['tenant_context_json'], isNull);
        expect(event['causation_id'], isNull);
        expect(event['provider_provenance_json'], isNull);
        expect(event['privacy_classification'], 'ownerOnly');
        expect(event['content_revision'], 'content-v1');
        expect(event['policy_version'], 'evidence-v1');
        expect(event['app_version'], 'synthetic-app');
        expect(event['build_id'], 'synthetic-build');
        expect(jsonDecode(event['payload_json']! as String), {
          'assignedTreatment': 'standard',
          'effectivePresentation': 'standard',
          'entryAttemptId': opportunityEntryId,
          'catalogVersion': 'catalog-v1',
        });
        expect(jsonDecode(event['consent_context_json']! as String), {
          'researchConsentVersion': 4,
          'aiConsentGranted': false,
          'voiceConsentGranted': false,
          'socialConsentGranted': false,
        });
        expect(jsonDecode(event['experiment_context_json']! as String), {
          'experimentId': 'synthetic-experiment',
          'variantId': 'standard',
          'assignedAtUtc': participationStart.toIso8601String(),
        });
        final facts = await fixture.facts() as MotivationAfterExposure;
        expect(facts.firstExposureAtUtc, at);
        expect(facts.indexSession, isNull);
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 0);
      },
    );

    test(
      'Presented replay preserves the event, occurrence and opportunity revision',
      () async {
        await fixture.ready();
        final beforeOpportunity = await fixture.storedOpportunity();
        final beforeEvents = await fixture.events();
        fixture.participation.clock.now = participationStart.add(
          const Duration(minutes: 1),
        );
        await fixture.newRepository().recordPresented(
          'owner-a',
          fixture.opportunityId,
        );
        expect(await fixture.storedOpportunity(), beforeOpportunity);
        expect(await fixture.events(), beforeEvents);
      },
    );

    for (final mutation in ['payload', 'millisecond', 'unlinked']) {
      test(
        'a $mutation inconsistency is unavailable rather than unexposed',
        () async {
          await fixture.ready(
            at: participationStart.add(const Duration(milliseconds: 123)),
          );
          if (mutation == 'payload') {
            final event = (await fixture.events()).single;
            final payload =
                jsonDecode(event['payload_json']! as String)
                    as Map<String, dynamic>;
            payload['freeText'] = 'synthetic forbidden field';
            await fixture.database.customStatement(
              'UPDATE events_v2 SET payload_json = ?',
              [jsonEncode(payload)],
            );
          } else if (mutation == 'millisecond') {
            await fixture.database.customStatement(
              'UPDATE measurement_opportunities SET presented_at_utc_ms = presented_at_utc_ms + 1',
            );
          } else {
            await fixture.database.customStatement(
              'UPDATE measurement_opportunities SET presented_event_id = NULL, presented_at_utc_ms = NULL',
            );
          }
          expect(await fixture.facts(), isNull);
        },
      );
    }

    test(
      'current authority lost after event insertion rolls event and projection back',
      () async {
        await fixture.baseline();
        await fixture.openOpportunity();
        final before = await fixture.storedOpportunity();
        queries.afterEventWrite = () async {
          fixture.participation.documents.available = false;
        };
        await expectLater(() => fixture.present(), captureDenied());
        expect(queries.didEventWrite, isTrue);
        expect(await fixture.storedOpportunity(), before);
        await fixture.expectArtifacts(opportunities: 1, events: 0);
      },
    );

    for (final authority in ['Ed25519', 'P256']) {
      test(
        '$authority expiry after final authorization and local read rolls Presented back',
        () async {
          await fixture.baseline();
          await fixture.openOpportunity();
          final before = await fixture.storedOpportunity();
          final expiry = authority == 'Ed25519'
              ? participationStart.add(const Duration(minutes: 5))
              : fixture.participation.current.expiresAtUtc;
          if (authority == 'Ed25519') {
            fixture.participation.operations.current = participationOperation(
              expiresAtUtc: expiry,
            );
          }
          fixture.participation.states.onRead = (_) async {
            if (queries.didEventWrite) queries.readArmed = true;
          };
          queries.afterArmedRead = () async {
            fixture.participation.clock.now = expiry;
          };
          await expectLater(
            () => fixture.present(),
            captureDenied(ResearchCaptureReason.expiredPermit),
          );
          expect(queries.didRead, isTrue);
          if (authority == 'Ed25519') {
            expect(
              expiry.isBefore(fixture.participation.current.expiresAtUtc),
              isTrue,
            );
          }
          expect(await fixture.storedOpportunity(), before);
          await fixture.expectArtifacts(opportunities: 1, events: 0);
        },
      );
    }

    test(
      'withdrawal after event insertion cannot leave a research exposure',
      () async {
        await fixture.baseline();
        await fixture.openOpportunity();
        final before = await fixture.storedOpportunity();
        queries.afterEventWrite = () => fixture.participation.withdraw();
        await expectLater(() => fixture.present(), captureDenied());
        expect(await fixture.storedOpportunity(), before);
        await fixture.expectArtifacts(opportunities: 1, events: 0);
      },
    );

    test('SQL projection failure rolls its new event back atomically', () async {
      await fixture.baseline();
      await fixture.openOpportunity();
      final before = await fixture.storedOpportunity();
      await fixture.database.customStatement(
        "CREATE TEMP TRIGGER fail_presented BEFORE UPDATE ON measurement_opportunities BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await expectLater(() => fixture.present(), throwsA(anything));
      expect(queries.didEventWrite, isTrue);
      expect(await fixture.storedOpportunity(), before);
      await fixture.expectArtifacts(opportunities: 1, events: 0);
    });

    test(
      'the first canonical accepted start becomes the immutable active index',
      () async {
        await fixture.ready();
        await fixture.accept();
        final stored = await fixture.storedOpportunity();
        expect(stored['learning_session_id'], 'first-session');
        expect(stored['is_index_session'], 1);
        final facts = await fixture.facts() as MotivationAfterExposure;
        expect(facts.indexSession!.id, 'first-session');
        expect(facts.indexSession!.state, MotivationIndexSessionState.active);
        expect(facts.indexSession!.completedAtUtc, isNull);
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 1);
      },
    );

    test(
      'canonical completion and retry retain the original index end and revision',
      () async {
        await fixture.ready();
        await fixture.accept();
        await fixture.finish();
        final before = await fixture.storedOpportunity();
        final originalEnd = participationStart.add(const Duration(minutes: 3));
        expect(before['closed_at_utc_ms'], originalEnd.millisecondsSinceEpoch);
        await fixture.finish(
          at: participationStart.add(const Duration(minutes: 4)),
        );
        expect(await fixture.storedOpportunity(), before);
        final facts = await fixture.facts() as MotivationAfterExposure;
        expect(facts.indexSession!.completedAtUtc, originalEnd);
        await fixture.expectArtifacts(
          opportunities: 1,
          events: 1,
          sessions: 1,
          ordinaryAchievementSessionId: 'first-session',
        );
      },
    );

    for (final firstState in ['active', 'abandoned']) {
      test(
        'a later completed session never replaces the $firstState first index',
        () async {
          await fixture.ready();
          await fixture.accept();
          if (firstState == 'abandoned') {
            await fixture.database.customStatement(
              "UPDATE learning_sessions SET state = 'abandoned' WHERE id = 'first-session'",
            );
          }
          await fixture.accept(
            id: 'later-session',
            at: participationStart.add(const Duration(minutes: 3)),
          );
          await fixture.finish(
            id: 'later-session',
            at: participationStart.add(const Duration(minutes: 4)),
          );
          final facts = await fixture.facts() as MotivationAfterExposure;
          expect(facts.indexSession!.id, 'first-session');
          expect(facts.indexSession!.state.name, firstState);
          expect(facts.indexSession!.completedAtUtc, isNull);
          expect(
            (await fixture.storedOpportunity())['learning_session_id'],
            'first-session',
          );
        },
      );
    }

    test(
      'denied first acceptance commits learning without research writes and leaves a permanent gap',
      () async {
        await fixture.ready();
        final before = await fixture.storedOpportunity();
        fixture.participation.documents.available = false;
        await fixture.accept();
        expect((await fixture.storedSession())['state'], 'active');
        expect(await fixture.storedOpportunity(), before);
        fixture.participation.documents.available = true;
        await fixture.accept(
          id: 'later-session',
          at: participationStart.add(const Duration(minutes: 3)),
        );
        expect(await fixture.facts(), isNull);
        expect(await fixture.storedOpportunity(), before);
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 2);
      },
    );

    test(
      'matching start replay cannot backfill a denied first acceptance',
      () async {
        await fixture.ready();
        fixture.participation.documents.available = false;
        await fixture.accept();
        fixture.participation.documents.available = true;
        await fixture.learning.startSession(
          fixture.session(
            at: participationStart.add(const Duration(minutes: 2)),
          ),
        );
        expect(
          (await fixture.storedOpportunity())['learning_session_id'],
          isNull,
        );
        expect(await fixture.facts(), isNull);
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 1);
      },
    );

    test(
      'synced evidence containers are excluded from canonical index candidates',
      () async {
        await fixture.ready();
        await fixture.rawSession(
          id: 'synced',
          at: participationStart.add(const Duration(minutes: 1)),
          activity: 'syncedEvidence',
          state: 'syncedEvidence',
        );
        await fixture.accept();
        final facts = await fixture.facts() as MotivationAfterExposure;
        expect(facts.indexSession!.id, 'first-session');
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 2);
      },
    );

    for (final partial in [
      (activity: 'quiz', state: 'syncedEvidence', minute: 1),
      (activity: 'syncedEvidence', state: 'active', minute: 2),
    ]) {
      test(
        'a partial synced marker ${partial.activity}/${partial.state} cannot hide an earlier or tied candidate',
        () async {
          await fixture.ready();
          final before = await fixture.storedOpportunity();
          await fixture.rawSession(
            id: 'partial-synced-marker',
            at: participationStart.add(Duration(minutes: partial.minute)),
            activity: partial.activity,
            state: partial.state,
          );
          await fixture.accept();
          expect(await fixture.facts(), isNull);
          expect(await fixture.storedOpportunity(), before);
          expect((await fixture.storedSession())['state'], 'active');
          await fixture.expectArtifacts(
            opportunities: 1,
            events: 1,
            sessions: 2,
          );
        },
      );
    }

    for (final offset in [1, 2]) {
      test(
        'an unlinked local-looking candidate at minute $offset cannot be replaced',
        () async {
          await fixture.ready();
          await fixture.rawSession(
            id: 'ambiguous-rehomed-guest',
            at: participationStart.add(Duration(minutes: offset)),
          );
          await fixture.accept();
          expect(await fixture.facts(), isNull);
          expect(
            (await fixture.storedOpportunity())['learning_session_id'],
            isNull,
          );
          await fixture.expectArtifacts(
            opportunities: 1,
            events: 1,
            sessions: 2,
          );
        },
      );
    }

    test(
      'a missing canonical index is unavailable and cannot select a later session',
      () async {
        await fixture.ready();
        await fixture.accept();
        await fixture.database.customStatement('PRAGMA foreign_keys = OFF');
        await fixture.database.customStatement(
          "DELETE FROM learning_sessions WHERE id = 'first-session'",
        );
        await fixture.database.customStatement('PRAGMA foreign_keys = ON');
        await fixture.accept(
          id: 'later-session',
          at: participationStart.add(const Duration(minutes: 3)),
        );
        await fixture.finish(
          id: 'later-session',
          at: participationStart.add(const Duration(minutes: 4)),
        );
        expect(await fixture.facts(), isNull);
        expect(
          (await fixture.storedOpportunity())['learning_session_id'],
          'first-session',
        );
      },
    );

    test(
      'a failed research savepoint preserves the ordinary learning start',
      () async {
        await fixture.ready();
        final before = await fixture.storedOpportunity();
        await fixture.database.customStatement(
          "CREATE TEMP TRIGGER fail_link BEFORE UPDATE ON measurement_opportunities BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
        );
        await fixture.accept();
        expect((await fixture.storedSession())['state'], 'active');
        expect(await fixture.storedOpportunity(), before);
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 1);
      },
    );

    test(
      'canonical transaction rollback also removes the research index link',
      () async {
        await fixture.ready();
        final before = await fixture.storedOpportunity();
        await expectLater(
          () => fixture.database.transaction(() async {
            await fixture.accept();
            throw StateError('synthetic canonical failure');
          }),
          throwsStateError,
        );
        expect(await fixture.storedOpportunity(), before);
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 0);
      },
    );

    test(
      'completion research failure preserves canonical end and retry repairs only its projection',
      () async {
        await fixture.ready();
        await fixture.accept();
        await fixture.database.customStatement(
          "CREATE TEMP TRIGGER fail_close BEFORE UPDATE ON measurement_opportunities WHEN NEW.closed_at_utc_ms IS NOT NULL BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
        );
        await fixture.finish();
        final ended = participationStart.add(const Duration(minutes: 3));
        expect(
          (await fixture.storedSession())['ended_at_utc_ms'],
          ended.millisecondsSinceEpoch,
        );
        expect((await fixture.storedSession())['state'], 'completed');
        expect((await fixture.storedOpportunity())['closed_at_utc_ms'], isNull);
        await fixture.database.customStatement('DROP TRIGGER fail_close');
        await fixture.finish(
          at: participationStart.add(const Duration(minutes: 4)),
        );
        expect(
          (await fixture.storedOpportunity())['closed_at_utc_ms'],
          ended.millisecondsSinceEpoch,
        );
        await fixture.expectArtifacts(
          opportunities: 1,
          events: 1,
          sessions: 1,
          ordinaryAchievementSessionId: 'first-session',
        );
      },
    );

    test(
      'ordinary learning without a measurement run creates no research facts',
      () async {
        await fixture.accept();
        await fixture.finish();
        await fixture.expectArtifacts(
          opportunities: 0,
          events: 0,
          sessions: 1,
          ordinaryAchievementSessionId: 'first-session',
        );
        final runs = await fixture.database
            .customSelect(
              'SELECT COUNT(*) AS n FROM motivation_measurement_runs',
            )
            .getSingle();
        expect(runs.read<int>('n'), 0);
      },
    );

    test(
      'a persistent deletion fence blocks the sidecar while ordinary learning commits',
      () async {
        await fixture.ready();
        final before = await fixture.storedOpportunity();
        await fixture.participation.ownerWrites.beginDeletion(
          ownerId: 'owner-a',
          firebaseUid: 'uid-a',
          idempotencyKey: 'synthetic-delete',
        );
        await fixture.accept();
        expect((await fixture.storedSession())['state'], 'active');
        expect(await fixture.storedOpportunity(), before);
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 1);
      },
    );

    test(
      'an owner change after linking rolls back only the research savepoint',
      () async {
        await fixture.ready();
        final before = await fixture.storedOpportunity();
        var changedOwner = false;
        queries.afterOpportunityWrite = () async {
          changedOwner = true;
          await fixture.database.customStatement(
            "UPDATE local_owners SET is_active = CASE WHEN id = 'owner-b' THEN 1 ELSE 0 END",
          );
        };
        await fixture.accept();
        expect(await fixture.storedOpportunity(), before);
        expect((await fixture.storedSession())['state'], 'active');
        expect(changedOwner, isTrue);
        await fixture.expectArtifacts(opportunities: 1, events: 1, sessions: 1);
      },
    );

    for (final altered in ['response', 'permit hash']) {
      test(
        'the active-run boundary rejects callback changes to $altered facts',
        () async {
          await fixture.baseline();
          await fixture.openOpportunity();
          final before = await fixture.storedOpportunity();
          await expectLater(
            () => fixture.measurements.writeForActiveRun(
              ownerId: 'owner-a',
              runId: fixture.runId,
              write: (_) async {
                await fixture.database.customStatement(
                  'UPDATE measurement_opportunities SET local_revision = local_revision + 1',
                );
                if (altered == 'response') {
                  await fixture.database.customStatement(
                    "UPDATE motivation_responses SET response_code = 'low', ordinal_value = 0",
                  );
                } else {
                  await fixture.database.customStatement(
                    'UPDATE motivation_measurement_runs SET permit_payload_sha256 = ?',
                    ['f' * 64],
                  );
                }
                return 'changed';
              },
            ),
            captureDenied(),
          );
          expect(await fixture.storedOpportunity(), before);
          final run = await fixture.measurements.load('owner-a', fixture.runId);
          expect(run!.responses.single.responseCode, 'high');
          expect(
            run.permitPayloadSha256,
            fixture.participation.current.payloadSha256,
          );
        },
      );
    }

    test(
      'a failed final synchronous validator rolls callback writes back',
      () async {
        await fixture.baseline();
        await fixture.openOpportunity();
        final before = await fixture.storedOpportunity();
        await expectLater(
          () => fixture.measurements.writeForActiveRun(
            ownerId: 'owner-a',
            runId: fixture.runId,
            write: (_) async {
              await fixture.database.customStatement(
                'UPDATE measurement_opportunities SET local_revision = local_revision + 1',
              );
              return 'callback result';
            },
            validate: (_, _) => throw StateError('synthetic final rejection'),
          ),
          throwsStateError,
        );
        expect(await fixture.storedOpportunity(), before);
      },
    );
  });

  test(
    'a nonparticipant can start and finish ordinary learning without research rows',
    () async {
      final fixture = await OpportunityFixture.open(admitParticipant: false);
      try {
        await fixture.accept();
        await fixture.finish();
        await fixture.expectArtifacts(
          opportunities: 0,
          events: 0,
          sessions: 1,
          ordinaryAchievementSessionId: 'first-session',
        );
        for (final table in [
          'research_consents',
          'experiment_assignments',
          'research_participation_permits',
          'motivation_measurement_runs',
          'motivation_responses',
        ]) {
          final row = await fixture.database
              .customSelect('SELECT COUNT(*) AS n FROM $table')
              .getSingle();
          expect(row.read<int>('n'), 0, reason: table);
        }
      } finally {
        await fixture.database.close();
      }
    },
  );

  for (final lateMicroseconds in [0, 1]) {
    test(
      'the baseline exposure boundary respects twenty four hours plus $lateMicroseconds microseconds',
      () async {
        final fixture = await OpportunityFixture.open(longLived: true);
        try {
          await fixture.baseline();
          fixture.participation.clock.now = participationStart.add(
            Duration(hours: 24, microseconds: lateMicroseconds),
          );
          await fixture.openOpportunity();
          if (lateMicroseconds == 0) {
            await fixture.present();
            await fixture.expectArtifacts(opportunities: 1, events: 1);
          } else {
            await expectLater(
              () => fixture.present(),
              captureDenied(ResearchCaptureReason.outsideWindow),
            );
            await fixture.expectArtifacts(opportunities: 1, events: 0);
          }
        } finally {
          await fixture.database.close();
        }
      },
    );
  }

  test(
    'restart reloads the same committed exposure, index and canonical completion',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-opportunity-',
      );
      final resolvedDirectory = directory.resolveSymbolicLinksSync();
      final file = File(
        '$resolvedDirectory${Platform.pathSeparator}opportunity.sqlite',
      );
      OpportunityFixture? active;
      try {
        active = await OpportunityFixture.open(
          database: AppDatabase(NativeDatabase(file)),
        );
        await active.ready();
        await active.accept();
        await active.finish();
        final beforeOpportunity = await active.storedOpportunity();
        final beforeEvents = await active.events();
        await active.database.close();
        active = null;
        active = await OpportunityFixture.open(
          database: AppDatabase(NativeDatabase(file)),
          seed: false,
        );
        active.participation.clock.now = participationStart.add(
          const Duration(minutes: 4),
        );
        expect(await active.storedOpportunity(), beforeOpportunity);
        expect(await active.events(), beforeEvents);
        final facts = await active.facts() as MotivationAfterExposure;
        expect(facts.indexSession!.id, 'first-session');
        expect(
          facts.indexSession!.completedAtUtc,
          participationStart.add(const Duration(minutes: 3)),
        );
        await active.expectArtifacts(
          opportunities: 1,
          events: 1,
          sessions: 1,
          ordinaryAchievementSessionId: 'first-session',
        );
      } finally {
        await active?.database.close();
        final resolvedTarget = directory.resolveSymbolicLinksSync();
        if (resolvedTarget != resolvedDirectory ||
            !file.absolute.path.startsWith(
              '$resolvedDirectory${Platform.pathSeparator}',
            )) {
          throw StateError(
            'Temporary database cleanup escaped its owned directory',
          );
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
