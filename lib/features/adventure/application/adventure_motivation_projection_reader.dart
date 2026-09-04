import '../../../data/local/app_database.dart';
import 'package:drift/drift.dart';

import '../../events/domain/event_envelope_v2.dart';
import '../../learning/application/learning_side_effect_reconciler.dart';
import '../../learning/data/drift_learning_event_store.dart';
import '../../learning/domain/evidence_context.dart';

enum AdventureProjectionReceiptState { pending, committed, notEligible }

final class AdventureProjectionOutcome {
  const AdventureProjectionOutcome({
    required this.state,
    this.receiptId,
    this.displayCode,
  }) : assert(
         state != AdventureProjectionReceiptState.committed ||
             receiptId != null,
       ),
       assert(
         state != AdventureProjectionReceiptState.pending || receiptId == null,
       );

  final AdventureProjectionReceiptState state;
  final String? receiptId;
  final String? displayCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    'receiptId': receiptId,
    'displayCode': displayCode,
  };
}

final class AdventureMotivationSnapshot {
  const AdventureMotivationSnapshot({
    required this.sourceEvidenceId,
    required this.questOutcome,
    required this.streakOutcome,
    required this.rewardOutcome,
    required this.pendingProjection,
    this.achievementOutcomes = const <AdventureProjectionOutcome>[],
  });

  final String sourceEvidenceId;
  final AdventureProjectionOutcome questOutcome;
  final AdventureProjectionOutcome streakOutcome;
  final AdventureProjectionOutcome rewardOutcome;
  final List<AdventureProjectionOutcome> achievementOutcomes;
  final bool pendingProjection;

  Map<String, Object?> toJson() => <String, Object?>{
    'sourceEvidenceId': sourceEvidenceId,
    'questOutcome': questOutcome.toJson(),
    'streakOutcome': streakOutcome.toJson(),
    'achievementOutcomes': achievementOutcomes
        .map((outcome) => outcome.toJson())
        .toList(growable: false),
    'rewardOutcome': rewardOutcome.toJson(),
    'pendingProjection': pendingProjection,
  };
}

abstract interface class AdventureMotivationProjectionReader {
  Future<AdventureMotivationSnapshot> readForEvidence(String evidenceId);
}

final class DriftAdventureMotivationProjectionReader
    implements AdventureMotivationProjectionReader {
  DriftAdventureMotivationProjectionReader(AppDatabase database)
    : _database = database,
      _events = DriftLearningEventStore(database);

  static const AdventureProjectionOutcome _pending = AdventureProjectionOutcome(
    state: AdventureProjectionReceiptState.pending,
  );
  static const AdventureProjectionOutcome _notEligible =
      AdventureProjectionOutcome(
        state: AdventureProjectionReceiptState.notEligible,
      );

  final AppDatabase _database;
  final DriftLearningEventStore _events;

  @override
  Future<AdventureMotivationSnapshot> readForEvidence(String evidenceId) async {
    _requireEvidenceId(evidenceId);
    final attempt = await (_database.select(
      _database.answerAttempts,
    )..where((row) => row.id.equals(evidenceId))).getSingleOrNull();
    if (attempt == null) return _noOp(evidenceId);

    final source = await _events.readValidatedSourceForAttempt(
      attempt: attempt,
    );
    if (source == null || _excluded(attempt.evidenceClass)) {
      return _noOp(evidenceId);
    }

    final quest = await _readProjection(source, 'quest');
    final streak = await _readProjection(source, 'streak');
    final reward = await _readProjection(source, 'reward');
    final achievements = await _readAchievements(
      source: source,
      evidenceId: evidenceId,
    );
    return AdventureMotivationSnapshot(
      sourceEvidenceId: evidenceId,
      questOutcome: quest,
      streakOutcome: streak,
      achievementOutcomes: achievements,
      rewardOutcome: reward,
      pendingProjection: <AdventureProjectionOutcome>[quest, streak, reward]
          .any(
            (outcome) =>
                outcome.state == AdventureProjectionReceiptState.pending,
          ),
    );
  }

  Future<AdventureProjectionOutcome> _readProjection(
    EventEnvelopeV2 source,
    String projection,
  ) async {
    final receipt = await _events.readProjectionReceipt(
      source: source,
      projection: projection,
      appliedVersion: LearningSideEffectReconciler.appliedVersion,
    );
    if (receipt == null) return _pending;

    final receiptId =
        'learning-projection:$projection:${source.eventId}:'
        'v${LearningSideEffectReconciler.appliedVersion}';
    return switch (receipt.outcome) {
      LearningProjectionOutcome.applied => AdventureProjectionOutcome(
        state: AdventureProjectionReceiptState.committed,
        receiptId: receiptId,
      ),
      LearningProjectionOutcome.notApplicable ||
      LearningProjectionOutcome.blocked => AdventureProjectionOutcome(
        state: AdventureProjectionReceiptState.notEligible,
        receiptId: receiptId,
        displayCode:
            receipt.reasonCode ?? receipt.result['reasonCode'] as String?,
      ),
    };
  }

  Future<List<AdventureProjectionOutcome>> _readAchievements({
    required EventEnvelopeV2 source,
    required String evidenceId,
  }) async {
    final rows =
        await (_database.select(_database.achievementUnlocks)
              ..where(
                (row) =>
                    row.ownerId.equals(source.ownerIdentity) &
                    row.sourceEventId.equals(evidenceId),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.unlockedAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return List<AdventureProjectionOutcome>.unmodifiable(
      rows.map(
        (row) => AdventureProjectionOutcome(
          state: AdventureProjectionReceiptState.committed,
          receiptId: row.id,
          displayCode: row.achievementId,
        ),
      ),
    );
  }

  AdventureMotivationSnapshot _noOp(String evidenceId) =>
      AdventureMotivationSnapshot(
        sourceEvidenceId: evidenceId,
        questOutcome: _notEligible,
        streakOutcome: _notEligible,
        rewardOutcome: _notEligible,
        pendingProjection: false,
      );

  bool _excluded(String evidenceClass) =>
      evidenceClass == EvidenceClass.assessment.name ||
      evidenceClass == EvidenceClass.recreational.name;

  void _requireEvidenceId(String value) {
    if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
      throw ArgumentError.value(value, 'evidenceId');
    }
  }
}
