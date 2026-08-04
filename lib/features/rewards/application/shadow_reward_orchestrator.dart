/// Shadow Reward Orchestrator — runs the V2 reward pipeline in parallel with
/// production V1, logging decisions without ever committing them.
///
/// Shadow mode is a safety harness: it MUST NOT affect production in any way.
/// All errors are swallowed and logged; the calling code (e.g.
/// [LearningUseCases]) must call [processShadow] inside a try/catch and never
/// let a shadow exception propagate.
///
/// Enable via [Feature.shadowRewardV2] in [FeatureRegistry].
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../events/domain/event_envelope_v2.dart';
import '../domain/reward_eligibility.dart';
import '../domain/reward_grant_request.dart';

// ─── Logger interface ─────────────────────────────────────────────────────────

/// A record written to the shadow log for one event.
final class ShadowLogEntry {
  const ShadowLogEntry({
    required this.timestamp,
    required this.eventId,
    required this.eventType,
    required this.ownerId,
    required this.decision,
    required this.request,
    required this.wouldSucceed,
    this.error,
  });

  final DateTime timestamp;
  final String eventId;
  final String eventType;
  final String ownerId;
  final RewardEligibilityDecision decision;
  final RewardGrantRequest? request;
  final bool wouldSucceed;
  final String? error;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'eventId': eventId,
    'eventType': eventType,
    'ownerId': ownerId,
    'decision': decision.toJson(),
    if (request != null) 'request': request!.toJson(),
    'wouldSucceed': wouldSucceed,
    if (error != null) 'error': error,
  };
}

/// Interface for recording shadow mode results.
///
/// Inject [InMemoryShadowLogger] in tests; inject a file- or analytics-backed
/// logger in production.
abstract interface class ShadowLogger {
  void logEntry(ShadowLogEntry entry);
  void logError(String eventId, Object error, StackTrace stack);
  List<ShadowLogEntry> get entries;
}

/// In-memory logger for tests — accumulates all entries for assertion.
final class InMemoryShadowLogger implements ShadowLogger {
  final List<ShadowLogEntry> _entries = [];
  final List<({String eventId, Object error})> errors = [];

  @override
  void logEntry(ShadowLogEntry entry) => _entries.add(entry);

  @override
  void logError(String eventId, Object error, StackTrace stack) {
    errors.add((eventId: eventId, error: error));
    debugPrint('[ShadowMode] error on $eventId: $error');
  }

  @override
  List<ShadowLogEntry> get entries => List.unmodifiable(_entries);
}

/// Debug-print logger for development builds — writes JSON lines to the
/// Flutter debug console.
final class DebugConsoleShadowLogger implements ShadowLogger {
  final List<ShadowLogEntry> _entries = [];

  @override
  void logEntry(ShadowLogEntry entry) {
    _entries.add(entry);
    debugPrint('[ShadowMode] ${jsonEncode(entry.toJson())}');
  }

  @override
  void logError(String eventId, Object error, StackTrace stack) {
    debugPrint('[ShadowMode] ERROR $eventId: $error\n$stack');
  }

  @override
  List<ShadowLogEntry> get entries => List.unmodifiable(_entries);
}

// ─── Canary check ─────────────────────────────────────────────────────────────

/// Checks whether a grant with the given [idempotencyKey] has already been
/// committed to production.
///
/// Injected as a function to keep the orchestrator independent of the reward
/// repository type.
typedef CanGrantCheck =
    Future<bool> Function(String ownerId, String idempotencyKey);

// ─── Orchestrator ─────────────────────────────────────────────────────────────

/// Runs the full V2 reward eligibility pipeline in shadow (dry-run) mode.
///
/// Call from [LearningUseCases.recordAnswer] **after** the production V1 path
/// has already succeeded.  Never let a shadow exception propagate to the
/// caller.
///
/// ```dart
/// // In LearningUseCases.recordAnswer:
/// try {
///   final v2 = eventAdapter!.adapt(v1Command);
///   await shadowOrchestrator!.processShadow(v2);
/// } catch (_) {} // shadow mode must never break production
/// ```
final class ShadowRewardOrchestrator {
  ShadowRewardOrchestrator({
    required this.logger,
    required this.canGrant,
    required this.generateId,
    required this.nowUtc,
  });

  final ShadowLogger logger;

  /// Async check: returns `true` if a grant with this key has NOT yet been
  /// committed — i.e. the grant WOULD succeed.
  final CanGrantCheck canGrant;

  final String Function() generateId;
  final DateTime Function() nowUtc;

  /// Evaluates [event] through the V2 reward pipeline without writing
  /// anything to the production database.
  Future<void> processShadow(EventEnvelopeV2 event) async {
    try {
      // 1. Eligibility decision (pure, no I/O)
      final decision = RewardEligibilityDecision.evaluate(event);

      if (decision.result != EligibilityResult.eligible) {
        logger.logEntry(
          ShadowLogEntry(
            timestamp: nowUtc(),
            eventId: event.eventId,
            eventType: event.eventType,
            ownerId: event.ownerIdentity,
            decision: decision,
            request: null,
            wouldSucceed: false,
          ),
        );
        return;
      }

      // 2. Build grant request
      final request = RewardGrantRequest.fromDecision(
        decision,
        event,
        requestedAtUtc: nowUtc(),
        requestId: generateId(),
      );

      // 3. Idempotency check — would this grant succeed?
      final wouldSucceed = await canGrant(
        event.ownerIdentity,
        event.idempotencyKey,
      );

      // 4. Log the decision (never write to reward_transactions)
      logger.logEntry(
        ShadowLogEntry(
          timestamp: nowUtc(),
          eventId: event.eventId,
          eventType: event.eventType,
          ownerId: event.ownerIdentity,
          decision: decision,
          request: request,
          wouldSucceed: wouldSucceed,
        ),
      );
    } catch (e, stack) {
      logger.logError(event.eventId, e, stack);
    }
  }
}
