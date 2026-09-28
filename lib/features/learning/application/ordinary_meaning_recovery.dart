import 'dart:convert';

import '../domain/learning_models.dart';
import '../domain/contrastive_explanation.dart';
import '../domain/learning_repository.dart';
import '../domain/meaning_quiz_composition.dart';
import '../domain/ordinary_meaning_plan.dart';
import '../domain/session_configuration.dart';
import 'current_activity_evidence.dart';
import 'learning_use_cases.dart';

/// Ordinary meaning progress is stored by the existing Learning authority.
/// The frozen admission remains intact; replay always uses the captured command.
final class OrdinaryMeaningProgress {
  OrdinaryMeaningProgress({
    required this.plan,
    this.index = 0,
    this.phase = 'awaitingAnswer',
    this.selected,
    this.evidence,
    this.closeAt,
  });

  final OrdinaryMeaningPlan plan;
  final int index;
  final String phase;
  final String? selected;
  final FrozenPendingCurrentActivityEvidence? evidence;
  final DateTime? closeAt;

  Map<String, Object?> toJson() => {
    'kind': OrdinaryMeaningPlan.kind,
    'version': 2,
    'plan': plan.toJson(),
    'progress': {
      'index': index,
      'phase': phase,
      'selected': selected,
      'evidence': evidence?.toJson(),
      'closeAt': closeAt?.toIso8601String(),
    },
  };

  static OrdinaryMeaningProgress decode(Map<String, Object?> value) {
    if (utf8.encode(jsonEncode(value)).length > OrdinaryMeaningPlan.maxBytes) {
      throw const FormatException('Ordinary progress exceeds byte budget');
    }
    if (value['version'] == 1) {
      return OrdinaryMeaningProgress(plan: OrdinaryMeaningPlan.decode(value));
    }
    Map<String, Object?> object(Object? raw, Set<String> keys) {
      if (raw is! Map ||
          raw.length != keys.length ||
          raw.keys.any((key) => !keys.contains(key))) {
        throw const FormatException('Ordinary progress shape is invalid');
      }
      return raw.cast<String, Object?>();
    }

    object(value, {'kind', 'version', 'plan', 'progress'});
    if (value['kind'] != OrdinaryMeaningPlan.kind ||
        value['version'] != 2 ||
        value['plan'] is! Map) {
      throw const FormatException('Ordinary progress version is invalid');
    }
    final plan = OrdinaryMeaningPlan.decode(
      (value['plan'] as Map).cast<String, Object?>(),
    );
    final p = object(value['progress'], {
      'index',
      'phase',
      'selected',
      'evidence',
      'closeAt',
    });
    final index = p['index'];
    final phase = p['phase'];
    final selected = p['selected'];
    if (index is! int ||
        index < 0 ||
        index >= plan.questions.length ||
        phase is! String ||
        !{
          'awaitingAnswer',
          'pending',
          'answered',
          'skipped',
          'closing',
        }.contains(phase) ||
        (selected != null &&
            !plan.questions[index].options.contains(selected))) {
      throw const FormatException('Ordinary progress state is invalid');
    }
    final raw = p['evidence'];
    if (raw != null && raw is! Map) {
      throw const FormatException('Invalid occurrence');
    }
    final evidence = raw == null
        ? null
        : FrozenPendingCurrentActivityEvidence.fromJson(
            (raw as Map).cast<String, Object?>(),
          );
    final requiresEvidence = phase == 'pending' || phase == 'answered';
    if ((requiresEvidence && evidence == null) ||
        (!requiresEvidence && phase != 'closing' && evidence != null) ||
        (evidence != null && selected == null) ||
        (phase == 'closing' && evidence == null && selected != null) ||
        (phase == 'skipped' && selected != null)) {
      throw const FormatException('Ordinary occurrence phase mismatch');
    }
    if (evidence != null) {
      final q = plan.questions[index];
      final input = q.direction == MeaningQuizDirection.wordToMeaning
          ? CurrentActivityInput.meaningMultipleChoice
          : CurrentActivityInput.meaningToWordMultipleChoice;
      final promptMode = input == CurrentActivityInput.meaningMultipleChoice
          ? 'meaningChoice'
          : 'wordChoice';
      final expectedRevision = q.evidenceChecksumSha256 == null
          ? 'built-in-v1'
          : contrastiveEvidenceContentRevision(
              promptMode: promptMode,
              wordId: q.word.id,
              revision: q.contrastiveIdentity!.revision,
              checksumSha256: q.evidenceChecksumSha256!,
            );
      final contrastive = evidence.contrastiveFeedback;
      if (evidence.ownerId != plan.session.ownerId ||
          evidence.sessionId != plan.session.id ||
          evidence.wordId != q.word.id ||
          evidence.attemptNumber != index + 1 ||
          evidence.input != input ||
          evidence.isCorrect != (selected == q.correctOption) ||
          evidence.hintLevel != 0 ||
          evidence.actorIdentity != plan.session.ownerId ||
          evidence.contentRevision != expectedRevision ||
          evidence.promptMode != promptMode ||
          (contrastive != null &&
              (contrastive.selectedDistractorId !=
                      q.optionIdentity(selected as String) ||
                  contrastive.correctOptionId !=
                      q.optionIdentity(q.correctOption) ||
                  contrastive.manifestChecksumSha256 !=
                      q.contrastiveChecksumSha256))) {
        throw const FormatException('Ordinary occurrence binding mismatch');
      }
    }
    final rawClose = p['closeAt'];
    final closeAt = rawClose is String ? DateTime.tryParse(rawClose) : null;
    if ((phase == 'closing') != (closeAt != null) ||
        (closeAt != null &&
            (!closeAt.isUtc ||
                index != plan.questions.length - 1 ||
                closeAt.isBefore(plan.session.startedAtUtc!))) ||
        (rawClose != null && closeAt == null)) {
      throw const FormatException('Ordinary close identity mismatch');
    }
    return OrdinaryMeaningProgress(
      plan: plan,
      index: index,
      phase: phase,
      selected: selected as String?,
      evidence: evidence,
      closeAt: closeAt,
    );
  }

  QuizSession get session => QuizSession(
    id: plan.session.id,
    ownerId: plan.session.ownerId,
    startedAtUtc: plan.session.startedAtUtc,
    questions: plan.session.questions,
    sessionConfiguration: plan.session.sessionConfiguration,
    ordinaryMeaningPlan: plan,
  );
}

final class OrdinaryMeaningRecovery {
  OrdinaryMeaningRecovery._(this.learning, this.recovery, this.progress);
  final LearningUseCases learning;
  LearningActivityRecovery recovery;
  OrdinaryMeaningProgress progress;
  LearningActivityCheckpoint? _pending;

  Future<void> reconcilePending(bool Function() accepts) async {
    final pending = _pending;
    if (pending != null) {
      await save(
        OrdinaryMeaningProgress.decode(pending.state),
        accepts,
        terminalAcknowledged: pending.terminalAcknowledged,
      );
    }
  }

  Future<void> requireCurrent(bool Function() accepts) async {
    if (!accepts()) throw StateError('Ordinary route retired');
    await (learning.repository as OrdinaryMeaningOperationRepository)
        .requireOrdinaryOwner(progress.plan.session.ownerId!);
    if (!accepts()) throw StateError('Ordinary route retired');
  }

  Future<void> acknowledgeClose(bool Function() accepts) =>
      save(progress, accepts, terminalAcknowledged: true);

  Future<T> run<T>(Future<T> Function() operation, bool Function() accepts) {
    final repository = learning.repository;
    if (repository is! OrdinaryMeaningOperationRepository) {
      throw StateError('Ordinary operation authority unavailable');
    }
    return (repository as OrdinaryMeaningOperationRepository)
        .runOrdinaryOperation(
          ownerId: progress.plan.session.ownerId!,
          checkpoint: recovery.checkpoint!,
          acceptsOperation: accepts,
          operation: operation,
        );
  }

  static Future<OrdinaryMeaningRecovery> load({
    required LearningUseCases learning,
    required String ownerId,
    required String sessionId,
    bool Function()? acceptsOperation,
  }) async {
    void guard() {
      if (acceptsOperation?.call() == false) {
        throw StateError('Ordinary route retired');
      }
    }

    Future<void> owner() async {
      guard();
      final authority = learning.repository;
      if (authority is! OrdinaryMeaningOperationRepository) {
        throw StateError('Ordinary owner authority unavailable');
      }
      await (authority as OrdinaryMeaningOperationRepository)
          .requireOrdinaryOwner(ownerId);
      guard();
    }

    await owner();
    final recovery = await learning.loadExactActivityRecovery(
      ownerId: ownerId,
      sessionId: sessionId,
      activityType: 'quiz',
    );
    await owner();
    if (recovery == null ||
        recovery.checkpoint == null ||
        recovery.checkpoint!.terminalAcknowledged ||
        !{'active', 'completed'}.contains(recovery.session.state)) {
      throw StateError('Exact ordinary session unavailable');
    }
    final progress = OrdinaryMeaningProgress.decode(recovery.checkpoint!.state);
    final plan = progress.plan;
    final summary = recovery.session;
    if (plan.session.id != summary.id ||
        plan.session.ownerId != ownerId ||
        plan.session.startedAtUtc != summary.startedAtUtc ||
        plan.session.sessionConfiguration?.stableSerialization !=
            summary.sessionConfiguration?.stableSerialization ||
        (recovery.checkpoint!.state['version'] == 1 &&
            (recovery.checkpoint!.revision != 1 ||
                recovery.attempts.isNotEmpty)) ||
        (summary.state == 'completed' && progress.phase != 'closing')) {
      throw StateError('Ordinary recovery binding changed');
    }
    final repository = learning.repository;
    if (repository is! PinnedLearningContentRepository ||
        repository is! OrdinaryMeaningContentRepository) {
      throw StateError('Ordinary content authority unavailable');
    }
    final content = await (repository as PinnedLearningContentRepository)
        .listExactPinnedQuizWords(ownerId: ownerId, content: plan.pins);
    await owner();
    final lexical = await (repository as OrdinaryMeaningContentRepository)
        .readMeaningLexicalWords(plan.questions.map((q) => q.word.id).toList());
    await owner();
    plan.validateCurrentContent(
      content,
      composeMeaningQuiz(
        plan.session,
        direction:
            plan.session.sessionConfiguration?.direction ??
            SessionDirection.mixed,
        lexicalWords: lexical,
      ),
    );
    for (final attempt in recovery.attempts) {
      if (attempt.attemptNumber < 1 ||
          attempt.attemptNumber > progress.index + 1 ||
          attempt.wordId != plan.questions[attempt.attemptNumber - 1].word.id ||
          (attempt.attemptNumber == progress.index + 1 &&
              attempt.id != progress.evidence?.sourceEvidenceId)) {
        throw StateError('Ordinary progress conflicts with canonical attempts');
      }
    }
    if ((progress.phase == 'answered' || progress.phase == 'closing') &&
        progress.evidence != null &&
        !recovery.attempts.any(
          (a) => a.id == progress.evidence!.sourceEvidenceId,
        )) {
      throw StateError('Ordinary feedback has no committed occurrence');
    }
    guard();
    return OrdinaryMeaningRecovery._(learning, recovery, progress);
  }

  Future<void> save(
    OrdinaryMeaningProgress next,
    bool Function() accepts, {
    bool terminalAcknowledged = false,
  }) async {
    if (_pending == null &&
        jsonEncode(progress.toJson()) == jsonEncode(next.toJson()) &&
        recovery.checkpoint!.terminalAcknowledged == terminalAcknowledged) {
      await run(() async {}, accepts);
      await requireCurrent(accepts);
      return;
    }
    // Retain an unacknowledged checkpoint, including its occurrence and revision.
    final checkpoint = _pending ??= LearningActivityCheckpoint(
      sessionId: progress.plan.session.id,
      activityType: 'quiz',
      revision: recovery.checkpoint!.revision + 1,
      occurredAtUtc: learning.nowUtc(),
      state: next.toJson(),
      terminalAtUtc: next.closeAt,
      terminalAcknowledged: terminalAcknowledged,
    );
    if (jsonEncode(checkpoint.state) != jsonEncode(next.toJson())) {
      throw StateError('An exact ordinary checkpoint retry is required');
    }
    if (!accepts()) throw StateError('Ordinary route retired');
    await learning.appendActivityCheckpoint(
      checkpoint,
      ownerId: progress.plan.session.ownerId,
    );
    await requireCurrent(accepts);
    progress = next;
    recovery = LearningActivityRecovery(
      session: recovery.session,
      checkpoint: checkpoint,
      attempts: recovery.attempts,
    );
    _pending = null;
  }
}
