import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../assessment/domain/assessment_models.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../learning/data/drift_learning_event_store.dart';
import '../../learning/domain/evidence_context.dart';
import '../../learning/domain/learning_event_context.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../learning/domain/lesson_session_state.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../time_tracking/domain/learning_time_repository.dart';
import '../domain/learning_history_models.dart';

typedef LearningHistoryUtcNow = DateTime Function();

final class DriftLearningHistoryReader implements LearningHistoryReader {
  const DriftLearningHistoryReader(
    this.database, {
    required this.learningTime,
    required this.nowUtc,
  });

  final AppDatabase database;
  final LearningTimeRepository learningTime;
  final LearningHistoryUtcNow nowUtc;

  static String canonicalReplaySessionId({
    required String sourceSessionId,
    required String replayOperationId,
  }) {
    final source = _canonicalText(sourceSessionId, 'sourceSessionId');
    final operation = _canonicalText(replayOperationId, 'replayOperationId');
    final identity = jsonEncode(<String, Object>{
      'version': 1,
      'sourceSessionId': source,
      'replayOperationId': operation,
    });
    return 'session:history-replay:${sha256.convert(utf8.encode(identity))}';
  }

  @override
  Future<List<LearningHistoryEntry>> list(HistoryFilter filter) async {
    final ownerId = _canonicalText(filter.ownerId, 'filter.ownerId');
    if (filter.limit < 1 || filter.limit > 100) {
      throw RangeError.range(filter.limit, 1, 100, 'filter.limit');
    }
    final terminalSessions =
        await (database.select(database.learningSessions)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.state.isIn(const <String>['completed', 'abandoned']),
              )
              ..orderBy(<OrderingTerm Function($LearningSessionsTable)>[
                (row) => OrderingTerm.desc(row.endedAtUtcMs),
                (row) => OrderingTerm.desc(row.startedAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ])
              ..limit(filter.limit))
            .get();
    final assessmentRows = <AssessmentRunRow>[
      ...await _terminalAssessmentRows(
        ownerId: ownerId,
        state: AssessmentRunState.completed,
        limit: filter.limit,
      ),
      ...await _terminalAssessmentRows(
        ownerId: ownerId,
        state: AssessmentRunState.abandoned,
        limit: filter.limit,
      ),
    ];
    final sessions = <String, LearningSession>{
      for (final session in terminalSessions) session.id: session,
    };
    for (final assessment in assessmentRows) {
      if (sessions.containsKey(assessment.learningSessionId)) continue;
      final session =
          await (database.select(database.learningSessions)..where(
                (row) =>
                    row.id.equals(assessment.learningSessionId) &
                    row.ownerId.equals(ownerId),
              ))
              .getSingleOrNull();
      if (session == null) {
        throw StateError('assessment history session is missing');
      }
      sessions[session.id] = session;
    }
    final result = <LearningHistoryEntry>[];
    for (final session in sessions.values) {
      result.add(await _entry(session));
    }
    result.sort((left, right) {
      final terminalOrder = right.endedAtUtc.compareTo(left.endedAtUtc);
      if (terminalOrder != 0) return terminalOrder;
      final startOrder = right.startedAtUtc.compareTo(left.startedAtUtc);
      if (startOrder != 0) return startOrder;
      return left.sessionId.compareTo(right.sessionId);
    });
    return List<LearningHistoryEntry>.unmodifiable(result.take(filter.limit));
  }

  @override
  Future<LessonStartCommand> replayAsNewSession(
    String sourceSessionId, {
    required String replayOperationId,
  }) async {
    final sourceId = _canonicalText(sourceSessionId, 'sourceSessionId');
    final sessionId = canonicalReplaySessionId(
      sourceSessionId: sourceId,
      replayOperationId: replayOperationId,
    );
    if (sessionId == sourceId) {
      throw StateError('replay session identity must differ from its source');
    }
    final source = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals(sourceId))).getSingleOrNull();
    if (source == null ||
        (source.state != 'completed' && source.state != 'abandoned') ||
        source.endedAtUtcMs == null) {
      throw StateError('replay requires one terminal learning session');
    }
    final configuration = _configuration(source);
    if (configuration == null || configuration.packIdentity == null) {
      throw StateError('replay requires exact pinned session configuration');
    }
    final content = await _packPresentation(configuration.packIdentity);
    if (!content.available) {
      throw StateError('replay content is no longer available');
    }
    final persisted = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
    DateTime startedAtUtc;
    if (persisted == null) {
      startedAtUtc = _requiredUtc(nowUtc(), 'nowUtc');
    } else {
      if (persisted.ownerId != source.ownerId ||
          persisted.activityType != configuration.mode.id ||
          persisted.sessionConfigurationIdentity !=
              configuration.contentIdentity ||
          persisted.sessionConfigurationJson !=
              configuration.stableSerialization) {
        throw StateError('replay session identity collision');
      }
      startedAtUtc = _utcMs(
        persisted.startedAtUtcMs,
        'persistedReplay.startedAtUtcMs',
      );
    }
    return LessonStartCommand(
      mode: configuration.mode,
      sessionId: sessionId,
      startedAtUtc: startedAtUtc,
      itemCount: configuration.itemCount,
      ownerId: configuration.ownerId,
      configuration: configuration,
    );
  }

  Future<LearningHistoryEntry> _entry(LearningSession session) async {
    final assessmentRows =
        await (database.select(database.assessmentRuns)..where(
              (row) =>
                  row.ownerId.equals(session.ownerId) &
                  row.learningSessionId.equals(session.id),
            ))
            .get();
    if (assessmentRows.length > 1) {
      throw StateError('history session has multiple assessment runs');
    }
    final assessmentRun = assessmentRows.isEmpty
        ? null
        : _assessmentRun(assessmentRows.single);
    final assessmentTerminalAtUtc = assessmentRun == null
        ? null
        : switch (assessmentRun.state) {
            AssessmentRunState.completed => assessmentRun.completedAtUtc,
            AssessmentRunState.abandoned => assessmentRun.abandonedAtUtc,
            AssessmentRunState.active => null,
          };
    final isAssessment = assessmentRun != null;
    final endedAtUtcMs = session.endedAtUtcMs;
    if (assessmentRun != null) {
      if (session.activityType != 'assessment' ||
          assessmentTerminalAtUtc == null ||
          assessmentRun.ownerId != session.ownerId ||
          assessmentRun.learningSessionId != session.id ||
          assessmentRun.startedAtUtc !=
              _utcMs(session.startedAtUtcMs, 'session.startedAtUtcMs') ||
          (session.state != 'active' &&
              session.state != 'completed' &&
              session.state != 'abandoned') ||
          (session.state != 'active' &&
              (session.state != assessmentRun.state.name ||
                  endedAtUtcMs == null ||
                  _utcMs(endedAtUtcMs, 'session.endedAtUtcMs') !=
                      assessmentTerminalAtUtc))) {
        throw StateError('assessment history identity is inconsistent');
      }
    } else if (session.activityType == 'assessment' || endedAtUtcMs == null) {
      throw StateError('terminal history session has no canonical outcome');
    }
    final configuration = _configuration(session);
    if (isAssessment && configuration != null) {
      throw StateError('assessment history cannot use lesson configuration');
    }
    final mode = isAssessment
        ? null
        : configuration?.mode ?? _modeForActivityType(session.activityType);
    final presentation = await _packPresentation(
      isAssessment ? null : configuration?.packIdentity,
    );
    final activeLearningDuration = await learningTime.activeDuration(
      session.id,
    );
    final attempts =
        await (database.select(database.answerAttempts)
              ..where(
                (row) =>
                    row.ownerId.equals(session.ownerId) &
                    row.sessionId.equals(session.id),
              )
              ..orderBy(<OrderingTerm Function($AnswerAttemptsTable)>[
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final eventRows =
        await (database.select(database.eventsV2)
              ..where(
                (row) =>
                    row.ownerId.equals(session.ownerId) &
                    row.aggregateId.equals(session.id),
              )
              ..orderBy(<OrderingTerm Function($EventsV2Table)>[
                (row) => OrderingTerm.asc(row.occurredAtUtc),
                (row) => OrderingTerm.asc(row.eventId),
              ]))
            .get();
    final attemptsByEventId = <String, AnswerAttempt>{
      for (final attempt in attempts)
        LearningEvidenceContract.learningEventId(attempt.id): attempt,
    };
    final events = <String, EventEnvelopeV2>{};
    for (final row in eventRows) {
      final event = _event(row);
      final attempt = attemptsByEventId[event.eventId];
      if (attempt == null) {
        if (_isAnswerEvent(event)) {
          throw StateError('history contains an answer event without attempt');
        }
        continue;
      }
      final attemptId = event.payload['attemptId'];
      final expectedType = attempt.isCorrect
          ? 'QuizCompleted'
          : 'QuizAttempted';
      if (attemptId != attempt.id ||
          event.eventType != expectedType ||
          events.containsKey(attempt.id)) {
        throw StateError('history event has ambiguous attempt identity');
      }
      events[attempt.id] = event;
    }
    final evidence = <LearningHistoryEvidence>[];
    for (final attempt in attempts) {
      final context = EvidenceContext.fromJson(
        _decodeMap(attempt.evidenceContextJson, 'evidenceContextJson'),
      );
      final event = events.remove(attempt.id);
      if (event == null) {
        throw StateError('history attempt has no canonical event');
      }
      final sourceValidation = await DriftLearningEventStore(
        database,
      ).validateSourceForAttempt(attempt: attempt, source: event);
      if (sourceValidation != null) {
        throw StateError(
          'history attempt has invalid canonical event: $sourceValidation',
        );
      }
      if (event.payload.containsKey('evidenceContext') &&
          (event.eventId !=
                  LearningEvidenceContract.learningEventId(attempt.id) ||
              event.payload['wordId'] != attempt.wordId ||
              event.payload['promptMode'] != attempt.promptMode ||
              event.payload['correct'] != attempt.isCorrect ||
              event.payload['attemptNumber'] != attempt.attemptNumber ||
              !_mapsEqual(
                event.payload['evidenceContext'],
                context.toJson(),
              ))) {
        throw StateError('history attempt and event do not match');
      }
      final occurredAtUtc = _utcMs(
        attempt.occurredAtUtcMs,
        'attempt.occurredAtUtcMs',
      );
      LearningEventContext.fromEvidenceEnvelope(
        envelope: event,
        evidenceContext: context,
      ).validateAgainst(evidenceContext: context, occurredAtUtc: occurredAtUtc);
      if (assessmentRun != null &&
          !_matchesAssessmentRunEvidence(
            run: assessmentRun,
            terminalAtUtc: assessmentTerminalAtUtc!,
            attempt: attempt,
            context: context,
            occurredAtUtc: occurredAtUtc,
          )) {
        throw StateError(
          'assessment history evidence does not match its terminal run',
        );
      }
      evidence.add(
        LearningHistoryEvidence(
          attemptId: attempt.id,
          eventId: event.eventId,
          wordId: attempt.wordId,
          promptMode: attempt.promptMode,
          isCorrect: attempt.isCorrect,
          occurredAtUtc: occurredAtUtc,
          evidenceContext: context,
          event: LearningHistoryEventSnapshot.fromValidatedEnvelope(event),
        ),
      );
    }
    if (events.isNotEmpty) {
      throw StateError('history contains an event without its attempt');
    }
    final assessmentCorrectCount = isAssessment
        ? evidence.where((item) => item.isCorrect).length
        : 0;
    final assessmentSampleSize = isAssessment ? evidence.length : 0;
    final assessmentSummary = assessmentRun == null
        ? null
        : LearningHistoryAssessmentSummary(
            phase: assessmentRun.phase,
            state: assessmentRun.state,
            terminalAtUtc: assessmentTerminalAtUtc!,
            instrumentVersion: assessmentRun.instrumentVersion,
            formVersion: assessmentRun.formVersion,
            sampleSize: assessmentSampleSize,
            correctCount: assessmentCorrectCount,
            incorrectCount: assessmentSampleSize - assessmentCorrectCount,
            accuracy: assessmentSampleSize == 0
                ? 0
                : assessmentCorrectCount / assessmentSampleSize,
          );
    return LearningHistoryEntry(
      sessionId: session.id,
      ownerId: session.ownerId,
      mode: mode,
      packIdentity: isAssessment ? null : configuration?.packIdentity,
      packTitle: presentation.title,
      contentAvailability: presentation.available
          ? LearningHistoryContentAvailability.available
          : LearningHistoryContentAvailability.unavailable,
      activeLearningDuration: activeLearningDuration,
      terminalState: assessmentRun != null
          ? switch (assessmentRun.state) {
              AssessmentRunState.completed =>
                LearningHistoryTerminalState.completed,
              AssessmentRunState.abandoned =>
                LearningHistoryTerminalState.abandoned,
              AssessmentRunState.active => throw StateError(
                'assessment history must be terminal',
              ),
            }
          : switch (session.state) {
              'completed' => LearningHistoryTerminalState.completed,
              'abandoned' => LearningHistoryTerminalState.abandoned,
              _ => throw StateError('unsupported history session state'),
            },
      startedAtUtc: _utcMs(session.startedAtUtcMs, 'session.startedAtUtcMs'),
      endedAtUtc: isAssessment
          ? assessmentTerminalAtUtc!
          : _utcMs(endedAtUtcMs!, 'session.endedAtUtcMs'),
      correctCount: isAssessment
          ? assessmentCorrectCount
          : session.correctCount,
      wrongCount: isAssessment
          ? assessmentSampleSize - assessmentCorrectCount
          : session.wrongCount,
      score: isAssessment ? null : session.score,
      sessionConfiguration: isAssessment ? null : configuration,
      evidence: isAssessment ? const <LearningHistoryEvidence>[] : evidence,
      assessmentSummary: assessmentSummary,
    );
  }

  Future<List<AssessmentRunRow>> _terminalAssessmentRows({
    required String ownerId,
    required AssessmentRunState state,
    required int limit,
  }) {
    final query = database.select(database.assessmentRuns)
      ..where(
        (row) => row.ownerId.equals(ownerId) & row.state.equals(state.name),
      )
      ..orderBy(<OrderingTerm Function($AssessmentRunsTable)>[
        state == AssessmentRunState.completed
            ? (row) => OrderingTerm.desc(row.completedAtUtcMs)
            : (row) => OrderingTerm.desc(row.abandonedAtUtcMs),
        (row) => OrderingTerm.desc(row.startedAtUtcMs),
        (row) => OrderingTerm.asc(row.id),
      ])
      ..limit(limit);
    return query.get();
  }

  SessionConfiguration? _configuration(LearningSession session) {
    final serialized = session.sessionConfigurationJson;
    final identity = session.sessionConfigurationIdentity;
    if (serialized == null && identity == null) return null;
    if (serialized == null || identity == null) {
      throw StateError('history session configuration is incomplete');
    }
    final configuration = SessionConfiguration.fromStableSerialization(
      serialized,
    );
    final packIdentity = configuration.packIdentity;
    if (configuration.contentIdentity != identity ||
        configuration.ownerId != session.ownerId ||
        configuration.mode.id != session.activityType ||
        (packIdentity != null &&
            packIdentity.type != ContentType.learningPack)) {
      throw StateError('history session configuration does not match');
    }
    return configuration;
  }

  LessonMode? _modeForActivityType(String activityType) {
    for (final mode in LessonMode.values) {
      if (mode.id == activityType) return mode;
    }
    return null;
  }

  Future<({bool available, String? title})> _packPresentation(
    ContentIdentity? identity,
  ) async {
    if (identity == null ||
        identity.type != ContentType.learningPack ||
        identity.revision <= 0) {
      return (available: false, title: null);
    }
    final packs =
        await (database.select(database.learningPacks)..where(
              (row) =>
                  row.packId.equals(identity.id) &
                  row.revision.equals(identity.revision),
            ))
            .get();
    if (packs.length != 1) return (available: false, title: null);
    final pack = packs.single;
    final manifest =
        await (database.select(database.contentManifests)..where(
              (row) =>
                  row.id.equals(pack.manifestId) &
                  row.contentType.equals(ContentType.learningPack.name) &
                  row.contentId.equals(identity.id) &
                  row.revision.equals(identity.revision),
            ))
            .getSingleOrNull();
    if (manifest == null ||
        manifest.reviewState != ContentReviewState.approved.name ||
        manifest.publicationState != ContentPublicationState.published.name ||
        pack.title.isEmpty ||
        pack.title != pack.title.trim()) {
      return (available: false, title: null);
    }
    return (available: true, title: pack.title);
  }

  EventEnvelopeV2 _event(EventsV2Data row) {
    final json = <String, dynamic>{
      'schemaVersion': EventEnvelopeV2.schemaVersion,
      'eventId': row.eventId,
      'eventType': row.eventType,
      'eventVersion': row.eventVersion,
      'occurredAtUtc': _storedUtc(
        row.occurredAtUtc,
        'event.occurredAtUtc',
      ).toIso8601String(),
      'recordedAtUtc': _storedUtc(
        row.recordedAtUtc,
        'event.recordedAtUtc',
      ).toIso8601String(),
      'actorIdentity': row.actorIdentity,
      'ownerIdentity': row.ownerId,
      if (row.tenantContextJson != null)
        'tenantContext': _decodeMap(
          row.tenantContextJson!,
          'tenantContextJson',
        ),
      'aggregateType': row.aggregateType,
      'aggregateId': row.aggregateId,
      if (row.correlationId != null) 'correlationId': row.correlationId,
      if (row.causationId != null) 'causationId': row.causationId,
      'idempotencyKey': row.idempotencyKey,
      'consentContext': _decodeMap(
        row.consentContextJson,
        'consentContextJson',
      ),
      if (row.experimentContextJson != null)
        'experimentContext': _decodeMap(
          row.experimentContextJson!,
          'experimentContextJson',
        ),
      if (row.contentRevision != null) 'contentRevision': row.contentRevision,
      if (row.policyVersion != null) 'policyVersion': row.policyVersion,
      'appVersion': row.appVersion,
      'buildId': row.buildId,
      if (row.providerProvenanceJson != null)
        'providerProvenance': _decodeMap(
          row.providerProvenanceJson!,
          'providerProvenanceJson',
        ),
      'privacyClassification': row.privacyClassification,
      'payload': _decodeMap(row.payloadJson, 'payloadJson'),
    };
    return EventEnvelopeV2.fromJson(json);
  }

  AssessmentRun _assessmentRun(AssessmentRunRow row) => AssessmentRun(
    id: row.id,
    ownerId: row.ownerId,
    learningSessionId: row.learningSessionId,
    studyCycleId: row.studyCycleId,
    phase: AssessmentPhase.values.byName(row.phase),
    state: AssessmentRunState.values.byName(row.state),
    protocolId: row.protocolId,
    protocolVersion: row.protocolVersion,
    experimentId: row.experimentId,
    experimentVersion: row.experimentVersion,
    assignmentId: row.assignmentId,
    cohort: row.cohort,
    consentVersion: row.consentVersion,
    consentDecidedAtUtc: _utcMs(
      row.consentDecidedAtUtcMs,
      'assessment.consentDecidedAtUtcMs',
    ),
    instrumentId: row.instrumentId,
    instrumentVersion: row.instrumentVersion,
    formId: row.formId,
    formVersion: row.formVersion,
    instrumentChecksumSha256: row.instrumentChecksumSha256,
    formChecksumSha256: row.formChecksumSha256,
    appVersion: row.appVersion,
    buildId: row.buildId,
    databaseSchemaVersion: row.databaseSchemaVersion,
    contentRevision: row.contentRevision,
    evidencePolicyVersion: row.evidencePolicyVersion,
    featureContractRevision: row.featureContractRevision,
    featureContractHash: row.featureContractHash,
    startedAtUtc: _utcMs(row.startedAtUtcMs, 'assessment.startedAtUtcMs'),
    completedAtUtc: row.completedAtUtcMs == null
        ? null
        : _utcMs(row.completedAtUtcMs!, 'assessment.completedAtUtcMs'),
    abandonedAtUtc: row.abandonedAtUtcMs == null
        ? null
        : _utcMs(row.abandonedAtUtcMs!, 'assessment.abandonedAtUtcMs'),
  );

  bool _matchesAssessmentRunEvidence({
    required AssessmentRun run,
    required DateTime terminalAtUtc,
    required AnswerAttempt attempt,
    required EvidenceContext context,
    required DateTime occurredAtUtc,
  }) =>
      attempt.ownerId == run.ownerId &&
      attempt.sessionId == run.learningSessionId &&
      attempt.evidenceClass == EvidenceClass.assessment.name &&
      context.evidenceClass == EvidenceClass.assessment &&
      context.classificationSource == EvidenceClassificationSource.declared &&
      context.rolloutMode == EvidencePolicyRolloutMode.enforced &&
      !context.engagementAllowed &&
      context.protocolId == run.protocolId &&
      context.protocolVersion == run.protocolVersion &&
      context.experimentId == run.experimentId &&
      context.experimentVersion == run.experimentVersion &&
      context.assignmentId == run.assignmentId &&
      context.cohort == run.cohort &&
      context.researchConsentVersion == run.consentVersion &&
      context.instrumentId == run.instrumentId &&
      context.instrumentVersion == run.instrumentVersion &&
      context.formId == run.formId &&
      context.formVersion == run.formVersion &&
      context.assessmentItemId != null &&
      context.assessmentResponseCode != null &&
      context.scoringRuleVersion != null &&
      context.contentRevision == run.contentRevision &&
      context.policyVersion == run.evidencePolicyVersion &&
      context.featureContractRevision == run.featureContractRevision &&
      context.featureContractHash == run.featureContractHash &&
      !occurredAtUtc.isBefore(run.startedAtUtc) &&
      !occurredAtUtc.isAfter(terminalAtUtc);
}

bool _isAnswerEvent(EventEnvelopeV2 event) =>
    event.eventId.startsWith('learning-event:') ||
    event.eventType == 'QuizCompleted' ||
    event.eventType == 'QuizAttempted';

Map<String, Object?> _decodeMap(String source, String name) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException();
    return decoded.cast<String, Object?>();
  } on Object catch (error) {
    throw FormatException('invalid $name: $error');
  }
}

bool _mapsEqual(Object? left, Map<String, Object?> right) {
  if (left is! Map) return false;
  return jsonEncode(left) == jsonEncode(right);
}

String _canonicalText(String value, String name) {
  if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
    throw ArgumentError.value(value, name, 'must be canonical nonblank text');
  }
  return value;
}

DateTime _utcMs(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must be nonnegative');
  }
  return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}

DateTime _storedUtc(DateTime value, String name) {
  final result = value.toUtc();
  if (result.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, name, 'must be nonnegative');
  }
  return result;
}

DateTime _requiredUtc(DateTime value, String name) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, name, 'must be nonnegative UTC');
  }
  return value;
}
