import 'dart:collection';
import 'dart:math' as math;

/// Pure fold and settlement decisions for a learner's dated Streak evidence.
abstract final class StreakPolicy {
  static const int version = 1;

  static StreakFoldResult fold(StreakFoldInput input) =>
      _fold(input, postForward: false).result;

  static StreakSettlement evaluateForward(StreakFoldInput input) =>
      _fold(input, postForward: true);

  static StreakSettlement _fold(
    StreakFoldInput input, {
    required bool postForward,
  }) {
    if (!_civil(input.today) || input.ownerId.isEmpty || input.asOfUtcMs < 0) {
      throw ArgumentError(
        'Streak fold requires an owner, UTC instant and civil day',
      );
    }
    final wallet = _StreakWallet(input);
    final opening = wallet.continuity;
    final prior = input.settled;
    final settled = prior != null && prior.updatedAtUtcMs <= input.asOfUtcMs
        ? prior
        : null;
    if (settled != null && settled.ownerId != input.ownerId) {
      throw ArgumentError('Settled streak belongs to another owner');
    }
    final origin = opening?.originOwnerId ?? input.ownerId;
    final cutoff = opening?.cutoffUtcMs ?? -1;
    final learned = <DateTime>{};
    final ownDays = SplayTreeMap<DateTime, StreakDayFact>();
    final identities =
        <String, (String?, String?, int, DateTime, bool, bool?)>{};
    final legacyAllowed =
        !wallet.incoming &&
        input.transferAtUtcMs.isEmpty &&
        !input.openings.any((o) => o.originOwnerId != origin) &&
        !input.movements.any((m) => m.originOwnerId != origin) &&
        !input.facts.any(
          (f) => f.originOwnerId != null && f.originOwnerId != origin,
        );
    final bound = settled?.lastLearnedAtUtcMs;
    var boundDay = opening?.lastDay;
    String? openingRule;
    var boundVerified =
        bound == null ||
        (bound == opening?.raw.lastLearnedAtUtcMs && boundDay != null);
    var unavailable = input.unresolvedEvidence || wallet.invalid;
    var uncertain =
        wallet.incoming ||
        (opening?.raw.lastLearnedAtUtcMs != null && opening?.lastDay == null);
    var lastUtc = opening?.raw.lastLearnedAtUtcMs;
    for (final fact in input.facts) {
      if (fact.occurredAtUtcMs > input.asOfUtcMs) continue;
      final identity = (
        fact.originOwnerId,
        fact.calendarRuleId,
        fact.occurredAtUtcMs,
        fact.day,
        fact.legacyUtcAttendance,
        fact.precedingCivilDayExists,
      );
      if (identities.putIfAbsent(fact.id, () => identity) != identity ||
          fact.id.isEmpty ||
          fact.occurredAtUtcMs < 0 ||
          !_civil(fact.day)) {
        unavailable = true;
        continue;
      }
      if (fact.legacyUtcAttendance) {
        final utc = DateTime.fromMillisecondsSinceEpoch(
          fact.occurredAtUtcMs,
          isUtc: true,
        );
        if (fact.originOwnerId != null ||
            fact.calendarRuleId != null ||
            fact.day != DateTime.utc(utc.year, utc.month, utc.day)) {
          unavailable = true;
          continue;
        }
        uncertain = true;
      }
      learned.add(fact.day);
      if (!(fact.legacyUtcAttendance && legacyAllowed) &&
          (fact.originOwnerId != origin || fact.calendarRuleId == null)) {
        uncertain = true;
        continue;
      }
      if (fact.occurredAtUtcMs <= cutoff) {
        if (fact.occurredAtUtcMs == opening?.raw.lastLearnedAtUtcMs &&
            fact.day == opening?.lastDay) {
          openingRule = fact.calendarRuleId;
        }
        continue;
      }
      if (bound != null && fact.occurredAtUtcMs <= bound) {
        if (boundDay == null || fact.day.isAfter(boundDay)) {
          boundDay = fact.day;
        }
        if (fact.occurredAtUtcMs == bound) {
          boundVerified = true;
        }
      }
      if (lastUtc == null || fact.occurredAtUtcMs > lastUtc) {
        lastUtc = fact.occurredAtUtcMs;
      }
      final first = ownDays[fact.day];
      if (first == null ||
          fact.occurredAtUtcMs < first.occurredAtUtcMs ||
          (fact.occurredAtUtcMs == first.occurredAtUtcMs &&
              fact.id.compareTo(first.id) < 0)) {
        ownDays[fact.day] = fact;
      }
    }
    if (!boundVerified) {
      unavailable = true;
      uncertain = true;
    }
    final missingBridge =
        opening?.raw.lastLearnedAtUtcMs != null && opening?.lastDay == null;
    if (missingBridge && ownDays.isNotEmpty) unavailable = true;
    var current = opening?.raw.currentStreakDays ?? 0;
    var longest = math.max(wallet.longest, settled?.longestStreakDays ?? 0);
    DateTime? lastDay = opening?.lastDay;
    String? lastRule = openingRule;
    final debits = <StreakMovement>[];
    var wouldSpend = false;
    for (final first in ownDays.values) {
      final day = first.day;
      final gap = lastDay == null ? null : day.difference(lastDay).inDays;
      if (gap != null && gap <= 0) continue;
      if (gap == 1) {
        current++;
      } else if (gap == 2 &&
          first.calendarRuleId != null &&
          lastRule == first.calendarRuleId &&
          first.precedingCivilDayExists == false) {
        current++;
      } else if (gap == 2) {
        final missed = day.subtract(const Duration(days: 1));
        var protected = wallet.protections.contains((origin, missed));
        if (!protected &&
            first.calendarRuleId != null &&
            lastRule == first.calendarRuleId &&
            first.precedingCivilDayExists == null) {
          unavailable = true;
        }
        final forward =
            (bound == null || first.occurredAtUtcMs > bound) &&
            (boundDay == null || day.isAfter(boundDay));
        if (!protected &&
            forward &&
            wallet.unknownTransfer &&
            wallet.balance > 0) {
          unavailable = true;
        }
        if (!protected &&
            forward &&
            !unavailable &&
            first.calendarRuleId != null &&
            lastRule == first.calendarRuleId &&
            first.precedingCivilDayExists == true &&
            wallet.canSpend(first.occurredAtUtcMs)) {
          final commandId =
              'autoProtect:${missed.toIso8601String().substring(0, 10)}';
          if (wallet.commands.containsKey((origin, commandId))) {
            unavailable = true;
          } else {
            wouldSpend = true;
            if (postForward) {
              final debit = StreakMovement(
                originOwnerId: origin,
                commandId: commandId,
                kind: StreakMovementKind.autoProtect,
                delta: -1,
                occurredAtUtcMs: first.occurredAtUtcMs,
                protectedDay: missed,
              );
              wallet.post(debit);
              debits.add(debit);
              protected = true;
            }
          }
        }
        if (!protected) current = 1;
      } else {
        current = 1;
      }
      lastDay = day;
      lastRule = first.calendarRuleId;
      longest = math.max(longest, current);
    }
    if (unavailable && debits.isNotEmpty) {
      final unposted = _fold(input, postForward: false).result;
      return StreakSettlement(
        autoDebits: const [],
        result: StreakFoldResult(
          state: unposted.state,
          currentStreakDays: unposted.currentStreakDays,
          days: unposted.days,
          status: StreakFoldStatus.unavailable,
          uncertainHistory: unposted.uncertainHistory,
        ),
      );
    }
    final headline =
        lastDay != null && input.today.difference(lastDay).inDays <= 1
        ? current
        : 0;
    final monday = input.today.subtract(
      Duration(days: input.today.weekday - DateTime.monday),
    );
    final protectedDays = wallet.protections.map((p) => p.$2).toSet();
    final balance = wallet.balance;
    final changed = settled == null
        ? (lastUtc != null || current != 0 || longest != 0 || balance != 0)
        : (current != settled.currentStreakDays ||
              longest != settled.longestStreakDays ||
              balance != settled.freezeCount ||
              lastUtc != settled.lastLearnedAtUtcMs);
    return StreakSettlement(
      autoDebits: unavailable ? const [] : debits,
      result: StreakFoldResult(
        state: StreakState(
          ownerId: input.ownerId,
          currentStreakDays: current,
          longestStreakDays: longest,
          freezeCount: balance,
          lastLearnedAtUtcMs: lastUtc,
          updatedAtUtcMs: !changed && settled != null
              ? settled.updatedAtUtcMs
              : input.asOfUtcMs,
        ),
        currentStreakDays: headline,
        uncertainHistory: uncertain,
        status: unavailable
            ? StreakFoldStatus.unavailable
            : !postForward && (changed || wouldSpend)
            ? StreakFoldStatus.pending
            : StreakFoldStatus.ready,
        days: [
          for (var i = 0; i < 7; i++)
            _marker(monday.add(Duration(days: i)), learned, protectedDays),
        ],
      ),
    );
  }
}

bool _civil(DateTime day) =>
    day.isUtc && day == DateTime.utc(day.year, day.month, day.day);

StreakDayMarker _marker(
  DateTime day,
  Set<DateTime> studied,
  Set<DateTime> protected,
) => StreakDayMarker(
  day: day,
  studied: studied.contains(day),
  protected: protected.contains(day),
);

// A merged origin's net assets enter the target's chronology at transfer.
// All its original ledger rows remain independently identifiable.
final class _StreakWallet {
  _StreakWallet(StreakFoldInput input) {
    final cutoffs = <String, int>{};
    final native = <String, SplayTreeMap<int, int>>{};
    for (final opening in input.openings) {
      if (opening.cutoffUtcMs > input.asOfUtcMs) continue;
      final origin = opening.originOwnerId;
      if (cutoffs.containsKey(origin)) {
        invalid = true;
        continue;
      }
      cutoffs[origin] = opening.cutoffUtcMs;
      final raw = opening.raw;
      if (raw.ownerId != input.ownerId ||
          raw.freezeCount < 0 ||
          raw.currentStreakDays < 0 ||
          raw.longestStreakDays < raw.currentStreakDays ||
          (opening.lastDay != null && !_civil(opening.lastDay!))) {
        invalid = true;
      }
      if (opening.controlsContinuity) {
        if (continuity != null || origin != input.ownerId) invalid = true;
        continuity = opening;
      }
      incoming = incoming || origin != input.ownerId;
      longest = math.max(longest, raw.longestStreakDays);
      _credit(
        native.putIfAbsent(origin, SplayTreeMap<int, int>.new),
        opening.cutoffUtcMs,
        raw.freezeCount,
      );
    }
    for (final movement in input.movements) {
      if (movement.occurredAtUtcMs > input.asOfUtcMs) continue;
      final origin = movement.originOwnerId;
      final key = (origin, movement.commandId);
      final existing = commands[key];
      if (existing != null) {
        if (existing.kind != movement.kind ||
            existing.occurredAtUtcMs != movement.occurredAtUtcMs ||
            existing.delta != movement.delta ||
            existing.protectedDay != movement.protectedDay) {
          invalid = true;
        }
        continue;
      }
      commands[key] = movement;
      final day = movement.protectedDay;
      final validShape = switch (movement.kind) {
        StreakMovementKind.grant => movement.delta > 0 && day == null,
        StreakMovementKind.manualDebit => movement.delta == -1 && day == null,
        StreakMovementKind.autoProtect =>
          movement.delta == -1 && day != null && _civil(day),
      };
      if (!validShape ||
          origin.isEmpty ||
          movement.commandId.isEmpty ||
          movement.occurredAtUtcMs < (cutoffs[origin] ?? 0)) {
        invalid = true;
      }
      if (day != null &&
          movement.kind == StreakMovementKind.autoProtect &&
          !protections.add((origin, day))) {
        invalid = true;
      }
      incoming = incoming || origin != input.ownerId;
      _credit(
        native.putIfAbsent(origin, SplayTreeMap<int, int>.new),
        movement.occurredAtUtcMs,
        movement.delta,
      );
    }
    for (final entry in native.entries) {
      final origin = entry.key;
      final takeAt = origin == input.ownerId
          ? null
          : input.transferAtUtcMs[origin];
      var originalBalance = 0;
      for (final event in entry.value.entries) {
        originalBalance += event.value;
        if (origin != input.ownerId &&
            (takeAt == null || event.key <= takeAt) &&
            originalBalance < 0) {
          invalid = true;
        }
        // With incomplete transfer provenance, preserve the aggregate but do not
        // award a dated spend from an unknowable historical balance.
        if (origin != input.ownerId && takeAt == null) {
          unknownTransfer = true;
          _credit(timeline, input.asOfUtcMs, event.value);
        } else {
          final posting = takeAt == null
              ? event.key
              : math.max(takeAt, event.key);
          if (posting <= input.asOfUtcMs) {
            _credit(timeline, posting, event.value);
          }
        }
      }
    }
    var running = 0;
    for (final delta in timeline.values) {
      running += delta;
      if (running < 0) invalid = true;
    }
    balance = running;
  }

  final timeline = SplayTreeMap<int, int>();
  final commands = <(String, String), StreakMovement>{};
  final protections = <(String, DateTime)>{};
  StreakOpening? continuity;
  int balance = 0, longest = 0;
  bool invalid = false, incoming = false, unknownTransfer = false;

  static void _credit(SplayTreeMap<int, int> timeline, int time, int delta) {
    timeline[time] = (timeline[time] ?? 0) + delta;
  }

  bool canSpend(int time) {
    if (invalid || unknownTransfer || balance <= 0) return false;
    var running = 0;
    for (final entry in timeline.entries) {
      if (entry.key > time && running < 1) return false;
      running += entry.value;
    }
    return running >= 1;
  }

  void post(StreakMovement debit) {
    commands[(debit.originOwnerId, debit.commandId)] = debit;
    protections.add((debit.originOwnerId, debit.protectedDay!));
    _credit(timeline, debit.occurredAtUtcMs, debit.delta);
    balance += debit.delta;
  }
}

/// Day labels throughout the fold are UTC-midnight civil ordinals.
final class StreakDayFact {
  const StreakDayFact({
    required this.id,
    required this.occurredAtUtcMs,
    required this.day,
    this.originOwnerId,
    this.calendarRuleId,
    this.legacyUtcAttendance = false,
    this.precedingCivilDayExists,
  });
  final String id;
  final int occurredAtUtcMs;
  final DateTime day;
  final String? originOwnerId, calendarRuleId;
  final bool legacyUtcAttendance;
  final bool? precedingCivilDayExists;
}

final class StreakOpening {
  const StreakOpening({
    required this.raw,
    required this.originOwnerId,
    required this.cutoffUtcMs,
    required this.controlsContinuity,
    this.lastDay,
  });
  final StreakState raw;
  final String originOwnerId;
  final int cutoffUtcMs;
  final bool controlsContinuity;
  final DateTime? lastDay;
}

enum StreakMovementKind { grant, manualDebit, autoProtect }

final class StreakMovement {
  const StreakMovement({
    required this.originOwnerId,
    required this.commandId,
    required this.kind,
    required this.delta,
    required this.occurredAtUtcMs,
    this.protectedDay,
  });
  final String originOwnerId, commandId;
  final StreakMovementKind kind;
  final int delta, occurredAtUtcMs;
  final DateTime? protectedDay;
}

final class StreakFoldInput {
  StreakFoldInput({
    required this.ownerId,
    required this.asOfUtcMs,
    required this.today,
    required List<StreakDayFact> facts,
    List<StreakOpening> openings = const [],
    List<StreakMovement> movements = const [],
    this.settled,
    Map<String, int> transferAtUtcMs = const {},
    this.unresolvedEvidence = false,
  }) : facts = List.unmodifiable(facts),
       openings = List.unmodifiable(openings),
       movements = List.unmodifiable(movements),
       transferAtUtcMs = Map.unmodifiable(transferAtUtcMs);
  final String ownerId;
  final int asOfUtcMs;
  final DateTime today;
  final List<StreakDayFact> facts;
  final List<StreakOpening> openings;
  final List<StreakMovement> movements;
  final StreakState? settled;
  final Map<String, int> transferAtUtcMs;
  final bool unresolvedEvidence;
}

enum StreakFoldStatus { ready, pending, unavailable }

final class StreakDayMarker {
  const StreakDayMarker({
    required this.day,
    required this.studied,
    required this.protected,
  });
  final DateTime day;
  final bool studied, protected;
}

final class StreakFoldResult {
  StreakFoldResult({
    required this.state,
    required this.currentStreakDays,
    required List<StreakDayMarker> days,
    required this.status,
    required this.uncertainHistory,
  }) : days = List.unmodifiable(days);
  final StreakState state;

  /// Headline at the supplied home civil day; the state retains last-event continuity.
  final int currentStreakDays;
  final List<StreakDayMarker> days;
  final StreakFoldStatus status;
  final bool uncertainHistory;
}

final class StreakSettlement {
  StreakSettlement({
    required List<StreakMovement> autoDebits,
    required this.result,
  }) : autoDebits = List.unmodifiable(autoDebits);
  final List<StreakMovement> autoDebits;
  final StreakFoldResult result;
}

// ─── Value objects ────────────────────────────────────────────────────────────

/// Current persisted streak counters for one owner.
final class StreakState {
  const StreakState({
    required this.ownerId,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.freezeCount,
    required this.lastLearnedAtUtcMs,
    required this.updatedAtUtcMs,
  });

  const StreakState.initial({required String ownerId, required int nowMs})
    : this(
        ownerId: ownerId,
        currentStreakDays: 0,
        longestStreakDays: 0,
        freezeCount: 0,
        lastLearnedAtUtcMs: null,
        updatedAtUtcMs: nowMs,
      );

  final String ownerId;
  final int currentStreakDays;
  final int longestStreakDays;
  final int freezeCount;

  /// `null` before the learner's first session.
  final int? lastLearnedAtUtcMs;
  final int updatedAtUtcMs;

  StreakState copyWith({
    int? currentStreakDays,
    int? longestStreakDays,
    int? freezeCount,
    int? lastLearnedAtUtcMs,
    int? updatedAtUtcMs,
  }) => StreakState(
    ownerId: ownerId,
    currentStreakDays: currentStreakDays ?? this.currentStreakDays,
    longestStreakDays: longestStreakDays ?? this.longestStreakDays,
    freezeCount: freezeCount ?? this.freezeCount,
    lastLearnedAtUtcMs: lastLearnedAtUtcMs ?? this.lastLearnedAtUtcMs,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
}
