import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../rewards/data/drift_reward_projection_rebuilder.dart';
import '../../vocabulary/domain/vocabulary_repository.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import 'drift_learning_event_store.dart'
    hide
        ContextEvidencePolicyRolloutModeProvider,
        EvidencePolicyRolloutModeProvider,
        FixedEvidencePolicyRolloutModeProvider;
import 'drift_learning_projection_rebuilder.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_policy_rollout.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_event_context.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import '../domain/srs_policy.dart';
import '../domain/srs_operation_identity.dart';

final class DriftLearningRepository
    implements
        LearningRepository,
        LearningEvidenceReplayRepository,
        LearningSessionLifecycleRepository,
        LearningActivityRecoveryRepository {
  static const int maxActivityRecoveryCheckpoints = 64;
  static const int maxActivityRecoveryAttempts = 128;

  DriftLearningRepository(
    this.database, {
    SrsPolicy srsPolicy = const BinarySm2SrsPolicy(),
    EvidenceEligibilityPolicy evidencePolicy =
        const EvidenceEligibilityPolicySet(),
    EvidencePolicyRolloutModeProvider rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
    this.lexicalVocabulary,
  }) : projections = DriftLearningProjectionRebuilder(
         database,
         srsPolicy: srsPolicy,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       ),
       rewardProjections = DriftRewardProjectionRebuilder(database),
       events = DriftLearningEventStore(
         database,
         evidencePolicy: evidencePolicy,
         rolloutModeProvider: rolloutModeProvider,
       );

  final db.AppDatabase database;
  final VocabularyRepository? lexicalVocabulary;
  final DriftLearningProjectionRebuilder projections;
  final DriftRewardProjectionRebuilder rewardProjections;
  final DriftLearningEventStore events;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async {
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final query = database.select(database.vocabularyWords)
      ..where(
        (row) =>
            row.ownerId.equals(ownerId) &
            row.isDeleted.equals(false) &
            (categoryId == null
                ? const Constant(true)
                : row.categoryId.equals(categoryId)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.id)])
      ..limit(limit);
    final rows = await query.get();
    final coreWords = rows
        .map(
          (row) => QuizWord(
            id: row.id,
            categoryId: row.categoryId,
            spelling: row.spelling,
            meaning: row.meaning,
            partOfSpeech: row.partOfSpeech,
            cefrLevel: row.cefrLevel,
            normalizedSpelling: row.normalizedSpelling,
            normalizedMeaning: row.normalizedMeaning,
            contentRevision: row.contentRevision,
            contentChecksumSha256: row.contentChecksumSha256,
          ),
        )
        .toList(growable: false);
    final vocabulary = lexicalVocabulary;
    if (vocabulary == null || coreWords.isEmpty) return coreWords;
    List<VocabularyWord> enriched;
    try {
      enriched = await vocabulary.readPinnedByIds(
        coreWords.map((word) => word.id),
      );
    } on Object {
      // Accepted variants are optional reviewed metadata. Core quiz content
      // remains available when that source is absent, stale, or offline.
      return coreWords;
    }
    if (enriched.length != coreWords.length) return coreWords;
    final enrichedById = <String, VocabularyWord>{
      for (final word in enriched) word.id: word,
    };
    return <QuizWord>[
      for (final core in coreWords)
        _withAcceptedSpellingVariants(core, enrichedById[core.id]),
    ];
  }

  QuizWord _withAcceptedSpellingVariants(
    QuizWord core,
    VocabularyWord? enriched,
  ) {
    final metadata = enriched?.richMetadata;
    final variants = metadata?.acceptedSpellingVariants;
    final revision = metadata?.verifiedContentRevision;
    final checksum = metadata?.verifiedArtifactChecksumSha256;
    if (variants == null ||
        variants.isEmpty ||
        revision == null ||
        revision != core.contentRevision ||
        checksum == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)) {
      return core;
    }
    return QuizWord(
      id: core.id,
      categoryId: core.categoryId,
      spelling: core.spelling,
      meaning: core.meaning,
      partOfSpeech: core.partOfSpeech,
      cefrLevel: core.cefrLevel,
      normalizedSpelling: core.normalizedSpelling,
      normalizedMeaning: core.normalizedMeaning,
      contentRevision: core.contentRevision,
      contentChecksumSha256: core.contentChecksumSha256,
      acceptedSpellingVariants: variants,
      acceptedSpellingVariantsRevision: revision,
      acceptedSpellingVariantsChecksumSha256: checksum,
    );
  }

  @override
  Future<void> startSession(LearningSessionDraft session) async {
    final startedAt = _requiredUtc(session.startedAtUtc, 'startedAtUtc');
    await database
        .into(database.learningSessions)
        .insert(
          db.LearningSessionsCompanion.insert(
            id: _required(session.id, 'id'),
            ownerId: _required(session.ownerId, 'ownerId'),
            activityType: _required(session.activityType, 'activityType'),
            state: 'active',
            startedAtUtcMs: startedAt.millisecondsSinceEpoch,
            appVersion: _required(session.appVersion, 'appVersion'),
            buildId: _required(session.buildId, 'buildId'),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<void> startSessionWithCheckpoint({
    required LearningSessionDraft session,
    required LearningActivityCheckpoint checkpoint,
  }) {
    if (checkpoint.sessionId != session.id ||
        checkpoint.activityType != session.activityType ||
        checkpoint.revision != 1) {
      throw ArgumentError.value(
        checkpoint,
        'checkpoint',
        'must be revision 1 for the same activity session',
      );
    }
    final canonicalCheckpoint = _canonicalizeActivityCheckpoint(checkpoint);
    return database.transaction(() async {
      await startSession(session);
      final stored = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(session.id))).getSingle();
      if (stored.ownerId != session.ownerId ||
          stored.activityType != session.activityType ||
          stored.state != 'active' ||
          stored.startedAtUtcMs !=
              _requiredUtc(
                session.startedAtUtc,
                'startedAtUtc',
              ).millisecondsSinceEpoch ||
          stored.appVersion != session.appVersion ||
          stored.buildId != session.buildId) {
        throw StateError('learning activity session identity conflict');
      }
      await _appendActivityCheckpoint(
        ownerId: session.ownerId,
        checkpoint: canonicalCheckpoint,
      );
    });
  }

  @override
  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) {
    final canonicalCheckpoint = _canonicalizeActivityCheckpoint(checkpoint);
    return database.transaction(
      () => _appendActivityCheckpoint(
        ownerId: ownerId,
        checkpoint: canonicalCheckpoint,
      ),
    );
  }

  LearningActivityCheckpoint _canonicalizeActivityCheckpoint(
    LearningActivityCheckpoint checkpoint,
  ) {
    late final Map<String, Object?> canonicalState;
    try {
      final decoded = jsonDecode(jsonEncode(checkpoint.state));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('checkpoint state must be an object');
      }
      canonicalState = _freezeJsonMap(decoded.cast<String, Object?>());
    } on Object catch (error) {
      throw ArgumentError.value(
        checkpoint.state,
        'state',
        'must be JSON encodable: $error',
      );
    }
    final stateBytes = utf8.encode(jsonEncode(canonicalState)).length;
    if (stateBytes > 65536) {
      throw ArgumentError.value(
        stateBytes,
        'state',
        'checkpoint exceeds the 64 KiB bound',
      );
    }
    return LearningActivityCheckpoint(
      sessionId: checkpoint.sessionId,
      activityType: checkpoint.activityType,
      revision: checkpoint.revision,
      occurredAtUtc: checkpoint.occurredAtUtc,
      state: canonicalState,
      terminalAtUtc: checkpoint.terminalAtUtc,
      terminalAcknowledged: checkpoint.terminalAcknowledged,
    );
  }

  Future<void> _appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    final requiredOwnerId = _required(ownerId, 'ownerId');
    final sessionId = _required(checkpoint.sessionId, 'sessionId');
    final activityType = _required(checkpoint.activityType, 'activityType');
    if (checkpoint.revision < 1 ||
        checkpoint.revision > maxActivityRecoveryCheckpoints) {
      throw RangeError.range(
        checkpoint.revision,
        1,
        maxActivityRecoveryCheckpoints,
        'revision',
      );
    }
    final occurredAtUtc = _requiredUtc(
      checkpoint.occurredAtUtc,
      'occurredAtUtc',
    );
    final terminalAtUtc = checkpoint.terminalAtUtc == null
        ? null
        : _requiredUtc(checkpoint.terminalAtUtc, 'terminalAtUtc');
    if (checkpoint.terminalAcknowledged && terminalAtUtc == null) {
      throw ArgumentError.value(
        checkpoint,
        'checkpoint',
        'terminal acknowledgement requires a terminal identity',
      );
    }
    final canonicalTime = LearningEvidenceContract.canonicalEventUtcSecond(
      occurredAtUtc,
    );
    final canonicalState = checkpoint.state;
    final stateJson = jsonEncode(canonicalState);
    final session =
        await (database.select(database.learningSessions)..where(
              (row) =>
                  row.id.equals(sessionId) &
                  row.ownerId.equals(requiredOwnerId) &
                  row.activityType.equals(activityType),
            ))
            .getSingleOrNull();
    if (session == null) {
      throw StateError('learning activity session not found');
    }
    final storedTerminalAtUtc = _fromEpoch(session.endedAtUtcMs);
    if (session.state == 'active') {
      if (checkpoint.terminalAcknowledged) {
        throw StateError('active activity cannot acknowledge completion');
      }
    } else if (session.state == 'completed') {
      if (terminalAtUtc == null || terminalAtUtc != storedTerminalAtUtc) {
        throw StateError('completed activity terminal identity is invalid');
      }
    } else {
      throw StateError('learning activity session is not recoverable');
    }
    final latest = await _latestActivityCheckpoint(
      ownerId: requiredOwnerId,
      session: session,
    );
    if (latest != null && latest.revision >= checkpoint.revision) {
      if (latest.revision == checkpoint.revision &&
          jsonEncode(latest.state) == stateJson &&
          latest.occurredAtUtc == canonicalTime &&
          latest.terminalAtUtc == terminalAtUtc &&
          latest.terminalAcknowledged == checkpoint.terminalAcknowledged) {
        return;
      }
      throw StateError('activity checkpoint revision already exists');
    }
    final expectedRevision = (latest?.revision ?? 0) + 1;
    if (checkpoint.revision != expectedRevision) {
      throw StateError('activity checkpoint revision is not sequential');
    }
    final key = _activityCheckpointKey(
      ownerId: requiredOwnerId,
      sessionId: sessionId,
      activityType: activityType,
      revision: checkpoint.revision,
    );
    final payload = <String, Object?>{
      'schemaVersion': 2,
      'activityType': activityType,
      'sessionId': sessionId,
      'revision': checkpoint.revision,
      'state': canonicalState,
      'terminalAtUtc': terminalAtUtc?.toIso8601String(),
      'terminalAcknowledged': checkpoint.terminalAcknowledged,
    };
    await database
        .into(database.eventsV2)
        .insert(
          db.EventsV2Companion.insert(
            eventId: key,
            eventType: 'LearningActivityCheckpoint',
            eventVersion: 2,
            occurredAtUtc: canonicalTime,
            recordedAtUtc: canonicalTime,
            actorIdentity: requiredOwnerId,
            ownerId: requiredOwnerId,
            aggregateType: 'LearningSession',
            aggregateId: sessionId,
            idempotencyKey: key,
            consentContextJson: jsonEncode(<String, Object?>{
              'researchConsentVersion': 0,
              'aiConsentGranted': false,
              'voiceConsentGranted': false,
              'socialConsentGranted': false,
            }),
            appVersion: session.appVersion,
            buildId: session.buildId,
            privacyClassification: 'ownerOnly',
            payloadJson: jsonEncode(payload),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final stored = await (database.select(
      database.eventsV2,
    )..where((row) => row.eventId.equals(key))).getSingleOrNull();
    if (stored == null ||
        !_isExactStoredActivityCheckpoint(
          row: stored,
          eventId: key,
          eventVersion: 2,
          actorIdentity: requiredOwnerId,
          ownerId: requiredOwnerId,
          session: session,
          occurredAtUtc: canonicalTime,
          payloadJson: jsonEncode(payload),
        )) {
      throw StateError('activity checkpoint identity conflict');
    }
  }

  @override
  Future<LearningActivityRecovery?> loadLatestActivityRecovery({
    required String ownerId,
    required String activityType,
  }) async {
    final requiredOwnerId = _required(ownerId, 'ownerId');
    final requiredActivityType = _required(activityType, 'activityType');
    var session =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(requiredOwnerId) &
                    row.activityType.equals(requiredActivityType) &
                    row.state.equals('active'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    session ??=
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(requiredOwnerId) &
                    row.activityType.equals(requiredActivityType) &
                    row.state.equals('completed'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    if (session == null) return null;
    final recoverySession = session;
    final checkpoint = await _latestActivityCheckpoint(
      ownerId: requiredOwnerId,
      session: recoverySession,
    );
    if (checkpoint == null) {
      if (recoverySession.state == 'completed') return null;
      return LearningActivityRecovery(
        session: _rowToSummary(recoverySession),
        checkpoint: null,
        attempts: const <RecordAnswerCandidate>[],
      );
    }
    if (recoverySession.state == 'completed' &&
        checkpoint.terminalAtUtc != _fromEpoch(recoverySession.endedAtUtcMs)) {
      return null;
    }
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(requiredOwnerId) &
                    row.sessionId.equals(recoverySession.id),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.attemptNumber),
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ])
              ..limit(maxActivityRecoveryAttempts + 1))
            .get();
    if (attempts.length > maxActivityRecoveryAttempts) {
      throw StateError('activity attempt recovery bound exceeded');
    }
    final sources = await events.readBySourceEvidenceIds(
      attempts.map((attempt) => attempt.id),
    );
    final candidates = <RecordAnswerCandidate>[];
    for (final attempt in attempts) {
      final source = sources[attempt.id];
      if (source == null ||
          await events.validateSourceForAttempt(
                attempt: attempt,
                source: source,
              ) !=
              null) {
        throw StateError('activity attempt has missing or corrupt event');
      }
      final decoded = jsonDecode(attempt.evidenceContextJson);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('activity attempt has corrupt evidence context');
      }
      final context = EvidenceContext.fromJson(decoded.cast<String, Object?>());
      candidates.add(
        RecordAnswerCandidate(
          id: attempt.id,
          ownerId: attempt.ownerId,
          sessionId: attempt.sessionId,
          wordId: attempt.wordId,
          promptMode: attempt.promptMode,
          isCorrect: attempt.isCorrect,
          responseTimeMs: attempt.responseTimeMs,
          attemptNumber: attempt.attemptNumber,
          occurredAtUtc: _fromEpoch(attempt.occurredAtUtcMs)!,
          evidenceContext: context,
          providerProvenance: attempt.providerProvenance,
          actorIdentity: source.actorIdentity,
          eventContext: LearningEventContext.fromEvidenceEnvelope(
            envelope: source,
            evidenceContext: context,
          ),
        ),
      );
    }
    return LearningActivityRecovery(
      session: _rowToSummary(recoverySession),
      checkpoint: checkpoint,
      attempts: List<RecordAnswerCandidate>.unmodifiable(candidates),
    );
  }

  Future<LearningActivityCheckpoint?> _latestActivityCheckpoint({
    required String ownerId,
    required db.LearningSession session,
  }) async {
    final rows =
        await (database.select(database.eventsV2)
              ..where(
                (row) =>
                    row.eventId.like('learning-activity-checkpoint:%') &
                    row.ownerId.equals(ownerId) &
                    row.eventType.equals('LearningActivityCheckpoint') &
                    row.aggregateType.equals('LearningSession') &
                    row.aggregateId.equals(session.id),
              )
              ..limit(maxActivityRecoveryCheckpoints + 1))
            .get();
    if (rows.length > maxActivityRecoveryCheckpoints) {
      throw StateError('activity checkpoint recovery bound exceeded');
    }
    LearningActivityCheckpoint? latest;
    final revisions = <int>[];
    for (final row in rows) {
      late final Object? decodedValue;
      try {
        decodedValue = jsonDecode(row.payloadJson);
      } on Object {
        if (row.aggregateId == session.id) {
          throw StateError('activity checkpoint is corrupt');
        }
        continue;
      }
      if (decodedValue is! Map<String, dynamic>) {
        if (row.aggregateId == session.id) {
          throw StateError('activity checkpoint is corrupt');
        }
        continue;
      }
      final decoded = decodedValue;
      if (decoded['sessionId'] != session.id && row.aggregateId != session.id) {
        continue;
      }
      final actorIsAuthorized = await _isAuthorizedCheckpointActor(
        actorIdentity: row.actorIdentity,
        ownerIdentity: ownerId,
      );
      final schemaVersion = decoded['schemaVersion'];
      final isV1 = schemaVersion == 1;
      final isV2 = schemaVersion == 2;
      final expectedLength = isV1 ? 5 : 7;
      if ((!isV1 && !isV2) ||
          decoded.length != expectedLength ||
          decoded['activityType'] != session.activityType ||
          decoded['sessionId'] != session.id ||
          decoded['revision'] is! int ||
          decoded['state'] is! Map<String, dynamic> ||
          row.eventVersion != schemaVersion ||
          row.recordedAtUtc != row.occurredAtUtc ||
          !actorIsAuthorized ||
          row.tenantContextJson != null ||
          row.correlationId != null ||
          row.causationId != null ||
          row.idempotencyKey != row.eventId ||
          row.consentContextJson !=
              jsonEncode(<String, Object?>{
                'researchConsentVersion': 0,
                'aiConsentGranted': false,
                'voiceConsentGranted': false,
                'socialConsentGranted': false,
              }) ||
          row.experimentContextJson != null ||
          row.contentRevision != null ||
          row.policyVersion != null ||
          row.appVersion != session.appVersion ||
          row.buildId != session.buildId ||
          row.providerProvenanceJson != null ||
          row.privacyClassification != 'ownerOnly') {
        throw StateError('activity checkpoint is corrupt');
      }
      final revision = decoded['revision']! as int;
      final canonicalState = _freezeJsonMap(
        (decoded['state']! as Map<String, dynamic>).cast<String, Object?>(),
      );
      if (revision < 1 ||
          revision > maxActivityRecoveryCheckpoints ||
          utf8.encode(jsonEncode(canonicalState)).length > 65536) {
        throw StateError('activity checkpoint is corrupt');
      }
      DateTime? terminalAtUtc;
      var terminalAcknowledged = false;
      if (isV2) {
        final encodedTerminal = decoded['terminalAtUtc'];
        terminalAcknowledged = decoded['terminalAcknowledged'] is bool
            ? decoded['terminalAcknowledged']! as bool
            : throw StateError('activity checkpoint is corrupt');
        if (encodedTerminal != null) {
          if (encodedTerminal is! String) {
            throw StateError('activity checkpoint is corrupt');
          }
          if (!encodedTerminal.endsWith('Z')) {
            throw StateError('activity checkpoint is corrupt');
          }
          terminalAtUtc = DateTime.tryParse(encodedTerminal);
          if (terminalAtUtc == null || !terminalAtUtc.isUtc) {
            throw StateError('activity checkpoint is corrupt');
          }
        }
        if (terminalAcknowledged && terminalAtUtc == null) {
          throw StateError('activity checkpoint is corrupt');
        }
      }
      final expectedKey = _activityCheckpointKey(
        ownerId: row.actorIdentity,
        sessionId: session.id,
        activityType: session.activityType,
        revision: revision,
      );
      if (row.eventId != expectedKey ||
          !_isExactStoredActivityCheckpoint(
            row: row,
            eventId: expectedKey,
            eventVersion: schemaVersion as int,
            actorIdentity: row.actorIdentity,
            ownerId: ownerId,
            session: session,
            occurredAtUtc: row.occurredAtUtc.toUtc(),
            payloadJson: row.payloadJson,
          )) {
        throw StateError('activity checkpoint identity is corrupt');
      }
      final candidate = LearningActivityCheckpoint(
        sessionId: session.id,
        activityType: session.activityType,
        revision: revision,
        occurredAtUtc: row.occurredAtUtc.toUtc(),
        state: canonicalState,
        terminalAtUtc: terminalAtUtc,
        terminalAcknowledged: terminalAcknowledged,
      );
      if (latest == null || candidate.revision > latest.revision) {
        latest = candidate;
      }
      revisions.add(revision);
    }
    revisions.sort();
    for (var index = 0; index < revisions.length; index += 1) {
      if (revisions[index] != index + 1) {
        throw StateError('activity checkpoint revision history is corrupt');
      }
    }
    return latest;
  }

  bool _isExactStoredActivityCheckpoint({
    required db.EventsV2Data row,
    required String eventId,
    required int eventVersion,
    required String actorIdentity,
    required String ownerId,
    required db.LearningSession session,
    required DateTime occurredAtUtc,
    required String payloadJson,
  }) {
    return row.eventId == eventId &&
        row.eventType == 'LearningActivityCheckpoint' &&
        row.eventVersion == eventVersion &&
        row.occurredAtUtc.toUtc() == occurredAtUtc &&
        row.recordedAtUtc.toUtc() == occurredAtUtc &&
        row.actorIdentity == actorIdentity &&
        row.ownerId == ownerId &&
        row.tenantContextJson == null &&
        row.aggregateType == 'LearningSession' &&
        row.aggregateId == session.id &&
        row.correlationId == null &&
        row.causationId == null &&
        row.idempotencyKey == eventId &&
        row.consentContextJson ==
            jsonEncode(<String, Object?>{
              'researchConsentVersion': 0,
              'aiConsentGranted': false,
              'voiceConsentGranted': false,
              'socialConsentGranted': false,
            }) &&
        row.experimentContextJson == null &&
        row.contentRevision == null &&
        row.policyVersion == null &&
        row.appVersion == session.appVersion &&
        row.buildId == session.buildId &&
        row.providerProvenanceJson == null &&
        row.privacyClassification == 'ownerOnly' &&
        row.payloadJson == payloadJson;
  }

  Map<String, Object?> _freezeJsonMap(Map<String, Object?> value) =>
      Map<String, Object?>.unmodifiable(
        value.map(
          (key, item) => MapEntry<String, Object?>(key, _freezeJsonValue(item)),
        ),
      );

  Object? _freezeJsonValue(Object? value) {
    if (value is Map<String, Object?>) return _freezeJsonMap(value);
    if (value is List<Object?>) {
      return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
    }
    return value;
  }

  Future<bool> _isAuthorizedCheckpointActor({
    required String actorIdentity,
    required String ownerIdentity,
  }) async {
    if (actorIdentity == ownerIdentity) return true;
    final historicalActor = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals(actorIdentity))).getSingleOrNull();
    return historicalActor != null &&
        !historicalActor.isActive &&
        historicalActor.accountState == 'mergedInto:$ownerIdentity';
  }

  String _activityCheckpointKey({
    required String ownerId,
    required String sessionId,
    required String activityType,
    required int revision,
  }) {
    final digest = sha256
        .convert(
          utf8.encode(
            '$ownerId\u0000$sessionId\u0000$activityType\u0000$revision',
          ),
        )
        .toString();
    return 'learning-activity-checkpoint:$digest';
  }

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) {
    _validateCandidate(candidate, requireSourceIdentity: true);
    return database.transaction(() async {
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(candidate.id))).getSingleOrNull();
      if (existing == null) return null;
      if (!_sameAttempt(existing, candidate)) {
        throw StateError('attempt id already exists with different evidence');
      }
      final event = await events.readBySourceEvidenceId(candidate.id);
      if (event == null ||
          await events.validateSourceForAttempt(
                attempt: existing,
                source: event,
              ) !=
              null) {
        throw StateError('committed answer has missing or corrupt event');
      }
      final decisionSet = await events.ensureDecisionSetForAttempt(
        attempt: existing,
        sourceEvent: event,
      );
      return CommittedAnswerReplay(
        result: AnswerRecordResult(
          inserted: false,
          isCorrect: existing.isCorrect,
          srs: decisionSet.allows(LearningProjection.masterySrs)
              ? await _readSrsSnapshot(
                  ownerId: candidate.ownerId,
                  wordId: candidate.wordId,
                )
              : null,
        ),
        event: event,
      );
    });
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) {
    _validateAnswer(command);
    return database.transaction(() async {
      final event = command.event;
      if (event != null &&
          !await _isAuthorizedCheckpointActor(
            actorIdentity: event.actorIdentity,
            ownerIdentity: command.ownerId,
          )) {
        throw ArgumentError.value(
          command,
          'command',
          'invalid answer actor lineage',
        );
      }
      final existing = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingleOrNull();
      if (existing != null) {
        if (!_sameAttempt(existing, command.candidate)) {
          throw StateError('attempt id already exists with different evidence');
        }
        final storedEvent = await events.readBySourceEvidenceId(command.id);
        late final LearningEvidenceDecisionSet decisionSet;
        if (command.isFrozenV13LegacyIngress) {
          if (storedEvent != null) {
            throw StateError('canonical event cannot be omitted during replay');
          }
          decisionSet = await events.ensureDecisionSetForAttempt(
            attempt: existing,
          );
        } else {
          final candidateEvent = command.event!;
          if (storedEvent == null ||
              await events.validateSourceForAttempt(
                    attempt: existing,
                    source: storedEvent,
                  ) !=
                  null) {
            throw StateError('canonical event cannot be retrofitted on replay');
          }
          if (jsonEncode(storedEvent.toJson()) !=
              jsonEncode(candidateEvent.toJson())) {
            throw StateError(
              'learning event identity already exists with different evidence',
            );
          }
          decisionSet = await events.ensureDecisionSetForAttempt(
            attempt: existing,
            sourceEvent: storedEvent,
          );
        }
        return AnswerRecordResult(
          inserted: false,
          isCorrect: existing.isCorrect,
          srs: decisionSet.allows(LearningProjection.masterySrs)
              ? await _readSrsSnapshot(
                  ownerId: command.ownerId,
                  wordId: command.wordId,
                )
              : null,
        );
      }

      if (event != null && event.actorIdentity != command.ownerId) {
        throw ArgumentError.value(
          command,
          'command',
          'a first-write answer actor must equal its owner',
        );
      }

      final session =
          await (database.select(database.learningSessions)..where(
                (row) =>
                    row.id.equals(command.sessionId) &
                    row.ownerId.equals(command.ownerId) &
                    row.state.equals('active'),
              ))
              .getSingleOrNull();
      if (session == null) {
        throw StateError('active learning session not found');
      }
      final word =
          await (database.select(database.vocabularyWords)..where(
                (row) =>
                    row.id.equals(command.wordId) &
                    row.ownerId.equals(command.ownerId),
              ))
              .getSingleOrNull();
      if (word == null) {
        throw StateError('active vocabulary word not found');
      }
      if (word.isDeleted &&
          !await _isValidPinnedDeletedMatchingAnswer(
            command: command,
            session: session,
          )) {
        throw StateError('deleted vocabulary is not pinned to this session');
      }

      await database
          .into(database.answerAttempts)
          .insert(
            db.AnswerAttemptsCompanion.insert(
              id: command.id,
              ownerId: command.ownerId,
              sessionId: command.sessionId,
              wordId: command.wordId,
              promptMode: command.promptMode,
              isCorrect: command.isCorrect,
              responseTimeMs: Value(command.responseTimeMs),
              attemptNumber: command.attemptNumber,
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
              providerProvenance: Value(command.providerProvenance),
              evidenceClass: Value(command.evidenceContext.evidenceClass.name),
              evidenceContextJson: Value(
                jsonEncode(command.evidenceContext.toJson()),
              ),
            ),
          );
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'attempt',
        entityId: command.id,
        occurredAtUtc: command.occurredAtUtc,
      );
      if (event != null) await events.append(event);
      final insertedAttempt = await (database.select(
        database.answerAttempts,
      )..where((row) => row.id.equals(command.id))).getSingle();
      final decisionSet = await events.ensureDecisionSetForAttempt(
        attempt: insertedAttempt,
        sourceEvent: event,
      );
      final rebuildWord =
          decisionSet.allows(LearningProjection.masterySrs) ||
          decisionSet.allows(LearningProjection.xp);
      final next = rebuildWord
          ? await projections.rebuildWord(
              ownerId: command.ownerId,
              wordId: command.wordId,
            )
          : null;
      await projections.rebuildSession(
        ownerId: command.ownerId,
        sessionId: command.sessionId,
      );
      if (decisionSet.allows(LearningProjection.achievement)) {
        await projections.rebuildAchievements(command.ownerId);
      }
      if (decisionSet.allows(LearningProjection.xp) ||
          decisionSet.allows(LearningProjection.coins)) {
        await rewardProjections.rebuild(command.ownerId);
      }
      // Outbox hook — push updated SRS state to Firestore (Phase 0 Week 12-13).
      // Entity ID is wordId (unique per owner-word pair).
      if (decisionSet.allows(LearningProjection.masterySrs) && next != null) {
        await _appendSrsOutbox(
          ownerId: command.ownerId,
          wordId: command.wordId,
          answerAttemptId: command.id,
          occurredAtUtc: command.occurredAtUtc,
        );
      }
      return AnswerRecordResult(
        inserted: true,
        isCorrect: command.isCorrect,
        srs: decisionSet.allows(LearningProjection.masterySrs) ? next : null,
      );
    });
  }

  Future<bool> _isValidPinnedDeletedMatchingAnswer({
    required RecordAnswerCommand command,
    required db.LearningSession session,
  }) async {
    if (session.activityType != 'matching' ||
        command.promptMode != 'matchingPair' ||
        command.providerProvenance != 'pinned-lexical-matching' ||
        command.evidenceContext.skillId != 'matching-recognition' ||
        (command.evidenceContext.evidenceClass != EvidenceClass.recognition &&
            command.evidenceContext.evidenceClass !=
                EvidenceClass.guidedPractice)) {
      return false;
    }
    final checkpoint = await _latestActivityCheckpoint(
      ownerId: command.ownerId,
      session: session,
    );
    final state = checkpoint?.state;
    final pairs = state?['pairs'];
    final pending = state?['pendingEvidence'];
    final stateVersion = state?['schemaVersion'];
    if ((stateVersion != 1 &&
            stateVersion != 2 &&
            stateVersion != 3 &&
            stateVersion != 4) ||
        pairs is! List<Object?> ||
        pending is! Map<String, Object?>) {
      return false;
    }
    final matches = pairs
        .where((value) {
          return value is Map<String, Object?> && value['id'] == command.wordId;
        })
        .toList(growable: false);
    if (matches.length != 1) return false;
    final snapshot = matches.single! as Map<String, Object?>;
    const wordKeys = <String>{
      'id',
      'categoryId',
      'spelling',
      'meaning',
      'partOfSpeech',
      'normalizedSpelling',
      'normalizedMeaning',
      'contentRevision',
      'contentChecksumSha256',
    };
    if (snapshot.length != wordKeys.length ||
        !snapshot.keys.every(wordKeys.contains)) {
      return false;
    }
    final revision = snapshot['contentRevision'];
    final checksum = snapshot['contentChecksumSha256'];
    final contentIdentity =
        revision is int &&
            revision > 0 &&
            checksum is String &&
            RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum)
        ? 'lexical-matching:v$revision:$checksum'
        : 'lexical-matching:snapshot:'
              '${sha256.convert(utf8.encode(jsonEncode(snapshot)))}';
    if (command.evidenceContext.contentRevision != contentIdentity) {
      return false;
    }
    const pendingV1Keys = <String>{
      'sourceEvidenceId',
      'occurredAtUtc',
      'wordId',
      'selectedMeaningWordId',
      'isCorrect',
      'responseTimeMs',
      'attemptNumber',
      'evidenceClass',
      'hintLevel',
      'contentRevision',
      'canonicalCorrectAnswer',
      'evidenceContext',
      'eventContext',
    };
    const pendingV2Keys = <String>{
      ...pendingV1Keys,
      'schemaVersion',
      'actorIdentity',
    };
    const pendingV3Keys = <String>{...pendingV2Keys, 'providerProvenance'};
    final pendingVersion = pending['schemaVersion'];
    final expectedPendingKeys = switch (pendingVersion) {
      2 => pendingV2Keys,
      3 => pendingV3Keys,
      _ => pendingV1Keys,
    };
    if (pendingVersion != null && pendingVersion != 2 && pendingVersion != 3) {
      return false;
    }
    if (pending.length != expectedPendingKeys.length ||
        !pending.keys.every(expectedPendingKeys.contains)) {
      return false;
    }
    final encodedOccurredAt = pending['occurredAtUtc'];
    if (encodedOccurredAt is! String || !encodedOccurredAt.endsWith('Z')) {
      return false;
    }
    final occurredAtUtc = DateTime.tryParse(encodedOccurredAt);
    final frozenEvidenceJson = pending['evidenceContext'];
    final frozenEventJson = pending['eventContext'];
    final event = command.event;
    final pendingActor = pendingVersion == 2 || pendingVersion == 3
        ? pending['actorIdentity']
        : command.ownerId;
    if (occurredAtUtc == null ||
        !occurredAtUtc.isUtc ||
        event == null ||
        pendingActor is! String ||
        pendingActor != event.actorIdentity ||
        frozenEvidenceJson is! Map<String, Object?> ||
        frozenEventJson is! Map<String, Object?> ||
        pending['sourceEvidenceId'] != command.id ||
        occurredAtUtc != command.occurredAtUtc ||
        pending['wordId'] != command.wordId ||
        pending['isCorrect'] != command.isCorrect ||
        pending['responseTimeMs'] != command.responseTimeMs ||
        pending['attemptNumber'] != command.attemptNumber ||
        (pendingVersion == 3 &&
            pending['providerProvenance'] != command.providerProvenance) ||
        pending['evidenceClass'] !=
            command.evidenceContext.evidenceClass.name ||
        pending['hintLevel'] != command.evidenceContext.hintLevel ||
        pending['contentRevision'] != contentIdentity ||
        pending['canonicalCorrectAnswer'] !=
            (snapshot['meaning'] as String).trim().replaceAll(
              RegExp(r'\s+'),
              ' ',
            ) ||
        pending['selectedMeaningWordId'] is! String ||
        command.isCorrect !=
            (pending['selectedMeaningWordId'] == command.wordId) ||
        jsonEncode(frozenEvidenceJson) !=
            jsonEncode(command.evidenceContext.toJson())) {
      return false;
    }
    if (!await _isAuthorizedCheckpointActor(
      actorIdentity: pendingActor,
      ownerIdentity: command.ownerId,
    )) {
      return false;
    }
    try {
      final frozenEventContext = LearningEventContext.fromJson(frozenEventJson);
      frozenEventContext.validateAgainst(
        evidenceContext: command.evidenceContext,
        occurredAtUtc: command.occurredAtUtc,
      );
      final commandEventContext = LearningEventContext.fromEvidenceEnvelope(
        envelope: event,
        evidenceContext: command.evidenceContext,
      );
      return jsonEncode(frozenEventContext.toJson()) ==
          jsonEncode(commandEventContext.toJson());
    } on Object {
      return false;
    }
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) {
    _requiredUtc(endedAtUtc, 'endedAtUtc');
    return database.transaction(() async {
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(sessionId) &
                    candidate.ownerId.equals(ownerId),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('learning session not found');
      final total = row.correctCount + row.wrongCount;
      final score = total == 0 ? 0 : ((row.correctCount * 100) / total).round();
      if (row.state == 'completed') {
        if (row.endedAtUtcMs != endedAtUtc.millisecondsSinceEpoch) {
          throw StateError(
            'learning session was completed with a different terminal time',
          );
        }
        return _rowToSummary(row);
      }
      if (row.state != 'active') {
        throw StateError('learning session is not active');
      }
      {
        await (database.update(
          database.learningSessions,
        )..where((candidate) => candidate.id.equals(sessionId))).write(
          db.LearningSessionsCompanion(
            state: const Value('completed'),
            endedAtUtcMs: Value(endedAtUtc.millisecondsSinceEpoch),
            score: Value(score),
          ),
        );
        final sessionAttempts =
            await (database.select(database.answerAttempts)..where(
                  (attempt) =>
                      attempt.ownerId.equals(ownerId) &
                      attempt.sessionId.equals(sessionId),
                ))
                .get();
        final achievementAttempts = <db.AnswerAttempt>[];
        for (final attempt in sessionAttempts) {
          final decisionSet = await projections.decisionSetForAttempt(attempt);
          if (decisionSet.allows(LearningProjection.achievement)) {
            achievementAttempts.add(attempt);
          }
        }
        if (achievementAttempts.isNotEmpty) {
          await _unlockAchievement(
            ownerId: ownerId,
            achievementId: 'first_session',
            sourceEventId: sessionId,
            unlockedAtUtc: endedAtUtc,
          );
          if (achievementAttempts.every((attempt) => attempt.isCorrect)) {
            await _unlockAchievement(
              ownerId: ownerId,
              achievementId: 'perfect_session',
              sourceEventId: sessionId,
              unlockedAtUtc: endedAtUtc,
            );
          }
        }
      }
      final completed = await (database.select(
        database.learningSessions,
      )..where((candidate) => candidate.id.equals(sessionId))).getSingle();
      return _rowToSummary(completed);
    });
  }

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async {
    _requiredUtc(nowUtc, 'nowUtc');
    if (limit < 1 || limit > 100) {
      throw RangeError.range(limit, 1, 100, 'limit');
    }
    final query =
        database.select(database.vocabularyWords).join([
            innerJoin(
              database.srsStates,
              database.srsStates.wordId.equalsExp(database.vocabularyWords.id) &
                  database.srsStates.ownerId.equals(ownerId) &
                  database.srsStates.dueAtUtcMs.isSmallerOrEqualValue(
                    nowUtc.millisecondsSinceEpoch,
                  ),
            ),
          ])
          ..where(
            database.vocabularyWords.ownerId.equals(ownerId) &
                database.vocabularyWords.isDeleted.equals(false),
          )
          ..orderBy([OrderingTerm.asc(database.srsStates.dueAtUtcMs)])
          ..limit(limit);
    final rows = await query.get();
    return rows
        .map((row) => row.readTable(database.vocabularyWords))
        .map(
          (word) => QuizWord(
            id: word.id,
            categoryId: word.categoryId,
            spelling: word.spelling,
            meaning: word.meaning,
            partOfSpeech: word.partOfSpeech,
            cefrLevel: word.cefrLevel,
            normalizedSpelling: word.normalizedSpelling,
            normalizedMeaning: word.normalizedMeaning,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async {
    final row =
        await (database.select(database.readingProgressEntries)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.documentId.equals(documentId) &
                  candidate.documentRevision.equals(documentRevision),
            ))
            .getSingleOrNull();
    return row == null ? null : _readingSnapshot(row);
  }

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) {
    _validateReading(command);
    return database.transaction(() async {
      final priorEvent = await (database.select(
        database.readingEvents,
      )..where((row) => row.id.equals(command.eventId))).getSingleOrNull();
      if (priorEvent != null) {
        if (!_sameReadingEvent(priorEvent, command)) {
          throw StateError(
            'reading event id already exists with different evidence',
          );
        }
        return projections.rebuildReading(
          ownerId: command.ownerId,
          documentId: command.documentId,
          documentRevision: command.documentRevision,
        );
      }
      await database
          .into(database.readingEvents)
          .insert(
            db.ReadingEventsCompanion.insert(
              id: command.eventId,
              ownerId: command.ownerId,
              documentId: command.documentId,
              documentRevision: Value(command.documentRevision),
              eventType: command.isCompleted ? 'completed' : 'checkpoint',
              position: Value(command.position),
              occurredAtUtcMs: command.occurredAtUtc.millisecondsSinceEpoch,
            ),
          );
      await _appendImmutableOutbox(
        ownerId: command.ownerId,
        entityType: 'readingEvent',
        entityId: command.eventId,
        occurredAtUtc: command.occurredAtUtc,
      );
      return projections.rebuildReading(
        ownerId: command.ownerId,
        documentId: command.documentId,
        documentRevision: command.documentRevision,
      );
    });
  }

  Future<void> _unlockAchievement({
    required String ownerId,
    required String achievementId,
    required String sourceEventId,
    required DateTime unlockedAtUtc,
  }) async {
    const definitionVersion = 1;
    final achievementId_ =
        'achievement:$ownerId:$achievementId:$definitionVersion';
    await database
        .into(database.achievementUnlocks)
        .insert(
          db.AchievementUnlocksCompanion.insert(
            id: achievementId_,
            ownerId: ownerId,
            achievementId: achievementId,
            definitionVersion: definitionVersion,
            sourceEventId: sourceEventId,
            unlockedAtUtcMs: unlockedAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    // Outbox hook — sync achievement unlock to Firestore (Phase 0 Week 12-13).
    await _appendImmutableOutbox(
      ownerId: ownerId,
      entityType: 'achievementUnlock',
      entityId: achievementId_,
      occurredAtUtc: unlockedAtUtc,
    );
  }

  Future<void> _appendImmutableOutbox({
    required String ownerId,
    required String entityType,
    required String entityId,
    required DateTime occurredAtUtc,
  }) async {
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId:
                entityType == 'attempt' &&
                    LearningEvidenceContract.validSourceEvidenceId(entityId)
                ? LearningEvidenceContract.answerAttemptOutboxOperationId(
                    entityId,
                  )
                : '$entityType:$entityId:1',
            ownerId: ownerId,
            entityType: entityType,
            entityId: entityId,
            operationKind: 'upsert',
            baseRevision: const Value(0),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> _appendSrsOutbox({
    required String ownerId,
    required String wordId,
    required String answerAttemptId,
    required DateTime occurredAtUtc,
  }) async {
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (attempt) =>
                  attempt.ownerId.equals(ownerId) &
                  attempt.wordId.equals(wordId),
            ))
            .get();
    var revision = 0;
    for (final attempt in attempts) {
      final decisionSet = await projections.decisionSetForAttempt(attempt);
      if (decisionSet.allows(LearningProjection.masterySrs)) revision++;
    }
    if (revision < 1) {
      throw StateError('SRS revision requires durable answer evidence');
    }
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: SrsOperationIdentity.create(
              ownerId: ownerId,
              wordId: wordId,
              answerAttemptId: answerAttemptId,
              revision: revision,
            ),
            ownerId: ownerId,
            entityType: 'srsState',
            entityId: wordId,
            operationKind: 'upsert',
            baseRevision: Value(revision - 1),
            createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<SrsSnapshot?> _readSrsSnapshot({
    required String ownerId,
    required String wordId,
  }) async {
    final row =
        await (database.select(database.srsStates)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.wordId.equals(wordId),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return SrsSnapshot(
      intervalDays: row.intervalDays,
      repetitions: row.repetitions,
      lapses: row.lapses,
      stability: row.stability,
      difficulty: row.difficulty,
      lastReviewAtUtc: _fromEpoch(row.lastReviewAtUtcMs),
      dueAtUtc: _fromEpoch(row.dueAtUtcMs),
      algorithmVersion: row.algorithmVersion,
    );
  }

  bool _sameAttempt(db.AnswerAttempt row, RecordAnswerCandidate candidate) {
    return row.ownerId == candidate.ownerId &&
        row.sessionId == candidate.sessionId &&
        row.wordId == candidate.wordId &&
        row.promptMode == candidate.promptMode &&
        row.isCorrect == candidate.isCorrect &&
        row.responseTimeMs == candidate.responseTimeMs &&
        row.attemptNumber == candidate.attemptNumber &&
        row.occurredAtUtcMs == candidate.occurredAtUtc.millisecondsSinceEpoch &&
        row.providerProvenance == candidate.providerProvenance &&
        LearningEvidenceContract.sameEvidenceMetadata(
          evidenceClass: row.evidenceClass,
          evidenceContextJson: row.evidenceContextJson,
          expectedContext: candidate.evidenceContext,
        );
  }

  bool _sameReadingEvent(db.ReadingEvent row, ReadingProgressCommand command) {
    return row.ownerId == command.ownerId &&
        row.documentId == command.documentId &&
        row.documentRevision == command.documentRevision &&
        row.eventType == (command.isCompleted ? 'completed' : 'checkpoint') &&
        row.position == command.position &&
        row.occurredAtUtcMs == command.occurredAtUtc.millisecondsSinceEpoch;
  }

  ReadingProgressSnapshot _readingSnapshot(db.ReadingProgressEntry row) {
    return ReadingProgressSnapshot(
      documentId: row.documentId,
      documentRevision: row.documentRevision,
      lastPosition: row.lastPosition,
      isCompleted: row.isCompleted,
      updatedAtUtc: _fromEpoch(row.updatedAtUtcMs)!,
    );
  }

  void _validateAnswer(RecordAnswerCommand command) {
    final candidate = command.candidate;
    _validateCandidate(
      candidate,
      requireSourceIdentity: !command.isFrozenV13LegacyIngress,
    );
    if (command.isFrozenV13LegacyIngress) {
      if (command.event != null ||
          !LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
            command.evidenceContext,
          )) {
        throw ArgumentError.value(
          command,
          'command',
          'invalid frozen-v13 legacy ingress',
        );
      }
      return;
    }
    final event = command.event;
    if (event == null ||
        !events.isExactDeclaredSourceForCandidate(
          candidate: candidate,
          source: event,
        )) {
      throw ArgumentError.value(command, 'command', 'invalid answer evidence');
    }
  }

  void _validateCandidate(
    RecordAnswerCandidate candidate, {
    required bool requireSourceIdentity,
  }) {
    final occurredAt = _requiredUtc(candidate.occurredAtUtc, 'occurredAtUtc');
    if ((requireSourceIdentity &&
            (!LearningEvidenceContract.validSourceEvidenceId(candidate.id) ||
                LearningEvidenceContract.isExactFrozenV13LegacyEvidence(
                  candidate.evidenceContext,
                ))) ||
        !LearningEvidenceContract.validAttempt(
          id: candidate.id,
          ownerId: candidate.ownerId,
          sessionId: candidate.sessionId,
          wordId: candidate.wordId,
          promptMode: candidate.promptMode,
          responseTimeMs: candidate.responseTimeMs,
          attemptNumber: candidate.attemptNumber,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          providerProvenance: candidate.providerProvenance,
          evidenceClass: candidate.evidenceContext.evidenceClass.name,
          evidenceContextJson: jsonEncode(candidate.evidenceContext.toJson()),
        )) {
      throw ArgumentError.value(
        candidate,
        'candidate',
        'invalid answer evidence',
      );
    }
  }

  void _validateReading(ReadingProgressCommand command) {
    final occurredAt = _requiredUtc(command.occurredAtUtc, 'occurredAtUtc');
    if (!LearningEvidenceContract.validReading(
      eventId: command.eventId,
      ownerId: command.ownerId,
      documentId: command.documentId,
      documentRevision: command.documentRevision,
      eventType: command.isCompleted ? 'completed' : 'checkpoint',
      position: command.position,
      occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
    )) {
      throw ArgumentError.value(command, 'command', 'invalid reading evidence');
    }
  }

  String _required(String value, String field) {
    final result = value.trim();
    if (result.isEmpty) throw ArgumentError.value(value, field, 'blank');
    return result;
  }

  DateTime _requiredUtc(DateTime? value, String field) {
    if (value == null || !value.isUtc) {
      throw ArgumentError.value(value, field, 'must be UTC');
    }
    return value;
  }

  DateTime? _fromEpoch(int? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  @override
  Future<LearningSessionSummary?> getActiveSession({
    required String ownerId,
  }) async {
    final row =
        await (database.select(database.learningSessions)
              ..where(
                (t) => t.ownerId.equals(ownerId) & t.state.equals('active'),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.startedAtUtcMs)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return _rowToSummary(row);
  }

  @override
  Future<void> abandonActiveSessions({required String ownerId}) async {
    await (database.update(database.learningSessions)
          ..where((t) => t.ownerId.equals(ownerId) & t.state.equals('active')))
        .write(const db.LearningSessionsCompanion(state: Value('abandoned')));
  }

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) {
    final requiredOwnerId = _required(ownerId, 'ownerId');
    final requiredSessionId = _required(sessionId, 'sessionId');
    final terminalAt = _requiredUtc(abandonedAtUtc, 'abandonedAtUtc');
    final terminalAtUtcMs = terminalAt.millisecondsSinceEpoch;
    return database.transaction(() async {
      final row =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(requiredSessionId) &
                    candidate.ownerId.equals(requiredOwnerId),
              ))
              .getSingleOrNull();
      if (row == null) throw StateError('learning session not found');
      if (row.state == 'abandoned') {
        if (row.endedAtUtcMs == terminalAtUtcMs) return _rowToSummary(row);
        throw StateError(
          'learning session was abandoned with a different terminal time',
        );
      }
      if (row.state != 'active') {
        throw StateError('learning session is not active');
      }
      await (database.update(database.learningSessions)..where(
            (candidate) =>
                candidate.id.equals(requiredSessionId) &
                candidate.ownerId.equals(requiredOwnerId) &
                candidate.state.equals('active'),
          ))
          .write(
            db.LearningSessionsCompanion(
              state: const Value('abandoned'),
              endedAtUtcMs: Value(terminalAtUtcMs),
            ),
          );
      final updated =
          await (database.select(database.learningSessions)..where(
                (candidate) =>
                    candidate.id.equals(requiredSessionId) &
                    candidate.ownerId.equals(requiredOwnerId),
              ))
              .getSingle();
      return _rowToSummary(updated);
    });
  }

  @override
  Future<List<LearningSessionSummary>> listSessionHistory({
    required String ownerId,
    required int limit,
  }) async {
    final rows =
        await (database.select(database.learningSessions)
              ..where(
                (t) => t.ownerId.equals(ownerId) & t.state.equals('completed'),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.startedAtUtcMs)])
              ..limit(limit))
            .get();
    return rows.map(_rowToSummary).toList(growable: false);
  }

  LearningSessionSummary _rowToSummary(db.LearningSession row) {
    return LearningSessionSummary(
      id: row.id,
      ownerId: row.ownerId,
      activityType: row.activityType,
      state: row.state,
      startedAtUtc: _fromEpoch(row.startedAtUtcMs)!,
      endedAtUtc: _fromEpoch(row.endedAtUtcMs),
      correctCount: row.correctCount,
      wrongCount: row.wrongCount,
      score: row.score ?? 0,
      appVersion: row.appVersion,
      buildId: row.buildId,
    );
  }
}
