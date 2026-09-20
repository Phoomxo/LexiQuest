import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../identity/application/owner_generation.dart';
import '../../learning/application/current_activity_evidence.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/data/drift_learning_repository.dart';
import '../../learning/domain/context_practice.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/hint_policy.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/lexical_prompt_artifact_identity.dart';
import '../../learning_packs/application/personal_sets_use_cases.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../learning_packs/domain/personal_sets.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../../vocabulary/data/drift_vocabulary_repository.dart';
import '../../vocabulary/data/packaged_starter_access.dart';
import '../domain/transfer_probe.dart';

const transferProbeActivityType = 'transferProbe';

final class TransferProbeRollout {
  const TransferProbeRollout.implementedOff() : enabled = false;
  const TransferProbeRollout.internal() : enabled = true;
  final bool enabled;
}

final class TransferProbeOffer {
  TransferProbeOffer._(this.origin, this.item);
  final Map<String, Object?> origin;
  final TransferProbeItem item;
  String get originAttemptId => origin['attemptId'] as String;
  DateTime get originUtc => DateTime.parse(origin['occurredAtUtc'] as String);
}

final class TransferProbeRun {
  TransferProbeRun._(
    this.owner,
    this.session,
    this.offer,
    this.operationId,
    this.revision,
    this.assisted,
    this.result,
    this.summary,
    this._capability,
  ) : clock = Stopwatch()..start();
  final OwnerGenerationToken owner;
  final QuizSession session;
  final TransferProbeOffer offer;
  final String operationId;
  final int revision;
  final bool assisted;
  final Map<String, Object?>? result;
  final LearningSessionSummary? summary;
  final Object _capability;
  final Stopwatch clock;
  DateTime? _sampledAtUtc;
  TransferProbeItem get item => offer.item;
  bool? get correct => result?['correct'] as bool?;
  ProbeTiming get timing => ProbeTiming.unverified;
  Map<String, Object?> state() => {
    'schemaVersion': 1,
    'kind': transferProbeActivityType,
    'policy': TransferProbePolicy.revision,
    'inventoryHash': TransferProbeInventory.fingerprint,
    'origin': offer.origin,
    'item': item.toJson(),
    'launchOperationId': operationId,
    'assisted': assisted,
    'result': result,
  };
}

/// Owner-fenced adapter into the canonical Learning transaction. Supplemental
/// context identity does not reinterpret old evidence or research instruments.
final class TransferProbeUseCases {
  TransferProbeUseCases({
    required this.sets,
    required this.learning,
    required this.evidence,
    required this.isAvailable,
  }) {
    final r = learning.repository;
    if (r is! DriftLearningRepository ||
        !identical(r.database, database) ||
        !identical(evidence.learning, learning)) {
      throw ArgumentError('Probe requires canonical durable Learning');
    }
  }
  final PersonalSetsUseCases sets;
  final LearningUseCases learning;
  final CurrentActivityEvidenceAdapter evidence;
  final bool Function() isAvailable;
  AppDatabase get database => sets.repository.database;
  Object _capability = Object();
  bool _disposed = false;
  void retire() {
    _capability = Object();
  }

  void dispose() {
    _disposed = true;
    retire();
  }

  Future<T> _run<T>(
    OwnerGenerationToken owner,
    Future<T> Function() action, {
    bool available = true,
  }) async {
    final capability = _capability;
    Future<void> fence() async {
      if (_disposed ||
          !identical(capability, _capability) ||
          available && !isAvailable()) {
        throw StateError('Probe retired');
      }
      await sets.ownerGeneration.requireCurrentAsync(owner);
      await DriftOwnerOperationGate(database).requireOwned(
        token: sets.ownerOperations.currentOperationVersion,
        nowUtc: sets.repository.nowUtc(),
      );
      if (_disposed ||
          !identical(capability, _capability) ||
          available && !isAvailable()) {
        throw StateError('Probe retired');
      }
    }

    await sets.ownerGeneration.requireCurrentAsync(owner);
    return sets.ownerOperations.run(AiCancellation(), (active) async {
      if (active != owner.ownerId) throw StateError('Probe owner changed');
      return database.transaction(() async {
        await fence();
        final result = await action();
        await fence();
        return result;
      });
    });
  }

  Future<Map<String, Object?>> _origin(
    OwnerGenerationToken owner,
    String sessionId,
    String attemptId, {
    bool admit = true,
  }) async {
    final recovery = await learning.loadExactActivityRecovery(
      ownerId: owner.ownerId,
      sessionId: sessionId,
      activityType: 'contextPractice',
    );
    final state = recovery?.checkpoint?.state;
    if (recovery == null ||
        state == null ||
        state.length != 7 ||
        state['schemaVersion'] != 1 ||
        state['kind'] != 'contextPractice' ||
        state['inventoryRevision'] != ContextPracticeInventory.revision ||
        state['inventoryHash'] != ContextPracticeInventory.fingerprint ||
        !['typed', 'selected'].contains(state['inputMode'])) {
      throw StateError('Origin context unavailable');
    }
    final a = recovery.attempts.singleWhere((a) => a.id == attemptId);
    final saved = PersonalSetRevision.fromJson(
      Map<String, Object?>.from(state['personalSetRevision'] as Map),
    );
    final ref = saved.members.singleWhere((r) => r.wordId == a.wordId);
    final entry = const ContextPracticeInventory().find(a.wordId);
    final crosswalk = await sets.repository.crosswalks.requirePinned(
      saved.crosswalkPin,
    );
    final pin = crosswalk.resolve(ref);
    final mode = state['inputMode'] == 'typed' ? 'clozeTyped' : 'clozeSelected';
    final artifact = LexicalPromptArtifactResolver.resolveForAdapter(
      promptMode: mode,
      wordId: ref.wordId,
      coreRevision: pin.wordRevision,
      coreChecksumSha256: pin.wordChecksumSha256,
      verifiedArtifactRevision: 1,
      verifiedArtifactChecksumSha256: ref.lexicalArtifactHash,
    );
    if (entry == null ||
        ref.senseKey != 'starter-object-v1' ||
        ref.senseRevision != 1 ||
        ref.lexicalArtifactHash != entry.artifactHash ||
        pin.wordRevision != 1 ||
        a.promptMode != mode ||
        a.evidenceContext.contentRevision !=
            artifact?.evidenceContentRevision ||
        a.evidenceContext.protocolId != null ||
        a.occurredAtUtc.isBefore(recovery.session.startedAtUtc)) {
      throw StateError('Origin evidence mismatch');
    }
    if (admit) {
      final words = await DriftVocabularyRepository(
        database,
        contentManifests: sets.repository.crosswalks.manifests,
      ).readPinnedByIds([ref.wordId]);
      final lexical = await sets.repository.crosswalks.manifests
          .requireVerified(
            ContentIdentity(
              type: ContentType.lexicalMetadata,
              id: ref.wordId,
              revision: 1,
            ),
          );
      final categories =
          await (database.select(database.vocabularyCategories)..where(
                (c) =>
                    PackagedStarterAccess.categoriesFor(
                      database,
                      owner.ownerId,
                    ) &
                    c.isDeleted.equals(false) &
                    c.id.equals(words.single.categoryId),
              ))
              .get();
      crosswalk.requireScored(
        ref,
        word: words.single,
        categoryAvailable: categories.length == 1,
        lexicalArtifact: lexical,
      );
    }
    return Map.unmodifiable({
      'sessionId': sessionId,
      'attemptId': attemptId,
      'wordId': ref.wordId,
      'occurredAtUtc': a.occurredAtUtc.toIso8601String(),
      'contentRevision': 1,
      'coreHash': pin.wordChecksumSha256,
      'lexicalHash': ref.lexicalArtifactHash,
      'sense': ref.toJson(),
      'setId': saved.setId,
      'setRevision': saved.revision,
      'setHash': saved.payloadHash,
      'contextHash': sha256.convert(utf8.encode(entry.sentence)).toString(),
      'promptMode': a.promptMode,
      'assistance': a.evidenceContext.hintLevel,
      'evidenceClass': a.evidenceContext.evidenceClass.name,
      'evidenceRevision': a.evidenceContext.contentRevision,
    });
  }

  Future<List<TransferProbeOffer>> offers(
    OwnerGenerationToken owner,
  ) => _run(owner, () async {
    final rows = await database
        .customSelect(
          "SELECT a.id, a.session_id FROM answer_attempts a JOIN learning_sessions s ON s.id=a.session_id AND s.owner_id=a.owner_id WHERE a.owner_id=? AND s.activity_type='contextPractice' ORDER BY a.occurred_at_utc_ms DESC, a.id DESC LIMIT 100",
          variables: [Variable(owner.ownerId)],
        )
        .get();
    final result = <TransferProbeOffer>[];
    final words = <String>{};
    for (final row in rows) {
      final origin = await _origin(
        owner,
        row.read<String>('session_id'),
        row.read<String>('id'),
      );
      if (!words.add(origin['wordId'] as String)) continue;
      for (final item in TransferProbeInventory.items.where(
        (i) => i.wordId == origin['wordId'],
      )) {
        final offer = TransferProbeOffer._(origin, item);
        if (_timing(offer) == ProbeTiming.unverified &&
            !(await _used(owner, item))) {
          result.add(offer);
        }
      }
    }
    return List.unmodifiable(result);
  });
  ProbeTiming _timing(TransferProbeOffer offer) => TransferProbePolicy.evaluate(
    origin: offer.originUtc,
    now: sets.repository.nowUtc(),
    distinct: offer.item.contextHash != offer.origin['contextHash'],
  );
  Future<bool> _used(
    OwnerGenerationToken owner,
    TransferProbeItem item,
  ) async =>
      (await database
              .customSelect(
                "SELECT 1 FROM events_v2 WHERE owner_id=? AND event_type='LearningActivityCheckpoint' AND json_extract(payload_json, '\$.state.kind')='transferProbe' AND json_extract(payload_json, '\$.state.item.contextHash')=? LIMIT 1",
                variables: [
                  Variable(owner.ownerId),
                  Variable(item.contextHash),
                ],
              )
              .get())
          .isNotEmpty;

  Future<TransferProbeRun> start(
    OwnerGenerationToken owner, {
    required TransferProbeOffer offer,
    required String operationId,
  }) => _run(owner, () async {
    _id(operationId);
    final rows = await database
        .customSelect(
          "SELECT DISTINCT aggregate_id FROM events_v2 WHERE owner_id=? AND event_type='LearningActivityCheckpoint' AND json_extract(payload_json, '\$.state.kind')='transferProbe' AND json_extract(payload_json, '\$.state.launchOperationId')=?",
          variables: [Variable(owner.ownerId), Variable(operationId)],
        )
        .get();
    if (rows.isNotEmpty) {
      if (rows.length != 1) throw StateError('Ambiguous launch');
      final old = await _load(owner, rows.single.read<String>('aggregate_id'));
      if (_json(old.offer.origin) != _json(offer.origin) ||
          old.item.id != offer.item.id) {
        throw StateError('Probe launch collision');
      }
      return old;
    }
    final origin = await _origin(
      owner,
      offer.origin['sessionId'] as String,
      offer.originAttemptId,
    );
    if (_json(origin) != _json(offer.origin) ||
        _timing(offer) != ProbeTiming.unverified ||
        await _used(owner, offer.item)) {
      throw StateError('Probe no longer eligible');
    }
    final session = await learning.startCheckpointedQuiz(
      activityType: transferProbeActivityType,
      limit: 1,
      pinnedContent: [
        PinnedQuizContent(
          identity: ContentIdentity(
            type: ContentType.lexicalMetadata,
            id: offer.item.wordId,
            revision: 1,
          ),
          checksumSha256: origin['coreHash'] as String,
        ),
      ],
      initialState: (s) => TransferProbeRun._(
        owner,
        s,
        offer,
        operationId,
        1,
        false,
        null,
        null,
        _capability,
      ).state(),
    );
    if (session.isEmpty || session.ownerId != owner.ownerId) {
      throw StateError('Probe admission failed');
    }
    await _origin(owner, origin['sessionId'] as String, offer.originAttemptId);
    return _load(owner, session.id);
  });

  Future<TransferProbeRun> resume(
    OwnerGenerationToken owner,
    String sessionId,
  ) => _run(owner, () => _load(owner, sessionId), available: false);
  Future<TransferProbeRun?> latest(OwnerGenerationToken owner) =>
      _run(owner, () async {
        final r = await learning.loadActivityRecovery(
          ownerId: owner.ownerId,
          activityType: transferProbeActivityType,
        );
        return r == null ? null : _load(owner, r.session.id);
      }, available: false);
  Future<TransferProbeRun> _load(
    OwnerGenerationToken owner,
    String sessionId,
  ) async {
    final r = await learning.loadExactActivityRecovery(
      ownerId: owner.ownerId,
      sessionId: sessionId,
      activityType: transferProbeActivityType,
    );
    final j = r?.checkpoint?.state;
    if (r == null ||
        !['active', 'completed'].contains(r.session.state) ||
        j == null ||
        j.length != 9 ||
        j['schemaVersion'] != 1 ||
        j['kind'] != transferProbeActivityType ||
        j['policy'] != TransferProbePolicy.revision ||
        j['inventoryHash'] != TransferProbeInventory.fingerprint ||
        j['assisted'] is! bool) {
      throw StateError('Unsupported probe checkpoint');
    }
    final item = TransferProbeInventory.items.singleWhere(
      (i) => _json(i.toJson()) == _json(j['item']),
    );
    final origin = Map<String, Object?>.from(j['origin'] as Map);
    final verified = await _origin(
      owner,
      origin['sessionId'] as String,
      origin['attemptId'] as String,
      admit: false,
    );
    if (_json(verified) != _json(origin) ||
        origin['wordId'] != item.wordId ||
        origin['contextHash'] == item.contextHash ||
        r.session.startedAtUtc.difference(
              DateTime.parse(origin['occurredAtUtc'] as String),
            ) <
            TransferProbePolicy.minimumDelay) {
      throw StateError('Probe origin changed');
    }
    _id(j['launchOperationId'] as String);
    final result = j['result'] == null
        ? null
        : Map<String, Object?>.from(j['result'] as Map);
    final assisted = j['assisted'] as bool;
    final completed = r.session.state == 'completed';
    if (r.attempts.length != (result == null ? 0 : 1) ||
        r.checkpoint!.revision !=
            1 + (assisted ? 1 : 0) + (result == null ? 0 : 1) ||
        completed != (result != null) ||
        completed != r.checkpoint!.terminalAcknowledged) {
      throw StateError('Probe checkpoint history mismatch');
    }
    if (result != null) {
      final a = r.attempts.single;
      if (result.length != 7 ||
          result['evidenceId'] != a.id ||
          result['correct'] != a.isCorrect ||
          result['timing'] != ProbeTiming.unverified.name ||
          result['occurredAtUtc'] != a.occurredAtUtc.toIso8601String() ||
          result['elapsedMs'] !=
              a.occurredAtUtc
                  .difference(DateTime.parse(origin['occurredAtUtc'] as String))
                  .inMilliseconds ||
          a.occurredAtUtc.isBefore(r.session.startedAtUtc) ||
          result['answerHash'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(result['answerHash'] as String) ||
          a.wordId != item.wordId ||
          a.attemptNumber != 1 ||
          a.promptMode != 'clozeTyped' ||
          a.evidenceContext.hintLevel != (assisted ? 1 : 0) ||
          a.evidenceContext.evidenceClass !=
              (assisted
                  ? EvidenceClass.guidedPractice
                  : EvidenceClass.independentRecall) ||
          a.evidenceContext.contentRevision !=
              LexicalPromptArtifactResolver.formatEvidenceContentRevision(
                promptMode: 'clozeTyped',
                wordId: item.wordId,
                revision: item.revision,
                checksumSha256: _itemHash(item, origin),
              )) {
        throw StateError('Probe result mismatch');
      }
      _id(result['operationId'] as String);
    }
    final session = await learning.reconstructPinnedQuizSession(
      session: r.session,
      content: [
        ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: item.wordId,
          revision: 1,
        ),
      ],
      contentChecksumsSha256: {item.wordId: origin['coreHash'] as String},
    );
    return TransferProbeRun._(
      owner,
      session,
      TransferProbeOffer._(Map.unmodifiable(origin), item),
      j['launchOperationId'] as String,
      r.checkpoint!.revision,
      assisted,
      result == null ? null : Map.unmodifiable(result),
      completed ? r.session : null,
      _capability,
    ).._sampledAtUtc = sets.repository.nowUtc();
  }

  String _itemHash(TransferProbeItem item, Map<String, Object?> origin) =>
      item.evidenceHash(
        coreHash: origin['coreHash'] as String,
        lexicalHash: origin['lexicalHash'] as String,
      );
  void _handle(TransferProbeRun run) {
    if (!identical(run._capability, _capability)) {
      throw StateError('Probe handle retired');
    }
  }

  void _clock(TransferProbeRun run) {
    final sampled = run._sampledAtUtc;
    final now = sets.repository.nowUtc();
    if (sampled == null ||
        !now.isUtc ||
        (now.difference(sampled) - run.clock.elapsed).abs() >
            const Duration(seconds: 5)) {
      throw StateError('Probe clock changed; reopen to check timing');
    }
  }

  Future<TransferProbeRun> hint(TransferProbeRun run) =>
      _run(run.owner, () async {
        _handle(run);
        final current = await _load(run.owner, run.session.id);
        if (current.result != null) throw StateError('Probe already answered');
        if (current.assisted) return current;
        _clock(run);
        await _origin(
          run.owner,
          current.offer.origin['sessionId'] as String,
          current.offer.originAttemptId,
        );
        final next = TransferProbeRun._(
          run.owner,
          current.session,
          current.offer,
          current.operationId,
          current.revision + 1,
          true,
          null,
          null,
          _capability,
        );
        await learning.appendActivityCheckpoint(
          LearningActivityCheckpoint(
            sessionId: run.session.id,
            activityType: transferProbeActivityType,
            revision: next.revision,
            occurredAtUtc: sets.repository.nowUtc(),
            state: next.state(),
          ),
          ownerId: run.owner.ownerId,
        );
        return _load(run.owner, run.session.id);
      });
  Future<TransferProbeRun> answer(
    TransferProbeRun run, {
    required String answer,
    required String operationId,
  }) => _run(run.owner, () async {
    _handle(run);
    _id(operationId);
    if (answer.trim().isEmpty || answer.length > 120) {
      throw ArgumentError('Enter a short answer');
    }
    final digest = sha256.convert(utf8.encode(answer)).toString();
    final current = await _load(run.owner, run.session.id);
    if (current.result != null) {
      if (current.result!['operationId'] != operationId ||
          current.result!['answerHash'] != digest) {
        throw StateError('Probe answer collision');
      }
      return current;
    }
    if (current.revision != run.revision) throw StateError('Stale probe');
    _clock(run);
    if (_timing(current.offer) != ProbeTiming.unverified) {
      throw StateError('Probe timing uncertain');
    }
    await _origin(
      run.owner,
      current.offer.origin['sessionId'] as String,
      current.offer.originAttemptId,
    );
    final pending = evidence.captureCloze(
      ownerId: run.owner.ownerId,
      sessionId: run.session.id,
      wordId: current.item.wordId,
      isCorrect: answer.trim().toLowerCase() == current.item.answer,
      responseTimeMs: run.clock.elapsedMilliseconds,
      attemptNumber: 1,
      contentRevision: 1,
      checksumSha256: _itemHash(current.item, current.offer.origin),
      typed: true,
      classification: HintEvidenceClassification(
        evidenceClass: current.assisted
            ? EvidenceClass.guidedPractice
            : EvidenceClass.independentRecall,
        hintLevel: current.assisted ? 1 : 0,
      ),
    );
    await pending.record();
    final summary = await learning.finishSession(
      run.session.id,
      ownerId: run.owner.ownerId,
    );
    final result = <String, Object?>{
      'operationId': operationId,
      'answerHash': digest,
      'correct': answer.trim().toLowerCase() == current.item.answer,
      'evidenceId': pending.sourceEvidenceId,
      'occurredAtUtc': pending.occurredAtUtc.toIso8601String(),
      'timing': ProbeTiming.unverified.name,
      'elapsedMs': pending.occurredAtUtc
          .difference(current.offer.originUtc)
          .inMilliseconds,
    };
    final next = TransferProbeRun._(
      run.owner,
      current.session,
      current.offer,
      current.operationId,
      current.revision + 1,
      current.assisted,
      Map.unmodifiable(result),
      summary,
      _capability,
    );
    await learning.appendActivityCheckpoint(
      LearningActivityCheckpoint(
        sessionId: run.session.id,
        activityType: transferProbeActivityType,
        revision: next.revision,
        occurredAtUtc: summary.endedAtUtc!,
        terminalAtUtc: summary.endedAtUtc,
        terminalAcknowledged: true,
        state: next.state(),
      ),
      ownerId: run.owner.ownerId,
    );
    await _origin(
      run.owner,
      current.offer.origin['sessionId'] as String,
      current.offer.originAttemptId,
    );
    _clock(run);
    return _load(run.owner, run.session.id);
  });
  Future<void> abandon(OwnerGenerationToken owner, String sessionId) => _run(
    owner,
    () async {
      final row =
          await (database.select(database.learningSessions)..where(
                (r) =>
                    r.ownerId.equals(owner.ownerId) &
                    r.id.equals(sessionId) &
                    r.activityType.equals(transferProbeActivityType),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('Probe unavailable');
      // A lost acknowledgement must retry the committed terminal identity,
      // including after reopen, rather than propose a second end time.
      final when = row.state == 'abandoned' && row.endedAtUtcMs != null
          ? DateTime.fromMillisecondsSinceEpoch(row.endedAtUtcMs!, isUtc: true)
          : sets.repository.nowUtc();
      await learning.abandonSession(
        ownerId: owner.ownerId,
        sessionId: sessionId,
        abandonedAtUtc: when,
      );
    },
    available: false,
  );
}

String _json(Object? value) => jsonEncode(value);
void _id(String value) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.length > 200 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw ArgumentError('Invalid probe operation');
  }
}
