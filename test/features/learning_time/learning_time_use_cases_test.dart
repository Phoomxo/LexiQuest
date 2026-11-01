import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';

void main() {
  test(
    'Tutor initial task has no invented model and reply display pins its model',
    () {
      const task = TutorTimeSource(
        episodeId: 'synthetic-tutor-episode',
        mode: TutorTimeMode.guided,
        scenario: TutorTimeScenario.cafeOrder,
        responseDisplayId: 'tutor-task:synthetic-initial-task',
        model: null,
        callerContext: LearningTimeCallerContext.ordinary,
      );
      final value = parseTimeBindingJson(
        task.contextBindingJson,
        sourceKind: TimeSourceKind.tutor,
        isContext: true,
      );
      expect(value['model'], isNull);
      expect(value['responseDisplayId'], 'tutor-task:synthetic-initial-task');
      for (final change in <Map<String, Object?>>[
        {'model': 'invented-pending-model'},
        {'responseDisplayId': 'tutor-reply:synthetic-reply'},
        {'responseDisplayId': 'tutor-task:'},
      ]) {
        expect(
          () => parseTimeBindingJson(
            jsonEncode({...value, ...change}),
            sourceKind: TimeSourceKind.tutor,
            isContext: true,
          ),
          throwsFormatException,
        );
      }
      final reply = {
        ...value,
        'responseDisplayId': 'tutor-reply:synthetic-actual-reply',
        'model': 'synthetic-actual-reply-model',
      };
      expect(
        parseTimeBindingJson(
          jsonEncode(reply),
          sourceKind: TimeSourceKind.tutor,
          isContext: true,
        ),
        reply,
      );
    },
  );
  late _Harness h;
  setUp(() async {
    h = _Harness();
    await h.start();
  });
  tearDown(() => h.dispose());

  test(
    'opening and ready alone never create a persisted scope or segment',
    () async {
      final lease = await h.attach();
      h.clock.advance(50000000);
      h.useCases.detach(lease);
      await h.settle();
      expect(h.repository.scopes, isEmpty);
      expect(h.repository.segments, isEmpty);
    },
  );

  test(
    'positive microsecond pair is kept and terminal tail is excluded',
    () async {
      final lease = await h.attach();
      h.clock.advance(1);
      h.useCases.interacted(lease);
      h.clock.advance(59000000);
      h.useCases.detach(lease);
      await h.settle();
      expect(h.repository.totalUs, 1);
      expect(h.repository.segments.values.single.activeDurationUs, 1);
    },
  );

  test('exactly sixty seconds confirms and checkpoints', () async {
    final lease = await h.attach();
    h.clock.advance(60000000);
    h.useCases.interacted(lease);
    await h.settle();
    expect(h.repository.totalUs, 60000000);
    expect(h.repository.segments.length, 1);
  });

  test('long gap credits nothing and supplies only a fresh anchor', () async {
    final lease = await h.attach();
    h.clock.advance(60000001);
    h.useCases.interacted(lease);
    expect(h.repository.segments, isEmpty);
    h.clock.advance(2000000);
    h.useCases.interacted(lease);
    h.useCases.detach(lease);
    await h.settle();
    expect(h.repository.totalUs, 2000000);
  });

  test(
    'input checkpoint permits less than 120 seconds, not an invented 60 cap',
    () async {
      final lease = await h.attach();
      h.clock.advance(59999999);
      h.useCases.interacted(lease);
      h.clock.advance(60000000);
      h.useCases.interacted(lease);
      await h.settle();
      expect(h.repository.segments.values.single.activeDurationUs, 119999999);
      expect(
        h.repository.segments.values.single.capturePolicyRevision,
        'confirmed-interaction-v1',
      );
    },
  );

  test(
    'UTC reversal never calculates or invalidates monotonic duration',
    () async {
      final lease = await h.attach();
      final startUtc = h.clock.utc;
      h.clock.advance(2000000);
      h.clock.utc = startUtc.subtract(const Duration(hours: 1));
      h.useCases.interacted(lease);
      h.useCases.detach(lease);
      await h.settle();
      final segment = h.repository.segments.values.single;
      expect(segment.activeDurationUs, 2000000);
      expect(segment.endedAtUtcMs, lessThan(segment.startedAtUtcMs));
    },
  );

  test('nonpositive monotonic gap never credits time', () async {
    final lease = await h.attach();
    h.clock.us -= 1;
    h.useCases.interacted(lease);
    h.useCases.detach(lease);
    await h.settle();
    expect(h.repository.totalUs, 0);
  });

  test('provider or save waiting is excluded until explicit ready', () async {
    final lease = await h.attach();
    h.clock.advance(4000000);
    h.useCases.interacted(lease);
    h.useCases.suspend(lease);
    await h.settle();
    h.clock.advance(90000000);
    h.useCases.interacted(lease);
    expect(h.repository.totalUs, 4000000);
    expect(await h.useCases.ready(lease), isTrue);
    h.clock.advance(3000000);
    h.useCases.interacted(lease);
    h.useCases.detach(lease);
    await h.settle();
    expect(h.repository.totalUs, 7000000);
    expect(h.repository.segments.length, 2);
  });

  test('context changes seal previous contiguous context', () async {
    final lease = await h.attach();
    h.clock.advance(2000000);
    h.useCases.interacted(lease);
    expect(await h.useCases.ready(lease, source: _reading(stage: 2)), isFalse);
    await h.settle();
    expect(await h.useCases.ready(lease, source: _reading(stage: 2)), isTrue);
    h.clock.advance(3000000);
    h.useCases.interacted(lease);
    h.useCases.detach(lease);
    await h.settle();
    expect(
      h.repository.segments.values.map(
        (s) => jsonDecode(s.eligibilityContextJson)['readingStage'],
      ),
      [1, 2],
    );
    expect(h.repository.totalUs, 5000000);
  });

  test(
    'closed A persists after B admitted and old route becomes false',
    () async {
      final gate = Completer<void>();
      h.repository.segmentGate = gate;
      var aVisible = true;
      final a = await h.attach(stillCurrent: () => aVisible);
      h.clock.advance(5000000);
      h.useCases.interacted(a);
      final b = await h.useCases.attach(
        _reading(document: 'doc-b'),
        stillCurrent: () => true,
      );
      expect(b, isNotNull);
      aVisible = false;
      expect(await h.useCases.ready(b!), isFalse);
      gate.complete();
      await h.settle();
      expect(h.repository.totalUs, 5000000);
      expect(h.repository.scopes.keys, [a.scopeId]);
      expect(await h.useCases.ready(b), isTrue);
      h.clock.advance(2000000);
      h.useCases.interacted(b);
      h.useCases.detach(b);
      await h.settle();
      expect(h.repository.totalUs, 7000000);
      expect(h.repository.scopes.length, 2);
    },
  );

  test(
    'pending write pauses input and retries the same immutable segment',
    () async {
      final lease = await h.attach();
      h.repository.loseNextSegmentAck = true;
      h.clock.advance(60000000);
      h.useCases.interacted(lease);
      await h.settle();
      expect(h.useCases.pendingState, LearningTimePendingState.segment);
      final first = h.repository.segmentCalls.single;
      h.clock.advance(5000000);
      h.useCases.interacted(lease);
      await h.useCases.retryPending();
      expect(h.repository.segmentCalls.length, 2);
      expect(identical(h.repository.segmentCalls[1], first), isTrue);
      expect(h.repository.totalUs, 60000000);
      expect(h.repository.segments.length, 1);
      expect(h.useCases.pendingState, LearningTimePendingState.none);
      h.useCases.detach(lease);
      await h.settle();
      expect(h.repository.totalUs, 60000000);
    },
  );

  test(
    'retiring closed A dependencies preserves live B and its owner gate',
    () async {
      final gate = Completer<void>();
      h.repository.segmentGate = gate;
      final a = await h.attach();
      h.clock.advance(2000000);
      h.useCases.interacted(a);
      final b = await h.useCases.attach(
        _reading(document: 'doc-b'),
        stillCurrent: () => true,
      );
      expect(b, isNotNull);
      final old = h.useCases.pendingSegmentIntent!;
      final ownerGeneration = h.useCases.ownerGeneration;
      final captureGeneration = h.useCases.captureGeneration;
      h.useCases.retireLeaseDependencies(a);
      expect(old.isCurrent, isFalse);
      expect(h.useCases.ownerGeneration, ownerGeneration);
      expect(h.useCases.captureGeneration, captureGeneration);
      expect(await h.useCases.ready(b!), isTrue);
      h.clock.advance(3000000);
      h.useCases.interacted(b);
      h.useCases.detach(b);
      gate.complete();
      await h.settle();
      await h.useCases.retryPending();
      expect(h.repository.totalUs, 3000000);
      expect(h.repository.scopes.keys, [b.scopeId]);
      expect(await h.useCases.ready(a), isFalse);
    },
  );

  test(
    'interaction readiness follows ready, suspend, pending and owner retirement',
    () async {
      final lease = await h.attach();
      expect(h.useCases.acceptsInteraction(lease), isTrue);
      h.useCases.suspend(lease);
      expect(h.useCases.acceptsInteraction(lease), isFalse);
      expect(await h.useCases.ready(lease), isTrue);
      expect(h.useCases.acceptsInteraction(lease), isTrue);
      final gate = Completer<void>();
      h.repository.segmentGate = gate;
      h.clock.advance(60000000);
      h.useCases.interacted(lease);
      expect(h.useCases.acceptsInteraction(lease), isFalse);
      gate.complete();
      await h.settle();
      expect(h.useCases.acceptsInteraction(lease), isTrue);
      h.owners.add(null);
      expect(h.useCases.acceptsInteraction(lease), isFalse);
    },
  );

  test('owner ABA retires an unacknowledged segment permanently', () async {
    final gate = Completer<void>();
    h.repository.segmentGate = gate;
    final lease = await h.attach();
    h.clock.advance(60000000);
    h.useCases.interacted(lease);
    final old = h.repository.segmentCalls.single;
    h.owners.add(null);
    h.owners.add('owner-a');
    await h.settle();
    expect(old.isCurrent, isFalse);
    gate.complete();
    await h.settle();
    await h.useCases.retryPending();
    expect(h.repository.segments, isEmpty);
    expect(h.useCases.pendingState, LearningTimePendingState.none);
  });

  test(
    'disable/re-enable gate ABA retires the original closed write',
    () async {
      final gate = Completer<void>();
      h.repository.segmentGate = gate;
      final lease = await h.attach();
      h.clock.advance(60000000);
      h.useCases.interacted(lease);
      final old = h.repository.segmentCalls.single;
      h.repository.emitPreference(false, revision: 2);
      h.repository.emitPreference(true, revision: 3);
      expect(old.isCurrent, isFalse);
      gate.complete();
      await h.settle();
      expect(h.repository.segments, isEmpty);
    },
  );

  test('dependency retirement rejects an old repository command', () async {
    final gate = Completer<void>();
    h.repository.segmentGate = gate;
    final lease = await h.attach();
    h.clock.advance(60000000);
    h.useCases.interacted(lease);
    final old = h.repository.segmentCalls.single;
    h.useCases.retireDependencies();
    gate.complete();
    await h.settle();
    expect(old.isCurrent, isFalse);
    expect(h.repository.segments, isEmpty);
  });

  test(
    'preference CAS lost ACK reuses expected revision and fixed timestamp',
    () async {
      h.repository.loseNextPreferenceAck = true;
      final result = await h.useCases.setEnabled(
        false,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      expect(result, isNull);
      expect(h.useCases.pendingState, LearningTimePendingState.preference);
      final first = h.repository.preferenceCalls.single;
      h.clock.advance(10000000);
      final replay = await h.useCases.setEnabled(
        false,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      expect(replay?.revision, 2);
      expect(identical(first, h.repository.preferenceCalls.last), isTrue);
      expect(first.expectedRevision, 1);
      expect(replay?.updatedAtUtcMs, first.updatedAtUtcMs);
      expect(h.repository.preference.revision, 2);
    },
  );

  test(
    'pending setting retry cannot acknowledge a new owner generation after ABA',
    () async {
      h.repository.loseNextPreferenceAck = true;
      expect(
        await h.useCases.setEnabled(
          false,
          expectedOwnerId: 'owner-a',
          stillCurrent: () => true,
        ),
        isNull,
      );
      final original = h.useCases.pendingPreferenceIntent!;
      final committed = h.repository.preference;
      expect(committed.revision, 2);
      final gate = Completer<void>();
      h.repository.preferenceGate = gate;
      final retry = h.useCases.setEnabled(
        false,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      try {
        expect(h.repository.preferenceCalls, hasLength(2));
        expect(h.repository.preferenceCalls.last, same(original));
        h.owners.add('owner-b');
        await h.settle();
        h.owners.add('owner-a');
        await h.settle();
        expect(h.useCases.ownerId, 'owner-a');
        expect(h.useCases.preference?.sameAs(committed), isTrue);
        expect(original.isCurrent, isFalse);
        expect(h.useCases.pendingState, LearningTimePendingState.none);
      } finally {
        gate.complete();
      }
      expect(await retry, isNull);
      expect(h.repository.preference.sameAs(committed), isTrue);
      expect(h.repository.preferenceCalls.last, same(original));
    },
  );

  test(
    'no-op preference retains the live collector and creates no row',
    () async {
      final lease = await h.attach();
      final result = await h.useCases.setEnabled(
        true,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      expect(result?.revision, 1);
      expect(h.repository.preferenceCalls, isEmpty);
      h.clock.advance(2000000);
      h.useCases.interacted(lease);
      h.useCases.detach(lease);
      await h.settle();
      expect(h.repository.totalUs, 2000000);
    },
  );

  test(
    'external gate revision retires the old unacknowledged preference CAS',
    () async {
      final gate = Completer<void>();
      h.repository.preferenceGate = gate;
      final setting = h.useCases.setEnabled(
        false,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      final old = h.repository.preferenceCalls.single;
      h.repository.emitPreference(true, revision: 3);
      expect(old.isCurrent, isFalse);
      gate.complete();
      expect(await setting, isNull);
      expect(h.useCases.pendingState, LearningTimePendingState.none);
      expect(h.repository.preference.revision, 3);
    },
  );

  test(
    'delayed lower preference revisions cannot undo a confirmed CAS',
    () async {
      final original = h.repository.preference;
      final disabled = await h.useCases.setEnabled(
        false,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      expect(disabled?.revision, 2);
      final capture = h.useCases.captureGeneration;
      h.repository.controller.add(original);
      expect(h.useCases.preference?.revision, 2);
      expect(h.useCases.preference?.enabled, isFalse);
      expect(h.useCases.captureGeneration, capture);
      h.repository.controller.add(null);
      expect(h.useCases.preference, isNull);
      h.repository.controller.add(original);
      expect(h.useCases.preference, isNull);
      h.repository.controller.add(h.repository.preference);
      final enabled = await h.useCases.setEnabled(
        true,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      expect(enabled?.revision, 3);
    },
  );

  test(
    'setting awaits its own queued ACK before the opposite setting',
    () async {
      final gate = Completer<void>();
      h.repository.segmentGate = gate;
      final lease = await h.attach();
      h.clock.advance(60000000);
      h.useCases.interacted(lease);
      final disabled = h.useCases.setEnabled(
        false,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      gate.complete();
      expect((await disabled)?.enabled, isFalse);
      final enabled = await h.useCases.setEnabled(
        true,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      expect(enabled?.enabled, isTrue);
      expect(enabled?.revision, 3);
      expect(h.repository.segments, isEmpty);
      expect(h.useCases.hasPending, isFalse);
    },
  );

  test(
    'captured-owner settings callback cannot write the next owner',
    () async {
      h.owners.add('owner-b');
      await h.settle();
      expect(
        await h.useCases.setEnabled(
          false,
          expectedOwnerId: 'owner-a',
          stillCurrent: () => true,
        ),
        isNull,
      );
      expect(h.repository.preferenceCalls, isEmpty);
    },
  );

  test(
    'acknowledged history stays readable after capture is disabled',
    () async {
      final lease = await h.attach();
      h.clock.advance(3000000);
      h.useCases.interacted(lease);
      h.useCases.detach(lease);
      await h.settle();
      await h.useCases.setEnabled(
        false,
        expectedOwnerId: 'owner-a',
        stillCurrent: () => true,
      );
      final before = h.repository.segmentCalls.length;
      final read = await h.useCases.read(const OwnerTimeRead());
      expect(read.status, RecordedTimeStatus.recorded);
      expect(read.activeDurationUs, 3000000);
      expect(h.repository.segmentCalls.length, before);
      h.owners.add(null);
      expect(
        (await h.useCases.read(const OwnerTimeRead())).status,
        RecordedTimeStatus.unavailable,
      );
    },
  );

  test('Research/unavailable caller cannot attach ordinary time', () async {
    expect(
      await h.useCases.attach(
        _reading(context: LearningTimeCallerContext.researchControlled),
        stillCurrent: () => true,
      ),
      isNull,
    );
    expect(
      await h.useCases.attach(
        _reading(context: LearningTimeCallerContext.unavailable),
        stillCurrent: () => true,
      ),
      isNull,
    );
    expect(h.repository.scopes, isEmpty);
  });

  test('a prepared real link before any pair remains memory-only', () async {
    final lease = await h.attach();
    final proof = _ReadingProof('session-reading', _reading());
    final link = await h.useCases.prepareSessionLink(lease, proof);
    expect(link, isNotNull);
    expect(h.useCases.acknowledgeSessionLink(lease, link!), isTrue);
    await h.settle();
    expect(h.repository.scopes, isEmpty);
    expect(h.repository.linkCalls, isEmpty);
    h.clock.advance(2000000);
    h.useCases.interacted(lease);
    h.useCases.detach(lease);
    await h.settle();
    final segment = h.repository.segments.values.single;
    expect(segment.scope.linkedSessionId, proof.sessionId);
    expect(identical(segment.sessionLinkAdmission, link), isTrue);
    expect(h.repository.totalUs, 2000000);
  });

  test(
    'post-recording link writes dedicated link fields without another segment',
    () async {
      final lease = await h.attach();
      h.clock.advance(2000000);
      h.useCases.interacted(lease);
      h.useCases.suspend(lease);
      await h.settle();
      final link = await h.useCases.prepareSessionLink(
        lease,
        _ReadingProof('session-reading', _reading()),
      );
      expect(h.useCases.acknowledgeSessionLink(lease, link!), isTrue);
      await h.settle();
      expect(h.repository.linkCalls.length, 1);
      expect(h.repository.segments.length, 1);
      expect(h.repository.totalUs, 2000000);
    },
  );

  test('public copied link DTO cannot mint a repository command', () async {
    final lease = await h.attach();
    final fake = TimeSessionLinkAdmission(
      ownerId: 'owner-a',
      scopeId: lease.scopeId,
      linkedSessionId: 'fake',
      sessionLinkBindingJson: '{}',
      verifyClosed: (_) async {},
    );
    expect(h.useCases.acknowledgeSessionLink(lease, fake), isFalse);
    expect(h.repository.linkCalls, isEmpty);
  });

  test(
    'strict binding masks reject wrong value types and raw extra fields',
    () {
      expect(
        parseTimeBindingJson(
          _reading(stage: 6).contextBindingJson,
          sourceKind: TimeSourceKind.reading,
          isContext: true,
        )['readingStage'],
        6,
      );
      final target = ReadingTimeSource(
        documentId: 'doc-a',
        documentRevision: 1,
        snapshotSha256: List.filled(64, 'a').join(),
        targetPinsSha256: List.filled(64, 'b').join(),
        readingStage: 3,
        targetWordId: 'word-a',
        targetContentRevision: 'synthetic-r1',
        callerContext: LearningTimeCallerContext.ordinary,
      );
      expect(
        parseTimeBindingJson(
          target.contextBindingJson,
          sourceKind: TimeSourceKind.reading,
          isContext: true,
        )['wordId'],
        'word-a',
      );
      final wrongStage =
          jsonDecode(target.contextBindingJson) as Map<String, dynamic>;
      wrongStage['readingStage'] = 4;
      expect(
        () => parseTimeBindingJson(
          jsonEncode(wrongStage),
          sourceKind: TimeSourceKind.reading,
          isContext: true,
        ),
        throwsFormatException,
      );
      final source =
          jsonDecode(_reading().sourceBindingJson) as Map<String, dynamic>;
      source['documentId'] = 123;
      expect(
        () => parseTimeBindingJson(
          jsonEncode(source),
          sourceKind: TimeSourceKind.reading,
          isContext: false,
        ),
        throwsFormatException,
      );
      source['documentId'] = 'doc-a';
      source['passage'] = 'must never persist';
      expect(
        () => parseTimeBindingJson(
          jsonEncode(source),
          sourceKind: TimeSourceKind.reading,
          isContext: false,
        ),
        throwsFormatException,
      );
    },
  );
}

ReadingTimeSource _reading({
  String document = 'doc-a',
  int stage = 1,
  LearningTimeCallerContext context = LearningTimeCallerContext.ordinary,
}) => ReadingTimeSource(
  documentId: document,
  documentRevision: 1,
  snapshotSha256: List.filled(64, 'a').join(),
  targetPinsSha256: List.filled(64, 'b').join(),
  readingStage: stage,
  callerContext: context,
);

final class _Clock {
  int us = 0;
  DateTime utc = DateTime.utc(2026, 10, 31);
  void advance(int durationUs) {
    us += durationUs;
    utc = utc.add(Duration(microseconds: durationUs));
  }
}

final class _Harness {
  final clock = _Clock();
  final repository = _Repository();
  final owners = StreamController<String?>.broadcast(sync: true);
  late final LearningTimeUseCases useCases;
  int nextId = 0;
  Future<void> start() async {
    useCases = LearningTimeUseCases(
      repository: repository,
      ownerChanges: owners.stream,
      monotonicMicros: () => clock.us,
      nowUtc: () => clock.utc,
      generateId: () => '${nextId++}',
    );
    owners.add('owner-a');
    await settle();
  }

  Future<LiveTimeLease> attach({bool Function()? stillCurrent}) async {
    final lease = await useCases.attach(
      _reading(),
      stillCurrent: stillCurrent ?? () => true,
    );
    expect(lease, isNotNull);
    expect(await useCases.ready(lease!), isTrue);
    return lease;
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> dispose() async {
    await useCases.dispose();
    await owners.close();
    await repository.controller.close();
  }
}

final class _Repository implements LearningTimeRepository {
  LearningTimePreference preference = const LearningTimePreference(
    ownerId: 'owner-a',
    enabled: true,
    revision: 1,
    updatedAtUtcMs: 1,
  );
  final controller = StreamController<LearningTimePreference?>.broadcast(
    sync: true,
  );
  final scopes = <String, LearningTimeScope>{};
  final segments = <String, ClosedTimeSegmentIntent>{};
  final segmentCalls = <ClosedTimeSegmentIntent>[];
  final preferenceCalls = <LearningTimePreferenceIntent>[];
  final linkCalls = <TimeSessionLinkIntent>[];
  Completer<void>? segmentGate;
  Completer<void>? preferenceGate;
  bool loseNextSegmentAck = false;
  bool loseNextPreferenceAck = false;
  int get totalUs =>
      segments.values.fold(0, (sum, value) => sum + value.activeDurationUs);

  void emitPreference(bool enabled, {required int revision}) {
    preference = LearningTimePreference(
      ownerId: preference.ownerId,
      enabled: enabled,
      revision: revision,
      updatedAtUtcMs: revision,
    );
    controller.add(preference);
  }

  @override
  Stream<LearningTimePreference?> watchPreference(String ownerId) async* {
    yield preference.ownerId == ownerId
        ? preference
        : LearningTimePreference.absent(ownerId);
    yield* controller.stream;
  }

  @override
  Future<LearningTimePreference> readPreference({
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) throw StateError('stale owner');
    return preference;
  }

  @override
  Future<LearningTimePreference> commitPreference(
    LearningTimePreferenceIntent intent,
  ) async {
    preferenceCalls.add(intent);
    final gate = preferenceGate;
    preferenceGate = null;
    if (gate != null) await gate.future;
    if (!intent.belongsTo(this) || !intent.isCurrent) {
      throw StateError('stale setting');
    }
    final exactReplay =
        preference.ownerId == intent.ownerId &&
        preference.revision == intent.expectedRevision + 1 &&
        preference.enabled == intent.enabled &&
        preference.updatedAtUtcMs == intent.updatedAtUtcMs;
    if (!exactReplay) {
      if (preference.ownerId != intent.ownerId ||
          preference.revision != intent.expectedRevision) {
        throw StateError('CAS');
      }
      preference = LearningTimePreference(
        ownerId: intent.ownerId,
        enabled: intent.enabled,
        revision: intent.expectedRevision + 1,
        updatedAtUtcMs: intent.updatedAtUtcMs,
      );
      controller.add(preference);
    }
    if (loseNextPreferenceAck) {
      loseNextPreferenceAck = false;
      throw StateError('synthetic lost ACK');
    }
    return preference;
  }

  @override
  Future<TimeSourceAdmission> admitSource({
    required TimeSource source,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent() || source is! ReadingTimeSource) {
      throw StateError('not admitted');
    }
    return TimeSourceAdmission(
      ownerId: expectedOwnerId,
      sourceKind: TimeSourceKind.reading,
      sourceBindingJson: source.sourceBindingJson,
      contextBindingJson: source.contextBindingJson,
      verifyClosed: (current) async {
        if (!current()) throw StateError('closed permission retired');
      },
    );
  }

  @override
  Future<void> commitSegment(ClosedTimeSegmentIntent intent) async {
    segmentCalls.add(intent);
    final gate = segmentGate;
    segmentGate = null;
    if (gate != null) await gate.future;
    if (!intent.belongsTo(this) ||
        !intent.isCurrent ||
        !preference.enabled ||
        preference.revision != intent.preferenceRevision) {
      throw StateError('closed write retired');
    }
    await intent.admission.verifyClosed(
      ownerStillCurrent: () => intent.isCurrent,
    );
    await intent.sessionLinkAdmission?.verifyClosed(
      ownerStillCurrent: () => intent.isCurrent,
    );
    final existing = segments[intent.id];
    if (existing != null && !identical(existing, intent)) {
      throw StateError('changed replay');
    }
    scopes.putIfAbsent(intent.scope.id, () => intent.scope);
    segments[intent.id] = intent;
    if (loseNextSegmentAck) {
      loseNextSegmentAck = false;
      throw StateError('synthetic lost ACK');
    }
  }

  @override
  Future<TimeSessionLinkAdmission> prepareSessionLink({
    required LearningTimeScope scope,
    required CanonicalLearningTimeSessionLinkReceipt proof,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent() ||
        proof.ownerId != expectedOwnerId ||
        proof.sourceBindingJson != scope.sourceBindingJson) {
      throw StateError('foreign link');
    }
    return TimeSessionLinkAdmission(
      ownerId: expectedOwnerId,
      scopeId: scope.id,
      linkedSessionId: proof.sessionId,
      sessionLinkBindingJson: jsonEncode({
        'schemaVersion': 1,
        'sessionId': proof.sessionId,
        'sourceBindingSha256': List.filled(64, 'c').join(),
        'canonicalSourceBindingSha256': List.filled(64, 'c').join(),
      }),
      verifyClosed: (current) async {
        if (!current()) throw StateError('link retired');
      },
    );
  }

  @override
  Future<void> commitSessionLink(TimeSessionLinkIntent intent) async {
    linkCalls.add(intent);
    if (!intent.belongsTo(this) ||
        !intent.isCurrent ||
        !scopes.containsKey(intent.scope.id)) {
      throw StateError('link retired');
    }
    await intent.admission.verifyClosed(
      ownerStillCurrent: () => intent.isCurrent,
    );
  }

  @override
  Future<RecordedTimeRead> read({
    required TimeReadTarget target,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return const RecordedTimeRead.unavailable();
    final values = segments.values.where(
      (s) => s.scope.ownerId == expectedOwnerId,
    );
    if (values.isEmpty) return const RecordedTimeRead.noneRecorded();
    return RecordedTimeRead.recorded(
      activeDurationUs: values.fold(0, (sum, s) => sum + s.activeDurationUs),
      segmentCount: values.length,
    );
  }
}

final class _ReadingProof implements CanonicalLearningTimeAdmission {
  _ReadingProof(this.sessionId, this.source);
  final ReadingTimeSource source;
  @override
  final String sessionId;
  @override
  String get ownerId => 'owner-a';
  @override
  String get activityType => 'reading';
  @override
  CanonicalLearningTimeSourceKind get sourceKind =>
      CanonicalLearningTimeSourceKind.reading;
  @override
  String get sourceBindingJson => source.sourceBindingJson;
  @override
  String get contextBindingJson => source.contextBindingJson;
  @override
  EvidenceContext get evidenceContext => EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.recognition,
    skillId: 'reading-recall',
    hintLevel: 0,
    contentRevision: 'synthetic-r1',
    rolloutMode: EvidencePolicyRolloutMode.legacy,
  );
}
