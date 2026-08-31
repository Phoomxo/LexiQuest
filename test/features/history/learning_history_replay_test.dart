import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/history/application/learning_history_use_cases.dart';
import 'package:vocab_learning_app/features/history/data/drift_learning_history_reader.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

void main() {
  late AppDatabase database;
  late DriftLearningHistoryReader reader;
  late _RecordingSessionLauncher launcher;
  late LearningHistoryUseCases useCases;
  var replayClockCalls = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    replayClockCalls = 0;
    reader = DriftLearningHistoryReader(
      database,
      learningTime: DriftLearningTimeRepository(
        database,
        owners: const _Owners('owner:history'),
      ),
      nowUtc: () => DateTime.utc(2026, 8, 31, 14, replayClockCalls++),
    );
    launcher = _RecordingSessionLauncher();
    useCases = LearningHistoryUseCases(
      owners: const _Owners('owner:history'),
      reader: reader,
      sessionLauncher: launcher,
    );
    await _seedReplaySource(database);
  });

  tearDown(() => database.close());

  test(
    'f43 replay creates a new command through the lesson authority and keeps source rows byte equivalent',
    () async {
      final before = await _sourceRows(database);
      final durableLauncher = _DurableSessionLauncher(database);
      final durableUseCases = LearningHistoryUseCases(
        owners: const _Owners('owner:history'),
        reader: reader,
        sessionLauncher: durableLauncher,
      );

      final command = await durableUseCases.replayAsNewSession(
        'session:source',
        replayOperationId: 'history-replay:action-1',
      );

      expect(command.sessionId, isNot('session:source'));
      expect(command.ownerId, 'owner:history');
      expect(command.mode, LessonMode.typedRecall);
      expect(command.itemCount, 1);
      expect(command.startedAtUtc, DateTime.utc(2026, 8, 31, 14));
      expect(command.configuration, _configuration());
      expect(durableLauncher.commands, <LessonStartCommand>[command]);
      expect(await _sourceRows(database), before);
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(2),
      );
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(await database.select(database.eventsV2).get(), hasLength(1));
    },
  );

  test(
    'f43 separate replay actions are new sessions while source evidence identity and research context never clone',
    () async {
      final sourceAttempt =
          (await database.select(database.answerAttempts).get()).single;
      final sourceEvent =
          (await database.select(database.eventsV2).get()).single;

      final first = await useCases.replayAsNewSession(
        'session:source',
        replayOperationId: 'history-replay:action-1',
      );
      final second = await useCases.replayAsNewSession(
        'session:source',
        replayOperationId: 'history-replay:action-2',
      );

      expect(
        first.sessionId,
        DriftLearningHistoryReader.canonicalReplaySessionId(
          sourceSessionId: 'session:source',
          replayOperationId: 'history-replay:action-1',
        ),
      );
      expect(
        second.sessionId,
        DriftLearningHistoryReader.canonicalReplaySessionId(
          sourceSessionId: 'session:source',
          replayOperationId: 'history-replay:action-2',
        ),
      );
      expect(second.sessionId, isNot(first.sessionId));
      expect(launcher.commands, <LessonStartCommand>[first, second]);
      final attempts = await database.select(database.answerAttempts).get();
      final events = await database.select(database.eventsV2).get();
      expect(attempts, hasLength(1));
      expect(events, hasLength(1));
      expect(attempts.single.toJson(), sourceAttempt.toJson());
      expect(events.single.toJson(), sourceEvent.toJson());
    },
  );

  test(
    'f43 replay lost acknowledgement returns the same durable new session without cloning source evidence',
    () async {
      final lostAckLauncher = _LostAckDurableSessionLauncher(database);
      final retryingUseCases = LearningHistoryUseCases(
        owners: const _Owners('owner:history'),
        reader: reader,
        sessionLauncher: lostAckLauncher,
      );
      final before = await _sourceRows(database);

      await expectLater(
        retryingUseCases.replayAsNewSession(
          'session:source',
          replayOperationId: 'history-replay:lost-ack-operation',
        ),
        throwsStateError,
      );
      final replay = await retryingUseCases.replayAsNewSession(
        'session:source',
        replayOperationId: 'history-replay:lost-ack-operation',
      );

      expect(replay.sessionId, isNot('session:source'));
      expect(lostAckLauncher.commands, hasLength(2));
      expect(
        lostAckLauncher.commands.map((command) => command.sessionId),
        everyElement(replay.sessionId),
      );
      expect(
        lostAckLauncher.commands.map((command) => command.configuration),
        everyElement(replay.configuration),
      );
      expect(
        lostAckLauncher.commands.map((command) => command.startedAtUtc),
        everyElement(replay.startedAtUtc),
        reason: 'retry must reuse the durable start time after lost ACK',
      );
      expect(replayClockCalls, 1);
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(2));
      expect(sessions.where((row) => row.id == replay.sessionId), hasLength(1));
      expect(await _sourceRows(database), before);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(await database.select(database.eventsV2).get(), hasLength(1));
    },
  );

  test(
    'f43 replay fails closed for another owner nonterminal source and deleted pack',
    () async {
      final foreignUseCases = LearningHistoryUseCases(
        owners: const _Owners('owner:foreign'),
        reader: reader,
        sessionLauncher: launcher,
      );
      await expectLater(
        foreignUseCases.replayAsNewSession(
          'session:source',
          replayOperationId: 'history-replay:foreign-owner',
        ),
        throwsStateError,
      );
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'session:active',
              ownerId: 'owner:history',
              activityType: LessonMode.typedRecall.id,
              state: 'active',
              startedAtUtcMs: DateTime.utc(
                2026,
                8,
                31,
                13,
              ).millisecondsSinceEpoch,
              appVersion: 'test',
              buildId: 'f43',
            ),
          );
      await expectLater(
        useCases.replayAsNewSession(
          'session:active',
          replayOperationId: 'history-replay:active-source',
        ),
        throwsStateError,
      );
      await expectLater(
        useCases.replayAsNewSession(
          'session:source',
          replayOperationId: ' history-replay:noncanonical ',
        ),
        throwsArgumentError,
      );
      final collisionOperationId = 'history-replay:collision';
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: DriftLearningHistoryReader.canonicalReplaySessionId(
                sourceSessionId: 'session:source',
                replayOperationId: collisionOperationId,
              ),
              ownerId: 'owner:history',
              activityType: LessonMode.meaningQuiz.id,
              state: 'active',
              startedAtUtcMs: DateTime.utc(
                2026,
                8,
                31,
                13,
              ).millisecondsSinceEpoch,
              appVersion: 'test',
              buildId: 'f43',
            ),
          );
      await expectLater(
        useCases.replayAsNewSession(
          'session:source',
          replayOperationId: collisionOperationId,
        ),
        throwsStateError,
      );
      await database.delete(database.learningPacks).go();
      await expectLater(
        useCases.replayAsNewSession(
          'session:source',
          replayOperationId: 'history-replay:missing-content',
        ),
        throwsStateError,
      );
      expect(launcher.commands, isEmpty);
    },
  );
}

final class _RecordingSessionLauncher
    implements LearningHistorySessionLauncher {
  final List<LessonStartCommand> commands = <LessonStartCommand>[];

  @override
  Object get authorityIdentity => this;

  @override
  Future<void> start(LessonStartCommand command) async {
    commands.add(command);
  }
}

class _DurableSessionLauncher implements LearningHistorySessionLauncher {
  _DurableSessionLauncher(AppDatabase database)
    : repository = DriftLearningRepository(database);

  final DriftLearningRepository repository;
  final List<LessonStartCommand> commands = <LessonStartCommand>[];

  @override
  Object get authorityIdentity => repository;

  @override
  Future<void> start(LessonStartCommand command) async {
    commands.add(command);
    await repository.startSession(
      LearningSessionDraft(
        id: command.sessionId,
        ownerId: command.ownerId!,
        activityType: command.mode.id,
        startedAtUtc: command.startedAtUtc,
        appVersion: 'test',
        buildId: 'f43',
        sessionConfiguration: command.configuration,
      ),
    );
  }
}

final class _LostAckDurableSessionLauncher extends _DurableSessionLauncher {
  _LostAckDurableSessionLauncher(super.database);

  var _loseNextAcknowledgement = true;

  @override
  Future<void> start(LessonStartCommand command) async {
    await super.start(command);
    if (_loseNextAcknowledgement) {
      _loseNextAcknowledgement = false;
      throw StateError('simulated lost acknowledgement after durable commit');
    }
  }
}

final class _Owners implements LocalOwnerRepository {
  const _Owners(this.ownerId);

  final String ownerId;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: ownerId, createdAtUtc: DateTime.utc(2026, 8, 31));

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

const _packIdentity = ContentIdentity(
  type: ContentType.learningPack,
  id: 'pack:travel',
  revision: 1,
);

SessionConfiguration _configuration() => SessionConfiguration.validated(
  schemaVersion: sessionConfigurationSchemaVersion,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'owner:history',
  mode: LessonMode.typedRecall,
  itemCount: 1,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 0,
  timing: const SessionTiming.untimedAlternative(
    maximumActiveEffort: Duration(minutes: 10),
  ),
  packIdentity: _packIdentity,
  protocolId: 'protocol:local-standard',
  protocolVersion: '1',
  protocolLimitsIdentity:
      const SessionConfigurationProtocolLimits.standard().contentIdentity,
);

Future<void> _seedReplaySource(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(id: 'owner:history', createdAtUtcMs: 1),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:history',
          ownerId: 'owner:history',
          name: 'History',
          normalizedName: 'history',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word:station',
          ownerId: 'owner:history',
          categoryId: 'category:history',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: 'manifest:pack:travel:r1',
          contentType: ContentType.learningPack.name,
          contentId: _packIdentity.id,
          revision: _packIdentity.revision,
          checksumSha256: 'a' * 64,
          byteLength: 1,
          provenance: ContentProvenance.packaged.name,
          sourceUri: 'asset://learning-packs/pack-travel-r1.json',
          reviewState: ContentReviewState.approved.name,
          publicationState: ContentPublicationState.published.name,
          createdAtUtcMs: 1,
          reviewedAtUtcMs: const Value(2),
          publishedAtUtcMs: const Value(3),
        ),
      );
  await database
      .into(database.learningPacks)
      .insert(
        LearningPacksCompanion.insert(
          id: 'pack:travel:r1',
          packId: _packIdentity.id,
          revision: _packIdentity.revision,
          manifestId: 'manifest:pack:travel:r1',
          title: 'Travel Essentials',
          cefrLevel: 'A1',
          topic: 'travel',
          skill: 'vocabulary',
          goal: 'recognition',
          createdAtUtcMs: 1,
        ),
      );
  final configuration = _configuration();
  final assignedAtUtc = DateTime.utc(2026, 8, 30, 8, 55);
  await database
      .into(database.experimentAssignments)
      .insert(
        ExperimentAssignmentsCompanion.insert(
          id: 'assignment:history',
          ownerId: 'owner:history',
          experimentId: 'experiment:history',
          experimentVersion: 1,
          cohort: 'enforced',
          protocolVersion: '1.0.0',
          assignedAtUtcMs: assignedAtUtc.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session:source',
          ownerId: 'owner:history',
          activityType: LessonMode.typedRecall.id,
          state: 'completed',
          startedAtUtcMs: DateTime.utc(2026, 8, 30, 9).millisecondsSinceEpoch,
          endedAtUtcMs: Value(
            DateTime.utc(2026, 8, 30, 9, 5).millisecondsSinceEpoch,
          ),
          correctCount: const Value(1),
          wrongCount: const Value(0),
          score: const Value(100),
          appVersion: 'test',
          buildId: 'f43',
          sessionConfigurationIdentity: Value(configuration.contentIdentity),
          sessionConfigurationJson: Value(configuration.stableSerialization),
        ),
      );
  final evidence = EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'typed-recall',
    hintLevel: 0,
    contentRevision: 'pack:travel@1',
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: 'protocol:history',
    protocolVersion: '1.0.0',
    experimentId: 'experiment:history',
    experimentVersion: 1,
    assignmentId: 'assignment:history',
    cohort: 'enforced',
    researchConsentVersion: 1,
    engagementAllowed: false,
  );
  final occurredAtUtc = DateTime.utc(2026, 8, 30, 9, 2);
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt:source',
          ownerId: 'owner:history',
          sessionId: 'session:source',
          wordId: 'word:station',
          promptMode: 'typedRecall',
          isCorrect: true,
          responseTimeMs: const Value(850),
          attemptNumber: 1,
          occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          evidenceClass: Value(evidence.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(evidence.toJson())),
        ),
      );
  final event = const EventV1ToV2Adapter(appVersion: 'test', buildId: 'f43')
      .adaptFromCommand(
        sourceEvidenceId: 'attempt:source',
        ownerId: 'owner:history',
        sessionId: 'session:source',
        wordId: 'word:station',
        promptMode: 'typedRecall',
        isCorrect: true,
        attemptNumber: 1,
        occurredAtUtc: occurredAtUtc,
        evidenceContext: evidence,
        learningEventContext: LearningEventContext(
          consentContext: const ConsentContext(
            researchConsentVersion: 1,
            aiConsentGranted: false,
            voiceConsentGranted: false,
            socialConsentGranted: false,
          ),
          experimentContext: ExperimentContext(
            experimentId: 'experiment:history',
            variantId: 'enforced',
            assignedAtUtc: assignedAtUtc,
          ),
          protocolId: 'protocol:history',
          protocolVersion: '1.0.0',
          experimentVersion: 1,
          assignmentId: 'assignment:history',
          featureContractIdentity: currentFeatureContractIdentity,
        ),
      );
  await _insertEvent(database, event);
}

Future<void> _insertEvent(AppDatabase database, EventEnvelopeV2 event) =>
    database
        .into(database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: event.eventId,
            eventType: event.eventType,
            eventVersion: event.eventVersion,
            occurredAtUtc: event.occurredAtUtc,
            recordedAtUtc: event.recordedAtUtc,
            actorIdentity: event.actorIdentity,
            ownerId: event.ownerIdentity,
            aggregateType: event.aggregateType,
            aggregateId: event.aggregateId,
            idempotencyKey: event.idempotencyKey,
            consentContextJson: jsonEncode(event.consentContext.toJson()),
            contentRevision: Value(event.contentRevision),
            policyVersion: Value(event.policyVersion),
            appVersion: event.appVersion,
            buildId: event.buildId,
            privacyClassification: event.privacyClassification.name,
            payloadJson: jsonEncode(event.payload),
          ),
        );

Future<Map<String, Object?>> _sourceRows(AppDatabase database) async =>
    <String, Object?>{
      'sessions': [
        for (final row in await (database.select(
          database.learningSessions,
        )..where((row) => row.id.equals('session:source'))).get())
          row.toJson(),
      ],
      'attempts': [
        for (final row in await database.select(database.answerAttempts).get())
          row.toJson(),
      ],
      'events': [
        for (final row in await database.select(database.eventsV2).get())
          row.toJson(),
      ],
      'assignments': [
        for (final row
            in await database.select(database.experimentAssignments).get())
          row.toJson(),
      ],
    };
