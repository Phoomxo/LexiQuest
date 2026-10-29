import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import '../../support/measurement_opportunity_harness.dart';

void main() {
  late OpportunityFixture fixture;
  setUp(() async {
    fixture = await OpportunityFixture.open();
    await fixture.ready();
  });
  tearDown(() => fixture.database.close());

  Future<MeasurementOpportunity> prepare(int attempt) async {
    final current = (await fixture.repository.load(
      'owner-a',
      fixture.opportunityId,
    ))!;
    return fixture.repository.preparePresentationChange(
      'owner-a',
      fixture.opportunityId,
      attemptId:
          '10000000-0000-4000-8000-${attempt.toString().padLeft(12, '0')}',
      expectedRevision: current.localRevision,
      target:
          current.currentPresentation == TodayExperiencePresentation.standard
          ? TodayExperiencePresentation.adventure
          : TodayExperiencePresentation.standard,
      stillCurrent: () => true,
    );
  }

  Future<MeasurementOpportunity> commit(PendingPresentationChange receipt) =>
      fixture.repository.commitPresentationChange(
        'owner-a',
        fixture.opportunityId,
        receipt: receipt,
        stillVisible: () => true,
      );

  test(
    'prepare is durable uncertainty, not an exposure or a counter',
    () async {
      final before = await fixture.events();
      final prepared = await prepare(1);
      final opportunity = prepared;
      expect(opportunity.pendingPresentationChange, isNotNull);
      expect(opportunity.lastSwitchOrdinal, 0);
      expect(opportunity.suppressedSwitchCount, 0);
      expect(
        opportunity.currentPresentation,
        TodayExperiencePresentation.standard,
      );
      expect(await fixture.facts(), isNull);
      expect(await fixture.events(), before);
      expect(
        (await fixture.newRepository().load(
          'owner-a',
          fixture.opportunityId,
        ))!.pendingPresentationChange!.toJson(),
        opportunity.pendingPresentationChange!.toJson(),
      );
      final retry = await fixture.repository.preparePresentationChange(
        'owner-a',
        fixture.opportunityId,
        attemptId: opportunity.pendingPresentationChange!.attemptId,
        expectedRevision: opportunity.pendingPresentationChange!.baseRevision,
        target: TodayExperiencePresentation.adventure,
        stillCurrent: () => true,
      );
      expect(retry.localRevision, opportunity.localRevision);
      expect(
        retry.pendingPresentationChange!.toJson(),
        opportunity.pendingPresentationChange!.toJson(),
      );
    },
  );

  test(
    'twelve committed frames retain ten exact Changed facts and suppression two',
    () async {
      final presented = await fixture.events();
      for (var position = 1; position <= 12; position++) {
        final prepared = await prepare(position);
        final receipt = prepared.pendingPresentationChange!;
        fixture.participation.clock.now = fixture.participation.clock.now.add(
          const Duration(milliseconds: 1),
        );
        final result = await commit(receipt);
        expect(result.pendingPresentationChange, isNull);
        expect(result.lastSwitchOrdinal, position.clamp(0, 10));
        expect(result.suppressedSwitchCount, position > 10 ? position - 10 : 0);
        expect(
          result.currentPresentation,
          position.isEven
              ? TodayExperiencePresentation.standard
              : TodayExperiencePresentation.adventure,
        );
        final beforeRetry = await fixture.events();
        expect((await commit(receipt)).localRevision, result.localRevision);
        expect(await fixture.events(), beforeRetry);
        expect(await fixture.facts(), isNotNull);
      }
      final events = await fixture.events();
      expect(
        events.where((e) => e['event_type'] == measurementPresentedEventType),
        presented,
      );
      final changed = events
          .where(
            (e) => e['event_type'] == measurementPresentationChangedEventType,
          )
          .toList();
      expect(changed, hasLength(10));
      for (var index = 0; index < changed.length; index++) {
        final event = changed[index];
        expect(event, hasLength(22));
        final payload = jsonDecode(event['payload_json']! as String) as Map;
        expect(payload.keys.toSet(), {
          'assignedTreatment',
          'effectivePresentation',
          'fromPresentation',
          'switchOrdinal',
        });
        final ordinal = payload['switchOrdinal']! as int;
        expect(
          event['idempotency_key'],
          'research:${sha256.convert(utf8.encode(jsonEncode([fixture.opportunityId, measurementPresentationChangedEventType, ordinal])))}',
        );
        expect(event['aggregate_type'], 'MeasurementOpportunity');
        expect(event['aggregate_id'], fixture.opportunityId);
        expect(event['correlation_id'], fixture.opportunityId);
        expect(event['owner_id'], 'owner-a');
        expect(event['privacy_classification'], 'ownerOnly');
      }
      expect(
        await fixture.database
            .customSelect('SELECT * FROM outbox_operations')
            .get(),
        isEmpty,
      );
    },
  );

  test(
    'same choice and stale revision create no pending intent or transition',
    () async {
      final current = (await fixture.repository.load(
        'owner-a',
        fixture.opportunityId,
      ))!;
      final before = await fixture.storedOpportunity();
      final unchanged = await fixture.repository.preparePresentationChange(
        'owner-a',
        fixture.opportunityId,
        attemptId: '10000000-0000-4000-8000-000000000001',
        expectedRevision: current.localRevision,
        target: current.currentPresentation,
        stillCurrent: () => true,
      );
      expect(unchanged.pendingPresentationChange, isNull);
      await expectLater(
        fixture.repository.preparePresentationChange(
          'owner-a',
          fixture.opportunityId,
          attemptId: '10000000-0000-4000-8000-000000000002',
          expectedRevision: current.localRevision - 1,
          target: TodayExperiencePresentation.adventure,
          stillCurrent: () => true,
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await fixture.storedOpportunity(), before);
    },
  );

  for (final denial in ['visibility', 'revocation']) {
    test(
      '$denial after prepare preserves pending and all prior facts',
      () async {
        final receipt = (await prepare(1)).pendingPresentationChange!;
        final before = await fixture.storedOpportunity();
        final events = await fixture.events();
        if (denial == 'revocation') fixture.participation.states.revoked = true;
        await expectLater(
          fixture.repository.commitPresentationChange(
            'owner-a',
            fixture.opportunityId,
            receipt: receipt,
            stillVisible: () => denial != 'visibility',
          ),
          throwsA(isA<ResearchCaptureDenied>()),
        );
        expect(await fixture.storedOpportunity(), before);
        expect(await fixture.events(), events);
        expect(await fixture.facts(), isNull);
      },
    );
  }

  test(
    'Started snapshots current presentation and later switches do not rewrite it',
    () async {
      await commit((await prepare(1)).pendingPresentationChange!);
      await fixture.accept();
      final started = (await fixture.events()).singleWhere(
        (e) => e['event_type'] == measurementMissionStartedEventType,
      );
      expect(
        jsonDecode(started['payload_json']! as String)['effectivePresentation'],
        'adventure',
      );
      await commit((await prepare(2)).pendingPresentationChange!);
      final current = (await fixture.repository.load(
        'owner-a',
        fixture.opportunityId,
      ))!;
      expect(
        current.startedEffectivePresentation,
        TodayExperiencePresentation.adventure,
      );
      expect(
        current.effectivePresentation,
        TodayExperiencePresentation.standard,
      );
      expect(current.currentPresentation, TodayExperiencePresentation.standard);
      expect(
        (await fixture.events()).singleWhere(
          (e) => e['event_type'] == measurementMissionStartedEventType,
        ),
        started,
      );
      await fixture.finish();
      final completed = (await fixture.events()).singleWhere(
        (e) => e['event_type'] == measurementMissionCompletedEventType,
      );
      expect(
        jsonDecode(
          completed['payload_json']! as String,
        )['effectivePresentation'],
        'standard',
      );
    },
  );

  test(
    'canonical completed session denies change even without Completed projection',
    () async {
      await fixture.accept();
      await fixture.database.customStatement(
        "CREATE TEMP TRIGGER fail_close BEFORE UPDATE ON measurement_opportunities WHEN NEW.closed_at_utc_ms IS NOT NULL BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      await fixture.finish();
      expect((await fixture.storedSession())['state'], 'completed');
      expect((await fixture.storedOpportunity())['closed_at_utc_ms'], isNull);
      final before = await fixture.storedOpportunity();
      await expectLater(prepare(1), throwsA(isA<ResearchCaptureDenied>()));
      expect(await fixture.storedOpportunity(), before);
    },
  );

  test('a tampered Changed envelope makes normal timing unavailable', () async {
    await commit((await prepare(1)).pendingPresentationChange!);
    await fixture.database.customStatement(
      "UPDATE events_v2 SET build_id = 'tampered' WHERE event_type = 'TodayExperiencePresentationChanged'",
    );
    expect(await fixture.facts(), isNull);
    await expectLater(prepare(2), throwsA(isA<ResearchCaptureDenied>()));
  });

  test(
    'prepare final visibility denial after actual marker write rolls it back',
    () async {
      final before = await fixture.storedOpportunity();
      final events = await fixture.events();
      var sawMarker = false;
      var current = true;
      fixture.participation.states.onRead = (_) async {
        if ((await fixture
                .storedOpportunity())['pending_presentation_change_json'] !=
            null) {
          sawMarker = true;
          current = false;
        }
      };
      await expectLater(
        fixture.repository.preparePresentationChange(
          'owner-a',
          fixture.opportunityId,
          attemptId: '10000000-0000-4000-8000-000000000001',
          expectedRevision: before['local_revision']! as int,
          target: TodayExperiencePresentation.adventure,
          stillCurrent: () => current,
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(sawMarker, isTrue);
      expect(await fixture.storedOpportunity(), before);
      expect(await fixture.events(), events);
    },
  );

  for (final denial in ['expiry', 'visibility', 'revocation']) {
    test(
      '$denial during actual post-insert authority await preserves pending',
      () async {
        final receipt = (await prepare(1)).pendingPresentationChange!;
        final before = await fixture.storedOpportunity();
        final events = await fixture.events();
        var sawChanged = false;
        var visible = true;
        fixture.participation.states.onRead = (_) async {
          if ((await fixture.events()).any(
            (row) =>
                row['event_type'] == measurementPresentationChangedEventType,
          )) {
            sawChanged = true;
            if (denial == 'expiry') {
              fixture.participation.clock.now = participationStart.add(
                const Duration(hours: 2),
              );
            }
            if (denial == 'visibility') {
              visible = false;
            }
            if (denial == 'revocation') {
              fixture.participation.states.revoked = true;
            }
          }
        };
        await expectLater(
          fixture.repository.commitPresentationChange(
            'owner-a',
            fixture.opportunityId,
            receipt: receipt,
            stillVisible: () => visible,
          ),
          throwsA(isA<ResearchCaptureDenied>()),
        );
        expect(sawChanged, isTrue);
        expect(await fixture.storedOpportunity(), before);
        expect(await fixture.events(), events);
      },
    );
  }

  for (final denial in ['owner', 'deletion', 'withdrawal']) {
    test('durable $denial after preparation cannot consume its marker', () async {
      final receipt = (await prepare(1)).pendingPresentationChange!;
      final before = await fixture.storedOpportunity();
      final events = await fixture.events();
      switch (denial) {
        case 'owner':
          await fixture.database.customStatement(
            "UPDATE local_owners SET is_active = CASE WHEN id = 'owner-b' THEN 1 ELSE 0 END",
          );
        case 'deletion':
          await fixture.participation.ownerWrites.beginDeletion(
            ownerId: 'owner-a',
            firebaseUid: 'uid-a',
            idempotencyKey: 'synthetic-pending-delete',
          );
        case 'withdrawal':
          await fixture.participation.withdraw();
      }
      await expectLater(commit(receipt), throwsA(isA<ResearchCaptureDenied>()));
      expect(await fixture.storedOpportunity(), before);
      expect(await fixture.events(), events);
      if (denial == 'withdrawal') {
        expect(
          (await fixture.participation.consent.load(
            ownerId: 'owner-a',
            version: 4,
          )).accepted,
          isFalse,
        );
      }
    });
  }

  test(
    'canonical completion after prepare cannot commit or discard pending',
    () async {
      await fixture.accept();
      final receipt = (await prepare(1)).pendingPresentationChange!;
      final before = await fixture.storedOpportunity();
      final events = await fixture.events();
      await fixture.finish();
      expect((await fixture.storedSession())['state'], 'completed');
      expect(await fixture.storedOpportunity(), before);
      await expectLater(commit(receipt), throwsA(isA<ResearchCaptureDenied>()));
      expect(await fixture.storedOpportunity(), before);
      expect(await fixture.events(), events);
    },
  );

  test(
    'an indexed row missing its Started snapshot cannot use a fallback',
    () async {
      await fixture.accept();
      final events = await fixture.events();
      await fixture.database.customStatement(
        'UPDATE measurement_opportunities SET started_effective_presentation = NULL WHERE id = ?',
        [fixture.opportunityId],
      );
      expect(await fixture.facts(), isNull);
      await expectLater(prepare(1), throwsFormatException);
      expect(await fixture.events(), events);
    },
  );

  for (final mutation in ['unknown key', 'noncanonical', 'base tuple']) {
    test(
      '$mutation pending JSON is unavailable and cannot authorize commit',
      () async {
        final receipt = (await prepare(1)).pendingPresentationChange!;
        final json = receipt.toJson();
        if (mutation == 'unknown key') json['unexpected'] = true;
        if (mutation == 'base tuple') json['baseOrdinal'] = 1;
        final text = mutation == 'noncanonical'
            ? ' ${receipt.canonicalJson}'
            : jsonEncode(json);
        await fixture.database.customStatement(
          'UPDATE measurement_opportunities SET pending_presentation_change_json = ? WHERE id = ?',
          [text, fixture.opportunityId],
        );
        final before = await fixture.storedOpportunity();
        expect(await fixture.facts(), isNull);
        await expectLater(commit(receipt), throwsA(isA<FormatException>()));
        expect(await fixture.storedOpportunity(), before);
      },
    );
  }

  for (final mutation in ['ownerId', 'entryAttemptId', 'attemptId']) {
    test('foreign $mutation receipt cannot consume pending', () async {
      final receipt = (await prepare(1)).pendingPresentationChange!;
      final json = receipt.toJson();
      json[mutation] = mutation == 'ownerId'
          ? 'owner-b'
          : '20000000-0000-4000-8000-000000000002';
      final foreign = PendingPresentationChange.fromJson(jsonEncode(json));
      final before = await fixture.storedOpportunity();
      await expectLater(commit(foreign), throwsA(isA<ResearchCaptureDenied>()));
      expect(await fixture.storedOpportunity(), before);
    });
  }

  test(
    'stale suppressed ACK after newer transition never increments again',
    () async {
      late PendingPresentationChange older;
      for (var position = 1; position <= 12; position++) {
        final receipt = (await prepare(position)).pendingPresentationChange!;
        await commit(receipt);
        if (position == 11) older = receipt;
      }
      final before = await fixture.storedOpportunity();
      final events = await fixture.events();
      await expectLater(commit(older), throwsA(isA<ResearchCaptureDenied>()));
      expect(await fixture.storedOpportunity(), before);
      expect(await fixture.events(), events);
    },
  );

  for (final phase in ['prepare', 'commit']) {
    test(
      'canonical completion injected in final authority await denies $phase',
      () async {
        await fixture.accept();
        final receipt = phase == 'commit'
            ? (await prepare(1)).pendingPresentationChange!
            : null;
        if (phase == 'commit') {
          await fixture.database.customStatement(
            "CREATE TEMP TRIGGER fail_close BEFORE UPDATE ON measurement_opportunities WHEN NEW.closed_at_utc_ms IS NOT NULL BEGIN SELECT RAISE(ABORT, 'synthetic completion projection failure'); END",
          );
        }
        final before = await fixture.storedOpportunity();
        final events = await fixture.events();
        var injected = false;
        String? canonicalStateDuringAwait;
        fixture.participation.states.onRead = (_) async {
          if (injected) return;
          final targetWritten = phase == 'prepare'
              ? (await fixture
                        .storedOpportunity())['pending_presentation_change_json'] !=
                    null
              : (await fixture.events()).any(
                  (row) =>
                      row['event_type'] ==
                      measurementPresentationChangedEventType,
                );
          if (!targetWritten) return;
          injected = true;
          await fixture.finish();
          canonicalStateDuringAwait =
              (await fixture.storedSession())['state']! as String;
        };
        Object? failure;
        MeasurementOpportunity? returned;
        try {
          returned = phase == 'prepare'
              ? await prepare(1)
              : await commit(receipt!);
        } on Object catch (error) {
          failure = error;
        }
        expect(
          injected,
          isTrue,
          reason:
              'The actual target row/event must exist before the real Ed state await injects finish',
        );
        expect(canonicalStateDuringAwait, 'completed');
        expect(
          failure,
          isA<ResearchCaptureDenied>(),
          reason:
              '$phase must reject canonical completion after its DB write; returned revision ${returned?.localRevision}',
        );
        expect(await fixture.storedOpportunity(), before);
        expect(await fixture.events(), events);
      },
    );
  }

  test(
    'domain getter rejects corrupt counters instead of deriving a presentation',
    () async {
      final current = (await fixture.repository.load(
        'owner-a',
        fixture.opportunityId,
      ))!;
      for (final values in [(11, 0), (0, 1), (10, -1)]) {
        final invalid = MeasurementOpportunity(
          id: current.id,
          ownerId: current.ownerId,
          measurementRunId: current.measurementRunId,
          permitId: current.permitId,
          entryAttemptId: current.entryAttemptId,
          assignedTreatment: current.assignedTreatment,
          effectivePresentation: current.effectivePresentation,
          openedAtUtc: current.openedAtUtc,
          localRevision: current.localRevision,
          lastSwitchOrdinal: values.$1,
          suppressedSwitchCount: values.$2,
        );
        expect(() => invalid.currentPresentation, throwsFormatException);
        expect(() => invalid.totalSwitches, throwsFormatException);
      }
      expect(
        () => PendingPresentationChange.fromJson('x' * 2049),
        throwsFormatException,
      );
    },
  );
}
