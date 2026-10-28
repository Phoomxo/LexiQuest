import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_session_purpose.dart';

/// Deliberately seeded attack/recovery fixture, not proof of canonical start.
Future<String> seedSyntheticReplayPurpose(
  AppDatabase db, {
  required String owner,
  required DateTime at,
  String operationId = 'synthetic-replay-boundary',
  String appVersion = '1',
  String buildId = 'test',
  PairSessionPurpose purpose = PairSessionPurpose.practiceReplay,
}) async {
  final id = pairSessionId(owner, operationId);
  final plan = PairMatchingPlanV1(
    ownerId: owner,
    orderedLexicalItems: [
      for (var i = 0; i < 4; i++)
        PairLexicalItem(
          wordId: 'synthetic-$i',
          contentRevision: 1,
          checksum: 'a' * 64,
          spelling: 'word$i',
          meaning: 'คำ$i',
          sourceLocale: 'en',
          targetLocale: 'th',
          sourceReasons: {PairSourceReason.dueSrs},
        ),
    ],
    direction: PairDirection.enToTh,
    density: PairDensity.compact4,
    shuffleSeed: 52,
    timerPreset: PairTimerPreset.off,
    allowlistVersion: 'synthetic',
    learningSessionId: id,
    entryKind: PairSourceSurface.learn,
    sourceSnapshotId: 'synthetic',
    createdAtUtc: at,
    sessionPurpose: purpose,
    sourceSessionId: purpose == PairSessionPurpose.practiceReplay
        ? 'synthetic-terminal-source'
        : null,
  );
  final config = SessionConfiguration.validated(
    schemaVersion: 1,
    policyVersion: sessionConfigurationPolicyVersion,
    ownerId: owner,
    mode: LessonMode.matching,
    itemCount: 4,
    direction: SessionDirection.forward,
    difficulty: SessionDifficulty.standard,
    hintBudget: 0,
    timing: const SessionTiming.timed(Duration(minutes: 2)),
    packIdentity: null,
    protocolId: 'standard',
    protocolVersion: '1',
    protocolLimitsIdentity: 'standard',
  );
  await db
      .into(db.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: id,
          ownerId: owner,
          activityType: 'matching',
          state: 'active',
          startedAtUtcMs: at.millisecondsSinceEpoch,
          appVersion: appVersion,
          buildId: buildId,
          sessionConfigurationIdentity: Value(config.contentIdentity),
          sessionConfigurationJson: Value(config.stableSerialization),
        ),
      );
  final operation = PairMatchingStartOperation(
    plan: plan,
    launchOperationId: operationId,
    appVersion: appVersion,
    buildId: buildId,
    configuration: config,
  );
  final key = PairMatchingSessionPurpose.checkpointKey(owner, id, 1);
  await db
      .into(db.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: key,
          eventType: 'LearningActivityCheckpoint',
          eventVersion: 1,
          occurredAtUtc: at,
          recordedAtUtc: at,
          actorIdentity: owner,
          ownerId: owner,
          aggregateType: 'LearningSession',
          aggregateId: id,
          idempotencyKey: key,
          consentContextJson: jsonEncode({
            'researchConsentVersion': 0,
            'aiConsentGranted': false,
            'voiceConsentGranted': false,
            'socialConsentGranted': false,
          }),
          appVersion: appVersion,
          buildId: buildId,
          privacyClassification: 'ownerOnly',
          payloadJson: jsonEncode({
            'schemaVersion': 1,
            'activityType': 'matching',
            'sessionId': id,
            'revision': 1,
            'state': operation.initialCheckpoint.state,
          }),
        ),
      );
  return id;
}
