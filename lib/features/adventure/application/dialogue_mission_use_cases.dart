import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../identity/application/owner_generation.dart';
import '../../learning/application/current_activity_evidence.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/context_practice.dart';
import '../../learning/domain/hint_policy.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/lexical_prompt_artifact_identity.dart';
import '../../learning_packs/application/personal_sets_use_cases.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../domain/adventure_session_plan.dart';
import '../domain/dialogue_mission.dart';

const dialogueActivityType = 'dialogueMission';

final class DialogueMissionRollout {
  const DialogueMissionRollout.implementedOff() : enabled = false;
  const DialogueMissionRollout.internal() : enabled = true;
  final bool enabled;
}

final class DialogueRun {
  DialogueRun._(
    this.owner,
    this.session,
    this.mission,
    this.coreHash,
    this.operationId,
    this.checkpointRevision,
    List<Map<String, Object?>> decisions,
    this.summary,
    this._capability,
  ) : decisions = List.unmodifiable(
        decisions.map((d) => Map<String, Object?>.unmodifiable(d)),
      );
  final OwnerGenerationToken owner;
  final QuizSession session;
  final DialogueMission mission;
  final String coreHash, operationId;
  final int checkpointRevision;
  final List<Map<String, Object?>> decisions;
  final LearningSessionSummary? summary;
  final Object _capability;
  DialogueNode get node => mission.node(
    decisions.isEmpty ? mission.start : decisions.last['next'] as String,
  );
  Map<String, Object?> state() => {
    'schemaVersion': 1,
    'kind': dialogueActivityType,
    'launchOperationId': operationId,
    'mission': mission.toJson(),
    'missionHash': mission.fingerprint,
    'coreHash': coreHash,
    'decisions': decisions,
  };
}

/// Coordinates authored choices with the existing Learning writer. The same
/// SQLite transaction commits both evidence and its immutable branch receipt.
/// Nothing here writes SRS, rewards, or research rows directly.
final class DialogueMissionUseCases {
  DialogueMissionUseCases({
    required this.sets,
    required this.learning,
    required this.evidence,
    required this.isAvailable,
  }) {
    final repository = learning.repository;
    if (repository is! DriftLearningRepository ||
        !identical(repository.database, database) ||
        !identical(evidence.learning, learning)) {
      throw ArgumentError(
        'Dialogue requires the canonical durable Learning authority',
      );
    }
  }
  final PersonalSetsUseCases sets;
  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter evidence;
  final bool Function() isAvailable;
  AppDatabase get database => sets.repository.database;
  int _generation = 0;
  Object _capability = Object();
  bool _disposed = false;
  void retire() {
    _generation++;
    _capability = Object();
  }

  void dispose() {
    _disposed = true;
    retire();
  }

  Future<T> _run<T>(
    OwnerGenerationToken owner,
    Future<T> Function() operation, {
    bool available = true,
  }) async {
    final generation = _generation;
    Future<void> fence() async {
      if (_disposed ||
          generation != _generation ||
          (available && !isAvailable())) {
        throw StateError('Dialogue retired');
      }
      await sets.ownerGeneration.requireCurrentAsync(owner);
      await DriftOwnerOperationGate(database).requireOwned(
        token: sets.ownerOperations.currentOperationVersion,
        nowUtc: sets.repository.nowUtc(),
      );
      if (_disposed ||
          generation != _generation ||
          (available && !isAvailable())) {
        throw StateError('Dialogue retired');
      }
    }

    await sets.ownerGeneration.requireCurrentAsync(owner);
    return sets.ownerOperations.run(AiCancellation(), (active) async {
      if (active != owner.ownerId) throw StateError('Dialogue owner changed');
      return database.transaction(() async {
        await fence();
        final result = await operation();
        await fence();
        return result;
      });
    });
  }

  Future<void> _admit(DialogueMission mission) async {
    if (mission.validate().isNotEmpty ||
        DialogueMissionInventory.find(mission.id, mission.fingerprint) ==
            null) {
      throw StateError('Unreviewed dialogue');
    }
    final artifact = await sets.repository.crosswalks.manifests.requireVerified(
      ContentIdentity(
        type: ContentType.lexicalMetadata,
        id: mission.wordId,
        revision: mission.contentRevision,
      ),
    );
    final m = artifact.manifest;
    if (m.checksumSha256 != mission.contentHash ||
        m.provenance != ContentProvenance.packaged ||
        m.reviewState != ContentReviewState.approved ||
        m.publicationState != ContentPublicationState.published ||
        m.reviewedAtUtc == null ||
        m.publishedAtUtc == null) {
      throw StateError('Dialogue content unavailable');
    }
    final entry = const ContextPracticeInventory().find(mission.wordId)!;
    final alternative = await sets.repository.crosswalks.manifests
        .requireVerified(
          ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: entry.distractorId,
            revision: 1,
          ),
        );
    if (alternative.manifest.checksumSha256 != entry.distractorArtifactHash ||
        alternative.manifest.reviewState != ContentReviewState.approved ||
        alternative.manifest.publicationState !=
            ContentPublicationState.published) {
      throw StateError('Dialogue alternative unavailable');
    }
  }

  Future<DialogueRun> start(
    OwnerGenerationToken owner, {
    required AdventureSessionPlanV1 plan,
    required DialogueMission mission,
    required String operationId,
  }) => _run(owner, () async {
    _id(operationId);
    if (plan.ownerId != owner.ownerId ||
        plan.configuration.ownerId != owner.ownerId ||
        plan.content.length != 1 ||
        plan.configuration.itemCount != 1 ||
        plan.content.single.id != mission.wordId ||
        plan.content.single.revision != mission.contentRevision ||
        plan.content.single.type != ContentType.lexicalMetadata) {
      throw StateError('Dialogue plan mismatch');
    }
    await _admit(mission);
    final matches = await database
        .customSelect(
          "SELECT DISTINCT aggregate_id FROM events_v2 WHERE owner_id = ? AND event_type = 'LearningActivityCheckpoint' AND json_extract(payload_json, '\$.state.kind') = 'dialogueMission' AND json_extract(payload_json, '\$.state.launchOperationId') = ?",
          variables: [Variable(owner.ownerId), Variable(operationId)],
        )
        .get();
    if (matches.isNotEmpty) {
      if (matches.length != 1) throw StateError('Ambiguous dialogue launch');
      final old = await _load(
        owner,
        matches.single.read<String>('aggregate_id'),
      );
      if (old.mission.fingerprint != mission.fingerprint ||
          old.coreHash != plan.contentChecksumsSha256[mission.wordId]) {
        throw StateError('Dialogue launch collision');
      }
      return old;
    }
    final coreHash = plan.contentChecksumsSha256[mission.wordId];
    if (coreHash == null) throw StateError('Missing canonical pin');
    final session = await learning.startCheckpointedQuiz(
      activityType: dialogueActivityType,
      limit: 1,
      pinnedContent: [
        PinnedQuizContent(
          identity: plan.content.single,
          checksumSha256: coreHash,
        ),
      ],
      // Dialogue is a distinct bounded recognition activity; the transient
      // Adventure presentation configuration is not a false timed-lesson claim.
      initialState: (session) => DialogueRun._(
        owner,
        session,
        mission,
        coreHash,
        operationId,
        1,
        [],
        null,
        _capability,
      ).state(),
    );
    if (session.isEmpty || session.ownerId != owner.ownerId) {
      throw StateError('Dialogue admission failed');
    }
    await _admit(mission);
    return _load(owner, session.id);
  });
  Future<DialogueRun> resume(OwnerGenerationToken owner, String sessionId) =>
      _run(owner, () => _load(owner, sessionId), available: false);
  Future<DialogueRun?> latest(OwnerGenerationToken owner) =>
      _run(owner, () async {
        final latest = await learning.loadActivityRecovery(
          activityType: dialogueActivityType,
          ownerId: owner.ownerId,
        );
        return latest == null ? null : _load(owner, latest.session.id);
      }, available: false);
  Future<DialogueRun> _load(
    OwnerGenerationToken owner,
    String sessionId,
  ) async {
    final recovery = await learning.loadExactActivityRecovery(
      ownerId: owner.ownerId,
      sessionId: sessionId,
      activityType: dialogueActivityType,
    );
    final j = recovery?.checkpoint?.state;
    if (recovery == null ||
        j == null ||
        j.length != 7 ||
        j['schemaVersion'] != 1 ||
        j['kind'] != dialogueActivityType) {
      throw StateError('Unsupported dialogue checkpoint');
    }
    final mission = DialogueMission.fromJson(
      Map<String, Object?>.from(j['mission'] as Map),
    );
    if (mission.validate().isNotEmpty ||
        mission.fingerprint != j['missionHash'] ||
        DialogueMissionInventory.find(mission.id, mission.fingerprint) ==
            null) {
      throw StateError('Dialogue pin mismatch');
    }
    final decisions = [
      for (final d in j['decisions'] as List)
        Map<String, Object?>.from(d as Map),
    ];
    if (decisions.length > mission.maximumTurns ||
        recovery.attempts.length != decisions.length) {
      throw StateError('Dialogue history mismatch');
    }
    var cursor = mission.start;
    final operations = <String>{};
    for (final (index, d) in decisions.indexed) {
      final n = mission.node(cursor);
      if (d.length != 8 ||
          d['node'] != cursor ||
          !operations.add(d['operationId'] as String)) {
        throw StateError('Invalid dialogue decision');
      }
      final choice = n.choices.singleWhere((c) => c.id == d['choice']);
      final attempt = recovery.attempts.singleWhere(
        (a) => a.id == d['evidenceId'],
      );
      if (d['next'] != choice.next ||
          d['correct'] != choice.correct ||
          d['assisted'] != n.assisted ||
          d['ordinal'] != index + 1 ||
          attempt.wordId != mission.wordId ||
          attempt.promptMode != 'clozeSelected' ||
          attempt.evidenceContext.hintLevel != (n.assisted ? 1 : 0) ||
          attempt.evidenceContext.contentRevision !=
              LexicalPromptArtifactResolver.formatEvidenceContentRevision(
                promptMode: 'clozeSelected',
                wordId: mission.wordId,
                revision: mission.contentRevision,
                checksumSha256: mission.contentHash,
              ) ||
          attempt.providerProvenance !=
              'reviewed-lexical-example:${mission.contentRevision}:${mission.contentHash}' ||
          attempt.isCorrect != choice.correct ||
          attempt.attemptNumber != index + 1 ||
          attempt.evidenceContext.evidenceClass !=
              (n.assisted
                  ? EvidenceClass.guidedPractice
                  : EvidenceClass.recognition)) {
        throw StateError('Dialogue evidence mismatch');
      }
      cursor = choice.next;
    }
    final checkpoint = recovery.checkpoint!;
    final completed = recovery.session.state == 'completed';
    if (checkpoint.revision != 1 + decisions.length + (completed ? 1 : 0) ||
        completed &&
            (!mission.node(cursor).terminal ||
                !checkpoint.terminalAcknowledged)) {
      throw StateError('Dialogue revision mismatch');
    }
    final session = await learning.reconstructPinnedQuizSession(
      session: recovery.session,
      content: [
        ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: mission.wordId,
          revision: mission.contentRevision,
        ),
      ],
      contentChecksumsSha256: {mission.wordId: j['coreHash'] as String},
    );
    return DialogueRun._(
      owner,
      session,
      mission,
      j['coreHash'] as String,
      j['launchOperationId'] as String,
      checkpoint.revision,
      decisions,
      completed ? recovery.session : null,
      _capability,
    );
  }

  Future<DialogueRun> choose(
    DialogueRun run, {
    required String nodeId,
    required String choiceId,
    required String operationId,
    int responseTimeMs = 0,
  }) => _run(run.owner, () async {
    if (!identical(run._capability, _capability)) {
      throw StateError('Dialogue handle retired');
    }
    _id(operationId);
    final current = await _load(run.owner, run.session.id);
    for (final decision in current.decisions) {
      if (decision['operationId'] == operationId) {
        if (decision['node'] != nodeId || decision['choice'] != choiceId) {
          throw StateError('Dialogue decision collision');
        }
        return current;
      }
    }
    if (current.summary != null ||
        current.node.terminal ||
        current.node.id != nodeId ||
        current.checkpointRevision != run.checkpointRevision ||
        current.decisions.length >= current.mission.maximumTurns) {
      throw StateError('Stale dialogue choice');
    }
    await _admit(current.mission);
    final choice = current.node.choices.singleWhere((c) => c.id == choiceId);
    final assisted = current.node.assisted;
    final pending = evidence.captureCloze(
      ownerId: run.owner.ownerId,
      sessionId: run.session.id,
      wordId: current.mission.wordId,
      isCorrect: choice.correct,
      responseTimeMs: responseTimeMs,
      attemptNumber: current.decisions.length + 1,
      contentRevision: current.mission.contentRevision,
      checksumSha256: current.mission.contentHash,
      typed: false,
      classification: HintEvidenceClassification(
        evidenceClass: assisted
            ? EvidenceClass.guidedPractice
            : EvidenceClass.recognition,
        hintLevel: assisted ? 1 : 0,
      ),
    );
    await pending.record();
    final next = DialogueRun._(
      run.owner,
      current.session,
      current.mission,
      current.coreHash,
      current.operationId,
      current.checkpointRevision + 1,
      [
        ...current.decisions,
        {
          'operationId': operationId,
          'node': nodeId,
          'choice': choiceId,
          'next': choice.next,
          'correct': choice.correct,
          'assisted': assisted,
          'ordinal': current.decisions.length + 1,
          'evidenceId': pending.sourceEvidenceId,
        },
      ],
      null,
      _capability,
    );
    await learning.appendActivityCheckpoint(
      LearningActivityCheckpoint(
        sessionId: run.session.id,
        activityType: dialogueActivityType,
        revision: next.checkpointRevision,
        occurredAtUtc: pending.occurredAtUtc,
        state: next.state(),
      ),
      ownerId: run.owner.ownerId,
    );
    await _admit(current.mission);
    return _load(run.owner, run.session.id);
  });
  Future<DialogueRun> complete(DialogueRun run) => _run(run.owner, () async {
    if (!identical(run._capability, _capability)) {
      throw StateError('Dialogue handle retired');
    }
    final current = await _load(run.owner, run.session.id);
    if (current.summary != null) return current;
    if (!current.node.terminal) throw StateError('Dialogue has not terminated');
    final summary = await learning.finishSession(
      run.session.id,
      ownerId: run.owner.ownerId,
    );
    await learning.appendActivityCheckpoint(
      LearningActivityCheckpoint(
        sessionId: run.session.id,
        activityType: dialogueActivityType,
        revision: current.checkpointRevision + 1,
        occurredAtUtc: summary.endedAtUtc!,
        terminalAtUtc: summary.endedAtUtc,
        terminalAcknowledged: true,
        state: current.state(),
      ),
      ownerId: run.owner.ownerId,
    );
    return _load(run.owner, run.session.id);
  }, available: false);

  /// Exit remains available without withdrawn content or an enabled entry.
  /// The Learning lifecycle owns abandonment and retains committed history.
  Future<LearningSessionSummary> abandon(
    OwnerGenerationToken owner,
    String sessionId,
  ) => _run(owner, () async {
    final row =
        await (database.select(database.learningSessions)..where(
              (r) =>
                  r.ownerId.equals(owner.ownerId) &
                  r.id.equals(sessionId) &
                  r.activityType.equals(dialogueActivityType),
            ))
            .getSingleOrNull();
    if (row == null) throw StateError('Dialogue session unavailable');
    final when = row.state == 'abandoned' && row.endedAtUtcMs != null
        ? DateTime.fromMillisecondsSinceEpoch(row.endedAtUtcMs!, isUtc: true)
        : sets.repository.nowUtc();
    return learning.abandonSession(
      ownerId: owner.ownerId,
      sessionId: sessionId,
      abandonedAtUtc: when,
    );
  }, available: false);
}

void _id(String value) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.length > 200 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw ArgumentError('Invalid dialogue operation');
  }
}
