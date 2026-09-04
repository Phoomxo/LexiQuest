import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_recovery_use_cases.dart';

import 'adventure_learning_bridge_test.dart' show createAdventureTestPlan;

void main() {
  test(
    'write failure retains and retries the exact immutable identity',
    () async {
      final gateway = _Gateway()..failRecord = true;
      final useCases = AdventureRecoveryUseCases(
        gateway: gateway,
        canStartNewMission: () => true,
      );
      await useCases.startOrResume(
        plan: createAdventureTestPlan(),
        activeOwnerId: 'owner:one',
        sessionId: 'session:one',
      );
      final retry = AdventureExactRetry(
        evidenceId: 'evidence:one',
        sessionId: 'session:one',
        ownerId: 'owner:one',
        payloadFingerprint: 'sha256:one',
        payload: const <String, Object?>{'answer': 'station', 'attempt': 1},
      );

      await expectLater(useCases.record(retry), throwsStateError);
      gateway.failRecord = false;
      await useCases.retry('evidence:one');

      expect(gateway.records, hasLength(2));
      expect(identical(gateway.records[0], gateway.records[1]), isTrue);
      expect(useCases.pendingRetries, isEmpty);
    },
  );

  test('accepted session resumes before any new mission', () async {
    final gateway = _Gateway();
    final useCases = AdventureRecoveryUseCases(
      gateway: gateway,
      canStartNewMission: () => true,
    );
    final plan = createAdventureTestPlan();
    final first = await useCases.startOrResume(
      plan: plan,
      activeOwnerId: 'owner:one',
      sessionId: 'session:one',
    );
    final resumed = await useCases.startOrResume(
      plan: plan,
      activeOwnerId: 'owner:one',
      sessionId: 'session:two',
    );
    expect(resumed.sessionId, first.sessionId);
    expect(gateway.starts, 1);
    expect(gateway.resumes, 1);
  });

  test(
    'emergency off blocks new start but allows accepted session close',
    () async {
      final gateway = _Gateway();
      var enabled = true;
      final useCases = AdventureRecoveryUseCases(
        gateway: gateway,
        canStartNewMission: () => enabled,
      );
      await useCases.startOrResume(
        plan: createAdventureTestPlan(),
        activeOwnerId: 'owner:one',
        sessionId: 'session:one',
      );
      enabled = false;
      await useCases.close();
      expect(gateway.closes, 1);

      final fresh = AdventureRecoveryUseCases(
        gateway: gateway,
        canStartNewMission: () => false,
      );
      await expectLater(
        fresh.startOrResume(
          plan: createAdventureTestPlan(),
          activeOwnerId: 'owner:one',
          sessionId: 'session:new',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'owner switch rejects accepted session without gateway mutation',
    () async {
      final gateway = _Gateway();
      final useCases = AdventureRecoveryUseCases(
        gateway: gateway,
        canStartNewMission: () => true,
      );
      final plan = createAdventureTestPlan();
      await useCases.startOrResume(
        plan: plan,
        activeOwnerId: 'owner:one',
        sessionId: 'session:one',
      );
      await expectLater(
        useCases.startOrResume(
          plan: plan,
          activeOwnerId: 'owner:other',
          sessionId: 'session:other',
        ),
        throwsStateError,
      );
      expect(gateway.starts, 1);
      expect(gateway.resumes, 0);
    },
  );

  test(
    'same evidence identity cannot be reused with another payload',
    () async {
      final gateway = _Gateway()..failRecord = true;
      final useCases = AdventureRecoveryUseCases(
        gateway: gateway,
        canStartNewMission: () => true,
      );
      await useCases.startOrResume(
        plan: createAdventureTestPlan(),
        activeOwnerId: 'owner:one',
        sessionId: 'session:one',
      );
      final first = AdventureExactRetry(
        evidenceId: 'evidence:one',
        sessionId: 'session:one',
        ownerId: 'owner:one',
        payloadFingerprint: 'sha256:one',
        payload: const <String, Object?>{'answer': 'station', 'attempt': 1},
      );
      await expectLater(useCases.record(first), throwsStateError);

      final conflict = AdventureExactRetry(
        evidenceId: 'evidence:one',
        sessionId: 'session:one',
        ownerId: 'owner:one',
        payloadFingerprint: 'sha256:one',
        payload: const <String, Object?>{'answer': 'station', 'attempt': 2},
      );
      await expectLater(useCases.record(conflict), throwsStateError);
      expect(gateway.records, hasLength(1));
    },
  );

  test('retry payload is deeply frozen and canonically ordered', () {
    final nested = <Object?>[
      1,
      <String, Object?>{'value': true},
    ];
    final first = AdventureExactRetry(
      evidenceId: 'evidence:one',
      sessionId: 'session:one',
      ownerId: 'owner:one',
      payloadFingerprint: 'sha256:one',
      payload: <String, Object?>{'z': nested, 'a': 1},
    );
    final reordered = AdventureExactRetry(
      evidenceId: 'evidence:one',
      sessionId: 'session:one',
      ownerId: 'owner:one',
      payloadFingerprint: 'sha256:one',
      payload: const <String, Object?>{
        'a': 1,
        'z': <Object?>[
          1,
          <String, Object?>{'value': true},
        ],
      },
    );
    nested.add(2);

    expect(first.canonicalPayload, reordered.canonicalPayload);
    expect(first.payload['z'], hasLength(2));
    expect(
      () => (first.payload['z']! as List<Object?>).add(3),
      throwsUnsupportedError,
    );
  });
}

final class _Gateway implements AdventureRecoveryGateway {
  int starts = 0;
  int resumes = 0;
  int closes = 0;
  bool failRecord = false;
  final List<AdventureExactRetry> records = <AdventureExactRetry>[];

  @override
  Future<void> start(AdventureRecoverySession session) async => starts += 1;
  @override
  Future<void> resume(AdventureRecoverySession session) async => resumes += 1;
  @override
  Future<void> close(AdventureRecoverySession session) async => closes += 1;
  @override
  Future<void> record(AdventureExactRetry retry) async {
    records.add(retry);
    if (failRecord) throw StateError('offline');
  }
}
