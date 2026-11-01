import '../../../product/feature_contract/feature_contract_digest.dart';
import 'evidence_context.dart';
import 'learning_evidence_contract.dart';
import 'learning_models.dart';

enum RecallLadderStage {
  exposure,
  recognition,
  matching,
  cloze,
  typedRecall,
  dictation,
  speaking,
}

final class RecallLadderObservation {
  const RecallLadderObservation._({
    required this.attemptId,
    required this.stage,
    required this.isCorrect,
    required this.assisted,
    required this.evidenceClass,
    required this.occurredAtUtc,
  });
  final String attemptId;
  final RecallLadderStage stage;
  final bool isCorrect;
  final bool assisted;
  final EvidenceClass evidenceClass;
  final DateTime occurredAtUtc;

  static RecallLadderObservation? fromEvidence({
    required String attemptId,
    required String promptMode,
    required bool isCorrect,
    required DateTime occurredAtUtc,
    required EvidenceContext context,
  }) {
    try {
      if (!LearningEvidenceContract.validIdentifier(attemptId) ||
          !occurredAtUtc.isUtc ||
          occurredAtUtc.millisecondsSinceEpoch < 0 ||
          !LearningEvidenceContract.isOrdinaryEvidence(context) ||
          context.classificationSource !=
              EvidenceClassificationSource.declared ||
          context.policyVersion != EvidenceContext.currentPolicyVersion ||
          context.featureContractRevision !=
              currentFeatureContractIdentity.revision ||
          context.featureContractHash !=
              currentFeatureContractIdentity.semanticHash) {
        return null;
      }
      final stage = switch (promptMode) {
        'meaningChoice' || 'definitionChoice' => RecallLadderStage.recognition,
        'matchingPair' => RecallLadderStage.matching,
        'clozeChoice' || 'clozeTyped' => RecallLadderStage.cloze,
        'definitionTyped' ||
        'srsRecall' ||
        'associativeRecall' => RecallLadderStage.typedRecall,
        'dictation' => RecallLadderStage.dictation,
        'shadowing' || 'pronunciationTranscript' => RecallLadderStage.speaking,
        _ => null,
      };
      if (stage == null) return null;
      final skill = switch (promptMode) {
        'meaningChoice' => 'meaning-recall',
        'definitionChoice' || 'definitionTyped' => 'definition-recall',
        'matchingPair' => 'meaning-recognition',
        'clozeChoice' || 'clozeTyped' => 'cloze-context',
        'srsRecall' => 'srs-recall',
        'associativeRecall' => 'associative-recall',
        'dictation' => 'dictation-spelling',
        'shadowing' => 'shadowing-pronunciation',
        'pronunciationTranscript' => 'pronunciation-transcript',
        _ => null,
      };
      if (context.skillId != skill) return null;
      final expected = switch (promptMode) {
        'meaningChoice' || 'definitionChoice' =>
          context.hintLevel == 0
              ? EvidenceClass.recognition
              : EvidenceClass.guidedPractice,
        'matchingPair' || 'clozeChoice' => EvidenceClass.recognition,
        'clozeTyped' => EvidenceClass.guidedPractice,
        'definitionTyped' || 'dictation' =>
          context.hintLevel == 0
              ? EvidenceClass.independentRecall
              : EvidenceClass.guidedPractice,
        'srsRecall' || 'associativeRecall' => EvidenceClass.independentRecall,
        'shadowing' || 'pronunciationTranscript' => EvidenceClass.pronunciation,
        _ => null,
      };
      if (context.evidenceClass != expected) return null;
      final assisted =
          context.hintLevel > 0 ||
          context.evidenceClass == EvidenceClass.guidedPractice;
      if ((promptMode == 'matchingPair' || promptMode == 'clozeChoice') &&
          assisted) {
        return null;
      }
      return RecallLadderObservation._(
        attemptId: attemptId,
        stage: stage,
        isCorrect: isCorrect,
        assisted: assisted,
        evidenceClass: context.evidenceClass,
        occurredAtUtc: occurredAtUtc,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}

final class RecallLadderSnapshot {
  RecallLadderSnapshot({
    required this.ownerId,
    required this.word,
    required Iterable<RecallLadderObservation> observations,
  }) : observations = List.unmodifiable(
         observations.toList()..sort((a, b) {
           final time = b.occurredAtUtc.compareTo(a.occurredAtUtc);
           return time == 0 ? b.attemptId.compareTo(a.attemptId) : time;
         }),
       );
  final String ownerId;
  final QuizWord? word;
  final List<RecallLadderObservation> observations;
  RecallLadderObservation? get latest => observations.firstOrNull;
  RecallLadderStage get suggestedStage => suggestRecallLadderStage(latest);
  int observedCount(RecallLadderStage stage) =>
      observations.where((row) => row.stage == stage).length;
}

RecallLadderStage suggestRecallLadderStage(RecallLadderObservation? latest) {
  if (latest == null) return RecallLadderStage.exposure;
  if (latest.assisted) {
    return RecallLadderStage.values[latest.stage.index > 0
        ? latest.stage.index - 1
        : 0];
  }
  if (!latest.isCorrect || latest.stage == RecallLadderStage.speaking) {
    return latest.stage;
  }
  return RecallLadderStage.values[latest.stage.index + 1];
}

abstract interface class RecallLadderReader {
  Future<RecallLadderSnapshot> load({
    required String expectedOwnerId,
    String? wordId,
    required bool Function() stillCurrent,
  });
}
