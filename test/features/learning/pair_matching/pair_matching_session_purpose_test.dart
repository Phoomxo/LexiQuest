import 'dart:convert';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'pair_matching_evidence_contract_test.dart' show PairHarness;
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_session_purpose.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';

void main() {
  for (final marker in ['missing', 'active', 'wrong-target', 'valid']) {
    test('legacy historical actor requires authentic merge marker: $marker', () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final learning = LearningUseCases(
        owners: h.learning.owners,
        repository: h.real,
        generateId: () => 'synthetic-legacy-${++h.nextId}',
        nowUtc: h.learning.nowUtc,
        buildInfo: h.learning.buildInfo,
      );
      await h.db.customStatement(
        "UPDATE learning_sessions SET state='abandoned',ended_at_utc_ms=started_at_utc_ms WHERE id=?",
        [h.operation.plan.learningSessionId],
      );
      final prepared = await const MatchingModeAdapter().prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        categoryId: 'synthetic-category',
      );
      final id = prepared.session.id;
      final rows = await h.db
          .customSelect(
            "SELECT * FROM events_v2 WHERE aggregate_id=? AND event_type='LearningActivityCheckpoint'",
            variables: [Variable(id)],
          )
          .get();
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final revision =
            (jsonDecode(row.data['payload_json'] as String) as Map)['revision']
                as int;
        final key = PairMatchingSessionPurpose.checkpointKey(
          'synthetic-historical',
          id,
          revision,
        );
        await h.db.customStatement(
          'UPDATE events_v2 SET actor_identity=?, event_id=?, idempotency_key=? WHERE event_id=?',
          ['synthetic-historical', key, key, row.data['event_id']],
        );
      }
      if (marker != 'missing') {
        await h.db.customStatement(
          'INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES (?,?,1,?)',
          [
            'synthetic-historical',
            'mergedInto:${marker == 'wrong-target' ? 'other' : h.owner}',
            marker == 'active' ? 1 : 0,
          ],
        );
      }
      final read = DriftPairMatchingSessionPurposeReader(
        h.db,
      ).read(ownerId: h.owner, sessionId: id);
      if (marker == 'valid') {
        expect((await read).allowsLearningAuthority, true);
        for (final terminal in [42, '2026-09-05T00:00:00']) {
          final payload = {
            ...(jsonDecode(rows.first.data['payload_json'] as String) as Map),
            'schemaVersion': 2,
            'terminalAtUtc': terminal,
            'terminalAcknowledged': false,
          };
          await h.db.customStatement(
            'UPDATE events_v2 SET event_version=2,payload_json=? WHERE aggregate_id=?',
            [jsonEncode(payload), id],
          );
          await expectLater(
            DriftPairMatchingSessionPurposeReader(
              h.db,
            ).read(ownerId: h.owner, sessionId: id),
            throwsStateError,
          );
        }
      } else {
        await expectLater(read, throwsStateError);
      }
    });
  }
  test(
    'v6 envelope requires bool terminal acknowledgement even when initial',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final row = (await h.db.select(h.db.eventsV2).get()).single;
      final payload = {
        ...(jsonDecode(row.payloadJson) as Map),
        'schemaVersion': 2,
        'terminalAtUtc': null,
        'terminalAcknowledged': null,
      };
      await h.db.customStatement(
        'UPDATE events_v2 SET event_version=2,payload_json=? WHERE event_id=?',
        [jsonEncode(payload), row.eventId],
      );
      await expectLater(
        DriftPairMatchingSessionPurposeReader(
          h.db,
        ).read(ownerId: h.owner, sessionId: h.operation.plan.learningSessionId),
        throwsStateError,
      );
    },
  );
  test(
    'missing matching checkpoints deny new direct normal evidence writes',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      final revision =
          h.repository.commands.single.evidenceContext.contentRevision;
      await h.db.customStatement(
        "DELETE FROM events_v2 WHERE event_type='LearningActivityCheckpoint'",
      );
      final pending = CurrentActivityEvidenceAdapter(learning: h.learning)
          .captureMatching(
            ownerId: h.owner,
            sessionId: h.operation.plan.learningSessionId,
            wordId: 'synthetic-0',
            isCorrect: true,
            responseTimeMs: 25,
            attemptNumber: 2,
            contentRevision: revision,
            classification: const HintEvidenceClassification(
              evidenceClass: EvidenceClass.recognition,
              hintLevel: 0,
            ),
          );
      await expectLater(pending.record(), throwsStateError);
      expect(await h.db.select(h.db.answerAttempts).get(), hasLength(1));
    },
  );
  test('missing all checkpoints never grants ordinary authority', () async {
    final h = PairHarness();
    addTearDown(h.db.close);
    await h.initialize();
    await h.db.customStatement(
      "DELETE FROM events_v2 WHERE event_type='LearningActivityCheckpoint'",
    );
    final value = await DriftPairMatchingSessionPurposeReader(
      h.db,
    ).read(ownerId: h.owner, sessionId: h.operation.plan.learningSessionId);
    expect(value.purpose, isNull);
    expect(value.allowsLearningAuthority, false);
  });
  test(
    'v6 disguised as legacy is rejected rather than granting authority',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final row = (await h.db.select(h.db.eventsV2).get()).single;
      final payload = jsonDecode(row.payloadJson) as Map;
      (payload['state'] as Map)['schemaVersion'] = 5;
      await h.db.customStatement(
        'UPDATE events_v2 SET payload_json=? WHERE event_id=?',
        [jsonEncode(payload), row.eventId],
      );
      await expectLater(
        DriftPairMatchingSessionPurposeReader(
          h.db,
        ).read(ownerId: h.owner, sessionId: h.operation.plan.learningSessionId),
        throwsStateError,
      );
    },
  );
  test(
    'persisted initial/latest reader authenticates learning and rejects payload corruption',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final reader = DriftPairMatchingSessionPurposeReader(h.db);
      final value = await reader.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(value.purpose, PairSessionPurpose.learning);
      expect(
        value.snapshot!.engine.plan.planFingerprint,
        h.operation.plan.planFingerprint,
      );
      final rows = await h.db
          .customSelect(
            "SELECT * FROM events_v2 WHERE event_type='LearningActivityCheckpoint'",
          )
          .get();
      final payload =
          jsonDecode(rows.single.data['payload_json'] as String) as Map;
      (payload['state'] as Map)['unexpected'] = true;
      await h.db.customStatement(
        'UPDATE events_v2 SET payload_json=? WHERE event_id=?',
        [jsonEncode(payload), rows.single.data['event_id']],
      );
      await expectLater(
        reader.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'persisted purpose rejects forged owner and checkpoint identity',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final reader = DriftPairMatchingSessionPurposeReader(h.db);
      await expectLater(
        reader.read(
          ownerId: 'other',
          sessionId: h.operation.plan.learningSessionId,
        ),
        throwsStateError,
      );
      await h.db.customStatement(
        "UPDATE events_v2 SET idempotency_key='forged' WHERE event_type='LearningActivityCheckpoint'",
      );
      await expectLater(
        reader.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        ),
        throwsStateError,
      );
    },
  );
}
