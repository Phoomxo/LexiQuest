import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_repair_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';

void main() {
  test('repair becomes due after exactly 3 to 5 eligible items', () {
    for (final spacing in <int>[3, 4, 5]) {
      final policy = AdventureRepairPolicy(
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => spacing,
      );
      final wrong = policy.recordAttempt(
        attempt: _attempt(
          index: 0,
          mode: LessonMode.typedRecall,
          outcome: AdventureAttemptOutcome.incorrect,
        ),
        remainingOriginalItems: 8,
      );

      expect(wrong.disposition, AdventureRepairDisposition.scheduled);
      expect(wrong.dueRepairs, isEmpty);
      for (var index = 1; index <= spacing; index += 1) {
        final observation = policy.recordAttempt(
          attempt: _attempt(
            index: index,
            outcome: AdventureAttemptOutcome.correct,
          ),
          remainingOriginalItems: 8 - index,
        );
        expect(
          observation.dueRepairs,
          index == spacing ? hasLength(1) : isEmpty,
        );
      }

      final ticket = policy.tickets.single;
      expect(ticket.dueAfterEligibleItems, spacing);
      expect(ticket.state, AdventureRepairTicketState.due);
      expect(ticket.repairMode, LessonMode.cloze);
      expect(ticket.repairPromptVariant, 'clozeSelected');
    }
  });

  test('fewer than three remaining items defers without padding', () {
    for (final remaining in <int>[0, 1, 2]) {
      final policy = AdventureRepairPolicy(
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => 3,
      );

      final decision = policy.recordAttempt(
        attempt: _attempt(index: 0, outcome: AdventureAttemptOutcome.incorrect),
        remainingOriginalItems: remaining,
      );

      expect(
        decision.disposition,
        AdventureRepairDisposition.deferredToCanonicalReview,
      );
      expect(decision.dueRepairs, isEmpty);
      expect(policy.tickets.single.state, AdventureRepairTicketState.deferred);
    }
  });

  test('recognition-root incorrect defers when remaining originals cannot '
      'advance independent-recall spacing', () {
    for (final mode in <LessonMode>[
      LessonMode.meaningQuiz,
      LessonMode.definitionQuiz,
      LessonMode.matching,
    ]) {
      final policy = AdventureRepairPolicy(
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => 3,
      );

      final decision = policy.recordAttempt(
        attempt: _attempt(
          index: 0,
          mode: mode,
          outcome: AdventureAttemptOutcome.incorrect,
          evidenceClass: EvidenceClass.recognition,
        ),
        remainingOriginalItems: 8,
      );

      expect(
        decision.disposition,
        AdventureRepairDisposition.deferredToCanonicalReview,
        reason: mode.name,
      );
      expect(decision.dueRepairs, isEmpty, reason: mode.name);
      expect(
        policy.tickets.single.state,
        AdventureRepairTicketState.deferred,
        reason: mode.name,
      );
      expect(policy.tickets.single.dueAfterEligibleItems, 0);
    }
  });

  test('independent-recall incorrect still schedules same-session repair', () {
    final policy = AdventureRepairPolicy(
      isModeEligible: (_, _, _) => true,
      spacingForIdentity: (_) => 3,
    );

    final decision = policy.recordAttempt(
      attempt: _attempt(
        index: 0,
        mode: LessonMode.typedRecall,
        outcome: AdventureAttemptOutcome.incorrect,
        evidenceClass: EvidenceClass.independentRecall,
      ),
      remainingOriginalItems: 8,
    );

    expect(decision.disposition, AdventureRepairDisposition.scheduled);
    expect(policy.tickets.single.state, AdventureRepairTicketState.waiting);
    expect(policy.tickets.single.dueAfterEligibleItems, 3);
  });

  test('unscheduled deferrals roundtrip without a phantom repair target', () {
    for (final testCase
        in <({LessonMode mode, EvidenceClass evidence, int remaining})>[
          (
            mode: LessonMode.typedRecall,
            evidence: EvidenceClass.independentRecall,
            remaining: 2,
          ),
          (
            mode: LessonMode.meaningQuiz,
            evidence: EvidenceClass.recognition,
            remaining: 8,
          ),
        ]) {
      final policy = AdventureRepairPolicy(
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => 3,
      );
      policy.recordAttempt(
        attempt: _attempt(
          index: testCase.remaining,
          mode: testCase.mode,
          outcome: AdventureAttemptOutcome.incorrect,
          evidenceClass: testCase.evidence,
        ),
        remainingOriginalItems: testCase.remaining,
      );

      final restored = AdventureRepairPolicy.restore(
        AdventureRepairPolicySnapshot.fromJson(policy.snapshot().toJson()),
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => 3,
      );

      expect(
        restored.tickets.single.state,
        AdventureRepairTicketState.deferred,
      );
      expect(restored.tickets.single.repairMode, isNull);
      expect(restored.tickets.single.repairPromptVariant, isNull);
      expect(restored.tickets.single.dueAfterEligibleItems, 0);
    }
  });

  test(
    'spacing counts only distinct committed independent non-repair answers',
    () {
      final policy = AdventureRepairPolicy(
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => 3,
      );
      policy.recordAttempt(
        attempt: _attempt(index: 0, outcome: AdventureAttemptOutcome.incorrect),
        remainingOriginalItems: 9,
      );

      final ignored = <AdventureRepairAttempt>[
        _attempt(
          index: 1,
          outcome: AdventureAttemptOutcome.skipped,
          committed: false,
        ),
        _attempt(
          index: 2,
          outcome: AdventureAttemptOutcome.technical,
          committed: false,
        ),
        _attempt(index: 3, outcome: AdventureAttemptOutcome.guided),
        _attempt(index: 4, outcome: AdventureAttemptOutcome.exposure),
        _attempt(
          index: 10,
          mode: LessonMode.meaningQuiz,
          outcome: AdventureAttemptOutcome.correct,
          evidenceClass: EvidenceClass.recognition,
        ),
        _attempt(
          index: 5,
          outcome: AdventureAttemptOutcome.correct,
          committed: false,
        ),
        _attempt(
          index: 6,
          outcome: AdventureAttemptOutcome.correct,
          isRepair: true,
        ),
      ];
      for (final attempt in ignored) {
        expect(
          policy
              .recordAttempt(attempt: attempt, remainingOriginalItems: 5)
              .dueRepairs,
          isEmpty,
        );
      }

      for (final index in <int>[7, 7, 8]) {
        expect(
          policy
              .recordAttempt(
                attempt: _attempt(
                  index: index,
                  outcome: AdventureAttemptOutcome.correct,
                ),
                remainingOriginalItems: 4,
              )
              .dueRepairs,
          isEmpty,
        );
      }
      final due = policy.recordAttempt(
        attempt: _attempt(index: 9, outcome: AdventureAttemptOutcome.correct),
        remainingOriginalItems: 3,
      );

      expect(due.dueRepairs, hasLength(1));
      expect(policy.tickets.single.eligibleInterveningIdentities, hasLength(3));
    },
  );

  test('support ladder always moves toward earlier available support', () {
    final cases =
        <
          ({LessonMode current, Set<LessonMode> eligible, LessonMode? expected})
        >[
          (
            current: LessonMode.typedRecall,
            eligible: <LessonMode>{
              LessonMode.flashcard,
              LessonMode.meaningQuiz,
              LessonMode.matching,
              LessonMode.cloze,
              LessonMode.typedRecall,
            },
            expected: LessonMode.cloze,
          ),
          (
            current: LessonMode.typedRecall,
            eligible: <LessonMode>{LessonMode.meaningQuiz},
            expected: LessonMode.meaningQuiz,
          ),
          (
            current: LessonMode.cloze,
            eligible: <LessonMode>{LessonMode.matching},
            expected: LessonMode.matching,
          ),
          (
            current: LessonMode.matching,
            eligible: <LessonMode>{LessonMode.flashcard},
            expected: LessonMode.flashcard,
          ),
          (
            current: LessonMode.meaningQuiz,
            eligible: <LessonMode>{LessonMode.flashcard},
            expected: LessonMode.flashcard,
          ),
          (
            current: LessonMode.flashcard,
            eligible: LessonMode.values.toSet(),
            expected: null,
          ),
        ];

    for (final testCase in cases) {
      final policy = AdventureRepairPolicy(
        isModeEligible: (_, mode, _) => testCase.eligible.contains(mode),
        spacingForIdentity: (_) => 3,
      );
      final decision = policy.recordAttempt(
        attempt: _attempt(
          index: 0,
          mode: testCase.current,
          outcome: AdventureAttemptOutcome.incorrect,
        ),
        remainingOriginalItems: 5,
      );

      expect(policy.tickets.single.repairMode, testCase.expected);
      expect(
        policy.tickets.single.repairPromptVariant,
        testCase.expected == null ? isNull : _promptForMode(testCase.expected!),
      );
      expect(
        decision.disposition,
        testCase.expected == null
            ? AdventureRepairDisposition.deferredToCanonicalReview
            : AdventureRepairDisposition.scheduled,
      );
    }
  });

  test('scheduled definition repairs roundtrip for every source mode', () {
    for (final originalMode in <LessonMode>[
      LessonMode.typedRecall,
      LessonMode.cloze,
    ]) {
      final policy = AdventureRepairPolicy(
        isModeEligible: (_, mode, promptVariant) =>
            mode == LessonMode.definitionQuiz &&
            promptVariant == 'definitionChoice',
        spacingForIdentity: (_) => 3,
      );
      final decision = policy.recordAttempt(
        attempt: _attempt(
          index: originalMode.index,
          mode: originalMode,
          outcome: AdventureAttemptOutcome.incorrect,
        ),
        remainingOriginalItems: 5,
      );
      final snapshotJson = policy.snapshot().toJson();

      expect(decision.disposition, AdventureRepairDisposition.scheduled);
      expect(policy.tickets.single.repairMode, LessonMode.definitionQuiz);
      expect(
        policy.tickets.single.repairPromptVariant,
        'definitionChoice',
      );

      final restored = AdventureRepairPolicy.restore(
        AdventureRepairPolicySnapshot.fromJson(snapshotJson),
        isModeEligible: (_, mode, promptVariant) =>
            mode == LessonMode.definitionQuiz &&
            promptVariant == 'definitionChoice',
        spacingForIdentity: (_) => 3,
      );

      expect(restored.snapshot().toJson(), equals(snapshotJson));
    }
  });

  test('support availability is checked for the exact item and prompt', () {
    final observed = <(ContentIdentity, LessonMode, String)>[];
    final policy = AdventureRepairPolicy(
      isModeEligible: (identity, mode, promptVariant) {
        observed.add((identity, mode, promptVariant));
        return mode == LessonMode.meaningQuiz &&
            promptVariant == 'meaningChoice';
      },
      spacingForIdentity: (_) => 3,
    );

    policy.recordAttempt(
      attempt: _attempt(
        index: 4,
        mode: LessonMode.typedRecall,
        outcome: AdventureAttemptOutcome.incorrect,
      ),
      remainingOriginalItems: 5,
    );

    expect(observed, <(ContentIdentity, LessonMode, String)>[
      (
        const ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: 'word:4',
          revision: 1,
        ),
        LessonMode.cloze,
        'clozeSelected',
      ),
      (
        const ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: 'word:4',
          revision: 1,
        ),
        LessonMode.meaningQuiz,
        'meaningChoice',
      ),
    ]);
    expect(policy.tickets.single.repairMode, LessonMode.meaningQuiz);
    expect(policy.tickets.single.repairPromptVariant, 'meaningChoice');
  });

  test('multiple wrong identities retain independent stable tickets', () {
    final policy = AdventureRepairPolicy(
      isModeEligible: (_, _, _) => true,
      spacingForIdentity: (_) => 3,
    );
    for (final index in <int>[0, 1]) {
      expect(
        policy
            .recordAttempt(
              attempt: _attempt(
                index: index,
                mode: LessonMode.typedRecall,
                outcome: AdventureAttemptOutcome.incorrect,
              ),
              remainingOriginalItems: 8,
            )
            .disposition,
        AdventureRepairDisposition.scheduled,
      );
    }

    final dueIds = <String>[];
    for (final index in <int>[2, 3, 4]) {
      final decision = policy.recordAttempt(
        attempt: _attempt(
          index: index,
          outcome: AdventureAttemptOutcome.correct,
        ),
        remainingOriginalItems: 8 - index,
      );
      dueIds.addAll(decision.dueRepairs.map((ticket) => ticket.identity.id));
    }

    expect(dueIds, <String>['word:0', 'word:1']);
    expect(policy.tickets, hasLength(2));
  });

  test('committed independent incorrect advances older repair spacing', () {
    final policy = AdventureRepairPolicy(
      isModeEligible: (_, _, _) => true,
      spacingForIdentity: (_) => 3,
    );
    policy.recordAttempt(
      attempt: _attempt(index: 0, outcome: AdventureAttemptOutcome.incorrect),
      remainingOriginalItems: 7,
    );

    final secondWrong = policy.recordAttempt(
      attempt: _attempt(index: 1, outcome: AdventureAttemptOutcome.incorrect),
      remainingOriginalItems: 6,
    );

    expect(secondWrong.disposition, AdventureRepairDisposition.scheduled);
    expect(secondWrong.dueRepairs, isEmpty);
    expect(
      policy.tickets.first.eligibleInterveningIdentities,
      <ContentIdentity>{
        const ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: 'word:1',
          revision: 1,
        ),
      },
    );
    expect(policy.tickets, hasLength(2));
  });

  test(
    'a repair never schedules recursively and failed repair stays Review',
    () {
      final policy = AdventureRepairPolicy(
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => 3,
      );
      policy.recordAttempt(
        attempt: _attempt(
          index: 0,
          mode: LessonMode.typedRecall,
          outcome: AdventureAttemptOutcome.incorrect,
        ),
        remainingOriginalItems: 5,
      );
      for (final index in <int>[1, 2, 3]) {
        policy.recordAttempt(
          attempt: _attempt(
            index: index,
            outcome: AdventureAttemptOutcome.correct,
          ),
          remainingOriginalItems: 5 - index,
        );
      }

      final repair = policy.recordAttempt(
        attempt: _attempt(
          index: 0,
          mode: LessonMode.cloze,
          outcome: AdventureAttemptOutcome.incorrect,
          isRepair: true,
        ),
        remainingOriginalItems: 2,
      );

      expect(
        repair.disposition,
        AdventureRepairDisposition.deferredToCanonicalReview,
      );
      expect(policy.tickets, hasLength(1));
      expect(policy.tickets.single.state, AdventureRepairTicketState.deferred);
    },
  );

  test('flashcard repair completes as checkpoint-only exposure', () {
    final policy = AdventureRepairPolicy(
      isModeEligible: (_, mode, prompt) =>
          mode == LessonMode.flashcard && prompt == 'flashcardExposure',
      spacingForIdentity: (_) => 3,
    );
    policy.recordAttempt(
      attempt: _attempt(
        index: 0,
        mode: LessonMode.meaningQuiz,
        outcome: AdventureAttemptOutcome.incorrect,
      ),
      remainingOriginalItems: 5,
    );
    for (final index in <int>[1, 2, 3]) {
      policy.recordAttempt(
        attempt: _attempt(
          index: index,
          outcome: AdventureAttemptOutcome.correct,
        ),
        remainingOriginalItems: 5 - index,
      );
    }

    final repair = policy.recordAttempt(
      attempt: _attempt(
        index: 0,
        mode: LessonMode.flashcard,
        outcome: AdventureAttemptOutcome.exposure,
        committed: false,
        isRepair: true,
      ),
      remainingOriginalItems: 2,
    );

    expect(repair.disposition, AdventureRepairDisposition.completed);
    expect(policy.tickets.single.state, AdventureRepairTicketState.completed);
  });

  test('unfinished tickets defer at the natural tail without new items', () {
    final policy = AdventureRepairPolicy(
      isModeEligible: (_, _, _) => true,
      spacingForIdentity: (_) => 5,
    );
    policy.recordAttempt(
      attempt: _attempt(index: 0, outcome: AdventureAttemptOutcome.incorrect),
      remainingOriginalItems: 5,
    );
    policy.recordAttempt(
      attempt: _attempt(index: 1, outcome: AdventureAttemptOutcome.correct),
      remainingOriginalItems: 0,
    );

    final deferred = policy.deferRemaining();

    expect(deferred, hasLength(1));
    expect(deferred.single.state, AdventureRepairTicketState.deferred);
    expect(policy.dueRepairs, isEmpty);
  });

  test('same original evidence identity can schedule at most one repair', () {
    final policy = AdventureRepairPolicy(
      isModeEligible: (_, _, _) => true,
      spacingForIdentity: (_) => 3,
    );
    final attempt = _attempt(
      index: 0,
      outcome: AdventureAttemptOutcome.incorrect,
    );
    expect(
      policy
          .recordAttempt(attempt: attempt, remainingOriginalItems: 5)
          .disposition,
      AdventureRepairDisposition.scheduled,
    );
    expect(
      policy
          .recordAttempt(attempt: attempt, remainingOriginalItems: 5)
          .disposition,
      AdventureRepairDisposition.alreadyScheduled,
    );
    expect(policy.tickets, hasLength(1));
  });

  test(
    'strict snapshot restores exact ticket spacing and counted identities',
    () {
      final first = AdventureRepairPolicy(
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => 3,
      );
      first.recordAttempt(
        attempt: _attempt(
          index: 0,
          mode: LessonMode.typedRecall,
          outcome: AdventureAttemptOutcome.incorrect,
        ),
        remainingOriginalItems: 5,
      );
      first.recordAttempt(
        attempt: _attempt(index: 1, outcome: AdventureAttemptOutcome.correct),
        remainingOriginalItems: 4,
      );
      final json = first.snapshot().toJson();

      expect(
        () =>
            (json['tickets']! as List<Object?>).add(const <String, Object?>{}),
        throwsUnsupportedError,
      );
      final restored = AdventureRepairPolicy.restore(
        AdventureRepairPolicySnapshot.fromJson(json),
        isModeEligible: (_, _, _) => true,
        spacingForIdentity: (_) => 3,
      );
      expect(
        restored.tickets.single.eligibleInterveningIdentities,
        hasLength(1),
      );
      expect(
        restored
            .recordAttempt(
              attempt: _attempt(
                index: 2,
                outcome: AdventureAttemptOutcome.correct,
              ),
              remainingOriginalItems: 3,
            )
            .dueRepairs,
        isEmpty,
      );
      expect(
        restored
            .recordAttempt(
              attempt: _attempt(
                index: 3,
                outcome: AdventureAttemptOutcome.correct,
              ),
              remainingOriginalItems: 2,
            )
            .dueRepairs,
        hasLength(1),
      );
    },
  );

  test('snapshot rejects unknown fields and inconsistent due state', () {
    final policy = AdventureRepairPolicy(
      isModeEligible: (_, _, _) => true,
      spacingForIdentity: (_) => 3,
    );
    policy.recordAttempt(
      attempt: _attempt(index: 0, outcome: AdventureAttemptOutcome.incorrect),
      remainingOriginalItems: 5,
    );
    final unknown = Map<String, Object?>.of(policy.snapshot().toJson())
      ..['unknown'] = true;
    expect(
      () => AdventureRepairPolicySnapshot.fromJson(unknown),
      throwsFormatException,
    );

    final corrupt = Map<String, Object?>.of(policy.snapshot().toJson());
    final tickets = (corrupt['tickets']! as List<Object?>)
        .map((item) => Map<String, Object?>.of(item! as Map<String, Object?>))
        .toList();
    tickets.single['state'] = AdventureRepairTicketState.due.name;
    corrupt['tickets'] = tickets;
    expect(
      () => AdventureRepairPolicySnapshot.fromJson(corrupt),
      throwsFormatException,
    );
  });

  test('snapshot rejects unauthorized mode and prompt combinations', () {
    final policy = AdventureRepairPolicy(
      isModeEligible: (_, _, _) => true,
      spacingForIdentity: (_) => 3,
    );
    policy.recordAttempt(
      attempt: _attempt(index: 0, outcome: AdventureAttemptOutcome.incorrect),
      remainingOriginalItems: 5,
    );

    Map<String, Object?> corruptTicket(
      void Function(Map<String, Object?> ticket) mutate,
    ) {
      final json = Map<String, Object?>.of(policy.snapshot().toJson());
      final tickets = (json['tickets']! as List<Object?>)
          .map((item) => Map<String, Object?>.of(item! as Map<String, Object?>))
          .toList();
      mutate(tickets.single);
      json['tickets'] = tickets;
      return json;
    }

    expect(
      () => AdventureRepairPolicySnapshot.fromJson(
        corruptTicket((ticket) => ticket['originalMode'] = 'dictation'),
      ),
      throwsFormatException,
    );
    expect(
      () => AdventureRepairPolicySnapshot.fromJson(
        corruptTicket(
          (ticket) => ticket['originalPromptVariant'] = 'meaningChoice',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AdventureRepairPolicySnapshot.fromJson(
        corruptTicket((ticket) => ticket['repairPromptVariant'] = 'clozeTyped'),
      ),
      throwsFormatException,
    );
    expect(
      () => AdventureRepairPolicySnapshot.fromJson(
        Map<String, Object?>.of(policy.snapshot().toJson())
          ..['schemaVersion'] = 1.0,
      ),
      throwsFormatException,
    );
  });
}

AdventureRepairAttempt _attempt({
  required int index,
  LessonMode mode = LessonMode.typedRecall,
  required AdventureAttemptOutcome outcome,
  bool committed = true,
  bool isRepair = false,
  EvidenceClass? evidenceClass,
  String? promptVariant,
}) => AdventureRepairAttempt(
  identity: ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: 'word:$index',
    revision: 1,
  ),
  mode: mode,
  promptVariant: promptVariant ?? _promptForMode(mode),
  outcome: outcome,
  evidenceClass: committed
      ? evidenceClass ??
            switch (outcome) {
              AdventureAttemptOutcome.guided => EvidenceClass.guidedPractice,
              AdventureAttemptOutcome.exposure => EvidenceClass.exposure,
              _ => EvidenceClass.independentRecall,
            }
      : null,
  canonicalEvidenceCommitted: committed,
  sourceEvidenceId: committed
      ? 'evidence:$index:${isRepair ? 'repair' : 'first'}'
      : null,
  isRepair: isRepair,
);

String _promptForMode(LessonMode mode) => switch (mode) {
  LessonMode.typedRecall => 'typedRecall',
  LessonMode.cloze => 'clozeSelected',
  LessonMode.meaningQuiz => 'meaningChoice',
  LessonMode.definitionQuiz => 'definitionChoice',
  LessonMode.matching => 'matchingPair',
  LessonMode.flashcard => 'flashcardExposure',
  _ => throw ArgumentError.value(mode, 'mode', 'unsupported test mode'),
};
