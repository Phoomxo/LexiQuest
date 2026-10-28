import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'motivation_instrument.dart';
import 'motivation_study_protocol.dart';

const motivationScoringRuleVersion = 'normalized-score-v1';

enum MotivationMeasurementRunState {
  started,
  completed,
  skipped,
  abandoned,
  withdrawn,
}

enum ResearchCaptureReason {
  eligible,
  noPermit,
  invalidPermit,
  expiredPermit,
  revokedPermit,
  noActiveRun,
  withdrawn,
  versionConflict,
  ownerConflict,
  outsideWindow,
  incomplete,
  identityConflict,
  sessionUnavailable,
  timingUnavailable,
  invalidInput,
}

final class ResearchCaptureDenied implements Exception {
  const ResearchCaptureDenied(this.reason);
  final ResearchCaptureReason reason;
}

final class MotivationMeasurementStart {
  const MotivationMeasurementStart({
    required this.ownerId,
    required this.permitId,
  });
  final String ownerId;
  final String permitId;
}

final class MotivationResponse {
  const MotivationResponse({
    required this.ownerId,
    required this.runId,
    required this.itemId,
    required this.responseCode,
  });
  final String ownerId;
  final String runId;
  final String itemId;
  final String responseCode;
}

/// Completed is accepted only as a replay of an already completed run.
final class MotivationMeasurementClose {
  const MotivationMeasurementClose({
    required this.ownerId,
    required this.runId,
    required this.state,
  });
  final String ownerId;
  final String runId;
  final MotivationMeasurementRunState state;
}

final class RecordedMotivationResponse {
  const RecordedMotivationResponse({
    required this.id,
    required this.itemId,
    required this.responseCode,
    required this.ordinalValue,
    required this.answeredAtUtc,
    required this.localRevision,
  });
  final String id;
  final String itemId;
  final String responseCode;
  final int ordinalValue;
  final DateTime answeredAtUtc;
  final int localRevision;
}

enum MotivationIndexSessionState { active, completed, abandoned }

final class MotivationIndexSession {
  const MotivationIndexSession({
    required this.id,
    required this.startedAtUtc,
    required this.state,
    this.completedAtUtc,
  });
  final String id;
  final DateTime startedAtUtc;
  final MotivationIndexSessionState state;
  final DateTime? completedAtUtc;
}

sealed class MotivationTimingFacts {
  const MotivationTimingFacts({
    required this.ownerId,
    required this.runId,
    required this.permitId,
    required this.assignmentId,
  });
  final String ownerId;
  final String runId;
  final String permitId;
  final String assignmentId;
}

/// Positive evidence that no committed first exposure exists for this cycle.
final class MotivationBeforeExposure extends MotivationTimingFacts {
  const MotivationBeforeExposure({
    required super.ownerId,
    required super.runId,
    required super.permitId,
    required super.assignmentId,
  });
}

final class MotivationAfterExposure extends MotivationTimingFacts {
  const MotivationAfterExposure({
    required super.ownerId,
    required super.runId,
    required super.permitId,
    required super.assignmentId,
    required this.firstExposureEventId,
    required this.firstExposureAtUtc,
    this.indexSession,
  });
  final String firstExposureEventId;
  final DateTime firstExposureAtUtc;
  final MotivationIndexSession? indexSession;
}

abstract interface class MotivationMeasurementTimingReader {
  /// Reads committed same-database cycle facts. Null means unavailable or
  /// inconsistent, never proof of no exposure. The first index is immutable.
  Future<MotivationTimingFacts?> read({
    required String ownerId,
    required String runId,
    required String permitId,
    required String assignmentId,
  });
}

/// Historical facts, not continuing permission to collect another response.
final class MotivationMeasurementRun {
  MotivationMeasurementRun({
    required this.id,
    required this.ownerId,
    required this.permitId,
    required this.permitPayloadSha256,
    required this.assignmentId,
    required this.assignmentRevision,
    required this.protocolRevision,
    required this.instrumentRevision,
    required this.consentVersion,
    required this.treatment,
    required this.consentDecidedAtUtc,
    required this.study,
    required this.databaseSchemaVersion,
    required this.state,
    required this.startedAtUtc,
    required this.localRevision,
    required List<RecordedMotivationResponse> responses,
    this.closedAtUtc,
    this.timing,
  }) : responses = List.unmodifiable(responses);

  final String id;
  final String ownerId;
  final String permitId;
  final String permitPayloadSha256;
  final String assignmentId;
  final int assignmentRevision;
  final int protocolRevision;
  final int instrumentRevision;
  final int consentVersion;
  final String treatment;
  final DateTime consentDecidedAtUtc;
  final MotivationStudyProtocol study;
  final int databaseSchemaVersion;
  final MotivationMeasurementRunState state;
  final DateTime startedAtUtc;
  final DateTime? closedAtUtc;
  final int localRevision;
  final List<RecordedMotivationResponse> responses;
  final MotivationTimingFacts? timing;

  MotivationInstrument get instrument => study.instrument;
  DateTime? get firstExposureAtUtc => switch (timing) {
    MotivationAfterExposure facts => facts.firstExposureAtUtc,
    _ => null,
  };
  DateTime? get indexCompletionAtUtc {
    final facts = timing;
    if (facts is! MotivationAfterExposure) return null;
    final session = facts.indexSession;
    return session?.state == MotivationIndexSessionState.completed
        ? session?.completedAtUtc
        : null;
  }

  double? score(MotivationTimepoint point) => instrument.normalizedScore(
    point,
    {for (final response in responses) response.itemId: response.responseCode},
  );

  bool get primaryAnalysisEligible {
    final exposure = firstExposureAtUtc;
    final completion = indexCompletionAtUtc;
    if (state != MotivationMeasurementRunState.completed ||
        exposure == null ||
        completion == null ||
        score(MotivationTimepoint.baseline) == null ||
        score(MotivationTimepoint.post) == null) {
      return false;
    }
    return responses.every((response) {
      final point = instrument.item(response.itemId).timepoint;
      return point == MotivationTimepoint.baseline
          ? !response.answeredAtUtc.isAfter(exposure) &&
                !response.answeredAtUtc.isBefore(
                  exposure.subtract(const Duration(hours: 24)),
                )
          : !response.answeredAtUtc.isBefore(completion) &&
                !response.answeredAtUtc.isAfter(
                  completion.add(const Duration(minutes: 30)),
                );
    });
  }
}

String motivationMeasurementRunId({
  required String ownerId,
  required String permitId,
  required String protocolId,
  required String protocolVersion,
  required String instrumentChecksumSha256,
}) =>
    'motivation:${sha256.convert(utf8.encode(jsonEncode([ownerId, permitId, protocolId, protocolVersion, instrumentChecksumSha256])))}';

String motivationResponseId({required String runId, required String itemId}) =>
    'response:${sha256.convert(utf8.encode(jsonEncode([runId, itemId])))}';
