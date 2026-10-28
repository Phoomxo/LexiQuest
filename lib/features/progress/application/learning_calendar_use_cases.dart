import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_learning_calendar_reader.dart';
import '../domain/learning_calendar.dart';

typedef LearningCalendarUtcNow = DateTime Function();

/// Owner-bound façade for the local learning-calendar read model.
final class LearningCalendarUseCases {
  const LearningCalendarUseCases({
    required this.owners,
    required this.reader,
    required this.nowUtc,
    required this.timezoneId,
  });

  final LocalOwnerRepository owners;
  final DriftLearningCalendarReader reader;
  final LearningCalendarUtcNow nowUtc;
  final String timezoneId;

  Future<LearningCalendarSnapshot> loadCurrentWeek() => loadWeek(nowUtc());

  Future<LearningCalendarSnapshot> loadWeek(DateTime referenceUtc) async {
    if (!referenceUtc.isUtc) {
      throw ArgumentError.value(referenceUtc, 'referenceUtc', 'must be UTC');
    }
    final owner = await owners.getOrCreateActiveOwner();
    return reader.loadWeek(
      ownerId: owner.id,
      referenceUtc: referenceUtc,
      timezoneId: timezoneId,
    );
  }
}
