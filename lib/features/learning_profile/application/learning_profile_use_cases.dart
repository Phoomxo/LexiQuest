import 'dart:async';

import '../domain/learning_profile.dart';
import '../domain/learning_profile_repository.dart';

final class LearningProfileUseCases {
  LearningProfileUseCases({required this.repository, required this.nowUtc}) {
    _ownerChanges = repository.watchActiveOwnerId().listen(
      (_) => _ownerGeneration++,
      onError: (Object _) => _ownerGeneration++,
      onDone: () => _ownerGeneration++,
    );
  }

  final LearningProfileRepository repository;
  final DateTime Function() nowUtc;
  late final StreamSubscription<String?> _ownerChanges;
  var _ownerGeneration = 0;
  var _disposed = false;

  Stream<String?> watchActiveOwnerId() => repository.watchActiveOwnerId();

  Future<LearningProfileSnapshot> load({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => repository.read(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: () => !_disposed && stillCurrent(),
  );

  Stream<LearningProfileSnapshot> watch({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => repository.watch(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: () => !_disposed && stillCurrent(),
  );

  LearningProfileChange prepareChange({
    required LearningProfileSnapshot snapshot,
    required LearningProfileDraft draft,
    required bool Function() stillCurrent,
  }) {
    final generation = _ownerGeneration;
    return LearningProfileChange(
      expectedOwnerId: snapshot.ownerId,
      expectedRevision: snapshot.revision,
      draft: draft,
      updatedAtUtc: _timestamp(),
      stillCurrent: () =>
          !_disposed && generation == _ownerGeneration && stillCurrent(),
    );
  }

  DateTime _timestamp() {
    final value = nowUtc();
    if (!value.isUtc ||
        value.millisecondsSinceEpoch < 0 ||
        value.millisecondsSinceEpoch > 8640000000000000) {
      throw const LearningProfileException(LearningProfileFailureCode.invalid);
    }
    return DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    );
  }

  Future<LearningProfile> save(LearningProfileChange change) {
    if (_disposed || !change.stillCurrent()) {
      throw const LearningProfileException(
        LearningProfileFailureCode.ownerChanged,
      );
    }
    return repository.save(change);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ownerGeneration++;
    await _ownerChanges.cancel();
  }
}
