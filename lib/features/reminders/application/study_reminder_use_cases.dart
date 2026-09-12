import 'package:timezone/timezone.dart' as timezone;

import '../domain/reminder_scheduler.dart';
import '../domain/study_reminder.dart';
import '../domain/study_reminder_repository.dart';

typedef StudyReminderIdGenerator = String Function();
typedef StudyReminderUtcNow = DateTime Function();
typedef StudyReminderFeatureEligibilityLoader =
    Future<StudyReminderFeatureEligibility> Function();

final class StudyReminderFeatureEligibility {
  const StudyReminderFeatureEligibility({
    required this.enabled,
    required this.epoch,
  });

  const StudyReminderFeatureEligibility.unfenced() : enabled = true, epoch = 0;

  final bool enabled;
  final Object epoch;
}

enum StudyReminderOptInResult {
  scheduled,
  permissionDenied,
  unavailable,
  pendingRetry,
  invalidSchedule,
}

enum StudyReminderAvailability { available, unsupported, degraded }

enum StudyReminderFailureKind {
  initialization,
  supportStatus,
  permissionStatus,
  pendingEntries,
  platformSideEffect,
  durableState,
  featureEligibility,
}

final class StudyReminderReconcileResult {
  const StudyReminderReconcileResult({
    required this.scheduled,
    required this.cancelled,
    required this.failed,
    this.availability = StudyReminderAvailability.available,
    this.failureKinds = const <StudyReminderFailureKind>{},
  });

  final int scheduled;
  final int cancelled;
  final int failed;
  final StudyReminderAvailability availability;
  final Set<StudyReminderFailureKind> failureKinds;
}

final class StudyReminderOperationCoordinator {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final ready = _tail.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    final result = ready.then<T>((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

final class StudyReminderUseCases {
  StudyReminderUseCases({
    required this.repository,
    required this.scheduler,
    required this.nowUtc,
    required this.generateId,
    StudyReminderFeatureEligibilityLoader? loadFeatureEligibility,
    StudyReminderOperationCoordinator? operationCoordinator,
  }) : operationCoordinator =
           operationCoordinator ?? _sharedCoordinatorFor(repository),
       loadFeatureEligibility =
           loadFeatureEligibility ??
           _loadUnfencedStudyReminderFeatureEligibility;

  static final Expando<StudyReminderOperationCoordinator> _sharedCoordinators =
      Expando<StudyReminderOperationCoordinator>();

  final StudyReminderRepository repository;
  final ReminderScheduler scheduler;
  final StudyReminderUtcNow nowUtc;
  final StudyReminderIdGenerator generateId;
  final StudyReminderFeatureEligibilityLoader loadFeatureEligibility;
  final StudyReminderOperationCoordinator operationCoordinator;
  bool _initialized = false;
  StudyReminderAvailability _availability = StudyReminderAvailability.available;
  Set<StudyReminderFailureKind> _lastFailureKinds = const {};
  // Set only by the serialized lifecycle while its caller holds the actual
  // canonical lease. Native repair shares that proof through every await.
  Future<void> Function()? _transitionNativeGuard;

  StudyReminderAvailability get availability => _availability;

  Set<StudyReminderFailureKind> get lastFailureKinds => _lastFailureKinds;

  Future<StudyReminderAvailability> initialize() async {
    try {
      await scheduler.initialize();
      _initialized = true;
      _availability = StudyReminderAvailability.available;
      _lastFailureKinds = const {};
      return _availability;
    } on Object {
      _initialized = false;
      _availability = StudyReminderAvailability.degraded;
      _lastFailureKinds = const {StudyReminderFailureKind.initialization};
      return _availability;
    }
  }

  Future<List<StudyReminder>> list() async {
    final ownerId = await repository.activeOwnerId();
    if (!await _ownerOperationAllows(ownerId)) return const <StudyReminder>[];
    final states = await repository.listForOwner(ownerId);
    return List<StudyReminder>.unmodifiable(
      states.map((state) => state.reminder),
    );
  }

  Future<bool> canOpenSettings() async {
    final ownerId = await repository.activeOwnerId();
    if (!await _ownerOperationAllows(ownerId)) return false;
    if (!await _ensureInitialized()) return false;
    try {
      if (!await scheduler.isSupported()) {
        _recordAvailability(StudyReminderAvailability.unsupported);
        return false;
      }
    } on Object {
      _recordFailure(StudyReminderFailureKind.supportStatus);
      return false;
    }
    try {
      final permission = await scheduler.permissionState();
      _recordAvailability(StudyReminderAvailability.available);
      return permission != ReminderPermissionState.denied;
    } on Object {
      _recordFailure(StudyReminderFailureKind.permissionStatus);
      return false;
    }
  }

  /// Observe desired state and native scheduling without prompting, repairing,
  /// acknowledging an intent, or changing the learner's reminder preference.
  Future<StudyReminderStatusSnapshot> loadStatus({
    required String expectedOwnerId,
    required StudyReminderSource source,
  }) async {
    final ownerId = _canonicalIdentifier(expectedOwnerId, 'expectedOwnerId');
    await _requireStatusOwner(ownerId);
    StudyReminderDesiredState? observed;
    var status = StudyReminderDisplayStatus.unavailable;
    var stable = false;
    try {
      final states = (await repository.listForOwner(
        ownerId,
      )).where((state) => state.reminder.source == source).toList();
      if (states.length > 1) throw StateError('Reminder source is ambiguous.');
      observed = states.firstOrNull;
      final eligibility = await loadFeatureEligibility();
      final allowed = await _ownerOperationAllows(ownerId);
      final reminder = observed?.reminder;
      if (eligibility.enabled && allowed) {
        if (reminder == null || !reminder.isEnabled || reminder.isDeleted) {
          status = StudyReminderDisplayStatus.disabled;
        } else if (await _ensureInitialized() &&
            await scheduler.isSupported()) {
          final permission = await scheduler.permissionState();
          if (permission == ReminderPermissionState.denied) {
            status = StudyReminderDisplayStatus.permissionDenied;
          } else if (permission == ReminderPermissionState.granted) {
            final native = await _pendingNativeEntries();
            final intents = await repository.pendingPlatformIntentsForOwner(
              ownerId,
            );
            final pending = intents.any(
              (intent) => intent.reminderId == reminder.id,
            );
            final platformId = studyReminderPlatformId(ownerId, reminder.id);
            final matchingEntry = native.any(
              (entry) =>
                  entry.platformId == platformId &&
                  entry.ownerId == ownerId &&
                  entry.reminderId == reminder.id,
            );
            if (!reminder.effectiveScheduledAtUtc.isAfter(_utcNow())) {
              status = StudyReminderDisplayStatus.elapsed;
            } else {
              status = !pending && matchingEntry
                  ? StudyReminderDisplayStatus.scheduled
                  : StudyReminderDisplayStatus.pendingRetry;
            }
          }
        }
      }
      // A read can span another worker's revision or feature change. Do not
      // combine an old native observation with a newer desired schedule.
      final latest = (await repository.listForOwner(
        ownerId,
      )).where((state) => state.reminder.source == source).toList();
      final latestEligibility = await loadFeatureEligibility();
      stable =
          latest.length <= 1 &&
          _sameRevision(observed, latest.firstOrNull) &&
          latestEligibility.enabled == eligibility.enabled &&
          latestEligibility.epoch == eligibility.epoch &&
          await _ownerOperationAllows(ownerId) == allowed;
    } on Object {
      status = StudyReminderDisplayStatus.unavailable;
    }
    // Owner mismatch is an admission failure, not a native availability state.
    await _requireStatusOwner(ownerId);
    return StudyReminderStatusSnapshot(
      status: stable ? status : StudyReminderDisplayStatus.unavailable,
      reminder: stable ? observed?.reminder : null,
    );
  }

  Future<void> _requireStatusOwner(String expectedOwnerId) async {
    if (await repository.activeOwnerId() != expectedOwnerId) {
      throw const StudyReminderMutationUnavailable();
    }
  }

  Future<StudyReminderOptInResult> optIn({
    required StudyReminderSource source,
    required DateTime scheduledAtUtc,
    required String timezoneId,
    ReminderQuietHours? quietHours,
    String? expectedOwnerId,
    required StudyReminderMutationGuard mutationAllowed,
  }) => _serialize(() async {
    if (!mutationAllowed()) {
      throw const StudyReminderMutationUnavailable();
    }
    final now = _utcNow();
    final context = _validatedSchedule(
      scheduledAtUtc: scheduledAtUtc,
      timezoneId: timezoneId,
      quietHours: quietHours,
      nowUtc: now,
    );
    if (context == null) return StudyReminderOptInResult.invalidSchedule;
    final ownerId = await repository.activeOwnerId();
    if (expectedOwnerId != null && expectedOwnerId != ownerId) {
      throw const StudyReminderMutationUnavailable();
    }
    if (!await _ownerOperationAllows(ownerId)) {
      throw const StudyReminderMutationUnavailable();
    }
    try {
      if (!(await loadFeatureEligibility()).enabled) {
        return StudyReminderOptInResult.unavailable;
      }
    } on Object {
      _recordFailure(StudyReminderFailureKind.featureEligibility);
      return StudyReminderOptInResult.unavailable;
    }
    if (!await _ensureInitialized()) {
      return StudyReminderOptInResult.unavailable;
    }
    late final bool supported;
    try {
      supported = await scheduler.isSupported();
    } on Object {
      _recordFailure(StudyReminderFailureKind.supportStatus);
      return StudyReminderOptInResult.unavailable;
    }
    if (!supported) {
      _recordAvailability(StudyReminderAvailability.unsupported);
      return StudyReminderOptInResult.unavailable;
    }
    late var permission = ReminderPermissionState.unknown;
    try {
      permission = await scheduler.permissionState();
    } on Object {
      _recordFailure(StudyReminderFailureKind.permissionStatus);
      return StudyReminderOptInResult.unavailable;
    }
    if (permission != ReminderPermissionState.granted) {
      try {
        permission = await scheduler.requestPermission();
      } on Object {
        _recordFailure(StudyReminderFailureKind.permissionStatus);
        return StudyReminderOptInResult.unavailable;
      }
    }
    if (permission != ReminderPermissionState.granted) {
      return permission == ReminderPermissionState.denied
          ? StudyReminderOptInResult.permissionDenied
          : StudyReminderOptInResult.unavailable;
    }
    final existing =
        (await repository.listForOwner(ownerId, includeDeleted: true))
            .where(
              (candidate) =>
                  !candidate.reminder.isDeleted &&
                  candidate.reminder.source.stableIdentity ==
                      source.stableIdentity,
            )
            .firstOrNull;
    final reminder = StudyReminder(
      id: existing?.reminder.id ?? _newReminderId(),
      ownerId: ownerId,
      source: source,
      scheduledAtUtc: scheduledAtUtc,
      timezone: context,
      quietHours: quietHours,
      isEnabled: true,
      createdAtUtc: existing?.reminder.createdAtUtc ?? now,
      updatedAtUtc: existing == null
          ? now
          : _after(existing.reminder.updatedAtUtc),
    );
    await repository.save(reminder, mutationAllowed: mutationAllowed);
    final result = await _reconcileOwner(
      ownerId,
      featureEnabled: mutationAllowed(),
    );
    return result.failed == 0 && result.cancelled == 0
        ? StudyReminderOptInResult.scheduled
        : StudyReminderOptInResult.pendingRetry;
  });

  Future<void> cancel(
    String reminderId, {
    required StudyReminderMutationGuard mutationAllowed,
  }) => _serialize(() async {
    final ownerId = await repository.activeOwnerId();
    if (!await _ownerOperationAllows(ownerId)) {
      throw const StudyReminderMutationUnavailable();
    }
    await repository.cancel(
      reminderId,
      updatedAtUtc: _nextMutationTime(reminderId),
      mutationAllowed: mutationAllowed,
    );
    await _reconcileOwner(ownerId, featureEnabled: mutationAllowed());
  });

  Future<void> delete(
    String reminderId, {
    required StudyReminderMutationGuard mutationAllowed,
  }) => _serialize(() async {
    final ownerId = await repository.activeOwnerId();
    if (!await _ownerOperationAllows(ownerId)) {
      throw const StudyReminderMutationUnavailable();
    }
    await repository.delete(
      reminderId,
      updatedAtUtc: _nextMutationTime(reminderId),
      mutationAllowed: mutationAllowed,
    );
    await _reconcileOwner(ownerId, featureEnabled: mutationAllowed());
  });

  Future<StudyReminderReconcileResult> reconcile({
    required bool featureEnabled,
    String? currentTimezoneId,
  }) => _serialize(() async {
    // Persisted IANA zones are authoritative. Follow-device semantics do not
    // exist in this model, so the legacy runtime hint cannot rebase reminders.
    final _ = currentTimezoneId;
    var scheduled = 0;
    var cancelled = 0;
    var failed = 0;
    var availability = StudyReminderAvailability.available;
    final failureKinds = <StudyReminderFailureKind>{};
    // Native calls cannot be recalled once issued. If their owner/fence
    // boundary retires, make at most one pass from fresh canonical state.
    // This stays inside the current serializer and never acquires a lease.
    for (var pass = 0; pass < 2; pass++) {
      var needsCurrentOwnerRepair = false;
      final ownerId = await repository.activeOwnerId();
      final result = await _reconcileOwner(
        ownerId,
        featureEnabled: featureEnabled,
        requestCurrentOwnerRepair: () => needsCurrentOwnerRepair = true,
      );
      final orphans = await _repairInactiveOwnerEntries(ownerId);
      scheduled += result.scheduled;
      cancelled += result.cancelled + orphans.cancelled;
      failed += result.failed + orphans.failed;
      availability = result.availability;
      failureKinds.addAll(result.failureKinds);
      if (orphans.failed > 0) {
        failureKinds.add(StudyReminderFailureKind.platformSideEffect);
      }
      needsCurrentOwnerRepair |= orphans.needsCurrentOwnerRepair;
      if (!needsCurrentOwnerRepair) break;
      if (pass == 1) {
        failed++;
        failureKinds.add(StudyReminderFailureKind.durableState);
      }
    }
    return _completeResult(
      StudyReminderReconcileResult(
        scheduled: scheduled,
        cancelled: cancelled,
        failed: failed,
        availability: failed > 0 || failureKinds.isNotEmpty
            ? StudyReminderAvailability.degraded
            : availability,
        failureKinds: Set<StudyReminderFailureKind>.unmodifiable(failureKinds),
      ),
    );
  });

  Future<T> coordinateOwnerChange<T>({
    required String sourceOwnerId,
    required String operationToken,
    required Future<T> Function() operation,
    required String Function(T result) targetOwnerId,
    required bool featureEnabled,
  }) => _serialize(() async {
    final source = _canonicalIdentifier(sourceOwnerId, 'sourceOwnerId');
    final token = _canonicalIdentifier(operationToken, 'operationToken');
    var expectedOwner = source;
    Future<void> requireAuthority() =>
        _requireTransitionAuthority(expectedOwner, token);
    await requireAuthority();
    _transitionNativeGuard = requireAuthority;
    var fenceEnded = false;
    try {
      await repository.beginOwnerOperationFence(
        ownerId: source,
        operationToken: token,
        nowUtc: _utcNow(),
      );
      final captured = <int>{};
      final cleanupFailures = <StudyReminderFailureKind>{};
      late final T result;
      Object? operationError;
      StackTrace? operationStack;
      try {
        captured.addAll(await _ownerPlatformIds(source));
        await requireAuthority();
        await _cancelPlatformIds(
          captured,
          failOnError: true,
          entryOwner: source,
        );
        await requireAuthority();
        result = await operation();
        expectedOwner = _canonicalIdentifier(
          targetOwnerId(result),
          'targetOwnerId',
        );
      } catch (error, stackTrace) {
        operationError = error;
        operationStack = stackTrace;
      }
      try {
        await requireAuthority();
        final swept = await _cancelPlatformIds(
          captured,
          failOnError: false,
          entryOwner: source,
        );
        if (!swept) {
          cleanupFailures.add(StudyReminderFailureKind.platformSideEffect);
        }
      } on Object {
        cleanupFailures.add(StudyReminderFailureKind.platformSideEffect);
        _recordFailure(StudyReminderFailureKind.platformSideEffect);
      }
      try {
        await repository.endOwnerOperationFence(
          ownerId: source,
          operationToken: token,
        );
        fenceEnded = true;
      } on Object {
        cleanupFailures.add(StudyReminderFailureKind.durableState);
        _recordFailure(StudyReminderFailureKind.durableState);
      }
      try {
        // Restoration is legal only after removing our marker and while the
        // same token still owns the canonical lease, including same-owner races.
        await requireAuthority();
        if (fenceEnded) {
          await _reconcileOwner(expectedOwner, featureEnabled: featureEnabled);
        }
      } on Object {
        cleanupFailures.add(StudyReminderFailureKind.platformSideEffect);
        _recordFailure(StudyReminderFailureKind.platformSideEffect);
      }
      if (cleanupFailures.isNotEmpty) {
        // Target desired state can converge while a captured source native ID
        // still needs retry. Keep both observations in the reported status.
        _availability = StudyReminderAvailability.degraded;
        _lastFailureKinds = Set<StudyReminderFailureKind>.unmodifiable({
          ..._lastFailureKinds,
          ...cleanupFailures,
        });
      }
      if (operationError != null) {
        Error.throwWithStackTrace(operationError, operationStack!);
      }
      return result;
    } finally {
      if (!fenceEnded) {
        try {
          await repository.endOwnerOperationFence(
            ownerId: source,
            operationToken: token,
          );
        } on Object {
          // The exact marker becomes inert when this lease expires/releases.
        }
      }
      _transitionNativeGuard = null;
    }
  });

  Future<void> _requireTransitionAuthority(String ownerId, String token) async {
    if (!await repository.isOwnerOperationTokenOwned(
      operationToken: token,
      nowUtc: _utcNow(),
    ))
      throw StateError('reminder owner-operation lease was lost');
    if (await repository.activeOwnerId() != ownerId ||
        !await repository.isOwnerOperationTokenOwned(
          operationToken: token,
          nowUtc: _utcNow(),
        ))
      throw StateError('reminder owner-operation authority changed');
  }

  Future<_PlatformDelta> _repairInactiveOwnerEntries(String activeOwner) async {
    var cancelled = 0;
    var failed = 0;
    var needsCurrentOwnerRepair = false;
    try {
      if (!await _orphanCleanupAllows(activeOwner)) {
        return const _PlatformDelta();
      }
      final entries = await _pendingNativeEntries();
      if (!await _orphanCleanupAllows(activeOwner)) {
        return const _PlatformDelta();
      }
      for (final entry in entries) {
        if (entry.ownerId == activeOwner) continue;
        if (!await _orphanCleanupAllows(activeOwner, entry.ownerId)) break;
        // Payloads can be replaced at the same native ID while enumeration is
        // pending. Revalidate the decoded identity, never derive a new hash.
        final latest = await _pendingNativeEntries();
        if (!latest.any(
          (candidate) =>
              candidate.platformId == entry.platformId &&
              candidate.ownerId == entry.ownerId &&
              candidate.reminderId == entry.reminderId,
        ))
          continue;
        if (!await _orphanCleanupAllows(activeOwner, entry.ownerId)) break;
        try {
          await _cancelNative(entry.platformId);
          cancelled++;
        } on Object {
          failed++;
        }
        if (!await _orphanCleanupAllows(activeOwner, entry.ownerId)) {
          needsCurrentOwnerRepair = true;
          break;
        }
      }
    } on Object {
      failed++;
    }
    return _PlatformDelta(
      cancelled: cancelled,
      failed: failed,
      needsCurrentOwnerRepair: needsCurrentOwnerRepair,
    );
  }

  Future<bool> _orphanCleanupAllows(
    String activeOwner, [
    String? payloadOwner,
  ]) async {
    if (await repository.activeOwnerId() != activeOwner ||
        !await _ownerOperationAllows(activeOwner))
      return false;
    if (payloadOwner != null && !await _ownerOperationAllows(payloadOwner))
      return false;
    // Fence reads are asynchronous too. Never continue using the owner sample
    // from before those reads when another transition has already committed.
    return await repository.activeOwnerId() == activeOwner;
  }

  Future<void> cancelOwnerPlatformEntries(String ownerId) =>
      _serialize(() => _cancelOwnerPlatformEntries(ownerId));

  Future<T> coordinateOwnerErasure<T>({
    required String ownerId,
    required String operationToken,
    required Future<T> Function() operation,
  }) => _serialize(() async {
    final owner = _canonicalIdentifier(ownerId, 'ownerId');
    if (await repository.activeOwnerId() != owner) {
      throw StateError('reminder owner erasure source is not active');
    }
    await repository.beginOwnerOperationFence(
      ownerId: owner,
      operationToken: operationToken,
      nowUtc: _utcNow(),
    );
    try {
      final capturedPlatformIds = await _ownerPlatformIds(owner);
      await _cancelPlatformIds(capturedPlatformIds, failOnError: true);
      late final T result;
      try {
        result = await operation();
      } catch (error, stackTrace) {
        await _cancelPlatformIds(capturedPlatformIds, failOnError: false);
        Error.throwWithStackTrace(error, stackTrace);
      }
      // Rows and outbox entries may now be gone. Reuse the exact pre-delete
      // platform identities so the final sweep never needs a new active owner.
      await _cancelPlatformIds(capturedPlatformIds, failOnError: false);
      return result;
    } finally {
      try {
        await repository.endOwnerOperationFence(
          ownerId: owner,
          operationToken: operationToken,
        );
      } on Object {
        // The canonical lease release makes an uncleared marker inert. Never
        // replace the authoritative erasure result or failure during cleanup.
      }
    }
  });

  Future<StudyReminderReconcileResult> _reconcileOwner(
    String ownerId, {
    required bool featureEnabled,
    void Function()? requestCurrentOwnerRepair,
  }) async {
    // The live registry value is only a wake-up hint. Cross-isolate
    // correctness comes from the durable eligibility decision below.
    final _ = featureEnabled;
    if (!await _ownerOperationAllows(ownerId)) {
      return _completeResult(
        await _cancelFencedOwnerPlatformEntries(
          ownerId,
          requestCurrentOwnerRepair: requestCurrentOwnerRepair,
        ),
      );
    }
    late final StudyReminderFeatureEligibility eligibility;
    try {
      eligibility = await loadFeatureEligibility();
    } on Object {
      return _reconcileFeatureOff(
        ownerId,
        observedEligibility: null,
        featureEligibilityFailed: true,
      );
    }
    if (!eligibility.enabled) {
      return _reconcileFeatureOff(ownerId, observedEligibility: eligibility);
    }
    return _reconcileEnabledOwner(ownerId);
  }

  Future<StudyReminderReconcileResult> _reconcileEnabledOwner(
    String ownerId,
  ) async {
    if (!await _ensureInitialized()) {
      return _completeResult(
        const StudyReminderReconcileResult(
          scheduled: 0,
          cancelled: 0,
          failed: 1,
          availability: StudyReminderAvailability.degraded,
          failureKinds: {StudyReminderFailureKind.initialization},
        ),
      );
    }

    late final bool supported;
    try {
      supported = await scheduler.isSupported();
    } on Object {
      return _completeResult(
        const StudyReminderReconcileResult(
          scheduled: 0,
          cancelled: 0,
          failed: 1,
          availability: StudyReminderAvailability.degraded,
          failureKinds: {StudyReminderFailureKind.supportStatus},
        ),
      );
    }
    var permission = ReminderPermissionState.unknown;
    if (supported) {
      try {
        permission = await scheduler.permissionState();
      } on Object {
        return _completeResult(
          const StudyReminderReconcileResult(
            scheduled: 0,
            cancelled: 0,
            failed: 1,
            availability: StudyReminderAvailability.degraded,
            failureKinds: {StudyReminderFailureKind.permissionStatus},
          ),
        );
      }
    }
    var scheduled = 0;
    var cancelled = 0;
    var failed = 0;
    final failureKinds = <StudyReminderFailureKind>{};

    late final List<ReminderPlatformEntry> platformEntries;
    try {
      platformEntries = await _pendingNativeEntries();
    } on Object {
      return _completeResult(
        const StudyReminderReconcileResult(
          scheduled: 0,
          cancelled: 0,
          failed: 1,
          availability: StudyReminderAvailability.degraded,
          failureKinds: {StudyReminderFailureKind.pendingEntries},
        ),
      );
    }
    for (final entry in platformEntries) {
      if (entry.ownerId != ownerId) continue;
      final delta = await _repairPlatformEntry(
        ownerId: entry.ownerId,
        reminderId: entry.reminderId,
        supported: supported,
        permission: permission,
      );
      scheduled += delta.scheduled;
      cancelled += delta.cancelled;
      failed += delta.failed;
      if (delta.featureEligibilityFailed) {
        failureKinds.add(StudyReminderFailureKind.featureEligibility);
      } else if (delta.failed > 0) {
        failureKinds.add(StudyReminderFailureKind.platformSideEffect);
      }
    }

    late final List<StudyReminderPlatformIntent> intents;
    try {
      intents = await repository.pendingPlatformIntentsForOwner(ownerId);
    } on Object {
      return _completeResult(
        StudyReminderReconcileResult(
          scheduled: scheduled,
          cancelled: cancelled,
          failed: failed + 1,
          availability: StudyReminderAvailability.degraded,
          failureKinds: {
            ...failureKinds,
            StudyReminderFailureKind.durableState,
          },
        ),
      );
    }
    for (final intent in intents) {
      final delta = await _applyIntent(
        intent,
        supported: supported,
        permission: permission,
      );
      scheduled += delta.scheduled;
      cancelled += delta.cancelled;
      failed += delta.failed;
      if (delta.featureEligibilityFailed) {
        failureKinds.add(StudyReminderFailureKind.featureEligibility);
      } else if (delta.failed > 0) {
        failureKinds.add(StudyReminderFailureKind.platformSideEffect);
      }
    }

    late final List<StudyReminderDesiredState> desired;
    try {
      desired = await repository.listForOwner(ownerId, includeDeleted: true);
    } on Object {
      return _completeResult(
        StudyReminderReconcileResult(
          scheduled: scheduled,
          cancelled: cancelled,
          failed: failed + 1,
          availability: StudyReminderAvailability.degraded,
          failureKinds: {
            ...failureKinds,
            StudyReminderFailureKind.durableState,
          },
        ),
      );
    }
    for (final state in desired) {
      final delta = await _repairPlatformEntry(
        ownerId: ownerId,
        reminderId: state.reminder.id,
        supported: supported,
        permission: permission,
      );
      scheduled += delta.scheduled;
      cancelled += delta.cancelled;
      failed += delta.failed;
      if (delta.featureEligibilityFailed) {
        failureKinds.add(StudyReminderFailureKind.featureEligibility);
      } else if (delta.failed > 0) {
        failureKinds.add(StudyReminderFailureKind.platformSideEffect);
      }
    }

    return _completeResult(
      StudyReminderReconcileResult(
        scheduled: scheduled,
        cancelled: cancelled,
        failed: failed,
        availability: failureKinds.isNotEmpty
            ? StudyReminderAvailability.degraded
            : supported
            ? StudyReminderAvailability.available
            : StudyReminderAvailability.unsupported,
        failureKinds: Set<StudyReminderFailureKind>.unmodifiable(failureKinds),
      ),
    );
  }

  Future<StudyReminderReconcileResult> _reconcileFeatureOff(
    String ownerId, {
    required StudyReminderFeatureEligibility? observedEligibility,
    bool featureEligibilityFailed = false,
  }) async {
    final platformIds = <int>{};
    final initializationDegraded =
        !_initialized &&
        _lastFailureKinds.contains(StudyReminderFailureKind.initialization);
    final failureKinds = <StudyReminderFailureKind>{
      if (initializationDegraded) StudyReminderFailureKind.initialization,
      if (featureEligibilityFailed) StudyReminderFailureKind.featureEligibility,
    };
    var cancelled = 0;
    var failed =
        (initializationDegraded ? 1 : 0) + (featureEligibilityFailed ? 1 : 0);
    bool? supported;
    try {
      for (final reminderId in await repository.reminderIdsForOwner(ownerId)) {
        platformIds.add(studyReminderPlatformId(ownerId, reminderId));
      }
    } on Object {
      failed += 1;
      failureKinds.add(StudyReminderFailureKind.durableState);
    }
    try {
      supported = await scheduler.isSupported();
    } on Object {
      failed += 1;
      failureKinds.add(StudyReminderFailureKind.supportStatus);
    }
    if (supported != false) {
      try {
        await scheduler.permissionState();
      } on Object {
        failed += 1;
        failureKinds.add(StudyReminderFailureKind.permissionStatus);
      }
    }
    try {
      for (final entry in await _pendingNativeEntries()) {
        if (entry.ownerId == ownerId) platformIds.add(entry.platformId);
      }
    } on Object {
      failed += 1;
      failureKinds.add(StudyReminderFailureKind.pendingEntries);
    }
    for (final platformId in platformIds) {
      try {
        await _cancelNative(platformId);
        cancelled += 1;
      } on Object {
        failed += 1;
        failureKinds.add(StudyReminderFailureKind.platformSideEffect);
      }
    }

    // A worker can observe off, block in platform cancellation, and then land
    // that stale cancellation after another isolate clears the override and
    // restores the reminder. Re-read the exact durable epoch once and perform
    // one bounded desired-state repair when the newer decision is enabled.
    StudyReminderReconcileResult? convergence;
    if (observedEligibility != null) {
      try {
        final latest = await loadFeatureEligibility();
        if (latest.enabled &&
            (!observedEligibility.enabled ||
                latest.epoch != observedEligibility.epoch)) {
          convergence = await _reconcileEnabledOwner(ownerId);
        }
      } on Object {
        failed += 1;
        failureKinds.add(StudyReminderFailureKind.featureEligibility);
      }
    }
    if (convergence != null) {
      failed += convergence.failed;
      failureKinds.addAll(convergence.failureKinds);
    }

    return _completeResult(
      StudyReminderReconcileResult(
        scheduled: convergence?.scheduled ?? 0,
        cancelled: cancelled + (convergence?.cancelled ?? 0),
        failed: failed,
        availability: failureKinds.isNotEmpty
            ? StudyReminderAvailability.degraded
            : supported == false
            ? StudyReminderAvailability.unsupported
            : StudyReminderAvailability.available,
        failureKinds: Set<StudyReminderFailureKind>.unmodifiable(failureKinds),
      ),
    );
  }

  Future<_PlatformDelta> _applyIntent(
    StudyReminderPlatformIntent intent, {
    required bool supported,
    required ReminderPermissionState permission,
  }) async {
    final platformId = studyReminderPlatformId(
      intent.ownerId,
      intent.reminderId,
    );
    var scheduled = 0;
    var cancelled = 0;
    try {
      if (!await _ownerOperationAllows(intent.ownerId)) {
        await _cancelNative(platformId);
        return const _PlatformDelta(cancelled: 1);
      }
      final resolved = await repository.resolvePlatformIntent(intent);
      if (resolved == null) return const _PlatformDelta();
      final current = await repository.resolvePlatformIntent(intent);
      if (current == null) return const _PlatformDelta();
      final shouldSchedule =
          intent.kind == StudyReminderPlatformIntentKind.schedule &&
          await _shouldScheduleState(
            current,
            supported: supported,
            permission: permission,
          );
      if (shouldSchedule) {
        final guarded = await _scheduleWithFeatureFence(
          _request(current.reminder),
        );
        scheduled += guarded.scheduled;
        cancelled += guarded.cancelled;
        if (guarded.status != _FeatureFencedScheduleStatus.landed) {
          if (guarded.status == _FeatureFencedScheduleStatus.unavailable) {
            try {
              await repository.recordPlatformFailure(
                intent,
                attemptedAtUtc: _utcNow(),
                failureCode: 'featureEligibility',
              );
            } on Object {
              // Preserve the fail-closed feature-fence outcome.
            }
          }
          return _PlatformDelta(
            scheduled: scheduled,
            cancelled: cancelled,
            failed: guarded.failed,
            featureEligibilityFailed:
                guarded.status == _FeatureFencedScheduleStatus.unavailable,
          );
        }
      } else {
        await _cancelNative(platformId);
        cancelled += 1;
      }
      final afterSideEffect = await repository.resolvePlatformIntent(intent);
      final shouldScheduleAfter =
          intent.kind == StudyReminderPlatformIntentKind.schedule &&
          await _shouldScheduleState(
            afterSideEffect,
            supported: supported,
            permission: permission,
          );
      if (!_sameRevision(current, afterSideEffect) ||
          shouldScheduleAfter != shouldSchedule) {
        if (shouldSchedule) {
          await _cancelNative(platformId);
          cancelled += 1;
        }
        final repair = await _repairPlatformEntry(
          ownerId: intent.ownerId,
          reminderId: intent.reminderId,
          supported: supported,
          permission: permission,
        );
        return _PlatformDelta(
          scheduled: scheduled + repair.scheduled,
          cancelled: cancelled + repair.cancelled,
          failed: repair.failed,
          featureEligibilityFailed: repair.featureEligibilityFailed,
        );
      }
      await repository.acknowledgePlatformIntent(
        intent,
        acknowledgedAtUtc: _utcNow(),
      );
      final repair = await _repairPlatformEntry(
        ownerId: intent.ownerId,
        reminderId: intent.reminderId,
        supported: supported,
        permission: permission,
      );
      return _PlatformDelta(
        scheduled: scheduled + repair.scheduled,
        cancelled: cancelled + repair.cancelled,
        failed: repair.failed,
        featureEligibilityFailed: repair.featureEligibilityFailed,
      );
    } on Object catch (error) {
      try {
        await repository.recordPlatformFailure(
          intent,
          attemptedAtUtc: _utcNow(),
          failureCode: error.runtimeType.toString(),
        );
      } on Object {
        // Preserve fail-closed platform cleanup below.
      }
      try {
        await _cancelNative(platformId);
        return const _PlatformDelta(cancelled: 1, failed: 1);
      } on Object {
        return const _PlatformDelta(failed: 1);
      }
    }
  }

  Future<_PlatformDelta> _repairPlatformEntry({
    required String ownerId,
    required String reminderId,
    required bool supported,
    required ReminderPermissionState permission,
  }) async {
    final platformId = studyReminderPlatformId(ownerId, reminderId);
    var scheduled = 0;
    var cancelled = 0;
    int? appliedRevision;
    try {
      for (var pass = 0; pass < 4; pass += 1) {
        final state = await repository.desiredState(ownerId, reminderId);
        final shouldSchedule = await _shouldScheduleState(
          state,
          supported: supported,
          permission: permission,
        );
        final isPending = (await _pendingNativeEntries()).any(
          (entry) =>
              entry.platformId == platformId &&
              entry.ownerId == ownerId &&
              entry.reminderId == reminderId,
        );
        if (shouldSchedule == isPending &&
            (!isPending ||
                appliedRevision == null ||
                appliedRevision == state?.localRevision)) {
          return _PlatformDelta(scheduled: scheduled, cancelled: cancelled);
        }
        final checked = await repository.desiredState(ownerId, reminderId);
        if (!_sameRevision(state, checked) ||
            await _shouldScheduleState(
                  checked,
                  supported: supported,
                  permission: permission,
                ) !=
                shouldSchedule) {
          continue;
        }
        if (shouldSchedule) {
          final guarded = await _scheduleWithFeatureFence(
            _request(checked!.reminder),
          );
          scheduled += guarded.scheduled;
          cancelled += guarded.cancelled;
          if (guarded.status != _FeatureFencedScheduleStatus.landed) {
            return _PlatformDelta(
              scheduled: scheduled,
              cancelled: cancelled,
              failed: guarded.failed,
              featureEligibilityFailed:
                  guarded.status == _FeatureFencedScheduleStatus.unavailable,
            );
          }
          appliedRevision = checked.localRevision;
        } else {
          await _cancelNative(platformId);
          cancelled += 1;
          appliedRevision = null;
        }
        final afterSideEffect = await repository.desiredState(
          ownerId,
          reminderId,
        );
        final shouldScheduleAfter = await _shouldScheduleState(
          afterSideEffect,
          supported: supported,
          permission: permission,
        );
        if (_sameRevision(checked, afterSideEffect) &&
            shouldScheduleAfter == shouldSchedule) {
          return _PlatformDelta(scheduled: scheduled, cancelled: cancelled);
        }
      }
      // Bounded fail-closed terminal action: never let a stale schedule be the
      // last platform effect if desired state churns outside this coordinator.
      await _cancelNative(platformId);
      cancelled += 1;
      return _PlatformDelta(
        scheduled: scheduled,
        cancelled: cancelled,
        failed: 1,
      );
    } on Object {
      try {
        await _cancelNative(platformId);
        return _PlatformDelta(
          scheduled: scheduled,
          cancelled: cancelled + 1,
          failed: 1,
        );
      } on Object {
        return _PlatformDelta(
          scheduled: scheduled,
          cancelled: cancelled,
          failed: 1,
        );
      }
    }
  }

  Future<void> _cancelOwnerPlatformEntries(String ownerId) async {
    final owner = _canonicalIdentifier(ownerId, 'ownerId');
    final platformIds = await _ownerPlatformIds(owner);
    await _cancelPlatformIds(platformIds, failOnError: true);
  }

  Future<_FeatureFencedSchedule> _scheduleWithFeatureFence(
    ReminderScheduleRequest request,
  ) async {
    late final StudyReminderFeatureEligibility before;
    try {
      before = await loadFeatureEligibility();
    } on Object {
      return _cancelFeatureFencedSchedule(
        request.platformId,
        status: _FeatureFencedScheduleStatus.unavailable,
      );
    }
    if (!before.enabled) {
      return _cancelFeatureFencedSchedule(
        request.platformId,
        status: _FeatureFencedScheduleStatus.featureChanged,
      );
    }

    await _scheduleNative(request);

    late final StudyReminderFeatureEligibility after;
    try {
      after = await loadFeatureEligibility();
    } on Object {
      return _cancelFeatureFencedSchedule(
        request.platformId,
        status: _FeatureFencedScheduleStatus.unavailable,
        scheduled: 1,
      );
    }
    if (!after.enabled || after.epoch != before.epoch) {
      return _cancelFeatureFencedSchedule(
        request.platformId,
        status: _FeatureFencedScheduleStatus.featureChanged,
        scheduled: 1,
      );
    }
    return const _FeatureFencedSchedule(
      status: _FeatureFencedScheduleStatus.landed,
      scheduled: 1,
    );
  }

  Future<_FeatureFencedSchedule> _cancelFeatureFencedSchedule(
    int platformId, {
    required _FeatureFencedScheduleStatus status,
    int scheduled = 0,
  }) async {
    try {
      await _cancelNative(platformId);
      return _FeatureFencedSchedule(
        status: status,
        scheduled: scheduled,
        cancelled: 1,
        failed: status == _FeatureFencedScheduleStatus.unavailable ? 1 : 0,
      );
    } on Object {
      return _FeatureFencedSchedule(
        status: _FeatureFencedScheduleStatus.unavailable,
        scheduled: scheduled,
        failed: 1,
      );
    }
  }

  Future<Set<int>> _ownerPlatformIds(String ownerId) async {
    final platformEntries = await _pendingNativeEntries();
    final reminderIds = await repository.reminderIdsForOwner(ownerId);
    return <int>{
      for (final reminderId in reminderIds)
        studyReminderPlatformId(ownerId, reminderId),
      for (final entry in platformEntries)
        if (entry.ownerId == ownerId) entry.platformId,
    };
  }

  Future<bool> _cancelPlatformIds(
    Set<int> platformIds, {
    required bool failOnError,
    String? entryOwner,
  }) async {
    final failures = <Object>[];
    for (final platformId in platformIds) {
      await _transitionNativeGuard?.call();
      try {
        if (entryOwner != null) {
          final entries = await _pendingNativeEntries();
          if (entries.any(
            (entry) =>
                entry.platformId == platformId && entry.ownerId != entryOwner,
          ))
            continue;
        }
        await _cancelNative(platformId);
      } on Object catch (error) {
        failures.add(error);
      }
    }
    if (failOnError && failures.isNotEmpty) {
      throw StateError('source-owner reminder platform cleanup failed');
    }
    if (failures.isNotEmpty) {
      _recordFailure(StudyReminderFailureKind.platformSideEffect);
    }
    return failures.isEmpty;
  }

  Future<List<ReminderPlatformEntry>> _pendingNativeEntries() async {
    await _transitionNativeGuard?.call();
    final entries = await scheduler.pendingEntries();
    await _transitionNativeGuard?.call();
    return entries;
  }

  Future<void> _cancelNative(int platformId) async {
    await _transitionNativeGuard?.call();
    await scheduler.cancel(platformId);
    await _transitionNativeGuard?.call();
  }

  Future<void> _scheduleNative(ReminderScheduleRequest request) async {
    await _transitionNativeGuard?.call();
    await scheduler.schedule(request);
    await _transitionNativeGuard?.call();
  }

  Future<StudyReminderReconcileResult> _cancelFencedOwnerPlatformEntries(
    String ownerId, {
    void Function()? requestCurrentOwnerRepair,
  }) async {
    var cancelled = 0;
    var failed = 0;
    var invalidated = false;
    final failureKinds = <StudyReminderFailureKind>{};
    Future<bool> stillFenced() async =>
        await repository.activeOwnerId() == ownerId &&
        await repository.isOwnerOperationFenced(
          ownerId: ownerId,
          nowUtc: _utcNow(),
        ) &&
        await repository.activeOwnerId() == ownerId;
    late final List<ReminderPlatformEntry> entries;
    try {
      entries = await _pendingNativeEntries();
    } on Object {
      return const StudyReminderReconcileResult(
        scheduled: 0,
        cancelled: 0,
        failed: 1,
        availability: StudyReminderAvailability.degraded,
        failureKinds: {StudyReminderFailureKind.pendingEntries},
      );
    }
    try {
      if (!await stillFenced()) {
        invalidated = true;
      } else {
        for (final entry in entries) {
          if (entry.ownerId != ownerId) continue;
          if (!await stillFenced()) {
            invalidated = true;
            break;
          }
          try {
            await _cancelNative(entry.platformId);
            cancelled++;
          } on Object {
            failed++;
            failureKinds.add(StudyReminderFailureKind.platformSideEffect);
          }
          if (!await stillFenced()) {
            invalidated = true;
            break;
          }
        }
      }
    } on Object {
      failed++;
      failureKinds.add(StudyReminderFailureKind.durableState);
    }
    if (invalidated) {
      if (requestCurrentOwnerRepair != null) {
        requestCurrentOwnerRepair();
      } else {
        failed++;
        failureKinds.add(StudyReminderFailureKind.durableState);
      }
    }
    return StudyReminderReconcileResult(
      scheduled: 0,
      cancelled: cancelled,
      failed: failed,
      availability: failed > 0
          ? StudyReminderAvailability.degraded
          : StudyReminderAvailability.available,
      failureKinds: Set<StudyReminderFailureKind>.unmodifiable(failureKinds),
    );
  }

  static StudyReminderTimezoneContext timezoneContext(
    String timezoneId,
    DateTime occurredAtUtc,
  ) {
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'occurredAtUtc', 'must be UTC');
    }
    final location = timezone.getLocation(timezoneId);
    final local = timezone.TZDateTime.from(occurredAtUtc, location);
    return StudyReminderTimezoneContext(
      timezoneId: timezoneId,
      utcOffsetMinutes: local.timeZoneOffset.inMinutes,
    );
  }

  StudyReminderTimezoneContext? _validatedSchedule({
    required DateTime scheduledAtUtc,
    required String timezoneId,
    required ReminderQuietHours? quietHours,
    required DateTime nowUtc,
  }) {
    if (!scheduledAtUtc.isUtc ||
        scheduledAtUtc.millisecondsSinceEpoch < 0 ||
        !scheduledAtUtc.isAfter(nowUtc)) {
      return null;
    }
    if (quietHours != null &&
        (quietHours.startMinutes < 0 ||
            quietHours.startMinutes >= 24 * 60 ||
            quietHours.endMinutes < 0 ||
            quietHours.endMinutes >= 24 * 60)) {
      return null;
    }
    try {
      final context = timezoneContext(timezoneId, scheduledAtUtc);
      final effective =
          quietHours?.shiftOutside(scheduledAtUtc, timezoneId) ??
          scheduledAtUtc;
      return effective.isAfter(nowUtc) ? context : null;
    } on Object {
      return null;
    }
  }

  ReminderScheduleRequest _request(StudyReminder reminder) {
    final copy = switch (reminder.source.kind) {
      StudyReminderSourceKind.dueReview => (
        title: 'A gentle study reminder',
        body: 'A few reviews are ready whenever you are.',
      ),
      StudyReminderSourceKind.goalDeadline => (
        title: 'A gentle goal reminder',
        body: 'Your learning goal is here whenever you are ready.',
      ),
    };
    return ReminderScheduleRequest(
      platformId: studyReminderPlatformId(reminder.ownerId, reminder.id),
      ownerId: reminder.ownerId,
      reminderId: reminder.id,
      scheduledAtUtc: reminder.effectiveScheduledAtUtc,
      timezoneId: reminder.timezone.timezoneId,
      title: copy.title,
      body: copy.body,
    );
  }

  Future<bool> _shouldScheduleState(
    StudyReminderDesiredState? state, {
    required bool supported,
    required ReminderPermissionState permission,
  }) async {
    final reminder = state?.reminder;
    if (reminder == null ||
        !supported ||
        permission != ReminderPermissionState.granted ||
        !reminder.isEnabled ||
        reminder.isDeleted ||
        !await _ownerOperationAllows(reminder.ownerId) ||
        await repository.activeOwnerId() != reminder.ownerId) {
      return false;
    }
    try {
      return reminder.effectiveScheduledAtUtc.isAfter(_utcNow());
    } on Object {
      return false;
    }
  }

  bool _sameRevision(
    StudyReminderDesiredState? left,
    StudyReminderDesiredState? right,
  ) => left == null
      ? right == null
      : right != null &&
            left.reminder.ownerId == right.reminder.ownerId &&
            left.reminder.id == right.reminder.id &&
            left.localRevision == right.localRevision;

  Future<bool> _ownerOperationAllows(String ownerId) async {
    try {
      return !await repository.isOwnerOperationFenced(
        ownerId: ownerId,
        nowUtc: _utcNow(),
      );
    } on Object {
      return false;
    }
  }

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    return await initialize() != StudyReminderAvailability.degraded;
  }

  StudyReminderReconcileResult _completeResult(
    StudyReminderReconcileResult result,
  ) {
    _availability = result.availability;
    _lastFailureKinds = Set<StudyReminderFailureKind>.unmodifiable(
      result.failureKinds,
    );
    return result;
  }

  void _recordAvailability(StudyReminderAvailability availability) {
    _availability = availability;
    _lastFailureKinds = const {};
  }

  void _recordFailure(StudyReminderFailureKind failure) {
    _availability = StudyReminderAvailability.degraded;
    _lastFailureKinds = Set<StudyReminderFailureKind>.unmodifiable({failure});
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    return operationCoordinator.run(operation);
  }

  static StudyReminderOperationCoordinator _sharedCoordinatorFor(
    StudyReminderRepository repository,
  ) => _sharedCoordinators[repository] ??= StudyReminderOperationCoordinator();

  String _newReminderId() {
    final generated = generateId();
    if (generated.isEmpty || generated != generated.trim()) {
      throw StateError('reminder id generator returned an invalid value');
    }
    return 'reminder:$generated';
  }

  DateTime _nextMutationTime(String reminderId) {
    final now = _utcNow();
    if (reminderId.isEmpty) {
      throw ArgumentError.value(reminderId, 'reminderId', 'must not be empty');
    }
    return now;
  }

  DateTime _after(DateTime existing) {
    final now = _utcNow();
    return now.isAfter(existing)
        ? now
        : existing.add(const Duration(milliseconds: 1));
  }

  DateTime _utcNow() {
    final now = nowUtc();
    if (!now.isUtc || now.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(now, 'nowUtc', 'must be nonnegative UTC');
    }
    return now;
  }
}

final class _PlatformDelta {
  const _PlatformDelta({
    this.scheduled = 0,
    this.cancelled = 0,
    this.failed = 0,
    this.featureEligibilityFailed = false,
    this.needsCurrentOwnerRepair = false,
  });

  final int scheduled;
  final int cancelled;
  final int failed;
  final bool featureEligibilityFailed;
  final bool needsCurrentOwnerRepair;
}

enum _FeatureFencedScheduleStatus { landed, featureChanged, unavailable }

final class _FeatureFencedSchedule {
  const _FeatureFencedSchedule({
    required this.status,
    this.scheduled = 0,
    this.cancelled = 0,
    this.failed = 0,
  });

  final _FeatureFencedScheduleStatus status;
  final int scheduled;
  final int cancelled;
  final int failed;
}

Future<StudyReminderFeatureEligibility>
_loadUnfencedStudyReminderFeatureEligibility() async =>
    const StudyReminderFeatureEligibility.unfenced();

String _canonicalIdentifier(String value, String field) {
  final canonical = value.trim();
  if (canonical.isEmpty || canonical.length > 256) {
    throw ArgumentError.value(value, field, 'must be canonical text');
  }
  return canonical;
}
