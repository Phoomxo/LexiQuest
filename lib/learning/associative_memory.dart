import 'association_prompt.dart';
import 'association_record.dart';
import 'deletion_tombstone.dart';
import 'learning_commit.dart';
import 'learning_record_validation.dart';
import 'learning_repository.dart';
import 'secure_id_generator.dart';

typedef LearningClock = DateTime Function();

final class CueRevealEvidence {
  CueRevealEvidence({
    required this.unaidedRecallCompleted,
    required this.answerWasCorrect,
    required this.confidence,
    required this.responseTime,
  }) {
    if (confidence < 1 || confidence > 5) {
      throw ArgumentError.value(confidence, 'confidence', 'must be 1 to 5');
    }
    if (responseTime.isNegative) {
      throw ArgumentError.value(
        responseTime,
        'responseTime',
        'must not be negative',
      );
    }
  }

  final bool unaidedRecallCompleted;
  final bool answerWasCorrect;
  final int confidence;
  final Duration responseTime;
}

final class AssociationCuePolicy {
  AssociationCuePolicy({
    this.lowConfidenceThreshold = 2,
    this.slowResponseThreshold = const Duration(seconds: 4),
  }) {
    if (lowConfidenceThreshold < 1 || lowConfidenceThreshold > 5) {
      throw ArgumentError.value(
        lowConfidenceThreshold,
        'lowConfidenceThreshold',
        'must be 1 to 5',
      );
    }
    if (slowResponseThreshold.isNegative) {
      throw ArgumentError.value(
        slowResponseThreshold,
        'slowResponseThreshold',
        'must not be negative',
      );
    }
  }

  final int lowConfidenceThreshold;
  final Duration slowResponseThreshold;

  bool shouldReveal(
    CueRevealEvidence evidence, {
    bool sessionPolicyAllowsCue = false,
  }) {
    if (!evidence.unaidedRecallCompleted) {
      return false;
    }
    return !evidence.answerWasCorrect ||
        evidence.confidence <= lowConfidenceThreshold ||
        evidence.responseTime > slowResponseThreshold ||
        sessionPolicyAllowsCue;
  }
}

final class AssociationCueSet {
  AssociationCueSet({
    required this.isVisible,
    required List<AssociationPrompt> curatedPrompts,
    required List<AssociationRecord> privateAssociations,
  }) : curatedPrompts = List<AssociationPrompt>.unmodifiable(curatedPrompts),
       privateAssociations = List<AssociationRecord>.unmodifiable(
         privateAssociations,
       );

  factory AssociationCueSet.hidden() {
    return AssociationCueSet(
      isVisible: false,
      curatedPrompts: const [],
      privateAssociations: const [],
    );
  }

  final bool isVisible;
  final List<AssociationPrompt> curatedPrompts;
  final List<AssociationRecord> privateAssociations;
}

enum AssociationCueSource { curatedPrompt, privateAssociation }

enum AssociationCueOutcome { selected, skipped }

final class AssociationCueDecision {
  const AssociationCueDecision({
    required this.outcome,
    this.cueId,
    this.source,
  });

  final AssociationCueOutcome outcome;
  final String? cueId;
  final AssociationCueSource? source;

  bool get countsAsCorrectAnswer => false;
}

enum AssociativeMemoryErrorCode { associationNotFound }

final class AssociativeMemoryException implements Exception {
  const AssociativeMemoryException(this.code);

  final AssociativeMemoryErrorCode code;

  @override
  String toString() => 'AssociativeMemoryException($code)';
}

final class AssociativeMemory {
  AssociativeMemory({
    required this.repository,
    required this.reader,
    required this.promptCatalog,
    required this.idGenerator,
    required this.clock,
    AssociationCuePolicy? cuePolicy,
  }) : cuePolicy = cuePolicy ?? AssociationCuePolicy();

  final LearningRepository repository;
  final LearningReader reader;
  final AssociationPromptCatalog promptCatalog;
  final SecureIdGenerator idGenerator;
  final LearningClock clock;
  final AssociationCuePolicy cuePolicy;

  Future<AssociationRecord> create({
    required String ownerId,
    required String wordKey,
    required AssociationCueType cueType,
    required String cueText,
  }) async {
    final now = clock().toUtc();
    final record = AssociationRecord(
      associationId: idGenerator.nextId(),
      ownerId: ownerId,
      wordKey: wordKey,
      cueType: cueType,
      cueText: cueText,
      origin: AssociationOrigin.userCreated,
      createdAtUtc: now,
      updatedAtUtc: now,
    );
    await repository.commit(
      LearningCommit(
        commitId: idGenerator.nextId(),
        ownerId: ownerId,
        recordedAtUtc: now,
        associations: [record],
      ),
    );
    return record;
  }

  Future<AssociationRecord> edit({
    required String ownerId,
    required String wordKey,
    required String associationId,
    required AssociationCueType cueType,
    required String cueText,
  }) async {
    final existing = await _findPrivate(
      ownerId: ownerId,
      wordKey: wordKey,
      associationId: associationId,
    );
    final now = clock().toUtc();
    final updated = AssociationRecord(
      associationId: existing.associationId,
      ownerId: existing.ownerId,
      wordKey: existing.wordKey,
      cueType: cueType,
      cueText: cueText,
      origin: existing.origin,
      strength: existing.strength,
      successCount: existing.successCount,
      failureCount: existing.failureCount,
      createdAtUtc: existing.createdAtUtc,
      updatedAtUtc: now,
      schemaVersion: existing.schemaVersion,
    );
    await repository.commit(
      LearningCommit(
        commitId: idGenerator.nextId(),
        ownerId: ownerId,
        recordedAtUtc: now,
        associations: [updated],
      ),
    );
    return updated;
  }

  Future<void> delete({
    required String ownerId,
    required String wordKey,
    required String associationId,
  }) async {
    await _findPrivate(
      ownerId: ownerId,
      wordKey: wordKey,
      associationId: associationId,
    );
    final now = clock().toUtc();
    final tombstone = DeletionTombstone(
      tombstoneId: idGenerator.nextId(),
      ownerId: ownerId,
      entityType: TombstoneEntityType.association,
      entityId: associationId,
      deletedAtUtc: now,
    );
    await repository.commit(
      LearningCommit(
        commitId: idGenerator.nextId(),
        ownerId: ownerId,
        recordedAtUtc: now,
        tombstones: [tombstone],
      ),
    );
  }

  Future<AssociationCueSet> cuesForRecall({
    required String ownerId,
    required String wordKey,
    required CueRevealEvidence evidence,
    bool sessionPolicyAllowsCue = false,
  }) async {
    LearningRecordValidation.identifier(ownerId, 'ownerId');
    LearningRecordValidation.identifier(wordKey, 'wordKey');
    if (!cuePolicy.shouldReveal(
      evidence,
      sessionPolicyAllowsCue: sessionPolicyAllowsCue,
    )) {
      return AssociationCueSet.hidden();
    }
    final privateAssociations = await reader.readAssociations(
      ownerId: ownerId,
      wordKey: wordKey,
    );
    return AssociationCueSet(
      isVisible: true,
      curatedPrompts: promptCatalog.forWord(wordKey),
      privateAssociations: privateAssociations,
    );
  }

  AssociationCueDecision select({
    required String cueId,
    required AssociationCueSource source,
  }) {
    LearningRecordValidation.identifier(cueId, 'cueId');
    return AssociationCueDecision(
      outcome: AssociationCueOutcome.selected,
      cueId: cueId,
      source: source,
    );
  }

  AssociationCueDecision skip() {
    return const AssociationCueDecision(outcome: AssociationCueOutcome.skipped);
  }

  Future<AssociationRecord> _findPrivate({
    required String ownerId,
    required String wordKey,
    required String associationId,
  }) async {
    final records = await reader.readAssociations(
      ownerId: ownerId,
      wordKey: wordKey,
    );
    for (final record in records) {
      if (record.associationId == associationId) {
        return record;
      }
    }
    throw const AssociativeMemoryException(
      AssociativeMemoryErrorCode.associationNotFound,
    );
  }
}
