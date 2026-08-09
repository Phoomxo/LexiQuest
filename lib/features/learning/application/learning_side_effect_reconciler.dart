import '../../../data/local/app_database.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../data/drift_learning_event_store.dart';

typedef LearningProjectionSink = Future<void> Function(EventEnvelopeV2 event);

final class LearningSideEffectReconciler {
  LearningSideEffectReconciler(
    AppDatabase database, {
    this.questSink,
    this.streakSink,
    this.rewardSink,
  }) : _events = DriftLearningEventStore(database);

  static const int appliedVersion = 1;

  final DriftLearningEventStore _events;
  final LearningProjectionSink? questSink;
  final LearningProjectionSink? streakSink;
  final LearningProjectionSink? rewardSink;

  Future<void> reconcileOwner(String ownerId) async {
    final events = await _events.listLearningEvents(ownerId);
    for (final event in events) {
      await _apply(event, 'quest', questSink);
      await _apply(event, 'streak', streakSink);
      await _apply(event, 'reward', rewardSink);
    }
  }

  Future<void> _apply(
    EventEnvelopeV2 event,
    String projection,
    LearningProjectionSink? sink,
  ) async {
    if (sink == null) return;
    if (await _events.isProjectionApplied(
      ownerId: event.ownerIdentity,
      sourceEventId: event.eventId,
      projection: projection,
      appliedVersion: appliedVersion,
    )) {
      return;
    }
    try {
      await sink(event);
      await _events.markProjectionApplied(
        source: event,
        projection: projection,
        appliedVersion: appliedVersion,
      );
    } catch (_) {
      // Each projection is independently retryable on the next reconciliation.
    }
  }
}
