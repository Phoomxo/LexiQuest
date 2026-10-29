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
const measurementPresentationChangedEventType =
    'TodayExperiencePresentationChanged';
const measurementPresentationChangedEventVersion = 1;

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
    this.lastSwitchOrdinal = 0,
    this.suppressedSwitchCount = 0,
    this.startedEffectivePresentation,
    this.pendingPresentationChange,
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
  final int lastSwitchOrdinal;
  final int suppressedSwitchCount;
  final TodayExperiencePresentation? startedEffectivePresentation;
  final PendingPresentationChange? pendingPresentationChange;
  int get totalSwitches {
    validatePresentationCounters(lastSwitchOrdinal, suppressedSwitchCount);
    return lastSwitchOrdinal + suppressedSwitchCount;
  }

  TodayExperiencePresentation get currentPresentation => totalSwitches.isEven
      ? effectivePresentation
      : oppositePresentation(effectivePresentation);
}

TodayExperiencePresentation oppositePresentation(
  TodayExperiencePresentation value,
) => value == TodayExperiencePresentation.standard
    ? TodayExperiencePresentation.adventure
    : TodayExperiencePresentation.standard;

final class PendingPresentationChange {
  PendingPresentationChange({
    required this.attemptId,
    required this.ownerId,
    required this.opportunityId,
    required this.entryAttemptId,
    required this.from,
    required this.to,
    required this.baseRevision,
    required this.baseOrdinal,
    required this.baseSuppressed,
    required this.preparedAtUtc,
  }) {
    requireMeasurementEntryId(attemptId);
    requireMeasurementEntryId(entryAttemptId);
    requireResearchCode(ownerId);
    requireResearchCode(opportunityId);
    requireResearchUtc(preparedAtUtc);
    validatePresentationCounters(baseOrdinal, baseSuppressed);
    if (baseRevision < 1 ||
        baseRevision > 0x7fffffffffffffff - 2 ||
        from == to) {
      throw const FormatException('Invalid presentation change');
    }
  }
  final String attemptId;
  final String ownerId;
  final String opportunityId;
  final String entryAttemptId;
  final TodayExperiencePresentation from;
  final TodayExperiencePresentation to;
  final int baseRevision;
  final int baseOrdinal;
  final int baseSuppressed;
  final DateTime preparedAtUtc;
  int get position => baseOrdinal + baseSuppressed + 1;
  Map<String, Object> toJson() => {
    'version': 1,
    'attemptId': attemptId,
    'ownerId': ownerId,
    'opportunityId': opportunityId,
    'entryAttemptId': entryAttemptId,
    'from': from.wireName,
    'to': to.wireName,
    'baseRevision': baseRevision,
    'baseOrdinal': baseOrdinal,
    'baseSuppressed': baseSuppressed,
    'preparedAtUtcMs': preparedAtUtc.millisecondsSinceEpoch,
  };
  String get canonicalJson => jsonEncode(toJson());
  factory PendingPresentationChange.fromJson(String source) {
    if (source.length > 2048 || utf8.encode(source).length > 2048) {
      throw const FormatException('Unbounded presentation change');
    }
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid presentation change');
    }
    final result = PendingPresentationChange(
      attemptId: value['attemptId'] as String,
      ownerId: value['ownerId'] as String,
      opportunityId: value['opportunityId'] as String,
      entryAttemptId: value['entryAttemptId'] as String,
      from: TodayExperiencePresentationCodec.decode(value['from']),
      to: TodayExperiencePresentationCodec.decode(value['to']),
      baseRevision: value['baseRevision'] as int,
      baseOrdinal: value['baseOrdinal'] as int,
      baseSuppressed: value['baseSuppressed'] as int,
      preparedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        value['preparedAtUtcMs'] as int,
        isUtc: true,
      ),
    );
    if (source != result.canonicalJson) {
      throw const FormatException('Noncanonical presentation change');
    }
    return result;
  }
}

void validatePresentationCounters(int ordinal, int suppressed) {
  if (ordinal < 0 ||
      ordinal > 10 ||
      suppressed < 0 ||
      (suppressed > 0 && ordinal != 10) ||
      suppressed > 0x7fffffffffffffff - 11) {
    throw const FormatException('Invalid presentation counters');
  }
}

String measurementPresentationChangedIdentity(
  String opportunityId,
  int ordinal,
) {
  requireResearchCode(opportunityId);
  if (ordinal < 1 || ordinal > 10) {
    throw const FormatException('Invalid switch ordinal');
  }
  return 'research:${sha256.convert(utf8.encode(jsonEncode([opportunityId, measurementPresentationChangedEventType, ordinal])))}';
}

void validateMeasurementPresentationChangedPayload(
  Map<String, Object?> payload,
) {
  const keys = {
    'assignedTreatment',
    'effectivePresentation',
    'fromPresentation',
    'switchOrdinal',
  };
  final assigned = TodayExperiencePresentationCodec.tryDecode(
    payload['assignedTreatment'],
  );
  final from = TodayExperiencePresentationCodec.tryDecode(
    payload['fromPresentation'],
  );
  final to = TodayExperiencePresentationCodec.tryDecode(
    payload['effectivePresentation'],
  );
  final ordinal = payload['switchOrdinal'];
  if (payload.length != keys.length ||
      !payload.keys.every(keys.contains) ||
      assigned == null ||
      from == null ||
      to == null ||
      from == to ||
      ordinal is! int ||
      ordinal < 1 ||
      ordinal > 10) {
    throw const FormatException('Invalid PresentationChanged payload');
  }
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
