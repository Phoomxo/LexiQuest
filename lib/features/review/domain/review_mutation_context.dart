import 'dart:async';

/// Admission carried through the existing callback/repository contracts.
/// This is only a cancellation/expected-owner constraint: the canonical owner
/// repository and database remain the authorities. Nested callers retain every
/// outer constraint. No cancellation is claimed after a transaction commits.
final class ReviewMutationContext {
  ReviewMutationContext._(this.expectedOwnerId, this.isCurrent, this.parent);

  static final Object _key = Object();
  static ReviewMutationContext? get current =>
      Zone.current[_key] as ReviewMutationContext?;

  final String? expectedOwnerId;
  final bool Function() isCurrent;
  final ReviewMutationContext? parent;

  void requireCurrent([String? ownerId]) {
    parent?.requireCurrent(ownerId);
    if (!isCurrent() ||
        (ownerId != null &&
            expectedOwnerId != null &&
            ownerId != expectedOwnerId)) {
      throw StateError('Review mutation admission expired or owner changed');
    }
  }

  static Future<T> run<T>(
    Future<T> Function() action, {
    required bool Function() isCurrent,
    String? expectedOwnerId,
  }) async {
    final admission = ReviewMutationContext._(
      expectedOwnerId,
      isCurrent,
      current,
    );
    admission.requireCurrent();
    return runZoned(action, zoneValues: {_key: admission});
  }
}
