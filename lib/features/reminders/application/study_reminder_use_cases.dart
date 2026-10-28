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

  Future<StudyReminderOptInResult> optIn({
    required StudyReminderSource source,
    required DateTime scheduledAtUtc,
    required String timezoneId,
    ReminderQuietHours? quietHours,
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
    return _reconcileOwner(
      await repository.activeOwnerId(),
      featureEnabled: featureEnabled,
    );
  });

  Future<T> coordinateOwnerChange<T>({
    required String sourceOwnerId,
    required Future<T> Function() operation,
    required String Function(T result) targetOwnerId,
    required bool featureEnabled,
  }) => _serialize(() async {
    final source = _canonicalIdentifier(sourceOwnerId, 'sourceOwnerId');
    if (await repository.activeOwnerId() != source) {
      throw StateError('reminder owner change source is not active');
    }
    await _cancelOwnerPlatformEntries(source);
    late final T result;
    try {
      result = await operation();
    } catch (error, stackTrace) {
      try {
        if (await repository.activeOwnerId() == source) {
          await _reconcileOwner(source, featureEnabled: featureEnabled);
        }
      } on Object {
        // Preserve the canonical owner-change failure.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    try {
      final target = _canonicalIdentifier(
        targetOwnerId(result),
        'targetOwnerId',
      );
      if (await repository.activeOwnerId() != target) {
        throw StateError('reminder owner change target is not active');
      }
      await _reconcileOwner(target, featureEnabled: featureEnabled);
    } on Object {
      // The owner transition is already durable. Target platform repair is
      // best-effort and will replay from desired state on the next trigger.
    }
    return result;
  });

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
  }) async {
    // The live registry value is only a wake-up hint. Cross-isolate
    // correctness comes from the durable eligibility decision below.
    final _ = featureEnabled;
    if (!await _ownerOperationAllows(ownerId)) {
      return _completeResult(await _cancelFencedOwnerPlatformEntries(ownerId));
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
      platformEntries = await scheduler.pendingEntries();
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
      for (final entry in await scheduler.pendingEntries()) {
        if (entry.ownerId == ownerId) platformIds.add(entry.platformId);
      }
    } on Object {
      failed += 1;
      failureKinds.add(StudyReminderFailureKind.pendingEntries);
    }
    for (final platformId in platformIds) {
      try {
        await scheduler.cancel(platformId);
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
        await scheduler.cancel(platformId);
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
        await scheduler.cancel(platformId);
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
          await scheduler.cancel(platformId);
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
        await scheduler.cancel(platformId);
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
        final isPending = (await scheduler.pendingEntries()).any(
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
          await scheduler.cancel(platformId);
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
      await scheduler.cancel(platformId);
      cancelled += 1;
      return _PlatformDelta(
        scheduled: scheduled,
        cancelled: cancelled,
        failed: 1,
      );
    } on Object {
      try {
        await scheduler.cancel(platformId);
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

    await scheduler.schedule(request);

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
      await scheduler.cancel(platformId);
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
    final platformEntries = await scheduler.pendingEntries();
    final reminderIds = await repository.reminderIdsForOwner(ownerId);
    return <int>{
      for (final reminderId in reminderIds)
        studyReminderPlatformId(ownerId, reminderId),
      for (final entry in platformEntries)
        if (entry.ownerId == ownerId) entry.platformId,
    };
  }

  Future<void> _cancelPlatformIds(
    Set<int> platformIds, {
    required bool failOnError,
  }) async {
    final failures = <Object>[];
    for (final platformId in platformIds) {
      try {
        await scheduler.cancel(platformId);
      } on Object catch (error) {
        failures.add(error);
      }
    }
    if (failOnError && failures.isNotEmpty) {
      throw StateError('source-owner reminder platform cleanup failed');
    }
  }

  Future<StudyReminderReconcileResult> _cancelFencedOwnerPlatformEntries(
    String ownerId,
  ) async {
    var cancelled = 0;
    var failed = 0;
    late final List<ReminderPlatformEntry> entries;
    try {
      entries = await scheduler.pendingEntries();
    } on Object {
      return const StudyReminderReconcileResult(
        scheduled: 0,
        cancelled: 0,
        failed: 1,
      );
    }
    for (final entry in entries) {
      if (entry.ownerId != ownerId) continue;
      try {
        await scheduler.cancel(entry.platformId);
        cancelled += 1;
      } on Object {
        failed += 1;
      }
    }
    return StudyReminderReconcileResult(
      scheduled: 0,
      cancelled: cancelled,
      failed: failed,
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
  });

  final int scheduled;
  final int cancelled;
  final int failed;
  final bool featureEligibilityFailed;
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
