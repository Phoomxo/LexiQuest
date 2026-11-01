import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/matching_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning/domain/matching_exercise.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/learning_time/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late DriftLearningRepository canonical;
  late MatchingUseCases matching;
  var ids = 0;
  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    canonical = DriftLearningRepository(h.database, ownerWrites: h.ownerWrites);
    matching = MatchingUseCases(
      repository: DriftMatchingRepository(canonical),
      generateId: () => 'synthetic-matching-time-${++ids}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic',
        buildId: 'synthetic-matching-time',
      ),
    );
  });
  tearDown(() => h.close());

  Future<MatchingState> start() async {
    final plan = await matching.prepare(
      expectedOwnerId: configuredOwnerId,
      categoryId: configuredCategoryId,
      stillCurrent: () => true,
    );
    return matching.start(plan!, stillCurrent: () => true);
  }

  Future<CanonicalLearningTimeAdmission> admit(MatchingState state) =>
      canonical.admitCanonicalLearningTime(
        MatchingTimeAdmission(
          state,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );

  test(
    'matching time admission reads the issued selecting board without creating rows',
    () async {
      final state = await start();
      final before = await h.snapshot();
      final proof = await admit(state);
      expect(proof.sourceKind, CanonicalLearningTimeSourceKind.matching);
      expect(proof.activityType, MatchingPlan.activityType);
      expect(
        jsonDecode(proof.sourceBindingJson)['acceptedPlanId'],
        state.plan.id,
      );
      expect(
        jsonDecode(proof.contextBindingJson)['checkpointRevision'],
        state.revision,
      );
      expect(await h.snapshot(), before);
      expect(
        parseTimeBindingJson(
          proof.sourceBindingJson,
          sourceKind: TimeSourceKind.matching,
          isContext: false,
        )['kind'],
        'matching',
      );
      expect(
        parseTimeBindingJson(
          proof.contextBindingJson,
          sourceKind: TimeSourceKind.matching,
          isContext: true,
        )['phase'],
        'selecting',
      );
      final changed =
          jsonDecode(proof.contextBindingJson) as Map<String, dynamic>;
      changed['phase'] = 'answered';
      expect(
        () => parseTimeBindingJson(
          jsonEncode(changed),
          sourceKind: TimeSourceKind.matching,
          isContext: true,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'stale board and Research caller cannot admit new matching time',
    () async {
      final state = await start();
      final proof = await admit(state);
      final selected = await matching.saveSelection(
        state,
        wordIndex: 0,
        meaningIndex: 0,
        stillCurrent: () => true,
      );
      final before = await h.snapshot();
      await expectLater(admit(state), throwsStateError);
      await expectLater(
        canonical.requireLiveCanonicalLearningTimeAdmission(
          proof,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      await expectLater(
        canonical.admitCanonicalLearningTime(
          MatchingTimeAdmission(
            selected,
            callerContext: LearningTimeCallerContext.researchControlled,
          ),
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      await canonical.requireCanonicalLearningTimeAdmission(
        proof,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => true,
      );
      expect(await h.snapshot(), before);
    },
  );

  test('pending answer is not an eligible visible matching board', () async {
    var state = await start();
    state = await matching.saveSelection(
      state,
      wordIndex: 0,
      meaningIndex: 0,
      stillCurrent: () => true,
    );
    state = await matching.save(
      state,
      matching.preparePair(state, responseTime: Duration.zero),
      stillCurrent: () => true,
    );
    final before = await h.snapshot();
    await expectLater(admit(state), throwsStateError);
    expect(await h.snapshot(), before);
  });

  test(
    'actual matching source persists only confirmed interaction time through SQLite',
    () async {
      final state = await start();
      final proof = await admit(state);
      final owners = StreamController<String?>.broadcast();
      var micros = 0;
      final time = LearningTimeUseCases(
        repository: DriftLearningTimeRepository(
          database: h.database,
          ownerWrites: h.ownerWrites,
          learning: canonical,
        ),
        ownerChanges: owners.stream,
        monotonicMicros: () => micros,
        nowUtc: () => h.now,
        generateId: () => 'synthetic-matching-time-window-${++ids}',
      );
      addTearDown(() async {
        await time.dispose();
        await owners.close();
      });
      final observed = time.changes
          .firstWhere((_) => time.preference?.ownerId == configuredOwnerId)
          .timeout(const Duration(seconds: 5));
      owners.add(configuredOwnerId);
      await observed;
      await time.setEnabled(
        true,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      final lease = await time.attach(
        CanonicalTimeSource(
          proof,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        stillCurrent: () => true,
      );
      expect(lease, isNotNull);
      expect(await time.ready(lease!), isTrue);
      micros += 2000000;
      h.now = h.now.add(const Duration(seconds: 2));
      time.interacted(lease);
      time.detach(lease);
      await time.retryPending();
      expect(time.hasPending, isFalse);
      final value = await time.read(SessionTimeRead(state.plan.session.id));
      expect(value.status, RecordedTimeStatus.recorded);
      expect(value.activeDurationUs, 2000000);
      expect(value.segmentCount, 1);
      expect(await h.count('answer_attempts'), 0);
      expect(await h.count('srs_states'), 0);
      expect(await h.count('points_ledger_entries'), 0);
      expect((await h.researchCounts()).values, everyElement(0));
    },
  );
}
