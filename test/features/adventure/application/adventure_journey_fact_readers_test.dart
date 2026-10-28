import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_journey_fact_readers.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_journey.dart';
import 'package:vocab_learning_app/features/history/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  test(
    'empty canonical sources stay owner-scoped and return empty facts',
    () async {
      String? progressOwnerId;
      final rewards = _RewardAccounts(_emptyRewardAccount());
      final history = _History(const <LearningHistoryEntry>[]);
      final readers = <AdventureJourneyFactReader>[
        AdventureAchievementFactReader(
          loadForOwner: (ownerId) async {
            progressOwnerId = ownerId;
            return _progress();
          },
        ),
        AdventureRewardFactReader(accounts: rewards),
        AdventureHistoryFactReader(history: history),
        AdventurePackCompletionFactReader(history: history),
      ];

      final facts = <AdventureJourneyFacts>[];
      for (final reader in readers) {
        facts.add(
          await reader.read(ownerId: _ownerId, evaluatedAtUtc: _evaluatedAtUtc),
        );
      }

      expect(progressOwnerId, _ownerId);
      expect(rewards.ownerIds, <String>[_ownerId]);
      expect(history.filters, hasLength(2));
      expect(
        history.filters.map((filter) => filter.ownerId),
        everyElement(_ownerId),
      );
      expect(
        history.filters.map((filter) => filter.limit),
        everyElement(inInclusiveRange(1, 100)),
      );
      expect(facts.map((fact) => fact.authority), _supplementalAuthorities);
      expect(
        facts.map((fact) => fact.state),
        everyElement(AdventureJourneyDependencyState.empty),
      );
      expect(facts.map((fact) => fact.fingerprintPart), everyElement(isEmpty));
      expect(facts.map((fact) => fact.completedNodeIds), everyElement(isEmpty));
    },
  );

  test(
    'nonempty canonical facts have order-independent serialization',
    () async {
      final historyA = _historyEntry(sessionId: 'session-a');
      final historyB = _historyEntry(sessionId: 'session-b');
      final forward = await _readNonemptyFacts(
        achievements: <AchievementEvidence>[_achievementB, _achievementA],
        rewardAccount: RewardAccount(
          coinBalance: 7,
          catalogVersion: 2,
          ownedItemIds: <String>{'theme-ocean', 'armor-srs'},
          equippedBySlot: const <String, String>{
            'theme': 'theme-ocean',
            'armor': 'armor-srs',
          },
          transactionCount: 3,
        ),
        history: <LearningHistoryEntry>[historyB, historyA],
      );
      final reversed = await _readNonemptyFacts(
        achievements: <AchievementEvidence>[_achievementA, _achievementB],
        rewardAccount: RewardAccount(
          coinBalance: 7,
          catalogVersion: 2,
          ownedItemIds: <String>{'armor-srs', 'theme-ocean'},
          equippedBySlot: const <String, String>{
            'armor': 'armor-srs',
            'theme': 'theme-ocean',
          },
          transactionCount: 3,
        ),
        history: <LearningHistoryEntry>[historyA, historyB],
      );

      expect(
        forward.map((fact) => fact.state),
        everyElement(AdventureJourneyDependencyState.ready),
      );
      expect(
        forward.map((fact) => fact.fingerprintPart),
        reversed.map((fact) => fact.fingerprintPart),
      );
      expect(
        forward.map((fact) => fact.fingerprintPart),
        everyElement(isNotEmpty),
      );
      expect(
        forward.map((fact) => fact.completedNodeIds),
        everyElement(isEmpty),
        reason:
            'canonical sources do not persist exact Adventure node identity',
      );
    },
  );

  test(
    'pack completion requires a completed terminal with a pinned pack',
    () async {
      final history = _History(<LearningHistoryEntry>[
        _historyEntry(
          sessionId: 'abandoned-pinned',
          terminalState: LearningHistoryTerminalState.abandoned,
        ),
        _historyEntry(sessionId: 'completed-unpinned', pinned: false),
      ]);
      final reader = AdventurePackCompletionFactReader(history: history);

      final empty = await reader.read(
        ownerId: _ownerId,
        evaluatedAtUtc: _evaluatedAtUtc,
      );
      history.entries = <LearningHistoryEntry>[
        ...history.entries,
        _historyEntry(sessionId: 'completed-pinned'),
      ];
      final ready = await reader.read(
        ownerId: _ownerId,
        evaluatedAtUtc: _evaluatedAtUtc,
      );

      expect(empty.state, AdventureJourneyDependencyState.empty);
      expect(empty.fingerprintPart, isEmpty);
      expect(ready.state, AdventureJourneyDependencyState.ready);
      expect(ready.fingerprintPart, isNotEmpty);
      expect(ready.completedNodeIds, isEmpty);
    },
  );
}

Future<List<AdventureJourneyFacts>> _readNonemptyFacts({
  required List<AchievementEvidence> achievements,
  required RewardAccount rewardAccount,
  required List<LearningHistoryEntry> history,
}) async {
  final historyReader = _History(history);
  final readers = <AdventureJourneyFactReader>[
    AdventureAchievementFactReader(
      loadForOwner: (_) async => _progress(achievements: achievements),
    ),
    AdventureRewardFactReader(accounts: _RewardAccounts(rewardAccount)),
    AdventureHistoryFactReader(history: historyReader),
    AdventurePackCompletionFactReader(history: historyReader),
  ];
  final facts = <AdventureJourneyFacts>[];
  for (final reader in readers) {
    facts.add(
      await reader.read(ownerId: _ownerId, evaluatedAtUtc: _evaluatedAtUtc),
    );
  }
  return facts;
}

ProgressSnapshot _progress({
  List<AchievementEvidence> achievements = const <AchievementEvidence>[],
}) => ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: achievements.length,
  gameLevel: 1,
  skills: const <SkillEvidence>[],
  weaknesses: const <WeaknessEvidence>[],
  recommendations: const <LearningRecommendation>[],
  achievements: achievements,
);

RewardAccount _emptyRewardAccount() => const RewardAccount(
  coinBalance: 0,
  catalogVersion: 2,
  ownedItemIds: <String>{},
  equippedBySlot: <String, String>{},
  transactionCount: 0,
);

LearningHistoryEntry _historyEntry({
  required String sessionId,
  LearningHistoryTerminalState terminalState =
      LearningHistoryTerminalState.completed,
  bool pinned = true,
}) {
  final configuration = pinned
      ? SessionConfiguration.validated(
          schemaVersion: sessionConfigurationSchemaVersion,
          policyVersion: sessionConfigurationPolicyVersion,
          ownerId: _ownerId,
          mode: LessonMode.typedRecall,
          itemCount: 2,
          direction: SessionDirection.forward,
          difficulty: SessionDifficulty.standard,
          hintBudget: 0,
          timing: const SessionTiming.untimedAlternative(
            maximumActiveEffort: Duration(minutes: 10),
          ),
          packIdentity: _packIdentity,
          protocolId: 'protocol:local-standard',
          protocolVersion: '1',
          protocolLimitsIdentity:
              const SessionConfigurationProtocolLimits.standard()
                  .contentIdentity,
        )
      : null;
  final startedAtUtc = sessionId.endsWith('a')
      ? DateTime.utc(2026, 9, 3, 8)
      : DateTime.utc(2026, 9, 4, 8);
  return LearningHistoryEntry(
    sessionId: sessionId,
    ownerId: _ownerId,
    mode: LessonMode.typedRecall,
    packIdentity: pinned ? _packIdentity : null,
    packTitle: pinned ? 'Travel' : null,
    contentAvailability: pinned
        ? LearningHistoryContentAvailability.available
        : LearningHistoryContentAvailability.unavailable,
    activeLearningDuration: const Duration(minutes: 4),
    terminalState: terminalState,
    startedAtUtc: startedAtUtc,
    endedAtUtc: startedAtUtc.add(const Duration(minutes: 5)),
    correctCount: terminalState == LearningHistoryTerminalState.completed
        ? 2
        : 0,
    wrongCount: 0,
    score: terminalState == LearningHistoryTerminalState.completed ? 100 : null,
    sessionConfiguration: configuration,
    evidence: const <LearningHistoryEvidence>[],
  );
}

final class _RewardAccounts implements RewardAccountReader {
  _RewardAccounts(this.account);

  final RewardAccount account;
  final List<String> ownerIds = <String>[];

  @override
  Future<RewardAccount> loadForOwner(String ownerId) async {
    ownerIds.add(ownerId);
    return account;
  }
}

final class _History implements LearningHistoryReader {
  _History(this.entries);

  List<LearningHistoryEntry> entries;
  final List<HistoryFilter> filters = <HistoryFilter>[];

  @override
  Future<List<LearningHistoryEntry>> list(HistoryFilter filter) async {
    filters.add(filter);
    return List<LearningHistoryEntry>.of(entries);
  }

  @override
  Future<LessonStartCommand> replayAsNewSession(
    String sourceSessionId, {
    required String replayOperationId,
  }) async => throw UnimplementedError('not used by journey projection');
}

const _supplementalAuthorities = <AdventureJourneyAuthority>[
  AdventureJourneyAuthority.achievement,
  AdventureJourneyAuthority.reward,
  AdventureJourneyAuthority.history,
  AdventureJourneyAuthority.packCompletion,
];

const _ownerId = 'owner:journey-reader';
final _evaluatedAtUtc = DateTime.utc(2026, 9, 5, 10);
const _packIdentity = ContentIdentity(
  type: ContentType.learningPack,
  id: 'pack:travel',
  revision: 3,
);
final _achievementA = AchievementEvidence(
  id: 'achievement-a',
  definitionVersion: 1,
  sourceEventId: 'event-a',
  unlockedAtUtc: DateTime.utc(2026, 9, 3),
);
final _achievementB = AchievementEvidence(
  id: 'achievement-b',
  definitionVersion: 2,
  sourceEventId: 'event-b',
  unlockedAtUtc: DateTime.utc(2026, 9, 4),
);
