import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';

import '../../support/motivation_research_fixture.dart';

void main() {
  late MotivationResearchFixture f;
  setUp(() {
    f = MotivationResearchFixture();
  });
  tearDown(() => f.database.close());
  Future<MotivationMeasurementRun> start() => f.measurements.start(
    const MotivationMeasurementStart(ownerId: 'owner:a', permitId: 'permit:a'),
  );

  test(
    'nonparticipant is denied with zero research rows/events/outbox',
    () async {
      await f.initialize(enroll: false);
      await expectLater(start(), throwsA(isA<ResearchCaptureDenied>()));
      for (final table in [
        'motivation_measurement_runs',
        'motivation_responses',
        'research_participation_permits',
        'measurement_opportunities',
        'events_v2',
        'outbox_operations',
      ]) {
        expect(
          await f.database.customSelect('SELECT * FROM $table').get(),
          isEmpty,
        );
      }
    },
  );
  test(
    'start is deterministic; bounded response is durable and retry-idempotent',
    () async {
      await f.initialize();
      final run = await start();
      expect((await start()).id, run.id);
      final response = MotivationResponse(
        ownerId: 'owner:a',
        runId: run.id,
        itemId: 'baseline',
        responseCode: 'high',
      );
      await f.measurements.record(response);
      f.now = f.now.add(const Duration(minutes: 1));
      await f.measurements.record(response);
      final loaded = (await f.measurements.load('owner:a', run.id))!;
      expect(loaded.score(MotivationTimepoint.baseline), 100);
      expect(loaded.score(MotivationTimepoint.post), isNull);
      expect(loaded.responses, hasLength(1));
      expect(
        loaded.responses.single.answeredAtUtc,
        DateTime.utc(2026, 9, 5, 12),
      );
    },
  );
  test(
    'reject unknown codes and opposite owner without inserting data',
    () async {
      await f.initialize();
      final run = await start();
      for (final response in [
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run.id,
          itemId: 'baseline',
          responseCode: 'free text',
        ),
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run.id,
          itemId: 'unknown',
          responseCode: 'high',
        ),
        MotivationResponse(
          ownerId: 'owner:b',
          runId: run.id,
          itemId: 'baseline',
          responseCode: 'high',
        ),
      ]) {
        await expectLater(f.measurements.record(response), throwsA(anything));
      }
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        isEmpty,
      );
    },
  );
  test(
    'post cannot be recorded without a canonical accepted completion',
    () async {
      await f.initialize();
      final run = await start();
      await expectLater(
        f.measurements.record(
          MotivationResponse(
            ownerId: 'owner:a',
            runId: run.id,
            itemId: 'post',
            responseCode: 'high',
          ),
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
    },
  );
  test('skip closes run and prevents restart/response resurrection', () async {
    await f.initialize();
    final run = await start();
    await f.measurements.close(
      MotivationMeasurementClose(
        ownerId: 'owner:a',
        runId: run.id,
        state: MotivationMeasurementRunState.skipped,
      ),
    );
    expect((await start()).state, MotivationMeasurementRunState.skipped);
    await expectLater(
      f.measurements.record(
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run.id,
          itemId: 'baseline',
          responseCode: 'high',
        ),
      ),
      throwsA(isA<ResearchCaptureDenied>()),
    );
  });
  test('incomplete close never converts missing motivation to zero', () async {
    await f.initialize();
    final run = await start();
    await expectLater(
      f.measurements.close(
        MotivationMeasurementClose(
          ownerId: 'owner:a',
          runId: run.id,
          state: MotivationMeasurementRunState.completed,
        ),
      ),
      throwsA(isA<ResearchCaptureDenied>()),
    );
    expect(
      (await f.measurements.load('owner:a', run.id))!.state,
      MotivationMeasurementRunState.started,
    );
  });
  test(
    'expiry, signature failure and receipt withdrawal deny mutation',
    () async {
      await f.initialize();
      final run = await start();
      final command = MotivationResponse(
        ownerId: 'owner:a',
        runId: run.id,
        itemId: 'baseline',
        responseCode: 'high',
      );
      f.authority.validSignature = false;
      await expectLater(
        f.measurements.record(command),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      f.authority.validSignature = true;
      f.authority.receiptsActive = false;
      await expectLater(
        f.measurements.record(command),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      f.authority.receiptsActive = true;
      f.now = f.permit().expiresAtUtc;
      await expectLater(
        f.measurements.record(command),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        isEmpty,
      );
    },
  );
  test('withdrawal while receipt authority awaits rolls back response', () async {
    await f.initialize();
    final run = await start();
    f.authority.onRead = () async {
      f.authority.onRead = null;
      await f.database.customStatement(
        "UPDATE research_consents SET consent_state='withdrawn',withdrawn_at_utc_ms=?",
        [f.now.millisecondsSinceEpoch],
      );
    };
    await expectLater(
      f.measurements.record(
        MotivationResponse(
          ownerId: 'owner:a',
          runId: run.id,
          itemId: 'baseline',
          responseCode: 'high',
        ),
      ),
      throwsA(isA<ResearchCaptureDenied>()),
    );
    expect(
      await f.database.select(f.database.motivationResponses).get(),
      isEmpty,
    );
  });
  test(
    'minor enrollment requires independent guardian and assent refs',
    () async {
      await f.initialize(enroll: false);
      await expectLater(
        f.participation.importPermit(
          f.permit(participantClass: ResearchParticipantClass.minor),
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(
        await f.database.select(f.database.researchParticipationPermits).get(),
        isEmpty,
      );
      await f.participation.importPermit(
        f.permit(
          participantClass: ResearchParticipantClass.minor,
          guardian: 'guardian:opaque',
          assent: 'assent:opaque',
        ),
      );
      expect(
        await f.participation.readActivePermit(
          ownerId: 'owner:a',
          evaluatedAtUtc: f.now,
        ),
        isNotNull,
      );
    },
  );
}
