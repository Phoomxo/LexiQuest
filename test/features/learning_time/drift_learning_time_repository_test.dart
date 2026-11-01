import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/learning_time/data/drift_learning_time_repository.dart';

import '../../support/review_center_harness.dart';

void main() {
  test(
    'default-off reads and page-open cannot create an owner or any row',
    () async {
      final h = await _Harness.open(seed: false);
      addTearDown(h.close);
      final before = await h.base.snapshotAllTables();
      expect(before.values, everyElement(isEmpty));
      expect(h.useCases.captureEnabled, isFalse);
      expect(
        (await h.useCases.read(const OwnerTimeRead())).status,
        RecordedTimeStatus.unavailable,
      );
      expect(
        (await h.repository.read(
          target: const OwnerTimeRead(),
          expectedOwnerId: 'synthetic-owner-that-does-not-exist',
          isCurrent: () => true,
        )).status,
        RecordedTimeStatus.unavailable,
      );
      expect(
        await h.useCases.attach(_reading(), stillCurrent: () => true),
        isNull,
      );
      expect(await h.base.snapshotAllTables(), before);
    },
  );

  test(
    'absent choice is revision zero and repeated enable has one CAS revision',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final before = await h.oldRows();
      expect(h.useCases.preference!.enabled, isFalse);
      expect(h.useCases.preference!.revision, 0);
      expect(await h.rows('learning_time_preferences'), isEmpty);
      await h.useCases.setEnabled(
        false,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(await h.rows('learning_time_preferences'), isEmpty);
      await h.enable();
      final choice = await h.rows('learning_time_preferences');
      expect(choice.single['revision'], 1);
      await h.enable();
      expect(await h.rows('learning_time_preferences'), choice);
      expect(await h.oldRows(), before);
    },
  );

  for (final source in <TimeSource>[_reading(), _tutor()]) {
    test(
      'actual ${source.runtimeType} records a confirmed pair without a learning session',
      () async {
        final h = await _Harness.open();
        addTearDown(h.close);
        final before = await h.oldRows();
        await h.enable();
        final lease = await h.attach(source);
        h.advance(const Duration(seconds: 2, microseconds: 3));
        h.useCases.interacted(lease);
        h.advance(const Duration(seconds: 9));
        h.useCases.detach(lease);
        await h.useCases.retryPending();
        expect(h.useCases.hasPending, isFalse);
        final value = await h.useCases.read(ScopeTimeRead(lease.scopeId));
        expect(value.status, RecordedTimeStatus.recorded);
        expect(value.activeDurationUs, 2000003);
        expect(value.segmentCount, 1);
        expect(
          (await h.rows('learning_time_scopes')).single['linked_session_id'],
          isNull,
        );
        expect(await h.rows('learning_sessions'), isEmpty);
        expect(await h.oldRows(), before);
        expect(before, hasLength(42));
      },
    );
  }

  test(
    'opening ready waiting and closing with no user pair leave all43 tables unchanged',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final before = await h.base.snapshotAllTables();
      expect(before, hasLength(45));
      final lease = await h.attach(_reading());
      h.advance(const Duration(minutes: 2));
      h.useCases.detach(lease);
      await h.useCases.retryPending();
      expect(await h.base.snapshotAllTables(), before);
    },
  );

  test(
    'physical commit then lost ACK retains the exact intent and retries without another segment',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      h.probe.loseNextSegmentAck();
      final intent = await h.closed();
      await h.useCases.retryPending();
      expect(h.probe.lostAcknowledgements, 1);
      expect(h.useCases.pendingSegmentIntent, same(intent));
      expect(intent.belongsTo(h.repository), isTrue);
      expect(intent.isCurrent, isTrue);
      final committed = await h.rows('learning_time_segments');
      expect(committed, hasLength(1));
      expect(committed.single['id'], intent.id);
      await h.repository.commitSegment(intent);
      expect(await h.rows('learning_time_segments'), committed);
      await h.useCases.retryPending();
      expect(h.useCases.hasPending, isFalse);
      expect(await h.rows('learning_time_segments'), committed);
      await expectLater(h.repository.commitSegment(intent), throwsStateError);
      expect(await h.rows('outbox_operations'), isEmpty);
    },
  );

  test(
    'preference lost ACK replays the exact original CAS without another revision',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      h.probe.loseNextPreferenceAck();
      await h.useCases.setEnabled(
        true,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(h.probe.lostAcknowledgements, 1);
      final intent = h.useCases.pendingPreferenceIntent;
      expect(intent, isNotNull);
      expect(intent!.belongsTo(h.repository), isTrue);
      final committed = await h.rows('learning_time_preferences');
      expect(committed.single['revision'], 1);
      final ack = await h.repository.commitPreference(intent);
      expect(ack.revision, 1);
      expect(ack.updatedAtUtcMs, intent.updatedAtUtcMs);
      await h.useCases.retryPending();
      expect(h.useCases.hasPending, isFalse);
      expect(await h.rows('learning_time_preferences'), committed);
    },
  );

  test(
    'acknowledged time remains readable after capture is disabled',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final intent = await h.closed();
      await h.useCases.retryPending();
      final facts = await h.rows('learning_time_segments');
      await h.useCases.setEnabled(
        false,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(h.useCases.captureEnabled, isFalse);
      final read = await h.useCases.read(ScopeTimeRead(intent.scope.id));
      expect(read.status, RecordedTimeStatus.recorded);
      expect(read.activeDurationUs, 2000000);
      expect(await h.rows('learning_time_segments'), facts);
      expect(
        await h.useCases.attach(_reading(), stillCurrent: () => true),
        isNull,
      );
    },
  );

  test(
    'a changed persisted payload conflicts with the original lost-ACK replay',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      h.probe.loseNextSegmentAck();
      final intent = await h.closed();
      await h.useCases.retryPending();
      expect(h.probe.lostAcknowledgements, 1);
      await h.base.database.customStatement(
        'UPDATE learning_time_segments SET active_duration_us = active_duration_us + 1 WHERE id = ?',
        [intent.id],
      );
      final corrupted = await h.rows('learning_time_segments');
      await expectLater(h.repository.commitSegment(intent), throwsStateError);
      await h.useCases.retryPending();
      expect(h.useCases.pendingSegmentIntent, same(intent));
      expect(await h.rows('learning_time_segments'), corrupted);
    },
  );

  test(
    'same-database foreign store cannot use an actual opaque pending intent',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final intent = await h.blockedIntent();
      final foreign = DriftLearningTimeRepository(
        database: h.base.database,
        ownerWrites: h.base.ownerWrites,
        learning: h.base.learningRepository,
      );
      final before = await h.base.snapshotAllTables();
      expect(intent.belongsTo(h.repository), isTrue);
      expect(intent.belongsTo(foreign), isFalse);
      await expectLater(foreign.commitSegment(intent), throwsStateError);
      expect(await h.base.snapshotAllTables(), before);
      await h.useCases.retryPending();
      expect((await h.rows('learning_time_segments')).single['id'], intent.id);
    },
  );

  test(
    'copying real canonical fields cannot forge original learning authority',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final proof = await h.configuredProof();
      final before = await h.base.snapshotAllTables();
      expect(
        await h.useCases.attach(
          CanonicalTimeSource(
            _CopiedProof(proof),
            callerContext: LearningTimeCallerContext.ordinary,
          ),
          stillCurrent: () => true,
        ),
        isNull,
      );
      expect(await h.base.snapshotAllTables(), before);
      expect(
        await h.useCases.attach(
          CanonicalTimeSource(
            proof,
            callerContext: LearningTimeCallerContext.ordinary,
          ),
          stillCurrent: () => true,
        ),
        isNotNull,
      );
    },
  );

  test(
    'constructor refuses owner or canonical writers from another database',
    () async {
      final a = await _Harness.open();
      addTearDown(a.close);
      final b = await _Harness.open();
      addTearDown(b.close);
      expect(
        () => DriftLearningTimeRepository(
          database: a.base.database,
          ownerWrites: b.base.ownerWrites,
          learning: a.base.learningRepository,
        ),
        throwsArgumentError,
      );
      expect(
        () => DriftLearningTimeRepository(
          database: a.base.database,
          ownerWrites: a.base.ownerWrites,
          learning: b.base.learningRepository,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'closed A can commit after B is admitted and A route is no longer current',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      var aVisible = true;
      final intent = await h.blockedIntent(
        source: _reading(document: 'synthetic-doc-a'),
        current: () => aVisible,
      );
      aVisible = false;
      final b = await h.useCases.attach(
        _reading(document: 'synthetic-doc-b'),
        stillCurrent: () => true,
      );
      expect(b, isNotNull);
      expect(await h.useCases.ready(b!), isFalse);
      expect(await h.rows('learning_time_scopes'), isEmpty);
      await h.useCases.retryPending();
      expect(
        (await h.rows('learning_time_scopes')).single['id'],
        intent.scope.id,
      );
      expect(
        (await h.rows('learning_time_segments')).single['active_duration_us'],
        2000000,
      );
      expect(await h.useCases.ready(b), isTrue);
      h.advance(const Duration(seconds: 2));
      h.useCases.interacted(b);
      h.useCases.detach(b);
      await h.useCases.retryPending();
      expect(await h.rows('learning_time_scopes'), hasLength(2));
      expect(
        (await h.useCases.read(const OwnerTimeRead())).activeDurationUs,
        4000000,
      );
    },
  );

  test(
    'disable and re-enable retire the original closed intent across gate ABA',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final intent = await h.blockedIntent();
      final disabled = await h.useCases.setEnabled(
        false,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(
        disabled?.enabled,
        isFalse,
        reason:
            'pending=${h.useCases.pendingState}; preference=${h.useCases.preference?.enabled}/${h.useCases.preference?.revision}',
      );
      await h.enable();
      expect(h.useCases.preference!.revision, 3);
      expect(intent.isCurrent, isFalse);
      final before = await h.base.snapshotAllTables();
      await expectLater(h.repository.commitSegment(intent), throwsStateError);
      expect(await h.base.snapshotAllTables(), before);
      expect(await h.rows('learning_time_scopes'), isEmpty);
    },
  );

  test(
    'actual database owner A-B-A cannot revive original closed A intent',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final intent = await h.blockedIntent();
      await h.switchOwner(configuredOtherOwnerId);
      await h.switchOwner(configuredOwnerId);
      expect(h.useCases.captureEnabled, isTrue);
      expect(intent.isCurrent, isFalse);
      final before = await h.base.snapshotAllTables();
      await expectLater(h.repository.commitSegment(intent), throwsStateError);
      expect(await h.base.snapshotAllTables(), before);
    },
  );

  test(
    'actual deletion fence rejects pending time without changing recorded data',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final ownerGeneration = h.useCases.ownerGeneration;
      await h.base.owners.bindFirebaseUid(
        configuredOwnerId,
        configuredFirebaseUid,
      );
      await h.waitFor(
        () =>
            h.useCases.ownerGeneration > ownerGeneration &&
            h.useCases.preference?.ownerId == configuredOwnerId,
      );
      await h.enable();
      final intent = await h.blockedIntent();
      await h.base.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-time-store-delete',
      );
      final before = await h.base.snapshotAllTables();
      await expectLater(
        h.repository.commitSegment(intent),
        throwsA(isA<Object>()),
      );
      expect(await h.base.snapshotAllTables(), before);
      expect(await h.rows('learning_time_segments'), isEmpty);
    },
  );

  test(
    'dependency retirement denies the original pending intent even with the same owner',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final intent = await h.blockedIntent();
      h.useCases.retireDependencies();
      await h.waitFor(() => h.useCases.preference != null);
      final before = await h.base.snapshotAllTables();
      await expectLater(h.repository.commitSegment(intent), throwsStateError);
      expect(await h.base.snapshotAllTables(), before);
    },
  );

  test(
    'an inherited real Drift transaction cannot claim a time commit ACK',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final intent = await h.blockedIntent();
      final before = await h.base.snapshotAllTables();
      await h.base.database.transaction(() async {
        expect(await h.base.ownerWrites.hasAmbientTransaction(), isTrue);
        await expectLater(h.repository.commitSegment(intent), throwsStateError);
      });
      expect(await h.base.snapshotAllTables(), before);
      await h.useCases.retryPending();
      expect((await h.rows('learning_time_segments')).single['id'], intent.id);
    },
  );

  for (final corruption in [
    ('learning_time_scopes', 'source_binding_json'),
    ('learning_time_segments', 'eligibility_context_json'),
  ]) {
    test(
      'malformed stored ${corruption.$2} fails closed without repair or new rows',
      () async {
        final h = await _Harness.open();
        addTearDown(h.close);
        await h.enable();
        await h.closed();
        await h.useCases.retryPending();
        await h.base.database.customStatement(
          'UPDATE ${corruption.$1} SET ${corruption.$2} = ?',
          ['{}'],
        );
        final before = await h.base.snapshotAllTables();
        final read = await h.useCases.read(const OwnerTimeRead());
        expect(read.status, RecordedTimeStatus.unavailable);
        expect(read.activeDurationUs, isNull);
        expect(await h.base.snapshotAllTables(), before);
      },
    );
  }

  test(
    'another owner scope is never included in the current owner read',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final a = await h.closed();
      await h.useCases.retryPending();
      await h.switchOwner(configuredOtherOwnerId);
      await h.enable(owner: configuredOtherOwnerId);
      final b = await h.closed();
      await h.useCases.retryPending();
      expect(a.scope.id, isNot(b.scope.id));
      final bRead = await h.useCases.read(ScopeTimeRead(b.scope.id));
      expect(bRead.status, RecordedTimeStatus.recorded);
      expect(bRead.activeDurationUs, 2000000);
      expect(await h.rows('learning_time_segments'), hasLength(2));
      await h.switchOwner(configuredOwnerId);
      expect(
        (await h.useCases.read(const OwnerTimeRead())).activeDurationUs,
        2000000,
      );
      final foreign = await h.useCases.read(ScopeTimeRead(b.scope.id));
      expect(foreign.status, isNot(RecordedTimeStatus.recorded));
      expect(foreign.activeDurationUs, isNot(2000000));
    },
  );

  test(
    'early Reading links once through its original acknowledged canonical start receipt',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.enable();
      final words = await h.base.learningRepository.listQuizWords(
        ownerId: configuredOwnerId,
        wordIds: [configuredWordIds.first],
        limit: 1,
      );
      final pin = ReadingLearningTimeSourcePin(
        documentId: 'synthetic-store-reading',
        documentRevision: 2,
        snapshotSha256: sha256
            .convert(utf8.encode('Synthetic displayed passage.'))
            .toString(),
        targetPinsSha256: learningTimeTargetPinsSha256(words),
      );
      final source = ReadingTimeSource(
        documentId: pin.documentId,
        documentRevision: pin.documentRevision,
        snapshotSha256: pin.snapshotSha256,
        targetPinsSha256: pin.targetPinsSha256,
        readingStage: 1,
        callerContext: LearningTimeCallerContext.ordinary,
      );
      final lease = await h.attach(source);
      h.advance(const Duration(seconds: 2));
      h.useCases.interacted(lease);
      h.useCases.detach(lease);
      await h.useCases.retryPending();
      expect(await h.rows('learning_sessions'), isEmpty);
      final segments = await h.rows('learning_time_segments');
      final scopeBefore = (await h.rows('learning_time_scopes')).single;
      expect(scopeBefore['linked_session_id'], isNull);
      final prepared = (await h.base.learning.prepareSourceBoundReadingStart(
        expectedOwnerId: configuredOwnerId,
        wordIds: words.map((word) => word.id),
        source: pin,
        callerContext: LearningTimeCallerContext.ordinary,
        stillCurrent: () => true,
      ))!;
      final session = await h.base.learning.startSourceBoundVocabularySession(
        prepared,
        operationStillCurrent: () => true,
      );
      final receipt = await h.base.learning
          .readSourceBoundVocabularyStartReceipt(
            prepared,
            expectedOwnerId: configuredOwnerId,
            ownerStillCurrent: () => true,
          );
      final ordinaryBeforeLink = await h.oldRows();
      final admission = await h.useCases.prepareSessionLink(lease, receipt);
      expect(admission, isNotNull);
      expect(h.useCases.acknowledgeSessionLink(lease, admission!), isTrue);
      await h.useCases.retryPending();
      expect(h.useCases.hasPending, isFalse);
      final linked = (await h.rows('learning_time_scopes')).single;
      expect(linked['linked_session_id'], session.id);
      expect(
        {...linked}
          ..remove('linked_session_id')
          ..remove('session_link_binding_json'),
        {...scopeBefore}
          ..remove('linked_session_id')
          ..remove('session_link_binding_json'),
      );
      expect(await h.rows('learning_time_segments'), segments);
      expect(await h.oldRows(), ordinaryBeforeLink);
      final value = await h.useCases.read(SessionTimeRead(session.id));
      expect(value.status, RecordedTimeStatus.recorded);
      expect(value.activeDurationUs, 2000000);
      expect(h.useCases.acknowledgeSessionLink(lease, admission), isTrue);
      await h.useCases.retryPending();
      expect(await h.rows('learning_time_segments'), segments);
      expect(await h.rows('learning_time_scopes'), [linked]);
      final malformedLink = jsonEncode({
        ...jsonDecode(linked['session_link_binding_json']! as String)
            as Map<String, dynamic>,
        'schemaVersion': 1.0,
      });
      await h.base.database.customStatement(
        'UPDATE learning_time_scopes SET session_link_binding_json=? WHERE id=?',
        [malformedLink, linked['id']],
      );
      final corrupted = await h.base.snapshotAllTables();
      expect(
        (await h.useCases.read(ScopeTimeRead(lease.scopeId))).status,
        RecordedTimeStatus.unavailable,
      );
      expect(await h.base.snapshotAllTables(), corrupted);
    },
  );
}

ReadingTimeSource _reading({String document = 'synthetic-store-doc'}) =>
    ReadingTimeSource(
      documentId: document,
      documentRevision: 1,
      snapshotSha256: 'a' * 64,
      targetPinsSha256: 'b' * 64,
      readingStage: 1,
      callerContext: LearningTimeCallerContext.ordinary,
    );

TutorTimeSource _tutor() => const TutorTimeSource(
  episodeId: 'synthetic-tutor-episode',
  mode: TutorTimeMode.guided,
  scenario: TutorTimeScenario.cafeOrder,
  responseDisplayId: 'tutor-reply:synthetic-tutor-response-display',
  model: 'synthetic-model-v1',
  callerContext: LearningTimeCallerContext.ordinary,
);

final class _Harness {
  _Harness(this.base, this.probe) {
    repository = DriftLearningTimeRepository(
      database: base.database,
      ownerWrites: base.ownerWrites,
      learning: base.learningRepository,
    );
    useCases = LearningTimeUseCases(
      repository: repository,
      ownerChanges: base.ownerChanges,
      monotonicMicros: () => micros,
      nowUtc: () => base.now,
      generateId: () => 'synthetic-time-store-${++sequence}',
    );
  }

  final ReviewCenterHarness base;
  final _CommitProbe probe;
  late final DriftLearningTimeRepository repository;
  late final LearningTimeUseCases useCases;
  int micros = 0;
  int sequence = 0;

  static Future<_Harness> open({bool seed = true}) async {
    final probe = _CommitProbe();
    final result = _Harness(
      await ReviewCenterHarness.open(interceptor: probe, seed: seed),
      probe,
    );
    try {
      if (seed) {
        await result.waitFor(
          () => result.useCases.preference?.ownerId == configuredOwnerId,
        );
      } else {
        expect(
          await result.base.ownerChanges.first.timeout(
            const Duration(seconds: 5),
          ),
          isNull,
        );
      }
      return result;
    } catch (_) {
      await result.close();
      rethrow;
    }
  }

  Future<void> close() async {
    await useCases.retryPending();
    await useCases.dispose();
    await base.close();
  }

  Future<void> waitFor(bool Function() condition) async {
    if (condition()) return;
    await useCases.changes
        .firstWhere((_) => condition())
        .timeout(const Duration(seconds: 5));
  }

  Future<void> enable({String owner = configuredOwnerId}) async {
    final enabled = await useCases.setEnabled(
      true,
      expectedOwnerId: owner,
      stillCurrent: () => true,
    );
    expect(
      enabled?.enabled,
      isTrue,
      reason:
          'pending=${useCases.pendingState}; preference=${useCases.preference?.enabled}/${useCases.preference?.revision}',
    );
    await waitFor(() => useCases.captureEnabled);
  }

  void advance(Duration duration) {
    micros += duration.inMicroseconds;
    base.now = base.now.add(duration);
  }

  Future<LiveTimeLease> attach(
    TimeSource source, {
    bool Function()? current,
  }) async {
    final lease = await useCases.attach(
      source,
      stillCurrent: current ?? () => true,
    );
    expect(lease, isNotNull);
    expect(await useCases.ready(lease!), isTrue);
    return lease;
  }

  Future<ClosedTimeSegmentIntent> closed({
    TimeSource? source,
    bool Function()? current,
  }) async {
    final lease = await attach(
      source ?? _reading(document: 'synthetic-store-doc-${sequence + 1}'),
      current: current,
    );
    advance(const Duration(seconds: 2));
    useCases.interacted(lease);
    useCases.detach(lease);
    final intent = useCases.pendingSegmentIntent;
    expect(intent, isNotNull);
    return intent!;
  }

  Future<ClosedTimeSegmentIntent> blockedIntent({
    TimeSource? source,
    bool Function()? current,
  }) async {
    await base.database.customStatement(
      'CREATE TEMP TRIGGER reject_synthetic_time_segment '
      'BEFORE INSERT ON learning_time_segments '
      "BEGIN SELECT RAISE(ABORT, 'synthetic-time-store-failure'); END",
    );
    final intent = await closed(source: source, current: current);
    await useCases.retryPending();
    expect(useCases.pendingSegmentIntent, same(intent));
    expect(await rows('learning_time_scopes'), isEmpty);
    expect(await rows('learning_time_segments'), isEmpty);
    await base.database.customStatement(
      'DROP TRIGGER reject_synthetic_time_segment',
    );
    return intent;
  }

  Future<void> switchOwner(String owner) async {
    await base.switchOwner(owner);
    await waitFor(
      () => useCases.ownerId == owner && useCases.preference != null,
    );
  }

  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row
        in await base.database
            .customSelect('SELECT * FROM "$table" ORDER BY rowid')
            .get())
      Map<String, Object?>.from(row.data),
  ];

  Future<Map<String, List<String>>> oldRows() async {
    final result = await base.snapshotAllTables();
    result.removeWhere((table, _) => table.startsWith('learning_time_'));
    expect(result, hasLength(42));
    return result;
  }

  Future<CanonicalLearningTimeAdmission> configuredProof() async {
    final state = await base.learning.startConfiguredQuiz(
      await base.learning.prepareConfiguredQuiz(
        expectedOwnerId: configuredOwnerId,
        configuration: QuizConfiguration.category(
          categoryId: configuredCategoryId,
          limit: 1,
        ),
      ),
    );
    return base.learning.admitCanonicalLearningTime(
      ConfiguredQuizTimeAdmission(
        state,
        callerContext: LearningTimeCallerContext.ordinary,
      ),
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => true,
    );
  }
}

final class _CommitProbe extends drift.QueryInterceptor {
  final _affectedTransactions = Set<drift.QueryExecutor>.identity();
  String? _loseAckForTable;
  int lostAcknowledgements = 0;

  void loseNextSegmentAck() => _loseAckForTable = 'learning_time_segments';
  void loseNextPreferenceAck() =>
      _loseAckForTable = 'learning_time_preferences';

  void _observe(drift.QueryExecutor executor, String statement) {
    final sql = statement.toLowerCase().replaceAll('"', '');
    final table = _loseAckForTable;
    if (table != null && sql.contains('insert into $table')) {
      _affectedTransactions.add(executor);
    }
  }

  @override
  Future<void> runCustom(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _observe(executor, statement);
    return executor.runCustom(statement, args);
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _observe(executor, statement);
    return executor.runInsert(statement, args);
  }

  @override
  Future<void> commitTransaction(drift.TransactionExecutor inner) async {
    final loseAck =
        _affectedTransactions.remove(inner) && _loseAckForTable != null;
    if (loseAck) _loseAckForTable = null;
    await inner.send();
    if (loseAck) {
      lostAcknowledgements++;
      throw StateError(
        'synthetic physical time commit completed but caller ACK was lost',
      );
    }
  }

  @override
  Future<void> rollbackTransaction(drift.TransactionExecutor inner) {
    _affectedTransactions.remove(inner);
    return inner.rollback();
  }
}

final class _CopiedProof implements CanonicalLearningTimeAdmission {
  const _CopiedProof(this.original);
  final CanonicalLearningTimeAdmission original;
  @override
  String get ownerId => original.ownerId;
  @override
  String get sessionId => original.sessionId;
  @override
  String get activityType => original.activityType;
  @override
  CanonicalLearningTimeSourceKind get sourceKind => original.sourceKind;
  @override
  String get sourceBindingJson => original.sourceBindingJson;
  @override
  String get contextBindingJson => original.contextBindingJson;
  @override
  EvidenceContext get evidenceContext => original.evidenceContext;
}
