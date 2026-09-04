import 'dart:collection';
import 'dart:convert';

import '../domain/adventure_session_plan.dart';

enum AdventureRecoveryState { accepted, active, completed, closed }

final class AdventureRecoverySession {
  const AdventureRecoverySession({
    required this.sessionId,
    required this.ownerId,
    required this.planId,
    required this.state,
  });

  final String sessionId;
  final String ownerId;
  final String planId;
  final AdventureRecoveryState state;

  AdventureRecoverySession withState(AdventureRecoveryState value) =>
      AdventureRecoverySession(
        sessionId: sessionId,
        ownerId: ownerId,
        planId: planId,
        state: value,
      );
}

final class AdventureExactRetry {
  factory AdventureExactRetry({
    required String evidenceId,
    required String sessionId,
    required String ownerId,
    required String payloadFingerprint,
    required Map<String, Object?> payload,
  }) {
    if (!_canonical(evidenceId) ||
        !_canonical(sessionId) ||
        !_canonical(ownerId) ||
        !_canonical(payloadFingerprint)) {
      throw ArgumentError('Retry identity is not canonical.');
    }
    final frozen = _freezeMap(payload);
    return AdventureExactRetry._(
      evidenceId: evidenceId,
      sessionId: sessionId,
      ownerId: ownerId,
      payloadFingerprint: payloadFingerprint,
      payload: frozen,
      canonicalPayload: _canonicalJson(frozen),
    );
  }

  const AdventureExactRetry._({
    required this.evidenceId,
    required this.sessionId,
    required this.ownerId,
    required this.payloadFingerprint,
    required this.payload,
    required this.canonicalPayload,
  });

  final String evidenceId;
  final String sessionId;
  final String ownerId;
  final String payloadFingerprint;
  final Map<String, Object?> payload;
  final String canonicalPayload;
}

abstract interface class AdventureRecoveryGateway {
  Future<void> start(AdventureRecoverySession session);
  Future<void> resume(AdventureRecoverySession session);
  Future<void> record(AdventureExactRetry retry);
  Future<void> close(AdventureRecoverySession session);
}

typedef AdventureCanStart = bool Function();

final class AdventureRecoveryUseCases {
  AdventureRecoveryUseCases({
    required this.gateway,
    required this.canStartNewMission,
  });

  final AdventureRecoveryGateway gateway;
  final AdventureCanStart canStartNewMission;
  AdventureRecoverySession? _session;
  final Map<String, AdventureExactRetry> _pending =
      <String, AdventureExactRetry>{};

  AdventureRecoverySession? get acceptedSession => _session;
  Iterable<AdventureExactRetry> get pendingRetries =>
      List<AdventureExactRetry>.unmodifiable(_pending.values);

  Future<AdventureRecoverySession> startOrResume({
    required AdventureSessionPlanV1 plan,
    required String activeOwnerId,
    required String sessionId,
  }) async {
    final existing = _session;
    if (existing != null && existing.state != AdventureRecoveryState.closed) {
      if (existing.ownerId != activeOwnerId) {
        throw StateError(
          'Accepted Adventure session belongs to another owner.',
        );
      }
      await gateway.resume(existing);
      _session = existing.withState(AdventureRecoveryState.active);
      return _session!;
    }
    if (!canStartNewMission()) {
      throw StateError('Adventure is off for new missions.');
    }
    if (plan.ownerId != activeOwnerId ||
        plan.configuration.ownerId != activeOwnerId) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.ownerMismatch,
      );
    }
    final accepted = AdventureRecoverySession(
      sessionId: sessionId,
      ownerId: activeOwnerId,
      planId: plan.planId,
      state: AdventureRecoveryState.accepted,
    );
    await gateway.start(accepted);
    _session = accepted.withState(AdventureRecoveryState.active);
    return _session!;
  }

  Future<void> record(AdventureExactRetry retry) async {
    final session = _session;
    if (session == null ||
        session.sessionId != retry.sessionId ||
        session.ownerId != retry.ownerId ||
        session.state == AdventureRecoveryState.closed) {
      throw StateError('Retry does not belong to the accepted session.');
    }
    final existing = _pending[retry.evidenceId];
    if (existing != null &&
        (existing.payloadFingerprint != retry.payloadFingerprint ||
            existing.canonicalPayload != retry.canonicalPayload)) {
      throw StateError('Evidence identity was reused with another payload.');
    }
    final exact = existing ?? retry;
    _pending[retry.evidenceId] = exact;
    await gateway.record(exact);
    _pending.remove(retry.evidenceId);
  }

  Future<void> retry(String evidenceId) async {
    final exact = _pending[evidenceId];
    if (exact == null) return;
    await gateway.record(exact);
    _pending.remove(evidenceId);
  }

  Future<void> close() async {
    final session = _session;
    if (session == null || session.state == AdventureRecoveryState.closed) {
      return;
    }
    await gateway.close(session);
    _session = session.withState(AdventureRecoveryState.closed);
    _pending.clear();
  }
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) {
  final frozen = <String, Object?>{};
  for (final entry in source.entries) {
    if (!_canonical(entry.key)) {
      throw ArgumentError.value(entry.key, 'payload', 'has a noncanonical key');
    }
    frozen[entry.key] = _freezeValue(entry.value);
  }
  return UnmodifiableMapView<String, Object?>(frozen);
}

Object? _freezeValue(Object? value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is Map<String, Object?>) return _freezeMap(value);
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeValue));
  }
  throw ArgumentError.value(value, 'payload', 'must be JSON data');
}

String _canonicalJson(Object? value) => jsonEncode(_sortedJson(value));

Object? _sortedJson(Object? value) {
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final key in (value.keys.toList()..sort()))
        key: _sortedJson(value[key]),
    };
  }
  if (value is List<Object?>) {
    return value.map(_sortedJson).toList(growable: false);
  }
  return value;
}

bool _canonical(String value) =>
    value.isNotEmpty && value == value.trim() && value.runes.length <= 256;
