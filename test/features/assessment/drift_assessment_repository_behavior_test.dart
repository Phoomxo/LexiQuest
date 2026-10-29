import 'dart:convert';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';

import '../../support/assessment_writer_harness.dart';

void main() {
  late AssessmentWriterFixture fixture;
  setUp(() async => fixture = await AssessmentWriterFixture.open());
  tearDown(() => fixture.close());

  Future<AssessmentResponseResult> respond({
    String option = 'synthetic yes',
    int latency = 23,
  }) => fixture.repository.recordResponse(
    ownerId: 'owner-a',
    runId: fixture.command().runId,
    itemId: fixture.definition.items.single.itemId,
    option: option,
    responseTimeMs: latency,
    stillVisible: () => true,
  );

  test(
    'exact start preserves original time and rejects changed logical phase intent',
    () async {
      final first = await fixture.start();
      fixture.authorities.advance(const Duration(seconds: 1));
      expect(await fixture.start(), first);
      final before = await fixture.authorities.study.rows('assessment_runs');
      for (final command in [
        fixture.command(sessionId: 'different-session'),
        fixture.command(runId: 'different-run', sessionId: 'different-session'),
      ]) {
        await expectLater(
          () => fixture.repository.start(
            command,
            ownerId: 'owner-a',
            stillVisible: () => true,
          ),
          throwsA(isA<AssessmentRunConflict>()),
        );
      }
      expect(await fixture.authorities.study.rows('assessment_runs'), before);
      expect(
        await fixture.authorities.study.rows('learning_sessions'),
        hasLength(1),
      );
    },
  );

  test(
    'controlled aliases replay original enforced evidence and leave every ordinary table identical',
    () async {
      final before = await fixture.ordinaryRows();
      final run = await fixture.start();
      fixture.authorities.advance(const Duration(milliseconds: 500));
      final first = await respond(option: 'synthetic no');
      expect(
        first.sourceEvidenceId,
        assessmentResponseIdentity(
          run.id,
          fixture.definition.items.single.itemId,
        ),
      );
      expect(first.inserted, isTrue);
      final stored = await fixture.authorities.study.rows('answer_attempts');
      final context = EvidenceContext.fromJson(
        Map<String, Object?>.from(
          jsonDecode(stored.single['evidence_context_json']! as String) as Map,
        ),
      );
      expect(
        LearningEvidenceContract.strictAssessmentShape(
          persistedEvidenceClass: 'assessment',
          context: context,
        ),
        isTrue,
      );
      expect(context.rolloutMode, EvidencePolicyRolloutMode.enforced);
      expect(context.engagementAllowed, isFalse);
      fixture.authorities.advance(const Duration(seconds: 1));
      expect((await respond(option: 'synthetic no alias')).inserted, isFalse);
      for (final request in [
        () => respond(option: 'synthetic no', latency: 24),
        () => respond(option: 'synthetic different no'),
        () => respond(option: 'synthetic yes'),
      ]) {
        await expectLater(request, throwsA(isA<AssessmentRunConflict>()));
      }
      expect(await fixture.authorities.study.rows('answer_attempts'), stored);
      expect(await fixture.ordinaryRows(), before);
      final container = (await fixture.authorities.study.rows(
        'learning_sessions',
      )).single;
      expect(container['correct_count'], 0);
      expect(container['wrong_count'], 0);
      expect(container['score'], isNull);
    },
  );

  test(
    'completion requires all items and terminal replay preserves original time after expiry',
    () async {
      final run = await fixture.start();
      await expectLater(
        () => fixture.repository.complete(
          ownerId: 'owner-a',
          runId: run.id,
          stillVisible: () => true,
        ),
        throwsA(isA<AssessmentRunConflict>()),
      );
      await respond();
      fixture.authorities.advance(const Duration(seconds: 2));
      final completed = await fixture.repository.complete(
        ownerId: 'owner-a',
        runId: run.id,
        stillVisible: () => true,
      );
      expect(
        completed.completedAtUtc,
        participationStart.add(const Duration(seconds: 2)),
      );
      final stored = await fixture.authorities.study.rows('assessment_runs');
      fixture.authorities.advance(const Duration(hours: 2));
      fixture.authorities.cache.invalidate();
      expect(
        await fixture.repository.complete(
          ownerId: 'owner-a',
          runId: run.id,
          stillVisible: () => true,
        ),
        completed,
      );
      expect((await respond()).inserted, isFalse);
      await expectLater(
        () => fixture.repository.abandon(
          ownerId: 'owner-a',
          runId: run.id,
          stillVisible: () => true,
        ),
        throwsA(isA<AssessmentRunConflict>()),
      );
      expect(await fixture.authorities.study.rows('assessment_runs'), stored);
    },
  );

  test(
    'abandon is exact and never permits new response or completion',
    () async {
      final run = await fixture.start();
      final abandoned = await fixture.repository.abandon(
        ownerId: 'owner-a',
        runId: run.id,
        stillVisible: () => true,
      );
      fixture.authorities.advance(const Duration(seconds: 3));
      expect(
        await fixture.repository.abandon(
          ownerId: 'owner-a',
          runId: run.id,
          stillVisible: () => true,
        ),
        abandoned,
      );
      await expectLater(() => respond(), throwsA(isA<AssessmentRunConflict>()));
      await expectLater(
        () => fixture.repository.complete(
          ownerId: 'owner-a',
          runId: run.id,
          stillVisible: () => true,
        ),
        throwsA(isA<AssessmentRunConflict>()),
      );
      expect(await fixture.authorities.study.rows('answer_attempts'), isEmpty);
    },
  );

  test('ambient mutation denies before content IO and partial SQL', () async {
    final calls = fixture.content.calls;
    await fixture.authorities.study.database.transaction(() async {
      await expectLater(() => fixture.start(), throwsStateError);
    });
    expect(fixture.content.calls, calls);
    expect(await fixture.authorities.study.rows('assessment_runs'), isEmpty);
    expect(await fixture.authorities.study.rows('learning_sessions'), isEmpty);
  });

  test(
    'unavailable content invisible surface and malformed controlled input create no facts',
    () async {
      fixture.content.fail = true;
      await expectLater(() => fixture.start(), throwsStateError);
      fixture.content.fail = false;
      await expectLater(
        () => fixture.repository.start(
          fixture.command(),
          ownerId: 'owner-a',
          stillVisible: () => false,
        ),
        throwsStateError,
      );
      expect(await fixture.authorities.study.rows('assessment_runs'), isEmpty);
      await fixture.start();
      for (final request in [
        () => respond(option: 'uncontrolled'),
        () => respond(latency: -1),
        () => respond(latency: LearningEvidenceContract.maxResponseTimeMs + 1),
      ]) {
        await expectLater(request, throwsArgumentError);
      }
      expect(await fixture.authorities.study.rows('answer_attempts'), isEmpty);
    },
  );

  for (final change in <String, String>{
    'P2 payload':
        "UPDATE research_participation_permits SET age_band_code = 'tampered' WHERE owner_id = 'owner-a'",
    'P2 revision':
        "UPDATE research_participation_permits SET local_revision = 2, cloud_revision = 2 WHERE owner_id = 'owner-a'",
    'withdrawn consent':
        "UPDATE research_consents SET consent_state = 'declined', withdrawn_at_utc_ms = decided_at_utc_ms WHERE owner_id = 'owner-a'",
    'reaccepted decision':
        "UPDATE research_consents SET decided_at_utc_ms = decided_at_utc_ms + 1 WHERE owner_id = 'owner-a'",
    'actual UID':
        "UPDATE local_owners SET firebase_uid = 'changed-uid' WHERE id = 'owner-a'",
    'deleted word':
        "UPDATE vocabulary_words SET is_deleted = 1 WHERE id = 'synthetic-study-word'",
  }.entries) {
    test(
      '${change.key} drift rolls new response back without ordinary effects',
      () async {
        await fixture.start();
        await fixture.authorities.study.database.customStatement(change.value);
        final before = await fixture.ordinaryRows();
        await expectLater(() => respond(), throwsA(anything));
        expect(
          await fixture.authorities.study.rows('answer_attempts'),
          isEmpty,
        );
        expect(await fixture.ordinaryRows(), before);
      },
    );
  }

  test('opening after pre start rejects the next capture', () async {
    await fixture.start();
    await fixture.authorities.study.runtime.openPresentation(
      'owner-a',
      entryAttemptId: studyEntryId,
      stillCurrent: () => true,
    );
    final before = await fixture.ordinaryRows();
    await expectLater(() => respond(), throwsStateError);
    expect(await fixture.authorities.study.rows('answer_attempts'), isEmpty);
    expect(await fixture.ordinaryRows(), before);
  });

  test(
    'auth ABA during content fetch rejects original intent before SQL',
    () async {
      fixture.content.onRead = () async {
        fixture.authorities.scope = fixture.authorities.scopeFor(
          owner: 'owner-b',
          uid: 'uid-b',
          generation: 2,
        );
        fixture.authorities.scope = fixture.authorities.scopeFor(generation: 3);
      };
      await expectLater(() => fixture.start(), throwsStateError);
      expect(await fixture.authorities.study.rows('assessment_runs'), isEmpty);
      expect(
        await fixture.authorities.study.rows('learning_sessions'),
        isEmpty,
      );
    },
  );

  test(
    'scope change after actual answer INSERT rolls transaction back',
    () async {
      await fixture.start();
      final interceptor = _AssessmentWriteProbe(
        afterAnswer: () {
          fixture.authorities.scope = fixture.authorities.scopeFor(
            generation: 2,
          );
        },
      );
      final before = await fixture.ordinaryRows();
      await expectLater(
        () => fixture.authorities.study.database.runWithInterceptor(
          () => respond(),
          interceptor: interceptor,
        ),
        throwsStateError,
      );
      expect(interceptor.answerInserts, 1);
      expect(await fixture.authorities.study.rows('answer_attempts'), isEmpty);
      expect(await fixture.ordinaryRows(), before);
    },
  );

  test(
    'trusted expiry during final owner SQL rejects inserted response',
    () async {
      await fixture.start();
      final interceptor = _AssessmentWriteProbe(
        afterFinalOwner: () {
          fixture.authorities.advance(const Duration(minutes: 11));
        },
      );
      await expectLater(
        () => fixture.authorities.study.database.runWithInterceptor(
          () => respond(),
          interceptor: interceptor,
        ),
        throwsStateError,
      );
      expect(interceptor.answerInserts, 1);
      expect(await fixture.authorities.study.rows('answer_attempts'), isEmpty);
    },
  );

  test(
    'display is fresh and owner explicit; deletion fence blocks new capture',
    () async {
      final run = await fixture.start();
      final before = await fixture.ordinaryRows();
      final read = await fixture.repository.requireActivePresentation(
        ownerId: 'owner-a',
        runId: run.id,
        stillVisible: () => true,
      );
      expect(read.run, run);
      expect(read.verifiedAtUtc, participationStart);
      expect(await fixture.ordinaryRows(), before);
      await expectLater(
        () => fixture.repository.getRun(ownerId: 'owner-b', runId: run.id),
        throwsA(anything),
      );
      await fixture.authorities.cache.ownerWrites.beginDeletion(
        ownerId: 'owner-a',
        firebaseUid: 'uid-a',
        idempotencyKey: 'synthetic-writer-delete',
      );
      await expectLater(() => respond(), throwsA(anything));
      expect(await fixture.authorities.study.rows('answer_attempts'), isEmpty);
    },
  );
}

final class _AssessmentWriteProbe extends QueryInterceptor {
  _AssessmentWriteProbe({this.afterAnswer, this.afterFinalOwner});
  final void Function()? afterAnswer;
  final void Function()? afterFinalOwner;
  int answerInserts = 0;
  bool expired = false;
  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (statement.startsWith('INSERT INTO answer_attempts')) {
      answerInserts++;
      afterAnswer?.call();
    }
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (!expired &&
        answerInserts > 0 &&
        statement.startsWith(
          'SELECT o.id, o.firebase_uid, o.account_state, c.consent_state',
        )) {
      expired = true;
      afterFinalOwner?.call();
    }
    return result;
  }
}
