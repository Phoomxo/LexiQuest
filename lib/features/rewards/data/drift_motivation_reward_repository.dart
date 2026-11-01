import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../../../data/local/app_database.dart' as db;
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning_profile/domain/learning_timezone.dart';
import '../../motivation/data/drift_learning_day_recorder.dart';
import '../../motivation/data/drift_motivation_scope.dart';
import '../../motivation/domain/motivation_snapshot.dart';
import '../../quest/domain/quest_models.dart';
import '../../quest/data/drift_quest_repository.dart';
import '../domain/motivation_rewards.dart';

final class DriftMotivationRewardRepository {
  DriftMotivationRewardRepository(
    this.database, {
    required this.ownerWrites,
    required this.quests,
    required this.nowUtc,
  }) {
    if (!identical(database, ownerWrites.database) ||
        !identical(database, quests.database) ||
        !identical(ownerWrites, quests.ownerWrites)) {
      throw ArgumentError(
        'Motivation rewards require the canonical owner database',
      );
    }
  }
  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;
  final DriftQuestRepository quests;
  final DateTime Function() nowUtc;

  Future<MotivationRewardTotals> read({
    required String expectedOwnerId,
    required DateTime atUtc,
    required bool Function() stillCurrent,
  }) => withMotivationOwner(
    database,
    ownerWrites,
    expectedOwnerId,
    stillCurrent,
    (_) => readForProjection(ownerId: expectedOwnerId, atUtc: atUtc),
  );

  Future<MotivationRewardTotals> readForProjection({
    required String ownerId,
    required DateTime atUtc,
  }) => database.transaction(() async {
    if (!atUtc.isUtc || atUtc.millisecondsSinceEpoch < 0) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    final days = await readCanonicalLearningDays(
      database,
      ownerId: ownerId,
      nowUtc: atUtc,
    );
    final receipts = await quests.readValidatedCompletionsForProjection(
      ownerId: ownerId,
      nowUtc: atUtc,
    );
    return _fold(ownerId, atUtc, days, receipts);
  });

  Future<void> reconcile({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) async {
    if (await ownerWrites.hasAmbientTransaction()) {
      throw const MotivationException(MotivationFailureCode.unavailable);
    }
    await withMotivationOwner(
      database,
      ownerWrites,
      expectedOwnerId,
      stillCurrent,
      (current) => ownerWrites.writeForActiveOwner(
        expectedOwnerId: expectedOwnerId,
        write: () async {
          final receipts = await quests.readValidatedCompletions(
            expectedOwnerId: expectedOwnerId,
            stillCurrent: current,
          );
          final now = _now();
          for (final receipt in receipts) {
            for (final expected in _grantRows(expectedOwnerId, receipt)) {
              if (expected.occurredAtUtcMs > now.millisecondsSinceEpoch) {
                continue;
              }
              final stored =
                  await (database.select(database.rewardTransactions)..where(
                        (row) =>
                            row.ownerId.equals(expectedOwnerId) &
                            row.idempotencyKey.equals(expected.idempotencyKey),
                      ))
                      .getSingleOrNull();
              if (stored != null) {
                if (!_same(stored, expected)) {
                  throw const MotivationException(
                    MotivationFailureCode.conflict,
                  );
                }
                continue;
              }
              await database
                  .into(database.rewardTransactions)
                  .insert(_companion(expected));
            }
          }
          final rechecked = await quests.readValidatedCompletions(
            expectedOwnerId: expectedOwnerId,
            stillCurrent: current,
          );
          if (_receiptPins(receipts) != _receiptPins(rechecked)) {
            throw const MotivationException(MotivationFailureCode.conflict);
          }
          await requireMotivationOwner(
            database,
            ownerWrites,
            expectedOwnerId,
            current,
          );
        },
      ),
    );
  }

  Future<MotivationRewardTotals> protect(FreezeProtectionIntent intent) async {
    if (await ownerWrites.hasAmbientTransaction()) {
      throw const MotivationException(MotivationFailureCode.unavailable);
    }
    return withMotivationOwner(
      database,
      ownerWrites,
      intent.ownerId,
      intent.stillCurrent,
      (current) => ownerWrites.writeForActiveOwner(
        expectedOwnerId: intent.ownerId,
        write: () async {
          final now = _now();
          final days = await readCanonicalLearningDays(
            database,
            ownerId: intent.ownerId,
            nowUtc: now,
          );
          final expected = _protectionRow(intent);
          final existing =
              await (database.select(database.rewardTransactions)..where(
                    (row) =>
                        row.ownerId.equals(intent.ownerId) &
                        row.idempotencyKey.equals(expected.idempotencyKey),
                  ))
                  .getSingleOrNull();
          if (existing != null) {
            if (!_same(existing, expected)) {
              throw const MotivationException(MotivationFailureCode.conflict);
            }
            final totals = await _read(intent.ownerId, now, days, current);
            if (!totals.acceptedReceiptIds.contains(existing.id)) {
              throw const MotivationException(MotivationFailureCode.invalid);
            }
            return totals;
          }
          final profile =
              await (database.select(database.learningProfiles)
                    ..where((row) => row.ownerId.equals(intent.ownerId)))
                  .getSingleOrNull();
          final currentZone = requireLearningTimezone(
            profile?.learningTimezoneId ?? 'UTC',
          );
          if (currentZone != intent.timezoneId) {
            throw const MotivationException(MotivationFailureCode.conflict);
          }
          if (intent.occurredAtUtc.isAfter(now) ||
              motivationDayLabel(
                    timezone.TZDateTime.from(
                      intent.occurredAtUtc,
                      timezone.getLocation(intent.timezoneId),
                    ),
                  ) !=
                  motivationDayLabel(
                    timezone.TZDateTime.from(
                      now,
                      timezone.getLocation(intent.timezoneId),
                    ),
                  ) ||
              !_validProtection(expected, days)) {
            throw const MotivationException(MotivationFailureCode.invalid);
          }
          final rows = await (database.select(
            database.rewardTransactions,
          )..where((row) => row.ownerId.equals(intent.ownerId))).get();
          final currentTotals = await _read(intent.ownerId, now, days, current);
          if (rows
              .where((row) => currentTotals.acceptedReceiptIds.contains(row.id))
              .any(
                (row) =>
                    row.occurredAtUtcMs >
                    intent.occurredAtUtc.millisecondsSinceEpoch,
              )) {
            throw const MotivationException(MotivationFailureCode.invalid);
          }
          final before = await _read(
            intent.ownerId,
            intent.occurredAtUtc,
            days,
            current,
          );
          if (before.freezeCount < 1) {
            throw const MotivationException(MotivationFailureCode.noFreeze);
          }
          await database
              .into(database.rewardTransactions)
              .insert(_companion(expected));
          final afterDays = await readCanonicalLearningDays(
            database,
            ownerId: intent.ownerId,
            nowUtc: now,
          );
          final after = await _read(intent.ownerId, now, afterDays, current);
          if (!after.acceptedReceiptIds.contains(expected.id)) {
            throw const MotivationException(MotivationFailureCode.conflict);
          }
          final finalProfile =
              await (database.select(database.learningProfiles)
                    ..where((row) => row.ownerId.equals(intent.ownerId)))
                  .getSingleOrNull();
          if (requireLearningTimezone(
                finalProfile?.learningTimezoneId ?? 'UTC',
              ) !=
              currentZone) {
            throw const MotivationException(MotivationFailureCode.conflict);
          }
          await requireMotivationOwner(
            database,
            ownerWrites,
            intent.ownerId,
            current,
          );
          return after;
        },
      ),
    );
  }

  Future<MotivationRewardTotals> _read(
    String ownerId,
    DateTime atUtc,
    List<LearningDayFact> days,
    bool Function() current,
  ) async {
    if (!atUtc.isUtc || atUtc.millisecondsSinceEpoch < 0) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    final receipts = await quests.readValidatedCompletions(
      expectedOwnerId: ownerId,
      stillCurrent: current,
    );
    return _fold(ownerId, atUtc, days, receipts);
  }

  Future<MotivationRewardTotals> _fold(
    String ownerId,
    DateTime atUtc,
    List<LearningDayFact> days,
    List<QuestCompletionReceipt> receipts,
  ) async {
    final expected = {
      for (final receipt in receipts)
        for (final row in _grantRows(ownerId, receipt)) row.id: row,
    };
    final rows =
        await (database.select(database.rewardTransactions)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    var xp = 0;
    var freezes = 0;
    final protected = <String>{};
    final accepted = <String>{};
    final periods = <String>{};
    rows.sort((a, b) {
      final time = a.occurredAtUtcMs.compareTo(b.occurredAtUtcMs);
      if (time != 0) return time;
      final aSpend = a.transactionType == MotivationRewardPolicy.protection
          ? 1
          : 0;
      final bSpend = b.transactionType == MotivationRewardPolicy.protection
          ? 1
          : 0;
      final rank = aSpend.compareTo(bSpend);
      return rank == 0 ? a.id.compareTo(b.id) : rank;
    });
    for (final row in rows) {
      if (row.occurredAtUtcMs > atUtc.millisecondsSinceEpoch) continue;
      final grant = expected[row.id];
      if (grant != null && _same(row, grant)) {
        final source = receipts.singleWhere(
          (receipt) => receipt.instance.instanceId == row.sourceEventId,
        );
        final logical = jsonEncode([
          row.transactionType,
          source.instance.questId,
          source.instance.period!.key,
        ]);
        if (!periods.add(logical)) continue;
        if (row.transactionType == MotivationRewardPolicy.questXp) {
          xp += row.amount;
        }
        if (row.transactionType == MotivationRewardPolicy.weeklyFreeze) {
          freezes += row.amount;
        }
        accepted.add(row.id);
      } else if (row.transactionType == MotivationRewardPolicy.protection &&
          freezes > 0 &&
          _validProtection(row, days)) {
        final value = jsonDecode(row.itemId!) as Map<String, dynamic>;
        final day = value['protectedDay'] as String;
        if (!protected.add(day)) continue;
        freezes--;
        accepted.add(row.id);
      }
    }
    return MotivationRewardTotals(
      questXp: xp,
      freezeCount: freezes,
      protectedDays: protected,
      acceptedReceiptIds: accepted,
    );
  }

  List<db.RewardTransaction> _grantRows(
    String owner,
    QuestCompletionReceipt receipt,
  ) {
    final instance = receipt.instance;
    final digest = instance.definitionSha256;
    final period = instance.period;
    if (instance.ownerId != owner ||
        period == null ||
        digest == null ||
        digest.length != 64 ||
        instance.state != QuestInstanceState.completed ||
        instance.completedAtUtc == null ||
        receipt.completion.questInstanceId != instance.instanceId ||
        receipt.completion.ownerId != owner ||
        receipt.completion.completedAtUtc != instance.completedAtUtc) {
      return const [];
    }
    final xp = receipt.definition.reward.xpAmount;
    if (xp < 0 ||
        xp > 1000000 ||
        receipt.definition.reward.rewardItemId != null) {
      return const [];
    }
    db.RewardTransaction row(String type, int amount) => db.RewardTransaction(
      id: '$type:${instance.instanceId}',
      ownerId: owner,
      idempotencyKey: '$type:${instance.instanceId}',
      transactionType: type,
      amount: amount,
      itemId: digest,
      catalogVersion: MotivationRewardPolicy.version,
      sourceEventId: instance.instanceId,
      occurredAtUtcMs: instance.completedAtUtc!.millisecondsSinceEpoch,
    );
    return [
      if (xp > 0) row(MotivationRewardPolicy.questXp, xp),
      if (receipt.definition.type == QuestType.weekly)
        row(MotivationRewardPolicy.weeklyFreeze, 1),
    ];
  }

  db.RewardTransaction _protectionRow(FreezeProtectionIntent intent) {
    requireLearningTimezone(intent.timezoneId);
    motivationCivilDay(intent.protectedDay);
    if (intent.id.trim().isEmpty ||
        intent.id.length > 256 ||
        !intent.occurredAtUtc.isUtc ||
        intent.occurredAtUtc.millisecondsSinceEpoch < 0 ||
        intent.sourceAttemptId.trim().isEmpty) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    return db.RewardTransaction(
      id: intent.id,
      ownerId: intent.ownerId,
      idempotencyKey:
          '${MotivationRewardPolicy.protection}:${intent.protectedDay}',
      transactionType: MotivationRewardPolicy.protection,
      amount: -1,
      itemId: jsonEncode({
        'schemaVersion': 1,
        'protectedDay': intent.protectedDay,
        'timezoneId': intent.timezoneId,
      }),
      catalogVersion: MotivationRewardPolicy.version,
      sourceEventId: intent.sourceAttemptId,
      occurredAtUtcMs: intent.occurredAtUtc.millisecondsSinceEpoch,
    );
  }

  bool _validProtection(db.RewardTransaction row, List<LearningDayFact> days) {
    try {
      if (row.transactionType != MotivationRewardPolicy.protection ||
          row.amount != -1 ||
          row.catalogVersion != MotivationRewardPolicy.version ||
          row.itemId == null ||
          row.itemId!.length > 512 ||
          row.sourceEventId == null ||
          row.occurredAtUtcMs < 0 ||
          row.id.trim().isEmpty) {
        return false;
      }
      final value = jsonDecode(row.itemId!);
      if (value is! Map<String, dynamic> ||
          value.length != 3 ||
          value['schemaVersion'] != 1 ||
          value['protectedDay'] is! String ||
          value['timezoneId'] is! String) {
        return false;
      }
      final label = value['protectedDay'] as String;
      final protectedDay = motivationCivilDay(label);
      final zone = requireLearningTimezone(value['timezoneId'] as String);
      if (jsonEncode({
                'schemaVersion': 1,
                'protectedDay': label,
                'timezoneId': zone,
              }) !=
              row.itemId ||
          row.idempotencyKey != '${MotivationRewardPolicy.protection}:$label' ||
          days.any((fact) => fact.learningDay == label)) {
        return false;
      }
      final at = DateTime.fromMillisecondsSinceEpoch(
        row.occurredAtUtcMs,
        isUtc: true,
      );
      final today = motivationCivilDay(
        motivationDayLabel(
          timezone.TZDateTime.from(at, timezone.getLocation(zone)),
        ),
      );
      if (today.difference(protectedDay).inDays != 1) return false;
      final source = days.where(
        (fact) =>
            fact.sourceAttemptId == row.sourceEventId &&
            fact.timezoneId == zone &&
            motivationCivilDay(
                  fact.learningDay,
                ).difference(protectedDay).inDays ==
                -1 &&
            !fact.occurredAtUtc.isAfter(at),
      );
      return source.length == 1;
    } on Object {
      return false;
    }
  }

  DateTime _now() {
    final now = nowUtc();
    if (!now.isUtc || now.millisecondsSinceEpoch < 0) {
      throw const MotivationException(MotivationFailureCode.invalid);
    }
    return now;
  }
}

bool _same(db.RewardTransaction a, db.RewardTransaction b) =>
    a.id == b.id &&
    a.ownerId == b.ownerId &&
    a.idempotencyKey == b.idempotencyKey &&
    a.transactionType == b.transactionType &&
    a.amount == b.amount &&
    a.itemId == b.itemId &&
    a.catalogVersion == b.catalogVersion &&
    a.sourceEventId == b.sourceEventId &&
    a.occurredAtUtcMs == b.occurredAtUtcMs;

db.RewardTransactionsCompanion _companion(db.RewardTransaction row) =>
    db.RewardTransactionsCompanion.insert(
      id: row.id,
      ownerId: row.ownerId,
      idempotencyKey: row.idempotencyKey,
      transactionType: row.transactionType,
      amount: row.amount,
      itemId: Value(row.itemId),
      catalogVersion: row.catalogVersion,
      sourceEventId: Value(row.sourceEventId),
      occurredAtUtcMs: row.occurredAtUtcMs,
    );

String _receiptPins(List<QuestCompletionReceipt> receipts) => jsonEncode([
  for (final receipt in receipts)
    [
      receipt.instance.instanceId,
      receipt.instance.definitionSha256,
      receipt.instance.period!.json,
      receipt.completion.completedAtUtc.millisecondsSinceEpoch,
      receipt.completion.objectiveEventIds,
    ],
]);
