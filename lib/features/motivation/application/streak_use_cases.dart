import '../../events/domain/event_envelope_v2.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/evidence_eligibility_policy.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../data/drift_streak_repository.dart';
import '../domain/streak_policy.dart';

typedef StreakUtcNow = DateTime Function();

enum StreakProjectionDisposition { applied, notApplicable, blocked }

/// Result returned to the durable learning projection reconciler.
final class StreakProjectionEvaluation {
  const StreakProjectionEvaluation._({
    required this.disposition,
    required this.payload,
    required this.reasonCode,
  });

  factory StreakProjectionEvaluation.applied(StreakPolicyReceipt receipt) =>
      StreakProjectionEvaluation._(
        disposition: StreakProjectionDisposition.applied,
        payload: Map<String, dynamic>.unmodifiable(receipt.toJson()),
        reasonCode: null,
      );

  const StreakProjectionEvaluation.notApplicable(String reasonCode)
    : this._(
        disposition: StreakProjectionDisposition.notApplicable,
        payload: const <String, dynamic>{},
        reasonCode: reasonCode,
      );

  const StreakProjectionEvaluation.blocked(String reasonCode)
    : this._(
        disposition: StreakProjectionDisposition.blocked,
        payload: const <String, dynamic>{},
        reasonCode: reasonCode,
      );

  final StreakProjectionDisposition disposition;
  final Map<String, dynamic> payload;
  final String? reasonCode;

  bool get eligible => disposition == StreakProjectionDisposition.applied;
}

/// Application façade for streak tracking.
///
/// **Responsibilities:**
/// - On each learning session: evaluate the streak impact via [StreakPolicy]
///   and persist both the [StreakState] and a [LearningDayLog] entry.
/// - On demand: return the current [StreakState].
/// - On request: consume a freeze token to protect an at-risk streak.
///
/// All methods are idempotent when called multiple times for the same
/// learning day.
final class StreakUseCases {
  StreakUseCases({
    required this.repository,
    required this.owners,
    required this.nowUtc,
    required this.timezoneId,
  });

  final DriftStreakRepository repository;
  final LocalOwnerRepository owners;
  final StreakUtcNow nowUtc;

  /// IANA timezone identifier, e.g. `'Asia/Bangkok'`.
  final String timezoneId;

  // ISO date formatter: 'YYYY-MM-DD'
  static String _formatDay(DateTime utcMidnight) {
    final y = utcMidnight.year.toString().padLeft(4, '0');
    final m = utcMidnight.month.toString().padLeft(2, '0');
    final d = utcMidnight.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Record that the current owner completed a learning session and return
  /// the resulting [StreakUpdate].
  ///
  /// Safe to call multiple times for the same day — [StreakOutcome.sameDay]
  /// is returned for subsequent calls with no DB writes beyond the first.
  Future<StreakUpdate> recordLearningDay({DateTime? occurredAtUtc}) async {
    final owner = await owners.getOrCreateActiveOwner();
    return recordLearningDayForOwner(
      ownerId: owner.id,
      occurredAtUtc: occurredAtUtc,
    );
  }

  /// Applies a durable event to the owner captured by that event.
  Future<StreakUpdate> recordLearningDayForOwner({
    required String ownerId,
    DateTime? occurredAtUtc,
  }) async {
    final now = _now(occurredAtUtc);
    final nowMs = now.millisecondsSinceEpoch;

    final current = await repository.getOrCreate(ownerId, nowMs);
    var update = StreakPolicy.evaluate(
      current: current,
      nowUtc: now,
      timezoneId: timezoneId,
    );

    if (update.changed) {
      final updated = update.after.copyWith(updatedAtUtcMs: nowMs);
      await repository.save(updated);
    }

    // Record the local day idempotently. An exact replay after a timezone
    // change keeps the already-recorded day instead of inventing a second one.
    final dayLabel = _formatDay(update.learningDay);
    final isExactReplay = current.lastLearnedAtUtcMs == nowMs;
    final durableDays = isExactReplay
        ? await repository.getLearningDays(ownerId)
        : const <String>[];
    final hasDurableDay = durableDays.isNotEmpty;
    if (hasDurableDay) {
      update = update.pinLearningDay(durableDays.first);
    }
    if (!hasDurableDay) {
      await repository.recordLearningDay(
        ownerId: ownerId,
        learningDay: dayLabel,
        firstSessionAtUtcMs: nowMs,
      );
    }

    return update;
  }

  /// Applies one canonical, eligible Foundation learning event.
  ///
  /// The durable reconciler still owns the v2 projection receipt. This guard
  /// independently rejects malformed events and shadow-policy divergence
  /// before the Streak authority is asked to mutate.
  Future<StreakProjectionEvaluation> projectEvent(EventEnvelopeV2 event) async {
    final evidence = _validatedEvidence(event);
    final decision = EvidenceProjectionDecision.resolve(
      context: evidence,
      projection: LearningProjection.streak,
    );
    if (decision.isDivergent) {
      return const StreakProjectionEvaluation.notApplicable('shadowDivergence');
    }
    if (!decision.isEligible) {
      return const StreakProjectionEvaluation.notApplicable(
        'evidenceIneligible',
      );
    }
    _now(event.occurredAtUtc);
    final application = await repository.applyProjection(
      source: event,
      timezoneId: timezoneId,
    );
    final reasonCode = application.reasonCode;
    if (reasonCode != null) {
      return StreakProjectionEvaluation.blocked(reasonCode);
    }
    return StreakProjectionEvaluation.applied(application.receipt!);
  }

  /// Return the current [StreakState] for the active owner.
  Future<StreakState> getCurrentStreak() async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = _now();
    return repository.getOrCreate(owner.id, now.millisecondsSinceEpoch);
  }

  /// Returns a calm read-only state for the f42-owned card.
  Future<GentleStreakSnapshot> getGentleStreak() async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = _now();
    final current = await repository.getOrCreate(
      owner.id,
      now.millisecondsSinceEpoch,
    );
    return StreakPolicy.snapshot(
      current: current,
      nowUtc: now,
      timezoneId: timezoneId,
    );
  }

  /// Consume one freeze token to protect the current streak.
  ///
  /// Returns `true` if a token was consumed, `false` if none were available.
  Future<bool> useFreezeToken() async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = _now();
    final current = await repository.getOrCreate(
      owner.id,
      now.millisecondsSinceEpoch,
    );
    if (current.freezeCount <= 0) return false;
    final updated = current.copyWith(
      freezeCount: current.freezeCount - 1,
      updatedAtUtcMs: now.millisecondsSinceEpoch,
    );
    await repository.save(updated);
    return true;
  }

  /// Applies a bounded inventory adjustment already authorized upstream.
  ///
  /// This method neither awards nor spends XP, coins, or purchase value.
  Future<StreakState> grantFreezeTokens(int count) async {
    if (count < 1 || count > StreakPolicy.maxFreezeInventory) {
      throw RangeError.range(
        count,
        1,
        StreakPolicy.maxFreezeInventory,
        'count',
      );
    }
    final owner = await owners.getOrCreateActiveOwner();
    final now = _now();
    final current = await repository.getOrCreate(
      owner.id,
      now.millisecondsSinceEpoch,
    );
    final nextCount = current.freezeCount + count;
    if (nextCount > StreakPolicy.maxFreezeInventory) {
      throw RangeError.range(
        nextCount,
        0,
        StreakPolicy.maxFreezeInventory,
        'freezeCount',
      );
    }
    final updated = current.copyWith(
      freezeCount: nextCount,
      updatedAtUtcMs: now.millisecondsSinceEpoch,
    );
    await repository.save(updated);
    return updated;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  DateTime _now([DateTime? value]) {
    final clock = nowUtc();
    if (!clock.isUtc) {
      throw ArgumentError.value(clock, 'nowUtc', 'must be UTC');
    }
    final resolved = value ?? clock;
    if (!resolved.isUtc) {
      throw ArgumentError.value(resolved, 'nowUtc', 'must be UTC');
    }
    if (value != null && resolved.isAfter(clock)) {
      throw ArgumentError.value(
        resolved,
        'occurredAtUtc',
        'must not be in the future',
      );
    }
    return resolved;
  }

  EvidenceContext _validatedEvidence(EventEnvelopeV2 event) {
    final payload = event.payload;
    final attemptId = payload['attemptId'];
    final rawEvidence = payload['evidenceContext'];
    if (event.eventVersion != 2 ||
        (event.eventType != 'QuizCompleted' &&
            event.eventType != 'QuizAttempted') ||
        event.aggregateType != 'LearningSession' ||
        event.ownerIdentity.trim() != event.ownerIdentity ||
        event.ownerIdentity.isEmpty ||
        event.aggregateId.trim() != event.aggregateId ||
        event.aggregateId.isEmpty ||
        event.occurredAtUtc != event.recordedAtUtc ||
        !LearningEvidenceContract.isCanonicalEventUtcSecond(
          event.occurredAtUtc,
        ) ||
        !LearningEvidenceContract.isCanonicalEventUtcSecond(
          event.recordedAtUtc,
        ) ||
        attemptId is! String ||
        rawEvidence is! Map) {
      throw StateError('invalid canonical streak projection event');
    }
    late final String expectedEventId;
    late final String expectedIdempotencyKey;
    late final EvidenceContext evidence;
    try {
      expectedEventId = LearningEvidenceContract.learningEventId(attemptId);
      expectedIdempotencyKey =
          LearningEvidenceContract.learningAttemptIdempotencyKey(attemptId);
      evidence = EvidenceContext.fromJson(rawEvidence.cast<String, Object?>());
      evidence.validate();
    } catch (_) {
      throw StateError('invalid canonical streak projection evidence');
    }
    if (event.eventId != expectedEventId ||
        event.idempotencyKey != expectedIdempotencyKey ||
        event.policyVersion != evidence.policyVersion ||
        event.contentRevision != evidence.contentRevision) {
      throw StateError('streak projection evidence identity mismatch');
    }
    return evidence;
  }
}
