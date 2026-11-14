import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../learning/domain/answer_motivation_evidence.dart';
import '../../motivation/data/drift_streak_repository.dart';
import '../../motivation/domain/timezone_policy.dart';
import '../domain/quest_models.dart';
import '../domain/quest_progress_models.dart';
import 'drift_quest_repository.dart';

final class QualifiedQuestMember {
  const QualifiedQuestMember._({
    required this.instanceId,
    required this.periodKey,
    required this.originOwnerId,
    required this.calendarRuleId,
    required this.civilLabel,
    required this.segmentsJson,
    required this.assignedAtUtcMs,
  });

  final String instanceId,
      periodKey,
      originOwnerId,
      calendarRuleId,
      civilLabel,
      segmentsJson;
  final int assignedAtUtcMs;
}

final class VerifiedQuestReceipt {
  const VerifiedQuestReceipt._({
    required this.id,
    required this.ownerId,
    required this.originOwnerId,
    required this.instanceId,
    required this.issuedAtUtcMs,
    required this.completedAtUtcMs,
    required this.xpAmount,
  });

  final String id, ownerId, originOwnerId, instanceId;
  final int issuedAtUtcMs, completedAtUtcMs, xpAmount;
}

final class QualifiedQuestPeriod {
  QualifiedQuestPeriod._({
    required this.pin,
    required this.definition,
    required this.completedAtUtcMs,
    required this.evidenceJson,
    required List<QualifiedQuestMember> members,
    required List<VerifiedQuestReceipt> receipts,
  }) : members = List.unmodifiable(members),
       receipts = List.unmodifiable(receipts);

  final QuestRevisionPin pin;
  final QuestDefinition definition;
  final int completedAtUtcMs;
  final String evidenceJson;
  final List<QualifiedQuestMember> members;
  final List<VerifiedQuestReceipt> receipts;
  String get instanceId => members.first.instanceId;
  String get periodKey => members.first.periodKey;
  String get originOwnerId => members.first.originOwnerId;
  String get calendarRuleId => members.first.calendarRuleId;
  String get civilLabel => members.first.civilLabel;
  String get segmentsJson => members.first.segmentsJson;
  int get assignedAtUtcMs => members.first.assignedAtUtcMs;
  String get receiptId => 'quest-receipt:$periodKey';
  int get xpAmount => definition.reward.xpAmount;
}

final class DriftQuestProgressReader {
  const DriftQuestProgressReader(this.database, {this.catalog});

  final db.AppDatabase database;
  final TrustedQuestAnswerCatalog? catalog;

  Future<QuestSummary> load({
    required String ownerId,
    required DateTime asOfUtc,
  }) => database.transaction(() async {
    final snapshot = await _read(ownerId, asOfUtc, preview: true);
    final current = <QuestProgressCard>[], history = [...snapshot.archive];
    for (final group in snapshot.groups()) {
      (group.any((p) => p.current) ? current : history).add(
        snapshot.card(group, asOfUtc),
      );
    }
    current.sort(
      (a, b) => (a.cadence?.index ?? 99).compareTo(b.cadence?.index ?? 99),
    );
    history.sort((a, b) {
      final byTime = (b.lastEndUtc?.microsecondsSinceEpoch ?? 0).compareTo(
        a.lastEndUtc?.microsecondsSinceEpoch ?? 0,
      );
      return byTime == 0 ? a.instanceId.compareTo(b.instanceId) : byTime;
    });
    return QuestSummary(
      current: current,
      history: history,
      issues: snapshot.issues.toList(),
    );
  });

  Future<QualifiedQuestPeriod> qualify({
    required String ownerId,
    required String instanceId,
    required DateTime asOfUtc,
  }) => database.transaction(() async {
    if (!asOfUtc.isUtc || asOfUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(asOfUtc, 'asOfUtc');
    }
    // A committed receipt survives a clock rollback, even before its original answers.
    final issued =
        await (database.select(database.questClaimReceipts)
              ..where((r) => r.ownerId.equals(ownerId))
              ..limit(1))
            .getSingleOrNull();
    if (issued != null) {
      final durable = await _read(ownerId, null, preview: false);
      if (durable.invalidReceipt) {
        throw StateError('Invalid issued Quest evidence');
      }
      final replay = _qualification(
        durable,
        instanceId,
        asOfUtc,
        paidOnly: true,
      );
      if (replay != null) return replay;
    }
    final asOf = await _read(ownerId, asOfUtc, preview: false);
    return _qualification(asOf, instanceId, asOfUtc, paidOnly: false) ??
        (throw StateError('Quest period is not claimable'));
  });

  QualifiedQuestPeriod? _qualification(
    _Snapshot snapshot,
    String instanceId,
    DateTime asOfUtc, {
    required bool paidOnly,
  }) {
    for (final group in snapshot.groups()) {
      if (!group.any((p) => p.id == instanceId || p.key == instanceId)) {
        continue;
      }
      final receipts = snapshot.receipts(group);
      if (paidOnly && receipts.isEmpty) return null;
      final card = snapshot.card(group, asOfUtc);
      if (card.state != QuestProgressState.completedUnclaimed &&
          card.state != QuestProgressState.claimed) {
        throw StateError('Quest period is not claimable');
      }
      final first = group.first;
      final json = receipts.isNotEmpty
          ? snapshot.rawReceipts[receipts.first.id]!.evidenceJson
          : _issuedEvidence(
              first,
              snapshot.facts(group).take(first.target).toList(),
              card.completedAtUtc!.millisecondsSinceEpoch,
              asOfUtc.millisecondsSinceEpoch,
            );
      return QualifiedQuestPeriod._(
        pin: first.pin,
        definition: first.definition!,
        completedAtUtcMs: card.completedAtUtc!.millisecondsSinceEpoch,
        evidenceJson: json,
        members: [for (final p in group) p.member],
        receipts: receipts,
      );
    }
    return null;
  }

  Future<List<VerifiedQuestReceipt>> validatedReceipts({
    required String ownerId,
  }) => database.transaction(() async {
    final snapshot = await _read(ownerId, null, preview: false);
    if (snapshot.invalidReceipt) {
      throw StateError('Invalid issued Quest evidence');
    }
    return List<VerifiedQuestReceipt>.unmodifiable(snapshot.verified.values);
  });

  Future<_Snapshot> _read(
    String owner,
    DateTime? at, {
    required bool preview,
  }) async {
    if (at != null && (!at.isUtc || at.millisecondsSinceEpoch < 0)) {
      throw ArgumentError.value(at, 'asOfUtc');
    }
    final active = await (database.select(
      database.localOwners,
    )..where((r) => r.isActive)).get();
    if (active.length != 1 || active.single.id != owner) {
      throw StateError('Quest owner is no longer active');
    }
    final s = _Snapshot(owner);
    final epochs = await (database.select(
      database.ownerCalendarEpochs,
    )..where((r) => r.ownerId.equals(owner))).get();
    final rules = {for (final r in epochs) r.ruleId: r};
    final definitions = <(String, int, String), QuestDefinition?>{};
    Future<QuestDefinition?> definition(QuestRevisionPin pin) async {
      final key = (pin.questId, pin.catalogVersion, pin.definitionDigest);
      if (!definitions.containsKey(key)) {
        try {
          definitions[key] = (await catalog?.definitionForPin(
            database: database,
            pin: pin,
          ))?.definition;
        } on StateError {
          definitions[key] = null;
        } on FormatException {
          definitions[key] = null;
        } on ArgumentError {
          definitions[key] = null;
        }
      }
      if (definitions[key] == null) {
        s.issues.add(QuestProgressIssue.unavailableCatalog);
      }
      return definitions[key];
    }

    final query = database.select(database.answerAttempts)
      ..where(
        (r) =>
            r.ownerId.equals(owner) &
            r.legacyEvidenceDisposition.isNull() &
            r.questIntent.isNotNull(),
      );
    if (at != null) {
      query.where(
        (r) =>
            r.occurredAtUtcMs.isSmallerOrEqualValue(at.millisecondsSinceEpoch),
      );
    }
    query.orderBy([
      (r) => OrderingTerm.asc(r.occurredAtUtcMs),
      (r) => OrderingTerm.asc(r.id),
    ]);
    for (final a in await query.get()) {
      try {
        final calendar = decodeCalendarEvidence(a.calendarEvidence ?? '');
        final intent = decodeQuestIntent(a.questIntent!);
        OriginalAnswerMetadata(calendar: calendar, quest: intent);
        if (intent.occurredAtUtcMs != a.occurredAtUtcMs ||
            intent is! PinnedQuestIntent) {
          s.issues.add(QuestProgressIssue.unavailableEvidence);
          continue;
        }
        var stamp = calendar;
        final rule = intent.rule;
        final retained = rules[rule.ruleId];
        if (retained == null ||
            retained.originOwnerId != rule.originOwnerId ||
            retained.ianaId != rule.ianaId ||
            retained.tzdbRevision != rule.tzdbRevision ||
            retained.effectiveUtcUs != rule.effectiveUtcUs ||
            (rule.expiresUtcUs != null &&
                retained.expiresUtcUs != rule.expiresUtcUs)) {
          throw const FormatException('Original epoch mismatch');
        }
        if (intent is PendingQuestIntent) {
          if (rule.tzdbRevision != bundledTzdbRevision) {
            s.issues.add(QuestProgressIssue.pendingCalendar);
            continue;
          }
          try {
            stamp = _capture(rule, a.occurredAtUtcMs);
          } on StateError {
            s.issues.add(QuestProgressIssue.pendingCalendar);
            continue;
          } on ArgumentError {
            s.issues.add(QuestProgressIssue.pendingCalendar);
            continue;
          }
        }
        final c = stamp as CapturedCalendarEvidence;
        if (retained.expiresUtcUs != null &&
            c.weekSegments.last.$2 > retained.expiresUtcUs!) {
          throw const FormatException(
            'Period crosses a later scheduled expiry',
          );
        }
        final pinned = _capturedIntent(c, intent.daily, intent.weekly);
        for (final daily in [true, false]) {
          final pin = daily ? intent.daily : intent.weekly;
          final p = s.add(
            _Period.fromStamp(c, pinned, daily, await definition(pin)),
          );
          if (a.isCorrect) p.answers[a.id] = a.occurredAtUtcMs;
        }
      } on FormatException {
        s.issues.add(QuestProgressIssue.unavailableEvidence);
      }
    }
    if (preview && at != null) {
      var computingCalendar = true;
      try {
        final rule = await DriftStreakRepository(database)
            .previewCalendarRuleAt(
              ownerId: owner,
              occurredAtUtcMs: at.millisecondsSinceEpoch,
            );
        final c = _capture(rule, at.millisecondsSinceEpoch);
        computingCalendar = false;
        final pins = await catalog?.pinsForPeriod(
          database: database,
          dailyStartUtc: _us(c.daySegments.first.$1),
          weeklyStartUtc: _us(c.weekSegments.first.$1),
        );
        if (pins == null) throw StateError('Missing Quest catalog');
        final q = _capturedIntent(c, pins.daily, pins.weekly);
        for (final daily in [true, false]) {
          final p = s.add(
            _Period.fromStamp(
              c,
              q,
              daily,
              await definition(daily ? pins.daily : pins.weekly),
            ),
          );
          p.current = true;
        }
      } on StateError {
        s.issues.add(
          computingCalendar
              ? QuestProgressIssue.unavailableCalendar
              : QuestProgressIssue.unavailableCatalog,
        );
      } on ArgumentError {
        s.issues.add(QuestProgressIssue.unavailableCalendar);
      }
      // A verified existing period remains current even when a sibling archive is missing.
      for (final p in s.periods.values) {
        if (p.origin == owner &&
            rules[p.rule.ruleId]?.isSelected == true &&
            p.segments.any(
              (x) =>
                  x.$1 <= at.microsecondsSinceEpoch &&
                  at.microsecondsSinceEpoch < x.$2,
            )) {
          p.current = true;
        }
      }
    }
    final instances = await (database.select(
      database.questInstances,
    )..where((r) => r.ownerId.equals(owner))).get();
    final byId = {for (final r in instances) r.instanceId: r};
    for (final row in instances) {
      if (at != null && row.assignedAtUtcMs > at.millisecondsSinceEpoch) {
        continue;
      }
      final p = s.periods[row.periodKey];
      if (row.recordKind == 'legacy' || p == null) {
        s.archive.add(
          QuestProgressCard(
            instanceId: row.instanceId,
            cadence: null,
            civilLabel: row.civilLabel,
            title: row.questId,
            targetCount: null,
            xpAmount: null,
            correctCount: null,
            completedAtUtc: row.completedAtUtcMs == null
                ? null
                : _ms(row.completedAtUtcMs!),
            lastEndUtc: null,
            state: row.recordKind == 'legacy'
                ? QuestProgressState.legacy
                : QuestProgressState.unavailable,
          ),
        );
        if (row.recordKind != 'legacy') s.unresolvedInstances.add(row);
        continue;
      }
      if (p.physical != null || !p.matches(row)) {
        p.conflict = true;
        p.invalidAlias = true;
      }
      p.physical = row;
      if (row.recordKind == 'conflict') p.conflict = true;
    }
    for (final p in s.periods.values) {
      final row = p.physical;
      if (row?.recordKind == 'alias') {
        final parent = byId[row!.canonicalInstanceId];
        final root = s.periods[parent?.periodKey];
        if (parent == null ||
            parent.recordKind != 'canonical' ||
            root == null ||
            !root.matches(parent) ||
            !p.equivalent(root)) {
          p.invalidAlias = true;
          p.conflict = true;
          if (root != null) root.conflict = true;
        }
      }
      // An unverifiable materialized record can dispute a period even if all its original facts are gone.
      for (final r in s.unresolvedInstances.where(
        (r) => r.questId == p.pin.questId,
      )) {
        if (r.civilLabel == p.label ||
            r.periodKey == p.key ||
            _unknownOverlap(r.segmentsJson, p.segments)) {
          p.conflict = true;
        }
      }
    }
    if (instances.isNotEmpty) {
      final localIds = database.selectOnly(database.questInstances)
        ..addColumns([database.questInstances.instanceId])
        ..where(database.questInstances.ownerId.equals(owner));
      final foreignAliases =
          await (database.select(database.questInstances)..where(
                (r) =>
                    r.ownerId.equals(owner).not() &
                    r.canonicalInstanceId.isInQuery(localIds),
              ))
              .get();
      for (final r in foreignAliases) {
        final root = s.periods[byId[r.canonicalInstanceId]?.periodKey];
        if (root != null) {
          root.conflict = true;
          root.invalidAlias = true;
        }
      }
    }
    final localIds = database.selectOnly(database.questInstances)
      ..addColumns([database.questInstances.instanceId])
      ..where(database.questInstances.ownerId.equals(owner));
    final rq = database.select(
      database.questClaimReceipts,
    )..where((r) => r.ownerId.equals(owner) | r.instanceId.isInQuery(localIds));
    if (at != null) {
      rq.where(
        (r) => r.issuedAtUtcMs.isSmallerOrEqualValue(at.millisecondsSinceEpoch),
      );
    }
    for (final receipt in await rq.get()) {
      final physical = byId[receipt.instanceId],
          p = s.periods[physical?.periodKey];
      if (p == null || !s.verifyReceipt(receipt, p)) {
        s.invalidReceipt = true;
        s.issues.add(QuestProgressIssue.unavailableEvidence);
        if (p != null) p.conflict = true;
      }
    }
    return s;
  }
}

DateTime _us(int us) => DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);
DateTime _ms(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
CapturedCalendarEvidence _capture(OwnerCalendarRule r, int ms) {
  final w = TimezonePolicy.captureWindow(
    _ms(ms),
    r.ianaId,
    epochEffectiveAtUtc: _us(r.effectiveUtcUs),
    epochExpiresAtUtc: r.expiresUtcUs == null ? null : _us(r.expiresUtcUs!),
  );
  List<(int, int)> pairs(List<UtcSegment> v) => [
    for (final s in v)
      (s.startUtc.microsecondsSinceEpoch, s.endUtc.microsecondsSinceEpoch),
  ];
  return CapturedCalendarEvidence(
    originOwnerId: r.originOwnerId,
    occurredAtUtcMs: ms,
    rule: r,
    civilDay: w.civilDay.toIso8601String().substring(0, 10),
    weekMonday: w.weekMonday.toIso8601String().substring(0, 10),
    offsetSeconds: w.offsetSeconds,
    daySegments: pairs(w.daySegments),
    weekSegments: pairs(w.weekSegments),
  );
}

CapturedQuestIntent _capturedIntent(
  CapturedCalendarEvidence c,
  QuestRevisionPin daily,
  QuestRevisionPin weekly,
) => CapturedQuestIntent(
  originOwnerId: c.originOwnerId,
  occurredAtUtcMs: c.occurredAtUtcMs,
  rule: c.rule,
  daily: daily,
  weekly: weekly,
  civilDay: c.civilDay,
  weekMonday: c.weekMonday,
);

bool _overlap(List<(int, int)> a, List<(int, int)> b) {
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i].$2 <= b[j].$1) {
      i++;
    } else if (b[j].$2 <= a[i].$1) {
      j++;
    } else {
      return true;
    }
  }
  return false;
}

bool _unknownOverlap(String? encoded, List<(int, int)> other) {
  try {
    final raw = jsonDecode(encoded ?? '');
    if (raw is! List || raw.isEmpty) return true;
    int? last;
    final pairs = <(int, int)>[];
    for (final pair in raw) {
      if (pair case [int a, int b]) {
        if (a >= b || (last != null && a <= last)) return true;
        pairs.add((a, b));
        last = b;
      } else {
        return true;
      }
    }
    return _overlap(pairs, other);
  } on FormatException {
    return true;
  }
}

final class _Period {
  _Period.fromStamp(
    CapturedCalendarEvidence c,
    CapturedQuestIntent intent,
    bool daily,
    this.definition,
  ) : key = daily ? intent.dailyPeriodId : intent.weeklyPeriodId,
      pin = daily ? intent.daily : intent.weekly,
      cadence = daily ? QuestType.daily : QuestType.weekly,
      label = daily ? c.civilDay : c.weekMonday,
      rule = c.rule,
      segments = daily ? c.daySegments : c.weekSegments;
  final String key, label;
  final QuestRevisionPin pin;
  final QuestType cadence;
  final OwnerCalendarRule rule;
  final QuestDefinition? definition;
  final List<(int, int)> segments;
  late final String segmentsJson = canonicalJson([
    for (final (a, b) in segments) [a, b],
  ]);
  final answers = <String, int>{};
  db.QuestInstance? physical;
  bool conflict = false, current = false, invalidAlias = false;
  String get id => physical?.instanceId ?? key;
  String get origin => rule.originOwnerId;
  // Every supported authored objective uses the same correct-answer predicate.
  int get target => definition!.objectives
      .map((o) => o.targetCount)
      .reduce((a, b) => a > b ? a : b);
  bool equivalent(_Period p) =>
      cadence == p.cadence &&
      pin.questId == p.pin.questId &&
      pin.catalogVersion == p.pin.catalogVersion &&
      pin.definitionDigest == p.pin.definitionDigest &&
      label == p.label &&
      segmentsJson == p.segmentsJson &&
      rule.ianaId == p.rule.ianaId &&
      rule.tzdbRevision == p.rule.tzdbRevision;
  QualifiedQuestMember get member => QualifiedQuestMember._(
    instanceId: id,
    periodKey: key,
    originOwnerId: origin,
    calendarRuleId: rule.ruleId,
    civilLabel: label,
    segmentsJson: segmentsJson,
    assignedAtUtcMs: _us(segments.first.$1).millisecondsSinceEpoch,
  );
  bool matches(db.QuestInstance r) =>
      r.questId == pin.questId &&
      r.catalogVersion == pin.catalogVersion &&
      r.definitionDigest == pin.definitionDigest &&
      r.originOwnerId == origin &&
      r.calendarRuleId == rule.ruleId &&
      r.civilLabel == label &&
      r.segmentsJson == segmentsJson &&
      r.periodKey == key &&
      r.assignedAtUtcMs == member.assignedAtUtcMs;
}

typedef _Fact = ({String id, int time, _Period period});

Map<String, Object?> _memberProof(_Period p) => {
  'periodKey': p.key,
  'originOwnerId': p.origin,
  'ruleId': p.rule.ruleId,
  'ianaId': p.rule.ianaId,
  'tzdbRevision': p.rule.tzdbRevision,
  'civilLabel': p.label,
  'segments': [
    for (final (start, end) in p.segments) [start, end],
  ],
};

String _issuedEvidence(
  _Period root,
  List<_Fact> facts,
  int completed,
  int issuedAt,
) {
  final members = {
    root.key: root,
    for (final f in facts) f.period.key: f.period,
  };
  final keys = members.keys.toList()..sort();
  final json = canonicalJson({
    'v': 1,
    'periodKey': root.key,
    'originOwnerId': root.origin,
    'instanceId': root.id,
    'cadence': root.cadence.name,
    'questId': root.pin.questId,
    'catalogVersion': root.pin.catalogVersion,
    'definitionDigest': root.pin.definitionDigest,
    'completedAtUtcMs': completed,
    'issuedAtUtcMs': issuedAt,
    'members': [for (final key in keys) _memberProof(members[key]!)],
    'facts': [
      for (final f in facts) [f.id, f.time, f.period.key],
    ],
  });
  if (json.length > 65536 || utf8.encode(json).length > 65536) {
    throw StateError('Quest receipt evidence exceeds 64 KiB');
  }
  return json;
}

final class _Snapshot {
  _Snapshot(this.owner);
  final String owner;
  final periods = <String, _Period>{};
  final archive = <QuestProgressCard>[];
  final unresolvedInstances = <db.QuestInstance>[];
  final issues = <QuestProgressIssue>{};
  final verified = <String, VerifiedQuestReceipt>{};
  final rawReceipts = <String, db.QuestClaimReceipt>{};
  bool invalidReceipt = false;

  _Period add(_Period p) {
    final existing = periods.putIfAbsent(p.key, () => p);
    if (!existing.equivalent(p) ||
        existing.origin != p.origin ||
        existing.rule.ruleId != p.rule.ruleId) {
      existing.conflict = true;
    }
    if (p.definition != null && p.definition!.type != p.cadence) {
      existing.conflict = true;
      existing.invalidAlias = true;
    }
    return existing;
  }

  List<List<_Period>> groups() {
    final all = periods.values.toList();
    final buckets = <String, List<_Period>>{};
    for (final p in all) {
      // Keys here omit origin/rule ID only after validating each origin's actual epoch.
      final signature = canonicalJson([
        p.cadence.name,
        p.pin.questId,
        p.pin.catalogVersion,
        p.pin.definitionDigest,
        p.label,
        p.segmentsJson,
        p.rule.ianaId,
        p.rule.tzdbRevision,
      ]);
      (buckets[signature] ??= []).add(p);
    }
    for (var i = 0; i < all.length; i++) {
      final a = all[i];
      for (var j = i + 1; j < all.length; j++) {
        final b = all[j];
        if (a.origin == b.origin ||
            a.pin.questId != b.pin.questId ||
            a.cadence != b.cadence) {
          continue;
        }
        if (a.equivalent(b)) continue;
        if (a.label == b.label || _overlap(a.segments, b.segments)) {
          a.conflict = true;
          b.conflict = true;
        }
      }
    }
    for (final group in buckets.values) {
      final canonical = group
          .where((p) => p.physical?.recordKind == 'canonical')
          .length;
      if (canonical > 1 ||
          group.map((p) => p.origin).toSet().length != group.length ||
          group.any((p) => p.conflict)) {
        for (final p in group) {
          p.conflict = true;
        }
      }
      int priority(_Period p) => p.physical?.recordKind == 'canonical'
          ? 0
          : p.origin == owner
          ? 1
          : 2;
      group.sort((a, b) {
        final rank = priority(a).compareTo(priority(b));
        return rank == 0 ? a.key.compareTo(b.key) : rank;
      });
    }
    return buckets.values.toList();
  }

  List<_Fact> facts(List<_Period> group) {
    final list = <_Fact>[
      for (final p in group)
        for (final item in p.answers.entries)
          (id: item.key, time: item.value, period: p),
    ];
    list.sort((a, b) {
      final time = a.time.compareTo(b.time);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
    return list;
  }

  List<VerifiedQuestReceipt> receipts(List<_Period> group) {
    final ids = group.map((p) => p.id).toSet(), canonical = group.first.id;
    final list = verified.values
        .where((r) => ids.contains(r.instanceId))
        .toList();
    list.sort((a, b) {
      if (a.instanceId == canonical && b.instanceId != canonical) return -1;
      if (b.instanceId == canonical && a.instanceId != canonical) return 1;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  QuestProgressCard card(List<_Period> group, DateTime asOf) {
    final root = group.first;
    final def = root.definition;
    final ordered = facts(group), issued = receipts(group);
    final target = def == null ? null : root.target;
    final complete = issued.isNotEmpty
        ? issued.first.completedAtUtcMs
        : target != null && ordered.length >= target
        ? ordered[target - 1].time
        : null;
    final end = _us(root.segments.last.$2);
    final state = group.any((p) => p.conflict)
        ? QuestProgressState.conflict
        : def == null
        ? QuestProgressState.unavailable
        : issued.isNotEmpty
        ? QuestProgressState.claimed
        : complete != null
        ? QuestProgressState.completedUnclaimed
        : !asOf.isBefore(end)
        ? QuestProgressState.expired
        : QuestProgressState.active;
    return QuestProgressCard(
      instanceId: root.id,
      cadence: root.cadence,
      civilLabel: root.label,
      title: def?.title ?? root.pin.questId,
      targetCount: target,
      xpAmount: def?.reward.xpAmount,
      correctCount: ordered.length,
      completedAtUtc: complete == null ? null : _ms(complete),
      lastEndUtc: end,
      state: state,
      receiptIds: [for (final r in issued) r.id],
    );
  }

  bool verifyReceipt(db.QuestClaimReceipt r, _Period p) {
    final physical = p.physical;
    if (physical == null ||
        p.invalidAlias ||
        physical.instanceId != r.instanceId ||
        !p.matches(physical) ||
        physical.completedAtUtcMs != r.completedAtUtcMs ||
        physical.state != 'completed' ||
        r.ownerId != owner ||
        r.originOwnerId != p.origin ||
        r.id != 'quest-receipt:${p.key}' ||
        p.definition == null ||
        p.definition!.reward.xpAmount != r.xpAmount ||
        r.completedAtUtcMs > r.issuedAtUtcMs ||
        r.evidenceJson.length > 65536 ||
        utf8.encode(r.evidenceJson).length > 65536) {
      return false;
    }
    try {
      final decoded = jsonDecode(r.evidenceJson);
      if (decoded is! Map<String, dynamic>) return false;
      final proof = decoded['facts'];
      if (proof is! List || proof.length != p.target) return false;
      final selected = <_Fact>[], seen = <String>{};
      for (final raw in proof) {
        if (raw case [final String id, final int time, final String key]) {
          final member = periods[key];
          if (member == null ||
              member.invalidAlias ||
              !member.equivalent(p) ||
              member.answers[id] != time ||
              !seen.add(id) ||
              time > r.issuedAtUtcMs) {
            return false;
          }
          if (selected.isNotEmpty &&
              (time < selected.last.time ||
                  (time == selected.last.time &&
                      id.compareTo(selected.last.id) <= 0))) {
            return false;
          }
          selected.add((id: id, time: time, period: member));
        } else {
          return false;
        }
      }
      if (selected.last.time != r.completedAtUtcMs ||
          _issuedEvidence(p, selected, r.completedAtUtcMs, r.issuedAtUtcMs) !=
              r.evidenceJson) {
        return false;
      }
    } on FormatException {
      return false;
    }
    final receipt = VerifiedQuestReceipt._(
      id: r.id,
      ownerId: owner,
      originOwnerId: r.originOwnerId,
      instanceId: r.instanceId,
      issuedAtUtcMs: r.issuedAtUtcMs,
      completedAtUtcMs: r.completedAtUtcMs,
      xpAmount: r.xpAmount,
    );
    verified[r.id] = receipt;
    rawReceipts[r.id] = r;
    return true;
  }
}
