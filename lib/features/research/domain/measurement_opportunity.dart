import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../adventure/domain/adventure_entry.dart';
import 'motivation_study_protocol.dart';
import 'research_event_identity.dart';

const measurementPresentedEventType = 'TodayExperiencePresented';
const measurementPresentedEventVersion = 1;
const measurementMissionStartedEventType = 'TodayExperienceMissionStarted';
const measurementMissionCompletedEventType = 'TodayExperienceMissionCompleted';
const measurementMissionEventVersion = 1;

final class MeasurementPresentationFact {
  const MeasurementPresentationFact({
    required this.eventId,
    required this.occurredAtUtc,
  });
  final String eventId;
  final DateTime occurredAtUtc;
}

final class MeasurementIndexLink {
  const MeasurementIndexLink({
    required this.sessionId,
    required this.startedAtUtc,
  });
  final String sessionId;
  final DateTime startedAtUtc;
}

final class MeasurementOpportunity {
  const MeasurementOpportunity({
    required this.id,
    required this.ownerId,
    required this.measurementRunId,
    required this.permitId,
    required this.entryAttemptId,
    required this.assignedTreatment,
    required this.effectivePresentation,
    required this.openedAtUtc,
    required this.localRevision,
    this.presentation,
    this.indexLink,
    this.closedAtUtc,
  });
  final String id;
  final String ownerId;
  final String measurementRunId;
  final String permitId;
  final String entryAttemptId;
  final TodayExperiencePresentation assignedTreatment;
  final TodayExperiencePresentation effectivePresentation;
  final DateTime openedAtUtc;
  final int localRevision;
  final MeasurementPresentationFact? presentation;
  final MeasurementIndexLink? indexLink;
  final DateTime? closedAtUtc;
}

void requireMeasurementEntryId(String entryAttemptId) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(entryAttemptId)) {
    throw const FormatException('Expected entry UUID v4');
  }
}

String measurementOpportunityId({
  required String ownerId,
  required String measurementRunId,
  required String permitId,
  required String entryAttemptId,
}) =>
    'opportunity:${sha256.convert(utf8.encode(jsonEncode([ownerId, measurementRunId, permitId, entryAttemptId])))}';

String measurementPresentedIdentity(String opportunityId) =>
    researchEventIdentity(opportunityId, measurementPresentedEventType);

void validateMeasurementPresentedPayload(Map<String, Object?> payload) {
  const keys = {
    'assignedTreatment',
    'effectivePresentation',
    'entryAttemptId',
    'catalogVersion',
  };
  if (payload.length != keys.length ||
      !payload.keys.every(keys.contains) ||
      TodayExperiencePresentationCodec.tryDecode(
            payload['assignedTreatment'],
          ) ==
          null ||
      TodayExperiencePresentationCodec.tryDecode(
            payload['effectivePresentation'],
          ) ==
          null ||
      payload['entryAttemptId'] is! String ||
      payload['catalogVersion'] is! String) {
    throw const FormatException('Invalid Presented payload');
  }
  requireMeasurementEntryId(payload['entryAttemptId']! as String);
  requireResearchCode(payload['catalogVersion']! as String);
}

String measurementMissionIdentity(String opportunityId, String eventType) {
  if (eventType != measurementMissionStartedEventType &&
      eventType != measurementMissionCompletedEventType) {
    throw const FormatException('Expected a Mission event type');
  }
  return researchEventIdentity(opportunityId, eventType);
}

void validateMeasurementMissionStartedPayload(Map<String, Object?> payload) {
  _validateMissionPayload(payload, 'mode');
  if (payload['mode'] != 'meaning-quiz') {
    throw const FormatException('Expected the accepted meaning-quiz mode');
  }
}

void validateMeasurementMissionCompletedPayload(Map<String, Object?> payload) {
  _validateMissionPayload(payload, 'terminalState');
  if (payload['terminalState'] != 'completed') {
    throw const FormatException('Expected canonical completed state');
  }
}

void _validateMissionPayload(Map<String, Object?> payload, String field) {
  final keys = {
    'assignedTreatment',
    'effectivePresentation',
    'opportunityId',
    'planId',
    field,
  };
  if (payload.length != keys.length ||
      !payload.keys.every(keys.contains) ||
      TodayExperiencePresentationCodec.tryDecode(
            payload['assignedTreatment'],
          ) ==
          null ||
      TodayExperiencePresentationCodec.tryDecode(
            payload['effectivePresentation'],
          ) ==
          null ||
      payload['opportunityId'] is! String ||
      payload['planId'] is! String ||
      !RegExp(
        r'^opportunity:[0-9a-f]{64}$',
      ).hasMatch(payload['opportunityId']! as String) ||
      !RegExp(
        r'^quiz-plan:[0-9a-f]{64}$',
      ).hasMatch(payload['planId']! as String)) {
    throw const FormatException('Invalid Mission payload');
  }
}
