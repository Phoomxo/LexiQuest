import 'dart:convert';

import '../../history/domain/learning_history_models.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../progress/domain/progress_models.dart';
import '../../rewards/domain/reward_models.dart';
import '../domain/adventure_journey.dart';

typedef AdventureProgressForOwner =
    Future<ProgressSnapshot> Function(String ownerId);

final class AdventureAchievementFactReader
    implements AdventureJourneyFactReader {
  const AdventureAchievementFactReader({required this.loadForOwner});

  final AdventureProgressForOwner loadForOwner;

  @override
  AdventureJourneyAuthority get authority =>
      AdventureJourneyAuthority.achievement;

  @override
  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    final progress = await loadForOwner(ownerId);
    final achievements = progress.achievements.toList(growable: false);
    if (progress.achievementCount != achievements.length ||
        !_validAchievements(achievements)) {
      return _corrupt(authority);
    }
    if (achievements.isEmpty) return _empty(authority);
    final ordered = achievements.toList()
      ..sort((left, right) {
        var result = left.id.compareTo(right.id);
        if (result != 0) return result;
        result = left.definitionVersion.compareTo(right.definitionVersion);
        if (result != 0) return result;
        result = left.sourceEventId.compareTo(right.sourceEventId);
        if (result != 0) return result;
        return left.unlockedAtUtc.compareTo(right.unlockedAtUtc);
      });
    return _ready(authority, <String, Object?>{
      'achievements': <Map<String, Object?>>[
        for (final achievement in ordered)
          <String, Object?>{
            'id': achievement.id,
            'definitionVersion': achievement.definitionVersion,
            'sourceEventId': achievement.sourceEventId,
            'unlockedAtUtc': achievement.unlockedAtUtc.toIso8601String(),
          },
      ],
    });
  }
}

final class AdventureRewardFactReader implements AdventureJourneyFactReader {
  const AdventureRewardFactReader({required this.accounts});

  final RewardAccountReader accounts;

  @override
  AdventureJourneyAuthority get authority => AdventureJourneyAuthority.reward;

  @override
  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    final account = await accounts.loadForOwner(ownerId);
    if (!_validRewardAccount(account)) return _corrupt(authority);
    if (account.coinBalance == 0 &&
        account.ownedItemIds.isEmpty &&
        account.equippedBySlot.isEmpty &&
        account.transactionCount == 0) {
      return _empty(authority);
    }
    final ownedItemIds = account.ownedItemIds.toList()..sort();
    final equipped = account.equippedBySlot.entries.toList()
      ..sort((left, right) {
        final slotOrder = left.key.compareTo(right.key);
        return slotOrder != 0 ? slotOrder : left.value.compareTo(right.value);
      });
    return _ready(authority, <String, Object?>{
      'coinBalance': account.coinBalance,
      'catalogVersion': account.catalogVersion,
      'ownedItemIds': ownedItemIds,
      'equipped': <Map<String, String>>[
        for (final item in equipped)
          <String, String>{'slot': item.key, 'itemId': item.value},
      ],
      'transactionCount': account.transactionCount,
    });
  }
}

final class AdventureHistoryFactReader implements AdventureJourneyFactReader {
  const AdventureHistoryFactReader({required this.history});

  final LearningHistoryReader history;

  @override
  AdventureJourneyAuthority get authority => AdventureJourneyAuthority.history;

  @override
  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    final entries = await history.list(
      HistoryFilter(ownerId: ownerId, limit: _historyReadLimit),
    );
    if (!_validHistory(entries, ownerId)) return _corrupt(authority);
    if (entries.isEmpty) return _empty(authority);
    final ordered = entries.toList()..sort(_compareHistory);
    return _ready(authority, <String, Object?>{
      'sessions': <Map<String, Object?>>[
        for (final entry in ordered) _historyJson(entry),
      ],
    });
  }
}

final class AdventurePackCompletionFactReader
    implements AdventureJourneyFactReader {
  const AdventurePackCompletionFactReader({required this.history});

  final LearningHistoryReader history;

  @override
  AdventureJourneyAuthority get authority =>
      AdventureJourneyAuthority.packCompletion;

  @override
  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    final entries = await history.list(
      HistoryFilter(ownerId: ownerId, limit: _historyReadLimit),
    );
    if (!_validHistory(entries, ownerId)) return _corrupt(authority);
    final completions =
        entries
            .where(
              (entry) =>
                  entry.terminalState ==
                      LearningHistoryTerminalState.completed &&
                  entry.packIdentity != null &&
                  entry.sessionConfiguration?.packIdentity ==
                      entry.packIdentity,
            )
            .toList()
          ..sort((left, right) {
            final identityOrder = _compareIdentity(
              left.packIdentity!,
              right.packIdentity!,
            );
            return identityOrder != 0
                ? identityOrder
                : _compareHistory(left, right);
          });
    if (completions.isEmpty) return _empty(authority);
    return _ready(authority, <String, Object?>{
      'completedPacks': <Map<String, Object?>>[
        for (final entry in completions)
          <String, Object?>{
            'packIdentity': _identityJson(entry.packIdentity!),
            'sessionId': entry.sessionId,
            'endedAtUtc': entry.endedAtUtc.toIso8601String(),
            'configurationIdentity':
                entry.sessionConfiguration!.contentIdentity,
          },
      ],
    });
  }
}

const int _historyReadLimit = 100;

AdventureJourneyFacts _empty(AdventureJourneyAuthority authority) =>
    AdventureJourneyFacts(
      authority: authority,
      state: AdventureJourneyDependencyState.empty,
      completedNodeIds: const <String>{},
      fingerprintPart: '',
    );

AdventureJourneyFacts _ready(
  AdventureJourneyAuthority authority,
  Map<String, Object?> value,
) => AdventureJourneyFacts(
  authority: authority,
  state: AdventureJourneyDependencyState.ready,
  completedNodeIds: const <String>{},
  fingerprintPart: jsonEncode(<String, Object?>{
    'schemaVersion': 1,
    'authority': authority.name,
    'value': value,
  }),
);

AdventureJourneyFacts _corrupt(AdventureJourneyAuthority authority) =>
    AdventureJourneyFacts(
      authority: authority,
      state: AdventureJourneyDependencyState.corrupt,
      completedNodeIds: const <String>{},
      fingerprintPart: jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'authority': authority.name,
        'state': AdventureJourneyDependencyState.corrupt.name,
      }),
    );

bool _validAchievements(List<AchievementEvidence> achievements) {
  final ids = <String>{};
  for (final achievement in achievements) {
    if (!_isCanonicalText(achievement.id) ||
        !_isCanonicalText(achievement.sourceEventId) ||
        achievement.definitionVersion < 1 ||
        !_isCanonicalUtc(achievement.unlockedAtUtc) ||
        !ids.add(achievement.id)) {
      return false;
    }
  }
  return true;
}

bool _validRewardAccount(RewardAccount account) {
  if (account.coinBalance < 0 ||
      account.catalogVersion < 1 ||
      account.transactionCount < 0 ||
      account.ownedItemIds.any((id) => !_isCanonicalText(id))) {
    return false;
  }
  for (final item in account.equippedBySlot.entries) {
    if (!_isCanonicalText(item.key) || !_isCanonicalText(item.value)) {
      return false;
    }
  }
  return true;
}

bool _validHistory(List<LearningHistoryEntry> entries, String ownerId) {
  if (entries.length > _historyReadLimit) return false;
  final sessionIds = <String>{};
  for (final entry in entries) {
    final packIdentity = entry.packIdentity;
    if (entry.ownerId != ownerId ||
        !_isCanonicalText(entry.sessionId) ||
        !sessionIds.add(entry.sessionId) ||
        !_isCanonicalUtc(entry.startedAtUtc) ||
        !_isCanonicalUtc(entry.endedAtUtc) ||
        (packIdentity != null && !_validIdentity(packIdentity))) {
      return false;
    }
  }
  return true;
}

int _compareHistory(LearningHistoryEntry left, LearningHistoryEntry right) {
  var result = left.sessionId.compareTo(right.sessionId);
  if (result != 0) return result;
  result = left.endedAtUtc.compareTo(right.endedAtUtc);
  if (result != 0) return result;
  return left.startedAtUtc.compareTo(right.startedAtUtc);
}

Map<String, Object?> _historyJson(
  LearningHistoryEntry entry,
) => <String, Object?>{
  'sessionId': entry.sessionId,
  'mode': entry.mode?.name,
  'packIdentity': entry.packIdentity == null
      ? null
      : _identityJson(entry.packIdentity!),
  'packTitle': entry.packTitle,
  'contentAvailability': entry.contentAvailability.name,
  'activeLearningDurationMicros': entry.activeLearningDuration.inMicroseconds,
  'terminalState': entry.terminalState.name,
  'startedAtUtc': entry.startedAtUtc.toIso8601String(),
  'endedAtUtc': entry.endedAtUtc.toIso8601String(),
  'correctCount': entry.correctCount,
  'wrongCount': entry.wrongCount,
  'score': entry.score,
  'configuration': entry.sessionConfiguration?.stableSerialization,
  'evidenceCount': entry.evidence.length,
  'assessment': entry.assessmentSummary == null
      ? null
      : <String, Object?>{
          'phase': entry.assessmentSummary!.phase.name,
          'state': entry.assessmentSummary!.state.name,
          'terminalAtUtc': entry.assessmentSummary!.terminalAtUtc
              .toIso8601String(),
          'instrumentVersion': entry.assessmentSummary!.instrumentVersion,
          'formVersion': entry.assessmentSummary!.formVersion,
          'sampleSize': entry.assessmentSummary!.sampleSize,
          'correctCount': entry.assessmentSummary!.correctCount,
          'incorrectCount': entry.assessmentSummary!.incorrectCount,
          'accuracy': entry.assessmentSummary!.accuracy,
        },
};

bool _validIdentity(ContentIdentity identity) =>
    _isCanonicalText(identity.id) && identity.revision >= 1;

int _compareIdentity(ContentIdentity left, ContentIdentity right) {
  var result = left.type.name.compareTo(right.type.name);
  if (result != 0) return result;
  result = left.id.compareTo(right.id);
  if (result != 0) return result;
  return left.revision.compareTo(right.revision);
}

Map<String, Object?> _identityJson(ContentIdentity identity) =>
    <String, Object?>{
      'type': identity.type.name,
      'id': identity.id,
      'revision': identity.revision,
    };

bool _isCanonicalUtc(DateTime value) =>
    value.isUtc && value.millisecondsSinceEpoch >= 0;

bool _isCanonicalText(String value) =>
    value.isNotEmpty &&
    value == value.trim() &&
    value.runes.length <= 256 &&
    !value.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'));
