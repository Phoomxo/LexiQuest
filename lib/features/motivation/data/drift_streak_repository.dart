import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../data/local/app_database.dart' as db;
import '../../learning/domain/answer_motivation_evidence.dart';
import '../domain/streak_policy.dart';
import '../domain/timezone_policy.dart';

/// Drift-backed persistence for [StreakState] and [LearningDayLog].
final class DriftStreakRepository {
  DriftStreakRepository(this._database, {this.calendarVisible});

  final db.AppDatabase _database;
  final bool Function()? calendarVisible;

  Future<StreakFoldResult> loadLearningDays({
    required String ownerId,
    required DateTime asOfUtc,
  }) => _database.transaction(() async {
    final at = _calendarTime(asOfUtc);
    await _requireCalendarOwner(ownerId);
    final snapshot = await _streakSnapshot(ownerId, at);
    final view = StreakPolicy.fold(snapshot.input);
    if (snapshot.missingLogs.isNotEmpty &&
        view.status == StreakFoldStatus.ready) {
      return _withStatus(view, StreakFoldStatus.pending);
    }
    return view;
  });

  Future<StreakFoldResult> settle({
    required String expectedOwnerId,
    required DateTime asOfUtc,
    ({String attemptId, int occurredAtUtcMs})? answer,
  }) => _database.transaction(() async {
    final at = _calendarTime(asOfUtc);
    await _requireCalendarOwner(expectedOwnerId);
    if (answer != null) {
      final row = await (_database.select(
        _database.answerAttempts,
      )..where((r) => r.id.equals(answer.attemptId))).getSingleOrNull();
      if (row == null ||
          row.ownerId != expectedOwnerId ||
          row.occurredAtUtcMs != answer.occurredAtUtcMs) {
        throw StateError('Committed streak answer does not match');
      }
    }
    final snapshot = await _streakSnapshot(expectedOwnerId, at);
    final input = snapshot.input;
    final prior = input.settled;
    if (prior != null && prior.updatedAtUtcMs > at) {
      // A historical view cannot replace a later accepted learning horizon.
      return StreakPolicy.fold(input);
    }
    final proposal = StreakPolicy.evaluateForward(input);
    if (proposal.result.status == StreakFoldStatus.unavailable) {
      return proposal.result;
    }
    if (proposal.autoDebits.isNotEmpty &&
        _walletAt(input, snapshot.lastAssetMs, proposal.autoDebits).status ==
            StreakFoldStatus.unavailable) {
      return _withStatus(
        StreakPolicy.fold(input),
        StreakFoldStatus.unavailable,
      );
    }
    for (final debit in proposal.autoDebits) {
      await _postDebit(expectedOwnerId, debit);
    }
    for (final entry in snapshot.missingLogs.entries) {
      await _database.customInsert(
        'INSERT INTO learning_day_log (id,owner_id,learning_day,first_session_at_utc_ms) '
        'VALUES (?,?,?,?) ON CONFLICT(owner_id,learning_day) DO UPDATE SET '
        'first_session_at_utc_ms=MIN(learning_day_log.first_session_at_utc_ms,excluded.first_session_at_utc_ms)',
        variables: [
          Variable('day:$expectedOwnerId:${entry.key}'),
          Variable(expectedOwnerId),
          Variable(entry.key),
          Variable(entry.value),
        ],
        updates: {_database.learningDayLog},
      );
    }
    final next = proposal.result.state;
    if (prior == null
        ? next.lastLearnedAtUtcMs != null ||
              next.longestStreakDays != 0 ||
              next.freezeCount != 0
        : next.currentStreakDays != prior.currentStreakDays ||
              next.longestStreakDays != prior.longestStreakDays ||
              next.lastLearnedAtUtcMs != prior.lastLearnedAtUtcMs ||
              next.freezeCount != prior.freezeCount) {
      await _save(next);
    }
    return proposal.result;
  });

  Future<bool> debitFreezeToken({
    required String expectedOwnerId,
    required String commandId,
    required DateTime occurredAtUtc,
  }) => _database.transaction(() async {
    final at = _calendarTime(occurredAtUtc);
    await _requireCalendarOwner(expectedOwnerId);
    if (commandId.trim().isEmpty) {
      throw ArgumentError.value(commandId, 'commandId');
    }
    final existing =
        await (_database.select(_database.streakTokenAdjustments)..where(
              (r) =>
                  r.originOwnerId.equals(expectedOwnerId) &
                  r.commandId.equals(commandId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      if (existing.ownerId != expectedOwnerId ||
          existing.kind != 'manualDebit' ||
          existing.delta != -1 ||
          existing.protectedDay != null) {
        throw StateError('Conflicting streak token command');
      }
      return true;
    }
    final snapshot = await _streakSnapshot(expectedOwnerId, at);
    final input = snapshot.input;
    final view = StreakPolicy.fold(input);
    if (view.status == StreakFoldStatus.unavailable ||
        view.state.freezeCount <= 0) {
      return false;
    }
    final debit = StreakMovement(
      originOwnerId: expectedOwnerId,
      commandId: commandId,
      kind: StreakMovementKind.manualDebit,
      delta: -1,
      occurredAtUtcMs: at,
    );
    if (_walletAt(input, snapshot.lastAssetMs, [debit]).status ==
        StreakFoldStatus.unavailable) {
      return false;
    }
    await _postDebit(expectedOwnerId, debit);
    // Manual spending changes the wallet only. Unsettled attendance must
    // remain eligible for the normal forward settlement.
    final prior = input.settled;
    final publishAt = prior != null && prior.updatedAtUtcMs > at
        ? prior.updatedAtUtcMs
        : at;
    final balance = _walletAt(input, publishAt, [debit]).state.freezeCount;
    final base =
        prior ??
        input.openings
            .where(
              (opening) =>
                  opening.controlsContinuity &&
                  opening.cutoffUtcMs <= publishAt,
            )
            .firstOrNull
            ?.raw ??
        StreakState.initial(ownerId: expectedOwnerId, nowMs: publishAt);
    await _save(base.copyWith(freezeCount: balance, updatedAtUtcMs: publishAt));
    return true;
  });

  Future<void> _postDebit(String owner, StreakMovement movement) async {
    await _database
        .into(_database.streakTokenAdjustments)
        .insert(
          db.StreakTokenAdjustmentsCompanion.insert(
            id: 'streak:${jsonEncode([movement.originOwnerId, movement.commandId])}',
            ownerId: owner,
            originOwnerId: movement.originOwnerId,
            commandId: movement.commandId,
            kind: movement.kind.name,
            occurredAtUtcMs: movement.occurredAtUtcMs,
            delta: movement.delta,
            protectedDay: Value(
              movement.protectedDay == null
                  ? null
                  : _label(movement.protectedDay!),
            ),
          ),
        );
  }

  StreakFoldResult _walletAt(
    StreakFoldInput input,
    int at,
    List<StreakMovement> proposed,
  ) => StreakPolicy.fold(
    StreakFoldInput(
      ownerId: input.ownerId,
      today: input.today,
      asOfUtcMs: at,
      facts: const [],
      movements: [...input.movements, ...proposed],
      openings: input.openings,
      transferAtUtcMs: input.transferAtUtcMs,
      unresolvedEvidence: input.unresolvedEvidence,
    ),
  );

  StreakFoldResult _withStatus(
    StreakFoldResult result,
    StreakFoldStatus status,
  ) => StreakFoldResult(
    state: result.state,
    currentStreakDays: result.currentStreakDays,
    days: result.days,
    status: status,
    uncertainHistory: result.uncertainHistory,
  );

  Future<
    ({StreakFoldInput input, Map<String, int> missingLogs, int lastAssetMs})
  >
  _streakSnapshot(String owner, int at) async {
    final owners = await _database.select(_database.localOwners).get();
    final transfers = <String, int>{};
    final merged = <String>{};
    var unresolved = false;
    // Walk incoming edges from this target. Funds from an earlier source
    // become available here only after the last merge on its path.
    void collectTransfers(String target, int? laterEdge) {
      for (final source in owners.where(
        (o) => o.accountState == 'mergedInto:$target',
      )) {
        final edge = source.upgradedAtUtcMs;
        if (!merged.add(source.id) ||
            source.id == owner ||
            source.isActive ||
            edge == null ||
            edge < source.createdAtUtcMs ||
            (laterEdge != null && edge > laterEdge)) {
          unresolved = true;
          continue;
        }
        transfers[source.id] = transfers[target] ?? edge;
        collectTransfers(source.id, edge);
      }
    }

    collectTransfers(owner, null);
    final epochs = await (_database.select(
      _database.ownerCalendarEpochs,
    )..where((r) => r.ownerId.equals(owner))).get();
    final rules = {for (final epoch in epochs) epoch.ruleId: epoch};
    final baselines = await (_database.select(
      _database.streakBaselines,
    )..where((r) => r.ownerId.equals(owner))).get();
    final adjustments = await (_database.select(
      _database.streakTokenAdjustments,
    )..where((r) => r.ownerId.equals(owner))).get();
    final incoming =
        merged.isNotEmpty ||
        epochs.any((r) => r.originOwnerId != owner) ||
        baselines.any((r) => r.originOwnerId != owner) ||
        adjustments.any((r) => r.originOwnerId != owner);
    if ([
      ...epochs.map((r) => r.originOwnerId),
      ...baselines.map((r) => r.originOwnerId),
      ...adjustments.map((r) => r.originOwnerId),
    ].any((origin) => origin != owner && !transfers.containsKey(origin))) {
      unresolved = true;
    }
    final instant = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
    var today = DateTime.utc(instant.year, instant.month, instant.day);
    try {
      final rule = await previewCalendarRuleAt(
        ownerId: owner,
        occurredAtUtcMs: at,
      );
      if (rule.ianaId != 'UTC') today = _window(rule, at).civilDay;
    } on StateError {
      unresolved = true;
    } on ArgumentError {
      unresolved = true;
    }
    final facts = <StreakDayFact>[];
    final firstByLabel = <String, int>{};
    final attempts =
        await (_database.select(_database.answerAttempts)..where(
              (r) =>
                  r.ownerId.equals(owner) &
                  r.occurredAtUtcMs.isSmallerOrEqualValue(at),
            ))
            .get();
    for (final attempt in attempts) {
      try {
        final fact = _studyFact(attempt, rules, singleOwner: !incoming);
        facts.add(fact);
        firstByLabel.update(
          _label(fact.day),
          (previous) =>
              previous < fact.occurredAtUtcMs ? previous : fact.occurredAtUtcMs,
          ifAbsent: () => fact.occurredAtUtcMs,
        );
      } on FormatException {
        unresolved = true;
      } on StateError {
        unresolved = true;
      } on ArgumentError {
        unresolved = true;
      }
    }
    final logs = await (_database.select(
      _database.learningDayLog,
    )..where((r) => r.ownerId.equals(owner))).get();
    final missingLogs = Map.of(firstByLabel);
    final logDaysAt = <int, Set<DateTime>>{};
    for (final row in logs) {
      final first = row.firstSessionAtUtcMs;
      if (first > at) continue;
      final day = _parseDay(row.learningDay);
      if (day == null || first < 0) {
        unresolved = true;
        continue;
      }
      logDaysAt.putIfAbsent(first, () => {}).add(day);
      final fromAnswer = firstByLabel[row.learningDay];
      if (fromAnswer == null) {
        facts.add(
          StreakDayFact(id: 'log:${row.id}', occurredAtUtcMs: first, day: day),
        );
      } else if (first <= fromAnswer) {
        missingLogs.remove(row.learningDay);
      }
    }
    var lastAssetMs = at;
    final openings = <StreakOpening>[];
    for (final raw in baselines) {
      if (raw.cutoffUtcMs > lastAssetMs) lastAssetMs = raw.cutoffUtcMs;
      final last = raw.lastLearnedAtUtcMs;
      final labels = {
        if (last != null)
          for (final fact in facts)
            if (fact.occurredAtUtcMs == last &&
                fact.originOwnerId == raw.originOwnerId)
              fact.day,
        if (last != null && !incoming) ...?logDaysAt[last],
      };
      openings.add(
        StreakOpening(
          originOwnerId: raw.originOwnerId,
          controlsContinuity: raw.controlsContinuity,
          cutoffUtcMs: raw.cutoffUtcMs,
          lastDay: labels.length == 1 ? labels.single : null,
          raw: StreakState(
            ownerId: owner,
            currentStreakDays: raw.currentStreakDays,
            longestStreakDays: raw.longestStreakDays,
            freezeCount: raw.freezeCount,
            lastLearnedAtUtcMs: last,
            updatedAtUtcMs: raw.updatedAtUtcMs,
          ),
        ),
      );
    }
    final movements = <StreakMovement>[];
    for (final row in adjustments) {
      final kind = StreakMovementKind.values
          .where((k) => k.name == row.kind)
          .firstOrNull;
      final day = row.protectedDay == null
          ? null
          : _parseDay(row.protectedDay!);
      if (kind == null || (row.protectedDay != null && day == null)) {
        unresolved = true;
        continue;
      }
      movements.add(
        StreakMovement(
          originOwnerId: row.originOwnerId,
          commandId: row.commandId,
          kind: kind,
          delta: row.delta,
          occurredAtUtcMs: row.occurredAtUtcMs,
          protectedDay: day,
        ),
      );
      if (row.occurredAtUtcMs > lastAssetMs) lastAssetMs = row.occurredAtUtcMs;
    }
    for (final transfer in transfers.values) {
      if (transfer > lastAssetMs) lastAssetMs = transfer;
    }
    final stored = await (_database.select(
      _database.streakStates,
    )..where((r) => r.ownerId.equals(owner))).getSingleOrNull();
    return (
      input: StreakFoldInput(
        ownerId: owner,
        asOfUtcMs: at,
        today: today,
        facts: facts,
        openings: openings,
        movements: movements,
        transferAtUtcMs: transfers,
        unresolvedEvidence: unresolved,
        settled: stored == null ? null : _rowToState(stored),
      ),
      missingLogs: missingLogs,
      lastAssetMs: lastAssetMs,
    );
  }

  StreakDayFact _studyFact(
    db.AnswerAttempt attempt,
    Map<String, db.OwnerCalendarEpoch> rules, {
    required bool singleOwner,
  }) {
    final at = attempt.occurredAtUtcMs;
    final id = 'answer:${attempt.id}';
    final encoded = attempt.calendarEvidence;
    if (encoded == null) {
      if (attempt.questIntent != null) {
        throw const FormatException('Missing original answer calendar');
      }
      final instant = DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
      return StreakDayFact(
        id: id,
        occurredAtUtcMs: at,
        day: DateTime.utc(instant.year, instant.month, instant.day),
        legacyUtcAttendance: singleOwner,
      );
    }
    final evidence = decodeCalendarEvidence(encoded);
    final rule = switch (evidence) {
      CapturedCalendarEvidence() => evidence.rule,
      UnavailableCalendarEvidence() => evidence.rule,
    };
    final retained = rules[rule?.ruleId];
    if (at != evidence.occurredAtUtcMs ||
        rule == null ||
        retained == null ||
        retained.originOwnerId != rule.originOwnerId ||
        retained.effectiveUtcUs != rule.effectiveUtcUs ||
        retained.ianaId != rule.ianaId ||
        retained.tzdbRevision != rule.tzdbRevision ||
        (rule.expiresUtcUs != null &&
            retained.expiresUtcUs != rule.expiresUtcUs)) {
      throw const FormatException('Unverified original streak calendar');
    }
    late final DateTime day;
    late final int end;
    if (evidence is CapturedCalendarEvidence) {
      day = _parseDay(evidence.civilDay)!;
      end = evidence.weekSegments.last.$2;
    } else {
      if (rule.tzdbRevision != bundledTzdbRevision) {
        throw const FormatException('Original timezone bundle unavailable');
      }
      final window = _window(rule, at);
      day = window.civilDay;
      end = window.weekSegments.last.endUtc.microsecondsSinceEpoch;
    }
    if (retained.expiresUtcUs != null && end > retained.expiresUtcUs!) {
      throw const FormatException('Streak period exceeds its retained epoch');
    }
    bool? precedingCivilDayExists;
    if (rule.tzdbRevision == bundledTzdbRevision) {
      try {
        precedingCivilDayExists = TimezonePolicy.hasCivilDay(
          day.subtract(const Duration(days: 1)),
          rule.ianaId,
          epochEffectiveAtUtc: _calendarUtc(rule.effectiveUtcUs),
          epochExpiresAtUtc: rule.expiresUtcUs == null
              ? null
              : _calendarUtc(rule.expiresUtcUs!),
        );
      } on StateError {
        // The stored day remains authoritative without a local copy of its zone.
      } on ArgumentError {
        // An unsupported inverse interval cannot authorize a gap debit.
      }
    }
    return StreakDayFact(
      id: id,
      occurredAtUtcMs: at,
      day: day,
      originOwnerId: evidence.originOwnerId,
      calendarRuleId: rule.ruleId,
      precedingCivilDayExists: precedingCivilDayExists,
    );
  }

  LearningCalendarWindow _window(OwnerCalendarRule rule, int at) =>
      TimezonePolicy.captureWindow(
        DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
        rule.ianaId,
        epochEffectiveAtUtc: _calendarUtc(rule.effectiveUtcUs),
        epochExpiresAtUtc: rule.expiresUtcUs == null
            ? null
            : _calendarUtc(rule.expiresUtcUs!),
      );

  String _label(DateTime day) => day.toIso8601String().substring(0, 10);

  DateTime? _parseDay(String label) {
    if (label.length != 10) return null;
    final day = DateTime.tryParse('${label}T00:00:00Z');
    return day != null && _label(day) == label ? day : null;
  }

  Future<OwnerCalendarRule> selectHomeTimezone({
    required String expectedOwnerId,
    required String ianaId,
    required DateTime occurredAtUtc,
  }) => _database.transaction(() async {
    final nowMs = _calendarTime(occurredAtUtc);
    await _requireCalendarOwner(expectedOwnerId);
    if (!(calendarVisible?.call() ?? false)) {
      throw StateError('Home calendar selection is unavailable');
    }
    _requireCalendarZone(ianaId);
    final current = await calendarRuleAt(
      ownerId: expectedOwnerId,
      occurredAtUtcMs: nowMs,
    );
    final pending = await _pendingCalendarRule(expectedOwnerId, nowMs, current);
    if (pending != null && pending.ianaId == ianaId) return pending;
    if (pending == null && current.ianaId == ianaId) return current;

    final window = TimezonePolicy.captureWindow(
      DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true),
      current.ianaId,
      epochEffectiveAtUtc: _calendarUtc(current.effectiveUtcUs),
    );
    final boundary = window.weekSegments.last.endUtc.microsecondsSinceEpoch;
    if (boundary <= nowMs * 1000 ||
        boundary > tz.maxTime * 1000 ||
        (current.expiresUtcUs != null && current.expiresUtcUs != boundary) ||
        (pending != null && pending.effectiveUtcUs != boundary)) {
      throw StateError('Home calendar cutover is not a complete week boundary');
    }
    await _checkCalendarReferences(
      current,
      boundary,
      replacingRuleId: pending?.ruleId,
    );
    if (current.expiresUtcUs == null) {
      final changed =
          await (_database.update(_database.ownerCalendarEpochs)..where(
                (r) =>
                    r.ruleId.equals(current.ruleId) &
                    r.ownerId.equals(expectedOwnerId),
              ))
              .write(
                db.OwnerCalendarEpochsCompanion(expiresUtcUs: Value(boundary)),
              );
      if (changed != 1) throw StateError('Current calendar authority changed');
    }
    if (pending != null) {
      final changed =
          await (_database.update(_database.ownerCalendarEpochs)..where(
                (r) =>
                    r.ruleId.equals(pending.ruleId) &
                    r.ownerId.equals(expectedOwnerId),
              ))
              .write(
                db.OwnerCalendarEpochsCompanion(
                  ianaId: Value(ianaId),
                  tzdbRevision: const Value(bundledTzdbRevision),
                ),
              );
      if (changed != 1) throw StateError('Pending calendar authority changed');
    } else {
      final ruleId = 'calendar:home:$expectedOwnerId:$boundary';
      if (ruleId.length > 512) {
        throw StateError('Calendar identity is too long');
      }
      await _database
          .into(_database.ownerCalendarEpochs)
          .insert(
            db.OwnerCalendarEpochsCompanion.insert(
              ruleId: ruleId,
              ownerId: expectedOwnerId,
              originOwnerId: expectedOwnerId,
              effectiveUtcUs: boundary,
              ianaId: ianaId,
              tzdbRevision: bundledTzdbRevision,
              isSelected: true,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    final row =
        await (_database.select(_database.ownerCalendarEpochs)..where(
              (r) =>
                  r.originOwnerId.equals(expectedOwnerId) &
                  r.effectiveUtcUs.equals(boundary),
            ))
            .getSingleOrNull();
    final expectedId =
        pending?.ruleId ?? 'calendar:home:$expectedOwnerId:$boundary';
    if (row == null ||
        row.ruleId != expectedId ||
        row.ownerId != expectedOwnerId ||
        !row.isSelected ||
        row.expiresUtcUs != null ||
        row.ianaId != ianaId ||
        row.tzdbRevision != bundledTzdbRevision) {
      throw StateError('Conflicting home calendar authority');
    }
    return _calendarRule(row);
  });

  Future<({OwnerCalendarRule current, OwnerCalendarRule? pending})>
  previewCalendarSchedule({
    required String ownerId,
    required DateTime asOfUtc,
  }) => _database.transaction(() async {
    final atMs = _calendarTime(asOfUtc);
    await _requireCalendarOwner(ownerId);
    final current = await _resolveCalendarRule(
      ownerId: ownerId,
      occurredAtUtcMs: atMs,
      createDefault: false,
    );
    final pending = await _pendingCalendarRule(ownerId, atMs, current);
    return (current: current, pending: pending);
  });

  int _calendarTime(DateTime value) {
    if (!value.isUtc ||
        value.microsecondsSinceEpoch < 0 ||
        value.millisecondsSinceEpoch > tz.maxTime) {
      throw ArgumentError('Calendar time must be supported nonnegative UTC');
    }
    return value.millisecondsSinceEpoch;
  }

  Future<void> _requireCalendarOwner(String ownerId) async {
    final active = await (_database.select(
      _database.localOwners,
    )..where((r) => r.isActive.equals(true))).get();
    if (active.length != 1 || active.single.id != ownerId) {
      throw StateError('Home calendar owner changed');
    }
  }

  void _requireCalendarZone(String ianaId) {
    if (ianaId != 'UTC' &&
        (!ianaId.contains('/') ||
            !tz.timeZoneDatabase.isInitialized ||
            !tz.timeZoneDatabase.locations.containsKey(ianaId))) {
      throw ArgumentError('A bundled IANA region or explicit UTC is required');
    }
  }

  DateTime _calendarUtc(int us) =>
      DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true);

  OwnerCalendarRule _calendarRule(db.OwnerCalendarEpoch row) =>
      OwnerCalendarRule(
        ruleId: row.ruleId,
        originOwnerId: row.originOwnerId,
        ianaId: row.ianaId,
        tzdbRevision: row.tzdbRevision,
        effectiveUtcUs: row.effectiveUtcUs,
        expiresUtcUs: row.expiresUtcUs,
      );

  Future<OwnerCalendarRule?> _pendingCalendarRule(
    String ownerId,
    int atMs,
    OwnerCalendarRule current,
  ) async {
    final future =
        await (_database.select(_database.ownerCalendarEpochs)..where(
              (r) =>
                  r.ownerId.equals(ownerId) &
                  r.isSelected.equals(true) &
                  r.effectiveUtcUs.isBiggerThanValue(atMs * 1000),
            ))
            .get();
    if (future.isEmpty) {
      if (current.expiresUtcUs != null) {
        throw StateError('Calendar schedule has a gap');
      }
      return null;
    }
    if (future.length != 1) throw StateError('Ambiguous pending home calendar');
    final row = future.single;
    if (row.originOwnerId != ownerId ||
        row.effectiveUtcUs != current.expiresUtcUs ||
        row.expiresUtcUs != null ||
        row.tzdbRevision != bundledTzdbRevision) {
      throw StateError('Invalid pending home calendar');
    }
    _requireCalendarZone(row.ianaId);
    return _calendarRule(row);
  }

  Future<void> _checkCalendarReferences(
    OwnerCalendarRule current,
    int boundary, {
    String? replacingRuleId,
  }) async {
    final attempts = await (_database.select(
      _database.answerAttempts,
    )..where((r) => r.ownerId.equals(current.originOwnerId))).get();
    for (final attempt in attempts) {
      if (attempt.calendarEvidence == null && attempt.questIntent == null) {
        continue;
      }
      try {
        final calendar = decodeCalendarEvidence(attempt.calendarEvidence ?? '');
        final intent = attempt.questIntent == null
            ? null
            : decodeQuestIntent(attempt.questIntent!);
        OriginalAnswerMetadata(calendar: calendar, quest: intent);
        if (calendar.occurredAtUtcMs != attempt.occurredAtUtcMs) {
          throw StateError('Original calendar occurrence mismatch');
        }
        final rule = switch (calendar) {
          CapturedCalendarEvidence() => calendar.rule,
          UnavailableCalendarEvidence() => calendar.rule,
        };
        if (rule == null) {
          throw StateError('Original calendar authority is unavailable');
        }
        if (replacingRuleId != null && rule.ruleId == replacingRuleId) {
          throw StateError(
            'Pending home calendar has original answer references',
          );
        }
        if (rule.ruleId != current.ruleId) continue;
        if (rule.originOwnerId != current.originOwnerId ||
            rule.ianaId != current.ianaId ||
            rule.tzdbRevision != current.tzdbRevision ||
            rule.effectiveUtcUs != current.effectiveUtcUs ||
            (rule.expiresUtcUs != null &&
                rule.expiresUtcUs != current.expiresUtcUs)) {
          throw StateError(
            'Original calendar rule differs from retained authority',
          );
        }
        if (calendar is CapturedCalendarEvidence) {
          if (calendar.daySegments.last.$2 > boundary ||
              calendar.weekSegments.last.$2 > boundary) {
            throw StateError(
              'Captured period extends beyond the proposed cutover',
            );
          }
        } else {
          if (rule.tzdbRevision != bundledTzdbRevision) {
            throw StateError('Original calendar bundle is unavailable');
          }
          final original = TimezonePolicy.captureWindow(
            DateTime.fromMillisecondsSinceEpoch(
              attempt.occurredAtUtcMs,
              isUtc: true,
            ),
            rule.ianaId,
            epochEffectiveAtUtc: _calendarUtc(rule.effectiveUtcUs),
            epochExpiresAtUtc: rule.expiresUtcUs == null
                ? null
                : _calendarUtc(rule.expiresUtcUs!),
          );
          if (original.weekSegments.last.endUtc.microsecondsSinceEpoch >
              boundary) {
            throw StateError(
              'Pending period extends beyond the proposed cutover',
            );
          }
        }
      } on FormatException {
        throw StateError('Original calendar references cannot be verified');
      }
    }
    final ids = [current.ruleId, ?replacingRuleId];
    final instances = await (_database.select(
      _database.questInstances,
    )..where((r) => r.calendarRuleId.isIn(ids))).get();
    for (final row in instances) {
      if (row.calendarRuleId == replacingRuleId) {
        throw StateError('Pending home calendar has Quest history references');
      }
      if (row.ownerId != current.originOwnerId ||
          row.originOwnerId != current.originOwnerId) {
        throw StateError('Calendar history belongs to a different owner');
      }
      try {
        final raw = jsonDecode(row.segmentsJson ?? '');
        if (raw is! List || raw.isEmpty) throw const FormatException();
        int? last;
        for (final part in raw) {
          if (part case [final int start, final int end]) {
            if (start < current.effectiveUtcUs ||
                start >= end ||
                (last != null && start <= last) ||
                end > boundary ||
                (current.expiresUtcUs != null && end > current.expiresUtcUs!)) {
              throw const FormatException();
            }
            last = end;
          } else {
            throw const FormatException();
          }
        }
      } on FormatException {
        throw StateError(
          'Quest history crosses or cannot prove the calendar cutover',
        );
      }
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<OwnerCalendarRule> previewCalendarRuleAt({
    required String ownerId,
    required int occurredAtUtcMs,
  }) => _resolveCalendarRule(
    ownerId: ownerId,
    occurredAtUtcMs: occurredAtUtcMs,
    createDefault: false,
  );

  Future<OwnerCalendarRule> calendarRuleAt({
    required String ownerId,
    required int occurredAtUtcMs,
  }) => _database.transaction(
    () => _resolveCalendarRule(
      ownerId: ownerId,
      occurredAtUtcMs: occurredAtUtcMs,
      createDefault: true,
    ),
    requireNew: true,
  );

  Future<OwnerCalendarRule> _resolveCalendarRule({
    required String ownerId,
    required int occurredAtUtcMs,
    required bool createDefault,
  }) async {
    if (ownerId.trim().isEmpty ||
        occurredAtUtcMs < 0 ||
        occurredAtUtcMs > tz.maxTime) {
      throw ArgumentError('Invalid calendar owner or occurrence');
    }
    final owner = await (_database.select(
      _database.localOwners,
    )..where((row) => row.id.equals(ownerId))).getSingleOrNull();
    if (owner == null || occurredAtUtcMs < owner.createdAtUtcMs) {
      throw StateError('No calendar authority for this owner and occurrence');
    }
    final rules =
        await (_database.select(_database.ownerCalendarEpochs)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([(row) => OrderingTerm.asc(row.effectiveUtcUs)]))
            .get();
    var selected = rules.where((row) => row.isSelected).toList();
    if (selected.isEmpty) {
      if (rules.any((row) => row.originOwnerId == ownerId)) {
        throw StateError('Retired calendar authority cannot be reactivated');
      }
      final defaultId = 'calendar:utc-default:$ownerId';
      final effective = owner.createdAtUtcMs * 1000;
      if (!createDefault) {
        if (effective < tz.minTime * 1000 || effective > tz.maxTime * 1000) {
          throw StateError('Invalid calendar authority');
        }
        final collision = await (_database.select(
          _database.ownerCalendarEpochs,
        )..where((row) => row.ruleId.equals(defaultId))).getSingleOrNull();
        if (collision != null) {
          throw StateError('Default UTC calendar provenance conflict');
        }
        return OwnerCalendarRule(
          ruleId: defaultId,
          originOwnerId: ownerId,
          ianaId: 'UTC',
          tzdbRevision: bundledTzdbRevision,
          effectiveUtcUs: effective,
        );
      }
      await _database
          .into(_database.ownerCalendarEpochs)
          .insert(
            db.OwnerCalendarEpochsCompanion.insert(
              ruleId: defaultId,
              ownerId: ownerId,
              originOwnerId: ownerId,
              effectiveUtcUs: effective,
              ianaId: 'UTC',
              tzdbRevision: bundledTzdbRevision,
              isSelected: true,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final stored = await (_database.select(
        _database.ownerCalendarEpochs,
      )..where((row) => row.ruleId.equals(defaultId))).getSingleOrNull();
      if (stored == null ||
          stored.ownerId != ownerId ||
          stored.originOwnerId != ownerId ||
          stored.effectiveUtcUs != effective ||
          stored.expiresUtcUs != null ||
          stored.ianaId != 'UTC' ||
          stored.tzdbRevision != bundledTzdbRevision ||
          !stored.isSelected) {
        throw StateError('Default UTC calendar provenance conflict');
      }
      selected = [stored];
    }
    for (var index = 0; index < selected.length; index++) {
      final rule = selected[index];
      if (rule.originOwnerId != ownerId ||
          rule.ruleId.trim().isEmpty ||
          rule.effectiveUtcUs < tz.minTime * 1000 ||
          rule.effectiveUtcUs > tz.maxTime * 1000 ||
          (rule.expiresUtcUs != null &&
              (rule.expiresUtcUs! <= rule.effectiveUtcUs ||
                  rule.expiresUtcUs! > tz.maxTime * 1000))) {
        throw StateError('Invalid calendar authority');
      }
      if (index > 0 &&
          (selected[index - 1].expiresUtcUs == null ||
              selected[index - 1].expiresUtcUs! > rule.effectiveUtcUs)) {
        throw StateError('Selected calendar authorities overlap');
      }
    }
    final occurredUs = occurredAtUtcMs * 1000;
    final matching = selected.where(
      (rule) =>
          rule.effectiveUtcUs <= occurredUs &&
          (rule.expiresUtcUs == null || occurredUs < rule.expiresUtcUs!),
    );
    if (matching.length != 1) {
      throw StateError('No selected calendar authority at the occurrence');
    }
    final rule = matching.single;
    if (rule.tzdbRevision != bundledTzdbRevision ||
        (rule.ianaId != 'UTC' &&
            (!tz.timeZoneDatabase.isInitialized ||
                !tz.timeZoneDatabase.locations.containsKey(rule.ianaId)))) {
      throw StateError('Calendar timezone authority is unavailable');
    }
    return OwnerCalendarRule(
      ruleId: rule.ruleId,
      originOwnerId: rule.originOwnerId,
      ianaId: rule.ianaId,
      tzdbRevision: rule.tzdbRevision,
      effectiveUtcUs: rule.effectiveUtcUs,
      expiresUtcUs: rule.expiresUtcUs,
    );
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> _save(StreakState state) async {
    await _database
        .into(_database.streakStates)
        .insertOnConflictUpdate(
          db.StreakStatesCompanion(
            ownerId: Value(state.ownerId),
            currentStreakDays: Value(state.currentStreakDays),
            longestStreakDays: Value(state.longestStreakDays),
            freezeCount: Value(state.freezeCount),
            lastLearnedAtUtcMs: Value(state.lastLearnedAtUtcMs),
            updatedAtUtcMs: Value(state.updatedAtUtcMs),
          ),
        );
  }

  // ── Private ───────────────────────────────────────────────────────────────

  StreakState _rowToState(db.StreakState row) => StreakState(
    ownerId: row.ownerId,
    currentStreakDays: row.currentStreakDays,
    longestStreakDays: row.longestStreakDays,
    freezeCount: row.freezeCount,
    lastLearnedAtUtcMs: row.lastLearnedAtUtcMs,
    updatedAtUtcMs: row.updatedAtUtcMs,
  );
}
