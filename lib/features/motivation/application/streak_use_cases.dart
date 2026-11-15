import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_streak_repository.dart';
import '../domain/streak_policy.dart';
import '../domain/timezone_policy.dart';

typedef StreakUtcNow = DateTime Function();

final class StreakUseCases {
  const StreakUseCases({
    required this.repository,
    required this.owners,
    required this.nowUtc,
    this.onSettled,
  });

  final DriftStreakRepository repository;
  final LocalOwnerRepository owners;
  final StreakUtcNow nowUtc;
  final void Function()? onSettled;

  Future<StreakFoldResult> settle({required String expectedOwnerId}) async {
    await _requireOwner(expectedOwnerId);
    final result = await repository.settle(
      expectedOwnerId: expectedOwnerId,
      asOfUtc: _now(),
    );
    await _requireOwner(expectedOwnerId);
    if (result.status == StreakFoldStatus.ready) {
      onSettled?.call();
    }
    return result;
  }

  Future<void> afterAnswerCommitted({
    required String ownerId,
    required String attemptId,
    required int occurredAtUtcMs,
  }) async {
    await _requireOwner(ownerId);
    final result = await repository.settle(
      expectedOwnerId: ownerId,
      asOfUtc: _now(),
      answer: (attemptId: attemptId, occurredAtUtcMs: occurredAtUtcMs),
    );
    await _requireOwner(ownerId);
    if (result.status == StreakFoldStatus.ready) {
      onSettled?.call();
    }
  }

  Future<bool> useFreezeToken({
    required String expectedOwnerId,
    required String commandId,
  }) async {
    await _requireOwner(expectedOwnerId);
    final result = await repository.debitFreezeToken(
      expectedOwnerId: expectedOwnerId,
      commandId: commandId,
      occurredAtUtc: _now(),
    );
    await _requireOwner(expectedOwnerId);
    if (result) {
      onSettled?.call();
    }
    return result;
  }

  Future<OwnerCalendarRule> selectHomeTimezone({
    required String expectedOwnerId,
    required String ianaId,
  }) async {
    await _requireOwner(expectedOwnerId);
    final result = await repository.selectHomeTimezone(
      expectedOwnerId: expectedOwnerId,
      ianaId: ianaId,
      occurredAtUtc: _now(),
    );
    await _requireOwner(expectedOwnerId);
    onSettled?.call();
    return result;
  }

  Future<
    ({String ownerId, OwnerCalendarRule current, OwnerCalendarRule? pending})
  >
  loadCalendar() async {
    final owner = await owners.getOrCreateActiveOwner();
    final result = await repository.previewCalendarSchedule(
      ownerId: owner.id,
      asOfUtc: _now(),
    );
    await _requireOwner(owner.id);
    return (
      ownerId: owner.id,
      current: result.current,
      pending: result.pending,
    );
  }

  Future<void> _requireOwner(String expectedOwnerId) async {
    if (expectedOwnerId.isEmpty ||
        (await owners.getOrCreateActiveOwner()).id != expectedOwnerId) {
      throw StateError('Streak owner changed');
    }
  }

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc || value.microsecondsSinceEpoch < 0) {
      throw ArgumentError.value(value, 'nowUtc', 'must be nonnegative UTC');
    }
    return value;
  }
}
