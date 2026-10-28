import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../learning_packs/domain/content_manifest.dart';
import '../../offline_content/application/offline_content_manager.dart';
import '../../offline_content/domain/offline_content_state.dart';
import '../domain/adventure_entry.dart';
import '../domain/adventure_session_plan.dart';

/// Closed operational reasons for Adventure diagnostics.
///
/// Values are deliberately payload-free: diagnostics retain only a bounded
/// counter per code and never retain learning, research, story, or identity
/// data.
enum AdventureDiagnosticReasonCode {
  entryLearn,
  entryStandard,
  entryAdventure,
  entryFallbackLearnerChoseStandard,
  entryFallbackFeatureUnavailable,
  entryFallbackDependencyUnavailable,
  entryFallbackCatalogUnavailable,
  entryFallbackContentUnavailable,
  entryFallbackAssignmentUnavailable,
  entryFallbackEmergencyOff,
  compositionOwnerMismatch,
  compositionStaleSource,
  compositionUnresolvedContent,
  compositionIncompatibleConfiguration,
  compositionUnavailableEntry,
  evidenceRetry,
  evidenceRetryExhausted,
  projectionRetry,
  projectionRetryExhausted,
  assetChecksumMismatch,
  assetSizeMismatch,
  assetRevisionMismatch,
  assetMissingArtifact,
  assetUnsupportedContent,
  assetContentInUse,
  assetInterrupted,
  assetInvalidState,
}

final class AdventureDiagnosticSnapshot {
  AdventureDiagnosticSnapshot._(Map<AdventureDiagnosticReasonCode, int> values)
    : _values = UnmodifiableMapView<AdventureDiagnosticReasonCode, int>(
        Map<AdventureDiagnosticReasonCode, int>.of(values),
      );

  static const int schemaVersion = 1;

  factory AdventureDiagnosticSnapshot.decode(Map<String, Object?> source) {
    if (source.length != 2 ||
        !source.containsKey('schemaVersion') ||
        !source.containsKey('counters') ||
        source['schemaVersion'] != schemaVersion) {
      throw const FormatException('Invalid Adventure diagnostic envelope.');
    }
    final encodedCounters = source['counters'];
    if (encodedCounters is! Map) {
      throw const FormatException('Invalid Adventure diagnostic counters.');
    }
    final decoded = <AdventureDiagnosticReasonCode, int>{};
    for (final entry in encodedCounters.entries) {
      if (entry.key is! String || entry.value is! int) {
        throw const FormatException('Invalid Adventure diagnostic counter.');
      }
      AdventureDiagnosticReasonCode? code;
      for (final candidate in AdventureDiagnosticReasonCode.values) {
        if (candidate.name == entry.key) {
          code = candidate;
          break;
        }
      }
      final value = entry.value as int;
      if (code == null ||
          value < 0 ||
          value > AdventureDiagnostics.maximumCountPerCode) {
        throw const FormatException('Invalid Adventure diagnostic counter.');
      }
      if (value > 0) decoded[code] = value;
    }
    return AdventureDiagnosticSnapshot._(decoded);
  }

  final Map<AdventureDiagnosticReasonCode, int> _values;

  Map<AdventureDiagnosticReasonCode, int> get counters => _values;

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': schemaVersion,
    'counters': <String, int>{
      for (final code in AdventureDiagnosticReasonCode.values)
        if ((_values[code] ?? 0) > 0) code.name: _values[code]!,
    },
  };
}

final class AdventureDiagnostics {
  AdventureDiagnostics({this.maxCountPerCode = defaultMaxCountPerCode}) {
    if (maxCountPerCode <= 0 || maxCountPerCode > maximumCountPerCode) {
      throw ArgumentError.value(maxCountPerCode, 'maxCountPerCode');
    }
  }

  static const int defaultMaxCountPerCode = 1000;
  static const int maximumCountPerCode = 1000000;

  final int maxCountPerCode;
  final Map<AdventureDiagnosticReasonCode, int> _counters =
      <AdventureDiagnosticReasonCode, int>{};

  void record(AdventureDiagnosticReasonCode code) {
    final current = _counters[code] ?? 0;
    if (current < maxCountPerCode) _counters[code] = current + 1;
  }

  void recordEntry(AdventureEntryDestination destination) {
    record(switch (destination) {
      AdventureEntryDestination.learn =>
        AdventureDiagnosticReasonCode.entryLearn,
      AdventureEntryDestination.standardToday =>
        AdventureDiagnosticReasonCode.entryStandard,
      AdventureEntryDestination.adventure =>
        AdventureDiagnosticReasonCode.entryAdventure,
    });
  }

  void recordEntryFallback(AdventureFallbackReason reason) {
    final code = switch (reason) {
      AdventureFallbackReason.none => null,
      AdventureFallbackReason.learnerChoseStandard =>
        AdventureDiagnosticReasonCode.entryFallbackLearnerChoseStandard,
      AdventureFallbackReason.featureUnavailable =>
        AdventureDiagnosticReasonCode.entryFallbackFeatureUnavailable,
      AdventureFallbackReason.dependencyUnavailable =>
        AdventureDiagnosticReasonCode.entryFallbackDependencyUnavailable,
      AdventureFallbackReason.catalogUnavailable =>
        AdventureDiagnosticReasonCode.entryFallbackCatalogUnavailable,
      AdventureFallbackReason.contentUnavailable =>
        AdventureDiagnosticReasonCode.entryFallbackContentUnavailable,
      AdventureFallbackReason.assignmentUnavailable =>
        AdventureDiagnosticReasonCode.entryFallbackAssignmentUnavailable,
      AdventureFallbackReason.emergencyOff =>
        AdventureDiagnosticReasonCode.entryFallbackEmergencyOff,
    };
    if (code != null) record(code);
  }

  void recordCompositionFailure(AdventureSessionPlanFailure reason) {
    record(switch (reason) {
      AdventureSessionPlanFailure.ownerMismatch =>
        AdventureDiagnosticReasonCode.compositionOwnerMismatch,
      AdventureSessionPlanFailure.staleSource =>
        AdventureDiagnosticReasonCode.compositionStaleSource,
      AdventureSessionPlanFailure.unresolvedContent =>
        AdventureDiagnosticReasonCode.compositionUnresolvedContent,
      AdventureSessionPlanFailure.incompatibleConfiguration =>
        AdventureDiagnosticReasonCode.compositionIncompatibleConfiguration,
      AdventureSessionPlanFailure.unavailableEntry =>
        AdventureDiagnosticReasonCode.compositionUnavailableEntry,
    });
  }

  void recordEvidenceRetry({bool exhausted = false}) => record(
    exhausted
        ? AdventureDiagnosticReasonCode.evidenceRetryExhausted
        : AdventureDiagnosticReasonCode.evidenceRetry,
  );

  void recordProjectionRetry({bool exhausted = false}) => record(
    exhausted
        ? AdventureDiagnosticReasonCode.projectionRetryExhausted
        : AdventureDiagnosticReasonCode.projectionRetry,
  );

  void recordAssetFailure(OfflineContentFailureCode reason) {
    record(switch (reason) {
      OfflineContentFailureCode.checksumMismatch =>
        AdventureDiagnosticReasonCode.assetChecksumMismatch,
      OfflineContentFailureCode.sizeMismatch =>
        AdventureDiagnosticReasonCode.assetSizeMismatch,
      OfflineContentFailureCode.revisionMismatch =>
        AdventureDiagnosticReasonCode.assetRevisionMismatch,
      OfflineContentFailureCode.missingArtifact =>
        AdventureDiagnosticReasonCode.assetMissingArtifact,
      OfflineContentFailureCode.unsupportedContent =>
        AdventureDiagnosticReasonCode.assetUnsupportedContent,
      OfflineContentFailureCode.contentInUse =>
        AdventureDiagnosticReasonCode.assetContentInUse,
      OfflineContentFailureCode.interrupted =>
        AdventureDiagnosticReasonCode.assetInterrupted,
      OfflineContentFailureCode.invalidState =>
        AdventureDiagnosticReasonCode.assetInvalidState,
    });
  }

  AdventureDiagnosticSnapshot snapshot() =>
      AdventureDiagnosticSnapshot._(_counters);
}

enum AdventureCatalogRecoveryStatus {
  verified,
  repaired,
  quarantined,
  removed,
  unavailable,
}

final class AdventureCatalogRecoveryResult {
  const AdventureCatalogRecoveryResult({
    required this.status,
    required this.attempts,
    this.failureCode,
    this.removedBytes = 0,
  }) : assert(attempts >= 0 && attempts <= 3),
       assert(removedBytes >= 0);

  final AdventureCatalogRecoveryStatus status;
  final int attempts;
  final OfflineContentFailureCode? failureCode;
  final int removedBytes;
}

typedef AdventureCatalogRecoveryDelay = Future<void> Function(Duration delay);

enum AdventureCatalogManagerOwnership { shared, owned }

/// Bounded Adventure-facing access to the existing offline-content authority.
///
/// This coordinator never reads or mutates learning evidence or canonical
/// progress. All file and catalog changes remain owned by [OfflineContentManager].
final class AdventureCatalogRecoveryOperations {
  AdventureCatalogRecoveryOperations({
    required this.manager,
    required this.diagnostics,
    this.catalogIdentity = const ContentIdentity(
      type: ContentType.offlineArtifact,
      id: 'lexiquest.adventure.world-v1',
      revision: 1,
    ),
    this.onResult,
    this.maxAttempts = 3,
    this.baseBackoff = const Duration(milliseconds: 100),
    this.maxBackoff = const Duration(seconds: 2),
    this.operationTimeout = const Duration(seconds: 5),
    this.disposeTimeout = const Duration(seconds: 5),
    this.managerOwnership = AdventureCatalogManagerOwnership.shared,
    AdventureCatalogRecoveryDelay? delay,
  }) : _delay = delay ?? Future<void>.delayed {
    if (maxAttempts < 1 ||
        maxAttempts > 3 ||
        baseBackoff < Duration.zero ||
        maxBackoff <= Duration.zero ||
        maxBackoff > const Duration(seconds: 5) ||
        baseBackoff > maxBackoff ||
        operationTimeout <= Duration.zero ||
        operationTimeout > const Duration(seconds: 30) ||
        disposeTimeout <= Duration.zero ||
        disposeTimeout > const Duration(seconds: 30)) {
      throw ArgumentError('Invalid Adventure catalog retry configuration.');
    }
  }

  final OfflineContentManager manager;
  final AdventureDiagnostics diagnostics;
  final ContentIdentity catalogIdentity;
  final void Function(AdventureCatalogRecoveryResult result)? onResult;
  final int maxAttempts;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final Duration operationTimeout;
  final Duration disposeTimeout;
  final AdventureCatalogManagerOwnership managerOwnership;
  final AdventureCatalogRecoveryDelay _delay;
  final Map<ContentIdentity, Future<AdventureCatalogRecoveryResult>>
  _verifyInFlight = <ContentIdentity, Future<AdventureCatalogRecoveryResult>>{};
  final Map<ContentIdentity, Future<AdventureCatalogRecoveryResult>>
  _repairInFlight = <ContentIdentity, Future<AdventureCatalogRecoveryResult>>{};
  final Map<ContentIdentity, Future<AdventureCatalogRecoveryResult>>
  _removeInFlight = <ContentIdentity, Future<AdventureCatalogRecoveryResult>>{};
  final Map<ContentIdentity, Future<void>> _identityTails =
      <ContentIdentity, Future<void>>{};
  final Map<ContentIdentity, Future<void>> _managerFences =
      <ContentIdentity, Future<void>>{};
  final Set<ContentIdentity> _deadlineBlocked = <ContentIdentity>{};
  final Set<Future<Object?>> _active = <Future<Object?>>{};
  final Completer<void> _disposeSignal = Completer<void>();
  bool _disposed = false;
  Future<void>? _disposal;

  Future<AdventureCatalogRecoveryResult> verify([ContentIdentity? identity]) {
    _requireOpen();
    _requireCatalogIdentity(identity);
    return _schedule(
      identity: catalogIdentity,
      inFlight: _verifyInFlight,
      operation: () => _publish(_verify(catalogIdentity)),
    );
  }

  Future<AdventureCatalogRecoveryResult> repair([ContentIdentity? identity]) {
    _requireOpen();
    _requireCatalogIdentity(identity);
    return _schedule(
      identity: catalogIdentity,
      inFlight: _repairInFlight,
      operation: () => _publish(_repair(catalogIdentity)),
    );
  }

  Future<AdventureCatalogRecoveryResult> _repair(
    ContentIdentity identity,
  ) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        final state = await _attempt(identity, () => manager.repair(identity));
        _requireVerifiedState(state, identity);
        return AdventureCatalogRecoveryResult(
          status: AdventureCatalogRecoveryStatus.repaired,
          attempts: attempt,
        );
      } on Object catch (error) {
        if (error is _AdventureOperationDeadlineExceeded) {
          diagnostics.recordAssetFailure(OfflineContentFailureCode.interrupted);
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: OfflineContentFailureCode.interrupted,
          );
        }
        final code = await _repairFailureCode(identity, error);
        diagnostics.recordAssetFailure(code);
        if (code != OfflineContentFailureCode.interrupted) {
          final status = code == OfflineContentFailureCode.contentInUse
              ? AdventureCatalogRecoveryStatus.unavailable
              : AdventureCatalogRecoveryStatus.quarantined;
          final result = AdventureCatalogRecoveryResult(
            status: status,
            attempts: attempt,
            failureCode: code,
          );
          return result;
        }
        if (attempt == maxAttempts) {
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: code,
          );
        }
        if (!await _waitBackoff(_backoffAfter(attempt))) {
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: OfflineContentFailureCode.interrupted,
          );
        }
      }
    }
    throw StateError('Unreachable Adventure catalog retry state.');
  }

  Future<AdventureCatalogRecoveryResult> remove([ContentIdentity? identity]) {
    _requireOpen();
    _requireCatalogIdentity(identity);
    return _schedule(
      identity: catalogIdentity,
      inFlight: _removeInFlight,
      operation: () => _publish(_remove(catalogIdentity)),
    );
  }

  Future<AdventureCatalogRecoveryResult> _publish(
    Future<AdventureCatalogRecoveryResult> operation,
  ) => operation.then((result) {
    onResult?.call(result);
    return result;
  });

  Future<AdventureCatalogRecoveryResult> _remove(
    ContentIdentity identity,
  ) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        final removedBytes = await _attempt(
          identity,
          () => manager.removeBytes(identity),
        );
        return AdventureCatalogRecoveryResult(
          status: AdventureCatalogRecoveryStatus.removed,
          attempts: attempt,
          removedBytes: removedBytes,
        );
      } on Object catch (error) {
        if (error is _AdventureOperationDeadlineExceeded) {
          diagnostics.recordAssetFailure(OfflineContentFailureCode.interrupted);
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: OfflineContentFailureCode.interrupted,
          );
        }
        final code = _failureCode(error);
        diagnostics.recordAssetFailure(code);
        if (!_isTransient(error) || attempt == maxAttempts) {
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: code,
          );
        }
        if (!await _waitBackoff(_backoffAfter(attempt))) {
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: OfflineContentFailureCode.interrupted,
          );
        }
      }
    }
    throw StateError('Unreachable Adventure catalog removal retry state.');
  }

  Future<void> dispose() {
    final active = _disposal;
    if (active != null) return active;
    _disposed = true;
    if (!_disposeSignal.isCompleted) _disposeSignal.complete();
    return _disposal = _drainAndDispose();
  }

  Future<void> _drainAndDispose() async {
    try {
      await Future.wait<Object?>(
        _active.toList(growable: false),
        eagerError: false,
      ).timeout(disposeTimeout);
    } on Object {
      // Disposal is a lifecycle boundary; operation details remain closed.
    }
    if (managerOwnership == AdventureCatalogManagerOwnership.owned) {
      try {
        await manager.dispose().timeout(disposeTimeout);
      } on TimeoutException {
        diagnostics.recordAssetFailure(OfflineContentFailureCode.interrupted);
      }
    }
  }

  Future<AdventureCatalogRecoveryResult> _verify(
    ContentIdentity identity,
  ) async {
    final durable = await _durableState(identity);
    if (durable != null) return durable;
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        final state = await _attempt(identity, () => manager.verify(identity));
        _requireVerifiedState(state, identity);
        return AdventureCatalogRecoveryResult(
          status: AdventureCatalogRecoveryStatus.verified,
          attempts: attempt,
        );
      } on Object catch (error) {
        if (error is _AdventureOperationDeadlineExceeded) {
          diagnostics.recordAssetFailure(OfflineContentFailureCode.interrupted);
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: OfflineContentFailureCode.interrupted,
          );
        }
        final code = _failureCode(error);
        diagnostics.recordAssetFailure(code);
        if (!_isTransient(error)) {
          final status = code == OfflineContentFailureCode.contentInUse
              ? AdventureCatalogRecoveryStatus.unavailable
              : AdventureCatalogRecoveryStatus.quarantined;
          final result = AdventureCatalogRecoveryResult(
            status: status,
            attempts: attempt,
            failureCode: code,
          );
          return result;
        }
        if (attempt == maxAttempts) {
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: code,
          );
        }
        if (!await _waitBackoff(_backoffAfter(attempt))) {
          return AdventureCatalogRecoveryResult(
            status: AdventureCatalogRecoveryStatus.unavailable,
            attempts: attempt,
            failureCode: OfflineContentFailureCode.interrupted,
          );
        }
      }
    }
    throw StateError('Unreachable Adventure catalog verification retry state.');
  }

  Future<AdventureCatalogRecoveryResult?> _durableState(
    ContentIdentity identity,
  ) async {
    final source = manager;
    if (source is! OfflineContentStateInspector) return null;
    final inspector = source as OfflineContentStateInspector;
    late final OfflineContentState matching;
    try {
      matching = await _attempt(identity, () => inspector.inspect(identity));
      if (matching.identity != identity) {
        throw const OfflineContentFailure(
          OfflineContentFailureCode.invalidState,
        );
      }
    } on Object catch (error) {
      final code = _failureCode(error);
      diagnostics.recordAssetFailure(code);
      return AdventureCatalogRecoveryResult(
        status: AdventureCatalogRecoveryStatus.unavailable,
        attempts: 0,
        failureCode: code,
      );
    }
    if (matching.status != OfflineContentStatus.quarantined) return null;
    return AdventureCatalogRecoveryResult(
      status: AdventureCatalogRecoveryStatus.quarantined,
      attempts: 0,
      failureCode:
          matching.failureCode ?? OfflineContentFailureCode.invalidState,
    );
  }

  void _requireOpen() {
    if (_disposed) throw StateError('Adventure catalog recovery is disposed.');
  }

  void _requireCatalogIdentity(ContentIdentity? requested) {
    if (requested != null && requested != catalogIdentity) {
      throw ArgumentError.value(
        requested,
        'identity',
        'is outside the Adventure catalog recovery scope',
      );
    }
  }

  bool _isTransient(Object error) =>
      error is TimeoutException ||
      error is IOException ||
      (error is OfflineContentFailure &&
          error.code == OfflineContentFailureCode.interrupted);

  OfflineContentFailureCode _failureCode(Object error) =>
      error is OfflineContentFailure
      ? error.code
      : _isTransient(error)
      ? OfflineContentFailureCode.interrupted
      : OfflineContentFailureCode.invalidState;

  Future<OfflineContentFailureCode> _repairFailureCode(
    ContentIdentity identity,
    Object error,
  ) async {
    final direct = _failureCode(error);
    if (direct != OfflineContentFailureCode.invalidState ||
        error is OfflineContentFailure) {
      return direct;
    }
    final source = manager;
    if (source is! OfflineContentStateInspector) return direct;
    try {
      final inspector = source as OfflineContentStateInspector;
      final state = await _attempt(identity, () => inspector.inspect(identity));
      if (state.identity != identity) {
        return OfflineContentFailureCode.invalidState;
      }
      return state.failureCode ?? direct;
    } on Object {
      return direct;
    }
  }

  Duration _backoffAfter(int failedAttempt) {
    final candidate = baseBackoff * (1 << (failedAttempt - 1));
    return candidate > maxBackoff ? maxBackoff : candidate;
  }

  Future<T> _attempt<T>(
    ContentIdentity identity,
    Future<T> Function() operation,
  ) async {
    final source = Future<T>.sync(operation);
    final fence = source.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _managerFences[identity] = fence;
    fence.whenComplete(() {
      if (identical(_managerFences[identity], fence)) {
        _managerFences.remove(identity);
        _deadlineBlocked.remove(identity);
      }
    });
    final bounded = source.timeout(
      operationTimeout,
      onTimeout: () {
        _deadlineBlocked.add(identity);
        throw const _AdventureOperationDeadlineExceeded();
      },
    );
    return Future.any<T>(<Future<T>>[
      bounded,
      _disposeSignal.future.then<T>(
        (_) => throw const _AdventureOperationDeadlineExceeded(),
      ),
    ]);
  }

  void _requireVerifiedState(
    OfflineContentState state,
    ContentIdentity identity,
  ) {
    if (state.identity != identity) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    switch (state.status) {
      case OfflineContentStatus.verified:
        return;
      case OfflineContentStatus.interrupted:
        throw OfflineContentFailure(
          state.failureCode ?? OfflineContentFailureCode.interrupted,
        );
      case OfflineContentStatus.quarantined:
        throw OfflineContentFailure(
          state.failureCode ?? OfflineContentFailureCode.invalidState,
        );
      case OfflineContentStatus.notDownloaded:
      case OfflineContentStatus.downloading:
        throw const OfflineContentFailure(
          OfflineContentFailureCode.invalidState,
        );
    }
  }

  Future<bool> _waitBackoff(Duration duration) async {
    if (_disposed) return false;
    try {
      await Future.any<void>(<Future<void>>[
        _delay(duration).timeout(duration + operationTimeout),
        _disposeSignal.future,
      ]);
    } on Object {
      // The injected delay is treated as bounded scheduling infrastructure.
    }
    return !_disposed;
  }

  Future<AdventureCatalogRecoveryResult> _schedule({
    required ContentIdentity identity,
    required Map<ContentIdentity, Future<AdventureCatalogRecoveryResult>>
    inFlight,
    required Future<AdventureCatalogRecoveryResult> Function() operation,
  }) {
    if (_deadlineBlocked.contains(identity)) {
      return Future<AdventureCatalogRecoveryResult>.value(
        const AdventureCatalogRecoveryResult(
          status: AdventureCatalogRecoveryStatus.unavailable,
          attempts: 0,
          failureCode: OfflineContentFailureCode.interrupted,
        ),
      );
    }
    final active = inFlight[identity];
    if (active != null) return active;
    final predecessor = _identityTails[identity] ?? Future<void>.value();
    late final Future<AdventureCatalogRecoveryResult> scheduled;
    scheduled = _track(
      predecessor
          .then<AdventureCatalogRecoveryResult>((_) {
            if (_disposed || _deadlineBlocked.contains(identity)) {
              return const AdventureCatalogRecoveryResult(
                status: AdventureCatalogRecoveryStatus.unavailable,
                attempts: 0,
                failureCode: OfflineContentFailureCode.interrupted,
              );
            }
            return operation();
          })
          .whenComplete(() {
            if (identical(inFlight[identity], scheduled)) {
              inFlight.remove(identity);
            }
          }),
    );
    final tail = scheduled.then<void>(
      (_) {},
      onError: (Object _, StackTrace stackTrace) {},
    );
    _identityTails[identity] = tail;
    tail.whenComplete(() {
      if (identical(_identityTails[identity], tail)) {
        _identityTails.remove(identity);
      }
    });
    inFlight[identity] = scheduled;
    return scheduled;
  }

  Future<T> _track<T>(Future<T> source) {
    late final Future<T> tracked;
    tracked = source.whenComplete(() => _active.remove(tracked));
    _active.add(tracked);
    return tracked;
  }
}

final class _AdventureOperationDeadlineExceeded implements Exception {
  const _AdventureOperationDeadlineExceeded();
}
