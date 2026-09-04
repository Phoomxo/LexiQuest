import '../../review/domain/review_queue_item.dart';
import '../domain/adventure_result.dart';

abstract interface class AdventureResultNextActionReader {
  Future<AdventureNextAction> read({required String ownerId});
}

/// Read-only adapter from Adventure Result to the canonical Review/SRS queue.
final class ReviewCenterAdventureResultNextActionReader
    implements AdventureResultNextActionReader {
  ReviewCenterAdventureResultNextActionReader({
    required this.reader,
    required this.ownerIdentities,
    required this.nowUtc,
    required String timezoneId,
    int limit = 100,
  }) : timezoneId = _validatedCanonicalText(timezoneId, 'timezoneId'),
       limit = _validatedLimit(limit);

  final ReviewCenterReader reader;
  final ReviewOwnerIdentityReader ownerIdentities;
  final DateTime Function() nowUtc;
  final String timezoneId;
  final int limit;

  Object get readerIdentity => reader;
  Object get ownerIdentity => ownerIdentities;

  @override
  Future<AdventureNextAction> read({required String ownerId}) {
    final requestedOwnerId = _validatedCanonicalText(ownerId, 'ownerId');
    final evaluatedAtUtc = _validatedUtc(nowUtc(), 'nowUtc');
    return _readCanonicalQueue(
      ownerId: requestedOwnerId,
      evaluatedAtUtc: evaluatedAtUtc,
    );
  }

  Future<AdventureNextAction> _readCanonicalQueue({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  }) async {
    try {
      final activeOwnerId = await ownerIdentities.requireSingleActiveOwnerId();
      if (activeOwnerId != ownerId) return AdventureNextAction.none;

      final items = await reader.compose(
        ReviewQueueFilter(
          ownerId: ownerId,
          evaluatedAtUtc: evaluatedAtUtc,
          timezoneId: timezoneId,
          limit: limit,
        ),
      );
      if (items.isEmpty) return AdventureNextAction.none;
      final hasDueSrs = items.any(
        (item) => item.provenance.any(
          (source) => source.reason == ReviewQueueReason.dueSrs,
        ),
      );
      return hasDueSrs
          ? AdventureNextAction.spacedRepetition
          : AdventureNextAction.reviewCenter;
    } catch (_) {
      return AdventureNextAction.none;
    }
  }
}

String _validatedCanonicalText(String value, String name) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > 256 ||
      _controlText.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be canonical nonblank text');
  }
  return value;
}

DateTime _validatedUtc(DateTime value, String name) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, name, 'must be a nonnegative UTC time');
  }
  return value;
}

int _validatedLimit(int value) {
  if (value < 1 || value > 100) {
    throw ArgumentError.value(value, 'limit', 'must be between 1 and 100');
  }
  return value;
}

final RegExp _controlText = RegExp(
  r'[\u0000-\u001f\u007f-\u009f]',
  unicode: true,
);
