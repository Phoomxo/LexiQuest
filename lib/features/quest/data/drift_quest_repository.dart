import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../learning/domain/answer_motivation_evidence.dart';
import '../application/quest_catalog_provider.dart';
import '../domain/quest_models.dart';

final class VerifiedQuestAnswerDefinition {
  const VerifiedQuestAnswerDefinition._({
    required this.pin,
    required this.definition,
    required this.canonicalDefinition,
  });
  final QuestRevisionPin pin;
  final QuestDefinition definition;
  final String canonicalDefinition;
}

final class TrustedQuestAnswerCatalog {
  TrustedQuestAnswerCatalog._(this._database, this._entries);

  final db.AppDatabase _database;
  final List<_AnswerCatalogEntry> _entries;

  Future<VerifiedQuestAnswerDefinition> definitionForPin({
    required db.AppDatabase database,
    required QuestRevisionPin pin,
  }) async {
    if (!identical(database, _database)) {
      throw ArgumentError('Catalog database mismatch');
    }
    final matches = _entries.where(
      (entry) =>
          entry.pin.questId == pin.questId &&
          entry.pin.catalogVersion == pin.catalogVersion &&
          entry.pin.definitionDigest == pin.definitionDigest,
    );
    if (matches.length != 1) {
      throw StateError('Quest revision is not authored');
    }
    final entry = matches.single;
    await _verifiedPin(entry);
    final body = jsonDecode(entry.body) as Map<String, dynamic>;
    final reward = body['reward'] as Map<String, dynamic>;
    final objectives = (body['objectives'] as List).map((value) {
      final objective = value as Map<String, dynamic>;
      final filters = objective['filters'] as Map<String, dynamic>?;
      return QuestObjective(
        objectiveId: objective['objectiveId'] as String,
        description: objective['description'] as String,
        targetCount: objective['targetCount'] as int,
        criteria: ObjectiveCriteria(
          eventType: objective['eventType'] as String,
          filters: filters == null
              ? null
              : Map<String, dynamic>.unmodifiable(filters),
        ),
      );
    });
    final expires = body['expiresInMs'] as int?;
    return VerifiedQuestAnswerDefinition._(
      pin: entry.pin,
      canonicalDefinition: entry.body,
      definition: QuestDefinition(
        questId: body['questId'] as String,
        catalogVersion: body['catalogVersion'] as int,
        title: body['title'] as String,
        description: body['description'] as String,
        type: QuestType.values.byName(body['type'] as String),
        objectives: List<QuestObjective>.unmodifiable(objectives),
        reward: RewardSpec(
          xpAmount: reward['xpAmount'] as int,
          rewardItemId: reward['rewardItemId'] as String?,
        ),
        expiresIn: expires == null ? null : Duration(milliseconds: expires),
        tags: List<String>.unmodifiable((body['tags'] as List).cast<String>()),
      ),
    );
  }

  Future<({QuestRevisionPin daily, QuestRevisionPin weekly})>
  pinsForPendingCalendar({
    required db.AppDatabase database,
    required int occurredAtUtcMs,
    required int epochEffectiveUtcUs,
  }) async {
    if (!identical(database, _database) ||
        occurredAtUtcMs < 0 ||
        epochEffectiveUtcUs < 0 ||
        occurredAtUtcMs * Duration.microsecondsPerMillisecond <
            epochEffectiveUtcUs) {
      throw ArgumentError(
        'Catalog database and nonnegative occurrence required',
      );
    }
    _AnswerCatalogEntry soleInitial(QuestType type) {
      final entries = _entries.where((entry) => entry.type == type).toList();
      if (entries.length != 1 || entries.single.activeFromUtcMs != 0) {
        throw StateError('Pending calendar has ambiguous Quest revisions');
      }
      return entries.single;
    }

    final daily = soleInitial(QuestType.daily);
    final weekly = soleInitial(QuestType.weekly);
    return (
      daily: await _verifiedPin(daily),
      weekly: await _verifiedPin(weekly),
    );
  }

  Future<({QuestRevisionPin daily, QuestRevisionPin weekly})> pinsForPeriod({
    required db.AppDatabase database,
    required DateTime dailyStartUtc,
    required DateTime weeklyStartUtc,
  }) async {
    if (!identical(database, _database) ||
        !dailyStartUtc.isUtc ||
        !weeklyStartUtc.isUtc) {
      throw ArgumentError('Catalog database and UTC period starts required');
    }
    Future<QuestRevisionPin> resolve(QuestType type, DateTime start) async {
      final candidates = _entries.where(
        (entry) =>
            entry.type == type &&
            entry.activeFromUtcMs <= start.millisecondsSinceEpoch,
      );
      if (candidates.isEmpty) {
        throw StateError('No authored revision for period');
      }
      final selected = candidates.reduce(
        (a, b) => a.activeFromUtcMs > b.activeFromUtcMs ? a : b,
      );
      return _verifiedPin(selected);
    }

    return (
      daily: await resolve(QuestType.daily, dailyStartUtc),
      weekly: await resolve(QuestType.weekly, weeklyStartUtc),
    );
  }

  Future<QuestRevisionPin> _verifiedPin(_AnswerCatalogEntry entry) async {
    final row =
        await (_database.select(_database.questDefinitionRevisions)..where(
              (row) =>
                  row.questId.equals(entry.pin.questId) &
                  row.catalogVersion.equals(entry.pin.catalogVersion),
            ))
            .getSingleOrNull();
    if (row == null ||
        row.definitionDigest != entry.pin.definitionDigest ||
        row.canonicalDefinition != entry.body) {
      throw StateError('Quest revision archive mismatch');
    }
    return entry.pin;
  }
}

final class _AnswerCatalogEntry {
  const _AnswerCatalogEntry({
    required this.type,
    required this.activeFromUtcMs,
    required this.pin,
    required this.body,
  });
  final QuestType type;
  final int activeFromUtcMs;
  final QuestRevisionPin pin;
  final String body;
}

/// Installs and verifies the immutable authored answer Quest catalog.
final class DriftQuestRepository {
  DriftQuestRepository(this._database);

  final db.AppDatabase _database;

  Future<TrustedQuestAnswerCatalog> installAnswerCatalog({
    List<QuestCatalogRevision>? authoredRevisions,
  }) async {
    final revisions =
        authoredRevisions ?? QuestCatalogProvider.authoredRevisions;
    final entries = <_AnswerCatalogEntry>[];
    for (final revision in revisions) {
      final body = QuestCatalogProvider.canonicalAnswerManifest(revision);
      final def = revision.definition;
      final digest = sha256.convert(utf8.encode(body)).toString();
      entries.add(
        _AnswerCatalogEntry(
          type: def.type,
          activeFromUtcMs: revision.activeFromUtcMs,
          body: body,
          pin: QuestRevisionPin(
            questId: def.questId,
            catalogVersion: def.catalogVersion,
            definitionDigest: digest,
          ),
        ),
      );
    }
    for (final type in [QuestType.daily, QuestType.weekly]) {
      final group = entries.where((entry) => entry.type == type).toList()
        ..sort((a, b) => a.activeFromUtcMs.compareTo(b.activeFromUtcMs));
      if (group.isEmpty ||
          group.first.activeFromUtcMs != 0 ||
          group.any((entry) => entry.pin.questId != group.first.pin.questId)) {
        throw ArgumentError('Invalid answer Quest family');
      }
      for (var i = 1; i < group.length; i++) {
        if (group[i].activeFromUtcMs <= group[i - 1].activeFromUtcMs ||
            group[i].pin.catalogVersion <= group[i - 1].pin.catalogVersion) {
          throw ArgumentError('Invalid answer Quest activation schedule');
        }
      }
    }
    final dailyId = entries
        .firstWhere((entry) => entry.type == QuestType.daily)
        .pin
        .questId;
    final weeklyId = entries
        .firstWhere((entry) => entry.type == QuestType.weekly)
        .pin
        .questId;
    if (dailyId == weeklyId) {
      throw StateError('Daily and weekly Quest families must differ');
    }
    await _database.transaction(() async {
      for (final entry in entries) {
        await _database
            .into(_database.questDefinitionRevisions)
            .insert(
              db.QuestDefinitionRevisionsCompanion.insert(
                questId: entry.pin.questId,
                catalogVersion: entry.pin.catalogVersion,
                definitionDigest: entry.pin.definitionDigest,
                canonicalDefinition: entry.body,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        final row =
            await (_database.select(_database.questDefinitionRevisions)..where(
                  (row) =>
                      row.questId.equals(entry.pin.questId) &
                      row.catalogVersion.equals(entry.pin.catalogVersion),
                ))
                .getSingleOrNull();
        if (row == null ||
            row.definitionDigest != entry.pin.definitionDigest ||
            row.canonicalDefinition != entry.body) {
          throw StateError('Quest revision archive mismatch');
        }
      }
    });
    return TrustedQuestAnswerCatalog._(_database, List.unmodifiable(entries));
  }
}
